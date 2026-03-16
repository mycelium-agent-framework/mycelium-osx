import Foundation

/// Manages Ring 0 operations: loading manifest, SOUL.md, and git operations.
final class RingManager: Sendable {
    let ring0Path: URL

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(ring0Path: URL) {
        self.ring0Path = ring0Path
    }

    func loadManifest() -> Manifest? {
        let url = ring0Path.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            print("[RingManager] Could not read manifest.json at \(url.path)")
            return nil
        }
        return try? Self.decoder.decode(Manifest.self, from: data)
    }

    func loadSOUL() -> String? {
        let url = ring0Path.appendingPathComponent("SOUL.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Load SOUL.md from a content ring (not Ring 0).
    func loadSOUL(ringPath: URL) -> String? {
        let url = ringPath.appendingPathComponent("SOUL.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Check if a PoP has access to a specific ring.
    func canAccess(ring: String, pop: String) -> Bool {
        guard let manifest = loadManifest(),
              let popEntry = manifest.pops.first(where: { $0.deviceId == pop })
        else { return false }
        return popEntry.allowedRings.contains(ring)
    }

    /// Git pull on a ring repo.
    func gitPull(ringPath: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", ringPath.path, "pull", "--rebase"]
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Git commit and push on a ring repo.
    func gitCommitAndPush(ringPath: URL, message: String) async -> Bool {
        // Stage all changes
        let addOk = await runGit(args: ["-C", ringPath.path, "add", "-A"])
        guard addOk else { return false }

        // Commit
        let commitOk = await runGit(args: ["-C", ringPath.path, "commit", "-m", message])
        guard commitOk else { return true } // No changes to commit is fine

        // Push
        return await runGit(args: ["-C", ringPath.path, "push"])
    }

    private func runGit(args: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
