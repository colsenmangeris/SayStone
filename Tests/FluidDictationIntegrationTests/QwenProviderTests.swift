@testable import FluidVoice_Debug
import XCTest

@MainActor
final class QwenProviderTests: XCTestCase {
    func testLocalModelTranscribesFixture() async throws {
        guard ProcessInfo.processInfo.environment["SAYSTONE_QWEN_TEST"] == "1" else {
            throw XCTSkip("Opt in with TEST_RUNNER_SAYSTONE_QWEN_TEST=1; downloads the local Qwen model.")
        }
        let samples = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        let provider = QwenTranscriptionProvider()
        try await provider.prepare(progressHandler: nil)
        XCTAssertTrue(provider.isReady)
        let result = try await provider.transcribe(samples)
        let text = result.text.lowercased()
        XCTAssertTrue(text.contains("hello"), "Expected hello in fixture transcript: \(text)")
        XCTAssertTrue(text.contains("voice"), "Expected voice in fixture transcript: \(text)")
        print("QWEN_FIXTURE_TRANSCRIPT: \(result.text)")
    }
}
