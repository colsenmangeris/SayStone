import Foundation

/// The single deterministic post-recognition pipeline shared by desktop
/// dictation and the LocalAPI.
///
/// Callers snapshot their user settings into ``Options``. This type never reads
/// `SettingsStore`, the view layer, or any other UI state. UI delivery, history,
/// and audio recovery stay outside this core.
nonisolated enum SharedDictationPipeline {
    /// Revision of the extracted shared pipeline. Bump whenever stage semantics
    /// change so recorded results can be compared for parity.
    static let revision = "saystone-shared-pipeline-v1"

    struct Context: Equatable, Sendable {
        var appName: String?
        var bundleID: String?
        var windowTitle: String?

        init(appName: String? = nil, bundleID: String? = nil, windowTitle: String? = nil) {
            self.appName = appName
            self.bundleID = bundleID
            self.windowTitle = windowTitle
        }

        static let empty = Context()
    }

    // MARK: - Plain configuration values

    struct DictionaryEntry: Equatable, Hashable, Sendable {
        let triggers: [String]
        let replacement: String
    }

    struct PunctuationRule: Equatable, Hashable, Sendable {
        let aliases: [String]
        let symbol: String
    }

    enum FormattingAction: Equatable, Hashable, Sendable {
        case newLine
        case newParagraph
        case tab
        case space

        var output: String {
            switch self {
            case .newLine: return "\n"
            case .newParagraph: return "\n\n"
            case .tab: return "\t"
            case .space: return " "
            }
        }
    }

    struct FormattingActionRule: Equatable, Hashable, Sendable {
        let action: FormattingAction
        let aliases: [String]
        let isEnabled: Bool
    }

    struct LocalCleanupSelection: Equatable, Sendable {
        var isSelected: Bool
        var providerKey: String
        var model: String

        static let disabled = LocalCleanupSelection(isSelected: false, providerKey: "", model: "")
    }

    // MARK: - Options

    struct FillerOptions: Equatable, Sendable {
        var isEnabled: Bool
        var words: [String]

        static let disabled = FillerOptions(isEnabled: false, words: [])
    }

    struct DictionaryOptions: Equatable, Sendable {
        var entries: [DictionaryEntry]

        static let empty = DictionaryOptions(entries: [])
    }

    struct SpokenPunctuationOptions: Equatable, Sendable {
        var isEnabled: Bool
        var prefix: String
        var rules: [PunctuationRule]
        var actionRules: [FormattingActionRule]

        static let disabled = SpokenPunctuationOptions(isEnabled: false, prefix: "", rules: [], actionRules: [])
    }

    struct LiteralFormattingOptions: Equatable, Sendable {
        var isEnabled: Bool

        static let disabled = LiteralFormattingOptions(isEnabled: false)
    }

    struct GAAVOptions: Equatable, Sendable {
        var removeTrailingPeriod: Bool
        var lowercaseFirstLetter: Bool

        static let disabled = GAAVOptions(removeTrailingPeriod: false, lowercaseFirstLetter: false)
    }

    struct ContinuousOptions: Equatable, Sendable {
        var spacingEnabled: Bool
        var smartCapitalizationEnabled: Bool
        var precedingText: String

        static let disabled = ContinuousOptions(
            spacingEnabled: false,
            smartCapitalizationEnabled: false,
            precedingText: ""
        )
    }

    struct Options: Equatable, Sendable {
        var filler: FillerOptions
        var dictionary: DictionaryOptions
        var spokenPunctuation: SpokenPunctuationOptions
        var localCleanup: LocalCleanupSelection
        var literalFormatting: LiteralFormattingOptions
        var gaav: GAAVOptions
        var continuous: ContinuousOptions

        static let disabled = Options(
            filler: .disabled,
            dictionary: .empty,
            spokenPunctuation: .disabled,
            localCleanup: .disabled,
            literalFormatting: .disabled,
            gaav: .disabled,
            continuous: .disabled
        )
    }

    // MARK: - Result metadata

    enum Stage: String, Equatable, Sendable, CaseIterable {
        case fillerRemoval
        case customDictionary
        case spokenPunctuation
        case localCleanup
        case literalFormatting
        case gaavFormatting
        case continuousDictation
        case terminalSpacing
    }

    enum CleanupOutcome: String, Equatable, Sendable {
        case notSelected
        case unchanged
        case unavailable
        case rejected
        case applied
    }

    struct TraceEntry: Equatable, Sendable {
        let stage: Stage
        let text: String
    }

    struct StageOutcome: Equatable, Sendable {
        let text: String
        let stagesApplied: [Stage]
        let trace: [TraceEntry]
    }

    struct Result: Equatable, Sendable {
        let text: String
        let stagesApplied: [Stage]
        let cleanupOutcome: CleanupOutcome
        let cleanupModel: String?
        let trace: [TraceEntry]
        let engineIdentity: EngineIdentity
    }

    typealias LocalCleanup = @Sendable (String) async -> String?

    // MARK: - Deterministic stages

    /// Removes configured filler sounds from recognized text.
    static func removeFillerWords(_ text: String, options: FillerOptions) -> String {
        guard options.isEnabled else { return text }
        let fillers = Set(options.words.map { $0.lowercased() })
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        let filtered = words.filter { word in
            !fillers.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
        }
        return filtered.joined(separator: " ")
    }

    /// Applies custom-dictionary replacements, longest pattern first.
    static func applyCustomDictionary(_ text: String, options: DictionaryOptions) -> String {
        guard !options.entries.isEmpty else { return text }
        let patterns = self.dictionaryPatterns(for: options.entries)
        guard !patterns.isEmpty else { return text }

        var result = text
        for pattern in patterns {
            result = pattern.regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: pattern.template
            )
        }
        return result
    }

    /// Converts spoken punctuation and formatting actions into symbols.
    static func applySpokenPunctuation(
        _ text: String,
        options: SpokenPunctuationOptions,
        context: Context
    ) -> String {
        guard options.isEnabled else { return text }
        return SpokenPunctuationFormatter.apply(
            text,
            prefix: options.prefix,
            rules: options.rules,
            actionRules: options.actionRules,
            appName: context.appName,
            bundleID: context.bundleID,
            windowTitle: context.windowTitle
        )
    }

    /// Applies literal slash-command and @mention formatting.
    static func applyLiteralFormatting(
        _ text: String,
        options: LiteralFormattingOptions,
        context: Context
    ) -> String {
        DictationLiteralFormatter.applyDictationLiteralFormatting(
            text,
            enabled: options.isEnabled,
            appName: context.appName,
            bundleID: context.bundleID,
            windowTitle: context.windowTitle
        )
    }

    /// Removes a trailing period and/or lowercases the first letter (GAAV mode).
    static func applyGAAVFormatting(_ text: String, options: GAAVOptions) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        if options.removeTrailingPeriod, result.hasSuffix(".") {
            result.removeLast()
        }
        if options.lowercaseFirstLetter, let first = result.first, first.isUppercase {
            result = first.lowercased() + result.dropFirst()
        }
        return result
    }

    /// Applies continuous-dictation spacing and context-aware capitalization.
    static func applyContinuousDictationFormatting(_ text: String, options: ContinuousOptions) -> String {
        guard !text.isEmpty else { return text }
        guard options.spacingEnabled || options.smartCapitalizationEnabled else { return text }

        var result = text
        if options.smartCapitalizationEnabled {
            let precedingTrimmed = options.precedingText.trimmingCharacters(in: .whitespaces)
            let boundaryCharacter = self.lastCapitalizationBoundaryCharacter(in: precedingTrimmed)
            if boundaryCharacter == nil || boundaryCharacter?.isSentenceEndingPunctuation == true {
                result = self.replacingFirstLetter(in: result, transform: { $0.uppercased() })
            } else {
                result = self.replacingFirstLetter(in: result, transform: { $0.lowercased() })
            }
        }
        if options.spacingEnabled {
            if let lastPreceding = options.precedingText.last,
               !lastPreceding.isWhitespace,
               result.first?.isWhitespace != true
            {
                result = " " + result
            }
            if result.last?.isWhitespace != true {
                result += " "
            }
        }
        return result
    }

    /// Removes terminal whitespace that would break autocomplete inside literal
    /// slash-command / mention applications.
    static func applyTerminalLiteralAutocompleteSpacing(
        _ text: String,
        options: LiteralFormattingOptions,
        context: Context
    ) -> String {
        DictationLiteralFormatter.applyTerminalLiteralAutocompleteSpacing(
            text,
            enabled: options.isEnabled,
            appName: context.appName,
            bundleID: context.bundleID,
            windowTitle: context.windowTitle
        )
    }

    /// Runs the guarded local punctuation cleanup.
    ///
    /// The candidate is only accepted when ``LocalPunctuationCleanup/accepts(original:candidate:)``
    /// approves it, so an out-of-trial rewrite returns the original text.
    static func applyGuardedLocalCleanup(
        _ text: String,
        selection: LocalCleanupSelection,
        cleaner: LocalCleanup
    ) async -> (text: String, outcome: CleanupOutcome) {
        guard selection.isSelected else { return (text, .notSelected) }
        guard !text.isEmpty, text.count <= LocalPunctuationCleanup.maximumCleanupCharacterCount else {
            return (text, .unchanged)
        }
        guard let candidate = await cleaner(text) else { return (text, .unavailable) }
        guard candidate != text else { return (text, .unchanged) }
        guard LocalPunctuationCleanup.accepts(original: text, candidate: candidate) else {
            return (text, .rejected)
        }
        return (candidate, .applied)
    }

    // MARK: - Composition

    /// Filler removal, custom-dictionary replacement, and spoken punctuation —
    /// the deterministic personalization applied to raw recognized text.
    static func applyRecognitionPersonalization(
        _ rawText: String,
        options: Options,
        context: Context = .empty
    ) -> StageOutcome {
        var text = rawText
        var stages: [Stage] = []
        var trace: [TraceEntry] = []

        if options.filler.isEnabled {
            text = self.removeFillerWords(text, options: options.filler)
            stages.append(.fillerRemoval)
            trace.append(TraceEntry(stage: .fillerRemoval, text: text))
        }
        if !options.dictionary.entries.isEmpty {
            text = self.applyCustomDictionary(text, options: options.dictionary)
            stages.append(.customDictionary)
            trace.append(TraceEntry(stage: .customDictionary, text: text))
        }
        if options.spokenPunctuation.isEnabled {
            text = self.applySpokenPunctuation(text, options: options.spokenPunctuation, context: context)
            stages.append(.spokenPunctuation)
            trace.append(TraceEntry(stage: .spokenPunctuation, text: text))
        }
        return StageOutcome(text: text, stagesApplied: stages, trace: trace)
    }

    /// Literal formatting, GAAV, continuous dictation, and terminal spacing —
    /// the deterministic output formatting applied just before delivery.
    static func applyOutputFormatting(
        _ input: String,
        options: Options,
        context: Context = .empty
    ) -> StageOutcome {
        var text = input
        var stages: [Stage] = []
        var trace: [TraceEntry] = []

        if options.literalFormatting.isEnabled {
            text = self.applyLiteralFormatting(text, options: options.literalFormatting, context: context)
            stages.append(.literalFormatting)
            trace.append(TraceEntry(stage: .literalFormatting, text: text))
        }

        if options.gaav.removeTrailingPeriod || options.gaav.lowercaseFirstLetter {
            text = self.applyGAAVFormatting(text, options: options.gaav)
            stages.append(.gaavFormatting)
            trace.append(TraceEntry(stage: .gaavFormatting, text: text))
        }

        if options.continuous.spacingEnabled || options.continuous.smartCapitalizationEnabled {
            text = self.applyContinuousDictationFormatting(text, options: options.continuous)
            stages.append(.continuousDictation)
            trace.append(TraceEntry(stage: .continuousDictation, text: text))
        }

        if options.literalFormatting.isEnabled {
            text = self.applyTerminalLiteralAutocompleteSpacing(
                text,
                options: options.literalFormatting,
                context: context
            )
            stages.append(.terminalSpacing)
            trace.append(TraceEntry(stage: .terminalSpacing, text: text))
        }

        return StageOutcome(text: text, stagesApplied: stages, trace: trace)
    }

    /// Full deterministic pipeline: personalization, optional guarded local
    /// cleanup, then output formatting.
    static func process(
        _ rawText: String,
        context: Context,
        options: Options,
        engineIdentity: EngineIdentity = .unknown(),
        cleaner: LocalCleanup? = nil
    ) async -> Result {
        let personalization = self.applyRecognitionPersonalization(rawText, options: options, context: context)
        var text = personalization.text
        var stages = personalization.stagesApplied
        var trace = personalization.trace
        var cleanupOutcome: CleanupOutcome = .notSelected
        var cleanupModel: String?

        if options.localCleanup.isSelected {
            let effectiveCleaner = cleaner ?? { text in
                await LocalPunctuationCleanup.generateCandidate(text)
            }
            let cleanup = await self.applyGuardedLocalCleanup(
                text,
                selection: options.localCleanup,
                cleaner: effectiveCleaner
            )
            text = cleanup.text
            cleanupOutcome = cleanup.outcome
            cleanupModel = options.localCleanup.model
            stages.append(.localCleanup)
            trace.append(TraceEntry(stage: .localCleanup, text: text))
        }

        let output = self.applyOutputFormatting(text, options: options, context: context)
        text = output.text
        stages.append(contentsOf: output.stagesApplied)
        trace.append(contentsOf: output.trace)

        return Result(
            text: text,
            stagesApplied: stages,
            cleanupOutcome: cleanupOutcome,
            cleanupModel: cleanupModel,
            trace: trace,
            engineIdentity: engineIdentity
        )
    }

    // MARK: - Custom dictionary cache

    private static var dictionaryCache: (entries: [DictionaryEntry], patterns: [(regex: NSRegularExpression, template: String)])?
    private static let dictionaryCacheLock = NSLock()

    /// Invalidates the compiled custom-dictionary cache.
    static func invalidateDictionaryCache() {
        self.dictionaryCacheLock.lock()
        self.dictionaryCache = nil
        self.dictionaryCacheLock.unlock()
    }

    private static func dictionaryPatterns(
        for entries: [DictionaryEntry]
    ) -> [(regex: NSRegularExpression, template: String)] {
        self.dictionaryCacheLock.lock()
        defer { self.dictionaryCacheLock.unlock() }

        if let cached = self.dictionaryCache, cached.entries == entries {
            return cached.patterns
        }
        let patterns = self.compileDictionaryPatterns(for: entries)
        self.dictionaryCache = (entries, patterns)
        return patterns
    }

    private static func compileDictionaryPatterns(
        for entries: [DictionaryEntry]
    ) -> [(regex: NSRegularExpression, template: String)] {
        var patterns: [(regex: NSRegularExpression, template: String)] = []
        for entry in entries {
            for trigger in entry.triggers {
                guard !trigger.isEmpty else { continue }
                let consumesHorizontalSeparators = !entry.replacement.isEmpty &&
                    entry.replacement.allSatisfy(\.isWhitespace)
                let escapedTrigger = self.dictionaryPattern(
                    for: trigger,
                    consumesHorizontalSeparators: consumesHorizontalSeparators
                )
                guard let regex = try? NSRegularExpression(
                    pattern: escapedTrigger,
                    options: .caseInsensitive
                ) else { continue }
                patterns.append((regex: regex, template: NSRegularExpression.escapedTemplate(for: entry.replacement)))
            }
        }
        return patterns.sorted {
            $0.regex.pattern.utf16.count > $1.regex.pattern.utf16.count
        }
    }

    private static func dictionaryPattern(
        for trigger: String,
        consumesHorizontalSeparators: Bool = false
    ) -> String {
        let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
        let prefix = self.startsWithWordCharacter(trigger) ? "\\b" : ""
        let suffix = self.endsWithWordCharacter(trigger) ? "\\b" : ""
        let separator = consumesHorizontalSeparators ? "[ \\t]*" : ""
        return separator + prefix + escapedTrigger + suffix + separator
    }

    private static func startsWithWordCharacter(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return self.isWordCharacter(scalar)
    }

    private static func endsWithWordCharacter(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last else { return false }
        return self.isWordCharacter(scalar)
    }

    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    // MARK: - Continuous dictation helpers

    private static func lastCapitalizationBoundaryCharacter(in text: String) -> Character? {
        for character in text.reversed() {
            if character.isNewline {
                return nil
            }
            if character.isHorizontalWhitespace || character.isClosingPunctuationWrapper {
                continue
            }
            return character
        }
        return nil
    }

    private static func replacingFirstLetter(in text: String, transform: (Character) -> String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter }) else { return text }
        let nextIndex = text.index(after: index)
        return String(text[..<index]) + transform(text[index]) + String(text[nextIndex...])
    }
}

private extension Character {
    var isSentenceEndingPunctuation: Bool {
        self == "." || self == "!" || self == "?"
    }

    var isHorizontalWhitespace: Bool {
        self.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    var isClosingPunctuationWrapper: Bool {
        switch self {
        case "\"", "'", "”", "’", "»", "›", ")", "]", "}", "」", "』":
            return true
        default:
            return false
        }
    }
}
