import Foundation

/// Claude backend via the Claude Code CLI (`claude -p`).
/// Uses your existing Claude subscription — no separate API key needed.
/// Maintains conversation context via session resume.
final class ClaudeCliClient: Sendable {
    let model: String
    let systemPrompt: String
    private let claudePath: String

    /// Session ID for multi-turn continuity. Set after first response.
    private(set) var currentSessionId: String?

    struct ParsedResponse {
        let text: String
        let sessionId: String
        let isError: Bool
        let durationMs: Int
        let costUsd: Double
    }

    init(model: String = "haiku", systemPrompt: String, claudePath: String? = nil) {
        self.model = model
        self.systemPrompt = systemPrompt

        if let claudePath, FileManager.default.fileExists(atPath: claudePath) {
            self.claudePath = claudePath
        } else {
            let paths = [
                "\(NSHomeDirectory())/.local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "\(NSHomeDirectory())/.claude/local/claude",
            ]
            self.claudePath = paths.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/local/bin/claude"
        }
    }

    // MARK: - Send

    func send(_ prompt: String) async throws -> String {
        let args = buildArguments(prompt: prompt, sessionId: currentSessionId)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = Pipe() // Provide stdin with the prompt via pipe

        // Write prompt to stdin
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        let promptData = Data(prompt.utf8)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                do {
                    let parsed = try Self.parseResponse(output)
                    // Thread-safe update via a callback pattern
                    // (currentSessionId will be set on the calling actor)
                    continuation.resume(returning: parsed.text + "\n__SESSION__:\(parsed.sessionId)")
                } catch {
                    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                    if !stderrStr.isEmpty {
                        print("[ClaudeCli] stderr: \(stderrStr.prefix(200))")
                    }
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
                stdinPipe.fileHandleForWriting.write(promptData)
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: ClaudeError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Convenience that extracts session ID from the response.
    func sendAndUpdateSession(_ prompt: String) async throws -> String {
        let raw = try await send(prompt)
        if let range = raw.range(of: "\n__SESSION__:") {
            let sessionId = String(raw[range.upperBound...])
            // Can't mutate self in Sendable, so caller handles this
            return String(raw[..<range.lowerBound])
        }
        return raw
    }

    // MARK: - Availability

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: claudePath)
    }

    // MARK: - Argument Building (internal for testing)

    func buildArguments(prompt: String, sessionId: String?) -> [String] {
        var args = ["-p", "--output-format", "json", "--model", model]

        if !systemPrompt.isEmpty {
            args += ["--append-system-prompt", systemPrompt]
        }

        if let sessionId {
            args += ["--resume", sessionId]
        }

        return args
    }

    // MARK: - Response Parsing (internal for testing)

    static func parseResponse(_ output: String) throws -> ParsedResponse {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ClaudeError.parseError(output.prefix(100).description)
        }

        let text = json["result"] as? String ?? ""
        let sessionId = json["session_id"] as? String ?? ""
        let isError = json["is_error"] as? Bool ?? false
        let durationMs = json["duration_ms"] as? Int ?? 0
        let costUsd = json["total_cost_usd"] as? Double ?? 0

        return ParsedResponse(
            text: text,
            sessionId: sessionId,
            isError: isError,
            durationMs: durationMs,
            costUsd: costUsd
        )
    }

    enum ClaudeError: Error, LocalizedError {
        case launchFailed(String)
        case parseError(String)
        case cliError(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let msg): return "Failed to launch claude: \(msg)"
            case .parseError(let output): return "Could not parse claude output: \(output)"
            case .cliError(let msg): return "Claude error: \(msg)"
            }
        }
    }
}
