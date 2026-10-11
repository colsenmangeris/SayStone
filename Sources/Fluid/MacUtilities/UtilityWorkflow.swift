import Combine
import Foundation

nonisolated enum UtilityWorkflowInputSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case previousOutput
    case fixedText
    case latestTranscript

    var id: String { rawValue }
    var title: String {
        switch self {
        case .previousOutput: return "Previous output"
        case .fixedText: return "Authored text"
        case .latestTranscript: return "Latest transcript"
        }
    }
}

nonisolated struct UtilityWorkflowStep: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var action: UtilityActionRequest
    var input: UtilityWorkflowInputSource

    init(id: UUID = UUID(), action: UtilityActionRequest, input: UtilityWorkflowInputSource = .previousOutput) {
        self.id = id
        self.action = action
        self.input = input
    }
}

nonisolated struct UtilityWorkflow: Codable, Equatable, Identifiable, Sendable {
    static let maximumSteps = 24
    static let maximumTextBytes = 1_048_576

    var id: UUID
    var name: String
    var steps: [UtilityWorkflowStep]
    var voicePhrase: String
    var voiceEnabled: Bool
    /// Optional to decode existing version-1 definitions without changing their
    /// schema. Absence means ordinary dictation delivery remains selected.
    var runsAfterDictation: Bool?
    var timeoutSeconds: Double
    var stepTimeoutSeconds: Double

    init(
        id: UUID = UUID(), name: String = "New workflow",
        steps: [UtilityWorkflowStep] = [UtilityWorkflowStep(action: UtilityActionRequest(id: .copyText))],
        voicePhrase: String = "", voiceEnabled: Bool = false, runsAfterDictation: Bool? = nil,
        timeoutSeconds: Double = 60, stepTimeoutSeconds: Double = 20
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.voicePhrase = voicePhrase
        self.voiceEnabled = voiceEnabled
        self.runsAfterDictation = runsAfterDictation
        self.timeoutSeconds = timeoutSeconds
        self.stepTimeoutSeconds = stepTimeoutSeconds
    }

    static func normalizedVoicePhrase(_ phrase: String) -> String {
        phrase.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 80 else {
            throw UtilityWorkflowError.invalidDefinition("Use a workflow name between 1 and 80 characters.")
        }
        guard !steps.isEmpty, steps.count <= Self.maximumSteps else {
            throw UtilityWorkflowError.invalidDefinition("A workflow needs 1 to \(Self.maximumSteps) steps.")
        }
        guard Set(steps.map(\.id)).count == steps.count else {
            throw UtilityWorkflowError.invalidDefinition("Workflow step identifiers must be unique.")
        }
        guard timeoutSeconds.isFinite, (1...120).contains(timeoutSeconds),
              stepTimeoutSeconds.isFinite, (0.1...30).contains(stepTimeoutSeconds) else {
            throw UtilityWorkflowError.invalidDefinition("Use a run limit of 1–120 seconds and a step limit of 0.1–30 seconds.")
        }
        guard voicePhrase.utf8.count <= 256,
              !voiceEnabled || !Self.normalizedVoicePhrase(voicePhrase).isEmpty else {
            throw UtilityWorkflowError.invalidDefinition("Enter a voice phrase before enabling its trigger.")
        }
        for step in steps {
            if let text = step.action.text, text.utf8.count > Self.maximumTextBytes {
                throw UtilityWorkflowError.tooMuchText
            }
            var request = step.action
            if Self.usesText(request.id), step.input != .fixedText {
                request.text = "Workflow input"
            }
            try UtilityActionRegistry.validate(request)
        }
    }

    static func usesText(_ action: UtilityActionID) -> Bool {
        action == .copyText || action == .pasteText || action == .transformText || action == .runAppleShortcut
    }
}

nonisolated enum UtilityWorkflowError: LocalizedError, Equatable {
    case invalidDefinition(String)
    case missingTranscript
    case tooMuchText
    case timedOut
    case unsupportedSchema(Int)
    case malformedStorage
    case duplicateVoicePhrase
    case storageChanged

    var errorDescription: String? {
        switch self {
        case .invalidDefinition(let message): return message
        case .missingTranscript: return "There is no latest transcript to use."
        case .tooMuchText: return "Workflow text exceeds the 1 MiB limit."
        case .timedOut: return "The workflow reached its time limit. Later steps were stopped."
        case .unsupportedSchema(let version): return "This workflow file uses version \(version). It was preserved; update SayStone before editing it."
        case .malformedStorage: return "The workflow file could not be read. It will be preserved in a recovery file before new workflows are saved."
        case .duplicateVoicePhrase: return "An enabled workflow already uses this voice phrase."
        case .storageChanged: return "The workflow file changed since it was loaded. Reload saved workflows before saving again."
        }
    }
}

nonisolated enum UtilityWorkflowRunState: Equatable {
    case idle
    case running
    case cancelling
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool { self == .running || self == .cancelling }
    var title: String {
        switch self {
        case .idle: return "Ready"
        case .running: return "Running"
        case .cancelling: return "Stopping"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed(let message): return message
        }
    }
}

nonisolated struct UtilityWorkflowStepResult: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let action: UtilityActionID
    let message: String
    let output: String?
}

/// The executor owns focus revalidation and cancellation of side effects. A
/// deadline stops this pipeline even if an injected executor ignores cancellation.
@MainActor
final class UtilityWorkflowRunner: ObservableObject {
    typealias Executor = @MainActor (UtilityActionRequest) async throws -> UtilityActionResult

