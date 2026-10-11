@testable import FluidVoice_Debug
import Foundation
import XCTest

/// Explicit, network-optional acceptance using only the repository's authored WAV.
/// No microphone, clipboard, credentials, vocabulary or shared profile are used.
@MainActor
final class DevelopmentSpeechFixtureTests: XCTestCase {
    func testWhisperTinyRepeatedFinalRecognition() async throws {
        try self.requireIsolatedAcceptance()
        let directory = AppStorage.applicationSupportFallback
            .appendingPathComponent("AuthoredSpeechAcceptance/WhisperModels", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let provider = WhisperProvider(
            modelDirectory: directory, modelOverride: .whisperTiny, languageCodeOverride: "en"
        )
        try self.requireDownloadPermissionIfNeeded(provider)
        try await self.recognizeFixtureTwice(provider)
    }

    #if arch(arm64)
    func testParakeetV2RepeatedFinalRecognition() async throws {
        try self.requireIsolatedAcceptance()
        let provider = FluidAudioProvider(modelOverride: .parakeetTDTv2, configureWordBoosting: false)
        try self.requireDownloadPermissionIfNeeded(provider)
        if !provider.modelsExistOnDisk() {
            let values = try AppStorage.applicationSupportFallback.resourceValues(
                forKeys: [.volumeAvailableCapacityKey]
            )
            guard (values.volumeAvailableCapacity ?? 0) >= 8_000_000_000 else {
                throw XCTSkip("Parakeet acceptance needs at least 8 GB free before downloading and loading Core ML models.")
            }
        }
        try await self.recognizeFixtureTwice(provider)
    }
    #endif

    private func requireIsolatedAcceptance() throws {
        guard ProcessInfo.processInfo.environment["SAYSTONE_RUN_AUTHORED_SPEECH_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Use the opt-in authored speech acceptance runner; ordinary tests never download models.")
        }
        guard AppStorage.isDevelopment, DevelopmentRuntime.isUITesting,
              Bundle.main.bundleIdentifier == AppStorage.developmentBundleIdentifier
        else {
            XCTFail("Authored acceptance requires the isolated Development product and synthetic startup.")
            throw CancellationError()
        }
        // Override only the synthetic suite. These options are also read during
        // final recognition, even when prepare-time vocabulary boosting is off.
        SettingsStore.shared.pronunciationMatchingEnabled = false
        SettingsStore.shared.customDictionaryEntries = []
    }

    private func requireDownloadPermissionIfNeeded(_ provider: any TranscriptionProvider) throws {
        guard provider.modelsExistOnDisk() ||
            ProcessInfo.processInfo.environment["SAYSTONE_ALLOW_AUTHORED_MODEL_DOWNLOAD"] == "1"
        else {
            throw XCTSkip("The isolated model cache is empty. Pass --download-models to opt in to downloading.")
        }
    }

    private func recognizeFixtureTwice(_ provider: any TranscriptionProvider) async throws {
        let preparationStart = Date()
        try await provider.prepare(progressHandler: nil)
        XCTAssertTrue(provider.isReady)
        XCTAssertTrue(provider.modelsExistOnDisk())
        let samples = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        XCTAssertFalse(samples.isEmpty)
        print("Authored speech acceptance: \(provider.name), prepared in \(Date().timeIntervalSince(preparationStart))s")
        var previousText: String?
        for pass in 1...2 {
            let start = Date()
            let result = try await provider.transcribeFinal(samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = text.lowercased()
            XCTAssertTrue(normalized.contains("hello"), "Expected authored phrase 'hello fluid voice'; got: \(text)")
            XCTAssertTrue(normalized.contains("fluid"), "Expected authored phrase 'hello fluid voice'; got: \(text)")
            XCTAssertTrue(
                normalized.contains("voice") || normalized.contains("boys"),
                "Expected 'voice' or the established tiny-model variant 'boys'; got: \(text)"
            )
            if let previousText {
                XCTAssertEqual(text, previousText, "A repeated final must reset recognition state without duplicating text.")
            }
            previousText = text
            print("Authored speech acceptance pass \(pass): '\(text)' in \(Date().timeIntervalSince(start))s")
        }
    }
}
