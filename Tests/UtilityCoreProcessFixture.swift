import Darwin
import Foundation

private var terminationRequested: Int32 = 0

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
        case "term-spawn-tree":
            if arguments.first == "term-spawn-tree" {
                guard arguments.count == 2 else { exit(2) }
                let child = Process()
                child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                child.arguments = ["term-spawn-child", arguments[1]]
                try child.run()
            }
            fallthrough
        case "sleep":
            signal(SIGTERM, SIG_IGN)
            while true { Thread.sleep(forTimeInterval: 1) }
        case "term-spawn-child":
            guard arguments.count == 2 else { exit(2) }
            signal(SIGTERM) { _ in terminationRequested = 1 }
            try "authored descendant ready".write(toFile: arguments[1] + ".ready", atomically: true, encoding: .utf8)
            while terminationRequested == 0 { Thread.sleep(forTimeInterval: 0.005) }
            let grandchild = Process()
            grandchild.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            grandchild.arguments = ["sleep"]
            try grandchild.run()
            try String(grandchild.processIdentifier).write(toFile: arguments[1], atomically: true, encoding: .utf8)
            exit(0)
        default:
            exit(2)
        }
    }
}
