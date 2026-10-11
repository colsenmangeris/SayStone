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
        try verifyStorageFailure(root: root)
        try verifyExclusionAndUnicodeBounds(root: root)
        try verifyDisabledHistoryExpiry(root: root)
        try verifyDisabledHistoryExpiryTimer(root: root)
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
        print("Clipboard library checks passed: opt-in, markers, app exclusions, Unicode bounds, retention, snippets, storage failure/recovery, persistence and isolation.")
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
        pasteboard.setString(" COM.EXAMPLE.EXCLUDED \n", forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
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

    @MainActor private static func verifyStorageFailure(root: URL) throws {
        let blockedNewParent = root.appendingPathComponent("BlockedNewParent")
        try Data("Authored path blocker".utf8).write(to: blockedNewParent)
        var newCountReads = 0
        let unsaved = ClipboardLibrary(
            storageURL: blockedNewParent.appendingPathComponent("Library.json"),
            changeCountProvider: { newCountReads += 1; return 10 },
            snapshotProvider: { _ in preconditionFailure("Failed opt-in must not request clipboard text") }
        )
        precondition(unsaved.saveSnippet(title: "Authored unsaved draft", text: "Authored body") == nil)
        precondition(unsaved.snippets.isEmpty && unsaved.lastError != nil)
        unsaved.setHistoryEnabled(true)
        unsaved.resumeMonitoringIfEnabled()
        unsaved.poll()
        precondition(!unsaved.options.isEnabled && !unsaved.isMonitoring && newCountReads == 0)

        let parent = root.appendingPathComponent("SaveFailure")
        let backup = root.appendingPathComponent("SaveFailureBackup")
        let url = parent.appendingPathComponent("Library.json")
        var changeCount = 10
        var snapshotReads = 0
        let library = ClipboardLibrary(
            storageURL: url,
            changeCountProvider: { changeCount },
            snapshotProvider: { _ in
                snapshotReads += 1
                return ClipboardSnapshot(changeCount: changeCount, text: "Authored storage-failure history", sourceBundleIdentifier: "com.example.Source")
            }
        )
        let originalText = "Authored persisted draft: \"quoted\" -- dash  "
        guard let id = library.saveSnippet(title: "Authored saved title", text: originalText) else {
            preconditionFailure("Authored storage-failure setup could not save")
        }
        library.setHistoryEnabled(true)
        let originalDocument = try Data(contentsOf: url)
        try FileManager.default.moveItem(at: parent, to: backup)
        try Data("Authored path blocker".utf8).write(to: parent)
        changeCount += 1
        library.poll()
        precondition(library.isHistoryCollectionPaused && !library.isMonitoring && snapshotReads == 1)
        changeCount += 1
        library.poll()
        library.resumeMonitoringIfEnabled()
        precondition(snapshotReads == 1 && !library.isMonitoring, "Storage failure must stop further collection")
        precondition(library.saveSnippet(id: id, title: "Authored failed edit", text: "Authored unsaved edit") == nil)
        precondition(library.lookupSnippet(id: id)?.text == originalText)
        library.setPinned(false, id: id)
        precondition(library.lookupSnippet(id: id)?.isPinned == true)
        library.removeSnippet(id: id)
        precondition(library.lookupSnippet(id: id) != nil, "Failed deletion must not claim the saved snippet was removed")
        var options = library.options
        options.excludedBundleIdentifiers.insert("com.example.source")
        precondition(!library.updateOptions(options))
        precondition(library.history.isEmpty && library.options.excludedBundleIdentifiers.contains("com.example.source"))
        library.setHistoryEnabled(false)
        library.clearHistory()
        precondition(!library.options.isEnabled && !library.isMonitoring)
        precondition(library.lastError?.contains("after restarting") == true)
        let preservedDocument = try Data(contentsOf: backup.appendingPathComponent("Library.json"))
        precondition(preservedDocument == originalDocument)

        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: backup, to: parent)
        let recoveredText = "Authored recovered draft: \"literal\" -- dash  "
        precondition(library.saveSnippet(id: id, title: "Authored recovered title", text: recoveredText) == id)
        precondition(!library.isHistoryCollectionPaused && library.lastError == nil)
        let reloaded = ClipboardLibrary(storageURL: url, allowsPolling: false)
        precondition(reloaded.lookupSnippet(id: id)?.text == recoveredText)
        precondition(!reloaded.options.isEnabled && reloaded.history.isEmpty)
        precondition(reloaded.options.excludedBundleIdentifiers.contains("com.example.source"))
    }

    @MainActor private static func verifyExclusionAndUnicodeBounds(root: URL) throws {
        let url = root.appendingPathComponent("Bounds/Library.json")
        let library = ClipboardLibrary(storageURL: url, allowsPolling: false)
        let oversizedTitle = "a" + String(repeating: "\u{0301}", count: 240)
        let oversizedSnippet = "a" + String(repeating: "\u{0301}", count: ClipboardLibrary.maximumSnippetBytes / 2)
        precondition(oversizedTitle.count == 1 && oversizedSnippet.count == 1)
        precondition(library.saveSnippet(title: oversizedTitle, text: "Authored ordinary body") == nil)
        precondition(library.saveSnippet(title: "Authored Unicode bound", text: oversizedSnippet) == nil)
        library.setHistoryEnabled(true)
        let oversizedHistory = "a" + String(repeating: "\u{0301}", count: ClipboardLibrary.maximumHistoryBytes / 2)
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 1, text: oversizedHistory))
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 2, text: "Authored source fixture", sourceBundleIdentifier: " COM.APPLE.PASSWORDS \n"))
        precondition(library.history.isEmpty, "Byte bounds and normalized password app exclusions must reject capture")

        var options = library.options
        for index in 0..<(ClipboardLibrary.maximumExcludedAppCount - options.excludedBundleIdentifiers.count) {
            options.excludedBundleIdentifiers.insert("com.example.Excluded\(index)")
        }
        options.excludedBundleIdentifiers.insert(" COM.APPLE.PASSWORDS \n")
        options.excludedBundleIdentifiers.insert("Authored invalid identifier")
        precondition(library.updateOptions(options))
        let exclusions = library.options.excludedBundleIdentifiers
        precondition(exclusions.count == ClipboardLibrary.maximumExcludedAppCount)
        precondition(exclusions.contains("com.apple.passwords"))
        let documentBeforeOverflow = try Data(contentsOf: url)
        options = library.options
        options.excludedBundleIdentifiers.insert("com.example.Additional")
        precondition(!library.updateOptions(options))
        precondition(library.options.excludedBundleIdentifiers == exclusions, "Overflow must preserve every existing exclusion")
        let documentAfterOverflow = try Data(contentsOf: url)
        precondition(documentBeforeOverflow == documentAfterOverflow)
    }

    @MainActor private static func verifyDisabledHistoryExpiry(root: URL) throws {
        let parent = root.appendingPathComponent("DisabledExpiry")
        let backup = root.appendingPathComponent("DisabledExpiryBackup")
        let url = parent.appendingPathComponent("Library.json")
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var clipboardReads = 0
        let library = ClipboardLibrary(
            storageURL: url,
            allowsPolling: false,
            now: { clock },
            changeCountProvider: { clipboardReads += 1; return 0 },
            snapshotProvider: { _ in preconditionFailure("Disabled retention must not request clipboard text") }
        )
        var options = library.options
        options.isEnabled = true
        options.retentionDays = 1
        library.updateOptions(options)
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 1, text: "Authored disabled retention fixture"))
        library.setHistoryEnabled(false)
        clock = clock.addingTimeInterval(86_401)
        library.expireHistory()
        precondition(library.history.isEmpty && !library.options.isEnabled && clipboardReads == 0)
        let expiredDocument = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        precondition((expiredDocument?["history"] as? [[String: Any]])?.isEmpty == true)

        library.setHistoryEnabled(true)
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 2, text: "Authored failing expiry fixture"))
        library.setHistoryEnabled(false)
        try FileManager.default.moveItem(at: parent, to: backup)
        try Data("Authored path blocker".utf8).write(to: parent)
        clock = clock.addingTimeInterval(86_401)
        library.expireHistory()
        precondition(library.history.isEmpty && library.isHistoryCollectionPaused && !library.isMonitoring)
        precondition(library.lastError?.contains("after restarting") == true)
        let expiryError = library.lastError
        library.expireHistory()
        precondition(library.lastError == expiryError && clipboardReads == 0, "Empty retained history must not retry a failed expiry write")
        let preservedDocument = try JSONSerialization.jsonObject(with: Data(contentsOf: backup.appendingPathComponent("Library.json"))) as? [String: Any]
        precondition((preservedDocument?["history"] as? [[String: Any]])?.count == 1, "Failure must be reported rather than claiming durable deletion")
    }

    @MainActor private static func verifyDisabledHistoryExpiryTimer(root: URL) throws {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var countReads = 0
        let library = ClipboardLibrary(
            storageURL: root.appendingPathComponent("ExpiryTimer/Library.json"),
            now: { clock },
            changeCountProvider: { countReads += 1; return 0 },
            snapshotProvider: { _ in preconditionFailure("Expiry timer must not request clipboard text") }
        )
        var options = library.options
        options.isEnabled = true
        options.retentionDays = 1
        library.updateOptions(options)
        library.captureIfChanged(snapshot: ClipboardSnapshot(changeCount: 1, text: "Authored automatic expiry fixture"))
        library.setHistoryEnabled(false)
        clock = clock.addingTimeInterval(86_399.95)
        library.expireHistory()
        precondition(library.history.count == 1)
        clock = clock.addingTimeInterval(0.10)
        let deadline = Date().addingTimeInterval(2)
        while !library.history.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(library.history.isEmpty && !library.options.isEnabled && countReads == 1,
                     "The one-shot retention timer must expire disabled history without polling the clipboard")
    }
}
