import AgentCore
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Gmail sign-in for Lolek. Runs entirely between this phone and Google: the app asks for the read-only Gmail permission,
/// keeps the refresh token in this phone's Keychain, and never passes it (or any email) to Bolek or to our servers.
/// Developer builds: launch once with `GOOGLE_CLIENT_ID` set (an iOS OAuth client for bundle com.boleklolek.app).
enum GoogleConfig {
    static let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private static let defaultsKey = "googleClientID"

    static var clientID: String? {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           env.hasSuffix(".apps.googleusercontent.com") {
            UserDefaults.standard.set(env, forKey: defaultsKey)
        }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }

    /// Google's iOS clients redirect to the client id written backwards.
    static var callbackScheme: String? {
        clientID.map { "com.googleusercontent.apps." + $0.replacingOccurrences(of: ".apps.googleusercontent.com", with: "") }
    }
}

actor GoogleTokens {
    private static let service = "com.boleklolek.gmail"
    private static let account = "refresh-token"
    private var accessToken: String?
    private var expiry = Date.distantPast

    var isSignedIn: Bool { Keychain.read(service: Self.service, account: Self.account) != nil }

    func validAccessToken() async throws -> String {
        if let accessToken, expiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.read(service: Self.service, account: Self.account), let client = GoogleConfig.clientID else {
            throw ToolError("Gmail is not connected. Tell the user to connect Gmail from the + menu.")
        }
        let reply = try await Self.post("https://oauth2.googleapis.com/token", ["client_id": client, "grant_type": "refresh_token", "refresh_token": refresh])
        guard let token = reply["access_token"] as? String else {
            clear()
            throw ToolError("Gmail sign-in expired. Tell the user to reconnect Gmail from the + menu.")
        }
        accessToken = token
        expiry = Date().addingTimeInterval((reply["expires_in"] as? Double) ?? 3000)
        return token
    }

    func store(_ reply: [String: Any]) throws {
        guard let scopes = reply["scope"] as? String, scopes.contains("gmail.readonly") else {
            throw ToolError(String(localized: "Gmail needs permission to read your email. Connect again and leave “Read your email” ticked."))
        }
        guard let refresh = reply["refresh_token"] as? String, let access = reply["access_token"] as? String else {
            throw ToolError(String(localized: "Google did not finish the sign-in. Try again."))
        }
        Keychain.write(refresh, service: Self.service, account: Self.account)
        accessToken = access
        expiry = Date().addingTimeInterval((reply["expires_in"] as? Double) ?? 3000)
    }

    func signOut() async {
        if let refresh = Keychain.read(service: Self.service, account: Self.account) {
            _ = try? await Self.post("https://oauth2.googleapis.com/revoke", ["token": refresh])
        }
        clear()
    }

    private func clear() {
        Keychain.delete(service: Self.service, account: Self.account)
        accessToken = nil
        expiry = .distantPast
    }

    static func post(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

@MainActor
@Observable
final class MailConnection: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum State: Equatable { case unavailable, signedOut, signedIn, working, failed(String) }

    private(set) var state: State = .signedOut
    let tokens = GoogleTokens()
    /// The mailbox Lolek reads from. Only Lolek's registry gets tools built on this.
    nonisolated let provider: GmailClient

    override init() {
        let tokens = tokens
        provider = GmailClient(isSignedIn: { await tokens.isSignedIn }, accessToken: { try await tokens.validAccessToken() })
        super.init()
        state = GoogleConfig.clientID == nil ? .unavailable : .signedOut
        Task { if await tokens.isSignedIn { state = .signedIn } }
    }

    var isConnected: Bool { state == .signedIn }
    var canConnect: Bool { state != .unavailable }

    func connect() async -> Bool {
        guard let client = GoogleConfig.clientID, let scheme = GoogleConfig.callbackScheme else { return false }
        state = .working
        do {
            let verifier = Self.randomString(48)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let redirect = scheme + ":/oauth2redirect"
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                .init(name: "client_id", value: client), .init(name: "redirect_uri", value: redirect), .init(name: "response_type", value: "code"),
                .init(name: "scope", value: GoogleConfig.scope), .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
            ]
            let callback = try await authorize(components.url!, scheme: scheme)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw ToolError(String(localized: "Gmail was not connected."))
            }
            let reply = try await GoogleTokens.post("https://oauth2.googleapis.com/token", [
                "client_id": client, "code": code, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code",
            ])
            try await tokens.store(reply)
            state = .signedIn
            return true
        } catch {
            state = .failed((error as? ToolError)?.message ?? String(localized: "Gmail was not connected."))
            return false
        }
    }

    func disconnect() async {
        await tokens.signOut()
        state = .signedOut
    }

    private func authorize(_ url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback { continuation.resume(returning: callback) } else { continuation.resume(throwing: error ?? ToolError("Cancelled")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() { continuation.resume(throwing: ToolError("Could not open the Google sign-in.")) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
