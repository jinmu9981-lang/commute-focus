import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section {
                HStack {
                    metric("投入分钟", value: store.logs.reduce(0) { $0 + $1.seconds } / 60)
                    Spacer()
                    metric("完成步骤", value: Set(store.logs.flatMap(\.completedStepIDs)).count)
                    Spacer()
                    metric("仍待推进", value: store.steps.filter { !$0.completed }.count)
                }.padding(.vertical, 12)
            }
            if store.journeys.isEmpty {
                ContentUnavailableView("进展会留在这里", systemImage: "chart.bar.doc.horizontal",
                    description: Text("完成第一段通勤专注后，回来看看。"))
            }
            ForEach(store.journeys) { journey in
                Section {
                    let logs = store.logs.filter { $0.journeyID == journey.id }
                    LabeledContent(journey.direction,
                        value: journey.endedAt == nil ? "进行中 / 尚未结算" : "已结束")
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(log.taskTitle).font(.headline)
                            Text("投入 \(clockText(log.seconds)) · 完成 \(log.completedStepIDs.count) 步 · \(log.outcome)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                    if logs.isEmpty { Text("尚无已保存的专注记录").foregroundStyle(.secondary) }
                } header: {
                    Text(journey.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("每一步都算数")
        .refreshable { store.requestSync() }
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value)").font(.title.bold()).foregroundStyle(.teal)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
