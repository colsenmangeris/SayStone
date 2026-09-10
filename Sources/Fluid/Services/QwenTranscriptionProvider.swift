import Foundation
#if arch(arm64) && canImport(Qwen3ASR)
import Qwen3ASR
#endif

/// Local Qwen inference. Uses the ASR service's serialized transcription executor.
final class QwenTranscriptionProvider: TranscriptionProvider {
    static let modelID = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    static var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SayStone/Models/Qwen3-ASR-0.6B-MLX-4bit")
    }
    static var cached: Bool {
        let files = ["config.json", "model.safetensors", "vocab.json", "merges.txt", "tokenizer_config.json"]
        return files.allSatisfy { FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent($0).path) }
    }
    let name = "Qwen3-ASR 0.6B (Local MLX)"
    var isAvailable: Bool {
        #if arch(arm64) && canImport(Qwen3ASR)
        return true
        #else
        return false
        #endif
    }
    private(set) var isReady = false
    var shouldClearCacheAfterCancellation: Bool { false }
    #if arch(arm64) && canImport(Qwen3ASR)
    private var model: Qwen3ASRModel?
    #endif

    func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {
        guard !isReady else { return }
        try Task.checkCancellation()
        #if arch(arm64) && canImport(Qwen3ASR)
        progressHandler?(.preparingDownload)
        let loaded = try await Qwen3ASRModel.fromPretrained(
            modelId: Self.modelID, cacheDir: Self.cacheDirectory,
            progressHandler: { fraction, _ in progressHandler?(.downloading(fraction)) }
        )
        try Task.checkCancellation()
        model = loaded
        isReady = true
        #else
        throw failure("Qwen requires Apple Silicon and the local Qwen runtime.")
        #endif
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try Task.checkCancellation()
        guard !samples.isEmpty else { return ASRTranscriptionResult(text: "") }
        #if arch(arm64) && canImport(Qwen3ASR)
        guard let model, isReady else { throw failure("Qwen is not loaded.") }
        // Keep audio windows within the model's supported 30-second input.
        // Final-only mode avoids re-running this autoregressive model on every partial.
        let window = 25 * 16_000
        var parts: [String] = []
        for offset in stride(from: 0, to: samples.count, by: window) {
            try Task.checkCancellation()
            let chunk = Array(samples[offset..<min(offset + window, samples.count)])
            let text = model.transcribe(audio: chunk, sampleRate: 16_000, language: nil, maxTokens: 1024)
            try Task.checkCancellation()
            guard !text.contains("Text decoder not loaded") else { throw failure("Qwen's text decoder did not load.") }
            if !text.isEmpty { parts.append(text) }
        }
        return ASRTranscriptionResult(text: parts.joined(separator: " "), confidence: 0)
        #else
        throw failure("Qwen is unavailable on this device.")
        #endif
    }

    func modelsExistOnDisk() -> Bool { Self.cached }
    func clearCache() async throws {
        #if arch(arm64) && canImport(Qwen3ASR)
        model = nil
        #endif
        isReady = false
        if FileManager.default.fileExists(atPath: Self.cacheDirectory.path) {
            try FileManager.default.removeItem(at: Self.cacheDirectory)
        }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "SayStone.Qwen", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
