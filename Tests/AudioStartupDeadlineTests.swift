import Foundation

@MainActor
final class FakeHardware {
    var release: CheckedContinuation<Void, Never>?
    var entered = false
    var cleaned = false
    func start() async throws {
        entered = true
        await withCheckedContinuation { release = $0 }
        // Simulate ASR's cancellation check and serialized hardware cleanup.
        defer { cleaned = true }
        try Task.checkCancellation()
    }
}

@main
struct AudioStartupDeadlineTests {
    @MainActor static func main() async throws {
        let gate = AudioStartupDeadline()
        try await gate.run { }
        precondition(!gate.isRecovering)

        let hardware = FakeHardware()
        do {
            try await gate.run(timeoutNanoseconds: 20_000_000) { try await hardware.start() }
            fatalError("Blocked hardware must time out")
        } catch AudioStartupDeadline.Failure.timedOut { }
        precondition(gate.isRecovering && !hardware.cleaned)
        do {
            try await gate.run { fatalError("Must not start another hardware operation") }
            fatalError("Recovery must reject a new start")
        } catch AudioStartupDeadline.Failure.recovering { }
        hardware.release?.resume()
        while gate.isRecovering { await Task.yield() }
        precondition(hardware.cleaned)
        try await gate.run { }

        let cancelledHardware = FakeHardware()
        let attempt = Task { @MainActor in
            do {
                try await gate.run(timeoutNanoseconds: 1_000_000_000) { try await cancelledHardware.start() }
                fatalError("Cancellation must wake the caller")
            } catch is CancellationError { }
        }
        while !cancelledHardware.entered { await Task.yield() }
        gate.cancel()
        try await attempt.value
        precondition(gate.isRecovering && !cancelledHardware.cleaned)
        // Double cancellation must not resume a continuation twice.
        gate.cancel()
        cancelledHardware.release?.resume()
        while gate.isRecovering { await Task.yield() }
        precondition(cancelledHardware.cleaned)
        try await gate.run { }
        print("PASS: success, deadline, retained ownership, retry exclusion, cancellation, late cleanup, reuse")
    }
}
