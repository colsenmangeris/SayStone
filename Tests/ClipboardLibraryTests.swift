import AppKit
import Foundation

/// Authored text, isolated pasteboards, and a temporary fixture home only.
@main struct ClipboardLibraryTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saystone-clipboard-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var changeCount = 10
        var snapshotReads = 0
        var snapshot = ClipboardSnapshot(changeCount: 10, text: "Authored text before opt-in")
        let url = root.appendingPathComponent("Development/MacUtilities/ClipboardLibrary.json")
        let library = ClipboardLibrary(
            storageURL: url,
            now: { clock },
            changeCountProvider: { changeCount },
            snapshotProvider: { _ in snapshotReads += 1; return snapshot }
        )
        precondition(!library.options.isEnabled && !library.isMonitoring)
        library.poll()
        library.captureIfChanged(snapshot: snapshot)
        precondition(snapshotReads == 0 && library.history.isEmpty)
        library.setHistoryEnabled(true)
        precondition(library.isMonitoring && snapshotReads == 0)
        library.poll()
        precondition(snapshotReads == 0 && library.history.isEmpty, "Enabling must skip existing clipboard contents")
        changeCount = 11
        snapshot = ClipboardSnapshot(changeCount: 11, text: "Authored text after opt-in", observedBundleIdentifier: "com.example.Editor")
        library.poll()
        precondition(library.history.map(\.text) == [snapshot.text] && snapshotReads == 1)
        library.poll()
        precondition(snapshotReads == 1, "Unchanged clipboard must not be read again")
        changeCount = 12
        snapshot = ClipboardSnapshot(changeCount: 99, text: "Authored concurrent replacement")
        library.poll()
        precondition(library.history.count == 1, "Changed-during-read snapshot must be rejected")
        for (index, marker) in ClipboardLibrary.excludedPasteboardTypes.enumerated() {
            library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: index, text: "Authored sensitive fixture", types: [marker]))
        }
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 20, text: "Authored password app fixture", sourceBundleIdentifier: "com.1password.1password"))
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 21, text: "Authored observed password fixture", observedBundleIdentifier: "COM.APPLE.PASSWORDS"))
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 22, text: String(repeating: "x", count: ClipboardLibrary.maximumHistoryCharacters + 1)))
        precondition(library.history.count == 1)

        guard let snippetID = library.saveSnippet(title: "Build note", text: "Authored snippet with case 123") else {
            fatalError("Valid authored snippet failed to save")
        }
        precondition(library.lookupSnippet(id: snippetID)?.isPinned == true)
        precondition(library.matchingSnippets("CASE 123").count == 1)
        precondition(library.saveSnippet(id: snippetID, title: "Edited build note", text: "Authored edited snippet", isPinned: false) == snippetID)
        precondition(library.snippets.count == 1 && library.lookupSnippet(id: snippetID)?.text == "Authored edited snippet")
        library.setPinned(true, id: snippetID)
        precondition(library.lookupSnippet(id: snippetID)?.isPinned == true)
        precondition(library.saveSnippet(title: "", text: "Authored invalid title") == nil)
        precondition(library.saveSnippet(title: "Oversized", text: String(repeating: "x", count: ClipboardLibrary.maximumSnippetCharacters + 1)) == nil)

        var options = library.options
        options.maximumItems = 2
        options.retentionDays = 1
        library.updateOptions(options)
        for index in 1...3 {
            clock = clock.addingTimeInterval(1)
            library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 30 + index, text: "Authored retention item \(index)", sourceBundleIdentifier: "com.example.Source"))
        }
        precondition(library.history.map(\.text) == ["Authored retention item 3", "Authored retention item 2"])
        precondition(library.matchingHistory("ITEM 2").count == 1)
        clock = clock.addingTimeInterval(86_399.5)
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 39, text: "Authored retention item 3"))
        let storedDocument = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        precondition((storedDocument?["history"] as? [[String: Any]])?.count == 1, "A duplicate copy must still persist expiry deletion")
        options = library.options
        options.excludedBundleIdentifiers.insert("COM.EXAMPLE.SOURCE")
        library.updateOptions(options)
        precondition(library.history.isEmpty, "Adding exclusion must remove previously stored matches")
        clock = clock.addingTimeInterval(1)
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 40, text: "Authored expiring text"))
        precondition(library.history.count == 1)
        clock = clock.addingTimeInterval(86_401)
        library.poll()
        precondition(library.history.isEmpty, "Retention must expire entries without a new copy")
        library.setHistoryEnabled(false)
        precondition(!library.isMonitoring)
        let readsBeforeDisable = snapshotReads
        library.poll()
        precondition(snapshotReads == readsBeforeDisable)

        let reloaded = ClipboardLibrary(storageURL: url, allowsPolling: false, now: { clock })
        precondition(!reloaded.isMonitoring)
        precondition(reloaded.lookupSnippet(id: snippetID)?.text == "Authored edited snippet")
        precondition(reloaded.options.excludedBundleIdentifiers.contains("com.example.source"))
        reloaded.setHistoryEnabled(true)
        precondition(!reloaded.isMonitoring, "UI fixture mode must not start polling")
        reloaded.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 50, text: "Authored clear-history fixture"))
        reloaded.clearHistory()
        precondition(reloaded.history.isEmpty && reloaded.snippets.count == 1)
        reloaded.removeSnippet(id: snippetID)
        precondition(reloaded.snippets.isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        precondition(permissions.map { $0.intValue & 0o777 == 0o600 } == true)
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        precondition(directoryPermissions.map { $0.intValue & 0o777 == 0o700 } == true)

        try verifyPrivatePasteboardMarkers()
        try verifySchemaPreservation(root: root)
        let fixtureHome = root.appendingPathComponent("AuthoredHome")
        let publicSentinel = fixtureHome.appendingPathComponent("Library/Application Support/FluidVoice/MacUtilities/ClipboardLibrary.json")
        let developmentURL = AppStorage.developmentDirectory(for: .applicationSupportDirectory, homeDirectory: fixtureHome)
            .appendingPathComponent("FluidVoice/MacUtilities/ClipboardLibrary.json")
        try FileManager.default.createDirectory(at: publicSentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("Authored daily sentinel".utf8)
        try sentinel.write(to: publicSentinel)
        let development = ClipboardLibrary(storageURL: developmentURL, allowsPolling: false)
        precondition(development.saveSnippet(title: "Dev only", text: "Authored development snippet") != nil)
        let sentinelAfterDevelopmentWrite = try Data(contentsOf: publicSentinel)
        precondition(sentinelAfterDevelopmentWrite == sentinel)
        #if SAYSTONE_DEVELOPMENT
        precondition(ClipboardLibrary.defaultStorageURL.path.contains("/SayStone Development/"))
        #endif
        print("Clipboard library checks passed: opt-in, markers, app exclusions, bounds, retention, snippets, persistence and isolation.")
    }

    @MainActor private static func verifyPrivatePasteboardMarkers() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("saystone-authored-fixture-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Authored ordinary fixture", forType: .string)
        precondition(ClipboardLibrary.readSnapshot(from: pasteboard, observedBundleIdentifier: "com.example.Editor", excluding: [])?.text == "Authored ordinary fixture")
        for marker in ClipboardLibrary.excludedPasteboardTypes {
            pasteboard.clearContents()
            pasteboard.setString("Authored confidential fixture", forType: .string)
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
            precondition(ClipboardLibrary.readSnapshot(from: pasteboard, observedBundleIdentifier: nil, excluding: []) == nil)
        }
        pasteboard.clearContents()
        pasteboard.setString("Authored source exclusion fixture", forType: .string)
        pasteboard.setString("com.example.Excluded", forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        precondition(ClipboardLibrary.readSnapshot(from: pasteboard, observedBundleIdentifier: nil, excluding: ["com.example.excluded"]) == nil)
        precondition(ClipboardLibrary.readSnapshot(from: pasteboard, observedBundleIdentifier: "com.example.Excluded", excluding: ["com.example.excluded"]) == nil)
        let ordinary = NSPasteboardItem()
        ordinary.setString("Authored first item", forType: .string)
        let concealed = NSPasteboardItem()
        concealed.setString("Authored second concealed item", forType: .string)
        concealed.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        pasteboard.writeObjects([ordinary, concealed])
        precondition(ClipboardLibrary.readSnapshot(from: pasteboard, observedBundleIdentifier: nil, excluding: []) == nil)
    }

    @MainActor private static func verifySchemaPreservation(root: URL) throws {
        let url = root.appendingPathComponent("InvalidLibrary.json")
        let malformed = Data("Authored invalid JSON fixture".utf8)
        try malformed.write(to: url)
        let malformedLibrary = ClipboardLibrary(storageURL: url, allowsPolling: false)
        precondition(malformedLibrary.lastError != nil && malformedLibrary.snippets.isEmpty)
        let malformedAfterLoad = try Data(contentsOf: url)
        precondition(malformedAfterLoad == malformed)
        let future = Data("{\"schemaVersion\":99,\"snippets\":[],\"history\":[],\"options\":{\"isEnabled\":false,\"retentionDays\":7,\"maximumItems\":100,\"excludedBundleIdentifiers\":[]}}".utf8)
        try future.write(to: url)
        let futureLibrary = ClipboardLibrary(storageURL: url, allowsPolling: false)
        precondition(futureLibrary.lastError != nil)
        futureLibrary.setHistoryEnabled(true)
        precondition(!futureLibrary.options.isEnabled)
        precondition(futureLibrary.saveSnippet(title: "Authored attempted overwrite", text: "Authored text") == nil)
        let futureAfterLoad = try Data(contentsOf: url)
        precondition(futureAfterLoad == future)
    }
}
