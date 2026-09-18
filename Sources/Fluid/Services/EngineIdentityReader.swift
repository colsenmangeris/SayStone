import Foundation

/// Reads the running engine identity from real runtime state.
///
/// Only values the running process can actually observe are reported:
/// the selected Parakeet model and the app bundle version. Hashes, runtime
/// commits, and the profile schema revision come from signed manifests or the
/// (future) profile store, so they stay `nil` here rather than being invented.
enum EngineIdentityReader {
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

        return EngineIdentity.resolved(
            modelKey: "parakeet-\(modelVersion)",
            saystoneBuild: saystoneBuild
        )
    }
}
