import Foundation
#if canImport(llama)
import llama
#endif

public enum LlamaEngineError: LocalizedError, Sendable {
    case unavailable
    case modelLoadFailed(String)
    case contextFailed
    case promptTooLong(tokens: Int, limit: Int)
    case decodeFailed(Int32)
    case tokenizeFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable: "On-device models are not available on this platform (the iOS Simulator has no Metal GPU support for llama.cpp builds here)."
        case let .modelLoadFailed(path): "Could not load the model at \(path)."
        case .contextFailed: "Could not allocate memory for the model."
        case let .promptTooLong(tokens, limit): "The conversation is too long for Lolek (\(tokens) of \(limit) tokens)."
        case let .decodeFailed(code): "The model stopped with an error (\(code))."
        case .tokenizeFailed: "Could not read the text."
        }
    }
}

public struct GenerationStats: Sendable, Equatable {
    public var promptTokens = 0
    /// Tokens served from the previous turn's cache instead of being read again.
    public var reusedTokens = 0
    public var generatedTokens = 0
    public var prefillSeconds = 0.0
    /// Tokens restored from a saved checkpoint (hybrid models cannot rewind their live memory).
    public var checkpointTokens = 0
    public var checkpointBytes = 0
    public var generationSeconds = 0.0
    /// Debug aid: a checksum and size of the fixed header (instructions and tools) this call used, to see when it changed.
    public var headerChecksum: UInt32 = 0
    public var headerCharacters = 0
    public var tokensPerSecond: Double { generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0 }
}

public struct EngineSettings: Sendable {
    public var contextTokens = 8_192
    public var batchTokens = 512
    /// Layers on the GPU. 999 = all of them (Metal).
    public var gpuLayers: Int32 = 999
    public var threads: Int32 = Int32(max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))

    public init() {}
}

#if canImport(llama)

