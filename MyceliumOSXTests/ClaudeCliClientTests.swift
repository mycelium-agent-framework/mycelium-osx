import XCTest
@testable import MyceliumOSX

final class ClaudeCliClientTests: XCTestCase {

    func testParseSuccessResponse() throws {
        let json = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":1500,"result":"Hello there!","session_id":"abc-123","total_cost_usd":0.001}
        """
        let parsed = try ClaudeCliClient.parseResponse(json)
        XCTAssertEqual(parsed.text, "Hello there!")
        XCTAssertEqual(parsed.sessionId, "abc-123")
        XCTAssertFalse(parsed.isError)
    }

    func testParseErrorResponse() throws {
        let json = """
        {"type":"result","subtype":"error","is_error":true,"result":"Something went wrong","session_id":"abc-123"}
        """
        let parsed = try ClaudeCliClient.parseResponse(json)
        XCTAssertTrue(parsed.isError)
        XCTAssertEqual(parsed.text, "Something went wrong")
    }

    func testParseMalformedResponse() {
        XCTAssertThrowsError(try ClaudeCliClient.parseResponse("not json"))
    }

    func testBuildArguments() {
        let client = ClaudeCliClient(model: "haiku", systemPrompt: "Be brief.")
        let args = client.buildArguments(prompt: "Hello", sessionId: nil)

        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("json"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("haiku"))
        XCTAssertTrue(args.contains("--append-system-prompt"))
        XCTAssertTrue(args.contains("Be brief."))
        XCTAssertFalse(args.contains("--resume"))
    }

    func testBuildArgumentsWithSession() {
        let client = ClaudeCliClient(model: "sonnet", systemPrompt: "test")
        let args = client.buildArguments(prompt: "Hi", sessionId: "session-xyz")

        XCTAssertTrue(args.contains("--resume"))
        XCTAssertTrue(args.contains("session-xyz"))
    }

    func testSessionIdPreserved() {
        let client = ClaudeCliClient(model: "haiku", systemPrompt: "test")
        XCTAssertNil(client.currentSessionId)
    }

    func testIsAvailableChecksClaudeBinary() async {
        let client = ClaudeCliClient(model: "haiku", systemPrompt: "test")
        let available = await client.isAvailable()
        // Should be true since claude is installed
        XCTAssertTrue(available)
    }
}
