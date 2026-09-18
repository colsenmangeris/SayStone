import Foundation

/// The loopback-only final-dictation route (`POST /v1/dictate`).
///
/// This type is deliberately free of AppKit, `SettingsStore`, audio capture,
/// and network clients. The app-layer controller injects those through
/// ``Dependencies`` so the route's policy — the desktop-capture busy gate, the
/// route-specific size cap, request-ID resolution, temp-file lifecycle, the
/// single enhancement/cleanup pass, and the single output-formatting pass — is
/// deterministic and testable without hardware.
@MainActor
enum DictationAPI {
    /// Version of the `/v1/dictate` response document shape.
    static let schemaRevision = 1

    /// Conservative per-route cap for phone dictation, far below the generic
    /// `LocalAPI.maxRequestBytes` (500 MiB).
    static let maxRequestBytes = LocalAPI.dictateMaxRequestBytes

    /// Upper bound on an honored `x-request-id`, matching common proxy limits.
    static let maximumRequestIDLength = 128

    // MARK: - Dependency seam

    /// Recognition output from the selected SayStone engine.
    struct RecognitionResult: Equatable, Sendable {
        /// Recognition text after the shared recognition personalization,
        /// exactly as the API transcription entry point returns it.
        let rawText: String
        let confidence: Float
        let sampleCount: Int
    }

    enum EnhancementMode: String, Codable, Equatable, Sendable {
        /// No dictation enhancement/cleanup is configured or selected.
        case none
        /// The acceptance-critical guarded local punctuation cleanup.
        case guardedLocalCleanup
        /// A configured provider that this slice does not run through the
        /// shared one-pass path. Reported, never silently duplicated.
        case unsupportedProvider
    }

    enum EnhancementOutcome: String, Codable, Equatable, Sendable {
        case notSelected
        case applied
        case unchanged
        case unavailable
        case rejected
        case unsupported
    }

    struct EnhancementPlan: Equatable, Sendable {
        let mode: EnhancementMode
        let providerKey: String?
        let model: String?

        static let none = EnhancementPlan(mode: .none, providerKey: nil, model: nil)

        static func guardedLocalCleanup(providerKey: String, model: String) -> Self {
            EnhancementPlan(mode: .guardedLocalCleanup, providerKey: providerKey, model: model)
        }

        static func unsupportedProvider(providerKey: String, model: String) -> Self {
            EnhancementPlan(mode: .unsupportedProvider, providerKey: providerKey, model: model)
        }
    }

    /// Maps a resolved provider route to the enhancement this slice can run.
    ///
    /// Pure so the selection policy is testable without user settings. Only the
    /// guarded local punctuation cleanup shares the exact desktop one-pass
    /// path; everything else is reported as unsupported rather than run through
    /// a divergent path.
    static func enhancementPlan(
        isConfigured: Bool,
        providerKey: String,
        model: String
    ) -> EnhancementPlan {
        guard isConfigured else { return .none }
        let trimmedProviderKey = providerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProviderKey.isEmpty, !trimmedModel.isEmpty else { return .none }
        if trimmedProviderKey == "ollama", trimmedModel == LocalPunctuationCleanup.model {
            return .guardedLocalCleanup(providerKey: trimmedProviderKey, model: trimmedModel)
        }
        return .unsupportedProvider(providerKey: trimmedProviderKey, model: trimmedModel)
    }

    /// All environment access used by the route. The live controller supplies
    /// real implementations; tests supply fakes.
    struct Dependencies {
        var isASRBusy: @MainActor () -> Bool
        var writeTemporaryFile: @MainActor (Data, String) async throws -> URL
        var removeTemporaryFile: @MainActor (URL) async -> Void
        var transcribe: @MainActor (URL) async throws -> RecognitionResult
        var pipelineOptions: @MainActor () -> SharedDictationPipeline.Options
        var enhancementPlan: @MainActor () -> EnhancementPlan
        var cleaner: @Sendable (String) async -> String?
        var engineIdentity: @MainActor () -> EngineIdentity
        var makeRequestID: @MainActor () -> String
    }

