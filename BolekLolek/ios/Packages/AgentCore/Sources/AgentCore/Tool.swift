import Foundation

/// Which assistant may use a tool.
public enum ToolTier: String, Codable, Sendable {
    case lolek, bolek, both
}

/// What a tool can do to the world. Drives the approval gate.
public enum ToolRisk: String, Codable, Sendable {
    /// Reads data only.
    case read
    /// Writes data that stays on this device or in the user's own store.
    case writeLocal
    /// Changes something in an external service.
    case writeExternal
    /// Sends something to another person (email, message).
    case send
    /// Spends money.
    case spend

    public var needsApproval: Bool {
        switch self {
        case .read, .writeLocal: false
        case .writeExternal, .send, .spend: true
        }
    }
}

public struct ToolCall: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// Arguments as a JSON object string, exactly as the model produced them.
    public let argumentsJSON: String

    public init(id: String = UUID().uuidString, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ToolResult: Codable, Sendable, Equatable {
    public let callID: String
    public let content: String
    public let isError: Bool

    public init(callID: String, content: String, isError: Bool = false) {
        self.callID = callID
        self.content = content
        self.isError = isError
    }
}

/// What the model is told about a tool, in the conversation's language.
public struct ToolSpec: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    /// JSON Schema for the arguments object.
    public let parametersSchema: String
}

public protocol Tool: Sendable {
    var name: String { get }
    var description: LocalizedText { get }
    var parametersSchema: String { get }
    var tier: ToolTier { get }
    var risk: ToolRisk { get }

    /// Runs the tool. Returns text the model will see as the result.
    func run(argumentsJSON: String) async throws -> String
}

extension Tool {
    public func spec(in language: ConversationLanguage) -> ToolSpec {
        ToolSpec(name: name, description: description.text(for: language), parametersSchema: parametersSchema)
    }
}

/// All tools known to a session. Each mode only ever sees the tools its tier allows.
public struct ToolRegistry: Sendable {
    private let toolsByName: [String: any Tool]

    public init(_ tools: [any Tool]) {
        var byName: [String: any Tool] = [:]
        for tool in tools {
            precondition(byName[tool.name] == nil, "Duplicate tool name: \(tool.name)")
            byName[tool.name] = tool
        }
        toolsByName = byName
    }

    public func tools(for mode: AgentMode) -> [any Tool] {
        toolsByName.values
            .filter { mode.allows($0.tier) }
            .sorted { $0.name < $1.name }
    }

    public func tool(named name: String, for mode: AgentMode) -> (any Tool)? {
        guard let tool = toolsByName[name], mode.allows(tool.tier) else { return nil }
        return tool
    }
}

/// JSON helpers for tool arguments.
public enum ToolArguments {
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    public static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct TextArgument: Codable {
    let text: String
}
