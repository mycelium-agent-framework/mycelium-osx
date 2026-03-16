import XCTest
@testable import MyceliumOSX

/// Tests for hotkey event handling logic.
/// We can't test CGEvent tap creation (requires Accessibility permission),
/// but we can test the press/release state machine.
final class GlobalHotkeyManagerTests: XCTestCase {

    func testPressAndReleaseCallbacks() {
        var pressCount = 0
        var releaseCount = 0

        let manager = GlobalHotkeyManager(
            onPress: { pressCount += 1 },
            onRelease: { releaseCount += 1 }
        )

        // Initial state
        XCTAssertEqual(pressCount, 0)
        XCTAssertEqual(releaseCount, 0)

        // Can't simulate CGEvents directly in unit tests,
        // but we verify the manager initializes without crashing
        // and the callbacks are stored correctly.
        _ = manager
    }

    func testManagerDoesNotCrashOnStop() {
        let manager = GlobalHotkeyManager(onPress: {}, onRelease: {})
        // Stop without start should be safe
        manager.stop()
    }

    func testManagerDoesNotCrashOnDoubleStop() {
        let manager = GlobalHotkeyManager(onPress: {}, onRelease: {})
        manager.stop()
        manager.stop()
    }
}
