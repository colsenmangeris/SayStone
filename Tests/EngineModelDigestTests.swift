import Foundation

@main
struct EngineModelDigestTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("saystone-engine-digest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("alpha".utf8).write(to: root.appendingPathComponent("a.bin"))
        try Data("beta".utf8).write(to: root.appendingPathComponent("nested/b.bin"))

        let first = EngineModelDigest.sha256Tree(at: root)
        precondition(first == "b2c13e3423d0f4347e0d27cc78607483da485dd9d695831e50d70f56e4a7e7a7")
        try Data("changed".utf8).write(to: root.appendingPathComponent("nested/b.bin"))
        precondition(EngineModelDigest.sha256Tree(at: root) != first)
        print("EngineModelDigestTests passed")
    }
}
