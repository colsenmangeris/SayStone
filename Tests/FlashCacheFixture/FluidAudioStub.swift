import AVFoundation
import CoreML
import Foundation

// A network-boundary double: the real provider must select the destination.
// Deliberately uses a different synthetic public default if `to:` is omitted.
public enum StreamingChunkSize: Sendable {
    case ms160, ms320, ms1280
    public var modelSubdirectory: String {
        switch self {
        case .ms160: return "160ms"
        case .ms320: return "320ms"
        case .ms1280: return "1280ms"
        }
    }
}

public enum Repo {
    case parakeetEou160, parakeetEou320, parakeetEou1280
    public var folderName: String {
        switch self {
        case .parakeetEou160: return "parakeet-realtime-eou-120m-coreml/160ms"
        case .parakeetEou320: return "parakeet-realtime-eou-120m-coreml/320ms"
        case .parakeetEou1280: return "parakeet-realtime-eou-120m-coreml/1280ms"
        }
    }
}

public enum ModelNames {
    public enum ParakeetEOU {
        public static let requiredModels: Set<String> = ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc", "vocab.json"]
    }
}

public enum DownloadUtils {
    public enum Phase { case listing, downloading, compiling }
    public struct Progress {
        public let phase: Phase
        public let fractionCompleted: Double
    }
}

public actor StreamingEouAsrManager {
    private let chunkSize: StreamingChunkSize
    public static var receivedDirectory: URL?
    public static var syntheticPublicDirectory: URL?

    public init(configuration: MLModelConfiguration, chunkSize: StreamingChunkSize) {
        self.chunkSize = chunkSize
    }

    public static func setSyntheticPublicDirectory(_ directory: URL) {
        self.syntheticPublicDirectory = directory
    }

    public func loadModelsFromHuggingFace(
        to directory: URL? = nil, progressHandler: ((DownloadUtils.Progress) -> Void)? = nil
    ) async throws {
        Self.receivedDirectory = directory
        guard let root = directory ?? Self.syntheticPublicDirectory else {
            throw NSError(domain: "FlashFixture", code: 1)
        }
        let repo: Repo
        switch self.chunkSize {
        case .ms160: repo = .parakeetEou160
        case .ms320: repo = .parakeetEou320
        case .ms1280: repo = .parakeetEou1280
        }
        let model = root.appendingPathComponent(repo.folderName)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        for file in ModelNames.ParakeetEOU.requiredModels {
            try Data("authored fake artifact".utf8).write(to: model.appendingPathComponent(file))
        }
    }

    public func appendAudio(_ buffer: AVAudioPCMBuffer) async throws {}
    public func processBufferedAudio() async throws {}
    public func getPartialTranscript() async -> String { "" }
    public func finish() async throws -> String { "" }
    public func reset() async {}
}
