import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var creating = false
    var body: some View {
        List {
            if store.tasks.isEmpty {
                ContentUnavailableView("先放下一个大任务", systemImage: "square.and.pencil",
                    description: Text("把它拆成你愿意在路上推进的小步骤。"))
            }
            ForEach(store.tasks) { task in
                NavigationLink {
                    TaskDetailView(taskID: task.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.headline)
                        let items = store.orderedSteps(task.id)
                        Text("\(task.priority.title)优先级 · \(items.filter(\.completed).count)/\(items.count) 步骤完成")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
                .swipeActions {
                    if store.active?.timer?.segment.taskID != task.id {
                        Button("删除", role: .destructive) { store.deleteTask(task) }
                    }
                }
            }
            .onMove(perform: store.moveTasks)
            if !store.tasks.isEmpty {
                Text("拖动可调整同优先级任务的顺序。删除会同步到你的其他设备。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("任务清单")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) {
            TaskEditor(task: WorkTask(title: "", order: (store.tasks.map(\.order).max() ?? -1) + 1))
        }
    }
}

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    let taskID: UUID
    @State private var editTask = false
    @State private var editStep: WorkStep?
    var task: WorkTask? { store.tasks.first { $0.id == taskID } }
    var locked: Bool { store.active?.timer?.segment.taskID == taskID }
    var body: some View {
        List {
            if let task {
                Section {
                    LabeledContent("优先级", value: "\(task.priority.title)优先级")
                    Button("编辑任务") { editTask = true }.disabled(locked)
                }
                Section("按顺序推进") {
                    ForEach(store.orderedSteps(taskID)) { step in
                        Button {
                            editStep = step
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: step.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.completed ? .teal : .secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(step.title).foregroundStyle(.primary)
                                    Text(step.completed ? "已完成" : step.remainingSeconds == 0 ? "需要重新估算" : "剩余约 \(Int(ceil(Double(step.remainingSeconds) / 60))) 分钟")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 6)
                        }
                        .disabled(locked)
                        .swipeActions {
                            if !locked { Button("删除", role: .destructive) { store.deleteStep(step) } }
                        }
                    }
                    .onMove { from, to in store.moveSteps(taskID: taskID, from: from, to: to) }
                    .moveDisabled(locked)
                    Button("添加步骤", systemImage: "plus") {
                        editStep = WorkStep(taskID: taskID, title: "", remainingSeconds: 25 * 60,
                            order: (store.orderedSteps(taskID).map(\.order).max() ?? -1) + 1)
                    }.disabled(locked)
                }
                Text(locked ? "当前专注期间暂不编辑这项任务；先确认进度或结束该段。" : "少于 10 分钟的步骤会尝试与相邻步骤合并。超过 30 分钟的步骤会分段安排。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("任务已删除", systemImage: "tray")
            }
        }
        .navigationTitle(task?.title ?? "任务")
        .toolbar { EditButton().disabled(locked) }
        .sheet(isPresented: $editTask) { if let task { TaskEditor(task: task) } }
        .sheet(item: $editStep) { StepEditor(step: $0) }
    }
}

struct TaskEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var task: WorkTask
    var body: some View {
        NavigationStack {
            Form {
                TextField("例如：准备周五的项目汇报", text: $task.title, axis: .vertical)
                    .lineLimit(1...4)
                Picker("优先级", selection: $task.priority) {
                    ForEach(Priority.allCases) { Text($0.title).tag($0) }
                }
                Text("保存后，在任务中添加具体步骤和预计耗时。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("大任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.saveTask(task)
                        if store.error == nil { dismiss() }
                    }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct StepEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var step: WorkStep
    @State private var minutes: Int
    init(step: WorkStep) {
        _step = State(initialValue: step)
        _minutes = State(initialValue: max(1, Int(ceil(Double(step.remainingSeconds) / 60))))
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("例如：列出汇报的三个关键结论", text: $step.title, axis: .vertical)
                Stepper("剩余约 \(minutes) 分钟", value: $minutes, in: 1...1440)
                HStack {
                    ForEach([10, 15, 25, 30, 60], id: \.self) { value in
                        Button("\(value)") { minutes = value }.buttonStyle(.bordered)
                    }
                }
                Toggle("已完成", isOn: $step.completed)
            }
            .navigationTitle("任务步骤")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        step.remainingSeconds = step.completed ? 0 : minutes * 60
                        store.saveStep(step)
                        if store.error == nil { dismiss() }
                    }.disabled(step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
