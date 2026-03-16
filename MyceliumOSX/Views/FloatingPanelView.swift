import SwiftUI

struct FloatingPanelView: View {
    @Environment(AppState.self) private var appState

    @State private var showSidebar = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HStack(spacing: 0) {
                if showSidebar {
                    ChannelListView()
                        .frame(width: 130)
                    Divider()
                }

                VStack(spacing: 0) {
                    TranscriptView()
                    Divider()
                    inputBar
                }
            }
        }
        .frame(minWidth: 320, minHeight: 400)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Sidebar toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(showSidebar ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .tooltip("Toggle channels sidebar")

            Circle()
                .fill(appState.mountedRingName != nil ? .green : .red)
                .frame(width: 8, height: 8)

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
                if appState.isRecording {
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

            // Verbose/thinking toggle
            Button {
                appState.showThinking.toggle()
            } label: {
                Image(systemName: appState.showThinking ? "brain.fill" : "brain")
                    .foregroundStyle(appState.showThinking ? .purple : .secondary)
            }
            .buttonStyle(.plain)
            .tooltip(appState.showThinking ? "Hide thinking" : "Show thinking (verbose)")

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
        VStack(spacing: 6) {
            // Voice mode indicator (large, pulsing when active)
            if appState.mode == .voice {
                VoiceModeIndicator()
            }

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
                .tooltip(appState.mode == .voice ? "Switch to text mode" : "Switch to voice mode")

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
                .tooltip("Remember the last exchange")
            }
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

struct VoiceModeIndicator: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            // Push-to-talk button
            Button {
                // No-op: use press/release gestures
            } label: {
                HStack(spacing: 6) {
                    // Audio level bars (visible while recording)
                    if appState.isRecording {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 3, height: barHeight(index: i))
                                .animation(.easeInOut(duration: 0.1), value: appState.voiceSession.audioLevel)
                        }
                    }

                    Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                        .font(.title2)
                    Text(appState.isRecording ? "Recording..." : "Hold to talk")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appState.isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !appState.isRecording {
                            appState.startPushToTalk()
                        }
                    }
                    .onEnded { _ in
                        appState.stopPushToTalk()
                    }
            )

            if appState.isSpeaking {
                Button {
                    if appState.useLocalModel {
                        appState.localVoiceSession?.interrupt()
                    } else {
                        appState.voiceSession.bargeIn()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                        Text("Stop")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Spacer()

            Button("End") {
                appState.stopVoiceMode()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
    }

    private func barHeight(index: Int) -> CGFloat {
        let level = CGFloat(appState.voiceSession.audioLevel)
        let base: CGFloat = 4
        let maxHeight: CGFloat = 20
        let threshold = CGFloat(index) * 0.15
        let active = max(level - threshold, 0) / (1.0 - threshold)
        return base + active * (maxHeight - base)
    }
}

struct TextInputField: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Type a message...", text: $inputText)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .disabled(appState.isProcessing)
            .onSubmit {
                guard !inputText.isEmpty, !appState.isProcessing else { return }
                appState.sendTextMessage(inputText)
                inputText = ""
                // Re-focus after send
                isFocused = true
            }
            .onAppear { isFocused = true }
            .onChange(of: appState.isProcessing) {
                // Re-focus when processing completes
                if !appState.isProcessing {
                    isFocused = true
                }
            }
    }
}
