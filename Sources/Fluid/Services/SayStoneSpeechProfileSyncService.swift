import Foundation

actor SayStoneSpeechProfileSyncService {
    static let shared = SayStoneSpeechProfileSyncService()

    static let enabledDefaultsKey = "SayStoneProfileSyncEnabled"
    static let endpointDefaultsKey = "SayStoneProfileSyncEndpoint"
    static let tokenKeychainID = "saystone-profile-sync"

    private struct Cache: Codable {
        let version: Int
        let deviceID: String
        var authority: SayStoneSpeechProfileDocument
        var pending: PutRequest?
    }

    private struct PutRequest: Codable {
        let baseRevision: Int
        let idempotencyKey: String
        var document: SayStoneSpeechProfileDocument
    }

    private struct GetResponse: Codable {
        let document: SayStoneSpeechProfileDocument
    }

    private struct PutResponse: Codable {
        let changed: Bool
        let document: SayStoneSpeechProfileDocument
    }

    private struct ErrorResponse: Codable {
        let code: String
        let document: SayStoneSpeechProfileDocument?
    }

    private enum SyncError: LocalizedError {
        case invalidEndpoint
        case missingToken
        case invalidResponse
        case rejected(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                "The SayStone profile sync endpoint is invalid."
            case .missingToken:
                "SayStone profile sync has no Forge credential."
            case .invalidResponse:
                "The SayStone profile server returned an invalid response."
            case let .rejected(status, code):
                "The SayStone profile server rejected sync (HTTP \(status)\(code.map { ", \($0)" } ?? ""))."
            }
        }
    }

    private var loopTask: Task<Void, Never>?
    private let fileManager: FileManager
    private let cacheURL: URL

    init(fileManager: FileManager = .default, cacheURL: URL? = nil) {
        self.fileManager = fileManager
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.cacheURL = baseURL
                .appendingPathComponent("FluidVoice", isDirectory: true)
                .appendingPathComponent("saystone-speech-profile-sync-v2.json")
        }
    }

    func start() {
        guard self.loopTask == nil else { return }
        self.loopTask = Task {
            while !Task.isCancelled {
                await self.syncOnce()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        self.loopTask?.cancel()
        self.loopTask = nil
    }

    func syncNow() async {
        await self.syncOnce()
    }

    private func syncOnce() async {
        guard UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) else { return }
        do {
            let endpoint = try self.profileURL()
            let token = try await MainActor.run {
                try KeychainService.shared.fetchKey(for: Self.tokenKeychainID)
            }
            guard let token, !token.isEmpty else {
                throw SyncError.missingToken
            }
            var cache = try self.loadCache()
            let snapshot = try await self.captureLocalSnapshot()

            if let pending = cache.pending {
                let response = try await self.put(pending, endpoint: endpoint, token: token)
                let followup = SayStoneSpeechProfileReconciler.reconcile(
                    snapshot: snapshot,
                    cached: pending.document,
                    deviceID: cache.deviceID,
                    now: Self.timestamp()
                )
                if followup.changed {
                    let next = PutRequest(
                        baseRevision: response.document.revision,
                        idempotencyKey: "\(cache.deviceID)-\(UUID().uuidString.lowercased())",
                        document: Self.rebased(followup.document, revision: response.document.revision)
                    )
                    cache.pending = next
                    try self.saveCache(cache)
                    let final = try await self.put(next, endpoint: endpoint, token: token)
                    try await self.apply(final.document)
                    cache.authority = final.document
                } else {
                    try await self.apply(response.document)
                    cache.authority = response.document
                }
                cache.pending = nil
                try self.saveCache(cache)
                return
            }

            let local = SayStoneSpeechProfileReconciler.reconcile(
                snapshot: snapshot,
                cached: cache.authority,
                deviceID: cache.deviceID,
                now: Self.timestamp()
            )
            let remote = try await self.get(endpoint: endpoint, token: token)
            let authority: SayStoneSpeechProfileDocument
            if local.changed {
                let request = PutRequest(
                    baseRevision: remote.revision,
                    idempotencyKey: "\(cache.deviceID)-\(UUID().uuidString.lowercased())",
                    document: Self.rebased(local.document, revision: remote.revision)
                )
                cache.pending = request
                try self.saveCache(cache)
                authority = try await self.put(request, endpoint: endpoint, token: token).document
            } else {
                authority = remote
            }

            try await self.apply(authority)
            cache.authority = authority
            cache.pending = nil
            try self.saveCache(cache)
        } catch {
            DebugLogger.shared.warning(
                "SayStone profile sync deferred: \(error.localizedDescription)",
                source: "SayStoneSpeechProfileSyncService"
            )
        }
    }

    private func profileURL() throws -> URL {
        guard let raw = UserDefaults.standard.string(forKey: Self.endpointDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              var components = URLComponents(string: raw),
              components.scheme == "http" || components.scheme == "https"
        else { throw SyncError.invalidEndpoint }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.hasSuffix("api/speech/profile")
            ? "/\(path)"
            : "/\(path.isEmpty ? "" : "\(path)/")api/speech/profile"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw SyncError.invalidEndpoint }
        return url
    }

    private func get(endpoint: URL, token: String) async throws -> SayStoneSpeechProfileDocument {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let code = try? JSONDecoder().decode(ErrorResponse.self, from: data).code
            throw SyncError.rejected(http.statusCode, code)
        }
        let decoded = try JSONDecoder().decode(GetResponse.self, from: data)
        try Self.validate(decoded.document)
        return decoded.document
    }

    private func put(_ body: PutRequest, endpoint: URL, token: String) async throws -> PutResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw SyncError.rejected(http.statusCode, decoded?.code)
        }
        let decoded = try JSONDecoder().decode(PutResponse.self, from: data)
        try Self.validate(decoded.document)
        return decoded
    }

    private func loadCache() throws -> Cache {
        if self.fileManager.fileExists(atPath: self.cacheURL.path) {
            let data = try Data(contentsOf: self.cacheURL)
            let decoded = try JSONDecoder().decode(Cache.self, from: data)
            guard decoded.version == 2,
                  decoded.authority.schemaRevision == SayStoneSpeechProfileDocument.currentSchemaRevision
            else {
                throw SyncError.invalidResponse
            }
            try Self.validate(decoded.authority)
            if let pending = decoded.pending { try Self.validate(pending.document) }
            return decoded
        }
        let now = Self.timestamp()
        return Cache(
            version: 2,
            deviceID: "saystone-\(UUID().uuidString.lowercased())",
            authority: .empty(updatedAt: now),
            pending: nil
        )
    }

    private func saveCache(_ cache: Cache) throws {
        try Self.validate(cache.authority)
        if let pending = cache.pending { try Self.validate(pending.document) }
        try self.fileManager.createDirectory(
            at: self.cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(cache).write(to: self.cacheURL, options: .atomic)
    }

    private func captureLocalSnapshot() async throws -> SayStoneSpeechProfileLocalSnapshot {
        let storedPronunciations = await PronunciationDictionaryStore.shared.allProfiles()
        return try await MainActor.run {
            let words = try ParakeetVocabularyStore.shared.loadUserBoostTerms().map {
                SayStoneSpeechProfileLocalSnapshot.Word(
                    text: $0.text,
                    weight: $0.weight,
                    aliases: $0.aliases
                )
            }
            let replacements = SettingsStore.shared.customDictionaryEntries.map {
                SayStoneSpeechProfileLocalSnapshot.Replacement(
                    id: $0.id,
                    triggers: $0.triggers,
                    replacement: $0.replacement
                )
            }
            return SayStoneSpeechProfileLocalSnapshot(
                words: words,
                replacements: replacements,
                punctuationEnabled: SettingsStore.shared.autoConvertPunctuationEnabled,
                pronunciationProfiles: storedPronunciations.map { profile in
                    .init(
                        dictionaryEntryID: profile.dictionaryEntryID,
                        label: profile.label,
                        modelKey: profile.modelKey,
                        hiddenSize: profile.hiddenSize,
                        enrollments: profile.enrollments.map { enrollment in
                            .init(
                                values: enrollment.values,
                                sourceFrameCount: enrollment.sourceFrameCount,
                                modelKey: enrollment.modelKey
                            )
                        }
                    )
                }
            )
        }
    }

    private func apply(_ document: SayStoneSpeechProfileDocument) async throws {
        let snapshot = SayStoneSpeechProfileReconciler.localSnapshot(from: document)
        let pronunciationProfiles = snapshot.pronunciationProfiles.map { profile in
            PronunciationDictionaryProfile(
                dictionaryEntryID: profile.dictionaryEntryID,
                label: profile.label,
                modelKey: profile.modelKey,
                hiddenSize: profile.hiddenSize,
                enrollments: profile.enrollments.map { enrollment in
                    PronunciationEnrollmentCapture(
                        values: enrollment.values,
                        sourceFrameCount: enrollment.sourceFrameCount,
                        modelKey: enrollment.modelKey
                    )
                }
            )
        }
        try await PronunciationDictionaryStore.shared.replaceAllProfiles(pronunciationProfiles)
        try await MainActor.run {
            let terms = snapshot.words.map {
                ParakeetVocabularyStore.VocabularyConfig.Term(
                    text: $0.text,
                    weight: $0.weight,
                    aliases: $0.aliases
                )
            }
            let replacements = snapshot.replacements.map {
                SettingsStore.CustomDictionaryEntry(
                    id: $0.id,
                    triggers: $0.triggers,
                    replacement: $0.replacement
                )
            }
            try ParakeetVocabularyStore.shared.saveUserBoostTerms(terms)
            SettingsStore.shared.customDictionaryEntries = replacements
            SettingsStore.shared.autoConvertPunctuationEnabled = snapshot.punctuationEnabled
            ASRService.invalidateDictionaryCache()
        }
    }

    private static func validate(_ document: SayStoneSpeechProfileDocument) throws {
        guard document.schemaRevision == SayStoneSpeechProfileDocument.currentSchemaRevision,
              document.revision >= 0,
              document.revision > 0 || document.entries.isEmpty,
              document.entries.count <= 4096,
              Set(document.entries.map(\.id)).count == document.entries.count,
              document.entries.allSatisfy({
                  guard !$0.id.isEmpty,
                        $0.id.count <= 128,
                        $0.revision > 0,
                        !$0.updatedByDeviceId.isEmpty
                  else { return false }
                  guard $0.kind == "pronunciation" else { return true }
                  guard let dictionaryEntryId = $0.dictionaryEntryId,
                        UUID(uuidString: dictionaryEntryId) != nil,
                        let label = $0.label,
                        !label.isEmpty,
                        let modelKey = $0.modelKey,
                        modelKey.hasPrefix("parakeet-"),
                        let hiddenSize = $0.hiddenSize,
                        (1 ... 4096).contains(hiddenSize),
                        let enrollments = $0.enrollments,
                        (1 ... 10).contains(enrollments.count)
                  else { return false }
                  return enrollments.allSatisfy { enrollment in
                      enrollment.modelKey == modelKey &&
                          enrollment.sourceFrameCount > 0 &&
                          enrollment.values.count == hiddenSize &&
                          enrollment.values.allSatisfy(\.isFinite)
                  }
              }) || (document.revision == 0 && document.entries.isEmpty)
        else { throw SyncError.invalidResponse }
    }

    private static func rebased(
        _ document: SayStoneSpeechProfileDocument,
        revision: Int
    ) -> SayStoneSpeechProfileDocument {
        var value = document
        value.revision = revision
        return value
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
