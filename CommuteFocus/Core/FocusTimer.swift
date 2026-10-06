import Foundation

enum TimerPhase: String, Codable { case running, paused, awaitingConfirmation }

struct FocusTimer: Codable, Equatable {
    var segment: FocusSegment
    var startedAt: Date
    var phase: TimerPhase = .running
    var accumulatedSeconds = 0
    var runningSince: Date
    var deadline: Date

    init(segment: FocusSegment, now: Date, cutoff: Date) {
        self.segment = segment
        startedAt = now
        runningSince = now
        deadline = min(now.addingTimeInterval(Double(segment.seconds)), cutoff)
    }

    func elapsed(at now: Date) -> Int {
        let current = phase == .running ? max(0, Int(min(now, deadline).timeIntervalSince(runningSince))) : 0
        return min(segment.seconds, accumulatedSeconds + current)
    }

    func remaining(at now: Date) -> Int { max(0, segment.seconds - elapsed(at: now)) }

    mutating func reconcile(now: Date, cutoff: Date) {
        if phase == .running && (now >= deadline || now >= cutoff) {
            accumulatedSeconds = elapsed(at: min(now, cutoff))
            phase = .awaitingConfirmation
        } else if phase == .paused && now >= cutoff {
            phase = .awaitingConfirmation
        }
    }

    mutating func pause(now: Date) {
        guard phase == .running else { return }
        accumulatedSeconds = elapsed(at: now)
        phase = now >= deadline ? .awaitingConfirmation : .paused
    }

    mutating func resume(now: Date, cutoff: Date) {
        guard phase == .paused else { return }
        // Resuming is continuation of an existing block, not a new 10-minute block.
        guard cutoff.timeIntervalSince(now) >= Double(remaining(at: now)) else {
            phase = .awaitingConfirmation
            return
        }
        runningSince = now
        deadline = now.addingTimeInterval(Double(remaining(at: now)))
        phase = .running
    }

    mutating func requestConfirmation(now: Date) {
        accumulatedSeconds = elapsed(at: now)
        phase = .awaitingConfirmation
    }
}
