import AppKit
import Foundation

@MainActor final class SettingsStore {
    static let shared = SettingsStore()
    var primaryDictationShortcuts = [HotkeyShortcut(keyCode: 63, modifierFlags: [])]
    var cancelRecordingHotkeyShortcut = HotkeyShortcut(keyCode: 53, modifierFlags: [])
    var promptModeShortcutEnabled = false
    var promptModeHotkeyShortcut = HotkeyShortcut(keyCode: 2, modifierFlags: [.command, .shift])
    var rewriteModeShortcutEnabled = false
    var rewriteModeHotkeyShortcut = HotkeyShortcut(keyCode: 14, modifierFlags: [.command, .shift])
    var commandModeShortcutEnabled = false
    var commandModeHotkeyShortcut: HotkeyShortcut?
    var pasteLastTranscriptionShortcutEnabled = false
    var pasteLastTranscriptionHotkeyShortcut: HotkeyShortcut?
    struct Assignment { let shortcut: HotkeyShortcut }
    func dictationPromptShortcutAssignments() -> [Assignment] { [] }
}

@main struct UtilityShortcutFixtureTests {
    @MainActor static func main() throws {
        let chord = HotkeyShortcut(keyCode: 40, modifierFlags: [.command, .option])
        precondition(UtilityShortcutRules.validationMessage(chord, reserved: []) == nil)
        precondition(UtilityShortcutRules.validationMessage(HotkeyShortcut(keyCode: 40, modifierFlags: []), reserved: []) != nil)
        precondition(UtilityShortcutRules.validationMessage(chord, reserved: [chord]) != nil)
        let modifierPrefix = HotkeyShortcut(keyCode: 55, modifierFlags: [])
        precondition(UtilityShortcutRules.validationMessage(chord, reserved: [modifierPrefix]) != nil)
        precondition(UtilityShortcutRules.overlaps(chord, modifierPrefix) && UtilityShortcutRules.overlaps(modifierPrefix, chord))
        let capsLockVariant = HotkeyShortcut(keyCode: 40, modifierFlags: [.command, .option, .capsLock])
        precondition(UtilityShortcutRules.overlaps(chord, capsLockVariant))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SayStone-shortcuts-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("shortcuts.json")
        let store = UtilityShortcutStore(url: url)
        precondition(store.bindings.isEmpty)
        let binding = UtilityShortcutBinding(target: .copyLatestTranscript, shortcut: chord, appBundleIdentifier: "com.example.authored")
        precondition(store.save(binding))
        precondition(store.matching(keyCode: 40, modifiers: [.command, .option], appBundleIdentifier: "com.example.other") == nil)
        precondition(store.matching(keyCode: 40, modifiers: [.command, .option], appBundleIdentifier: "com.example.authored")?.id == binding.id)
        let loaded = UtilityShortcutStore(url: url)
        precondition(loaded.bindings.first?.id == binding.id)
        precondition(!loaded.save(.init(target: .pastePlainText, shortcut: chord)))
        SettingsStore.shared.commandModeShortcutEnabled = true
        SettingsStore.shared.commandModeHotkeyShortcut = chord
        precondition(loaded.matching(keyCode: 40, modifiers: [.command, .option], appBundleIdentifier: "com.example.authored") == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)
        let invalidURL = directory.appendingPathComponent("invalid.json")
        let invalid = Data("authored malformed fixture".utf8)
        try invalid.write(to: invalidURL)
        let invalidStore = UtilityShortcutStore(url: invalidURL)
        precondition(!invalidStore.save(binding))
        let preserved = try Data(contentsOf: invalidURL)
        precondition(preserved == invalid)
        print("Utility shortcut fixtures passed: conflicts, app scope, persistence, runtime changes and corrupt-file preservation.")
    }
}