    // MARK: - Response

    struct EnhancementMetadata: Codable, Equatable, Sendable {
        let mode: EnhancementMode
        let providerKey: String?
        let model: String?
        let outcome: EnhancementOutcome
    }

    struct ResponseBody: Codable, Equatable, Sendable {
        let schemaRevision: Int
        let requestId: String
        let rawText: String
        let text: String
        let confidence: Float
        let sampleCount: Int
        let engineIdentity: EngineIdentity
        let engineReadiness: EngineIdentity.Readiness
        let enhancement: EnhancementMetadata
        let pipelineRevision: String
    }

    private struct ErrorBody: Encodable {
        let code: String
        let error: String
        let requestId: String
    }

    // MARK: - Entry point

    /// Handles one `POST /v1/dictate` request.
    ///
    /// Ordering is intentional: desktop capture wins before any decode, then
    /// the route cap, then decoding, then transcription. The temporary file is
    /// removed on every path that creates it.
    static func handle(_ request: LocalAPI.Request, dependencies: Dependencies) async -> LocalAPI.Response {
        let requestId = self.resolveRequestID(
            request.headers["x-request-id"],
            make: dependencies.makeRequestID
        )

        guard request.method == "POST" else {
            return self.errorResponse(
                code: "method_not_allowed",
                message: "Method not allowed.",
                requestId: requestId,
                status: 405
            )
        }

        // Desktop microphone capture has priority over API dictation.
        guard !dependencies.isASRBusy() else {
            return self.errorResponse(
                code: "busy",
                message: "Dictation is busy: desktop microphone capture is active.",
                requestId: requestId,
                status: 409
            )
        }

        guard request.body.count <= self.maxRequestBytes else {
            return self.errorResponse(
                code: "payload_too_large",
                message: "Audio request exceeds the dictation size limit.",
                requestId: requestId,
                status: 413
            )
        }

        let payload: (data: Data, fileExtension: String)
        do {
            payload = try self.audioPayload(from: request)
        } catch {
            return self.errorResponse(
                code: "invalid_audio",
                message: error.localizedDescription,
                requestId: requestId,
                status: 400
            )
        }

        guard !payload.data.isEmpty else {
            return self.errorResponse(
                code: "empty_audio",
                message: "Missing audio body.",
                requestId: requestId,
                status: 400
            )
        }

        let temporaryURL: URL
        do {
            temporaryURL = try await dependencies.writeTemporaryFile(payload.data, payload.fileExtension)
        } catch {
            return self.errorResponse(
                code: "decode_failed",
                message: error.localizedDescription,
                requestId: requestId,
                status: 400
            )
        }

        do {
            let recognition = try await dependencies.transcribe(temporaryURL)
            await dependencies.removeTemporaryFile(temporaryURL)
            let body = await self.process(
                recognition: recognition,
                requestId: requestId,
                dependencies: dependencies
            )
            return LocalAPI.json(body)
        } catch {
            await dependencies.removeTemporaryFile(temporaryURL)
            return self.errorResponse(
                code: "transcription_failed",
                message: error.localizedDescription,
                requestId: requestId,
                status: 500
            )
        }
    }

    // MARK: - Request ID

    /// Returns the caller's `x-request-id` when it is a safe, bounded token;
    /// otherwise generates a fresh one.
    static func resolveRequestID(_ header: String?, make: @MainActor () -> String) -> String {
        guard let header else { return make() }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= self.maximumRequestIDLength,
              trimmed.allSatisfy(\.isValidRequestIDCharacter)
        else {
            return make()
        }
        return trimmed
    }

    // MARK: - Body decoding

