import SwiftUI

struct CommuteView: View {
    @EnvironmentObject private var store: AppStore
    @State private var direction = "去程"
    @State private var minutes = 60
    @State private var preview = false
    @State private var endConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let active = store.active {
                    activeContent(active)
                } else {
                    Text("让路上的时间，\n推进一件重要的小事。")
                        .font(.largeTitle.bold()).padding(.top, 8)
                    Text("不必填满每一分钟，从一段专注开始。")
                        .foregroundStyle(.secondary)
                    Panel {
                        Picker("通勤方向", selection: $direction) {
                            Text("去程").tag("去程")
                            Text("返程").tag("返程")
                        }.pickerStyle(.segmented)
                        Stepper(value: $minutes, in: 10...360, step: 5) {
                            Text("\(minutes)").font(.system(size: 48, weight: .semibold, design: .rounded))
                            + Text(" 分钟").font(.title3)
                        }
                        Text("预留 \(store.preferences.bufferMinutes) 分钟到站收尾")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { preview = true } label: {
                            Label("安排这次通勤", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }.primaryAction()
                    }
                    Panel {
                        Label("从你的任务清单中安排", systemImage: "checklist").font(.headline)
                        Text("\(store.steps.filter { !$0.completed }.count) 个待完成步骤")
                        Text("先按优先级选择，再按步骤顺序分成 10–30 分钟的专注段。")
                            .foregroundStyle(.secondary)
                    }
                }
                if store.notificationDenied {
                    Panel {
                        Label("锁屏提醒尚未开启", systemImage: "bell.slash")
                        Text("前台计时仍可使用。若需要锁屏提醒，请在系统设置中允许通知。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("打开系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }.padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("通勤专注")
        .onAppear { loadDuration() }
        .onChange(of: direction) { _, _ in loadDuration() }
        .sheet(isPresented: $preview) { PlanPreview(minutes: minutes, direction: direction) }
        .confirmationDialog("结束本次通勤？已投入时间会保存，任务不会自动完成。", isPresented: $endConfirmation, titleVisibility: .visible) {
            Button("保存并结束", role: .destructive) { store.endCommute() }
        }
    }
    private func loadDuration() {
        minutes = direction == "去程" ? store.preferences.outboundMinutes : store.preferences.inboundMinutes
    }
    @ViewBuilder private func activeContent(_ active: ActiveCommute) -> some View {
        HStack {
            Label(active.journey.direction, systemImage: "tram.fill")
            Spacer()
            Text("预计 \(active.journey.arrivalAt.formatted(date: .omitted, time: .shortened)) 到站")
        }.font(.subheadline).foregroundStyle(.secondary)
        if let timer = active.timer {
            if timer.phase == .awaitingConfirmation {
                CompletionPanel(timer: timer).id(timer.segment.id)
            } else {
                Panel {
                    Text(timer.phase == .paused ? "已暂停 · 到站时间不变" : "正在专注")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.teal)
                    Text(timer.segment.taskTitle).font(.title2.bold())
                    ForEach(timer.segment.allocations) { allocation in
                        Text(allocation.title).font(.title3)
                    }
                    Text(clockText(timer.remaining(at: store.now)))
                        .font(.system(size: 68, weight: .medium, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .accessibilityLabel("剩余 \(timer.remaining(at: store.now) / 60) 分钟")
                    ProgressView(value: Double(timer.elapsed(at: store.now)), total: Double(timer.segment.seconds))
                    Button(timer.phase == .paused ? "继续专注" : "换乘，暂停一下") {
                        if timer.phase == .paused { store.resume() } else { store.pause() }
                    }.primaryAction().frame(maxWidth: .infinity)
                    HStack {
                        Button("提前完成") { store.requestConfirmation() }
                        Spacer()
                        Button("跳过本任务") { store.settle(completed: [], outcome: "跳过") }
                    }.buttonStyle(.bordered)
                    if let next = store.projectedNext {
                        Divider()
                        Text("预计下一段 · \(next.minutes) 分钟").font(.caption).foregroundStyle(.secondary)
                        Text(next.allocations.map(\.title).joined(separator: " → ")).font(.subheadline)
                        Text("确认本段进度后再安排，不会自动开始。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Panel {
                Text(store.now >= active.cutoff ? "准备到站，收好今天的进展" : "歇一会儿，再决定下一步")
                    .font(.title2.bold())
                if let next = store.remainingPlan.segments.first {
                    Text("下一段 · \(next.minutes) 分钟").foregroundStyle(.teal)
                    Text(next.taskTitle).font(.headline)
                    Text(next.allocations.map(\.title).joined(separator: " → "))
                    Button("开始下一段") { store.startNext() }.primaryAction()
                } else {
                    ForEach(store.remainingPlan.reasons, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
            }
        }
        HStack {
            Button("通勤延长 10 分钟") { store.extendCommute(minutes: 10) }
            Spacer()
            Button("结束通勤", role: .destructive) { endConfirmation = true }
        }.font(.subheadline).padding(.vertical, 8)
    }
}

struct PlanPreview: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let minutes: Int
    let direction: String
    @State private var starting = false
    var plan: Plan { store.preview(minutes: minutes) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("单程时长", value: "\(minutes) 分钟")
                    LabeledContent("预计专注", value: "\(plan.totalSeconds / 60) 分钟")
                    LabeledContent("到站收尾", value: "\(store.preferences.bufferMinutes) 分钟")
                    LabeledContent("预计到站", value: Date().addingTimeInterval(Double(minutes * 60)).formatted(date: .omitted, time: .shortened))
                }
                Section("专注安排") {
                    ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index + 1). \(segment.taskTitle) · \(segment.minutes) 分钟").font(.headline)
                            Text(segment.allocations.map(\.title).joined(separator: " → "))
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                    ForEach(plan.reasons, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
                Section {
                    Text("这是预估顺序。每段结束后需确认进度，再根据剩余通勤时间重新安排。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(starting ? "正在准备…" : "确认，开始通勤") {
                        starting = true
                        Task {
                            if store.preferences.reminders { _ = await store.notifications.requestPermission() }
                            store.startCommute(minutes: minutes, direction: direction)
                            starting = false
                            dismiss()
                        }
                    }.primaryAction().disabled(plan.segments.isEmpty || starting)
                }
            }
            .navigationTitle("这次通勤的计划")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } }
            .interactiveDismissDisabled(starting)
        }
    }
}

struct CompletionPanel: View {
    @EnvironmentObject private var store: AppStore
    let timer: FocusTimer
    @State private var completed: Set<UUID> = []
    @State private var estimates: [UUID: Int] = [:]
    var body: some View {
        Panel {
            Label("这一段，辛苦了", systemImage: "leaf.fill").font(.title2.bold()).foregroundStyle(.teal)
            Text("投入 \(clockText(timer.accumulatedSeconds)) · 请确认实际进度")
                .foregroundStyle(.secondary)
            ForEach(Array(timer.segment.allocations.enumerated()), id: \.element.id) { index, allocation in
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(allocation.title + " · 已完成", isOn: Binding(
                        get: { completed.contains(allocation.stepID) },
                        set: { selected in
                            if selected { completed.insert(allocation.stepID) }
                            else {
                                for later in timer.segment.allocations[index...] { completed.remove(later.stepID) }
                            }
                        }))
                        .disabled(index > 0 && !completed.contains(timer.segment.allocations[index - 1].stepID))
                    if !completed.contains(allocation.stepID) {
                        Stepper("仍需约 \(estimates[allocation.stepID] ?? defaultEstimate(allocation)) 分钟",
                            value: Binding(get: { estimates[allocation.stepID] ?? defaultEstimate(allocation) },
                                           set: { estimates[allocation.stepID] = $0 }), in: 1...1440)
                            .font(.subheadline)
                    }
                }.padding(.vertical, 6)
            }
            Text("未勾选的步骤会保留。预计时间用完但尚未完成时，请重新估算剩余时间。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("保存进度") {
                var values = estimates
                for item in timer.segment.allocations where !completed.contains(item.stepID) && values[item.stepID] == nil {
                    values[item.stepID] = defaultEstimate(item)
                }
                store.settle(completed: completed, estimates: values, outcome: "已确认")
            }.primaryAction()
        }
    }
    private func defaultEstimate(_ allocation: Allocation) -> Int {
        var spent = timer.accumulatedSeconds
        for previous in timer.segment.allocations {
            if previous.stepID == allocation.stepID { break }
            spent -= min(spent, previous.seconds)
        }
        let original = store.steps.first { $0.id == allocation.stepID }?.remainingSeconds ?? allocation.seconds
        let remaining = max(0, original - min(spent, allocation.seconds))
        return remaining > 0 ? max(1, Int(ceil(Double(remaining) / 60))) : 10
    }
}
