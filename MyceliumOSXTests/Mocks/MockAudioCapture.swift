import Foundation
@testable import MyceliumOSX

final class MockAudioCapture: AudioCapturing {
    var audioLevel: Float = 0.0
    var onAudioChunk: ((Data) -> Void)?

    var permissionGranted = true
    var isCapturing = false
    var startCaptureCallCount = 0
    var stopCaptureCallCount = 0
    var shouldThrowOnStart = false

    func requestPermission() async -> Bool {
        permissionGranted
    }

    func startCapture() throws {
        if shouldThrowOnStart {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock capture error"])
        }
        isCapturing = true
        startCaptureCallCount += 1
    }

    func stopCapture() {
        isCapturing = false
        stopCaptureCallCount += 1
    }

    /// Simulate receiving an audio chunk.
    func simulateAudioChunk(_ data: Data = Data(repeating: 0, count: 320)) {
        onAudioChunk?(data)
    }
}
