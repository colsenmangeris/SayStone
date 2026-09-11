import SwiftUI

/// Compatibility capture follows the macOS duplex route. Selection here is
/// deliberately a system selection, rather than an unsupported AUHAL rebind.
struct SystemMicrophonePicker: View {
    @State private var devices: [AudioDevice.Device] = []
    @State private var selectedUID = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Microphone · Follow macOS").font(.headline)
            Picker("System microphone", selection: Binding(
                get: { selectedUID },
                set: { uid in
                    if AudioDevice.setDefaultInputDevice(uid: uid) {
                        selectedUID = uid
                        message = ""
                    } else {
                        message = "Could not change the system microphone."
                    }
                    refresh()
                }
            )) {
                if !devices.contains(where: { $0.uid == selectedUID }) {
                    Text("No system microphone available").tag(selectedUID)
                }
                ForEach(devices) { device in Text(device.name).tag(device.uid) }
            }
            Text("SayStone follows the macOS input. Choosing a microphone here also changes the macOS input for other apps.")
                .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 8)
        .task {
            while !Task.isCancelled {
                refresh()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { break }
            }
        }
    }
    private func refresh() {
        devices = AudioDevice.listInputDevices()
        selectedUID = AudioDevice.getDefaultInputDevice()?.uid ?? ""
    }
}
