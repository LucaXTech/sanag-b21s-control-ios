import SwiftUI

/// Only displays models whose BLE commands are documented by an external
/// interoperability project; this is not a list of all nearby Bluetooth devices.
struct CommunityHeadsetView: View {
    @StateObject private var manager = CommunityHeadsetManager()
    @State private var showExperimentalConfirmation = false
    @State private var controlsConfirmed = false

    var body: some View {
        Form {
            Section {
                Text("Community-supported protocols")
                    .font(.headline)
                Text("TOZO T10 and Marshall Motif II ANC have published BLE command documentation. Their controls are NOT yet hardware-tested in this iOS app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(manager.status)
                    .font(.subheadline)
                HStack {
                    Button(manager.scanning ? "Stop scan" : "Find compatible headphones") {
                        if manager.scanning { manager.stopScan() }
                        else { manager.scan() }
                    }
                    Spacer()
                    if manager.scanning { ProgressView() }
                }
            } header: {
                Text("Discover headphones")
            } footer: {
                Text("Only recognized headset models are shown. This screen does not list TVs, printers, watches or arbitrary Bluetooth devices. Headphones without a compatible BLE control channel will not appear.")
            }

            Section("Recognized devices") {
                if manager.candidates.isEmpty {
                    Text("No supported models found. Turn on your headphones or try pairing mode.")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.candidates) { candidate in
                    Button {
                        controlsConfirmed = false
                        manager.connect(candidate)
                    } label: {
                        HStack {
                            Image(systemName: "headphones")
                            Text(candidate.profile.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(candidate.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let model = manager.selectedModel {
                Section("Selected headphones") {
                    Text(model.rawValue)
                    Link("Protocol research and credits",
                         destination: URL(string: model.supportingSource)!)
                    if manager.ready {
                        if !controlsConfirmed {
                            Button("Enable experimental controls") {
                                showExperimentalConfirmation = true
                            }
                        } else if model == .tozoT10 {
                            if let battery = manager.battery {
                                LabeledContent("Battery", value: battery)
                            }
                            Button("Read battery") { manager.requestBattery() }
                            Button("Game Mode: On") { manager.setGameMode(true) }
                            Button("Game Mode: Off") { manager.setGameMode(false) }
                            Text("EQ packets are implemented but remain unavailable until the current 10-band values and Q factors can be checked on real TOZO hardware.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if model == .marshallMotifII {
                            Button("ANC On") { manager.setANC(.noiseCancellation) }
                            Button("ANC Off") { manager.setANC(.off) }
                            Button("Transparency") { manager.setANC(.transparency) }
                            ForEach(MarshallMotifIICommands.EQ.allCases, id: \.rawValue) { preset in
                                Button("EQ: \(String(describing: preset).capitalized)") {
                                    manager.setMarshallEQ(preset)
                                }
                            }
                        }
                    }
                    Button("Disconnect", role: .destructive) {
                        controlsConfirmed = false
                        manager.disconnect()
                    }
                }
            }

            Section("Unsupported headphones") {
                Text("Have another brand? Inspect its BLE services safely and request support.")
                    .font(.subheadline)
                NavigationLink {
                    UnsupportedHeadsetView()
                } label: {
                    Label("Find my model · Request support", systemImage: "plus.circle")
                }
            }

            Section {
                Text("Does your model use a different protocol? Submit a model-specific compatibility report. Please do not publish serial numbers, Bluetooth identifiers or personal logs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Contribute a headphone model",
                     destination: URL(string: "https://github.com/LucaXTech/sanag-b21s-control-ios/issues/new/choose")!)
            }
        }
        .navigationTitle("Other headphones")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Experimental BLE commands", isPresented: $showExperimentalConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("I understand — enable") { controlsConfirmed = true }
        } message: {
            Text("These commands are documented by independent projects, but not validated on physical headphones in this iOS app. Use only with the displayed model you own. No firmware updates or arbitrary commands are available.")
        }
        .onDisappear { manager.disconnect() }
    }
}