    @Published private(set) var state: UtilityWorkflowRunState = .idle
    @Published private(set) var results: [UtilityWorkflowStepResult] = []
    @Published private(set) var output: String?
    @Published private(set) var currentStepID: UUID?

    private var runTask: Task<Void, Never>?
    private(set) var runIdentifier: UUID?

    @discardableResult
    func start(
        workflow: UtilityWorkflow, initialText: String = "",
        latestTranscript: @escaping @MainActor () -> String?,
        executor: @escaping Executor
    ) -> Bool {
        guard !state.isRunning else { return false }
        results = []
        output = nil
        currentStepID = nil
        guard !Task.isCancelled else { state = .cancelled; return false }
        let transcript: String?
        do {
            try workflow.validate()
            guard initialText.utf8.count <= UtilityWorkflow.maximumTextBytes else {
                throw UtilityWorkflowError.tooMuchText
            }
            if workflow.steps.contains(where: {
                $0.action.id == .copyLatestTranscript || UtilityWorkflow.usesText($0.action.id) && $0.input == .latestTranscript
            }) {
                guard let latest = latestTranscript(), !latest.isEmpty else {
                    throw UtilityWorkflowError.missingTranscript
                }
                guard latest.utf8.count <= UtilityWorkflow.maximumTextBytes else {
                    throw UtilityWorkflowError.tooMuchText
                }
                transcript = latest
            } else {
                transcript = nil
            }
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
        let identifier = UUID()
        runIdentifier = identifier
        results = []
        output = initialText
        currentStepID = nil
        state = .running
        runTask = Task { [weak self] in
            guard let self else { return }
            let deadline = ContinuousClock.now.advanced(by: .seconds(workflow.timeoutSeconds))
            var text = initialText
            do {
                for (index, step) in workflow.steps.enumerated() {
                    try Task.checkCancellation()
                    guard self.runIdentifier == identifier, self.state == .running else { throw CancellationError() }
                    let remaining = ContinuousClock.now.duration(to: deadline)
                    guard remaining > .zero else { throw UtilityWorkflowError.timedOut }
                    var request = step.action
                    if request.id == .copyLatestTranscript {
                        // Resolve this fixed action from the same run snapshot
                        // as explicit Latest transcript input, never live history.
                        request = UtilityActionRequest(id: .copyText, text: transcript)
                    } else if UtilityWorkflow.usesText(request.id) {
                        switch step.input {
                        case .previousOutput: request.text = text
                        case .fixedText: break
                        case .latestTranscript:
                            request.text = transcript
                        }
                    }
                    try UtilityActionRegistry.validate(request)
                    self.currentStepID = step.id
                    let limit = min(remaining, .seconds(workflow.stepTimeoutSeconds))
                    let result = try await Self.execute(request, limit: limit, executor: executor)
                    try Task.checkCancellation()
                    guard self.runIdentifier == identifier, self.state == .running else { throw CancellationError() }
                    if let newText = result.output {
                        guard newText.utf8.count <= UtilityWorkflow.maximumTextBytes else {
                            throw UtilityWorkflowError.tooMuchText
                        }
                        text = newText
                    }
                    self.output = text
                    self.results.append(UtilityWorkflowStepResult(
                        id: step.id,
                        index: index,
                        action: step.action.id,
                        message: result.message,
                        output: result.output
                    ))
                }
                self.state = .completed
            } catch is CancellationError {
                self.state = .cancelled
            } catch {
                self.state = .failed(error.localizedDescription)
            }
            if self.runIdentifier == identifier {
                self.currentStepID = nil
                self.runTask = nil
                self.runIdentifier = nil
            }
        }
        return true
    }

    func cancel() {
        guard state == .running else { return }
        state = .cancelling
        runTask?.cancel()
    }

    /// A delayed caller's cancellation applies only to the run it started.
    func cancel(runIdentifier: UUID) {
        guard self.runIdentifier == runIdentifier else { return }
        cancel()
    }

    private static func execute(
        _ request: UtilityActionRequest, limit: Duration, executor: @escaping Executor
    ) async throws -> UtilityActionResult {
        let gate = UtilityWorkflowExecutionGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.register(continuation)
                let worker = Task { @MainActor in
                    do {
                        try Task.checkCancellation()
                        gate.finish(.success(try await executor(request)))
                    } catch {
                        gate.finish(.failure(error))
                    }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(for: limit)
                        gate.finish(.failure(UtilityWorkflowError.timedOut))
                    } catch { /* The winning operation cancels its timer. */ }
                }
                gate.install(worker: worker, timer: timer)
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Checked-continuation ownership is protected across cancellation and timer
/// races. Unstructured tasks avoid a task group's wait for an uncooperative child.
private nonisolated final class UtilityWorkflowExecutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UtilityActionResult, Error>?
    private var result: Result<UtilityActionResult, Error>?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    func register(_ continuation: CheckedContinuation<UtilityActionResult, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func install(worker: Task<Void, Never>, timer: Task<Void, Never>) {
        lock.lock()
        let finished = result != nil
        if !finished {
            self.worker = worker
            self.timer = timer
        }
        lock.unlock()
        if finished {
            worker.cancel()
            timer.cancel()
        }
    }

    func finish(_ result: Result<UtilityActionResult, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        let worker = self.worker
        let timer = self.timer
        self.continuation = nil
        self.worker = nil
        self.timer = nil
        lock.unlock()
        worker?.cancel()
        timer?.cancel()
        continuation?.resume(with: result)
    }
}