    /// Extracts bounded audio data and a suggested file extension from the raw
    /// WAV body or the optional JSON (`audioBase64`) form. The generic cap is
    /// enforced by the caller; this only validates shape.
    static func audioPayload(from request: LocalAPI.Request) throws -> (data: Data, fileExtension: String) {
        if self.isJSON(request) {
            struct JSONRequest: Decodable {
                let audioBase64: String?
                let filename: String?
            }

            let payload: JSONRequest
            do {
                payload = try LocalAPI.decoder.decode(JSONRequest.self, from: request.body)
            } catch {
                throw NSError(
                    domain: "DictationAPI",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON audio payload."]
                )
            }

            guard let audioBase64 = payload.audioBase64,
                  let data = Data(base64Encoded: audioBase64)
            else {
                throw NSError(
                    domain: "DictationAPI",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing or invalid audioBase64."]
                )
            }

            let fileExtension = payload.filename
                .flatMap { URL(fileURLWithPath: $0).pathExtension }
                .flatMap { $0.isEmpty ? nil : $0 } ?? "wav"
            return (data, fileExtension)
        }

        let filename = request.headers["x-filename"] ?? "audio.wav"
        let fileExtension = URL(fileURLWithPath: filename).pathExtension
        return (request.body, fileExtension.isEmpty ? "wav" : fileExtension)
    }

    // MARK: - Enhancement + formatting (exactly once each)

    private static func process(
        recognition: RecognitionResult,
        requestId: String,
        dependencies: Dependencies
    ) async -> ResponseBody {
        let options = dependencies.pipelineOptions()
        let plan = dependencies.enhancementPlan()
        let identity = dependencies.engineIdentity()

        var text = recognition.rawText
        var outcome: EnhancementOutcome

        switch plan.mode {
        case .none:
            outcome = .notSelected

        case .guardedLocalCleanup:
            let cleanup = await SharedDictationPipeline.applyGuardedLocalCleanup(
                text,
                selection: SharedDictationPipeline.LocalCleanupSelection(
                    isSelected: true,
                    providerKey: plan.providerKey ?? "",
                    model: plan.model ?? ""
                ),
                cleaner: dependencies.cleaner
            )
            text = cleanup.text
            outcome = Self.enhancementOutcome(from: cleanup.outcome)

        case .unsupportedProvider:
            // Non-local enhancement providers are intentionally not wired into
            // the shared one-pass path in this slice. Report the gap instead of
            // duplicating desktop behavior with a separate code path.
            outcome = .unsupported
        }

        // Output formatting runs exactly once, and GAAV lives inside it, so the
        // API never double-applies GAAV.
        let output = SharedDictationPipeline.applyOutputFormatting(
            text,
            options: options,
            context: .empty
        )

        return ResponseBody(
            schemaRevision: self.schemaRevision,
            requestId: requestId,
            rawText: recognition.rawText,
            text: output.text,
            confidence: recognition.confidence,
            sampleCount: recognition.sampleCount,
            engineIdentity: identity,
            engineReadiness: identity.readiness,
            enhancement: EnhancementMetadata(
                mode: plan.mode,
                providerKey: plan.providerKey,
                model: plan.model,
                outcome: outcome
            ),
            pipelineRevision: SharedDictationPipeline.revision
        )
    }

    private static func enhancementOutcome(
        from cleanup: SharedDictationPipeline.CleanupOutcome
    ) -> EnhancementOutcome {
        switch cleanup {
        case .notSelected: return .notSelected
        case .unchanged: return .unchanged
        case .unavailable: return .unavailable
        case .rejected: return .rejected
        case .applied: return .applied
        }
    }

    // MARK: - Helpers

    private static func isJSON(_ request: LocalAPI.Request) -> Bool {
        request.headers["content-type"]?.lowercased().contains("application/json") == true
    }

    private static func errorResponse(
        code: String,
        message: String,
        requestId: String,
        status: Int
    ) -> LocalAPI.Response {
        LocalAPI.json(
            ErrorBody(code: code, error: message, requestId: requestId),
            status: status
        )
    }
}

private extension Character {
    /// Bounded token characters: letters, digits, and `._:-` only. This keeps a
    /// caller-supplied request ID safe for logs, headers, and JSON.
    var isValidRequestIDCharacter: Bool {
        self.isASCII && (self.isLetter || self.isNumber || "._:-".contains(self))
    }
}
