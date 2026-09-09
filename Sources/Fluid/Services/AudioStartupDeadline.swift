import Foundation

/// Bounds the caller's wait, never the lifetime of a Core Audio operation.
/// Cancellation cannot interrupt AudioDeviceStart. Keep its task alive and reject
/// new starts until its serialized cleanup has actually completed.
@MainActor
final class AudioStartupDeadline {
    enum Failure: LocalizedError {
        case timedOut
        case recovering

        var errorDescription: String? {
            switch self {
            case .timedOut:
                return "The audio system did not start the microphone in time. Recording was cancelled. Try again after the audio system recovers."
            case .recovering:
                return "The previous microphone request is still recovering in macOS. Please wait before recording again."
            }
        }
    }

    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var waiter: CheckedContinuation<Void, Error>?
    var isRecovering: Bool { worker != nil && waiter == nil }

    func run(timeoutNanoseconds: UInt64 = 3_000_000_000,
             operation: @escaping @MainActor () async throws -> Void) async throws {
        guard worker == nil else { throw Failure.recovering }
        try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            worker = Task { @MainActor in
                let result: Result<Void, Error>
                do {
                    try Task.checkCancellation()
                    try await operation()
                    try Task.checkCancellation()
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                timer?.cancel()
                timer = nil
                worker = nil
                let pending = waiter
                waiter = nil
                pending?.resume(with: result)
            }
            timer = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
                catch { return }
                abandon(with: Failure.timedOut)
            }
        }
    }

    func cancel() { abandon(with: CancellationError()) }

    private func abandon(with error: Error) {
        guard let pending = waiter else { return }
        waiter = nil
        timer?.cancel()
        timer = nil
        worker?.cancel()
        pending.resume(throwing: error)
    }
}
