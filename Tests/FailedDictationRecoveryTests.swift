import Foundation
@main struct Test {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FailedDictationRecovery.save(samples: [-2, 0, 2, .nan], directory: folder)
        let bytes = try Data(contentsOf: url)
        precondition(bytes.count == 52)
        precondition(String(decoding: bytes.prefix(4), as: UTF8.self) == "RIFF")
        precondition(Array(bytes.suffix(8)) == [1,128,0,0,255,127,0,0])
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        precondition((attrs[.posixPermissions] as! NSNumber).intValue == 0o600)
        let second = try FailedDictationRecovery.save(samples: [0], directory: folder)
        let replacement = try Data(contentsOf: second)
        precondition(second == url && replacement.count == 46)
        print("PASS: recovery WAV encoding, clipping, private permissions, latest-file replacement")
    }
}
