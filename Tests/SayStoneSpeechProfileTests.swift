import Foundation

@main
struct SayStoneSpeechProfileTests {
    static func main() throws {
        let replacementID = UUID(uuidString: "CB3A3497-3F89-4D62-8B04-1E61D24B3A70")!
        let snapshot = SayStoneSpeechProfileLocalSnapshot(
            words: [.init(text: "Oikonomos", weight: 10, aliases: ["economos"])],
            replacements: [.init(id: replacementID, triggers: ["say stone"], replacement: "SayStone")],
            punctuationEnabled: true
        )
        let empty = SayStoneSpeechProfileDocument.empty(updatedAt: "2026-09-18T10:00:00Z")
        let created = SayStoneSpeechProfileReconciler.reconcile(
            snapshot: snapshot,
            cached: empty,
            deviceID: "macbook",
            now: "2026-09-18T10:01:00Z"
        )
        precondition(created.changed)
        precondition(created.document.entries.allSatisfy { $0.revision == 1 && !$0.deleted })
        precondition(created.document.entries.map(\.kind).sorted() == ["alias", "preference", "replacement", "word"])

        let unchanged = SayStoneSpeechProfileReconciler.reconcile(
            snapshot: snapshot,
            cached: created.document,
            deviceID: "macbook",
            now: "2026-09-18T10:02:00Z"
        )
        precondition(!unchanged.changed)
        precondition(unchanged.document == created.document)

        let restored = SayStoneSpeechProfileReconciler.localSnapshot(from: created.document)
        precondition(restored == snapshot)

        let deleted = SayStoneSpeechProfileReconciler.reconcile(
            snapshot: .init(words: [], replacements: [], punctuationEnabled: true),
            cached: created.document,
            deviceID: "mini",
            now: "2026-09-18T10:03:00Z"
        )
        let deletedKinds = deleted.document.entries.filter { $0.deleted }.map(\.kind).sorted()
        precondition(deletedKinds == ["alias", "replacement", "word"])
        precondition(deleted.document.entries.filter { $0.deleted }.allSatisfy { $0.revision == 2 })
        precondition(deleted.document.entries.first { $0.kind == "preference" }?.deleted == false)

        let data = try JSONEncoder().encode(created.document)
        let decoded = try JSONDecoder().decode(SayStoneSpeechProfileDocument.self, from: data)
        precondition(decoded == created.document)
        print("SayStone speech profile tests passed")
    }
}
