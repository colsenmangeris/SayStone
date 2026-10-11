import AppKit
import Foundation

nonisolated enum UtilityShortcutRules {
    static func overlaps(_ lhs: HotkeyShortcut, _ rhs: HotkeyShortcut) -> Bool {
        if lhs == rhs || lhs.conflictsWith(rhs) || rhs.conflictsWith(lhs) { return true }
        if lhs.isModifierOnlyShortcut, let flags = lhs.expectedModifierFlags {
            return flags.isSubset(of: rhs.relevantModifierFlags)
        }
        if rhs.isModifierOnlyShortcut, let flags = rhs.expectedModifierFlags {
            return flags.isSubset(of: lhs.relevantModifierFlags)
        }
        return lhs.kind == rhs.kind && lhs.keyCode == rhs.keyCode &&
            lhs.mouseButton == rhs.mouseButton && lhs.relevantModifierFlags == rhs.relevantModifierFlags
    }

    static func validationMessage(_ shortcut: HotkeyShortcut, reserved: [HotkeyShortcut]) -> String? {
        guard !shortcut.isMouseShortcut, !shortcut.isModifierOnlyShortcut,
              !shortcut.relevantModifierFlags.isDisjoint(with: [.command, .control, .option])
        else { return "Choose a key with Command, Control or Option." }
        guard !reserved.contains(where: { overlaps(shortcut, $0) }) else {
            return "This shortcut conflicts with another SayStone shortcut."
        }
        return nil
    }
}
