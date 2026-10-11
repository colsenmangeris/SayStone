import AppKit
import SwiftUI

struct UtilityWorkspaceView: View {
    @ObservedObject var coordinator: MacUtilityCoordinator
    @ObservedObject private var library: ClipboardLibrary
    @ObservedObject private var workflows: UtilityWorkflowStore

    init(coordinator: MacUtilityCoordinator) {
        self.coordinator = coordinator
        self.library = coordinator.library
        self.workflows = coordinator.workflows
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach([("palette", "Actions", "command"), ("clipboard", "Clipboard", "clipboard"), ("workflows", "Workflows", "list.bullet.rectangle"), ("shortcuts", "Shortcuts", "keyboard")], id: \.0) { tab in
                    Button { coordinator.selectedTab = tab.0 } label: { Label(tab.1, systemImage: tab.2) }
                        .buttonStyle(.bordered)
                        .tint(coordinator.selectedTab == tab.0 ? .accentColor : .secondary)
                        .accessibilityIdentifier("utilities.tab.\(tab.0)")
                }
                Spacer()
            }
            Divider()
            Group {
                switch coordinator.selectedTab {
                case "clipboard":
                    ClipboardLibraryView(library: library, onCopy: { coordinator.perform(.init(id: .copyText, text: $0)) }, onPaste: { coordinator.perform(.init(id: .pasteText, text: $0)) })
                case "workflows":
                    UtilityWorkflowView(store: workflows, runner: coordinator.workflowRunner, snippetOptions: library.snippets.map { .init(id: $0.id, name: $0.title) }, run: { coordinator.runWorkflow($0, input: $1) })
                case "shortcuts":
                    UtilityShortcutsView(coordinator: coordinator)
                default:
                    UtilityPaletteView(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(coordinator.message).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("utilities.status")
                Spacer()
                if coordinator.isExecuting { ProgressView().controlSize(.small) }
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 580)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("utilities.workspace")
    }
}

private struct UtilityPaletteView: View {
    @ObservedObject var coordinator: MacUtilityCoordinator
    @State private var query = ""
    @State private var selection: UtilityActionID? = .copyLatestTranscript
    @State private var text = ""
    @State private var parameter = ""
    @State private var transformation = UtilityTextTransform.trim
    @State private var snippetID: UUID?
    @State private var result = ""
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?

