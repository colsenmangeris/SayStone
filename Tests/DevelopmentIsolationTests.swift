import Foundation

/// Standalone checks: no microphone, app host, production preferences or Keychain I/O.
@main struct DevelopmentIsolationTests {
    static func main() throws {
        let fileManager = FileManager.default
        let fixtureHome = fileManager.temporaryDirectory.appendingPathComponent("saystone-isolation-\(UUID())", isDirectory: true)
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureHome) }

        let publicSupport = fixtureHome.appendingPathComponent("Library/Application Support", isDirectory: true)
        let publicHistory = publicSupport.appendingPathComponent("FluidVoice/TranscriptionHistory.sqlite3")
        let publicRecovery = publicSupport.appendingPathComponent("SayStone/Recovery/Latest Failed Dictation.wav")
        let publicModel = publicSupport.appendingPathComponent("FluidAudio/Models/parakeet-v2/model.bin")
        let publicLog = fixtureHome.appendingPathComponent("Library/Logs/Fluid/Fluid.log")
        let publicPreferences = fixtureHome.appendingPathComponent("Library/Preferences/com.FluidApp.app.debug.plist")
        let publicFiles = [publicHistory, publicRecovery, publicModel, publicLog, publicPreferences]
        let sentinel = Data("Authored daily-app fixture: preserve me".utf8)
        for url in publicFiles {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sentinel.write(to: url)
        }

        let support = AppStorage.developmentDirectory(for: .applicationSupportDirectory, homeDirectory: fixtureHome)
        let caches = AppStorage.developmentDirectory(for: .cachesDirectory, homeDirectory: fixtureHome)
        let library = AppStorage.developmentDirectory(for: .libraryDirectory, homeDirectory: fixtureHome)
        let root = AppStorage.developmentRoot(homeDirectory: fixtureHome)
        for directory in [support, caches, library] {
            precondition(directory.path.hasPrefix(root.path + "/"))
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let developmentHistory = support.appendingPathComponent("FluidVoice/TranscriptionHistory.sqlite3")
        try fileManager.createDirectory(at: developmentHistory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Authored development history".utf8).write(to: developmentHistory)
        let recovery = try FailedDictationRecovery.save(samples: [0, 0.25, -0.25], directory: support.appendingPathComponent("SayStone/Recovery"))
        precondition(recovery.path.hasPrefix(root.path + "/"))
        // Model deletion and clearing development history stay inside the development root.
        try fileManager.removeItem(at: caches)
        try fileManager.removeItem(at: developmentHistory)
        for url in publicFiles {
            let actual = try Data(contentsOf: url)
            precondition(actual == sentinel)
        }

        let foreignBundleURL = fixtureHome.appendingPathComponent("Foreign.app", isDirectory: true)
        let contents = foreignBundleURL.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.FluidApp.app.debug", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard let foreignBundle = Bundle(url: foreignBundleURL) else {
            preconditionFailure("The authored foreign-app fixture could not be loaded as a bundle.")
        }

        #if SAYSTONE_DEVELOPMENT
        precondition(AppStorage.isDevelopment)
        precondition(AppStorage.providerKeychainService != "com.fluidvoice.provider-api-keys")
        precondition(AppStorage.modelDirectory(publicModel.deletingLastPathComponent()).path.contains("/SayStone Development/"))
        do {
            try AppStorage.prepareDevelopmentStorage(bundle: foreignBundle)
            fatalError("A development build accepted the daily app's identity")
        } catch let error as CocoaError {
            precondition(error.code == .executableLoad)
        }
        #else
        precondition(!AppStorage.isDevelopment)
        precondition(AppStorage.providerKeychainService == "com.fluidvoice.provider-api-keys")
        precondition(AppStorage.modelDirectory(publicModel) == publicModel)
        precondition(AppStorage.urls(for: .applicationSupportDirectory, in: .userDomainMask) == fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
        try AppStorage.prepareDevelopmentStorage(bundle: foreignBundle)
        #endif
        print("Development isolation checks passed (development=\(AppStorage.isDevelopment)); authored daily fixtures preserved.")
    }
}
