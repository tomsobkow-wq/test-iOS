import Foundation

/// Notes kept on the device. Persistence arrives with Lolek's tools (build step 3).
public actor NoteStore {
    public private(set) var notes: [String] = []

    public init() {}

    public func add(_ text: String) {
        notes.append(text)
    }
}

public struct AddNoteTool: Tool {
    public let name = "add_note"
    public let description = LocalizedText(
        en: "Save a short note on this device.",
        pl: "Zapisz krótką notatkę na tym urządzeniu."
    )
    public let parametersSchema = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal

    private let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public func run(argumentsJSON: String) async throws -> String {
        let arguments = try ToolArguments.decode(TextArgument.self, from: argumentsJSON)
        await store.add(arguments.text)
        return "Saved note."
    }
}

/// Stand-in for a real "send" tool so the approval flow can be exercised.
/// Nothing is sent.
public struct DemoSendMessageTool: Tool {
    public let name = "send_message_demo"
    public let description = LocalizedText(
        en: "Send a message (demo: nothing is actually sent).",
        pl: "Wyślij wiadomość (demo: nic nie zostanie wysłane)."
    )
    public let parametersSchema = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.send

    public init() {}

    public func run(argumentsJSON: String) async throws -> String {
        let arguments = try ToolArguments.decode(TextArgument.self, from: argumentsJSON)
        return "Demo: would have sent \"\(arguments.text)\"."
    }
}
