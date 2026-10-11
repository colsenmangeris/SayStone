import Combine
import Foundation

@MainActor
final class UtilityWorkflowStore: ObservableObject {
    nonisolated static let maximumWorkflows = 100
    nonisolated static let maximumFileBytes = 4_194_304

    @Published private(set) var workflows: [UtilityWorkflow] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var recoveryFileURL: URL?
    @Published private(set) var requiresReload = false

    let url: URL
    private var malformedFileNeedsPreservation = false
    private var unsupportedVersion: Int?
    private var loadedFileStamp: FileStamp?

    private struct FileStamp: Equatable {
        let size: Int
        let modifiedAt: Date?
        let fileNumber: UInt64?

        init(_ attributes: [FileAttributeKey: Any]) {
            size = (attributes[.size] as? NSNumber)?.intValue ?? UtilityWorkflowStore.maximumFileBytes + 1
            modifiedAt = attributes[.modificationDate] as? Date
            fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        }
    }

    private struct Document: Codable {
        let version: Int
        let workflows: [UtilityWorkflow]
    }

    init(url: URL? = nil) {
        self.url = url ?? AppStorage.applicationSupportFallback
            .appendingPathComponent("FluidVoice/MacUtilities", isDirectory: true)
            .appendingPathComponent("workflows.json")
        reload()
    }

    func reload() {
        malformedFileNeedsPreservation = false
        unsupportedVersion = nil
        errorMessage = nil
        requiresReload = false
        loadedFileStamp = nil
        guard FileManager.default.fileExists(atPath: url.path) else { workflows = []; return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            loadedFileStamp = FileStamp(attributes)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? Self.maximumFileBytes + 1
            guard size <= Self.maximumFileBytes else { throw UtilityWorkflowError.malformedStorage }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= Self.maximumFileBytes {
                let limit = min(65_536, Self.maximumFileBytes + 1 - data.count)
                guard let chunk = try handle.read(upToCount: limit), !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count <= Self.maximumFileBytes else { throw UtilityWorkflowError.malformedStorage }
            // Inspect the version first so newer definitions are never overwritten.
            let version = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int
            guard let version else { throw UtilityWorkflowError.malformedStorage }
            guard version == 0 || version == 1 else {
                unsupportedVersion = version
                throw UtilityWorkflowError.unsupportedSchema(version)
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            try Self.validate(document.workflows)
            workflows = document.workflows
        } catch {
            workflows = []
            malformedFileNeedsPreservation = unsupportedVersion == nil
            errorMessage = unsupportedVersion.map { UtilityWorkflowError.unsupportedSchema($0).localizedDescription }
                ?? UtilityWorkflowError.malformedStorage.localizedDescription
        }
    }

    func save(_ workflow: UtilityWorkflow) throws {
        var updated = workflows
        if let index = updated.firstIndex(where: { $0.id == workflow.id }) {
            updated[index] = workflow
        } else {
            updated.append(workflow)
        }
        if workflow.runsAfterDictation == true {
            for index in updated.indices where updated[index].id != workflow.id {
                updated[index].runsAfterDictation = false
            }
        }
        try persist(updated)
    }

    func delete(id: UUID) throws {
        try persist(workflows.filter { $0.id != id })
    }

    /// Exact matching after case/whitespace normalization. Partial phrases and
    /// generated commands never resolve to a workflow.
    func matchingVoicePhrase(_ phrase: String) -> UtilityWorkflow? {
        let key = UtilityWorkflow.normalizedVoicePhrase(phrase)
        guard !key.isEmpty else { return nil }
        return workflows.first { $0.voiceEnabled && UtilityWorkflow.normalizedVoicePhrase($0.voicePhrase) == key }
    }

    /// The dictation coordinator provides the recognized text as initial input.
    /// This selection is independent of voice-phrase matching and is off by default.
    func dictationWorkflow() -> UtilityWorkflow? {
        workflows.first { $0.runsAfterDictation == true }
    }

    private func persist(_ updated: [UtilityWorkflow]) throws {
        do {
            if let unsupportedVersion { throw UtilityWorkflowError.unsupportedSchema(unsupportedVersion) }
            try Self.validate(updated)
            let currentStamp: FileStamp?
            if FileManager.default.fileExists(atPath: url.path) {
                currentStamp = FileStamp(try FileManager.default.attributesOfItem(atPath: url.path))
            } else {
                currentStamp = nil
            }
            guard currentStamp == loadedFileStamp else {
                requiresReload = true
                throw UtilityWorkflowError.storageChanged
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Document(version: 1, workflows: updated))
            guard data.count <= Self.maximumFileBytes else {
                throw UtilityWorkflowError.invalidDefinition("Workflow storage exceeds the 4 MiB limit.")
            }
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if malformedFileNeedsPreservation, FileManager.default.fileExists(atPath: url.path) {
                let backup = directory.appendingPathComponent("workflows.recovered.\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: url, to: backup)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                recoveryFileURL = backup
                malformedFileNeedsPreservation = false
            }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            loadedFileStamp = FileStamp(try FileManager.default.attributesOfItem(atPath: url.path))
            workflows = updated
            requiresReload = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private static func validate(_ workflows: [UtilityWorkflow]) throws {
        guard workflows.count <= maximumWorkflows, Set(workflows.map(\.id)).count == workflows.count else {
            throw UtilityWorkflowError.invalidDefinition("Keep at most \(maximumWorkflows) workflows, each with a unique identifier.")
        }
        guard workflows.filter({ $0.runsAfterDictation == true }).count <= 1 else {
            throw UtilityWorkflowError.invalidDefinition("Select only one workflow to run after dictation.")
        }
        var phrases = Set<String>()
        for workflow in workflows {
            try workflow.validate()
            if workflow.voiceEnabled {
                guard phrases.insert(UtilityWorkflow.normalizedVoicePhrase(workflow.voicePhrase)).inserted else {
                    throw UtilityWorkflowError.duplicateVoicePhrase
                }
            }
        }
    }
}
