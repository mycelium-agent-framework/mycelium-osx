import Foundation

/// Simple REST client for Gemini text generation (non-streaming).
/// Used for text chat mode — no WebSocket, no audio.
actor GeminiTextClient {
    private let apiKey: String
    private let model: String
    private let systemInstruction: String
    private var history: [[String: Any]] = []

    init(apiKey: String, model: String = "gemini-2.5-flash", systemInstruction: String) {
        self.apiKey = apiKey
        self.model = model
        self.systemInstruction = systemInstruction
    }

    struct Response {
        let text: String
        let toolCalls: [(id: String, name: String, args: [String: Any])]
    }

    /// Send a text message and get a response.
    func send(_ text: String) async throws -> Response {
        // Add user turn to history
        history.append([
            "role": "user",
            "parts": [["text": text]]
        ])

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var body: [String: Any] = [
            "contents": history,
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ],
            "generationConfig": [
                "thinkingConfig": [
                    "thinkingBudget": 1024  // Limit thinking tokens to reduce latency
                ]
            ],
        ]

        // Keep history manageable (last 20 turns)
        if history.count > 20 {
            history = Array(history.suffix(20))
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let resp = httpResponse as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard resp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[GeminiText] HTTP \(resp.statusCode): \(body.prefix(300))")
            throw GeminiError.httpError(resp.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw GeminiError.parseError
        }

        var responseText = ""
        var toolCalls: [(String, String, [String: Any])] = []

        for part in parts {
            // Skip thinking/reasoning blocks
            if part["thought"] as? Bool == true { continue }

            if let text = part["text"] as? String {
                responseText += text
            }
            if let fc = part["functionCall"] as? [String: Any],
               let name = fc["name"] as? String,
               let args = fc["args"] as? [String: Any] {
                toolCalls.append((UUID().uuidString, name, args))
            }
        }

        // Add model turn to history
        history.append([
            "role": "model",
            "parts": parts
        ])

        return Response(text: responseText, toolCalls: toolCalls)
    }

    /// Clear conversation history.
    func clearHistory() {
        history = []
    }

    enum GeminiError: Error, LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from Gemini"
            case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(100))"
            case .parseError: return "Could not parse Gemini response"
            }
        }
    }
}
