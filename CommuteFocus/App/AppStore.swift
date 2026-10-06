import SwiftUI
import SwiftData
import Network

@MainActor
final class AppStore: ObservableObject {
    @Published var tasks: [WorkTask] = []
    @Published var steps: [WorkStep] = []
    @Published var journeys: [Journey] = []
    @Published var logs: [FocusLog] = []
    @Published var preferences = Preferences()
    @Published var active: ActiveCommute?
    @Published var now = Date()
    @Published var error: String?
    @Published var syncStatus = "本机模式"
    @Published var notificationDenied = false
    @Published var syncing = false
    let auth: AuthService
    let local: LocalStore
    let notifications = NotificationService()
    private let network = NWPathMonitor()
    private var tickTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var notificationVersion = 0
    private var syncTask: Task<Void, Never>?
    private var syncAgain = false
    private var loadedOwner: String
    let deviceID: String
    var owner: String { loadedOwner }
    var activeKey: String { "commute.active.\(owner)" }

    init(context: ModelContext, auth: AuthService) {
        self.auth = auth
        local = LocalStore(context: context)
        loadedOwner = auth.owner
        let id = UserDefaults.standard.string(forKey: "deviceID") ?? UUID().uuidString
        deviceID = id
        UserDefaults.standard.set(id, forKey: "deviceID")
        reload()
        restoreActive()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
        network.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in self?.requestSync() } }
        }
        network.start(queue: DispatchQueue(label: "commute.network"))
        requestSync()
    }

    func reload() {
        do {
            tasks = try local.values(WorkTask.self, kind: .task, owner: owner).sorted {
                $0.order == $1.order ? $0.createdAt < $1.createdAt : $0.order < $1.order
            }
            let taskIDs = Set(tasks.map(\.id))
            steps = try local.values(WorkStep.self, kind: .step, owner: owner).filter { taskIDs.contains($0.taskID) }
            journeys = try local.values(Journey.self, kind: .journey, owner: owner).sorted { $0.startedAt > $1.startedAt }
            logs = try local.values(FocusLog.self, kind: .focus, owner: owner).sorted { $0.startedAt > $1.startedAt }
            preferences = try local.values(Preferences.self, kind: .preferences, owner: owner).first ?? Preferences()
        } catch { self.error = "读取本机数据失败：\(error.localizedDescription)" }
    }

    func perform(_ operation: () throws -> Void) {
        do { try local.transaction(operation); reload(); requestSync() }
        catch { self.error = "保存失败：\(error.localizedDescription)"; reload() }
    }
    func saveTask(_ task: WorkTask) { perform { try local.put(task, id: task.id, kind: .task, owner: owner) } }
    func saveStep(_ step: WorkStep) { perform { try local.put(step, id: step.id, kind: .step, owner: owner) } }
    func orderedSteps(_ taskID: UUID) -> [WorkStep] {
        steps.filter { $0.taskID == taskID }.sorted { $0.order < $1.order }
    }
    func deleteTask(_ task: WorkTask) {
        guard active?.timer?.segment.taskID != task.id else { return }
        perform {
            for step in orderedSteps(task.id) { try local.delete(id: step.id, owner: owner) }
            try local.delete(id: task.id, owner: owner)
        }
    }
    func deleteStep(_ step: WorkStep) {
        guard active?.timer?.segment.taskID != step.taskID else { return }
        perform { try local.delete(id: step.id, owner: owner) }
    }
    func moveTasks(from: IndexSet, to: Int) {
        var reordered = tasks
        reordered.move(fromOffsets: from, toOffset: to)
        perform {
            for (i, var task) in reordered.enumerated() {
                task.order = i
                try local.put(task, id: task.id, kind: .task, owner: owner)
            }
        }
    }
    func moveSteps(taskID: UUID, from: IndexSet, to: Int) {
        var reordered = orderedSteps(taskID)
        reordered.move(fromOffsets: from, toOffset: to)
        perform {
            for (i, var step) in reordered.enumerated() {
                step.order = i
                try local.put(step, id: step.id, kind: .step, owner: owner)
            }
        }
    }
    func savePreferences(_ value: Preferences) {
        perform { try local.put(value, id: Preferences.recordID, kind: .preferences, owner: owner) }
        refreshNotifications()
    }

    func preview(minutes: Int) -> Plan {
        Planner.make(tasks: tasks, steps: steps, availableSeconds: (minutes - preferences.bufferMinutes) * 60)
    }
    var remainingPlan: Plan {
        guard let active else { return Plan(segments: [], reasons: []) }
        return Planner.make(tasks: tasks, steps: steps,
            availableSeconds: Int(active.cutoff.timeIntervalSince(now)), excluding: active.skippedTaskIDs)
    }
    var projectedNext: FocusSegment? {
        guard let active, let timer = active.timer else { return nil }
        var projectedSteps = steps
        for allocation in timer.segment.allocations {
            guard let index = projectedSteps.firstIndex(where: { $0.id == allocation.stepID }) else { continue }
            projectedSteps[index].remainingSeconds = max(0, projectedSteps[index].remainingSeconds - allocation.seconds)
            projectedSteps[index].completed = projectedSteps[index].remainingSeconds == 0
        }
        let available = Int(active.cutoff.timeIntervalSince(now)) - timer.remaining(at: now)
        return Planner.make(tasks: tasks, steps: projectedSteps, availableSeconds: available,
                            excluding: active.skippedTaskIDs).segments.first
    }
    func startCommute(minutes: Int, direction: String) {
        guard active == nil else { return }
        let date = Date()
        let journey = Journey(deviceID: deviceID, startedAt: date,
            arrivalAt: date.addingTimeInterval(Double(minutes * 60)), direction: direction)
        do {
            try local.put(journey, id: journey.id, kind: .journey, owner: owner)
            var commute = ActiveCommute(journey: journey, bufferMinutes: preferences.bufferMinutes)
            if let first = preview(minutes: minutes).segments.first {
                commute.timer = FocusTimer(segment: first, now: date, cutoff: commute.cutoff)
            }
            active = commute
            now = date
            saveActive()
            refreshNotifications()
            reload()
            requestSync()
        } catch { self.error = error.localizedDescription }
    }

    func startNext() {
        now = Date()
        guard var commute = active, commute.timer == nil,
              let segment = remainingPlan.segments.first else { return }
        commute.timer = FocusTimer(segment: segment, now: now, cutoff: commute.cutoff)
        active = commute
        saveActive()
        refreshNotifications()
    }
    func pause() {
        active?.timer?.pause(now: Date())
        saveActive()
        refreshNotifications()
    }
    func resume() {
        guard let cutoff = active?.cutoff else { return }
        active?.timer?.resume(now: Date(), cutoff: cutoff)
        saveActive()
        refreshNotifications()
    }
    func requestConfirmation() {
        active?.timer?.requestConfirmation(now: Date())
        saveActive()
        refreshNotifications()
    }
    func extendCommute(minutes: Int) {
        guard var commute = active else { return }
        commute.journey.arrivalAt = commute.journey.arrivalAt.addingTimeInterval(Double(minutes * 60))
        do {
            try local.put(commute.journey, id: commute.journey.id, kind: .journey, owner: owner)
            active = commute
            saveActive()
            refreshNotifications()
            requestSync()
        } catch { self.error = error.localizedDescription }
    }

    /// Commit progress and its log atomically before clearing the local timer.
    /// A restored timer whose log exists is cleared without replaying progress.
    @discardableResult
    func settle(completed: Set<UUID>, estimates: [UUID: Int] = [:], outcome: String) -> Bool {
        guard let commute = active, let timer = commute.timer else { return true }
        do {
            let existing = try local.values(FocusLog.self, kind: .focus, owner: owner)
            if !existing.contains(where: { $0.id == timer.segment.id }) {
                let elapsed = timer.elapsed(at: Date())
                var seconds = elapsed
                var priorComplete = true
                var actualCompleted: [UUID] = []
                try local.transaction {
                    for allocation in timer.segment.allocations {
                        let spent = min(seconds, allocation.seconds)
                        seconds -= spent
                        guard var step = steps.first(where: { $0.id == allocation.stepID }) else { continue }
                        step.remainingSeconds = max(0, step.remainingSeconds - spent)
                        if completed.contains(step.id) && priorComplete {
                            step.completed = true
                            step.remainingSeconds = 0
                            actualCompleted.append(step.id)
                        } else {
                            priorComplete = false
                            if let estimate = estimates[step.id] { step.remainingSeconds = max(1, estimate) * 60 }
                        }
                        try local.put(step, id: step.id, kind: .step, owner: owner)
                    }
                    let log = FocusLog(id: timer.segment.id, journeyID: commute.journey.id,
                        taskID: timer.segment.taskID, taskTitle: timer.segment.taskTitle,
                        startedAt: timer.startedAt, seconds: elapsed, completedStepIDs: actualCompleted, outcome: outcome)
                    try local.put(log, id: log.id, kind: .focus, owner: owner)
                }
            }
            active?.timer = nil
            if outcome == "跳过" { active?.skippedTaskIDs.insert(timer.segment.taskID) }
            saveActive()
            reload()
            refreshNotifications()
            requestSync()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func endCommute() {
        guard var commute = active else { return }
        guard settle(completed: [], outcome: "结束通勤") else { return }
        commute.journey.endedAt = Date()
        do {
            try local.put(commute.journey, id: commute.journey.id, kind: .journey, owner: owner)
            active = nil
            saveActive()
            refreshNotifications()
            reload()
            requestSync()
        } catch { self.error = error.localizedDescription }
    }

    func tick() {
        now = Date()
        guard var commute = active else { return }
        let old = commute.timer?.phase
        commute.timer?.reconcile(now: now, cutoff: commute.cutoff)
        if old != commute.timer?.phase {
            active = commute
            saveActive()
            // Keep the already-delivered completion banner; cancel stale pending requests.
            refreshNotifications()
        }
    }
    func saveActive() {
        if let active {
            do { UserDefaults.standard.set(try JSONEncoder().encode(active), forKey: activeKey) }
            catch { self.error = "计时状态保存失败：\(error.localizedDescription)" }
        } else { UserDefaults.standard.removeObject(forKey: activeKey) }
    }
    func restoreActive() {
        active = nil
        if let data = UserDefaults.standard.data(forKey: activeKey) {
            do {
                let restored = try JSONDecoder().decode(ActiveCommute.self, from: data)
                if restored.journey.deviceID == deviceID { active = restored }
                if let timer = active?.timer, logs.contains(where: { $0.id == timer.segment.id }) {
                    active?.timer = nil
                    saveActive()
                }
                if let id = active?.journey.id, journeys.contains(where: { $0.id == id && $0.endedAt != nil }) {
                    active = nil
                    saveActive()
                }
            } catch { self.error = "上次计时状态无法读取，任务和历史记录仍保留。" }
        }
        tick()
        refreshNotifications()
    }
    func refreshNotifications() {
        notificationVersion += 1
        let version = notificationVersion
        let previous = notificationTask
        notificationTask = Task { [weak self] in
            await previous?.value
            guard let self, self.notificationVersion == version else { return }
            do { try await self.notifications.schedule(active: self.active, enabled: self.preferences.reminders) }
            catch { self.error = "提醒安排失败：\(error.localizedDescription)" }
            self.notificationDenied = await self.notifications.denied()
        }
    }
    func foreground() {
        tick()
        refreshNotifications()
        requestSync()
    }
    func changeOwner() {
        guard loadedOwner != auth.owner else { return }
        // UI prevents account changes while a commute is active.
        notifications.cancel()
        loadedOwner = auth.owner
        reload()
        restoreActive()
        requestSync()
    }

    func requestSync() {
        guard owner != "local" else { syncStatus = "本机模式 · 登录后使用独立云端空间"; return }
        guard CloudConfiguration.current != nil else { syncStatus = "云服务未配置"; return }
        if syncing { syncAgain = true; return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.synchronize()
        }
    }
    private func synchronize() async {
        guard !syncing else { syncAgain = true; return }
        syncing = true
        let syncOwner = owner
        syncStatus = "正在同步…"
        defer {
            syncing = false
            if syncAgain { syncAgain = false; requestSync() }
        }
        do {
            let token = try await auth.token()
            guard owner == syncOwner else { return }
            let uploads = try local.pending(owner: syncOwner)
            // Bound request sizes and retain newer in-flight edits in the outbox.
            for offset in stride(from: 0, to: uploads.count, by: 100) {
                let batch = Array(uploads[offset..<min(offset + 100, uploads.count)])
                let body = try JSONEncoder().encode(["changes": batch])
                let data = try await CloudAPI.shared.request(path: "/rest/v1/rpc/apply_changes", body: body, token: token)
                let rows = try JSONDecoder().decode([RemoteRecord].self, from: data)
                try local.merge(rows, owner: syncOwner,
                    acknowledgements: Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0.mutation_id) }))
            }
            var offset = 0
            while true {
                let data = try await CloudAPI.shared.request(
                    path: "/rest/v1/records?select=id,kind,payload,deleted,revision,mutation_id&order=id&limit=500&offset=\(offset)",
                    method: "GET", token: token)
                let rows = try JSONDecoder().decode([RemoteRecord].self, from: data)
                try local.merge(rows, owner: syncOwner)
                if rows.count < 500 { break }
                offset += rows.count
            }
            guard owner == syncOwner else { return }
            reload()
            let pending = try local.pending(owner: syncOwner).count
            syncStatus = pending == 0 ? "已同步 · \(Date().formatted(date: .omitted, time: .shortened))" : "有 \(pending) 项待同步"
            if pending > 0 { syncAgain = true }
        } catch {
            if owner == syncOwner { syncStatus = "待同步 · \(error.localizedDescription)" }
        }
    }
}
