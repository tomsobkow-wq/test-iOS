import Foundation

public struct MemoryRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Facts the agent remembers about the user. Each mode has its own store;
/// Lolek and Bolek never share one unless the user turns sharing on.
public protocol MemoryStore: Sendable {
    func all() async -> [MemoryRecord]
    func remember(_ text: String) async
    /// Deletes every record mentioning `topic`. Returns how many were removed.
    @discardableResult
    func forget(matching topic: String) async -> Int
}

public actor InMemoryMemoryStore: MemoryStore {
    private var records: [MemoryRecord] = []

    public init() {}

    public func all() -> [MemoryRecord] { records }

    public func remember(_ text: String) {
        records.append(MemoryRecord(text: text))
    }

    @discardableResult
    public func forget(matching topic: String) -> Int {
        let before = records.count
        records.removeAll { $0.text.localizedCaseInsensitiveContains(topic) }
        return before - records.count
    }
}
