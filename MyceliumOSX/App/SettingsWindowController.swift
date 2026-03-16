import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appState: AppState) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(onSave: { [weak self] in
            self?.window?.close()
            appState.reloadConfiguration()
        })
        .environment(appState)

        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mycelium Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("ring0Path") private var ring0PathString: String = ""

    var onSave: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Ring 0 (vivian-core)") {
                    HStack {
                        TextField("Path to vivian-core repo", text: $ring0PathString)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseForDirectory("Select the vivian-core repository") { url in
                                ring0PathString = url.path
                            }
                        }
                    }

                    if !ring0PathString.isEmpty {
                        let valid = isValidRing0(ring0PathString)
                        HStack(spacing: 4) {
                            Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(valid ? .green : .red)
                            Text(valid ? "SOUL.md and manifest.json found" : "Missing SOUL.md or manifest.json")
                                .font(.caption)
                                .foregroundColor(valid ? .secondary : .red)
                        }
                    }
                }

                if isValidRing0(ring0PathString) {
                    RingPathsSection(ring0Path: ring0PathString)

                    Section("API Keys (per ring, stored in Keychain)") {
                        ApiKeyListView(ring0Path: ring0PathString)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Save & Connect") {
                    onSave?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ring0PathString.isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 600)
    }

    private func isValidRing0(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let expanded = NSString(string: path).expandingTildeInPath
        let fm = FileManager.default
        return fm.fileExists(atPath: expanded + "/SOUL.md")
            && fm.fileExists(atPath: expanded + "/manifest.json")
    }
}

// MARK: - Ring Paths

/// Shows each ring from the manifest with a user-configurable local path.
/// Paths are stored in UserDefaults as "ringPath.<ringName>".
struct RingPathsSection: View {
    let ring0Path: String
    @State private var rings: [RingInfo] = []

    struct RingInfo: Identifiable {
        let name: String
        let hint: String?
        var id: String { name }
    }

    var body: some View {
        Section("Ring Paths") {
            ForEach(rings) { ring in
                RingPathRow(ring: ring)
            }

            if rings.isEmpty {
                Text("No rings found in manifest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadRings() }
        .onChange(of: ring0Path) { loadRings() }
    }

    private func loadRings() {
        let expanded = NSString(string: ring0Path).expandingTildeInPath
        let manifestURL = URL(fileURLWithPath: expanded).appendingPathComponent("manifest.json")

        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            rings = []
            return
        }

        rings = manifest.rings.map { RingInfo(name: $0.name, hint: $0.localPathHint) }

        // Pre-populate from hints if no user config exists yet
        for ring in rings {
            let key = "ringPath.\(ring.name)"
            if UserDefaults.standard.string(forKey: key) == nil, let hint = ring.hint {
                UserDefaults.standard.set(NSString(string: hint).expandingTildeInPath, forKey: key)
            }
        }
    }
}

struct RingPathRow: View {
    let ring: RingPathsSection.RingInfo
    @State private var path: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ring.name)
                .font(.caption)
                .fontWeight(.semibold)

            HStack {
                TextField("Local path to \(ring.name)", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: path) {
                        UserDefaults.standard.set(path, forKey: "ringPath.\(ring.name)")
                    }
                Button("Browse...") {
                    browseForDirectory("Select the \(ring.name) repository") { url in
                        path = url.path
                    }
                }
            }

            if !path.isEmpty {
                let exists = FileManager.default.fileExists(atPath: path + "/SOUL.md")
                HStack(spacing: 4) {
                    Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(exists ? .green : .red)
                    Text(exists ? "Ring found" : "SOUL.md not found at this path")
                        .font(.caption2)
                        .foregroundColor(exists ? .secondary : .red)
                }
            }
        }
        .onAppear {
            path = UserDefaults.standard.string(forKey: "ringPath.\(ring.name)") ?? ""
        }
    }
}

// MARK: - API Keys

struct ApiKeyListView: View {
    let ring0Path: String
    @State private var keyRefs: [(ringName: String, ref: String, provider: String, model: String)] = []
    @State private var keyValues: [String: String] = [:]
    @State private var savedRefs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(keyRefs, id: \.ref) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.ringName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("(\(entry.provider)/\(entry.model))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        SecureField("API key for \(entry.ref)", text: binding(for: entry.ref))
                            .textFieldStyle(.roundedBorder)

                        if savedRefs.contains(entry.ref) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }

            if keyRefs.isEmpty {
                Text("No rings with backend config found in manifest.json")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadRefs() }
        .onChange(of: ring0Path) { loadRefs() }
    }

    private func binding(for ref: String) -> Binding<String> {
        Binding(
            get: { keyValues[ref] ?? "" },
            set: { newValue in
                keyValues[ref] = newValue
                if !newValue.isEmpty {
                    KeychainManager.save(key: newValue, forRef: ref)
                    savedRefs.insert(ref)
                }
            }
        )
    }

    private func loadRefs() {
        let expanded = NSString(string: ring0Path).expandingTildeInPath
        let manifestURL = URL(fileURLWithPath: expanded).appendingPathComponent("manifest.json")

        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            keyRefs = []
            return
        }

        var refs: [(String, String, String, String)] = []
        var values: [String: String] = [:]
        var saved: Set<String> = []

        for ring in manifest.rings {
            if let backend = ring.backend {
                refs.append((ring.name, backend.apiKeyRef, backend.provider, backend.model))
                if let existing = KeychainManager.get(ref: backend.apiKeyRef) {
                    values[backend.apiKeyRef] = existing
                    saved.insert(backend.apiKeyRef)
                }
            }
        }

        keyRefs = refs
        keyValues = values
        savedRefs = saved
    }
}

// MARK: - Shared

private func browseForDirectory(_ message: String, onSelect: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = message

    if panel.runModal() == .OK, let url = panel.url {
        onSelect(url)
    }
}
