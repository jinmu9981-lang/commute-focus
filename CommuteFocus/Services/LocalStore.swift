import Foundation
import SwiftData

@Model
final class LocalRecord {
    @Attribute(.unique) var key: String
    var owner: String
    var recordID: UUID
    var kind: String
    var payload: Data
    var deleted: Bool
    var dirty: Bool
    var mutationID: UUID
    var revision: Int64

    init(owner: String, id: UUID, kind: RecordKind, payload: Data, deleted: Bool = false) {
        key = "\(owner)/\(id.uuidString)"
        self.owner = owner
        recordID = id
        self.kind = kind.rawValue
        self.payload = payload
        self.deleted = deleted
        dirty = true
        mutationID = UUID()
        revision = 0
    }
}

struct RemoteRecord: Codable {
    var id: UUID
    var kind: String
    var payload: JSONValue
    var deleted: Bool
    var revision: Int64
    var mutation_id: UUID
}

struct UploadRecord: Encodable {
    var id: UUID
    var kind: String
    var payload: JSONValue
    var deleted: Bool
    var mutation_id: UUID
}

enum JSONValue: Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

@MainActor
final class LocalStore {
    let context: ModelContext
    // Keep storage alive even when the caller only retains this store.
    private let container: ModelContainer
    private var batching = false
    init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    func transaction(_ body: () throws -> Void) throws {
        batching = true
        defer { batching = false }
        do {
            try body()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func rows(owner: String) throws -> [LocalRecord] {
        try context.fetch(FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.owner == owner }))
    }

    func values<T: Decodable>(_ type: T.Type, kind: RecordKind, owner: String) throws -> [T] {
        try rows(owner: owner).filter { $0.kind == kind.rawValue && !$0.deleted }.map {
            try JSONDecoder().decode(type, from: $0.payload)
        }
    }

    func put<T: Encodable>(_ value: T, id: UUID, kind: RecordKind, owner: String) throws {
        let data = try JSONEncoder().encode(value)
        if let row = try rows(owner: owner).first(where: { $0.recordID == id }) {
            guard !row.deleted else { return } // Tombstones cannot be resurrected.
            row.payload = data
            row.dirty = true
            row.mutationID = UUID()
        } else {
            context.insert(LocalRecord(owner: owner, id: id, kind: kind, payload: data))
        }
        if !batching { try context.save() }
    }

    func delete(id: UUID, owner: String) throws {
        guard let row = try rows(owner: owner).first(where: { $0.recordID == id }) else { return }
        row.deleted = true
        row.dirty = true
        row.mutationID = UUID()
        if !batching { try context.save() }
    }

    func pending(owner: String) throws -> [UploadRecord] {
        try rows(owner: owner).filter(\.dirty).map {
            UploadRecord(id: $0.recordID, kind: $0.kind,
                         payload: try JSONDecoder().decode(JSONValue.self, from: $0.payload),
                         deleted: $0.deleted, mutation_id: $0.mutationID)
        }
    }

    func merge(_ remote: [RemoteRecord], owner: String, acknowledgements: [UUID: UUID] = [:]) throws {
        var existing = Dictionary(uniqueKeysWithValues: try rows(owner: owner).map { ($0.recordID, $0) })
        for incoming in remote {
            guard let kind = RecordKind(rawValue: incoming.kind) else { continue }
            let payload = try JSONEncoder().encode(incoming.payload)
            if let row = existing[incoming.id] {
                let acknowledgesCurrent = acknowledgements[incoming.id] == row.mutationID
                guard incoming.deleted || !row.dirty || acknowledgesCurrent else { continue }
                guard incoming.revision >= row.revision else { continue }
                row.payload = payload
                row.deleted = incoming.deleted
                row.revision = incoming.revision
                row.dirty = false
            } else {
                let row = LocalRecord(owner: owner, id: incoming.id, kind: kind, payload: payload, deleted: incoming.deleted)
                row.dirty = false
                row.revision = incoming.revision
                context.insert(row)
                existing[incoming.id] = row
            }
        }
        try context.save()
    }
}
