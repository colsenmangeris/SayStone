import CryptoKit
import Foundation

nonisolated struct SayStoneSpeechProfileDocument: Codable, Equatable, Sendable {
    static let currentSchemaRevision = 2

    let schemaRevision: Int
    var revision: Int
    var updatedAt: String
    var pronunciation: PronunciationCompatibility?
    var entries: [Entry]

    struct PronunciationCompatibility: Codable, Equatable, Sendable {
        let modelKey: String
        let hiddenSize: Int
    }

    struct Entry: Codable, Equatable, Sendable {
        var id: String
        var revision: Int
        var updatedAt: String
        var updatedByDeviceId: String
        var deleted: Bool
        var kind: String
        var text: String?
        var weight: Int?
        var alias: String?
        var canonical: String?
        var from: String?
        var to: String?
        var setting: PreferenceSetting?
        var dictionaryEntryId: String? = nil
        var label: String? = nil
        var modelKey: String? = nil
        var hiddenSize: Int? = nil
        var enrollments: [PronunciationEnrollment]? = nil

        struct PronunciationEnrollment: Codable, Equatable, Sendable {
            let values: [Float]
            let sourceFrameCount: Int
            let modelKey: String
        }

        struct PreferenceSetting: Codable, Equatable, Sendable {
            let key: String
            let boolValue: Bool?
            let stringValue: String?

            private enum CodingKeys: String, CodingKey {
                case key
                case value
            }

            init(key: String, boolValue: Bool? = nil, stringValue: String? = nil) {
                self.key = key
                self.boolValue = boolValue
                self.stringValue = stringValue
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.key = try container.decode(String.self, forKey: .key)
                if let value = try? container.decode(Bool.self, forKey: .value) {
                    self.boolValue = value
                    self.stringValue = nil
                } else {
                    self.boolValue = nil
                    self.stringValue = try container.decode(String.self, forKey: .value)
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(self.key, forKey: .key)
                if let boolValue {
                    try container.encode(boolValue, forKey: .value)
                } else if let stringValue {
                    try container.encode(stringValue, forKey: .value)
                } else {
                    throw EncodingError.invalidValue(
                        self,
                        EncodingError.Context(
                            codingPath: encoder.codingPath,
                            debugDescription: "A speech profile preference needs one value."
                        )
                    )
                }
            }
        }
    }

    static func empty(updatedAt: String) -> Self {
        Self(
            schemaRevision: Self.currentSchemaRevision,
            revision: 0,
            updatedAt: updatedAt,
            pronunciation: nil,
            entries: []
        )
    }
}

nonisolated struct SayStoneSpeechProfileLocalSnapshot: Equatable, Sendable {
    struct Word: Equatable, Sendable {
        let text: String
        let weight: Float?
        let aliases: [String]
    }

    struct Replacement: Equatable, Sendable {
        let id: UUID
        let triggers: [String]
        let replacement: String
    }

    struct PronunciationProfile: Equatable, Sendable {
        let dictionaryEntryID: UUID
        let label: String
        let modelKey: String
        let hiddenSize: Int
        let enrollments: [SayStoneSpeechProfileDocument.Entry.PronunciationEnrollment]
    }

    let words: [Word]
    let replacements: [Replacement]
    let punctuationEnabled: Bool
    let pronunciationProfiles: [PronunciationProfile]
}

nonisolated enum SayStoneSpeechProfileReconciler {
    typealias Document = SayStoneSpeechProfileDocument
    typealias Entry = SayStoneSpeechProfileDocument.Entry

    struct Result: Equatable, Sendable {
        let changed: Bool
        let document: Document
    }

    static func reconcile(
        snapshot: SayStoneSpeechProfileLocalSnapshot,
        cached: Document,
        deviceID: String,
        now: String
    ) -> Result {
        let desired = Dictionary(uniqueKeysWithValues: self.desiredEntries(snapshot: snapshot).map { ($0.id, $0) })
        var resultByID = Dictionary(uniqueKeysWithValues: cached.entries.map { ($0.id, $0) })
        var changed = false

        for (id, desiredEntry) in desired {
            if let current = resultByID[id], !current.deleted,
               self.payloadSignature(current) == self.payloadSignature(desiredEntry)
            {
                continue
            }
            let nextRevision = (resultByID[id]?.revision ?? 0) + 1
            var next = desiredEntry
            next.revision = nextRevision
            next.updatedAt = now
            next.updatedByDeviceId = deviceID
            next.deleted = false
            resultByID[id] = next
            changed = true
        }

        for entry in cached.entries where self.isLocallyManaged(entry) && desired[entry.id] == nil && !entry.deleted {
            var tombstone = entry
            tombstone.revision += 1
            tombstone.updatedAt = now
            tombstone.updatedByDeviceId = deviceID
            tombstone.deleted = true
            resultByID[entry.id] = tombstone
            changed = true
        }

        let pronunciation = snapshot.pronunciationProfiles
            .sorted { $0.dictionaryEntryID.uuidString < $1.dictionaryEntryID.uuidString }
            .first
            .map { Document.PronunciationCompatibility(modelKey: $0.modelKey, hiddenSize: $0.hiddenSize) }

        return Result(
            changed: changed,
            document: Document(
                schemaRevision: Document.currentSchemaRevision,
                revision: cached.revision,
                updatedAt: changed ? now : cached.updatedAt,
                pronunciation: pronunciation,
                entries: resultByID.values.sorted { $0.id < $1.id }
            )
        )
    }

    static func localSnapshot(from document: Document) -> SayStoneSpeechProfileLocalSnapshot {
        let active = document.entries.filter { !$0.deleted }
        let aliasesByCanonical = Dictionary(grouping: active.filter { $0.kind == "alias" }) {
            ($0.canonical ?? "").lowercased()
        }
        let words = active.compactMap { entry -> SayStoneSpeechProfileLocalSnapshot.Word? in
            guard entry.kind == "word", let text = entry.text else { return nil }
            let aliases = aliasesByCanonical[text.lowercased(), default: []]
                .compactMap(\.alias)
                .uniquedCaseInsensitive()
            return .init(text: text, weight: entry.weight.map(Float.init), aliases: aliases)
        }.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }

        let groupedReplacements = Dictionary(grouping: active.filter { $0.kind == "replacement" }) {
            self.replacementUUID(entryID: $0.id)
        }
        let replacements = groupedReplacements.compactMap { uuid, entries -> SayStoneSpeechProfileLocalSnapshot.Replacement? in
            guard let uuid,
                  let replacement = entries.compactMap(\.to).first,
                  !replacement.isEmpty
            else { return nil }
            let triggers = entries.compactMap(\.from).uniquedCaseInsensitive()
            guard !triggers.isEmpty else { return nil }
            return .init(id: uuid, triggers: triggers, replacement: replacement)
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        let punctuationEnabled = active.first {
            $0.kind == "preference" && $0.setting?.key == "punctuation"
        }?.setting?.boolValue ?? true

        let pronunciationProfiles = active.compactMap {
            entry -> SayStoneSpeechProfileLocalSnapshot.PronunciationProfile? in
            guard entry.kind == "pronunciation",
                  let rawID = entry.dictionaryEntryId,
                  let dictionaryEntryID = UUID(uuidString: rawID),
                  let label = entry.label,
                  let modelKey = entry.modelKey,
                  let hiddenSize = entry.hiddenSize,
                  hiddenSize > 0,
                  let enrollments = entry.enrollments,
                  !enrollments.isEmpty,
                  enrollments.allSatisfy({
                      $0.modelKey == modelKey && $0.values.count == hiddenSize && $0.sourceFrameCount > 0
                  })
            else { return nil }
            return .init(
                dictionaryEntryID: dictionaryEntryID,
                label: label,
                modelKey: modelKey,
                hiddenSize: hiddenSize,
                enrollments: Array(enrollments.prefix(10))
            )
        }.sorted { lhs, rhs in
            if lhs.dictionaryEntryID == rhs.dictionaryEntryID { return lhs.modelKey < rhs.modelKey }
            return lhs.dictionaryEntryID.uuidString < rhs.dictionaryEntryID.uuidString
        }

        return .init(
            words: Array(words.prefix(256)),
            replacements: replacements,
            punctuationEnabled: punctuationEnabled,
            pronunciationProfiles: pronunciationProfiles
        )
    }

    private static func desiredEntries(snapshot: SayStoneSpeechProfileLocalSnapshot) -> [Entry] {
        var entries: [Entry] = []
        for word in snapshot.words.prefix(256) {
            let normalizedText = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { continue }
            entries.append(
                Entry(
                    id: "word-\(self.digest(normalizedText.lowercased()))",
                    revision: 0,
                    updatedAt: "",
                    updatedByDeviceId: "",
                    deleted: false,
                    kind: "word",
                    text: normalizedText,
                    weight: word.weight.map { min(1000, max(0, Int($0.rounded()))) },
                    alias: nil,
                    canonical: nil,
                    from: nil,
                    to: nil,
                    setting: nil
                )
            )
            for alias in word.aliases.uniquedCaseInsensitive() {
                let normalizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedAlias.isEmpty else { continue }
                entries.append(
                    Entry(
                        id: "alias-\(self.digest("\(normalizedAlias.lowercased())\u{0}\(normalizedText.lowercased())"))",
                        revision: 0,
                        updatedAt: "",
                        updatedByDeviceId: "",
                        deleted: false,
                        kind: "alias",
                        text: nil,
                        weight: word.weight.map { min(1000, max(0, Int($0.rounded()))) },
                        alias: normalizedAlias,
                        canonical: normalizedText,
                        from: nil,
                        to: nil,
                        setting: nil
                    )
                )
            }
        }

        for replacement in snapshot.replacements {
            for trigger in replacement.triggers.uniquedCaseInsensitive() {
                let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let normalizedReplacement = self.sanitizedReplacement(replacement.replacement)
                guard !normalizedTrigger.isEmpty, !normalizedReplacement.isEmpty else { continue }
                entries.append(
                    Entry(
                        id: "replacement-\(replacement.id.uuidString.lowercased())-\(self.digest(normalizedTrigger))",
                        revision: 0,
                        updatedAt: "",
                        updatedByDeviceId: "",
                        deleted: false,
                        kind: "replacement",
                        text: nil,
                        weight: nil,
                        alias: nil,
                        canonical: nil,
                        from: normalizedTrigger,
                        to: normalizedReplacement,
                        setting: nil
                    )
                )
            }
        }

        for profile in snapshot.pronunciationProfiles.prefix(256) {
            let enrollments = Array(profile.enrollments.prefix(10))
            guard profile.hiddenSize > 0,
                  profile.hiddenSize <= 4096,
                  !enrollments.isEmpty,
                  enrollments.allSatisfy({
                      $0.modelKey == profile.modelKey &&
                          $0.values.count == profile.hiddenSize &&
                          $0.sourceFrameCount > 0 &&
                          $0.values.allSatisfy(\.isFinite)
                  })
            else { continue }
            entries.append(
                Entry(
                    id: "pronunciation-\(profile.dictionaryEntryID.uuidString.lowercased())-\(self.digest(profile.modelKey))",
                    revision: 0,
                    updatedAt: "",
                    updatedByDeviceId: "",
                    deleted: false,
                    kind: "pronunciation",
                    text: nil,
                    weight: nil,
                    alias: nil,
                    canonical: nil,
                    from: nil,
                    to: nil,
                    setting: nil,
                    dictionaryEntryId: profile.dictionaryEntryID.uuidString.lowercased(),
                    label: profile.label,
                    modelKey: profile.modelKey,
                    hiddenSize: profile.hiddenSize,
                    enrollments: enrollments
                )
            )
        }

        entries.append(
            Entry(
                id: "preference-punctuation",
                revision: 0,
                updatedAt: "",
                updatedByDeviceId: "",
                deleted: false,
                kind: "preference",
                text: nil,
                weight: nil,
                alias: nil,
                canonical: nil,
                from: nil,
                to: nil,
                setting: .init(key: "punctuation", boolValue: snapshot.punctuationEnabled)
            )
        )
        return entries
    }

    private static func isLocallyManaged(_ entry: Entry) -> Bool {
        if entry.kind != "preference" { return true }
        return entry.setting?.key == "punctuation"
    }

    private static func payloadSignature(_ entry: Entry) -> String {
        [
            entry.kind,
            entry.text ?? "",
            entry.weight.map(String.init) ?? "",
            entry.alias ?? "",
            entry.canonical ?? "",
            entry.from ?? "",
            entry.to ?? "",
            entry.setting?.key ?? "",
            entry.setting?.boolValue.map(String.init) ?? "",
            entry.setting?.stringValue ?? "",
            entry.dictionaryEntryId ?? "",
            entry.label ?? "",
            entry.modelKey ?? "",
            entry.hiddenSize.map(String.init) ?? "",
            self.pronunciationDigest(entry.enrollments ?? []),
        ].joined(separator: "\u{1f}")
    }

    private static func pronunciationDigest(
        _ enrollments: [SayStoneSpeechProfileDocument.Entry.PronunciationEnrollment]
    ) -> String {
        var data = Data()
        for enrollment in enrollments {
            data.append(contentsOf: enrollment.modelKey.utf8)
            data.append(0)
            withUnsafeBytes(of: enrollment.sourceFrameCount.bigEndian) { data.append(contentsOf: $0) }
            for value in enrollment.values {
                withUnsafeBytes(of: value.bitPattern.bigEndian) { data.append(contentsOf: $0) }
            }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitizedReplacement(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private static func replacementUUID(entryID: String) -> UUID? {
        let prefix = "replacement-"
        guard entryID.hasPrefix(prefix) else { return self.deterministicUUID(entryID) }
        let start = entryID.index(entryID.startIndex, offsetBy: prefix.count)
        let tail = entryID[start...]
        let candidate = String(tail.prefix(36))
        return UUID(uuidString: candidate) ?? self.deterministicUUID(entryID)
    }

    private static func deterministicUUID(_ value: String) -> UUID? {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        guard bytes.count == 16 else { return nil }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension Array where Element == String {
    nonisolated func uniquedCaseInsensitive() -> [String] {
        var seen: Set<String> = []
        return self.filter { seen.insert($0.lowercased()).inserted }
    }
}
