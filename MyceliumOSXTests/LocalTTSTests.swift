import XCTest
@testable import MyceliumOSX

final class LocalTTSTests: XCTestCase {

    func testVoiceSelection() {
        let tts = LocalTTS()
        // Should have a default voice set
        XCTAssertNotNil(tts.voiceIdentifier)
    }

    func testAvailableVoicesNotEmpty() {
        let voices = LocalTTS.availableVoices()
        // macOS always has at least a few built-in voices
        XCTAssertFalse(voices.isEmpty)
    }

    func testStopDoesNotCrash() {
        let tts = LocalTTS()
        tts.stop()  // Should be safe to call when not speaking
    }

    func testIsSpeakingDefaultsFalse() {
        let tts = LocalTTS()
        XCTAssertFalse(tts.isSpeaking)
    }
}
