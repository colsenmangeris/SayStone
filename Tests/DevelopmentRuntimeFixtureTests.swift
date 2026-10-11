import Foundation

/// Compiles actual startup selection against authored bundle metadata only.
/// No application host, normal preferences, Keychain, microphone or clipboard I/O.
@main struct DevelopmentRuntimeFixtureTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saystone-runtime-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let development = try makeBundle(in: root, identifier: AppStorage.developmentBundleIdentifier)
        let publicApp = try makeBundle(in: root, identifier: "com.FluidApp.app.debug")
        let missingIdentity = try makeBundle(in: root, identifier: nil)
        let cliSession = UUID()
        let embeddedSession = UUID()
        let otherSession = UUID()
        let embedded = try makeBundle(in: root, identifier: AppStorage.developmentBundleIdentifier, marker: embeddedSession.uuidString.lowercased())
        let secondEmbedded = try makeBundle(in: root, identifier: AppStorage.developmentBundleIdentifier, marker: otherSession.uuidString)
        let foreignEmbedded = try makeBundle(in: root, identifier: "com.FluidApp.app.debug", marker: embeddedSession.uuidString)
        let noIdentityEmbedded = try makeBundle(in: root, identifier: nil, marker: embeddedSession.uuidString)
        let normalArguments = ["authored-fixture"]
        let foregroundArguments = normalArguments + ["--ui-testing", "--ui-test-session", cliSession.uuidString.lowercased()]
        let backgroundArguments = foregroundArguments + ["--ui-testing-background"]

        for bundle in [development, publicApp, missingIdentity] {
            try DevelopmentRuntime.validateSyntheticStartup(bundle: bundle)
            assertConfiguration(bundle, arguments: normalArguments, testing: false, background: false, session: "default", root: root)
            assertConfiguration(bundle, arguments: normalArguments + ["--ui-testing-background"], testing: false, background: false, session: "default", root: root)
        }

        let allowed = AppStorage.isDevelopment
        assertConfiguration(development, arguments: foregroundArguments, testing: allowed, background: false, session: cliSession.uuidString, root: root)
        assertConfiguration(development, arguments: backgroundArguments, testing: allowed, background: allowed, session: cliSession.uuidString, root: root)
        for bundle in [publicApp, missingIdentity] {
            assertConfiguration(bundle, arguments: backgroundArguments, testing: false, background: false, session: cliSession.uuidString, root: root)
        }
        for arguments in [["--ui-testing"], ["--ui-testing", "--ui-test-session"], ["--ui-testing", "--ui-test-session", "../../invalid"]] {
            assertConfiguration(development, arguments: arguments, testing: allowed, background: false, session: "default", root: root)
        }

        assertConfiguration(embedded, arguments: normalArguments, testing: allowed, background: allowed, session: allowed ? embeddedSession.uuidString : "default", root: root)
        assertConfiguration(embedded, arguments: foregroundArguments, testing: allowed, background: allowed, session: allowed ? embeddedSession.uuidString : cliSession.uuidString, root: root)
        for bundle in [foreignEmbedded, noIdentityEmbedded] {
            expectInvalidMarker(bundle)
            assertConfiguration(bundle, arguments: normalArguments, testing: false, background: false, session: "default", root: root)
        }

        for marker: Any in ["", "malformed UUID", "../../outside", NSNumber(value: 42)] {
            let malformed = try makeBundle(in: root, identifier: AppStorage.developmentBundleIdentifier, marker: marker)
            expectInvalidMarker(malformed)
        }

        if allowed {
            try DevelopmentRuntime.validateSyntheticStartup(bundle: embedded)
            try DevelopmentRuntime.validateSyntheticStartup(bundle: secondEmbedded)
            let first = DevelopmentRuntime.startupConfiguration(bundle: embedded, arguments: normalArguments)
            let second = DevelopmentRuntime.startupConfiguration(bundle: secondEmbedded, arguments: normalArguments)
            precondition(first.preferencesDomain != second.preferencesDomain, "Embedded sessions shared a preference namespace")
            guard let firstDirectory = first.utilityDirectory(in: root), let secondDirectory = second.utilityDirectory(in: root) else {
                preconditionFailure("Validated synthetic sessions lost their data namespace")
            }
            precondition(firstDirectory != secondDirectory, "Embedded sessions shared a data namespace")
            try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
            let authored = Data("Authored first-session state".utf8)
            let sentinel = firstDirectory.appendingPathComponent("sentinel.txt")
            try authored.write(to: sentinel)
            try Data("Authored second-session state".utf8).write(to: secondDirectory.appendingPathComponent("sentinel.txt"))
            let preserved = try Data(contentsOf: sentinel)
            precondition(preserved == authored, "Second session changed first-session state")
        } else {
            expectInvalidMarker(embedded)
            expectInvalidMarker(secondEmbedded)
        }
        print("Development runtime fixture passed (development=\(allowed)); embedded UUID, identity, foreground/background and namespace guards verified.")
    }

    private static func makeBundle(in root: URL, identifier: String?, marker: Any? = nil) throws -> Bundle {
        let app = root.appendingPathComponent("Authored-\(UUID()).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var metadata: [String: Any] = ["CFBundlePackageType": "APPL"]
        metadata["CFBundleIdentifier"] = identifier
        metadata[DevelopmentRuntime.syntheticUISessionKey] = marker
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard let bundle = Bundle(url: app) else { preconditionFailure("Authored bundle metadata could not be loaded") }
        return bundle
    }

    private static func expectInvalidMarker(_ bundle: Bundle) {
        do {
            try DevelopmentRuntime.validateSyntheticStartup(bundle: bundle)
            preconditionFailure("Invalid embedded marker was accepted")
        } catch {
            precondition(!error.localizedDescription.isEmpty, "Invalid startup needs a readable error")
        }
    }

    private static func assertConfiguration(
        _ bundle: Bundle,
        arguments: [String],
        testing: Bool,
        background: Bool,
        session: String,
        root: URL
    ) {
        let configuration = DevelopmentRuntime.startupConfiguration(bundle: bundle, arguments: arguments)
        precondition(configuration.isUITesting == testing, "Unexpected synthetic mode")
        precondition(configuration.isBackgroundUITesting == background, "Unexpected background mode")
        precondition(configuration.testSession == session, "Unexpected UUID precedence or canonicalization")
        if testing {
            precondition(configuration.preferencesDomain == "\(AppStorage.developmentBundleIdentifier).ui-tests.\(session)")
            precondition(configuration.utilityDirectory(in: root) == root.appendingPathComponent("SayStone-UITests/\(session)", isDirectory: true))
        } else {
            precondition(configuration.preferencesDomain == nil, "Normal startup selected synthetic preferences")
            precondition(configuration.utilityDirectory(in: root) == nil, "Normal startup selected synthetic data")
        }
    }
}
