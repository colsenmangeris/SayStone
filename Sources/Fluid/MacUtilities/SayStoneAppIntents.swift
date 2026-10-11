import AppIntents
import Foundation

extension UtilityTextTransform: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Text transformation" }
    static var caseDisplayRepresentations: [UtilityTextTransform: DisplayRepresentation] {
        [.trim: "Trim whitespace", .uppercase: "Uppercase", .lowercase: "Lowercase", .collapseWhitespace: "Collapse whitespace", .removeLineBreaks: "Remove line breaks"]
    }
}

nonisolated struct TransformSayStoneTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Transform text with SayStone"
    static var description = IntentDescription("Apply a deterministic text transformation locally.")
    @Parameter(title: "Text") var text: String
    @Parameter(title: "Transformation", default: .trim) var transformation: UtilityTextTransform
    static var parameterSummary: some ParameterSummary { Summary("Transform \(\.$text) with \(\.$transformation)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try UtilityActionRegistry.validate(.init(id: .transformText, text: text, transform: transformation))
        return .result(value: transformation.apply(to: text))
    }
}

nonisolated struct CopyLatestSayStoneTranscriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy latest SayStone transcript"
    static var description = IntentDescription("Copy the most recent available dictation text to the clipboard.")
    static var openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Copy the latest SayStone transcript") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await MacUtilityCoordinator.shared.execute(.init(id: .copyLatestTranscript))
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

nonisolated struct SayStoneWorkflowEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "SayStone workflow" }
    static var defaultQuery = SayStoneWorkflowQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}

nonisolated struct SayStoneWorkflowQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SayStoneWorkflowEntity] {
        await MainActor.run {
            MacUtilityCoordinator.shared.workflows.workflows.filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
        }
    }
    func entities(matching string: String) async throws -> [SayStoneWorkflowEntity] {
        await MainActor.run {
            MacUtilityCoordinator.shared.workflows.workflows.filter { $0.name.localizedCaseInsensitiveContains(string) }.map { .init(id: $0.id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [SayStoneWorkflowEntity] {
        await MainActor.run { MacUtilityCoordinator.shared.workflows.workflows.map { .init(id: $0.id, name: $0.name) } }
    }
}

nonisolated struct RunSayStoneWorkflowIntent: AppIntent {
    static var title: LocalizedStringResource = "Run SayStone workflow"
    static var description = IntentDescription("Run an explicitly configured SayStone workflow. Workflows with paste steps are available through SayStone's palette and configured shortcuts.")
    static var openAppWhenRun = true
    @Parameter(title: "Workflow") var workflow: SayStoneWorkflowEntity
    @Parameter(title: "Input text", default: "") var inputText: String
    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$workflow) with \(\.$inputText)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let output = try await MacUtilityCoordinator.shared.runWorkflowFromIntent(id: workflow.id, input: inputText)
        return .result(value: output)
    }
}

nonisolated struct OpenSayStoneUtilitiesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open SayStone utilities"
    static var openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Open SayStone utilities") }
    @MainActor func perform() async throws -> some IntentResult {
        MacUtilityCoordinator.shared.show()
        return .result()
    }
}

nonisolated struct SayStoneAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenSayStoneUtilitiesIntent(), phrases: ["Open utilities in \(.applicationName)"], shortTitle: "Open utilities", systemImageName: "command")
        AppShortcut(intent: CopyLatestSayStoneTranscriptIntent(), phrases: ["Copy latest transcript in \(.applicationName)"], shortTitle: "Copy latest transcript", systemImageName: "doc.on.doc")
    }
}
