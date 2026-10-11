import Darwin
import Foundation

@main
struct UtilityCoreProcessFixture {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "arguments":
            let data = try JSONEncoder().encode(Array(arguments.dropFirst()))
            FileHandle.standardOutput.write(data)
        case "flood":
            let block = Data(repeating: 65, count: 8_192)
            let errorBlock = Data(repeating: 66, count: 8_192)
            for _ in 0..<128 {
                FileHandle.standardOutput.write(block)
                FileHandle.standardError.write(errorBlock)
            }
        case "exit":
            FileHandle.standardOutput.write(Data("authored stdout".utf8))
            FileHandle.standardError.write(Data("authored stderr".utf8))
            exit(7)
        case "tree":
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["sleep"]
            try child.run()
            guard arguments.count == 2 else { exit(2) }
            try String(child.processIdentifier).write(toFile: arguments[1], atomically: true, encoding: .utf8)
            fallthrough
        case "sleep":
            signal(SIGTERM, SIG_IGN)
            while true { Thread.sleep(forTimeInterval: 1) }
        default:
            exit(2)
        }
    }
}
