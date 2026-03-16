import SwiftUI

struct TranscriptView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.transcript) { entry in
                        TranscriptBubble(entry: entry)
                            .id(entry.id)
                    }

                    if !appState.partialText.isEmpty {
                        Text(appState.partialText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .textSelection(.enabled)
                            .id("partial")
                    }

                    // Thinking block (verbose mode)
                    if appState.showThinking && !appState.lastThinking.isEmpty {
                        DisclosureGroup("Thinking") {
                            Text(appState.lastThinking)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .id("thinking")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: appState.transcript.count) {
                if let last = appState.transcript.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct TranscriptBubble: View {
    let entry: TranscriptEntry
    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .top) {
            if entry.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: entry.role == .user ? .trailing : .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 4) {
                    if entry.role == .user {
                        copyButton
                    }

                    if entry.role == .model {
                        Text(LocalizedStringKey(entry.text))
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.15))
                            )
                    } else {
                        Text(entry.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.2))
                            )
                    }

                    if entry.role == .model {
                        copyButton
                    }
                }

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if entry.role == .model || entry.role == .system {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 8)
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                showCopied = false
            }
        } label: {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundColor(showCopied ? .green : .gray)
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
        .padding(.top, 8)
    }
}