    private var descriptors: [UtilityActionDescriptor] {
        UtilityActionRegistry.descriptors.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack {
                TextField("Search actions", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("utilities.palette.search")
                List(selection: $selection) {
                    ForEach(descriptors) { descriptor in
                        Label(descriptor.title, systemImage: descriptor.systemImage)
                            .tag(descriptor.id)
                            .accessibilityIdentifier("utilities.action.\(descriptor.id.rawValue)")
                    }
                }
            }
            .frame(width: 250)
            VStack(alignment: .leading, spacing: 12) {
                if let selection {
                    let descriptor = UtilityActionRegistry.descriptor(for: selection)
                    Text(descriptor.title).font(.title2)
                    Text(descriptor.detail).foregroundStyle(.secondary)
                    if [.copyText, .pasteText, .transformText, .runAppleShortcut].contains(selection) {
                        Text("Text").font(.headline)
                        PromptTextView(text: $text, font: .systemFont(ofSize: NSFont.systemFontSize), allowsAutomaticTextSubstitution: false, accessibilityID: "utilities.palette.text")
                            .frame(minHeight: 100, maxHeight: 180)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                            .accessibilityIdentifier("utilities.palette.text")
                    }
                    if selection == .transformText {
                        Picker("Transformation", selection: $transformation) {
                            ForEach(UtilityTextTransform.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("utilities.palette.transform")
                    }
                    if [.openURL, .launchApp, .runAppleShortcut].contains(selection) {
                        TextField(parameterTitle(selection), text: $parameter)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("utilities.palette.parameter")
                    }
                    if selection == .insertSnippet {
                        Picker("Snippet", selection: $snippetID) {
                            Text("Choose a snippet").tag(UUID?.none)
                            ForEach(coordinator.library.snippets) { Text($0.title).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("utilities.palette.snippet")
                    }
                    Button(isRunning ? "Running…" : "Run action", action: run)
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(isRunning || coordinator.workflowRunner.state.isRunning)
                        .accessibilityIdentifier("utilities.palette.run")
                    if isRunning {
                        Button("Cancel action") { runTask?.cancel() }
                            .accessibilityIdentifier("utilities.palette.cancel")
                    }
                    if !result.isEmpty {
                        Text(result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("utilities.palette.result")
                    }
                    Spacer()
                } else {
                    ContentUnavailableView("Choose an action", systemImage: "command")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: query) { _, _ in
            if !descriptors.contains(where: { $0.id == selection }) { selection = descriptors.first?.id }
        }
        .onDisappear { runTask?.cancel() }
    }

    private func parameterTitle(_ id: UtilityActionID) -> String {
        switch id {
        case .openURL: return "URL, such as https://example.com"
        case .launchApp: return "App bundle identifier, such as com.apple.TextEdit"
        default: return "Apple Shortcut name"
        }
    }

    private func run() {
        guard let selection else { return }
        let request = UtilityActionRequest(id: selection, text: text, transform: transformation, snippetID: snippetID, urlString: parameter, bundleIdentifier: parameter, shortcutName: parameter)
        isRunning = true
        runTask = Task {
            defer { isRunning = false; runTask = nil }
            do {
                let outcome = try await coordinator.execute(request)
                result = outcome.output ?? outcome.message
                coordinator.message = outcome.message
            } catch {
                result = error.localizedDescription
                coordinator.message = result
            }
        }
    }
}

private struct UtilityShortcutsView: View {
    @ObservedObject var coordinator: MacUtilityCoordinator
    @ObservedObject private var store: UtilityShortcutStore
    @State private var target = UtilityShortcutTarget.copyLatestTranscript
    @State private var itemID: UUID?
    @State private var appID = ""
    @State private var draftShortcut: HotkeyShortcut?
    @State private var monitor: Any?
    @State private var captureMessage = ""

    init(coordinator: MacUtilityCoordinator) {
        self.coordinator = coordinator
        self.store = coordinator.shortcuts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Utility shortcuts").font(.title2)
            Text("Choose a keyboard chord. Leave the app identifier empty to use it across apps.")
                .foregroundStyle(.secondary)
            Picker("Action", selection: $target) {
                ForEach(UtilityShortcutTarget.allCases, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("utilities.shortcuts.action")
            if target == .workflow {
                Picker("Workflow", selection: $itemID) {
                    Text("Choose a workflow").tag(UUID?.none)
                    ForEach(coordinator.workflows.workflows) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if target == .snippet {
                Picker("Snippet", selection: $itemID) {
                    Text("Choose a snippet").tag(UUID?.none)
                    ForEach(coordinator.library.snippets) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            TextField("App bundle identifier (optional)", text: $appID)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("utilities.shortcuts.app")
            HStack {
                Button(coordinator.isRecordingShortcut ? "Cancel recording" : "Record shortcut", action: toggleCapture)
                    .accessibilityIdentifier("utilities.shortcuts.record")
                Text(draftShortcut?.displayString ?? "Unassigned")
                    .accessibilityIdentifier("utilities.shortcuts.chord")
                Button("Save shortcut") {
                    guard let draftShortcut else { return }
                    if store.save(.init(target: target, shortcut: draftShortcut, itemID: itemID, appBundleIdentifier: appID.trimmingCharacters(in: .whitespacesAndNewlines))) {
                        self.draftShortcut = nil
                        captureMessage = "Shortcut saved."
                    }
                }
                .disabled(draftShortcut == nil || coordinator.isRecordingShortcut)
                .accessibilityIdentifier("utilities.shortcuts.save")
            }
            Text(store.lastError ?? captureMessage).foregroundStyle(.secondary)
                .accessibilityIdentifier("utilities.shortcuts.status")
            List(store.bindings) { binding in
                HStack {
                    Text(binding.target.title)
                    Spacer()
                    Text(binding.shortcut.displayString).foregroundStyle(.secondary)
                    if !binding.appBundleIdentifier.isEmpty { Text(binding.appBundleIdentifier).font(.caption) }
                    Button("Remove") { store.remove(id: binding.id) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("utilities.shortcuts.binding.\(binding.id)")
            }
        }
        .onDisappear(perform: stopCapture)
    }

    private func toggleCapture() {
        if coordinator.isRecordingShortcut { stopCapture(); return }
        coordinator.isRecordingShortcut = true
        captureMessage = "Press your shortcut. Escape cancels."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopCapture(); return nil }
            guard !event.isARepeat else { return nil }
            let shortcut = HotkeyShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags.intersection(HotkeyShortcut.relevantModifierMask))
            if let message = UtilityShortcutRules.validationMessage(shortcut, reserved: UtilityShortcutStore.reservedShortcuts()) {
                captureMessage = message
            } else {
                draftShortcut = shortcut
                captureMessage = "Ready to save."
                stopCapture()
            }
            return nil
        }
    }

    private func stopCapture() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        coordinator.isRecordingShortcut = false
    }
}
