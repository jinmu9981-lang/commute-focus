import XCTest
@testable import CommuteFocus

final class TimerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func timer() -> FocusTimer {
        let segment = FocusSegment(taskID: UUID(), taskTitle: "汇报",
            allocations: [Allocation(stepID: UUID(), title: "结论", seconds: 1500)])
        return FocusTimer(segment: segment, now: start, cutoff: start.addingTimeInterval(3600))
    }
    func testPauseDoesNotCountWaiting() {
        var t = timer()
        t.pause(now: start.addingTimeInterval(300))
        XCTAssertEqual(t.elapsed(at: start.addingTimeInterval(900)), 300)
        t.resume(now: start.addingTimeInterval(900), cutoff: start.addingTimeInterval(3600))
        XCTAssertEqual(t.deadline, start.addingTimeInterval(2100))
        XCTAssertEqual(t.elapsed(at: start.addingTimeInterval(1000)), 400)
    }
    func testCannotResumePastArrival() {
        var t = timer()
        t.pause(now: start.addingTimeInterval(300))
        t.resume(now: start.addingTimeInterval(3500), cutoff: start.addingTimeInterval(3600))
        XCTAssertEqual(t.phase, .awaitingConfirmation)
        XCTAssertEqual(t.accumulatedSeconds, 300)
    }
    func testRestartUsesPersistedDeadlineAndCapsElapsed() throws {
        let saved = try JSONEncoder().encode(timer())
        var restored = try JSONDecoder().decode(FocusTimer.self, from: saved)
        restored.reconcile(now: start.addingTimeInterval(5000), cutoff: start.addingTimeInterval(3600))
        XCTAssertEqual(restored.phase, .awaitingConfirmation)
        XCTAssertEqual(restored.accumulatedSeconds, 1500)
        restored.reconcile(now: start.addingTimeInterval(9000), cutoff: start.addingTimeInterval(3600))
        XCTAssertEqual(restored.accumulatedSeconds, 1500)
    }
    func testEarlyFinishOnlyRequestsConfirmation() {
        var t = timer()
        t.requestConfirmation(now: start.addingTimeInterval(120))
        XCTAssertEqual(t.phase, .awaitingConfirmation)
        XCTAssertEqual(t.accumulatedSeconds, 120)
        XCTAssertEqual(t.segment.allocations.count, 1)
    }
    func testPausedAtArrivalAndClockGoingBackwards() {
        var t = timer()
        XCTAssertEqual(t.elapsed(at: start.addingTimeInterval(-100)), 0)
        t.pause(now: start.addingTimeInterval(120))
        t.reconcile(now: start.addingTimeInterval(3600), cutoff: start.addingTimeInterval(3600))
        XCTAssertEqual(t.phase, .awaitingConfirmation)
        XCTAssertEqual(t.accumulatedSeconds, 120)
    }
}
