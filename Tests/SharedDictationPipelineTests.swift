import Foundation

/// Focused standalone test for the shared post-recognition pipeline.
///
/// Compile with the Foundation-only core files; it never touches `SettingsStore`,
/// the UI, the network, or audio capture.
@main
struct SharedDictationPipelineTests {
    static func main() async {
        await self.testEquivalentDesktopAndAPIInputsMatch()
        await self.testCustomDictionaryAndSpokenPunctuation()
        await self.testGuardedCleanupAcceptsValidCandidate()
        await self.testGuardedCleanupRejectsOutOfTrialRewrite()
        await self.testGuardedCleanupUnavailableAndNotSelected()
        await self.testFullPipelineParityWithCleanup()
        self.testEngineIdentityReportsOnlyObservedValues()
        print("PASS: shared dictation pipeline parity, personalization, guarded cleanup, and engine identity")
    }

    // MARK: - Fixtures

    private static func makeOptions(
        localCleanupSelected: Bool = false,
        literalFormatting: Bool = false,
        removeTrailingPeriod: Bool = false
    ) -> SharedDictationPipeline.Options {
        SharedDictationPipeline.Options(
            filler: SharedDictationPipeline.FillerOptions(
                isEnabled: true,
                words: ["um", "uh"]
            ),
            dictionary: SharedDictationPipeline.DictionaryOptions(
                entries: [
                    SharedDictationPipeline.DictionaryEntry(
                        triggers: ["cortana"],
                        replacement: "Cortana"
                    ),
                    SharedDictationPipeline.DictionaryEntry(
                        triggers: ["say stone"],
                        replacement: "SayStone"
                    ),
                ]
            ),
            spokenPunctuation: SharedDictationPipeline.SpokenPunctuationOptions(
                isEnabled: true,
                prefix: "say",
                rules: [
                    SharedDictationPipeline.PunctuationRule(aliases: ["comma"], symbol: ","),
                    SharedDictationPipeline.PunctuationRule(aliases: ["period", "full stop"], symbol: "."),
                    SharedDictationPipeline.PunctuationRule(aliases: ["question mark"], symbol: "?"),
                ],
                actionRules: [
                    SharedDictationPipeline.FormattingActionRule(
                        action: .newLine,
                        aliases: ["new line"],
                        isEnabled: true
                    ),
                ]
            ),
            localCleanup: localCleanupSelected
                ? SharedDictationPipeline.LocalCleanupSelection(
                    isSelected: true,
                    providerKey: "ollama",
                    model: LocalPunctuationCleanup.model
                )
                : .disabled,
            literalFormatting: SharedDictationPipeline.LiteralFormattingOptions(isEnabled: literalFormatting),
            gaav: SharedDictationPipeline.GAAVOptions(
                removeTrailingPeriod: removeTrailingPeriod,
                lowercaseFirstLetter: false
            ),
            continuous: SharedDictationPipeline.ContinuousOptions(
                spacingEnabled: false,
                smartCapitalizationEnabled: false,
                precedingText: ""
            )
        )
    }

    private static func assertEqual(
        _ actual: String,
        _ expected: String,
        _ label: String
    ) {
        precondition(actual == expected, "\(label): expected \(expected.debugDescription), got \(actual.debugDescription)")
    }

    // MARK: - Tests

    private static func testEquivalentDesktopAndAPIInputsMatch() async {
        // Desktop snapshots app context; the LocalAPI has none. The deterministic
        // personalization output must still match for the same raw recognition.
        let options = self.makeOptions()
        let raw = "um cortana say comma hello say period"
        let desktop = SharedDictationPipeline.applyRecognitionPersonalization(
            raw,
            options: options,
            context: SharedDictationPipeline.Context(appName: "Notes")
        )
        let api = SharedDictationPipeline.applyRecognitionPersonalization(raw, options: options)

        self.assertEqual(desktop.text, api.text, "desktop/API personalization parity")
        precondition(
            desktop.stagesApplied == [.fillerRemoval, .customDictionary, .spokenPunctuation],
            "unexpected stages: \(desktop.stagesApplied)"
        )
        self.assertEqual(desktop.text, "Cortana, hello.", "personalization output")
    }

    private static func testCustomDictionaryAndSpokenPunctuation() async {
        let options = self.makeOptions()
        let raw = "say stone say question mark"
        let outcome = SharedDictationPipeline.applyRecognitionPersonalization(raw, options: options)
        self.assertEqual(outcome.text, "SayStone?", "dictionary + punctuation")
    }

