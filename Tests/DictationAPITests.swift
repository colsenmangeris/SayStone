import Foundation

/// Focused standalone tests for the loopback-only `POST /v1/dictate` route.
///
/// Compile with the Foundation-only core files plus the shared pipeline. These
/// tests never touch AppKit, `SettingsStore`, audio capture, ASR models, or the
/// network.
@main
struct DictationAPITests {
    static func main() async {
        await Self.runAll()
        print("PASS: dictation API request id, busy, size cap, temp cleanup, one-pass pipeline, and schema")
    }

    @MainActor
    static func runAll() async {
        await self.testRequestIDHonoredWhenValid()
        await self.testRequestIDGeneratedWhenInvalidOrMissing()
        await self.testBusyRejectionPrecedesDecodeAndTranscription()
        await self.testSizeCapRejection()
        await self.testTemporaryFileRemovedOnSuccessAndFailure()
        await self.testEnhancementPlanSelectionPolicy()
        await self.testGuardedCleanupAndFormattingRunExactlyOnce()
        await self.testUnsupportedProviderReportedWithoutDuplication()
        await self.testJSONBodyPathUsesBase64Audio()
        await self.testResponseSchema()
    }

    // MARK: - Fixtures

    @MainActor
    private static func makeOptions(
        localCleanupSelected: Bool = false,
        removeTrailingPeriod: Bool = true,
        lowercaseFirstLetter: Bool = false
    ) -> SharedDictationPipeline.Options {
        SharedDictationPipeline.Options(
            filler: SharedDictationPipeline.FillerOptions(isEnabled: false, words: []),
            dictionary: SharedDictationPipeline.DictionaryOptions(entries: []),
            spokenPunctuation: .disabled,
            localCleanup: localCleanupSelected
                ? SharedDictationPipeline.LocalCleanupSelection(
                    isSelected: true,
                    providerKey: "ollama",
                    model: LocalPunctuationCleanup.model
                )
                : .disabled,
            literalFormatting: .disabled,
            gaav: SharedDictationPipeline.GAAVOptions(
                removeTrailingPeriod: removeTrailingPeriod,
                lowercaseFirstLetter: lowercaseFirstLetter
            ),
            continuous: .disabled
        )
    }

    @MainActor
    private static func makeRequest(
        method: String = "POST",
        path: String = "/v1/dictate",
        headers: [String: String] = [:],
        body: Data = Data("wav-bytes".utf8)
    ) -> LocalAPI.Request {
        LocalAPI.Request(method: method, path: path, query: [:], headers: headers, body: body)
    }

    @MainActor
    private static func makeDependencies(
        isBusy: @escaping @MainActor () -> Bool = { false },
        writeTemporaryFile: @escaping @MainActor (Data, String) async throws -> URL = { data, fileExtension in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation-api-test-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            try data.write(to: url)
            return url
        },
        removeTemporaryFile: @escaping @MainActor (URL) async -> Void = { url in
            try? FileManager.default.removeItem(at: url)
        },
        transcribe: @escaping @MainActor (URL) async throws -> DictationAPI.RecognitionResult = { _ in
            DictationAPI.RecognitionResult(rawText: "hello", confidence: 0.9, sampleCount: 16_000)
        },
        options: SharedDictationPipeline.Options? = nil,
        enhancementPlan: DictationAPI.EnhancementPlan = .none,
        cleaner: @escaping @Sendable (String) async -> String? = { _ in nil },
        engineIdentity: EngineIdentity = .unknown(saystoneBuild: "test-build"),
        makeRequestID: @escaping @MainActor () -> String = { "generated-request-id" }
    ) -> DictationAPI.Dependencies {
        DictationAPI.Dependencies(
            isASRBusy: isBusy,
            writeTemporaryFile: writeTemporaryFile,
            removeTemporaryFile: removeTemporaryFile,
            transcribe: transcribe,
            pipelineOptions: { options ?? self.makeOptions() },
            enhancementPlan: { enhancementPlan },
            cleaner: cleaner,
            engineIdentity: { engineIdentity },
            makeRequestID: makeRequestID
        )
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        precondition(actual == expected, "\(label): expected \(expected), got \(actual)")
    }

