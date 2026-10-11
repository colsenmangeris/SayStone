import Foundation

private enum FixtureFailure: Error { case failed(String) }

@main
struct UtilityWorkflowFixtureTests {
    @MainActor static func main() async throws {
        try validation()
        try persistence()
        try await propagation()
        try await missingTranscript()
        try await cancellation()
        try await deadline()
        try await outputBound()
        print("Workflow fixtures passed: validation, versioned storage/recovery, exact voice triggers, propagation, cancellation and deadlines.")
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw FixtureFailure.failed(message) }
    }

    static func requiresFailure(_ operation: () throws -> Void, _ message: String) throws {
        do { try operation() } catch { return }
        throw FixtureFailure.failed(message)
    }

    static func validation() throws {
        var workflow = UtilityWorkflow()
        try workflow.validate()
        workflow.steps = []
        try requiresFailure({ try workflow.validate() }, "Empty pipeline accepted")
        workflow.steps = Array(repeating: UtilityWorkflowStep(action: UtilityActionRequest(id: .copyText)), count: 2)
        try requiresFailure({ try workflow.validate() }, "Duplicate step identifiers accepted")
        workflow.steps = (0...UtilityWorkflow.maximumSteps).map { _ in UtilityWorkflowStep(action: UtilityActionRequest(id: .copyText)) }
        try requiresFailure({ try workflow.validate() }, "Unbounded steps accepted")
        workflow = UtilityWorkflow(steps: [.init(action: .init(id: .copyText, text: ""), input: .fixedText)])
        try requiresFailure({ try workflow.validate() }, "Empty authored text accepted")
        workflow = UtilityWorkflow(steps: [.init(action: .init(id: .transformText))])
        try requiresFailure({ try workflow.validate() }, "Missing transform accepted")
        workflow = UtilityWorkflow(steps: [.init(action: .init(id: .openURL, urlString: "javascript:alert(1)"))])
        try requiresFailure({ try workflow.validate() }, "Executable URL accepted")
        workflow = UtilityWorkflow(timeoutSeconds: .infinity)
        try requiresFailure({ try workflow.validate() }, "Infinite deadline accepted")
        workflow = UtilityWorkflow(voiceEnabled: true)
        try requiresFailure({ try workflow.validate() }, "Empty voice trigger accepted")
    }

    @MainActor static func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saystone-workflow-fixtures-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workflows.json")
        let store = UtilityWorkflowStore(url: url)
        let workflow = UtilityWorkflow(name: "Fixture", voicePhrase: "  Copy   sample ", voiceEnabled: true)
        try store.save(workflow)
        let loaded = UtilityWorkflowStore(url: url)
        try require(loaded.workflows == [workflow], "Definitions did not round-trip")
        try require(loaded.dictationWorkflow() == nil, "Dictation workflow was enabled by default")
        try require(loaded.matchingVoicePhrase("COPY sample")?.id == workflow.id, "Configured exact trigger failed")
        try require(loaded.matchingVoicePhrase("Please copy sample") == nil, "Partial trigger executed")
        try require(loaded.matchingVoicePhrase("copy sample.") == nil, "Punctuation was silently broadened")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        try require(permissions?.intValue == 0o600, "Definitions were not private")
        let validBytes = try Data(contentsOf: url)
        let encodedDocument = try JSONSerialization.jsonObject(with: validBytes) as? [String: Any]
        let encodedWorkflows = encodedDocument?["workflows"] as? [[String: Any]]
        try require(encodedWorkflows?.first?["runsAfterDictation"] == nil, "Legacy version-1 fixture unexpectedly included dictation flag")
        try requiresFailure({ try loaded.save(UtilityWorkflow(voicePhrase: "copy sample", voiceEnabled: true)) }, "Duplicate enabled phrase accepted")
        try require(try Data(contentsOf: url) == validBytes, "Failed validation changed disk")

        var firstActive = workflow
        firstActive.runsAfterDictation = true
        try loaded.save(firstActive)
        try require(loaded.dictationWorkflow()?.id == workflow.id, "Dictation workflow selection was not saved")
        var secondActive = UtilityWorkflow(name: "Second dictation fixture", runsAfterDictation: true)
        try loaded.save(secondActive)
        let switched = UtilityWorkflowStore(url: url)
        try require(switched.dictationWorkflow()?.id == secondActive.id, "Dictation selection did not persist switching")
        try require(switched.workflows.first(where: { $0.id == workflow.id })?.runsAfterDictation == false, "Previous dictation selection remained active")
        secondActive.runsAfterDictation = false
        try loaded.save(secondActive)
        try require(UtilityWorkflowStore(url: url).dictationWorkflow() == nil, "Dictation selection did not turn off")
        try loaded.delete(id: secondActive.id)
        try loaded.delete(id: workflow.id)
        try require(UtilityWorkflowStore(url: url).workflows.isEmpty, "Delete did not persist")

        let malformed = Data("{ broken fixture".utf8)
        try malformed.write(to: url)
        let recovered = UtilityWorkflowStore(url: url)
        try require(recovered.workflows.isEmpty && recovered.errorMessage != nil, "Malformed file did not surface")
        try require(try Data(contentsOf: url) == malformed, "Loading altered malformed source")
        try recovered.save(workflow)
        guard let backup = recovered.recoveryFileURL else { throw FixtureFailure.failed("Malformed file was not preserved") }
        try require(try Data(contentsOf: backup) == malformed, "Recovery backup did not preserve bytes")

        let future = Data("{\"version\":99,\"workflows\":[]}".utf8)
        try future.write(to: url)
        let newer = UtilityWorkflowStore(url: url)
        try requiresFailure({ try newer.save(workflow) }, "Future schema was overwritten")
        try require(try Data(contentsOf: url) == future, "Newer definition file changed")

        let oldEnvelope: [String: Any] = ["version": 0, "workflows": []]
        try JSONSerialization.data(withJSONObject: oldEnvelope).write(to: url)
        let old = UtilityWorkflowStore(url: url)
        try old.save(workflow)
        let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        try require(updated?["version"] as? Int == 1, "Old envelope did not upgrade on save")

        try Data(repeating: 0, count: UtilityWorkflowStore.maximumFileBytes + 1).write(to: url)
        try require(UtilityWorkflowStore(url: url).errorMessage != nil, "Oversized storage accepted")
    }

    @MainActor static func waitForRun(_ runner: UtilityWorkflowRunner, timeout: Double = 2) async throws {
        let limit = ContinuousClock.now.advanced(by: .seconds(timeout))
        while runner.state.isRunning {
            try require(ContinuousClock.now < limit, "Runner did not stop within fixture deadline")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor static func propagation() async throws {
        let runner = UtilityWorkflowRunner()
        var requests: [UtilityActionRequest] = []
        let workflow = UtilityWorkflow(steps: [
            .init(action: .init(id: .transformText, transform: .uppercase)),
            .init(action: .init(id: .launchApp, bundleIdentifier: "com.apple.TextEdit")),
            .init(action: .init(id: .copyText)),
            .init(action: .init(id: .runAppleShortcut, shortcutName: "Authored Fixture Shortcut")),
            .init(action: .init(id: .copyText, text: "fixed fixture"), input: .fixedText),
            .init(action: .init(id: .copyText), input: .latestTranscript)
        ])
        let executor: UtilityWorkflowRunner.Executor = { request in
            requests.append(request)
            if let transform = request.transform, let text = request.text {
                return UtilityActionResult(output: transform.apply(to: text), message: "Transformed")
            }
            return UtilityActionResult(output: request.text, message: "Fixture action")
        }
        try require(runner.start(workflow: workflow, initialText: "Mixed Fixture", latestTranscript: { "raw authored transcript" }, executor: executor), "Valid workflow did not start")
        try require(!runner.start(workflow: workflow, latestTranscript: { nil }, executor: executor), "Concurrent workflow started")
        try await waitForRun(runner)
        try require(runner.state == .completed && requests.count == 6, "Workflow did not complete all steps")
        try require(requests[2].text == "MIXED FIXTURE", "No-output action destroyed prior output")
        try require(requests[3].text == "MIXED FIXTURE", "Named Apple Shortcut did not receive previous output")
        try require(requests[4].text == "fixed fixture", "Authored text source failed")
        try require(requests[5].text == "raw authored transcript", "Latest transcript source failed")
        try require(runner.output == "raw authored transcript" && runner.results.count == 6, "Final output/results incorrect")
    }

    @MainActor static func missingTranscript() async throws {
        let runner = UtilityWorkflowRunner()
        var called = false
        let workflow = UtilityWorkflow(steps: [.init(action: .init(id: .copyText), input: .latestTranscript)])
        runner.start(workflow: workflow, latestTranscript: { nil }) { _ in
            called = true
            return UtilityActionResult(message: "Unexpected")
        }
        try await waitForRun(runner)
        try require(!called && runner.results.isEmpty, "Missing transcript still executed")
        guard case .failed = runner.state else { throw FixtureFailure.failed("Missing transcript did not fail visibly") }
    }

    @MainActor static func cancellation() async throws {
        let runner = UtilityWorkflowRunner()
        var started = 0
        var executorCancelled = false
        let workflow = UtilityWorkflow(steps: [.init(action: .init(id: .copyText)), .init(action: .init(id: .copyText))])
        runner.start(workflow: workflow, initialText: "cancel fixture", latestTranscript: { nil }) { _ in
            started += 1
            do { try await Task.sleep(for: .seconds(5)) } catch { executorCancelled = true; throw error }
            return UtilityActionResult(output: "late output", message: "Unexpected")
        }
        try await Task.sleep(for: .milliseconds(25))
        runner.cancel()
        try await waitForRun(runner)
        try await Task.sleep(for: .milliseconds(10))
        try require(runner.state == .cancelled && started == 1 && executorCancelled, "Cancellation failed to stop executor/later step")
        try require(runner.results.isEmpty && runner.output == "cancel fixture", "Cancelled result was delivered")
    }

    @MainActor static func deadline() async throws {
        let runner = UtilityWorkflowRunner()
        var started = 0
        let workflow = UtilityWorkflow(steps: [.init(action: .init(id: .copyText)), .init(action: .init(id: .copyText))], stepTimeoutSeconds: 0.1)
        let began = ContinuousClock.now
        runner.start(workflow: workflow, initialText: "deadline fixture", latestTranscript: { nil }) { _ in
            started += 1
            // This deliberately ignores cancellation, proving the deadline does
            // not wait for a cooperative task-group child before returning.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) { continuation.resume() }
            }
            return UtilityActionResult(output: "late output", message: "Late fixture")
        }
        try await waitForRun(runner)
        try require(began.duration(to: .now) < .milliseconds(300), "Timeout waited for uncooperative executor")
        if case .failed = runner.state {} else { throw FixtureFailure.failed("Deadline did not fail visibly") }
        try await Task.sleep(for: .milliseconds(380))
        try require(started == 1 && runner.results.isEmpty && runner.output == "deadline fixture", "Late deadline result or next step escaped")
    }

    @MainActor static func outputBound() async throws {
        let runner = UtilityWorkflowRunner()
        var called = 0
        let workflow = UtilityWorkflow(steps: [.init(action: .init(id: .copyText)), .init(action: .init(id: .copyText))])
        runner.start(workflow: workflow, initialText: "bounded fixture", latestTranscript: { nil }) { _ in
            called += 1
            return UtilityActionResult(output: String(repeating: "x", count: UtilityWorkflow.maximumTextBytes + 1), message: "Oversized")
        }
        try await waitForRun(runner)
        try require(called == 1 && runner.results.isEmpty, "Oversized output reached later action")
        if case .failed = runner.state {} else { throw FixtureFailure.failed("Oversized output did not fail") }
    }
}
