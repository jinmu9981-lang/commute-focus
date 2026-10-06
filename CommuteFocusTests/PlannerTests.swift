import XCTest
@testable import CommuteFocus

final class PlannerTests: XCTestCase {
    func fixture(_ minutes: Int, priority: Priority = .medium, order: Int = 0) -> (WorkTask, WorkStep) {
        let task = WorkTask(title: "任务", priority: priority, order: order)
        return (task, WorkStep(taskID: task.id, title: "步骤", remainingSeconds: minutes * 60, order: 0))
    }
    func testExpectedDurations() {
        let cases = [(10, [10]), (25, [25]), (35, [25, 10]), (60, [25, 25, 10]), (90, [25, 25, 25, 15])]
        for (minutes, expected) in cases {
            let (task, step) = fixture(minutes)
            let plan = Planner.make(tasks: [task], steps: [step], availableSeconds: 180 * 60)
            XCTAssertEqual(plan.segments.map(\.minutes), expected)
        }
    }
    func testAllDurationsStayWithinBudgetAndBounds() {
        for workload in 1...180 {
            let (task, step) = fixture(workload)
            for budget in 0...180 {
                let plan = Planner.make(tasks: [task], steps: [step], availableSeconds: budget * 60)
                XCTAssertLessThanOrEqual(plan.totalSeconds, budget * 60)
                XCTAssertTrue(plan.segments.allSatisfy { (600...1800).contains($0.seconds) })
                XCTAssertLessThanOrEqual(plan.totalSeconds, workload * 60)
            }
        }
    }
    func testPriorityAndStableOrder() {
        let (low, lowStep) = fixture(25, priority: .low)
        let (high, highStep) = fixture(25, priority: .high, order: 2)
        let (first, firstStep) = fixture(25, priority: .high, order: 1)
        let plan = Planner.make(tasks: [low, high, first], steps: [lowStep, highStep, firstStep], availableSeconds: 75 * 60)
        XCTAssertEqual(plan.segments.map(\.taskID), [first.id, high.id, low.id])
    }
    func testShortStepsMergeOnlyWithinTheirTask() {
        let (task, first) = fixture(5)
        let second = WorkStep(taskID: task.id, title: "第二步", remainingSeconds: 5 * 60, order: 1)
        let (other, otherStep) = fixture(5)
        let merged = Planner.make(tasks: [task], steps: [second, first], availableSeconds: 600)
        XCTAssertEqual(merged.segments.first?.allocations.map(\.stepID), [first.id, second.id])
        XCTAssertEqual(merged.segments.first?.seconds, 600)
        XCTAssertTrue(Planner.make(tasks: [task, other], steps: [first, otherStep], availableSeconds: 1800).segments.isEmpty)
    }
    func testZeroEstimateBlocksLaterStep() {
        let (task, first) = fixture(0)
        let second = WorkStep(taskID: task.id, title: "第二步", remainingSeconds: 1500, order: 1)
        let plan = Planner.make(tasks: [task], steps: [first, second], availableSeconds: 3600)
        XCTAssertTrue(plan.segments.isEmpty)
        XCTAssertTrue(plan.reasons.contains { $0.contains("重新估算") })
    }
    func testInsufficientTimeDoesNotCreateUnusableTail() {
        let (task, step) = fixture(15)
        XCTAssertTrue(Planner.make(tasks: [task], steps: [step], availableSeconds: 600).segments.isEmpty)
        let (long, longStep) = fixture(31)
        XCTAssertEqual(Planner.make(tasks: [long], steps: [longStep], availableSeconds: 3600).segments.map(\.minutes), [21, 10])
    }
    func testEmptyExcludedAndUnderTenMinutes() {
        let (task, step) = fixture(60)
        XCTAssertTrue(Planner.make(tasks: [], steps: [], availableSeconds: 600).segments.isEmpty)
        XCTAssertTrue(Planner.make(tasks: [task], steps: [step], availableSeconds: 599).segments.isEmpty)
        XCTAssertTrue(Planner.make(tasks: [task], steps: [step], availableSeconds: 3600, excluding: [task.id]).segments.isEmpty)
    }
    func testCompletedStepsAndCrossCommuteRemainingWork() {
        let (task, step) = fixture(35)
        var done = WorkStep(taskID: task.id, title: "已完成", remainingSeconds: 0, order: -1)
        done.completed = true
        var remaining = step
        remaining.remainingSeconds -= 1500
        let plan = Planner.make(tasks: [task], steps: [done, remaining], availableSeconds: 600)
        XCTAssertEqual(plan.segments.first?.allocations.first?.stepID, step.id)
        XCTAssertEqual(plan.segments.first?.minutes, 10)
    }
}
