import XCTest
@testable import MyceliumOSX

final class LocalSTTTests: XCTestCase {

    func testInitialState() {
        let stt = LocalSTT()
        XCTAssertFalse(stt.isListening)
        XCTAssertEqual(stt.currentText, "")
    }

    func testStopWhenNotListeningDoesNotCrash() {
        let stt = LocalSTT()
        stt.stop()
        XCTAssertFalse(stt.isListening)
    }

    func testAuthorizationStatusAccessible() {
        // Just verify the enum is accessible — actual auth depends on system state
        let status = LocalSTT.authorizationStatus()
        XCTAssertNotNil(status)
    }

    func testCallbacksSetBeforeStart() {
        let stt = LocalSTT()
        var received = false
        stt.onFinalText = { _ in received = true }
        // Can't actually start without mic, but callbacks should be settable
        XCTAssertFalse(received)
    }
}