    @MainActor
    private static func decodeBody(_ response: LocalAPI.Response) -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] else {
            preconditionFailure("response body was not a JSON object")
        }
        return object
    }

    // MARK: - Tests

    @MainActor
    private static func testRequestIDHonoredWhenValid() async {
        let resolved = DictationAPI.resolveRequestID("phone-abc:123", make: { "generated" })
        self.assertEqual(resolved, "phone-abc:123", "valid x-request-id is honored")

        let response = await DictationAPI.handle(
            self.makeRequest(headers: ["x-request-id": "phone-abc:123"]),
            dependencies: self.makeDependencies()
        )
        let body = self.decodeBody(response)
        self.assertEqual(body["requestId"] as? String, "phone-abc:123", "response echoes honored request id")
    }

    @MainActor
    private static func testRequestIDGeneratedWhenInvalidOrMissing() async {
        self.assertEqual(
            DictationAPI.resolveRequestID(nil, make: { "generated" }),
            "generated",
            "missing x-request-id generates one"
        )
        self.assertEqual(
            DictationAPI.resolveRequestID("", make: { "generated" }),
            "generated",
            "empty x-request-id generates one"
        )
        self.assertEqual(
            DictationAPI.resolveRequestID("bad id", make: { "generated" }),
            "generated",
            "whitespace in x-request-id generates one"
        )
        self.assertEqual(
            DictationAPI.resolveRequestID("bad\nid", make: { "generated" }),
            "generated",
            "control characters in x-request-id generate one"
        )
        self.assertEqual(
            DictationAPI.resolveRequestID(String(repeating: "a", count: 129), make: { "generated" }),
            "generated",
            "over-long x-request-id generates one"
        )
    }

    @MainActor
    private static func testBusyRejectionPrecedesDecodeAndTranscription() async {
        final class Recorder {
            var wroteTemp = false
            var transcribed = false
        }
        let recorder = Recorder()

        let dependencies = self.makeDependencies(
            isBusy: { true },
            writeTemporaryFile: { data, fileExtension in
                recorder.wroteTemp = true
                return FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)
            },
            transcribe: { _ in
                recorder.transcribed = true
                return DictationAPI.RecognitionResult(rawText: "x", confidence: 1, sampleCount: 1)
            }
        )

        let response = await DictationAPI.handle(self.makeRequest(), dependencies: dependencies)
        self.assertEqual(response.status, 409, "busy request status")
        self.assertEqual(recorder.wroteTemp, false, "busy request must not decode/write audio")
        self.assertEqual(recorder.transcribed, false, "busy request must not transcribe")

        let body = self.decodeBody(response)
        self.assertEqual(body["code"] as? String, "busy", "stable busy code")
        precondition((body["error"] as? String)?.contains("desktop microphone capture") == true, "busy message")
    }

    @MainActor
    private static func testSizeCapRejection() async {
        final class Recorder {
            var wroteTemp = false
            var transcribed = false
        }
        let recorder = Recorder()
        let dependencies = self.makeDependencies(
            writeTemporaryFile: { data, fileExtension in
                recorder.wroteTemp = true
                return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)
            },
            transcribe: { _ in
                recorder.transcribed = true
                return DictationAPI.RecognitionResult(rawText: "x", confidence: 1, sampleCount: 1)
            }
        )

        let oversized = Data(repeating: 0xAB, count: DictationAPI.maxRequestBytes + 1)
        let response = await DictationAPI.handle(self.makeRequest(body: oversized), dependencies: dependencies)
        self.assertEqual(response.status, 413, "oversized request status")
        self.assertEqual(recorder.wroteTemp, false, "oversized request must not decode/write audio")
        self.assertEqual(recorder.transcribed, false, "oversized request must not transcribe")

        let body = self.decodeBody(response)
        self.assertEqual(body["code"] as? String, "payload_too_large", "stable size-cap code")

        // The server rejects with the same stable code before routing/buffering.
        let serverCapResponse = LocalAPI.error("Request too large.", code: "payload_too_large", status: 413)
        self.assertEqual(serverCapResponse.status, 413, "server route-cap status")
        self.assertEqual(
            self.decodeBody(serverCapResponse)["code"] as? String,
            "payload_too_large",
            "server route-cap code"
        )

        // The route cap must also stay far below the generic LocalAPI limit.
        precondition(
            DictationAPI.maxRequestBytes < LocalAPI.maxRequestBytes,
            "route cap must be conservative relative to the generic cap"
        )
        precondition(
            LocalAPI.bodyLimit(forPath: "/v1/dictate") == DictationAPI.maxRequestBytes,
            "server route limit matches the controller cap"
        )
        precondition(
            LocalAPI.bodyLimit(forPath: "/v1/transcribe") == LocalAPI.maxRequestBytes,
            "/v1/transcribe keeps the generic limit"
        )
    }

    @MainActor
    private static func testTemporaryFileRemovedOnSuccessAndFailure() async {
        final class Recorder {
            var written: [URL] = []
            var removed: [URL] = []
        }

        // Success path.
        let successRecorder = Recorder()
        let successDeps = self.makeDependencies(
            writeTemporaryFile: { data, fileExtension in
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dictation-api-success-\(UUID().uuidString)")
                    .appendingPathExtension(fileExtension)
                try data.write(to: url)
                successRecorder.written.append(url)
                return url
            },
            removeTemporaryFile: { url in
                successRecorder.removed.append(url)
                try? FileManager.default.removeItem(at: url)
            }
        )

        let successResponse = await DictationAPI.handle(self.makeRequest(), dependencies: successDeps)
        self.assertEqual(successResponse.status, 200, "success status")
        self.assertEqual(successRecorder.written.count, 1, "one temp file written")
        self.assertEqual(successRecorder.removed, successRecorder.written, "temp file removed on success")
        precondition(
            FileManager.default.fileExists(atPath: successRecorder.written[0].path) == false,
            "temp file is actually gone"
        )

        // Failure path: transcription throws after the file is written.
        struct Boom: Error {}
        let failureRecorder = Recorder()
        let failureDeps = self.makeDependencies(
            writeTemporaryFile: { data, fileExtension in
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dictation-api-failure-\(UUID().uuidString)")
                    .appendingPathExtension(fileExtension)
                try data.write(to: url)
                failureRecorder.written.append(url)
                return url
            },
            removeTemporaryFile: { url in
                failureRecorder.removed.append(url)
                try? FileManager.default.removeItem(at: url)
            },
            transcribe: { _ in throw Boom() }
        )

        let failureResponse = await DictationAPI.handle(self.makeRequest(), dependencies: failureDeps)
        self.assertEqual(failureResponse.status, 500, "transcription failure status")
        self.assertEqual(failureRecorder.removed, failureRecorder.written, "temp file removed on failure")
        precondition(
            FileManager.default.fileExists(atPath: failureRecorder.written[0].path) == false,
            "failed temp file is actually gone"
        )
    }

    @MainActor
    private static func testEnhancementPlanSelectionPolicy() async {
        self.assertEqual(
            DictationAPI.enhancementPlan(isConfigured: false, providerKey: "ollama", model: LocalPunctuationCleanup.model),
            .none,
            "unconfigured enhancement is none"
        )
        self.assertEqual(
            DictationAPI.enhancementPlan(isConfigured: true, providerKey: " ollama ", model: "\(LocalPunctuationCleanup.model) "),
            .guardedLocalCleanup(providerKey: "ollama", model: LocalPunctuationCleanup.model),
            "ollama cleanup model maps to guarded local cleanup"
        )
        self.assertEqual(
            DictationAPI.enhancementPlan(isConfigured: true, providerKey: "ollama", model: "other:latest"),
            .unsupportedProvider(providerKey: "ollama", model: "other:latest"),
            "non-cleanup ollama model is reported unsupported"
        )
        self.assertEqual(
            DictationAPI.enhancementPlan(isConfigured: true, providerKey: "openai", model: "gpt-x"),
            .unsupportedProvider(providerKey: "openai", model: "gpt-x"),
            "non-local provider is reported unsupported"
        )
        self.assertEqual(
            DictationAPI.enhancementPlan(isConfigured: true, providerKey: "", model: "gpt-x"),
            .none,
            "empty provider is none"
        )
    }

    @MainActor
    private static func testGuardedCleanupAndFormattingRunExactlyOnce() async {
        actor CleanerCounter {
            private(set) var count = 0
            func increment() { self.count += 1 }
        }
        let counter = CleanerCounter()

        let options = self.makeOptions(localCleanupSelected: true, removeTrailingPeriod: true)
        let plan = DictationAPI.EnhancementPlan.guardedLocalCleanup(
            providerKey: "ollama",
            model: LocalPunctuationCleanup.model
        )
        let cleaner: @Sendable (String) async -> String? = { text in
            await counter.increment()
            return "Cortana. Hello."
        }

        let response = await DictationAPI.handle(
            self.makeRequest(),
            dependencies: self.makeDependencies(
                transcribe: { _ in
                    DictationAPI.RecognitionResult(rawText: "Cortana, hello.", confidence: 0.8, sampleCount: 32_000)
                },
                options: options,
                enhancementPlan: plan,
                cleaner: cleaner
            )
        )

        self.assertEqual(response.status, 200, "cleanup status")
        let body = self.decodeBody(response)
        self.assertEqual(body["rawText"] as? String, "Cortana, hello.", "raw recognition preserved")
        // One cleanup pass turns "," into ".", then one output-formatting pass
        // removes the trailing period via GAAV. No stage runs twice.
        self.assertEqual(body["text"] as? String, "Cortana. Hello", "single cleanup + single formatting pass")
        self.assertEqual(await counter.count, 1, "cleaner invoked exactly once")

        let enhancement = body["enhancement"] as? [String: Any]
        self.assertEqual(enhancement?["mode"] as? String, "guardedLocalCleanup", "enhancement mode")
        self.assertEqual(enhancement?["outcome"] as? String, "applied", "enhancement outcome")
        self.assertEqual(enhancement?["model"] as? String, LocalPunctuationCleanup.model, "enhancement model")
    }

    @MainActor
    private static func testUnsupportedProviderReportedWithoutDuplication() async {
        actor CleanerCounter {
            private(set) var count = 0
            func increment() { self.count += 1 }
        }
        let counter = CleanerCounter()

        let plan = DictationAPI.EnhancementPlan.unsupportedProvider(providerKey: "openai", model: "gpt-x")
        let response = await DictationAPI.handle(
            self.makeRequest(),
            dependencies: self.makeDependencies(
                transcribe: { _ in
                    DictationAPI.RecognitionResult(rawText: "hello.", confidence: 0.7, sampleCount: 16_000)
                },
                options: self.makeOptions(removeTrailingPeriod: true),
                enhancementPlan: plan,
                cleaner: { text in
                    await counter.increment()
                    return text
                }
            )
        )

        self.assertEqual(response.status, 200, "unsupported provider status")
        let body = self.decodeBody(response)
        self.assertEqual(body["text"] as? String, "hello", "output formatting still runs once")
        let enhancement = body["enhancement"] as? [String: Any]
        self.assertEqual(enhancement?["mode"] as? String, "unsupportedProvider", "unsupported mode")
        self.assertEqual(enhancement?["outcome"] as? String, "unsupported", "unsupported outcome reported")
        self.assertEqual(enhancement?["providerKey"] as? String, "openai", "unsupported provider reported")
        self.assertEqual(await counter.count, 0, "unsupported provider must not run the local cleaner")
    }

    @MainActor
    private static func testJSONBodyPathUsesBase64Audio() async {
        final class Recorder {
            var received: Data?
            var receivedExtension: String?
        }
        let recorder = Recorder()
        let audio = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x01])

        let json: [String: Any] = [
            "audioBase64": audio.base64EncodedString(),
            "filename": "clip.wav",
        ]
        let body = try! JSONSerialization.data(withJSONObject: json)

        let deps = self.makeDependencies(
            writeTemporaryFile: { data, fileExtension in
                recorder.received = data
                recorder.receivedExtension = fileExtension
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dictation-api-json-\(UUID().uuidString)")
                    .appendingPathExtension(fileExtension)
                try data.write(to: url)
                return url
            },
            transcribe: { url in
                let onDisk = try Data(contentsOf: url)
                precondition(onDisk == audio, "transcriber sees decoded base64 audio")
                return DictationAPI.RecognitionResult(rawText: "json", confidence: 0.5, sampleCount: 3)
            }
        )

        let response = await DictationAPI.handle(
            self.makeRequest(headers: ["content-type": "application/json"], body: body),
            dependencies: deps
        )
        self.assertEqual(response.status, 200, "json body status")
        self.assertEqual(recorder.received, audio, "decoded base64 audio")
        self.assertEqual(recorder.receivedExtension, "wav", "suggested extension from filename")
    }

    @MainActor
    private static func testResponseSchema() async {
        let response = await DictationAPI.handle(
            self.makeRequest(headers: ["x-request-id": "schema-check"]),
            dependencies: self.makeDependencies()
        )
        self.assertEqual(response.status, 200, "schema status")

        let body = self.decodeBody(response)
        let expectedKeys: Set<String> = [
            "schemaRevision",
            "requestId",
            "rawText",
            "text",
            "confidence",
            "sampleCount",
            "engineIdentity",
            "engineReadiness",
            "enhancement",
            "pipelineRevision",
        ]
        self.assertEqual(Set(body.keys), expectedKeys, "response top-level schema")

        self.assertEqual(body["schemaRevision"] as? Int, DictationAPI.schemaRevision, "schema revision")
        self.assertEqual(body["pipelineRevision"] as? String, SharedDictationPipeline.revision, "pipeline revision")
        self.assertEqual(body["engineReadiness"] as? String, "unknown", "readiness uses observed value only")

        let engine = body["engineIdentity"] as? [String: Any]
        self.assertEqual(engine?["engineId"] as? String, "unknown", "unknown engine id reported as unknown")
        precondition(engine?["modelSha256"] == nil || engine?["modelSha256"] is NSNull, "no invented model hash")

        // Round-trip through the declared Codable shape to keep the contract honest.
        let decoded = try! LocalAPI.decoder.decode(DictationAPI.ResponseBody.self, from: response.body)
        self.assertEqual(decoded.requestId, "schema-check", "decoded request id")
        self.assertEqual(decoded.enhancement.outcome, .notSelected, "decoded enhancement outcome")
        self.assertEqual(decoded.engineReadiness, .unknown, "decoded readiness")
    }
}
