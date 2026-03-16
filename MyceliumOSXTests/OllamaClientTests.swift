import XCTest
@testable import MyceliumOSX

final class OllamaClientTests: XCTestCase {

    // MARK: - Response Parsing

    func testParseSuccessResponse() throws {
        let json: [String: Any] = [
            "response": "Hello there!",
            "done": true,
            "total_duration": 246000000,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try OllamaClient.parseResponse(data)

        XCTAssertEqual(parsed.text, "Hello there!")
        XCTAssertTrue(parsed.done)
    }

    func testParseEmptyResponse() throws {
        let json: [String: Any] = [
            "response": "",
            "done": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try OllamaClient.parseResponse(data)

        XCTAssertEqual(parsed.text, "")
        XCTAssertTrue(parsed.done)
    }

    func testParseErrorResponse() throws {
        let json: [String: Any] = [
            "error": "model not found"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try OllamaClient.parseResponse(data)) { error in
            XCTAssertTrue(error.localizedDescription.contains("model not found"))
        }
    }

    func testParseMalformedResponse() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try OllamaClient.parseResponse(data))
    }

    // MARK: - Request Building

    func testBuildRequest() throws {
        let client = OllamaClient(model: "gemma3:4b", systemInstruction: "Be brief.")
        let request = client.buildRequest(prompt: "Hello", history: [])

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]

        XCTAssertEqual(body["model"] as? String, "gemma3:4b")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["system"] as? String, "Be brief.")
        XCTAssertEqual(body["prompt"] as? String, "Hello")
    }

    func testBuildRequestWithHistory() throws {
        let client = OllamaClient(model: "gemma3:4b", systemInstruction: "test")
        let history: [OllamaClient.Message] = [
            .init(role: "user", content: "Hi"),
            .init(role: "assistant", content: "Hello!"),
        ]
        let request = client.buildRequest(prompt: "How are you?", history: history)

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]

        // Ollama uses "messages" format for chat with history
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertNotNil(messages)
        // system + 2 history + 1 new = 4
        XCTAssertEqual(messages?.count, 4)
    }

    func testBuildRequestURL() {
        let client = OllamaClient(model: "gemma3:4b", systemInstruction: "test", baseURL: "http://localhost:11434")
        let request = client.buildRequest(prompt: "Hi", history: [])

        XCTAssertEqual(request.url?.host, "localhost")
        XCTAssertEqual(request.url?.port, 11434)
    }

    // MARK: - History Management

    func testHistoryAccumulates() {
        var history: [OllamaClient.Message] = []
        OllamaClient.appendToHistory(&history, role: "user", content: "Hello")
        OllamaClient.appendToHistory(&history, role: "assistant", content: "Hi!")

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].role, "user")
        XCTAssertEqual(history[1].content, "Hi!")
    }

    func testHistoryTruncation() {
        var history: [OllamaClient.Message] = []
        for i in 0..<30 {
            OllamaClient.appendToHistory(&history, role: "user", content: "msg \(i)")
        }

        OllamaClient.truncateHistory(&history, maxTurns: 20)
        XCTAssertEqual(history.count, 20)
        // Should keep the most recent
        XCTAssertEqual(history.last?.content, "msg 29")
    }

    // MARK: - Availability Check

    func testIsAvailableReturnsFalseWhenNoServer() async {
        let client = OllamaClient(model: "test", systemInstruction: "test", baseURL: "http://localhost:99999")
        let available = await client.isAvailable()
        XCTAssertFalse(available)
    }
}
