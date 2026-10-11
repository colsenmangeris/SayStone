import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI

@MainActor
final class MacUtilityCoordinator: ObservableObject {
    static let shared = MacUtilityCoordinator()
    let library: ClipboardLibrary
    let workflows: UtilityWorkflowStore
    let workflowRunner = UtilityWorkflowRunner()
    let shortcuts: UtilityShortcutStore
    @Published var message = "Choose an action."
    @Published var selectedTab = "palette"
    @Published private(set) var isExecuting = false
    @Published var isRecordingShortcut = false
    private var window: NSWindow?
    private var target: TypingService.CapturedFocusTarget?
    private var actionTask: Task<Void, Never>?
    private var pendingShortcutTask: Task<Void, Never>?
    private var isDispatching = false
    private var isIntentExecuting = false
    private let pasteboard: NSPasteboard
    private var latestDictationText: String?

    init() {
        let root = DevelopmentRuntime.utilityDirectory
        self.library = ClipboardLibrary(storageURL: root.appendingPathComponent("clipboard.json"), allowsPolling: !DevelopmentRuntime.isUITesting)
        self.workflows = UtilityWorkflowStore(url: root.appendingPathComponent("workflows.json"))
        self.shortcuts = UtilityShortcutStore(url: root.appendingPathComponent("shortcuts.json"))
        if DevelopmentRuntime.isUITesting {
            self.pasteboard = NSPasteboard(name: .init("SayStone.UITests.\(DevelopmentRuntime.testSession)"))
        } else {
            self.pasteboard = .general
        }
    }

    func start() {
        guard !DevelopmentRuntime.isUITesting else { return }
        self.library.resumeMonitoringIfEnabled()
    }

    func stop() {
        self.actionTask?.cancel()
        self.pendingShortcutTask?.cancel()
        self.workflowRunner.cancel()
        self.library.stopMonitoring()
    }

