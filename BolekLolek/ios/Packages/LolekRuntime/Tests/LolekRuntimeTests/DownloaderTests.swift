import AgentCore
import CryptoKit
import XCTest
@testable import LolekRuntime

/// A fake model server with Range support, so downloads can be tested without the network.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var ignoreRange = false
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.append(request)
        var body = Self.payload
        var code = Self.status
        if code == 200, !Self.ignoreRange, let range = request.value(forHTTPHeaderField: "Range"),
           let start = Int(range.replacingOccurrences(of: "bytes=", with: "").replacingOccurrences(of: "-", with: "")) {
            body = start >= body.count ? Data() : body.subdata(in: start..<body.count)
            code = start >= Self.payload.count ? 416 : 206
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var offset = 0
        while offset < body.count {
            let end = min(offset + 65_536, body.count)
            client?.urlProtocol(self, didLoad: body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class DownloaderTests: XCTestCase {
    private var directory: URL!
    private var payload: Data!
    private var model: LocalModel!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lolek-tests-\(UUID().uuidString)")
        payload = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) })
        StubServer.payload = payload
        StubServer.ignoreRange = false
        StubServer.status = 200
        StubServer.requests = []
        model = LocalModel(
            id: "test", profile: .qwen35_4B, promptStyle: .qwen35, fileName: "test.gguf",
            url: URL(string: "https://models.example/test.gguf")!,
            sizeBytes: Int64(payload.count),
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func downloader() -> ModelDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return ModelDownloader(configuration: configuration)
    }

    private func run(_ model: LocalModel, store: ModelStore) async throws -> [DownloadProgress] {
        var seen: [DownloadProgress] = []
        for try await progress in downloader().download(model, to: store) { seen.append(progress) }
        return seen
    }

    func testFreshDownloadIsVerifiedAndInstalled() async throws {
        let store = ModelStore(directory: directory)
        XCTAssertFalse(store.isInstalled(model))
        let seen = try await run(model, store: store)
        XCTAssertEqual(seen.last?.phase, .finished)
        XCTAssertTrue(seen.contains { $0.phase == .verifying })
        XCTAssertTrue(store.isInstalled(model))
        XCTAssertEqual(try Data(contentsOf: store.path(for: model)), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partialPath(for: model).path))
    }

    func testResumesFromPartialFile() async throws {
        let store = ModelStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try payload.prefix(1_000_000).write(to: store.partialPath(for: model))
        _ = try await run(model, store: store)
        XCTAssertEqual(StubServer.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=1000000-")
        XCTAssertTrue(store.isInstalled(model))
        XCTAssertEqual(try Data(contentsOf: store.path(for: model)), payload)
    }

    func testServerIgnoringRangeRestartsCleanly() async throws {
        StubServer.ignoreRange = true
        let store = ModelStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 500_000).write(to: store.partialPath(for: model))
        _ = try await run(model, store: store)
        XCTAssertTrue(store.isInstalled(model), "stale partial bytes must not end up in the file")
        XCTAssertEqual(try Data(contentsOf: store.path(for: model)), payload)
    }

    func testCorruptDownloadIsRejectedAndDeleted() async throws {
        var corrupted = payload!
        corrupted[1_234_567] ^= 0xFF
        StubServer.payload = corrupted
        let store = ModelStore(directory: directory)
        do {
            _ = try await run(model, store: store)
            XCTFail("expected a checksum error")
        } catch {
            XCTAssertTrue(error is ModelDownloadError)
            XCTAssertTrue(error.localizedDescription.contains("fingerprint"))
        }
        XCTAssertFalse(store.isInstalled(model))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path(for: model).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partialPath(for: model).path))
    }

    func testServerErrorSurfaces() async {
        StubServer.status = 404
        let store = ModelStore(directory: directory)
        do {
            _ = try await run(model, store: store)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"))
        }
        XCTAssertFalse(store.isInstalled(model))
    }

    func testAlreadyInstalledSkipsNetwork() async throws {
        let store = ModelStore(directory: directory)
        _ = try await run(model, store: store)
        StubServer.requests = []
        let seen = try await run(model, store: store)
        XCTAssertEqual(seen.last?.phase, .finished)
        XCTAssertTrue(StubServer.requests.isEmpty)
    }

    func testTamperedFileIsNotTreatedAsInstalled() async throws {
        let store = ModelStore(directory: directory)
        _ = try await run(model, store: store)
        try Data(payload.prefix(10)).write(to: store.path(for: model))
        XCTAssertFalse(store.isInstalled(model), "wrong size must fail the install check")
    }

    func testCatalogPinsAreWellFormed() {
        for model in LocalModels.all {
            XCTAssertEqual(model.sha256.count, 64, model.id)
            XCTAssertTrue(model.sha256.allSatisfy { $0.isHexDigit }, model.id)
            XCTAssertGreaterThan(model.sizeBytes, 2_000_000_000, model.id)
            XCTAssertEqual(model.url.scheme, "https")
            XCTAssertTrue(model.fileName.hasSuffix(".gguf"))
        }
        XCTAssertEqual(LocalModels.default.id, ModelCatalog.lolekDefault.id)
    }
}

final class ContextTrimTests: XCTestCase {
    func testDropsOldestExchangeFirstAndKeepsCurrentTurn() {
        let messages = [
            ChatMessage(role: .user, text: "1"), ChatMessage(role: .assistant, text: "a1"),
            ChatMessage(role: .user, text: "2"), ChatMessage(role: .assistant, text: "a2"),
            ChatMessage(role: .user, text: "3"),
        ]
        XCTAssertEqual(LlamaCppProvider.firstDroppableTurnEnd(in: messages), 2)
        XCTAssertEqual(LlamaCppProvider.firstDroppableTurnEnd(in: Array(messages[2...])), 2)
        XCTAssertNil(LlamaCppProvider.firstDroppableTurnEnd(in: Array(messages[4...])), "only the current turn is left")
        XCTAssertNil(LlamaCppProvider.firstDroppableTurnEnd(in: []))
    }
}
