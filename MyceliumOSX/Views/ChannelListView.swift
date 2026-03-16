import SwiftUI

struct ChannelListView: View {
    @Environment(AppState.self) private var appState
    @State private var isAddingChannel = false
    @State private var newChannelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Channels")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    isAddingChannel = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Channel list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.channels) { channel in
                        ChannelRow(
                            channel: channel,
                            isActive: appState.activeChannel?.name == channel.name
                        )
                        .onTapGesture {
                            appState.switchChannel(to: channel)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.gray.opacity(0.05))
        .sheet(isPresented: $isAddingChannel) {
            VStack(spacing: 12) {
                Text("New Channel")
                    .font(.headline)

                TextField("Channel name", text: $newChannelName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        isAddingChannel = false
                        newChannelName = ""
                    }
                    Spacer()
                    Button("Create") {
                        let name = newChannelName
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }

                        guard !name.isEmpty else { return }
                        appState.createChannel(name: name)
                        isAddingChannel = false
                        newChannelName = ""
                    }
                    .disabled(newChannelName.isEmpty)
                }
            }
            .padding()
            .frame(width: 250)
        }
    }
}

struct ChannelRow: View {
    let channel: Channel
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("#")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(channel.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
