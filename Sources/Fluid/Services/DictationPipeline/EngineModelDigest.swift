import CryptoKit
import Foundation

/// Deterministic digest of every regular file in one downloaded model tree.
///
/// Each file is hashed independently, then a sorted manifest of
/// `<sha256><two spaces><relative path><newline>` is hashed again. This binds
/// both file contents and names without loading the 443 MiB model into memory.
nonisolated enum EngineModelDigest {
    static func sha256Tree(at root: URL, fileManager: FileManager = .default) -> String? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var files: [(relative: String, url: URL)] = []
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                values.isRegularFile == true,
                values.isSymbolicLink != true
            else { continue }
            let prefix = root.standardizedFileURL.path + "/"
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { return nil }
            files.append((String(path.dropFirst(prefix.count)), url))
        }
        guard !files.isEmpty else { return nil }
        files.sort { $0.relative < $1.relative }

        var tree = SHA256()
        for file in files {
            guard let digest = self.sha256File(at: file.url) else { return nil }
            guard let line = "\(digest)  \(file.relative)\n".data(using: .utf8) else { return nil }
            tree.update(data: line)
        }
        return tree.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256File(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var digest = SHA256()
        do {
            while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                digest.update(data: data)
            }
        } catch {
            return nil
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
