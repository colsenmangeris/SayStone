import Foundation

/// App-layer wiring for `POST /v1/dictate`.
///
/// The route policy lives in ``DictationAPI``; this controller only resolves
/// real services and user settings into its dependency seam.
@MainActor
final class DictationAPIController: LocalAPIRouteHandler {
    func handle(_ request: LocalAPI.Request) async -> LocalAPI.Response {
        await DictationAPI.handle(request, dependencies: self.makeDependencies())
    }

    private func makeDependencies() -> DictationAPI.Dependencies {
        DictationAPI.Dependencies(
            isASRBusy: { AppServices.shared.asr.isRunningOrStarting },
            writeTemporaryFile: { data, fileExtension in
                try await LocalAPIAudioDecoder.temporaryFile(
                    fromAudioData: data,
                    suggestedExtension: fileExtension
                )
            },
            removeTemporaryFile: { url in
                await LocalAPIAudioDecoder.removeTemporaryFile(at: url)
            },
            transcribe: { url in
                let result = try await AppServices.shared.asr.transcribeFileForAPI(url)
                return DictationAPI.RecognitionResult(
                    rawText: result.result.text,
                    confidence: result.result.confidence,
                    sampleCount: result.sampleCount
                )
            },
            pipelineOptions: { ASRService.sharedDictationPipelineOptions() },
            enhancementPlan: { Self.enhancementPlan() },
            cleaner: { text in await LocalPunctuationCleanup.generateCandidate(text) },
            engineIdentity: { EngineIdentityReader.current() },
            makeRequestID: { UUID().uuidString }
        )
    }

    /// Resolves the selected dictation enhancement for the API's slotless
    /// request.
    ///
    /// Only the guarded local punctuation cleanup shares the exact desktop
    /// one-pass path in this slice. Any other configured provider is reported
    /// as an unsupported enhancement rather than run through a divergent path.
    static func enhancementPlan() -> DictationAPI.EnhancementPlan {
        let settings = SettingsStore.shared
        let route = DictationProviderRoute.resolveForPostProcessing(
            settings: settings,
            dictationSlot: .primary
        )
        return DictationAPI.enhancementPlan(
            isConfigured: DictationAIPostProcessingGate.isConfigured(for: .primary, appBundleID: nil),
            providerKey: route.providerKey,
            model: route.model
        )
    }
}
