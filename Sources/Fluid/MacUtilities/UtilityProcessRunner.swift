import Darwin
import Foundation

nonisolated struct UtilityProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let executionTime: TimeInterval
    let outputTruncated: Bool

    var succeeded: Bool { exitCode == 0 }
}

nonisolated enum UtilityProcessError: Error, LocalizedError {
    case invalidConfiguration
    case launchFailed(String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The process configuration is invalid or exceeds its safety limits."
        case .launchFailed(let message):
            return "Could not start the process: \(message)"
        case .timedOut(let seconds):
            return "The process exceeded its \(Int(seconds.rounded(.up)))-second time limit."
        }
    }
}

/// Runs an explicitly selected executable with separate arguments, without a shell.
/// Pipe reads and process waiting happen on background queues, never the main actor.
nonisolated enum UtilityProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 30,
        maxOutputBytes: Int = 65_536
    ) async throws -> UtilityProcessResult {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/"),
              arguments.count <= 256,
              arguments.reduce(0, { $0 + $1.utf8.count }) <= 1_048_576,
              !arguments.contains(where: { $0.contains("\0") }),
              timeout.isFinite, timeout > 0, timeout <= 120,
              maxOutputBytes > 0, maxOutputBytes <= 1_048_576 else {
            throw UtilityProcessError.invalidConfiguration
        }
        let session = UtilityProcessSession(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                session.start(continuation)
            }
        } onCancel: {
            session.cancel()
        }
    }

    static func runAppleShortcut(
        named name: String,
        timeout: TimeInterval = 30
    ) async throws -> UtilityProcessResult {
        try UtilityActionRegistry.validate(.init(id: .runAppleShortcut, shortcutName: name))
        // A shortcut name containing punctuation is one argument, never shell source.
        return try await run(
            executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
            arguments: ["run", name],
            timeout: timeout
        )
    }
}

