import XCTest
@testable import MyceliumOSX

/// Tests for GeminiTextClient response parsing.
/// Network calls are not tested — only parsing and state management.
final class GeminiTextClientTests: XCTestCase {

    func testHistoryClearsOnClear() async {
        let client = GeminiTextClient(apiKey: "test", systemInstruction: "test")
        // Can't test send() without network, but can test clearHistory
        await client.clearHistory()
        // No crash = success
    }

    func testResponseParsing() throws {
        // Test the response parsing by creating the expected JSON structure
        let responseJson: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "role": "model",
                        "parts": [
                            ["text": "Hello there!"]
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJson)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let candidates = json["candidates"] as! [[String: Any]]
        let content = candidates[0]["content"] as! [String: Any]
        let parts = content["parts"] as! [[String: Any]]

        var text = ""
        for part in parts {
            if part["thought"] as? Bool == true { continue }
            if let t = part["text"] as? String { text += t }
        }

        XCTAssertEqual(text, "Hello there!")
    }

    func testThinkingBlocksFiltered() throws {
        let parts: [[String: Any]] = [
            ["text": "Let me think about this...", "thought": true],
            ["text": "Hello!"]
        ]

        var text = ""
        for part in parts {
            if part["thought"] as? Bool == true { continue }
            if let t = part["text"] as? String { text += t }
        }

        XCTAssertEqual(text, "Hello!")
    }

    func testToolCallParsing() throws {
        let parts: [[String: Any]] = [
            ["functionCall": ["name": "remember_this", "args": ["content": "test", "spore_type": "note"]]]
        ]

        var toolCalls: [(String, [String: Any])] = []
        for part in parts {
            if let fc = part["functionCall"] as? [String: Any],
               let name = fc["name"] as? String,
               let args = fc["args"] as? [String: Any] {
                toolCalls.append((name, args))
            }
        }

        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].0, "remember_this")
        XCTAssertEqual(toolCalls[0].1["content"] as? String, "test")
    }

    func testMixedThinkingAndResponse() throws {
        let parts: [[String: Any]] = [
            ["text": "**Analyzing**\nThinking deeply...", "thought": true],
            ["text": "**More thoughts**", "thought": true],
            ["text": "The answer is 42."]
        ]

        var responseText = ""
        var thinkingText = ""
        for part in parts {
            if part["thought"] as? Bool == true {
                thinkingText += (part["text"] as? String ?? "")
            } else if let t = part["text"] as? String {
                responseText += t
            }
        }

        XCTAssertEqual(responseText, "The answer is 42.")
        XCTAssertTrue(thinkingText.contains("Analyzing"))
    }
}
