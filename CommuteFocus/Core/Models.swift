import Foundation

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case high = 0, medium = 1, low = 2
    var id: Int { rawValue }
    var title: String { ["高", "中", "低"][rawValue] }
}

struct WorkTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var priority: Priority = .medium
    var order: Int = 0
    var createdAt = Date()
}

struct WorkStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var taskID: UUID
    var title: String
    var remainingSeconds: Int
    var order: Int
    var completed = false
}

struct Preferences: Codable, Equatable {
    static let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var outboundMinutes = 60
    var inboundMinutes = 60
    var bufferMinutes = 3
    var reminders = true
}

struct Journey: Codable, Identifiable, Equatable {
    var id = UUID()
    var deviceID: String
    var startedAt: Date
    var arrivalAt: Date
    var endedAt: Date?
    var direction: String
}

struct Allocation: Codable, Identifiable, Equatable {
    var stepID: UUID
    var title: String
    var seconds: Int
    var id: UUID { stepID }
}

struct FocusSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var taskID: UUID
    var taskTitle: String
    var allocations: [Allocation]
    var seconds: Int { allocations.reduce(0) { $0 + $1.seconds } }
    var minutes: Int { seconds / 60 }
}

struct FocusLog: Codable, Identifiable, Equatable {
    var id: UUID // Segment ID makes repeated completion idempotent.
    var journeyID: UUID
    var taskID: UUID
    var taskTitle: String
    var startedAt: Date
    var seconds: Int
    var completedStepIDs: [UUID]
    var outcome: String
}

enum RecordKind: String, Codable { case task, step, journey, focus, preferences }

struct Plan {
    var segments: [FocusSegment]
    var reasons: [String]
    var totalSeconds: Int { segments.reduce(0) { $0 + $1.seconds } }
}

struct ActiveCommute: Codable, Equatable {
    var journey: Journey
    var bufferMinutes: Int
    var skippedTaskIDs: Set<UUID> = []
    var timer: FocusTimer?
    var cutoff: Date { journey.arrivalAt.addingTimeInterval(-Double(bufferMinutes * 60)) }
}
