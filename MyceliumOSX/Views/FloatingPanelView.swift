import SwiftUI

struct FloatingPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                ChannelListView()
                    .frame(minWidth: 100, maxWidth: 140)

                VStack(spacing: 0) {
                    TranscriptView()
                    Divider()
                    inputBar
                }
            }
        }
        .frame(minWidth: 380, minHeight: 400)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Circle()
                .fill(appState.mode == .voice && appState.isConnected ? .green :
                      appState.mountedRingName != nil ? .yellow : .red)
                .frame(width: 8, height: 8)

            // Ring switcher dropdown
            RingSwitcher()

            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if appState.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            if appState.mode == .voice {
                if appState.isListening {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                }
                if appState.isSpeaking {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.blue)
                        .symbolEffect(.variableColor)
                }
            }

            Button {
                appState.isPanelVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Voice mode toggle
            Button {
                appState.toggleVoiceMode()
            } label: {
                Image(systemName: appState.mode == .voice ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title3)
                    .foregroundStyle(appState.mode == .voice ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(appState.mode == .voice ? "Switch to text mode" : "Switch to voice mode")

            // Text input (always available)
            TextInputField()

            // Remember button
            Button {
                promoteToSpore()
            } label: {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Remember the last exchange")
        }
        .padding(10)
    }

    private func promoteToSpore() {
        guard let store = appState.sporeStore,
              let lastModel = appState.transcript.last(where: { $0.role == .model })
        else { return }

        let lastUser = appState.transcript.last(where: { $0.role == .user })
        let content = [lastUser?.text, lastModel.text]
            .compactMap { $0 }
            .joined(separator: "\n---\n")

        let spore = Spore(
            type: .note,
            channel: appState.activeChannel?.name ?? "general",
            content: content,
            originPop: appState.deviceId
        )
        store.append(spore: spore)
    }
}

struct RingSwitcher: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            if let manifest = appState.manifest {
                let allowedRings = manifest.pops
                    .first(where: { $0.deviceId == appState.deviceId })?
                    .allowedRings ?? []

                ForEach(manifest.rings.filter({ allowedRings.contains($0.name) }), id: \.name) { ring in
                    Button {
                        appState.switchToRing(named: ring.name)
                    } label: {
                        HStack {
                            Text(ring.name)
                            if ring.name == appState.mountedRingName {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.hexagonpath")
                    .font(.caption2)
                Text(appState.mountedRingName ?? "No Ring")
                    .font(.caption)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct TextInputField: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    var body: some View {
        TextField("Type a message...", text: $inputText)
            .textFieldStyle(.roundedBorder)
            .disabled(appState.isProcessing)
            .onSubmit {
                guard !inputText.isEmpty, !appState.isProcessing else { return }
                appState.sendTextMessage(inputText)
                inputText = ""
            }
    }
}
