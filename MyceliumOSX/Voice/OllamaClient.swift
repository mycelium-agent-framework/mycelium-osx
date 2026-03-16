import Foundation

/// Local LLM client via Ollama REST API.
/// Runs entirely on-device — no network, no API keys, sub-second responses.
final class OllamaClient: Sendable {
    let model: String
    let systemInstruction: String
    let baseURL: String

    struct Message: Sendable {
        let role: String   // "user", "assistant", "system"
        let content: String
    }

    struct ParsedResponse {
        let text: String
        let done: Bool
    }

    init(model: String = "gemma3:4b", systemInstruction: String, baseURL: String = "http://localhost:11434") {
        self.model = model
        self.systemInstruction = systemInstruction
        self.baseURL = baseURL
    }

    // MARK: - Send

    /// Send a prompt with conversation history and get a response.
    func send(prompt: String, history: [Message]) async throws -> String {
        let request = buildRequest(prompt: prompt, history: history)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.httpError(httpResponse.statusCode, body)
        }

        let parsed = try Self.parseResponse(data)
        return parsed.text
    }

    // MARK: - Availability

    /// Check if Ollama is running and the model is available.
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else { return false }

        // Check if our model is in the list
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return false }

        return models.contains { ($0["name"] as? String)?.hasPrefix(model.split(separator: ":").first.map(String.init) ?? model) == true }
    }

    // MARK: - Request Building (internal for testing)

    func buildRequest(prompt: String, history: [Message]) -> URLRequest {
        let endpoint = history.isEmpty ? "\(baseURL)/api/generate" : "\(baseURL)/api/chat"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if history.isEmpty {
            // Simple generate (no history)
            let body: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "system": systemInstruction,
                "stream": false,
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // Chat with history
            var messages: [[String: Any]] = [
                ["role": "system", "content": systemInstruction]
            ]
            for msg in history {
                messages.append(["role": msg.role, "content": msg.content])
            }
            messages.append(["role": "user", "content": prompt])

            let body: [String: Any] = [
                "model": model,
                "messages": messages,
                "stream": false,
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    // MARK: - Response Parsing (internal for testing)

    static func parseResponse(_ data: Data) throws -> ParsedResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError.parseError
        }

        if let error = json["error"] as? String {
            throw OllamaError.serverError(error)
        }

        // Generate API returns "response", Chat API returns "message.content"
        let text: String
        if let response = json["response"] as? String {
            text = response
        } else if let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String {
            text = content
        } else {
            text = ""
        }

        let done = json["done"] as? Bool ?? true
        return ParsedResponse(text: text, done: done)
    }

    // MARK: - History Helpers (static for testing)

    static func appendToHistory(_ history: inout [Message], role: String, content: String) {
        history.append(Message(role: role, content: content))
    }

    static func truncateHistory(_ history: inout [Message], maxTurns: Int = 20) {
        if history.count > maxTurns {
            history = Array(history.suffix(maxTurns))
        }
    }

    // MARK: - Errors

    enum OllamaError: Error, LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case parseError
        case serverError(String)
        case notAvailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from Ollama"
            case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(100))"
            case .parseError: return "Could not parse Ollama response"
            case .serverError(let msg): return "Ollama error: \(msg)"
            case .notAvailable: return "Ollama is not running"
            }
        }
    }
}
