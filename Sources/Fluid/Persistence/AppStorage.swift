import Foundation

/// Development is a build configuration, never an environment-variable override.
/// Public Debug/Release builds retain their existing paths and Keychain names.
nonisolated enum AppStorage {
    static let developmentBundleIdentifier = "com.architech.saystone.development"

    #if SAYSTONE_DEVELOPMENT
    static let isDevelopment = true
    #else
    static let isDevelopment = false
    #endif

    static var providerKeychainService: String {
        isDevelopment ? "\(developmentBundleIdentifier).provider-api-keys" : "com.fluidvoice.provider-api-keys"
    }

    static let providerKeychainAccount = "fluidApiKeys"

    static func developmentRoot(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/SayStone Development", isDirectory: true)
    }

    static func developmentDirectory(
        for directory: FileManager.SearchPathDirectory,
        homeDirectory: URL
    ) -> URL {
        let root = developmentRoot(homeDirectory: homeDirectory)
        switch directory {
        case .applicationSupportDirectory: return root.appendingPathComponent("Application Support", isDirectory: true)
        case .cachesDirectory: return root.appendingPathComponent("Caches", isDirectory: true)
        case .libraryDirectory: return root.appendingPathComponent("Library", isDirectory: true)
        default: preconditionFailure("Unsupported development storage directory")
        }
    }

    static func urls(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard isDevelopment else { return fileManager.urls(for: directory, in: domain) }
        precondition(domain == .userDomainMask)
        return [developmentDirectory(for: directory, homeDirectory: fileManager.homeDirectoryForCurrentUser)]
    }

    static func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create: Bool
    ) throws -> URL {
        guard isDevelopment else {
            return try FileManager.default.url(for: directory, in: domain, appropriateFor: url, create: create)
        }
        let directoryURL = urls(for: directory, in: domain)[0]
        if create {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return directoryURL
    }

    static var applicationSupportFallback: URL {
        if isDevelopment {
            return developmentDirectory(for: .applicationSupportDirectory, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// FluidAudio accepts explicit model directories. Keep its repository folder
    /// name while redirecting downloads, compilation, checks and deletion together.
    static func modelDirectory(_ publicDirectory: URL) -> URL {
        guard isDevelopment else { return publicDirectory }
        return applicationSupportFallback
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
            .appendingPathComponent(publicDirectory.lastPathComponent, isDirectory: true)
    }

    /// Runs before app services or settings are initialized. A mismatched bundle
    /// must stop before UserDefaults.standard can access the daily app's domain.
    static func prepareDevelopmentStorage(bundle: Bundle = .main) throws {
        guard isDevelopment else { return }
        guard bundle.bundleIdentifier == developmentBundleIdentifier else {
            throw CocoaError(.executableLoad, userInfo: [
                NSLocalizedDescriptionKey: "Development builds require the isolated SayStone Development bundle identity.",
            ])
        }
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory, .libraryDirectory] {
            _ = try url(for: directory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
    }
}
