import Foundation

/// Synthetic UI startup is accepted only by the isolated Development product.
nonisolated enum DevelopmentRuntime {
    static let syntheticUISessionKey = "SayStoneSyntheticUISession"

    nonisolated struct StartupConfiguration: Equatable, Sendable {
        let isUITesting: Bool
        let isBackgroundUITesting: Bool
        let testSession: String

        var preferencesDomain: String? {
            guard isUITesting else { return nil }
            return "\(AppStorage.developmentBundleIdentifier).ui-tests.\(testSession)"
        }

        func utilityDirectory(in temporaryDirectory: URL) -> URL? {
            guard isUITesting else { return nil }
            return temporaryDirectory.appendingPathComponent("SayStone-UITests", isDirectory: true)
                .appendingPathComponent(testSession, isDirectory: true)
        }
    }

    private nonisolated enum StartupError: LocalizedError {
        case invalidEmbeddedSession

        var errorDescription: String? {
            "Embedded synthetic startup requires the isolated Development bundle and a valid UUID string."
        }
    }

    /// Runs before preferences and services are initialized. A malformed marker
    /// on a temporary review bundle must not fall through to ordinary startup.
    static func validateSyntheticStartup(bundle: Bundle = .main) throws {
        guard let value = bundle.object(forInfoDictionaryKey: syntheticUISessionKey) else { return }
        guard AppStorage.isDevelopment,
              bundle.bundleIdentifier == AppStorage.developmentBundleIdentifier,
              let string = value as? String, UUID(uuidString: string) != nil else {
            throw StartupError.invalidEmbeddedSession
        }
    }

    static func startupConfiguration(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> StartupConfiguration {
        let allowed = AppStorage.isDevelopment && bundle.bundleIdentifier == AppStorage.developmentBundleIdentifier
        let embedded = allowed ? (bundle.object(forInfoDictionaryKey: syntheticUISessionKey) as? String).flatMap(UUID.init(uuidString:)) : nil
        let synthetic = allowed && (embedded != nil || arguments.contains("--ui-testing"))
        return StartupConfiguration(
            isUITesting: synthetic,
            isBackgroundUITesting: synthetic && (embedded != nil || arguments.contains("--ui-testing-background")),
            testSession: (embedded ?? argumentSession(arguments))?.uuidString ?? "default"
        )
    }

    private static func argumentSession(_ arguments: [String]) -> UUID? {
        guard let index = arguments.firstIndex(of: "--ui-test-session"),
              arguments.indices.contains(index + 1),
              let session = UUID(uuidString: arguments[index + 1])
        else { return nil }
        return session
    }

    static var isUITesting: Bool { startupConfiguration().isUITesting }
    static var isBackgroundUITesting: Bool { startupConfiguration().isBackgroundUITesting }
    static var testSession: String { startupConfiguration().testSession }

    static var utilityDirectory: URL {
        if let directory = startupConfiguration().utilityDirectory(in: FileManager.default.temporaryDirectory) {
            return directory
        }
        return AppStorage.applicationSupportFallback
            .appendingPathComponent("SayStone/MacUtilities", isDirectory: true)
    }

    static var settingsDefaults: UserDefaults {
        guard let domain = startupConfiguration().preferencesDomain else { return .standard }
        guard let defaults = UserDefaults(suiteName: domain) else {
            fatalError("Could not create the synthetic UI test preferences domain")
        }
        return defaults
    }
}