/// A loaded model plus its context. All llama.cpp calls run on one serial queue.
public final class LlamaEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.boleklolek.llama", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private let settings: EngineSettings
    /// Tokens currently in the KV cache, so the next turn only reads what changed.
    private var cachedTokens: [Int32] = []

    /// Hybrid and recurrent models (Qwen3.5) cannot drop just the tail of their memory, so the
    /// plain "keep the common prefix" trick does not work. Instead we save the memory state at the
    /// end of each prompt body and restore the best match, which is what llama.cpp's server does.
    private struct Checkpoint {
        let tokens: [Int32]
        let state: [UInt8]
        /// The fixed header (instructions and tools) is shared by every conversation, so it is kept for good.
        /// Conversation snapshots are rotated.
        let pinned: Bool
    }
    private var checkpoints: [Checkpoint] = []
    private static let maxConversationCheckpoints = 2
    private static let maxPinnedCheckpoints = 2
    private var needsCheckpoints = false

    private static let backendReady: Void = {
        llama_backend_init()
        // Only errors; the default is very chatty.
        llama_log_set({ level, text, _ in
            if level == GGML_LOG_LEVEL_ERROR, let text { fputs(String(cString: text), stderr) }
        }, nil)
    }()

    public init(modelPath: String, settings: EngineSettings = EngineSettings()) async throws {
        self.settings = settings
        _ = Self.backendReady
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                var modelParams = llama_model_default_params()
                modelParams.n_gpu_layers = settings.gpuLayers
                guard let model = llama_model_load_from_file(modelPath, modelParams) else {
                    return continuation.resume(throwing: LlamaEngineError.modelLoadFailed(modelPath))
                }
                var contextParams = llama_context_default_params()
                contextParams.n_ctx = UInt32(settings.contextTokens)
                contextParams.n_batch = UInt32(settings.batchTokens)
                contextParams.n_ubatch = UInt32(settings.batchTokens)
                contextParams.n_threads = settings.threads
                contextParams.n_threads_batch = settings.threads
                contextParams.no_perf = true
                guard let context = llama_init_from_model(model, contextParams) else {
                    llama_model_free(model)
                    return continuation.resume(throwing: LlamaEngineError.contextFailed)
                }
                self.model = model
                self.context = context
                self.vocab = llama_model_get_vocab(model)
                self.needsCheckpoints = llama_model_is_recurrent(model) || llama_model_is_hybrid(model)
                continuation.resume()
            }
        }
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    /// How many tokens `text` takes. Special tokens such as `<|im_start|>` are recognised.
    public func tokenCount(_ text: String) async throws -> Int {
        try await onQueue { try self.tokenize(text).count }
    }

    /// Writes an answer for `prompt`, calling `onText` with each new piece. Return `false` from it to stop.
    ///
    /// `prompt` is the stable part (conversation so far); `suffix` is what opens the assistant's turn.
    /// The model's memory is checkpointed between the two so the next step can resume from there.
    public func generate(
        header: String = "",
        prompt: String,
        suffix: String = "",
        maxTokens: Int,
        temperature: Float,
        topP: Float = 0.9,
        onText: @escaping @Sendable (String) -> Bool
    ) async throws -> (text: String, stats: GenerationStats) {
        try await onQueue {
            try self.generateSync(header: header, prompt: prompt, suffix: suffix, maxTokens: maxTokens, temperature: temperature, topP: topP, onText: onText)
        }
    }

    /// Forget the cached conversation (for example after the model was swapped).
    public func resetCache() async {
        try? await onQueue {
            self.cachedTokens = []
            self.checkpoints = []
            if let memory = llama_get_memory(self.context) { llama_memory_clear(memory, true) }
        }
    }

    // MARK: - Implementation (always on `queue`)

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func tokenize(_ text: String) throws -> [Int32] {
        let utf8Count = Int32(text.utf8.count)
        // First call with no buffer returns the negative of the number of tokens needed.
        let needed = -llama_tokenize(vocab, text, utf8Count, nil, 0, false, true)
        guard needed > 0 else { return [] }
        var tokens = [Int32](repeating: 0, count: Int(needed))
        let written = llama_tokenize(vocab, text, utf8Count, &tokens, needed, false, true)
        guard written >= 0 else { throw LlamaEngineError.tokenizeFailed }
        return Array(tokens.prefix(Int(written)))
    }

    private func pieceBytes(_ token: Int32) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, 256, 0, false)
        guard length > 0 else { return [] }
        return buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    }

    private func commonPrefix(_ a: [Int32], _ b: [Int32]) -> Int {
        var n = 0
        while n < min(a.count, b.count), a[n] == b[n] { n += 1 }
        return n
    }

    private func decode(_ tokens: ArraySlice<Int32>, memory: OpaquePointer) throws {
        var offset = tokens.startIndex
        while offset < tokens.endIndex {
            let count = min(settings.batchTokens, tokens.endIndex - offset)
            var chunk = Array(tokens[offset..<offset + count])
            let result = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(count)))
            }
            guard result == 0 else {
                cachedTokens = []
                llama_memory_clear(memory, true)
                throw LlamaEngineError.decodeFailed(result)
            }
            cachedTokens += chunk
            offset += count
        }
    }

    private func saveCheckpoint(upTo tokens: [Int32], pinned: Bool, stats: inout GenerationStats) {
        let size = llama_state_seq_get_size(context, 0)
        guard size > 0 else { return }
        var state = [UInt8](repeating: 0, count: size)
        guard llama_state_seq_get_data(context, &state, size, 0) == size else { return }
        checkpoints.removeAll { $0.tokens == tokens }
        checkpoints.append(Checkpoint(tokens: tokens, state: state, pinned: pinned))
        // Rotate the oldest of each kind; the header snapshot never falls out because of conversation traffic.
        for (isPinned, limit) in [(true, Self.maxPinnedCheckpoints), (false, Self.maxConversationCheckpoints)] {
            while checkpoints.filter({ $0.pinned == isPinned }).count > limit, let oldest = checkpoints.firstIndex(where: { $0.pinned == isPinned }) {
                checkpoints.remove(at: oldest)
            }
        }
        stats.checkpointBytes = size
    }

    private func generateSync(
        header: String, prompt: String, suffix: String, maxTokens: Int, temperature: Float, topP: Float, onText: @Sendable (String) -> Bool
    ) throws -> (text: String, stats: GenerationStats) {
        guard let context, let vocab else { throw LlamaEngineError.unavailable }
        var stats = GenerationStats()
        // Tokenised apart: the suffix starts with a special token, so the seam is clean.
        let headerTokens = header.isEmpty ? [] : try tokenize(header)
        let bodyTokens = headerTokens + (prompt.isEmpty ? [] : try tokenize(prompt))
        let tokens = bodyTokens + (suffix.isEmpty ? [] : try tokenize(suffix))
        stats.promptTokens = tokens.count
        guard !tokens.isEmpty else { throw LlamaEngineError.tokenizeFailed }
        guard tokens.count + maxTokens <= settings.contextTokens else {
            throw LlamaEngineError.promptTooLong(tokens: tokens.count + maxTokens, limit: settings.contextTokens)
        }

        guard let memory = llama_get_memory(context) else { throw LlamaEngineError.contextFailed }

        // 1. Find the cheapest way to get the model's memory to "this prompt minus what is new".
        var common = commonPrefix(cachedTokens, tokens)
        if common == tokens.count { common -= 1 } // the last token must be decoded to get logits
        if common < cachedTokens.count {
            let rewound = !needsCheckpoints && common > 0 && llama_memory_seq_rm(memory, 0, Int32(common), -1)
            if rewound {
                cachedTokens = Array(cachedTokens.prefix(common))
            } else if let checkpoint = checkpoints
                .filter({ $0.tokens.count < tokens.count && commonPrefix($0.tokens, tokens) == $0.tokens.count })
                .max(by: { $0.tokens.count < $1.tokens.count }) {
                llama_memory_clear(memory, true)
                let restored = checkpoint.state.withUnsafeBufferPointer { llama_state_seq_set_data(context, $0.baseAddress, $0.count, 0) }
                if restored > 0 {
                    cachedTokens = checkpoint.tokens
                    common = checkpoint.tokens.count
                    stats.checkpointTokens = common
                } else {
                    llama_memory_clear(memory, true)
                    cachedTokens = []
                    common = 0
                }
            } else {
                llama_memory_clear(memory, true)
                cachedTokens = []
                common = 0
            }
        }
        stats.reusedTokens = common

        // 2. Read the new part of the body, checkpoint, then read the suffix.
        let prefillStart = Date()
        if needsCheckpoints {
            // Save the memory at the end of the fixed header and of the conversation body.
            var position = common
            for boundary in [headerTokens.count, bodyTokens.count] where boundary > position && boundary > 0 && (boundary < tokens.count || suffix.isEmpty) {
                try decode(tokens[position..<boundary], memory: memory)
                saveCheckpoint(upTo: Array(tokens[..<boundary]), pinned: boundary == headerTokens.count && !headerTokens.isEmpty, stats: &stats)
                position = boundary
            }
            if position < tokens.count { try decode(tokens[position...], memory: memory) }
        } else {
            try decode(tokens[common...], memory: memory)
        }
        stats.prefillSeconds = Date().timeIntervalSince(prefillStart)

        // Sampling: temperature 0 means greedy, which is what tool calls want.
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(sampler) }
        if temperature <= 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(topP, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        }

        var output = ""
        var pending: [UInt8] = []
        let generationStart = Date()
        var generated = 0
        generation: while generated < maxTokens {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            generated += 1

            // A character can be split across tokens; only emit complete UTF-8.
            pending += pieceBytes(token)
            if let text = String(bytes: pending, encoding: .utf8) {
                pending = []
                output += text
                if !text.isEmpty, !onText(text) { break generation }
            } else if pending.count >= 8 {
                let text = String(decoding: pending, as: UTF8.self)
                pending = []
                output += text
                if !onText(text) { break generation }
            }

            let result = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard result == 0 else {
                cachedTokens = []
                llama_memory_clear(memory, true)
                throw LlamaEngineError.decodeFailed(result)
            }
            cachedTokens.append(token)
        }
        stats.generatedTokens = generated
        stats.generationSeconds = Date().timeIntervalSince(generationStart)
        return (output, stats)
    }
}

#else

/// Stand-in where the llama.cpp framework has no build (the iOS Simulator until the local
/// xcframework is built, see Tools/build-llama-xcframework.sh). It always reports "unavailable".
public final class LlamaEngine: @unchecked Sendable {
    public init(modelPath: String, settings: EngineSettings = EngineSettings()) async throws {
        throw LlamaEngineError.unavailable
    }

    public func tokenCount(_ text: String) async throws -> Int { throw LlamaEngineError.unavailable }

    public func generate(
        header: String = "", prompt: String, suffix: String = "", maxTokens: Int, temperature: Float, topP: Float = 0.9,
        onText: @escaping @Sendable (String) -> Bool
    ) async throws -> (text: String, stats: GenerationStats) {
        throw LlamaEngineError.unavailable
    }

    public func resetCache() async {}
}

#endif
