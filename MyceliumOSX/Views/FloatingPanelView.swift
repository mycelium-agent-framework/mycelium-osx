import SwiftUI

struct FloatingPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider()

            // Main content
            HSplitView {
                // Channel sidebar
                ChannelListView()
                    .frame(minWidth: 100, maxWidth: 140)

                // Transcript area
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
                .fill(appState.isConnected ? .green : .red)
                .frame(width: 8, height: 8)

            Text(appState.mountedRingName ?? "No Ring")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

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
            // Mic toggle
            Button {
                appState.isListening.toggle()
            } label: {
                Image(systemName: appState.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.title3)
                    .foregroundStyle(appState.isListening ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(appState.isListening ? "Stop listening" : "Start listening")

            // Text input (fallback when mic is off)
            if !appState.isListening {
                TextInputField()
            } else {
                Text("Listening...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

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
            channel: appState.activeChannel?.name ?? "default",
            content: content,
            originPop: appState.deviceId
        )
        store.append(spore: spore)
    }
}

struct TextInputField: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    var body: some View {
        TextField("Type a message...", text: $inputText)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                guard !inputText.isEmpty else { return }
                let entry = TranscriptEntry(
                    role: .user,
                    text: inputText,
                    originPop: appState.deviceId
                )
                appState.transcript.append(entry)
                if let store = appState.transcriptStore,
                   let channel = appState.activeChannel {
                    store.append(entry: entry, channel: channel.name)
                }
                // TODO: Send to Gemini client
                inputText = ""
            }
    }
}
