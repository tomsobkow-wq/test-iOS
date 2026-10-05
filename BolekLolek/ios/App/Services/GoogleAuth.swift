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
    /// Reading, plus sending the replies the user writes and sends from the composer. Nothing else (no deleting, no settings).
    static let scope = "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send"
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
    private static let indexAccount = "accounts"
    private static let legacyAccount = "refresh-token"
    private var access: [String: (token: String, expiry: Date)] = [:]

    private static func refreshKey(_ email: String) -> String { "refresh-token:" + email.lowercased() }
    private static func scopeKey(_ email: String) -> String { "scope:" + email.lowercased() }

    /// Whether this sign-in was granted sending (sign-ins made before replies existed were read-only).
    func canSend(_ email: String) -> Bool {
        (Keychain.read(service: Self.service, account: Self.scopeKey(email)) ?? "").contains("gmail.send")
    }

    /// The connected mailboxes. A sign-in saved by the first single-account build is moved over on the way.
    func accounts() async -> [String] {
        var list = storedIndex()
        if let legacy = Keychain.read(service: Self.service, account: Self.legacyAccount) {
            if let email = try? await Self.fetchEmail(refresh: legacy, client: GoogleConfig.clientID) {
                Keychain.write(legacy, service: Self.service, account: Self.refreshKey(email))
                if !list.contains(email.lowercased()) { list.append(email.lowercased()); saveIndex(list) }
            }
            Keychain.delete(service: Self.service, account: Self.legacyAccount)
        }
        return list
    }

    func validAccessToken(for email: String) async throws -> String {
        if let cached = access[email], cached.expiry > Date().addingTimeInterval(60) { return cached.token }
        guard let refresh = Keychain.read(service: Self.service, account: Self.refreshKey(email)), let client = GoogleConfig.clientID else {
            throw ToolError("Gmail account \(email) is not connected. Tell the user to connect it from the + menu.")
        }
        let reply = try await Self.post("https://oauth2.googleapis.com/token", ["client_id": client, "grant_type": "refresh_token", "refresh_token": refresh])
        guard let token = reply["access_token"] as? String else {
            throw ToolError("Gmail sign-in for \(email) expired. Tell the user to reconnect it from the + menu.")
        }
        access[email] = (token, Date().addingTimeInterval((reply["expires_in"] as? Double) ?? 3000))
        return token
    }

    /// Saves a new sign-in under the mailbox's own address and returns that address.
    func add(_ reply: [String: Any]) async throws -> String {
        guard let scopes = reply["scope"] as? String, scopes.contains("gmail.readonly") else {
            throw ToolError(String(localized: "Gmail needs permission to read your email. Connect again and leave “Read your email” ticked."))
        }
        guard let refresh = reply["refresh_token"] as? String, let token = reply["access_token"] as? String else {
            throw ToolError(String(localized: "Google did not finish the sign-in. Try again."))
        }
        let email = try await Self.profileEmail(accessToken: token).lowercased()
        Keychain.write(refresh, service: Self.service, account: Self.refreshKey(email))
        Keychain.write(scopes, service: Self.service, account: Self.scopeKey(email))
        var list = storedIndex()
        if !list.contains(email) { list.append(email); saveIndex(list) }
        access[email] = (token, Date().addingTimeInterval((reply["expires_in"] as? Double) ?? 3000))
        return email
    }

    func signOut(_ email: String) async {
        if let refresh = Keychain.read(service: Self.service, account: Self.refreshKey(email)) {
            _ = try? await Self.post("https://oauth2.googleapis.com/revoke", ["token": refresh])
        }
        Keychain.delete(service: Self.service, account: Self.refreshKey(email))
        Keychain.delete(service: Self.service, account: Self.scopeKey(email))
        access[email] = nil
        saveIndex(storedIndex().filter { $0 != email.lowercased() })
    }

    private func storedIndex() -> [String] {
        Keychain.read(service: Self.service, account: Self.indexAccount)
            .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
    }

    private func saveIndex(_ list: [String]) {
        let text = (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        Keychain.write(text, service: Self.service, account: Self.indexAccount)
    }

    private static func fetchEmail(refresh: String, client: String?) async throws -> String {
        guard let client else { throw ToolError("no client") }
        let reply = try await post("https://oauth2.googleapis.com/token", ["client_id": client, "grant_type": "refresh_token", "refresh_token": refresh])
        guard let token = reply["access_token"] as? String else { throw ToolError("expired") }
        return try await profileEmail(accessToken: token)
    }

    private static func profileEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let email = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["emailAddress"] as? String else {
            throw ToolError(String(localized: "Google did not finish the sign-in. Try again."))
        }
        return email
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
    /// Addresses of the connected mailboxes.
    private(set) var accounts: [String] = []
    let tokens = GoogleTokens()
    /// The mailboxes Lolek reads from. Only Lolek's registry gets tools built on this.
    nonisolated let provider: MultiEmailProvider

    /// Unread inbox mail across the connected mailboxes (nil until known).
    private(set) var unread: Int?
    /// Debug only: BOLEK_DEBUG_MAIL_FIXTURE=1 (or 2) shows made-up mailboxes instead of Gmail, for screenshots.
    private let fixtureLabels: [String]

    override init() {
        let tokens = tokens
        var fixtures: [String] = []
        #if DEBUG
        if let count = ProcessInfo.processInfo.environment["BOLEK_DEBUG_MAIL_FIXTURE"].flatMap(Int.init), count > 0 {
            fixtures = ["anna@example.com", "praca@example.com"].prefix(min(count, 2)).map { $0 }
        }
        #endif
        fixtureLabels = fixtures
        let fixtureBoxes = fixtures.enumerated().map { index, label in
            // The second fixture mailbox is a little older, so the two interleave.
            FixtureMailbox(label: label, now: Date().addingTimeInterval(-Double(index) * 2400))
        }
        #if DEBUG
        // BOLEK_DEBUG_MAIL_READONLY=1 makes the made-up mailboxes read-only, to see the "reconnect to send" state.
        if ProcessInfo.processInfo.environment["BOLEK_DEBUG_MAIL_READONLY"] == "1" { fixtureBoxes.forEach { $0.allowsSending = false } }
        #endif
        provider = MultiEmailProvider {
            if !fixtureBoxes.isEmpty {
                return fixtureBoxes.map { MultiEmailProvider.Account(label: $0.label, provider: $0, paging: $0, sending: $0) }
            }
            return await tokens.accounts().map { email in
                let client = GmailClient(isSignedIn: { true }, accessToken: { try await tokens.validAccessToken(for: email) }, canSend: { await tokens.canSend(email) })
                return MultiEmailProvider.Account(label: email, provider: client, paging: client, sending: client)
            }
        }
        super.init()
        state = GoogleConfig.clientID == nil && fixtures.isEmpty ? .unavailable : .signedOut
        Task { await refreshAccounts() }
    }

    /// Fresh unread count; called when the app comes forward and after connecting.
    func refreshUnread() async {
        guard isConnected else { unread = nil; return }
        unread = await provider.unreadCount()
    }

    var isConnected: Bool { !accounts.isEmpty }
    var canConnect: Bool { state != .unavailable }

    private func refreshAccounts() async {
        accounts = fixtureLabels.isEmpty ? await tokens.accounts() : fixtureLabels
        if state != .unavailable { state = accounts.isEmpty ? .signedOut : .signedIn }
        await refreshUnread()
    }

    /// Signs in one more mailbox and returns its address (nil if cancelled or refused).
    func connect() async -> String? {
        guard let client = GoogleConfig.clientID, let scheme = GoogleConfig.callbackScheme else { return nil }
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
                .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "select_account consent"),
            ]
            let callback = try await authorize(components.url!, scheme: scheme)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw ToolError(String(localized: "Gmail was not connected."))
            }
            let reply = try await GoogleTokens.post("https://oauth2.googleapis.com/token", [
                "client_id": client, "code": code, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code",
            ])
            let email = try await tokens.add(reply)
            await refreshAccounts()
            return email
        } catch {
            await refreshAccounts()
            state = .failed((error as? ToolError)?.message ?? String(localized: "Gmail was not connected."))
            return nil
        }
    }

    func disconnect(_ email: String) async {
        await tokens.signOut(email)
        await refreshAccounts()
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
