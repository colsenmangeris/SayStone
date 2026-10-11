import AppKit
import SwiftUI

struct UtilityWorkflowSnippetOption: Identifiable {
    let id: UUID
    let name: String
}

/// Definitions remain drafts until Save. The coordinator owns executing actions
/// and selecting the intended external target before this editor becomes active.
struct UtilityWorkflowView: View {
    @ObservedObject var store: UtilityWorkflowStore
    @ObservedObject var runner: UtilityWorkflowRunner
    var snippetOptions: [UtilityWorkflowSnippetOption] = []
    var run: (UtilityWorkflow, String) -> Void

    @State private var selectedID: UUID?
    @State private var draft = UtilityWorkflow()
    @State private var hasSelection = false
    @State private var initialText = ""
    @State private var editorError: String?
    @State private var deletingWorkflow = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Workflows").font(.headline)
                    Spacer()
                    Button(action: createWorkflow) {
                        Label("Add workflow", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(runner.state.isRunning)
                    .accessibilityIdentifier("utilities.workflows.add")
                }
                List(store.workflows, selection: $selectedID) { workflow in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workflow.name)
                        Text("\(workflow.steps.count) steps")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(workflow.id)
                    .accessibilityIdentifier("utilities.workflows.row.\(workflow.id.uuidString)")
                }
                .disabled(runner.state.isRunning)
                .accessibilityIdentifier("utilities.workflows.list")
                if store.workflows.isEmpty {
                    Text("Create a workflow to combine local actions.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 300)

            ScrollView {
                if hasSelection {
                    editor
                        .padding(20)
                } else {
                    ContentUnavailableView {
                        Label("No workflow selected", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Combine text, snippets, links, apps and named Apple Shortcuts.")
                    } actions: {
                        Button("Create workflow", action: createWorkflow)
                            .accessibilityIdentifier("utilities.workflows.create")
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !hasSelection, let first = store.workflows.first { select(first) }
        }
        .onChange(of: selectedID) { _, newValue in
            if let workflow = store.workflows.first(where: { $0.id == newValue }) { select(workflow) }
        }
        .confirmationDialog("Delete this workflow?", isPresented: $deletingWorkflow) {
            Button("Delete workflow", role: .destructive, action: deleteWorkflow)
            Button("Keep workflow", role: .cancel) {}
        } message: {
            Text("This removes its saved steps and voice trigger.")
        }
        .accessibilityIdentifier("utilities.workflows.editor")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Workflow name", text: $draft.name)
                    .font(.title2)
                    .accessibilityIdentifier("utilities.workflows.name")
                Spacer()
                Button("Save workflow", action: saveWorkflow)
                    .disabled(runner.state.isRunning)
                    .accessibilityIdentifier("utilities.workflows.save")
                Button(role: .destructive) { deletingWorkflow = true } label: {
                    Label("Delete workflow", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .disabled(runner.state.isRunning)
                .accessibilityIdentifier("utilities.workflows.delete")
            }
            if let error = editorError ?? store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("utilities.workflows.error")
            }
            if store.recoveryFileURL != nil {
                Text("The previous unreadable file was preserved in the workflow data folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Dictation input") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use this workflow after dictation", isOn: Binding(
                        get: { draft.runsAfterDictation == true },
                        set: { draft.runsAfterDictation = $0 }
                    ))
                    .accessibilityIdentifier("utilities.workflows.afterDictation")
                    Text("Replaces ordinary automatic delivery. Add a Paste text step to insert the result. Saving this selection turns off the previous selection.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("On failure or cancellation, recognized text stays in SayStone. Completed actions are not repeated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .disabled(runner.state.isRunning)
            GroupBox("Voice trigger") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable exact voice phrase", isOn: $draft.voiceEnabled)
                        .accessibilityIdentifier("utilities.workflows.voiceEnabled")
                    TextField("Voice phrase", text: $draft.voicePhrase)
                        .disabled(!draft.voiceEnabled)
                        .accessibilityIdentifier("utilities.workflows.voicePhrase")
                    Text("Case and repeated spaces are ignored. Other dictation remains ordinary text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .disabled(runner.state.isRunning)

            VStack(alignment: .leading, spacing: 12) {
                ForEach($draft.steps) { step in
                    UtilityWorkflowStepEditor(
                        step: step,
                        snippetOptions: snippetOptions,
                        index: draft.steps.firstIndex(where: { $0.id == step.wrappedValue.id }) ?? 0,
                        stepCount: draft.steps.count,
                        move: { offset in moveStep(id: step.wrappedValue.id, offset: offset) },
                        remove: { draft.steps.removeAll { $0.id == step.wrappedValue.id } }
                    )
                }
                Button {
                    draft.steps.append(UtilityWorkflowStep(action: UtilityActionRequest(id: .transformText, transform: .trim)))
                } label: {
                    Label("Add step", systemImage: "plus")
                }
                .disabled(draft.steps.count >= UtilityWorkflow.maximumSteps)
                .accessibilityIdentifier("utilities.workflows.addStep")
            }
            .disabled(runner.state.isRunning)

            GroupBox("Run limits") {
                HStack {
                    Stepper("Run: \(Int(draft.timeoutSeconds)) seconds", value: $draft.timeoutSeconds, in: 1...120)
                        .accessibilityIdentifier("utilities.workflows.runLimit")
                    Spacer(minLength: 20)
                    Stepper("Step: \(Int(draft.stepTimeoutSeconds)) seconds", value: $draft.stepTimeoutSeconds, in: 1...30)
                        .accessibilityIdentifier("utilities.workflows.stepLimit")
                }
                .padding(8)
            }
            .disabled(runner.state.isRunning)

            GroupBox("Workflow input") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The first step receives this authored text. A step can instead use the latest transcript or its own text.")
                        .font(.caption).foregroundStyle(.secondary)
                    PromptTextView(
                        text: $initialText,
                        font: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                        contentInset: 5,
                        allowsAutomaticTextSubstitution: false,
                        accessibilityID: "utilities.workflows.input"
                    )
                        .frame(minHeight: 80)
                        .accessibilityIdentifier("utilities.workflows.input")
                }
                .padding(8)
            }
            .disabled(runner.state.isRunning)

            HStack {
                Button("Run workflow") {
                    do {
                        try draft.validate()
                        editorError = nil
                        run(draft, initialText)
                    } catch { editorError = error.localizedDescription }
                }
                .disabled(runner.state.isRunning)
                .accessibilityIdentifier("utilities.workflows.run")
                if runner.state.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel run", action: runner.cancel)
                        .disabled(runner.state == .cancelling)
                        .accessibilityIdentifier("utilities.workflows.cancel")
                }
                Text(runner.state.title)
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("utilities.workflows.status")
            }
            if !runner.results.isEmpty {
                GroupBox("Step results") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(runner.results) { result in
                            Label("\(result.index + 1). \(result.message)", systemImage: "checkmark.circle")
                                .textSelection(.enabled)
                                .accessibilityIdentifier("utilities.workflows.result.\(result.id.uuidString)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            if let output = runner.output, !output.isEmpty {
                GroupBox("Text output") {
                    Text(String(output.prefix(16_384)))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .accessibilityIdentifier("utilities.workflows.output")
                }
            }
        }
    }

    private func createWorkflow() {
        draft = UtilityWorkflow()
        selectedID = draft.id
        hasSelection = true
        editorError = nil
    }

    private func select(_ workflow: UtilityWorkflow) {
        draft = workflow
        selectedID = workflow.id
        hasSelection = true
        editorError = nil
    }

    private func saveWorkflow() {
        do { try store.save(draft); editorError = nil } catch { editorError = error.localizedDescription }
    }

    private func deleteWorkflow() {
        do {
            try store.delete(id: draft.id)
            editorError = nil
            if let first = store.workflows.first { select(first) } else { selectedID = nil; hasSelection = false }
        } catch { editorError = error.localizedDescription }
    }

    private func moveStep(id: UUID, offset: Int) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }),
              draft.steps.indices.contains(index + offset) else { return }
        draft.steps.swapAt(index, index + offset)
    }
}