private nonisolated final class UtilityProcessSession: @unchecked Sendable {
    private enum StopReason {
        case cancelled
        case timeout
    }

    private struct ChildIdentity: Sendable {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    private let queue = DispatchQueue(label: "com.architech.saystone.utility-process", qos: .utility)
    private let executableURL: URL
    private let arguments: [String]
    private let workingDirectory: URL?
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let maxOutputBytes: Int
    // Mutable state below is owned exclusively by queue.
    private var process: Process?
    private var pipes: [Pipe] = []
    private var readers: [DispatchSourceRead] = []
    private var descriptors: [Int32] = []
    private var streamEnded = [false, false]
    private var streams = [Data(), Data()]
    private var outputTruncated = false
    private var continuation: CheckedContinuation<UtilityProcessResult, Error>?
    private var stopReason: StopReason?
    private var completed = false
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var timeoutWork: DispatchWorkItem?

    init(
        executableURL: URL, arguments: [String], workingDirectory: URL?,
        environment: [String: String], timeout: TimeInterval, maxOutputBytes: Int
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    func start(_ continuation: CheckedContinuation<UtilityProcessResult, Error>) {
        queue.async { self.startOnQueue(continuation) }
    }

    func cancel() {
        queue.async { self.stop(.cancelled) }
    }

    private func startOnQueue(_ continuation: CheckedContinuation<UtilityProcessResult, Error>) {
        self.continuation = continuation
        if stopReason != nil {
            finish(.failure(CancellationError()))
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        pipes = [Pipe(), Pipe()]
        process.standardOutput = pipes[0]
        process.standardError = pipes[1]
        self.process = process
        // Foundation owns and reaps its child. Register before launch so even an
        // immediately exiting command has an asynchronous completion receipt.
        process.terminationHandler = { [self] _ in
            self.queue.async { self.didExit() }
        }
        startedAt = ProcessInfo.processInfo.systemUptime

        do {
            for (index, pipe) in pipes.enumerated() {
                let descriptor = pipe.fileHandleForReading.fileDescriptor
                descriptors.append(descriptor)
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
                    throw UtilityProcessError.launchFailed("Could not prepare asynchronous output capture.")
                }
                let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
                source.setEventHandler { [weak self] in self?.drain(index) }
                // A cancelled source must release its descriptor on this same serial queue.
                source.setCancelHandler { try? pipe.fileHandleForReading.close() }
                readers.append(source)
                source.resume()
            }
            try process.run()
            // The child owns its duplicated write descriptors. Closing our copies makes EOF observable.
            for pipe in pipes { try? pipe.fileHandleForWriting.close() }

            let timeoutWork = DispatchWorkItem { [weak self] in self?.stop(.timeout) }
            self.timeoutWork = timeoutWork
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        } catch {
            finish(.failure(UtilityProcessError.launchFailed(error.localizedDescription)))
        }
    }

    private func drain(_ index: Int) {
        guard !completed, descriptors.indices.contains(index), !streamEnded[index] else { return }
        let descriptor = descriptors[index]
        var bytes = [UInt8](repeating: 0, count: 16_384)
        // Yield between batches so a continuously writing process cannot starve cancellation.
        for _ in 0..<64 {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                let remaining = maxOutputBytes - streams[index].count
                let kept = min(remaining, count)
                if kept > 0 { streams[index].append(contentsOf: bytes.prefix(kept)) }
                if kept < count { outputTruncated = true }
            } else if count == 0 {
                streamEnded[index] = true
                readers[index].cancel()
                return
            } else if errno == EINTR {
                continue
            } else {
                return // EAGAIN, or a stream that has already closed.
            }
        }
    }

    private func stop(_ reason: StopReason) {
        guard !completed, stopReason == nil else { return }
        stopReason = reason
        guard let process else { return }
        guard process.isRunning else {
            didExit()
            return
        }

        // Freeze the owned root and each discovered child before shutdown. Sending
        // SIGTERM and resuming them would let a handler spawn untracked replacements.
        let pid = process.processIdentifier
        guard let root = Self.identity(for: pid) else { return }
        Self.signal(root, SIGSTOP)
        let ownsProcessGroup = getpgid(pid) == pid
        let descendants = Self.descendants(of: pid)

        // Foundation may give the child its own process group. Only signal a group
        // led by our still-identical frozen root; never the app's inherited group.
        if ownsProcessGroup, Self.matches(root), getpgid(pid) == pid {
            _ = Darwin.kill(-pid, SIGKILL)
        }
        for child in descendants.reversed() { Self.signal(child, SIGKILL) }
        Self.signal(root, SIGKILL)
    }

    private func didExit() {
        guard !completed, let process else { return }
        // The root has exited; drain the bytes already in its pipes without waiting for EOF
        // from unrelated descendants that may have inherited a write descriptor.
        for index in pipes.indices { drain(index) }
        switch stopReason {
        case .cancelled:
            finish(.failure(CancellationError()))
        case .timeout:
            finish(.failure(UtilityProcessError.timedOut(timeout)))
        case nil:
            finish(.success(.init(
                stdout: Self.decodeOutput(streams[0]),
                stderr: Self.decodeOutput(streams[1]),
                exitCode: process.terminationStatus,
                executionTime: ProcessInfo.processInfo.systemUptime - startedAt,
                outputTruncated: outputTruncated
            )))
        }
    }

    private func finish(_ result: Result<UtilityProcessResult, Error>) {
        guard !completed else { return }
        completed = true
        timeoutWork?.cancel()
        timeoutWork = nil
        process?.terminationHandler = nil
        for reader in readers { reader.cancel() }
        for pipe in pipes { try? pipe.fileHandleForWriting.close() }
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func identity(for pid: pid_t) -> ChildIdentity? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize) == expectedSize else { return nil }
        return .init(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }

    private static func decodeOutput(_ data: Data) -> String {
        if let text = String(bytes: data, encoding: .utf8) { return text }
        // A cap can split a UTF-8 scalar. Retain valid text with replacement rather
        // than silently discarding the whole stream when strict decoding fails.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    private static func signal(_ child: ChildIdentity, _ signal: Int32) {
        guard matches(child) else { return }
        _ = Darwin.kill(child.pid, signal)
    }

    private static func matches(_ child: ChildIdentity) -> Bool {
        guard let current = identity(for: child.pid) else { return false }
        return current.startSeconds == child.startSeconds && current.startMicroseconds == child.startMicroseconds
    }

    private static func descendants(of pid: pid_t) -> [ChildIdentity] {
        var result = [ChildIdentity]()
        var parents = [pid]
        var visited = Set<pid_t>(parents)
        while let parent = parents.popLast(), result.count < 256 {
            var children = [pid_t](repeating: 0, count: 256)
            let count = children.withUnsafeMutableBytes { buffer in
                proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count))
            }
            guard count > 0 else { continue }
            // Unlike proc_listpids, proc_listchildpids returns a PID count, not a byte count.
            for child in children.prefix(min(Int(count), children.count)) where child > 0 {
                if visited.insert(child).inserted, let identity = identity(for: child) {
                    signal(identity, SIGSTOP)
                    result.append(identity)
                    parents.append(child)
                }
            }
        }
        return result
    }
}
