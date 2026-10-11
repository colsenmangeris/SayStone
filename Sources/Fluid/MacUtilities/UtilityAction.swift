import Foundation

/// Stable identifiers shared by menus, keyboard shortcuts, App Intents and workflows.
nonisolated enum UtilityActionID: String, Codable, CaseIterable, Identifiable, Sendable {
    case copyLatestTranscript
    case pastePlainText
    case copyText
    case pasteText
    case transformText
    case insertSnippet
    case openURL
    case launchApp
    case runAppleShortcut

    var id: String { rawValue }
}

nonisolated enum UtilityTextTransform: String, Codable, CaseIterable, Identifiable, Sendable {
    case trim
    case uppercase
    case lowercase
    case collapseWhitespace
    case removeLineBreaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trim: return "Trim whitespace"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .collapseWhitespace: return "Collapse whitespace"
        case .removeLineBreaks: return "Remove line breaks"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .trim:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .collapseWhitespace:
            return text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
        case .removeLineBreaks:
            return text.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

/// Parameter values are data, never executable shell fragments.
nonisolated struct UtilityActionRequest: Codable, Equatable, Sendable {
    var id: UtilityActionID
    var text: String?
    var transform: UtilityTextTransform?
    var snippetID: UUID?
    var urlString: String?
    var bundleIdentifier: String?
    var shortcutName: String?

    init(
        id: UtilityActionID,
        text: String? = nil,
        transform: UtilityTextTransform? = nil,
        snippetID: UUID? = nil,
        urlString: String? = nil,
        bundleIdentifier: String? = nil,
        shortcutName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.transform = transform
        self.snippetID = snippetID
        self.urlString = urlString
        self.bundleIdentifier = bundleIdentifier
        self.shortcutName = shortcutName
    }
}

nonisolated struct UtilityActionResult: Equatable, Sendable {
    let output: String?
    let message: String

    init(output: String? = nil, message: String) {
        self.output = output
        self.message = message
    }
}

nonisolated struct UtilityActionDescriptor: Identifiable, Sendable {
    let id: UtilityActionID
    let title: String
    let detail: String
    let systemImage: String
}

nonisolated enum UtilityActionError: Error, LocalizedError, Equatable {
    case invalidInput(String)
    case targetChanged
    case clipboardUnavailable
    case clipboardBusy
    case clipboardTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .targetChanged: return "The intended text field changed. Select the target and try again."
        case .clipboardUnavailable: return "The clipboard could not be updated."
        case .clipboardBusy: return "Another paste is still completing. Try again shortly."
        case .clipboardTooLarge: return "The clipboard is too large to preserve safely for this paste."
        }
    }
}

nonisolated enum UtilityActionRegistry {
    static let maximumTextBytes = 1_048_576

    static let descriptors: [UtilityActionDescriptor] = [
        .init(id: .copyLatestTranscript, title: "Copy latest transcript", detail: "Copy the latest available dictation text", systemImage: "doc.on.doc"),
        .init(id: .pastePlainText, title: "Paste as plain text", detail: "Paste clipboard text without formatting", systemImage: "doc.plaintext"),
        .init(id: .copyText, title: "Copy text", detail: "Copy the supplied text", systemImage: "clipboard"),
        .init(id: .pasteText, title: "Paste text", detail: "Insert text into the intended field", systemImage: "text.insert"),
        .init(id: .transformText, title: "Transform text", detail: "Apply a local text transformation", systemImage: "textformat"),
        .init(id: .insertSnippet, title: "Insert snippet", detail: "Insert a saved text snippet", systemImage: "pin"),
        .init(id: .openURL, title: "Open URL", detail: "Open a web link or draft an email", systemImage: "link"),
        .init(id: .launchApp, title: "Launch app", detail: "Open an installed application", systemImage: "app"),
        .init(id: .runAppleShortcut, title: "Run Apple Shortcut", detail: "Run a named shortcut from Apple's Shortcuts app", systemImage: "square.stack.3d.up")
    ]

    static func descriptor(for id: UtilityActionID) -> UtilityActionDescriptor {
        // The static table and enum are tested together; no dynamic registry fallback is needed.
        guard let descriptor = descriptors.first(where: { $0.id == id }) else {
            preconditionFailure("Every UtilityActionID must have a registered descriptor.")
        }
        return descriptor
    }

    static func validate(_ request: UtilityActionRequest) throws {
        if let text = request.text, text.utf8.count > maximumTextBytes {
            throw UtilityActionError.invalidInput("Text must be no larger than 1 MiB.")
        }

        switch request.id {
        case .copyLatestTranscript, .pastePlainText:
            break
        case .copyText, .pasteText:
            try validateText(request.text)
        case .transformText:
            try validateText(request.text)
            guard request.transform != nil else {
                throw UtilityActionError.invalidInput("Choose a text transformation.")
            }
        case .insertSnippet:
            guard request.snippetID != nil else {
                throw UtilityActionError.invalidInput("Choose a saved snippet.")
            }
        case .openURL:
            guard let value = request.urlString, value.utf8.count <= 8_192,
                  !value.contains(where: { $0.isWhitespace || $0.isNewline }),
                  let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme),
                  scheme == "mailto" && !url.path.isEmpty || url.host?.isEmpty == false else {
                throw UtilityActionError.invalidInput("Enter a valid http, https or mailto URL.")
            }
        case .launchApp:
            guard let value = request.bundleIdentifier, value.utf8.count <= 256,
                  value.contains("."), value.first != ".", value.last != ".",
                  !value.contains(".."), value.unicodeScalars.allSatisfy({
                      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
                  }) else {
                throw UtilityActionError.invalidInput("Enter the application's bundle identifier, such as com.apple.TextEdit.")
            }
        case .runAppleShortcut:
            guard let value = request.shortcutName,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-"),
                  value.utf8.count <= 256,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw UtilityActionError.invalidInput("Choose an Apple Shortcut name of no more than 256 bytes.")
            }
        }
    }

    private static func validateText(_ text: String?) throws {
        guard let text, !text.isEmpty else {
            throw UtilityActionError.invalidInput("This action needs nonempty text.")
        }
    }
}
