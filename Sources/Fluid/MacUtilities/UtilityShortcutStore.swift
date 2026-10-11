import AppKit
import Combine
import Foundation

enum UtilityShortcutTarget: String, Codable, CaseIterable {
    case copyLatestTranscript, pastePlainText, palette, workflow, snippet

    var title: String {
        switch self {
        case .copyLatestTranscript: return "Copy latest transcript"
        case .pastePlainText: return "Paste plain text"
        case .palette: return "Open command palette"
        case .workflow: return "Run workflow"
        case .snippet: return "Insert snippet"
        }
    }
}

struct UtilityShortcutBinding: Identifiable, Codable {
    var id = UUID()
    var target: UtilityShortcutTarget
    var shortcut: HotkeyShortcut
    var itemID: UUID?
    var appBundleIdentifier: String = ""
    var isEnabled: Bool = true
}

@MainActor
final class UtilityShortcutStore: ObservableObject {
    @Published private(set) var bindings: [UtilityShortcutBinding] = []
    @Published private(set) var lastError: String?
    private let url: URL
    private var isReadOnly = false

    private struct Document: Codable {
        var version = 1
        var bindings: [UtilityShortcutBinding]
    }

    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, document.bindings.count <= 100,
                  Set(document.bindings.map(\.id)).count == document.bindings.count
            else { throw CocoaError(.fileReadCorruptFile) }
            self.bindings = document.bindings
        } catch {
            self.isReadOnly = true
            self.lastError = "Shortcut settings could not be read. The original file was preserved."
        }
    }

    static func reservedShortcuts() -> [HotkeyShortcut] {
        let settings = SettingsStore.shared
        var shortcuts = settings.primaryDictationShortcuts + [settings.cancelRecordingHotkeyShortcut]
        if settings.promptModeShortcutEnabled { shortcuts.append(settings.promptModeHotkeyShortcut) }
        if settings.rewriteModeShortcutEnabled { shortcuts.append(settings.rewriteModeHotkeyShortcut) }
        if settings.commandModeShortcutEnabled, let shortcut = settings.commandModeHotkeyShortcut { shortcuts.append(shortcut) }
        if settings.pasteLastTranscriptionShortcutEnabled, let shortcut = settings.pasteLastTranscriptionHotkeyShortcut { shortcuts.append(shortcut) }
        shortcuts += settings.dictationPromptShortcutAssignments().map(\.shortcut)
        return shortcuts
    }

    @discardableResult
    func save(_ binding: UtilityShortcutBinding) -> Bool {
        guard !self.isReadOnly else { return false }
        let others = self.bindings.filter { $0.id != binding.id && $0.isEnabled }.map(\.shortcut)
        if let message = UtilityShortcutRules.validationMessage(binding.shortcut, reserved: Self.reservedShortcuts() + others) {
            self.lastError = message
            return false
        }
        guard self.bindings.count < 100 || self.bindings.contains(where: { $0.id == binding.id }),
              binding.appBundleIdentifier.utf8.count <= 256,
              (binding.target != .workflow && binding.target != .snippet) || binding.itemID != nil
        else {
            self.lastError = "Choose the workflow or snippet, and keep the app identifier under 256 bytes."
            return false
        }
        var updated = self.bindings
        updated.removeAll { $0.id == binding.id }
        updated.append(binding)
        return self.persist(updated)
    }

    func remove(id: UUID) {
        _ = self.persist(self.bindings.filter { $0.id != id })
    }

    func matching(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, appBundleIdentifier: String?) -> UtilityShortcutBinding? {
        let reserved = Self.reservedShortcuts()
        return self.bindings.first {
            $0.isEnabled && $0.shortcut.matches(keyCode: keyCode, modifiers: modifiers) &&
                ($0.appBundleIdentifier.isEmpty || $0.appBundleIdentifier == appBundleIdentifier) &&
                UtilityShortcutRules.validationMessage($0.shortcut, reserved: reserved) == nil
        }
    }

    private func persist(_ bindings: [UtilityShortcutBinding]) -> Bool {
        guard !self.isReadOnly else { return false }
        do {
            try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(Document(bindings: bindings))
            try data.write(to: self.url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.url.path)
            self.bindings = bindings
            self.lastError = nil
            return true
        } catch {
            self.lastError = "Shortcut settings could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
