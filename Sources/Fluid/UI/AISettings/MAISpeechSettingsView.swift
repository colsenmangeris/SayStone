import SwiftUI
import Combine

struct MAISpeechSettingsView: View {
    @ObservedObject var settings: SettingsStore
    var activate: () -> Void
    var actionsBlocked: Bool
    @State private var resource = MAITranscriptionProvider.resource
    @State private var route = MAITranscriptionProvider.route
    @State private var style = MAITranscriptionProvider.style
    @State private var key = ""
    @State private var message = ""
    @State private var expanded = true
    var body: some View {
        DisclosureGroup("MAI-Transcribe-2 · Connection", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud transcription sends recorded audio to the selected service and incurs usage charges.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Connection", selection: $route) {
                    Text("OpenRouter").tag(MAITranscriptionProvider.Route.openRouter)
                    Text("Azure").tag(MAITranscriptionProvider.Route.azure)
                }
                .onChange(of: route) { _, _ in key = ""; message = "" }
                if route == .azure {
                    TextField("Azure Speech resource name", text: $resource)
                }
                Picker("Transcription style", selection: $style) {
                    Text("Verbatim").tag(MAITranscriptionRequest.Style.verbatim)
                    Text("Clean").tag(MAITranscriptionRequest.Style.clean)
                }
                Text("Verbatim preserves fillers and false starts. Clean removes fillers and formats speech for readability.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField(KeychainService.shared.containsKey(for: MAITranscriptionProvider.keyID(for: route)) ? "Key saved · enter to replace" : "API key", text: $key)
                Button("Save MAI configuration") {
                    do {
                        if route == .azure { _ = try MAITranscriptionRequest.endpoint(resource: resource) }
                        let id = MAITranscriptionProvider.keyID(for: route)
                        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try KeychainService.shared.storeKey(key, for: id)
                        }
                        guard KeychainService.shared.containsKey(for: id) else {
                            throw MAITranscriptionRequest.failure("Enter your API key.")
                        }
                        UserDefaults.standard.set(resource.trimmingCharacters(in: .whitespacesAndNewlines), forKey: MAITranscriptionProvider.resourceDefaultsKey)
                        UserDefaults.standard.set(route.rawValue, forKey: "SayStoneMAIRoute")
                        UserDefaults.standard.set(style.rawValue, forKey: "SayStoneMAIStyle")
                        key = ""
                        settings.objectWillChange.send()
                        message = "Saved in Keychain. Connection not yet tested. Your active model has not changed."
                    } catch { message = error.localizedDescription }
                }
                Text("Selected voice engine: \(settings.selectedSpeechModel.displayName)")
                    .font(.caption.bold())
                if settings.selectedSpeechModel != .maiTranscribe2 {
                    Button("Activate MAI-Transcribe-2", action: activate)
                        .disabled(!MAITranscriptionProvider.isConfigured || actionsBlocked)
                }
                Text("This connection is for speech recognition. OpenRouter in AI Providers configures text cleanup separately.")
                    .font(.caption).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message).font(.caption) }
            }.textFieldStyle(.roundedBorder).padding(.top, 8)
        }.padding(.vertical, 8)
    }
}
