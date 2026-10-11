import FluidAudio
import Foundation

enum AppStorage {
    static var applicationSupportFallback: URL { URL(fileURLWithPath: CommandLine.arguments[1]) }
    static func urls(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask) -> [URL] {
        [self.applicationSupportFallback]
    }
}

struct PronunciationEnrollmentCapture {}
final class DebugLogger {
    static let shared = DebugLogger()
    func info(_ message: String, source: String) {}
    func warning(_ message: String, source: String) {}
    func debug(_ message: String, source: String) {}
    func error(_ message: String, source: String) {}
}
enum HuggingFaceModelDownloader {
    static func artifactIsComplete(at url: URL, isDirectory: Bool) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

@main
struct FlashCacheFixture {
    @MainActor static func main() async throws {
        let root = AppStorage.applicationSupportFallback
        let publicRoot = root.appendingPathComponent("synthetic-public")
        StreamingEouAsrManager.setSyntheticPublicDirectory(publicRoot)
        let expected = root.appendingPathComponent("FluidAudio/Models/parakeet-eou-streaming")
        let chunks: [StreamingChunkSize] = [.ms160, .ms320, .ms1280]
        for chunk in chunks {
            let provider = ParakeetRealtimeProvider(chunkSize: chunk)
            precondition(!provider.modelsExistOnDisk())
            try await provider.prepare()
            let received = StreamingEouAsrManager.receivedDirectory
            precondition(received?.standardizedFileURL.path == expected.standardizedFileURL.path, "The SDK download must receive the app-selected cache root")
            precondition(provider.isReady && provider.modelsExistOnDisk())
            precondition(!FileManager.default.fileExists(atPath: publicRoot.path))
            try await provider.clearCache()
            precondition(!provider.isReady && !provider.modelsExistOnDisk())
        }
        print("PASS Flash provider: explicit isolated SDK destination, three chunk variants, readiness and clear-cache")
    }
}
