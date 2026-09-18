import Foundation

/// Reads the running engine identity from real runtime state.
///
/// Build metadata comes from the signed app Info.plist. The model digest is
/// recomputed from the installed FluidAudio artifact before the identity is
/// accepted, so copying a different model beside a signed app cannot produce a
/// false same-engine claim.
enum EngineIdentityReader {
    // The installed model is immutable for one app process. Hash it once so a
    // phone session does not pay to read the 443 MB artifact on every start.
    private static let installedV2ModelDigest: String? = {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v2-coreml", isDirectory: true)
        return EngineModelDigest.sha256Tree(at: directory)
    }()

    static func current() -> EngineIdentity {
        let model = SettingsStore.shared.selectedSpeechModel
        let info = Bundle.main.infoDictionary
        let buildVersion = info?["CFBundleShortVersionString"] as? String
        let buildNumber = info?["CFBundleVersion"] as? String
        let saystoneBuild: String? = {
            switch (buildVersion, buildNumber) {
            case let (version?, number?): return "\(version) (\(number))"
            case let (version?, nil): return version
            case let (nil, number?): return number
            case (nil, nil): return nil
            }
        }()

        let modelVersion: String?
        switch model {
        case .parakeetTDT: modelVersion = "v3"
        case .parakeetTDTv2: modelVersion = "v2"
        default: modelVersion = nil
        }

        guard let modelVersion else {
            return EngineIdentity.unknown(saystoneBuild: saystoneBuild)
        }

        let selectedModelKey = "parakeet-\(modelVersion)"
        let manifestModelKey = self.string(info, key: "SayStoneEngineModelKey")
        let manifestPipelineRevision = self.string(info, key: "SayStoneEnginePipelineRevision")
        let expectedDigest = self.string(info, key: "SayStoneEngineModelSha256")
        let installedDigest = self.installedModelDigest(modelVersion: modelVersion)

        guard manifestModelKey == selectedModelKey,
              manifestPipelineRevision == EngineIdentity.pipelineRevision,
              let expectedDigest,
              expectedDigest == installedDigest
        else {
            return EngineIdentity.resolved(modelKey: selectedModelKey, saystoneBuild: saystoneBuild)
        }

        return EngineIdentity.resolved(
            modelKey: selectedModelKey,
            saystoneBuild: saystoneBuild,
            modelRevision: self.string(info, key: "SayStoneEngineModelRevision"),
            modelSha256: expectedDigest,
            runtimeCommit: self.string(info, key: "SayStoneEngineRuntimeCommit"),
            profileSchemaRevision: self.integer(info, key: "SayStoneEngineProfileSchemaRevision")
        )
    }

    private static func string(_ info: [String: Any]?, key: String) -> String? {
        guard let value = info?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func integer(_ info: [String: Any]?, key: String) -> Int? {
        if let number = info?[key] as? NSNumber { return number.intValue }
        guard let value = self.string(info, key: key) else { return nil }
        return Int(value)
    }

    private static func installedModelDigest(modelVersion: String) -> String? {
        guard modelVersion == "v2" else { return nil }
        return self.installedV2ModelDigest
    }
}
