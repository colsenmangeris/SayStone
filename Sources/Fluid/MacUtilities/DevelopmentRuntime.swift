import Foundation

/// Synthetic UI startup is accepted only by the isolated Development product.
nonisolated enum DevelopmentRuntime {
    static var isUITesting: Bool {
        AppStorage.isDevelopment &&
            Bundle.main.bundleIdentifier == AppStorage.developmentBundleIdentifier &&
            ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var testSession: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-test-session"),
              arguments.indices.contains(index + 1),
              let session = UUID(uuidString: arguments[index + 1])
        else { return "default" }
        return session.uuidString
    }

    static var utilityDirectory: URL {
        if isUITesting {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("SayStone-UITests", isDirectory: true)
                .appendingPathComponent(testSession, isDirectory: true)
        }
        return AppStorage.applicationSupportFallback
            .appendingPathComponent("SayStone/MacUtilities", isDirectory: true)
    }

    static var settingsDefaults: UserDefaults {
        guard isUITesting else { return .standard }
        guard let defaults = UserDefaults(suiteName: "\(AppStorage.developmentBundleIdentifier).ui-tests.\(testSession)") else {
            fatalError("Could not create the synthetic UI test preferences domain")
        }
        return defaults
    }
}