private struct UtilityWorkflowStepEditor: View {
    @Binding var step: UtilityWorkflowStep
    let snippetOptions: [UtilityWorkflowSnippetOption]
    let index: Int
    let stepCount: Int
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Step \(index + 1)").font(.headline)
                    Spacer()
                    Button { move(-1) } label: { Label("Move step up", systemImage: "arrow.up") }
                        .disabled(index == 0)
                        .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).up")
                    Button { move(1) } label: { Label("Move step down", systemImage: "arrow.down") }
                        .disabled(index == stepCount - 1)
                        .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).down")
                    Button(role: .destructive, action: remove) { Label("Remove step", systemImage: "minus") }
                        .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).remove")
                }
                .labelStyle(.iconOnly)
                Picker("Action", selection: actionBinding) {
                    ForEach(UtilityActionRegistry.descriptors) { descriptor in
                        Text(descriptor.title).tag(descriptor.id)
                    }
                }
                .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).action")
                if UtilityWorkflow.usesText(step.action.id) {
                    Picker("Text source", selection: $step.input) {
                        ForEach(UtilityWorkflowInputSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).source")
                    if step.input == .fixedText {
                        PromptTextView(
                            text: optionalText(\.text),
                            font: .systemFont(ofSize: NSFont.systemFontSize),
                            contentInset: 5,
                            allowsAutomaticTextSubstitution: false,
                            accessibilityID: "utilities.workflows.step.\(step.id.uuidString).text"
                        )
                            .frame(minHeight: 65)
                            .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).text")
                    }
                }
                parameters
            }
            .padding(8)
        }
    }

    @ViewBuilder private var parameters: some View {
        switch step.action.id {
        case .transformText:
            Picker("Transformation", selection: Binding(
                get: { step.action.transform ?? .trim },
                set: { step.action.transform = $0 }
            )) {
                ForEach(UtilityTextTransform.allCases) { transform in
                    Text(transform.title).tag(transform)
                }
            }
            .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).transform")
        case .insertSnippet:
            Picker("Snippet", selection: $step.action.snippetID) {
                Text("Choose snippet").tag(Optional<UUID>.none)
                ForEach(snippetOptions) { snippet in
                    Text(snippet.name).tag(Optional(snippet.id))
                }
            }
            .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).snippet")
        case .openURL:
            TextField("https://example.com", text: optionalText(\.urlString))
                .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).url")
        case .launchApp:
            TextField("Application bundle ID, e.g. com.apple.TextEdit", text: optionalText(\.bundleIdentifier))
                .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).app")
        case .runAppleShortcut:
            TextField("Exact name in Apple's Shortcuts app", text: optionalText(\.shortcutName))
                .accessibilityIdentifier("utilities.workflows.step.\(step.id.uuidString).shortcut")
            Text("Choose a shortcut you have reviewed. SayStone runs its fixed name with separate arguments.")
                .font(.caption).foregroundStyle(.secondary)
        case .copyLatestTranscript:
            Text("Copies the latest raw transcript and passes that text to the next step.")
                .font(.caption).foregroundStyle(.secondary)
        case .pastePlainText:
            Text("Reads clipboard text only when this step runs. The target must still match the captured field.")
                .font(.caption).foregroundStyle(.secondary)
        case .copyText, .pasteText:
            EmptyView()
        }
    }

    private var actionBinding: Binding<UtilityActionID> {
        Binding(get: { step.action.id }, set: { newAction in
            let text = step.action.text
            step.action = UtilityActionRequest(id: newAction, text: text, transform: newAction == .transformText ? .trim : nil)
        })
    }

    private func optionalText(_ keyPath: WritableKeyPath<UtilityActionRequest, String?>) -> Binding<String> {
        Binding(get: { step.action[keyPath: keyPath] ?? "" }, set: { step.action[keyPath: keyPath] = $0 })
    }
}
