import AppKit
@testable import FluidVoice_Debug
import XCTest

/// Runs only in synthetic Development startup. All clipboard observations use
/// the coordinator's named test pasteboard; no window, target or polling starts.
@MainActor
final class MacUtilityCoordinatorTests: XCTestCase {
    func testIntentCannotInterleaveWithWorkflowBetweenSteps() async throws {
        let (coordinator, pasteboard) = try self.makeFixture()
        defer { coordinator.stop(); pasteboard.clearContents() }
        let sentinel = "Authored clipboard remains while workflow waits."
        XCTAssertTrue(pasteboard.setString(sentinel, forType: .string))
        var startedSteps = 0
        let workflow = UtilityWorkflow(steps: [
            .init(action: .init(id: .copyText)),
            .init(action: .init(id: .copyText))
        ])
        XCTAssertTrue(coordinator.workflowRunner.start(
            workflow: workflow, initialText: "Authored workflow input", latestTranscript: { nil }
        ) { request in
            startedSteps += 1
            if startedSteps == 1 { return .init(output: request.text, message: "Synthetic first step") }
            try await Task.sleep(for: .seconds(5))
            return .init(message: "Unexpected late step")
        })
        try await self.waitUntil { startedSteps == 2 }
        XCTAssertEqual(coordinator.workflowRunner.results.count, 1)
        do {
            _ = try await coordinator.executeFromIntent(.init(id: .copyLatestTranscript))
            XCTFail("An intent interleaved with an active workflow between dispatches.")
        } catch let error as UtilityActionError {
            guard case .invalidInput(let message) = error else { throw error }
            XCTAssertTrue(message.contains("already running"))
        }
        XCTAssertEqual(pasteboard.string(forType: .string), sentinel)
        coordinator.workflowRunner.cancel()
        try await self.waitUntil { !coordinator.workflowRunner.state.isRunning }
        XCTAssertEqual(coordinator.workflowRunner.state, .cancelled)
        XCTAssertEqual(coordinator.workflowRunner.results.count, 1)
    }

    func testPreCancelledIntentAndWorkflowPerformNoWork() async throws {
        let (coordinator, pasteboard) = try self.makeFixture()
        defer { coordinator.stop(); pasteboard.clearContents() }
        let sentinel = "Authored clipboard remains after cancellation."
        XCTAssertTrue(pasteboard.setString(sentinel, forType: .string))
        let task = Task { @MainActor in
            do {
                _ = try await coordinator.executeFromIntent(.init(id: .copyText, text: "Unexpected cancelled copy"))
                XCTFail("A cancelled intent reached clipboard dispatch.")
            } catch is CancellationError {
                // Cancellation must win before validation, state or side effects.
            } catch {
                XCTFail("Expected cancellation before intent dispatch: \(error)")
            }
            XCTAssertFalse(coordinator.runWorkflow(UtilityWorkflow(), input: "Unexpected cancelled workflow"))
            do {
                _ = try await coordinator.runWorkflowFromIntent(id: UUID(), input: "Cancelled authored input")
                XCTFail("A cancelled workflow intent started.")
            } catch is CancellationError {
                // Even a missing definition must not supersede pre-cancellation.
            } catch {
                XCTFail("Expected cancellation before workflow lookup: \(error)")
            }
        }
        task.cancel()
        await task.value
        XCTAssertEqual(pasteboard.string(forType: .string), sentinel)
        XCTAssertEqual(coordinator.workflowRunner.state, .idle)
        XCTAssertTrue(coordinator.workflowRunner.results.isEmpty)
        XCTAssertNil(coordinator.workflowRunner.runIdentifier)
    }

    func testLatestDictationPreservesLiteralTextAndIgnoresEmptyUpdates() throws {
        let (coordinator, pasteboard) = try self.makeFixture()
        defer { coordinator.stop(); pasteboard.clearContents() }
        let literal = "  Authored line one  \nLine two\t  "
        coordinator.recordDictationText(literal)
        XCTAssertEqual(coordinator.latestTranscript(), literal)
        coordinator.recordDictationText("")
        coordinator.recordDictationText(" \n\t ")
        XCTAssertEqual(coordinator.latestTranscript(), literal)
        let replacement = "Next authored dictation.  "
        coordinator.recordDictationText(replacement)
        XCTAssertEqual(coordinator.latestTranscript(), replacement)
    }

    func testCopyIntentUsesCurrentInMemoryDictation() async throws {
        let (coordinator, pasteboard) = try self.makeFixture()
        defer { coordinator.stop(); pasteboard.clearContents() }
        let literal = "Authored current dictation\nwith trailing spaces  "
        coordinator.recordDictationText(literal)
        let result = try await coordinator.executeFromIntent(.init(id: .copyLatestTranscript))
        XCTAssertEqual(result.output, literal)
        XCTAssertEqual(pasteboard.string(forType: .string), literal)
        XCTAssertEqual(coordinator.workflowRunner.state, .idle)
    }

    private func makeFixture() throws -> (MacUtilityCoordinator, NSPasteboard) {
        guard AppStorage.isDevelopment, DevelopmentRuntime.isUITesting,
              Bundle.main.bundleIdentifier == AppStorage.developmentBundleIdentifier
        else {
            throw XCTSkip("Coordinator fixtures require the isolated Development host with --ui-testing.")
        }
        let pasteboard = NSPasteboard(name: .init("SayStone.UITests.\(DevelopmentRuntime.testSession)"))
        pasteboard.clearContents()
        return (MacUtilityCoordinator(), pasteboard)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("The synthetic workflow did not reach its expected state within two seconds.")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
