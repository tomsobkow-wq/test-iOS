import Foundation

/// Where Bolek's server-side tools live (flight search, price watches). The agent loop stays on the
/// phone; only these tools run remotely, and only Bolek may use them.
public struct BackendConfig: Sendable, Equatable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

/// One alert the server stored, such as a watched fare dropping below the user's threshold.
public struct BackendAlert: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let message: String
}

public enum BackendError: LocalizedError, Sendable, Equatable {
    case unauthorized
    case unreachable
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "The Bolek server rejected the access token."
        case .unreachable: "The Bolek server could not be reached."
        case .server(let message): message
        }
    }
}

public struct BackendClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public struct RemoteSpec: Sendable, Equatable {
        public let name: String
        public let description: String
        public let risk: String
        /// JSON Schema for the arguments, as a string (what the prompt renderers take).
        public let parametersSchema: String
    }

    private let config: BackendConfig
    private let transport: Transport

    public init(config: BackendConfig, transport: Transport? = nil) {
        self.config = config
        self.transport = transport ?? { request in
            var request = request
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.unreachable }
            return (data, http)
        }
    }

    public func tools() async throws -> [RemoteSpec] {
        let data = try await send("v1/tools", method: "GET", body: nil)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["tools"] as? [[String: Any]] else { throw BackendError.server("Unexpected reply from the Bolek server.") }
        return list.compactMap { item in
            guard let name = item["name"] as? String,
                  let description = item["description"] as? String,
                  let parameters = item["parameters"],
                  let schema = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys])
            else { return nil }
            return RemoteSpec(
                name: name,
                description: description,
                risk: item["risk"] as? String ?? "write",
                parametersSchema: String(decoding: schema, as: UTF8.self)
            )
        }
    }

    /// Returns the text the model should read, whether the call worked or the server explained why not.
    public func call(_ name: String, argumentsJSON: String) async throws -> String {
        struct Reply: Decodable { let ok: Bool; let content: String }
        let arguments = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) ?? [String: Any]()
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "arguments": arguments])
        let data = try await send("v1/tools/call", method: "POST", body: body)
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        if !reply.ok { throw ToolError(reply.content) }
        return reply.content
    }

    public func alerts(since id: Int) async throws -> [BackendAlert] {
        struct Reply: Decodable { let alerts: [BackendAlert] }
        let data = try await send("v1/alerts?since=\(id)", method: "GET", body: nil)
        return try JSONDecoder().decode(Reply.self, from: data).alerts
    }

    public func markAlertsSeen(upTo id: Int) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["upTo": id])
        _ = try await send("v1/alerts/seen", method: "POST", body: body)
    }

    private func send(_ path: String, method: String, body: Data?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: config.baseURL) else { throw BackendError.unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw BackendError.unreachable
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw BackendError.unauthorized
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw BackendError.server(message ?? "The Bolek server answered \(response.statusCode).")
        }
    }
}

/// A tool whose description and schema come from the server and whose work happens there.
public struct RemoteTool: Tool {
    public let name: String
    public let description: LocalizedText
    public let parametersSchema: String
    public let tier: ToolTier = .bolek
    public let risk: ToolRisk
    private let client: BackendClient

    public init(spec: BackendClient.RemoteSpec, client: BackendClient) {
        name = spec.name
        // Server descriptions are English; Bolek is a large model and reads them fine in either conversation.
        description = LocalizedText(en: spec.description, pl: spec.description)
        parametersSchema = spec.parametersSchema
        // A watch lasts and can cost searches, so the user is asked first; searches and lists are plain reads.
        risk = spec.risk == "write" ? .writeExternal : .read
        self.client = client
    }

    public func run(argumentsJSON: String) async throws -> String {
        do {
            return try await client.call(name, argumentsJSON: argumentsJSON)
        } catch let error as BackendError {
            throw ToolError(error.errorDescription ?? "The Bolek server failed.")
        }
    }

    /// Fetches the server's tools. An unreachable or unauthorised server yields none rather than an error,
    /// so Bolek still chats; it just cannot search flights.
    public static func discover(client: BackendClient) async -> [RemoteTool] {
        guard let specs = try? await client.tools() else { return [] }
        return specs.map { RemoteTool(spec: $0, client: client) }
    }
}