    func show(tab: String = "palette", captureTarget: Bool = true) {
        if captureTarget, !DevelopmentRuntime.isUITesting, !self.isExecuting, !self.isDispatching, !self.isIntentExecuting, !self.workflowRunner.state.isRunning, self.pendingShortcutTask == nil {
            self.target = TypingService.captureSystemFocusTarget()
        }
        self.selectedTab = tab
        if self.window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = AppStorage.isDevelopment ? "SayStone Development — Utilities" : "SayStone Utilities"
            window.identifier = .init("saystone.utilities.window")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AdaptiveAppTheme(accent: SettingsStore.shared.accentColor) {
                UtilityWorkspaceView(coordinator: self)
            })
            window.center()
            self.window = window
        }
        if DevelopmentRuntime.isBackgroundUITesting {
            self.window?.orderBack(nil)
        } else {
            self.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func perform(_ request: UtilityActionRequest, captureTarget: Bool = false) {
        guard !self.isExecuting, !self.isIntentExecuting, !self.workflowRunner.state.isRunning else { return }
        if captureTarget, !DevelopmentRuntime.isUITesting { self.target = TypingService.captureSystemFocusTarget() }
        self.isExecuting = true
        self.actionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isExecuting = false; self.actionTask = nil }
            do {
                let result = try await self.execute(request)
                self.message = result.message
            } catch {
                self.message = error.localizedDescription
                self.show(captureTarget: false)
            }
        }
    }

    func latestTranscript() -> String? {
        if let latestDictationText { return latestDictationText }
        if DevelopmentRuntime.isUITesting { return "Authored SayStone UI fixture." }
        return TranscriptionHistoryStore.shared.latestClipboardText
    }

    func recordDictationText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self.latestDictationText = text
    }

    func executeFromIntent(_ request: UtilityActionRequest) async throws -> UtilityActionResult {
        try Task.checkCancellation()
        guard !self.workflowRunner.state.isRunning, !self.isExecuting, !self.isDispatching,
              !self.isIntentExecuting, self.pendingShortcutTask == nil else {
            throw UtilityActionError.invalidInput("Another action or workflow is already running.")
        }
        guard ![.pastePlainText, .pasteText, .insertSnippet].contains(request.id) else {
            throw UtilityActionError.invalidInput("Run paste actions from the palette or a configured shortcut, where a target field can be selected.")
        }
        self.isIntentExecuting = true
        defer { self.isIntentExecuting = false }
        return try await self.execute(request)
    }

    func execute(_ request: UtilityActionRequest) async throws -> UtilityActionResult {
        guard !self.isDispatching else { throw UtilityActionError.invalidInput("Another action is still completing.") }
        self.isDispatching = true
        defer { self.isDispatching = false }
        try Task.checkCancellation()
        try UtilityActionRegistry.validate(request)
        switch request.id {
        case .copyLatestTranscript:
            guard let text = self.latestTranscript() else { throw UtilityActionError.invalidInput("No transcript is available yet.") }
            try UtilityClipboard.copy(text, to: self.pasteboard)
            return .init(output: text, message: "Copied latest transcript.")
        case .copyText:
            let text = request.text ?? ""
            try UtilityClipboard.copy(text, to: self.pasteboard)
            return .init(output: text, message: "Copied text.")
        case .transformText:
            let text = request.transform?.apply(to: request.text ?? "") ?? ""
            return .init(output: text, message: "Text transformed.")
        case .pastePlainText:
            guard let text = self.pasteboard.string(forType: .string), !text.isEmpty else {
                throw UtilityActionError.invalidInput("The clipboard has no plain text.")
            }
            try await self.paste(text)
            return .init(output: text, message: "Plain-text paste dispatched.")
        case .pasteText:
            let text = request.text ?? ""
            try await self.paste(text)
            return .init(output: text, message: "Paste dispatched.")
        case .insertSnippet:
            guard let id = request.snippetID, let snippet = self.library.lookupSnippet(id: id) else {
                throw UtilityActionError.invalidInput("The selected snippet is no longer available.")
            }
            try await self.paste(snippet.text)
            return .init(output: snippet.text, message: "Snippet paste dispatched.")
        case .openURL:
            try self.requireExternalExecution()
            guard let value = request.urlString, let url = URL(string: value), NSWorkspace.shared.open(url) else {
                throw UtilityActionError.invalidInput("macOS could not open this URL.")
            }
            return .init(message: "Opened URL.")
        case .launchApp:
            try self.requireExternalExecution()
            guard let bundle = request.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
                throw UtilityActionError.invalidInput("This application is not installed.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .init(message: "Opened application.")
        case .runAppleShortcut:
            try self.requireExternalExecution()
            return try await self.runAppleShortcut(name: request.shortcutName ?? "", input: request.text)
        }
    }

    private func requireExternalExecution() throws {
        guard !DevelopmentRuntime.isUITesting else {
            throw UtilityActionError.invalidInput("External actions are disabled in synthetic UI tests.")
        }
    }

    private func paste(_ text: String) async throws {
        try self.requireExternalExecution()
        guard AXIsProcessTrusted() else {
            let appName = AppStorage.isDevelopment ? "SayStone Development" : "SayStone"
            throw UtilityActionError.invalidInput("Allow \(appName) in System Settings → Privacy & Security → Accessibility, then select the target field and try again.")
        }
        guard let target = self.target, target.pid != ProcessInfo.processInfo.processIdentifier else {
            throw UtilityActionError.targetChanged
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Returning from our palette is explicit. A switch to any third app invalidates it.
        if frontmost == ProcessInfo.processInfo.processIdentifier {
            self.window?.orderOut(nil)
            guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
                  app.activate(options: TypingService.focusRestoreActivationOptions) else { throw UtilityActionError.targetChanged }
            try await Task.sleep(nanoseconds: 120_000_000)
            guard TypingService.restoreFocusTarget(target) else { throw UtilityActionError.targetChanged }
        }
        try Task.checkCancellation()
        guard TypingService.tryAcquireUtilityPasteSession() else { throw UtilityActionError.clipboardBusy }
        defer { TypingService.releaseUtilityPasteSession() }
        try await UtilityClipboard.withTemporaryText(
            text,
            on: self.pasteboard,
            restoreDelay: 0.35,
            targetIsValid: {
                TypingService.isExactFocusTargetActive(target) &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
            },
            paste: { TypingService.postUtilityPaste(to: target) }
        )
    }

    private func runAppleShortcut(name: String, input: String?) async throws -> UtilityActionResult {
        try await self.confirmAppleShortcut(name: name)
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output.txt")
        var arguments = ["run", name, "--output-path", outputURL.path, "--output-type", "public.plain-text"]
        if let input, !input.isEmpty {
            let inputURL = directory.appendingPathComponent("input.txt")
            try Data(input.utf8).write(to: inputURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputURL.path)
            arguments += ["--input-path", inputURL.path]
        }
        let result = try await UtilityProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"), arguments: arguments, timeout: 30, maxOutputBytes: 1_048_576)
        try Task.checkCancellation()
        guard result.exitCode == 0 else { throw UtilityActionError.invalidInput("Apple Shortcut failed: \(String(result.stderr.prefix(500)))") }
        var output: String?
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let handle = try FileHandle(forReadingFrom: outputURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: UtilityActionRegistry.maximumTextBytes + 1) ?? Data()
            guard data.count <= UtilityActionRegistry.maximumTextBytes else {
                throw UtilityActionError.invalidInput("Apple Shortcut output exceeded 1 MiB.")
            }
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw UtilityActionError.invalidInput("Apple Shortcut output was not UTF-8 text.")
            }
            output = decoded
        }
        return .init(output: output, message: "Apple Shortcut completed.")
    }

    private func confirmAppleShortcut(name: String) async throws {
        self.show(tab: self.selectedTab, captureTarget: false)
        guard let window = self.window else { throw UtilityActionError.invalidInput("Open the utility window to confirm this shortcut.") }
        let alert = NSAlert()
        alert.messageText = "Run Apple Shortcut “\(name)”?"
        alert.informativeText = "Apple Shortcuts can send messages, change files or run other actions. Review this shortcut in Apple's Shortcuts app before running it."
        alert.addButton(withTitle: "Run Shortcut")
        alert.addButton(withTitle: "Cancel")
        let response = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor in
                if alert.window.sheetParent != nil { NSApp.endSheet(alert.window, returnCode: NSApplication.ModalResponse.cancel.rawValue) }
            }
        }
        try Task.checkCancellation()
        guard response == .alertFirstButtonReturn else { throw CancellationError() }
    }

    @discardableResult
    func runWorkflow(_ workflow: UtilityWorkflow, input: String, captureTarget: Bool = false) -> Bool {
        guard !Task.isCancelled else { self.message = "Workflow cancelled before starting."; return false }
        guard !self.isExecuting, !self.isDispatching, !self.isIntentExecuting else { self.message = "Wait for the current action to finish."; return false }
        if captureTarget, !DevelopmentRuntime.isUITesting { self.target = TypingService.captureSystemFocusTarget() }
        let started = self.workflowRunner.start(
            workflow: workflow,
            initialText: input,
            latestTranscript: { self.latestTranscript() },
            executor: { try await self.execute($0) }
        )
        self.message = started ? "Workflow started." : self.workflowRunner.state.title
        self.selectedTab = "workflows"
        return started
    }

    func runVoiceWorkflowIfMatched(_ text: String, target: TypingService.CapturedFocusTarget?) -> Bool {
        guard let workflow = self.workflows.matchingVoicePhrase(text) else { return false }
        // Keep the previous ordinary transcript available after ContentView
        // records this recognized trigger in history, including after restart.
        if self.latestDictationText == nil { self.latestDictationText = self.latestTranscript() }
        guard !Task.isCancelled else {
            self.message = "Voice workflow cancelled. Raw dictation is available in SayStone."
            return true
        }
        guard !self.workflowRunner.state.isRunning, !self.isExecuting, !self.isDispatching, !self.isIntentExecuting, self.pendingShortcutTask == nil else {
            self.message = "Voice workflow could not start. Raw dictation is available in SayStone."
            self.show(tab: "workflows", captureTarget: false)
            return true
        }
        self.target = target
        self.runWorkflow(workflow, input: "")
        self.show(tab: "workflows", captureTarget: false)
        return true
    }

    /// An explicitly selected workflow owns delivery. Failure exposes the raw
    /// text without replaying paste or other effects from completed steps.
    func runDictationWorkflowIfSelected(_ text: String, target: TypingService.CapturedFocusTarget?) async -> Bool {
        guard let workflow = self.workflows.dictationWorkflow() else { return false }
        guard !Task.isCancelled else {
            self.message = "Dictation workflow cancelled. Raw dictation is available in SayStone."
            return true
        }
        guard !self.workflowRunner.state.isRunning, !self.isExecuting, !self.isDispatching, !self.isIntentExecuting, self.pendingShortcutTask == nil else {
            self.message = "Dictation workflow could not start. Raw dictation is available in SayStone."
            self.show(tab: "workflows", captureTarget: false)
            return true
        }
        self.target = target
        guard self.runWorkflow(workflow, input: text), let runIdentifier = self.workflowRunner.runIdentifier else { return true }
        self.isIntentExecuting = true
        defer { self.isIntentExecuting = false }
        await withTaskCancellationHandler {
            do {
                while self.workflowRunner.state.isRunning {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                if self.workflowRunner.state == .completed {
                    self.message = "Dictation workflow completed."
                } else {
                    self.message = "\(self.workflowRunner.state.title). Raw dictation is available in SayStone."
                }
            } catch {
                self.workflowRunner.cancel(runIdentifier: runIdentifier)
                self.message = "Dictation workflow cancelled. Raw dictation is available in SayStone."
            }
        } onCancel: {
            Task { @MainActor in self.workflowRunner.cancel(runIdentifier: runIdentifier) }
        }
        self.show(tab: "workflows", captureTarget: false)
        return true
    }

    func runWorkflowFromIntent(id: UUID, input: String) async throws -> String {
        try Task.checkCancellation()
        guard let workflow = self.workflows.workflows.first(where: { $0.id == id }) else {
            throw UtilityActionError.invalidInput("This workflow is no longer available.")
        }
        guard !self.workflowRunner.state.isRunning, !self.isExecuting, !self.isDispatching, !self.isIntentExecuting, self.pendingShortcutTask == nil else {
            throw UtilityActionError.invalidInput("Another action or workflow is already running.")
        }
        guard !workflow.steps.contains(where: { [.pastePlainText, .pasteText, .insertSnippet].contains($0.action.id) }) else {
            throw UtilityActionError.invalidInput("Run workflows with paste steps from the palette or a configured shortcut, where a target field can be selected.")
        }
        self.target = nil
        guard self.runWorkflow(workflow, input: input), let runIdentifier = self.workflowRunner.runIdentifier else {
            throw UtilityActionError.invalidInput(self.workflowRunner.state.title)
        }
        self.isIntentExecuting = true
        defer { self.isIntentExecuting = false }
        return try await withTaskCancellationHandler {
            while self.workflowRunner.state.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            guard self.workflowRunner.state == .completed else {
                throw UtilityActionError.invalidInput(self.workflowRunner.state.title)
            }
            return self.workflowRunner.output ?? ""
        } onCancel: {
            Task { @MainActor in self.workflowRunner.cancel(runIdentifier: runIdentifier) }
        }
    }

    func handleShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard !self.isRecordingShortcut,
              let binding = self.shortcuts.matching(keyCode: keyCode, modifiers: modifiers, appBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        else { return false }
        guard !isRepeat else { return true }
        guard self.pendingShortcutTask == nil, !self.isDispatching, !self.isExecuting, !self.isIntentExecuting, !self.workflowRunner.state.isRunning else { return true }
        let capturedTarget = TypingService.captureSystemFocusTarget()
        let capturedApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        self.pendingShortcutTask = Task {
            defer { self.pendingShortcutTask = nil }
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                if NSEvent.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) { break }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard !Task.isCancelled else { return }
            guard NSEvent.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) else {
                self.message = "Release the shortcut keys and try again."
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == capturedApp,
                  capturedTarget.map({ TypingService.isExactFocusTargetActive($0) }) ?? true
            else {
                self.message = UtilityActionError.targetChanged.localizedDescription
                return
            }
            self.target = capturedTarget
            switch binding.target {
            case .copyLatestTranscript: self.perform(.init(id: .copyLatestTranscript))
            case .pastePlainText: self.perform(.init(id: .pastePlainText))
            case .palette: self.show(captureTarget: false)
            case .snippet: self.perform(.init(id: .insertSnippet, snippetID: binding.itemID))
            case .workflow:
                guard let id = binding.itemID, let workflow = self.workflows.workflows.first(where: { $0.id == id }) else { return }
                self.runWorkflow(workflow, input: "")
                self.show(tab: "workflows", captureTarget: false)
            }
        }
        return true
    }
}
