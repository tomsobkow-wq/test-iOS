import AgentCore
import Foundation

/// A model file Lolek can run: where to get it, how to check it, how to talk to it.
public struct LocalModel: Identifiable, Sendable, Equatable {
    public let id: String
    public let profile: ModelProfile
    public let promptStyle: PromptStyle
    public let fileName: String
    public let url: URL
    public let sizeBytes: Int64
    /// SHA-256 of the file, hex. Pinned: a download that does not match is thrown away.
    public let sha256: String

    public static func == (lhs: LocalModel, rhs: LocalModel) -> Bool { lhs.id == rhs.id }
}

public enum LocalModels {
    /// Qwen3.5 4B, Q4_K_M from unsloth. Chat template verified (XML tool calls, thinking off).
    public static let qwen35 = LocalModel(
        id: ModelProfile.qwen35_4B.id,
        profile: .qwen35_4B,
        promptStyle: .qwen35,
        fileName: "Qwen3.5-4B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!,
        sizeBytes: 2_740_937_888,
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"
    )

    public static let all = [qwen35]

    /// Whichever model `ModelCatalog.lolekDefault` points at. Changing the default there changes it here.
    public static var `default`: LocalModel {
        all.first { $0.id == ModelCatalog.lolekDefault.id } ?? qwen35
    }
}

/// Where downloaded models live. Excluded from iCloud backup: they can be fetched again.
public struct ModelStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BolekLolek/Models", isDirectory: true)
    }

    public func path(for model: LocalModel) -> URL { directory.appendingPathComponent(model.fileName) }
    public func partialPath(for model: LocalModel) -> URL { directory.appendingPathComponent(model.fileName + ".part") }
    private func markerPath(for model: LocalModel) -> URL { directory.appendingPathComponent(model.fileName + ".verified") }

    /// Installed means: the file is there, it has the right size, and it passed the SHA-256 check
    /// when it was downloaded (re-hashing 2.7 GB on every launch would be slow).
    public func isInstalled(_ model: LocalModel) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path(for: model).path)
        guard (attributes?[.size] as? NSNumber)?.int64Value == model.sizeBytes,
              let marker = try? String(contentsOf: markerPath(for: model), encoding: .utf8)
        else { return false }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines) == model.sha256
    }

    func markVerified(_ model: LocalModel) throws {
        try model.sha256.write(to: markerPath(for: model), atomically: true, encoding: .utf8)
    }

    public func partialBytes(for model: LocalModel) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: partialPath(for: model).path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func remove(_ model: LocalModel) {
        for url in [path(for: model), partialPath(for: model), markerPath(for: model)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try? mutable.setResourceValues(values)
    }
}