    private static func testGuardedCleanupAcceptsValidCandidate() async {
        let options = self.makeOptions(localCleanupSelected: true)
        let cleaner: SharedDictationPipeline.LocalCleanup = { _ in "Please send the report." }
        let result = await SharedDictationPipeline.process(
            "please send the report",
            context: .empty,
            options: options,
            cleaner: cleaner
        )
        self.assertEqual(result.text, "Please send the report.", "accepted cleanup output")
        precondition(result.cleanupOutcome == .applied, "expected .applied, got \(result.cleanupOutcome)")
        precondition(result.cleanupModel == LocalPunctuationCleanup.model, "cleanup model metadata")
    }

    private static func testGuardedCleanupRejectsOutOfTrialRewrite() async {
        let options = self.makeOptions(localCleanupSelected: true)
        // Lexical content changes are outside the punctuation/capitalization trial.
        let cleaner: SharedDictationPipeline.LocalCleanup = { _ in "Deploy the thing." }
        let result = await SharedDictationPipeline.process(
            "please send the report",
            context: .empty,
            options: options,
            cleaner: cleaner
        )
        self.assertEqual(result.text, "please send the report", "rejected cleanup returns input")
        precondition(result.cleanupOutcome == .rejected, "expected .rejected, got \(result.cleanupOutcome)")
    }

    private static func testGuardedCleanupUnavailableAndNotSelected() async {
        let selected = self.makeOptions(localCleanupSelected: true)
        let unavailable = await SharedDictationPipeline.process(
            "please send the report",
            context: .empty,
            options: selected,
            cleaner: { _ in nil }
        )
        self.assertEqual(unavailable.text, "please send the report", "unavailable cleanup returns input")
        precondition(unavailable.cleanupOutcome == .unavailable, "expected .unavailable")

        let disabled = self.makeOptions(localCleanupSelected: false)
        let notSelected = await SharedDictationPipeline.process(
            "please send the report",
            context: .empty,
            options: disabled,
            cleaner: { _ in "Should not run." }
        )
        self.assertEqual(notSelected.text, "please send the report", "disabled cleanup returns input")
        precondition(notSelected.cleanupOutcome == .notSelected, "expected .notSelected")
    }

    private static func testFullPipelineParityWithCleanup() async {
        // Two equivalent option snapshots representing the desktop and API
        // call sites must produce byte-identical results, including trace.
        let desktopOptions = self.makeOptions(
            localCleanupSelected: true,
            literalFormatting: false,
            removeTrailingPeriod: true
        )
        let apiOptions = self.makeOptions(
            localCleanupSelected: true,
            literalFormatting: false,
            removeTrailingPeriod: true
        )
        let cleaner: SharedDictationPipeline.LocalCleanup = { text in
            text.replacingOccurrences(of: ",", with: ".")
        }
        let raw = "um cortana say comma hello say period"
        let desktop = await SharedDictationPipeline.process(
            raw,
            context: SharedDictationPipeline.Context(appName: "Notes"),
            options: desktopOptions,
            cleaner: cleaner
        )
        let api = await SharedDictationPipeline.process(
            raw,
            context: .empty,
            options: apiOptions,
            cleaner: cleaner
        )

        precondition(desktop == api, "full pipeline parity: \(desktop) != \(api)")
        precondition(
            desktop.stagesApplied == [
                .fillerRemoval, .customDictionary, .spokenPunctuation, .localCleanup,
                .gaavFormatting,
            ],
            "unexpected stage order: \(desktop.stagesApplied)"
        )
    }

    private static func testEngineIdentityReportsOnlyObservedValues() {
        let unknown = EngineIdentity.unknown(
            saystoneBuild: "1.2.3 (45)"
        )
        precondition(unknown.readiness == .unknown, "unknown engine readiness")
        precondition(unknown.modelKey == nil, "unknown engine model key must be nil")
        precondition(unknown.modelSha256 == nil, "unknown engine hash must not be invented")
        precondition(unknown.runtimeCommit == nil, "unknown runtime commit must not be invented")
        precondition(unknown.unknownFieldNames.contains("modelKey"), "unknown fields list modelKey")
        precondition(unknown.unknownFieldNames.contains("modelSha256"), "unknown fields list modelSha256")
        precondition(unknown.saystoneBuild == "1.2.3 (45)", "observed build is reported")

        let partial = EngineIdentity.resolved(
            modelKey: "parakeet-v3",
            saystoneBuild: "1.2.3 (45)"
        )
        precondition(partial.readiness == .unknown, "partial identity cannot claim parity")
        precondition(partial.pipelineRevision == SharedDictationPipeline.revision, "pipeline revision")

        let ready = EngineIdentity.resolved(
            modelKey: "parakeet-v3",
            saystoneBuild: "1.2.3 (45)",
            modelRevision: "parakeet-v3-pinned",
            modelSha256: String(repeating: "a", count: 64),
            runtimeCommit: "0123456789abcdef",
            profileSchemaRevision: 1
        )
        precondition(ready.readiness == .ready, "complete engine readiness")
    }
}
