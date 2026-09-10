import SwiftUI
import Combine

struct MAISpeechSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var resource = MAITranscriptionProvider.resource
    @State private var key = ""
    @State private var message = ""
    var body: some View {
        DisclosureGroup("MAI-Transcribe-2 · Azure setup") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Optional cloud transcription. Selecting this model sends recorded audio to your Microsoft Azure Speech resource and incurs Azure usage charges.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Azure Speech resource name", text: $resource)
                SecureField(KeychainService.shared.containsKey(for: MAITranscriptionProvider.keyID) ? "Key saved · enter to replace" : "Azure Speech API key", text: $key)
                Button("Save Azure configuration") {
                    do {
                        _ = try MAITranscriptionRequest.endpoint(resource: resource)
                        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try KeychainService.shared.storeKey(key, for: MAITranscriptionProvider.keyID)
                        }
                        guard KeychainService.shared.containsKey(for: MAITranscriptionProvider.keyID) else {
                            throw MAITranscriptionRequest.failure("Enter your Azure Speech key.")
                        }
                        UserDefaults.standard.set(resource.trimmingCharacters(in: .whitespacesAndNewlines), forKey: MAITranscriptionProvider.resourceDefaultsKey)
                        key = ""
                        settings.objectWillChange.send()
                        message = "Saved. Activate MAI-Transcribe-2 in the model list when you want cloud transcription."
                    } catch { message = error.localizedDescription }
                }
                if !message.isEmpty { Text(message).font(.caption) }
                Link("Azure Speech setup guide", destination: URL(string: "https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe")!)
                    .font(.caption)
            }.textFieldStyle(.roundedBorder).padding(.top, 8)
        }.padding(.vertical, 8)
    }
}
