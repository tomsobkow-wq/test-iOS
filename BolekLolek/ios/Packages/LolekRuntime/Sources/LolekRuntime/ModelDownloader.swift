import CryptoKit
import Foundation

public enum ModelDownloadError: LocalizedError, Sendable {
    case notEnoughSpace(neededBytes: Int64, availableBytes: Int64)
    case badStatus(Int)
    case checksumMismatch
    case sizeMismatch(expected: Int64, got: Int64)

    public var errorDescription: String? {
        switch self {
        case let .notEnoughSpace(needed, available):
            "Not enough free space. Lolek needs about \(Self.gigabytes(needed)) GB and \(Self.gigabytes(available)) GB is free."
        case let .badStatus(code):
            "The download server answered with an error (\(code))."
        case .checksumMismatch:
            "The downloaded file did not match its fingerprint, so it was discarded. Try again."
        case let .sizeMismatch(expected, got):
            "The downloaded file has the wrong size (\(got) of \(expected) bytes)."
        }
    }

    private static func gigabytes(_ bytes: Int64) -> String { String(format: "%.1f", Double(bytes) / 1e9) }
}

public struct DownloadProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case downloading, verifying, finished }
    public let phase: Phase
    public let bytesReceived: Int64
    public let totalBytes: Int64

    public var fraction: Double { totalBytes > 0 ? min(1, Double(bytesReceived) / Double(totalBytes)) : 0 }
}

/// Downloads a model with resume support and checks its SHA-256 before it is allowed to run.
/// A stopped or failed download keeps its `.part` file and continues from there next time.
public final class ModelDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private var session: URLSession!
    private let queue = OperationQueue()

    // State of the single active download; touched only on `queue`.
    private var model: LocalModel?
    private var store: ModelStore?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var lastReport = Date.distantPast
    private var continuation: AsyncThrowingStream<DownloadProgress, Error>.Continuation?
    private var failure: Error?

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
        super.init()
        queue.maxConcurrentOperationCount = 1
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// Streams progress. The stream ends when the file is verified and in place, or throws.
    public func download(_ model: LocalModel, to store: ModelStore) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            queue.addOperation { [self] in
                if store.isInstalled(model) {
                    continuation.yield(DownloadProgress(phase: .finished, bytesReceived: model.sizeBytes, totalBytes: model.sizeBytes))
                    continuation.finish()
                    return
                }
                do {
                    try store.prepareDirectory()
                    let needed = model.sizeBytes - store.partialBytes(for: model)
                    let available = Self.availableBytes(at: store.directory)
                    // A little headroom so the phone is not left completely full.
                    guard available >= needed + 200_000_000 else {
                        throw ModelDownloadError.notEnoughSpace(neededBytes: needed, availableBytes: available)
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                self.model = model
                self.store = store
                self.continuation = continuation
                self.failure = nil
                self.received = 0

                var request = URLRequest(url: model.url)
                let existing = store.partialBytes(for: model)
                if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
                let task = session.dataTask(with: request)
                continuation.onTermination = { @Sendable _ in task.cancel() }
                task.resume()
            }
        }
    }

    // MARK: URLSessionDataDelegate (all on `queue`)

    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let model, let store, let http = response as? HTTPURLResponse else { return completionHandler(.cancel) }
        let partial = store.partialPath(for: model)
        switch http.statusCode {
        case 206:
            received = store.partialBytes(for: model)
        case 200:
            // Server ignored the Range header (or there was nothing to resume): start over.
            try? FileManager.default.removeItem(at: partial)
            received = 0
        case 416:
            // The partial file is already complete (or bigger than the file): verify what we have.
            received = store.partialBytes(for: model)
            return completionHandler(.cancel)
        default:
            failure = ModelDownloadError.badStatus(http.statusCode)
            return completionHandler(.cancel)
        }
        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        do {
            handle = try FileHandle(forWritingTo: partial)
            try handle?.seekToEnd()
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handle, let model else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = error
            dataTask.cancel()
            return
        }
        received += Int64(data.count)
        if Date().timeIntervalSince(lastReport) > 0.2 {
            lastReport = Date()
            continuation?.yield(DownloadProgress(phase: .downloading, bytesReceived: received, totalBytes: model.sizeBytes))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        guard let model, let store, let continuation else { return }
        defer {
            self.model = nil
            self.store = nil
            self.continuation = nil
        }
        if let failure {
            return continuation.finish(throwing: failure)
        }
        let http = task.response as? HTTPURLResponse
        if let error, http?.statusCode != 416 {
            // Keep the .part file so the next attempt resumes.
            return continuation.finish(throwing: error)
        }

        do {
            let partial = store.partialPath(for: model)
            let size = store.partialBytes(for: model)
            guard size == model.sizeBytes else {
                if size > model.sizeBytes { try? FileManager.default.removeItem(at: partial) }
                throw ModelDownloadError.sizeMismatch(expected: model.sizeBytes, got: size)
            }
            continuation.yield(DownloadProgress(phase: .verifying, bytesReceived: size, totalBytes: model.sizeBytes))
            guard try Self.sha256(of: partial) == model.sha256 else {
                try? FileManager.default.removeItem(at: partial)
                throw ModelDownloadError.checksumMismatch
            }
            let final = store.path(for: model)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: partial, to: final)
            try store.markVerified(model)
            continuation.yield(DownloadProgress(phase: .finished, bytesReceived: size, totalBytes: model.sizeBytes))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    // MARK: Helpers

    static func sha256(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func availableBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
