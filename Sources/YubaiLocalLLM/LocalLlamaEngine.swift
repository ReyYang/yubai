import Foundation
import LlamaSwift
import YubaiCore

/// Thin Metal-first GGUF runner wrapping llama.cpp C API (via LlamaSwift / official XCFramework).
/// Not Sendable across actors: all calls go through `LocalLlamaRegistry`.
public final class LocalLlamaEngine: @unchecked Sendable {
    public enum EngineError: LocalizedError {
        case modelLoadFailed(String)
        case contextInitFailed
        case tokenizeFailed
        case decodeFailed
        case emptyGeneration

        public var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let path): return "无法加载本机模型：\(path)"
            case .contextInitFailed: return "本机模型上下文初始化失败。"
            case .tokenizeFailed: return "本机模型分词失败。"
            case .decodeFailed: return "本机模型推理失败。"
            case .emptyGeneration: return "本机模型未返回有效文本。"
            }
        }
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let modelPath: String
    private let contextLength: UInt32
    private let lock = NSLock()

    public init(modelPath: String, contextLength: UInt32 = 2048, gpuLayers: Int32 = 99) throws {
        self.modelPath = modelPath
        self.contextLength = contextLength
        llama_backend_init()

        var modelParams = llama_model_default_params()
        // Metal prefer; large value offloads as many layers as the device allows.
        modelParams.n_gpu_layers = gpuLayers
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            throw EngineError.modelLoadFailed(modelPath)
        }
        self.model = model
        self.vocab = llama_model_get_vocab(model)

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextLength
        ctxParams.n_batch = 512
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        ctxParams.n_threads = Int32(threads)
        ctxParams.n_threads_batch = Int32(threads)
        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw EngineError.contextInitFailed
        }
        self.context = context
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
        // Do not call llama_backend_free here: other sessions may still be alive.
    }

    public func complete(system: String, user: String, temperature: Float, maxTokens: Int) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        llama_memory_clear(llama_get_memory(context), true)

        let prompt = try formatChat(system: system, user: user)
        var tokens = try tokenize(prompt, addSpecial: true, parseSpecial: true)
        guard !tokens.isEmpty else { throw EngineError.tokenizeFailed }

        let batchResult = tokens.withUnsafeMutableBufferPointer { buf -> Int32 in
            llama_decode(context, llama_batch_get_one(buf.baseAddress, Int32(buf.count)))
        }
        guard batchResult == 0 else { throw EngineError.decodeFailed }

        let sampler = makeSampler(temperature: temperature)
        defer { llama_sampler_free(sampler) }

        var pending: [UInt8] = []
        var pieces: [String] = []
        var rc: Int32 = 0
        for _ in 0..<max(1, maxTokens) {
            guard rc == 0 else { break }
            var next = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, next) { break }

            pending += pieceBytes(next)
            if let text = String(bytes: pending, encoding: .utf8) {
                pieces.append(text)
                pending.removeAll(keepingCapacity: true)
            }
            rc = withUnsafeMutablePointer(to: &next) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
        }

        let joined = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw EngineError.emptyGeneration }
        return joined
    }

    private func makeSampler(temperature: Float) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if temperature <= 0.01 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))
        }
        return chain
    }

    private func formatChat(system: String, user: String) throws -> String {
        // Keep CStrings alive for the duration of apply_template.
        return try system.withCString { systemC in
            try user.withCString { userC in
                try "system".withCString { systemRole in
                    try "user".withCString { userRole in
                        let messages = [
                            llama_chat_message(role: systemRole, content: systemC),
                            llama_chat_message(role: userRole, content: userC)
                        ]
                        let tmpl = llama_model_chat_template(model, nil)
                        let alloc = max(1024, (system.utf8.count + user.utf8.count) * 2 + 256)
                        var buffer = [CChar](repeating: 0, count: alloc)
                        let written = messages.withUnsafeBufferPointer { ptr in
                            llama_chat_apply_template(
                                tmpl,
                                ptr.baseAddress,
                                ptr.count,
                                true,
                                &buffer,
                                Int32(buffer.count)
                            )
                        }
                        if written < 0 {
                            // Fallback: ChatML (Qwen2.5 Instruct)
                            return """
                            <|im_start|>system
                            \(system)<|im_end|>
                            <|im_start|>user
                            \(user)<|im_end|>
                            <|im_start|>assistant

                            """
                        }
                        if Int(written) > buffer.count {
                            buffer = [CChar](repeating: 0, count: Int(written) + 1)
                            let again = messages.withUnsafeBufferPointer { ptr in
                                llama_chat_apply_template(
                                    tmpl,
                                    ptr.baseAddress,
                                    ptr.count,
                                    true,
                                    &buffer,
                                    Int32(buffer.count)
                                )
                            }
                            guard again > 0 else { throw EngineError.tokenizeFailed }
                        }
                        return String(cString: buffer)
                    }
                }
            }
        }
    }

    private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) throws -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var capacity = utf8Count + 8
        var tokens = [llama_token](repeating: 0, count: Int(capacity))
        let n = text.withCString { cstr in
            llama_tokenize(vocab, cstr, utf8Count, &tokens, capacity, addSpecial, parseSpecial)
        }
        if n < 0 {
            capacity = -n
            tokens = [llama_token](repeating: 0, count: Int(capacity))
            let again = text.withCString { cstr in
                llama_tokenize(vocab, cstr, utf8Count, &tokens, capacity, addSpecial, parseSpecial)
            }
            guard again > 0 else { throw EngineError.tokenizeFailed }
            return Array(tokens.prefix(Int(again)))
        }
        guard n > 0 else { throw EngineError.tokenizeFailed }
        return Array(tokens.prefix(Int(n)))
    }

    private func pieceBytes(_ token: llama_token) -> [UInt8] {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        guard n > 0 else { return [] }
        return buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }
    }
}

/// Process-wide loaded GGUF session. Sync API avoids MainActor + semaphore deadlocks in UI routing.
public enum LocalLlamaRegistry {
    private static let lock = NSLock()
    private static var engine: LocalLlamaEngine?
    private static var loadedPath: String?

    /// Load (or reuse) a Metal-backed engine for `modelPath`.
    public static func inference(at modelPath: String) throws -> LocalLlamaInferenceAdapter {
        lock.lock()
        defer { lock.unlock() }
        if loadedPath == modelPath, let engine {
            return LocalLlamaInferenceAdapter(engine: engine)
        }
        let next = try LocalLlamaEngine(modelPath: modelPath)
        engine = next
        loadedPath = modelPath
        return LocalLlamaInferenceAdapter(engine: next)
    }

    public static func unload() {
        lock.lock()
        engine = nil
        loadedPath = nil
        lock.unlock()
    }
}

/// Bridges `LocalLlamaEngine` to `YubaiCore.LocalGGUFInference` (async, Sendable).
public struct LocalLlamaInferenceAdapter: LocalGGUFInference {
    private let engine: LocalLlamaEngine

    public init(engine: LocalLlamaEngine) {
        self.engine = engine
    }

    public func complete(system: String, user: String, temperature: Float, maxTokens: Int) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try engine.complete(system: system, user: user, temperature: temperature, maxTokens: maxTokens)
        }.value
    }
}
