import XCTest
import SwiftData
@testable import CommuteFocus

@MainActor
final class LocalStoreTests: XCTestCase {
    func makeStore() throws -> LocalStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalRecord.self, configurations: configuration)
        return LocalStore(context: container.mainContext)
    }
    func remote(_ task: WorkTask, revision: Int64, deleted: Bool = false, mutation: UUID = UUID()) throws -> RemoteRecord {
        RemoteRecord(id: task.id, kind: "task", payload: try JSONDecoder().decode(JSONValue.self,
            from: JSONEncoder().encode(task)), deleted: deleted, revision: revision, mutation_id: mutation)
    }
    func testAccountIsolationAndPendingOfflineEdits() throws {
        let store = try makeStore()
        let task = WorkTask(title: "A 的任务")
        try store.put(task, id: task.id, kind: .task, owner: "A")
        XCTAssertEqual(try store.values(WorkTask.self, kind: .task, owner: "A").count, 1)
        XCTAssertTrue(try store.values(WorkTask.self, kind: .task, owner: "B").isEmpty)
        XCTAssertEqual(try store.pending(owner: "A").count, 1)
    }
    func testAcknowledgementDoesNotDiscardNewerLocalEdit() throws {
        let store = try makeStore()
        var task = WorkTask(title: "旧值")
        try store.put(task, id: task.id, kind: .task, owner: "A")
        let old = try store.pending(owner: "A")[0]
        let response = try remote(task, revision: 1, mutation: old.mutation_id)
        task.title = "请求期间的新值"
        try store.put(task, id: task.id, kind: .task, owner: "A")
        try store.merge([response], owner: "A", acknowledgements: [task.id: old.mutation_id])
        XCTAssertEqual(try store.values(WorkTask.self, kind: .task, owner: "A").first?.title, task.title)
        XCTAssertEqual(try store.pending(owner: "A").count, 1)
    }
    func testTombstoneWinsAndRepeatedMergeDoesNotDuplicate() throws {
        let store = try makeStore()
        let task = WorkTask(title: "任务")
        try store.put(task, id: task.id, kind: .task, owner: "A")
        let deleted = try remote(task, revision: 2, deleted: true)
        try store.merge([deleted, deleted], owner: "A")
        try store.put(task, id: task.id, kind: .task, owner: "A")
        try store.merge([try remote(task, revision: 1)], owner: "A")
        XCTAssertTrue(try store.values(WorkTask.self, kind: .task, owner: "A").isEmpty)
        XCTAssertEqual(try store.rows(owner: "A").count, 1)
        XCTAssertTrue(try store.pending(owner: "A").isEmpty)
    }
    func testAtomicRollback() throws {
        let store = try makeStore()
        let task = WorkTask(title: "未保存")
        XCTAssertThrowsError(try store.transaction {
            try store.put(task, id: task.id, kind: .task, owner: "A")
            throw CloudError.message("模拟写入失败")
        })
        XCTAssertTrue(try store.values(WorkTask.self, kind: .task, owner: "A").isEmpty)
    }
    func testFocusLogUsesStableSegmentIdentity() throws {
        let store = try makeStore()
        let log = FocusLog(id: UUID(), journeyID: UUID(), taskID: UUID(), taskTitle: "任务",
                           startedAt: Date(), seconds: 600, completedStepIDs: [], outcome: "已确认")
        try store.put(log, id: log.id, kind: .focus, owner: "A")
        try store.put(log, id: log.id, kind: .focus, owner: "A")
        let logs = try store.values(FocusLog.self, kind: .focus, owner: "A")
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.reduce(0) { $0 + $1.seconds }, 600)
    }
}
