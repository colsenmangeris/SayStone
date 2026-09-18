import Foundation

/// App-layer bridge between `SettingsStore` and the UI-independent
/// ``SharedDictationPipeline``. This is the only place that turns user settings
/// into pipeline options; the shared core never reads UI state.
extension ASRService {
    static func sharedDictationContext(
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> SharedDictationPipeline.Context {
        SharedDictationPipeline.Context(
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle
        )
    }

    /// Snapshots the deterministic pipeline settings.
    ///
    /// - Parameters:
    ///   - includeDictionary: Set false for dictionary-training capture, which
    ///     must not run replacements over the recorded phrase.
    ///   - includeSpokenPunctuation: Set false alongside `includeDictionary` for
    ///     dictionary-training capture.
    static func sharedDictationPipelineOptions(
        includeDictionary: Bool = true,
        includeSpokenPunctuation: Bool = true
    ) -> SharedDictationPipeline.Options {
        let settings = SettingsStore.shared
        return SharedDictationPipeline.Options(
            filler: SharedDictationPipeline.FillerOptions(
                isEnabled: settings.removeFillerWordsEnabled,
                words: settings.fillerWords
            ),
            dictionary: SharedDictationPipeline.DictionaryOptions(
                entries: includeDictionary
                    ? settings.customDictionaryEntries.map(Self.sharedDictionaryEntry(from:))
                    : []
            ),
            spokenPunctuation: SharedDictationPipeline.SpokenPunctuationOptions(
                isEnabled: includeSpokenPunctuation && settings.autoConvertPunctuationEnabled,
                prefix: settings.punctuationDictionaryPrefix,
                rules: settings.punctuationDictionaryRules.map(Self.sharedPunctuationRule(from:)),
                actionRules: settings.spokenFormattingActionRules.map(Self.sharedActionRule(from:))
            ),
            localCleanup: .disabled,
            literalFormatting: SharedDictationPipeline.LiteralFormattingOptions(
                isEnabled: settings.literalDictationFormattingEnabled
            ),
            gaav: SharedDictationPipeline.GAAVOptions(
                removeTrailingPeriod: settings.gaavRemoveTrailingPeriodEnabled,
                lowercaseFirstLetter: settings.gaavLowercaseFirstLetterEnabled
            ),
            continuous: SharedDictationPipeline.ContinuousOptions(
                spacingEnabled: settings.continuousDictationSpacingEnabled,
                smartCapitalizationEnabled: settings.contextAwareCapitalizationEnabled,
                precedingText: ""
            )
        )
    }

    // MARK: - Spoken punctuation

    static func applySpokenPunctuationFormatting(
        _ text: String,
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> String {
        let settings = SettingsStore.shared
        return SharedDictationPipeline.applySpokenPunctuation(
            text,
            options: SharedDictationPipeline.SpokenPunctuationOptions(
                isEnabled: settings.autoConvertPunctuationEnabled,
                prefix: settings.punctuationDictionaryPrefix,
                rules: settings.punctuationDictionaryRules.map(Self.sharedPunctuationRule(from:)),
                actionRules: settings.spokenFormattingActionRules.map(Self.sharedActionRule(from:))
            ),
            context: Self.sharedDictationContext(
                appName: appName,
                bundleID: bundleID,
                windowTitle: windowTitle
            )
        )
    }

    // MARK: - Literal formatting

    static func applyDictationLiteralFormatting(
        _ text: String,
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> String {
        DictationLiteralFormatter.applyDictationLiteralFormatting(
            text,
            enabled: SettingsStore.shared.literalDictationFormattingEnabled,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle
        )
    }

    static func applySlashCommandFormatting(_ text: String) -> String {
        DictationLiteralFormatter.applySlashCommandFormatting(
            text,
            enabled: SettingsStore.shared.literalDictationFormattingEnabled
        )
    }

    static func applyMentionFormatting(
        _ text: String,
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> String {
        DictationLiteralFormatter.applyMentionFormatting(
            text,
            enabled: SettingsStore.shared.literalDictationFormattingEnabled,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle
        )
    }

    static func makeDictationLiteralOutputPlan(
        for text: String,
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> DictationLiteralOutputPlan {
        DictationLiteralFormatter.makeOutputPlan(
            for: text,
            enabled: SettingsStore.shared.literalDictationFormattingEnabled,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle
        )
    }

    static func applyTerminalLiteralAutocompleteSpacing(
        _ text: String,
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> String {
        DictationLiteralFormatter.applyTerminalLiteralAutocompleteSpacing(
            text,
            enabled: SettingsStore.shared.literalDictationFormattingEnabled,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle
        )
    }

    // MARK: - Settings mapping

    private static func sharedDictionaryEntry(
        from entry: SettingsStore.CustomDictionaryEntry
    ) -> SharedDictationPipeline.DictionaryEntry {
        SharedDictationPipeline.DictionaryEntry(
            triggers: entry.triggers,
            replacement: entry.replacement
        )
    }

    private static func sharedPunctuationRule(
        from rule: SettingsStore.PunctuationDictionaryRule
    ) -> SharedDictationPipeline.PunctuationRule {
        SharedDictationPipeline.PunctuationRule(aliases: rule.aliases, symbol: rule.symbol)
    }

    private static func sharedActionRule(
        from rule: SettingsStore.SpokenFormattingActionRule
    ) -> SharedDictationPipeline.FormattingActionRule {
        SharedDictationPipeline.FormattingActionRule(
            action: Self.sharedAction(from: rule.action),
            aliases: rule.aliases,
            isEnabled: rule.isEnabled
        )
    }

    private static func sharedAction(
        from action: SettingsStore.SpokenFormattingAction
    ) -> SharedDictationPipeline.FormattingAction {
        switch action {
        case .newLine: return .newLine
        case .newParagraph: return .newParagraph
        case .tab: return .tab
        case .space: return .space
        }
    }
}
