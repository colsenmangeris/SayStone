import Foundation

/// Versioned identity of the speech engine that produced a transcription.
///
/// This is the source of truth for "same engine" checks. Fields that the
/// running process cannot observe are explicitly `nil`; no hash, revision, or
/// deployment-parity claim is ever synthesized. The running process fills in
/// what it really knows via ``resolved(...)``; callers that cannot identify the
/// engine use ``unknown(...)``.
struct EngineIdentity: Codable, Equatable, Sendable {
    /// Version of this identity document shape.
    static let schemaRevision = 1
    /// Engine identifier for the shared SayStone/Parakeet pipeline.
    static let sharedEngineID = "saystone-parakeet"
    /// Engine identifier used when the running engine cannot be identified.
    static let unknownEngineID = "unknown"
    /// Revision of the shared post-recognition pipeline in this build.
    static let pipelineRevision = SharedDictationPipeline.revision

    enum Readiness: String, Codable, Sendable {
        /// The running process reported the engine and model key it is using.
        case ready
        /// One or more identity fields are unavailable; do not claim parity.
        case unknown
    }

    let schemaRevision: Int
    let engineId: String
    let pipelineRevision: String
    let modelKey: String?
    let modelRevision: String?
    let modelSha256: String?
    let runtimeCommit: String?
    let saystoneBuild: String?
    let profileSchemaRevision: Int?

    /// `ready` only when the running process can prove every field required for
    /// a same-engine claim. Until the signed manifest and profile store land,
    /// the identity remains explicitly unknown.
    var readiness: Readiness {
        guard self.engineId == Self.sharedEngineID,
              self.modelKey != nil,
              self.modelRevision != nil,
              self.modelSha256 != nil,
              self.runtimeCommit != nil,
              self.saystoneBuild != nil,
              self.profileSchemaRevision != nil
        else { return .unknown }
        return .ready
    }

    /// Names of fields the running process could not observe. Stable ordering so
    /// readiness payloads and parity tests are deterministic.
    var unknownFieldNames: [String] {
        var fields: [String] = []
        if self.modelKey == nil { fields.append("modelKey") }
        if self.modelRevision == nil { fields.append("modelRevision") }
        if self.modelSha256 == nil { fields.append("modelSha256") }
        if self.runtimeCommit == nil { fields.append("runtimeCommit") }
        if self.saystoneBuild == nil { fields.append("saystoneBuild") }
        if self.profileSchemaRevision == nil { fields.append("profileSchemaRevision") }
        return fields
    }

    /// Builds an identity from values the running process observed. Omitted
    /// arguments stay `nil` rather than being guessed.
    static func resolved(
        modelKey: String?,
        saystoneBuild: String?,
        modelRevision: String? = nil,
        modelSha256: String? = nil,
        runtimeCommit: String? = nil,
        profileSchemaRevision: Int? = nil,
        engineId: String = EngineIdentity.sharedEngineID
    ) -> EngineIdentity {
        EngineIdentity(
            schemaRevision: Self.schemaRevision,
            engineId: engineId,
            pipelineRevision: Self.pipelineRevision,
            modelKey: modelKey,
            modelRevision: modelRevision,
            modelSha256: modelSha256,
            runtimeCommit: runtimeCommit,
            saystoneBuild: saystoneBuild,
            profileSchemaRevision: profileSchemaRevision
        )
    }

    /// Explicit unknown identity. Build metadata that is genuinely available can
    /// still be reported; nothing else is inferred.
    static func unknown(
        saystoneBuild: String? = nil
    ) -> EngineIdentity {
        EngineIdentity(
            schemaRevision: Self.schemaRevision,
            engineId: Self.unknownEngineID,
            pipelineRevision: Self.pipelineRevision,
            modelKey: nil,
            modelRevision: nil,
            modelSha256: nil,
            runtimeCommit: nil,
            saystoneBuild: saystoneBuild,
            profileSchemaRevision: nil
        )
    }
}
