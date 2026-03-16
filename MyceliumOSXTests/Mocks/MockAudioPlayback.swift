import Foundation
@testable import MyceliumOSX

final class MockAudioPlayback: AudioPlaying {
    var isStarted = false
    var enqueuedChunks: [Data] = []
    var interruptCallCount = 0

    func start() throws {
        isStarted = true
    }

    func stop() {
        isStarted = false
        enqueuedChunks = []
    }

    func enqueue(pcmData: Data) {
        enqueuedChunks.append(pcmData)
    }

    func interrupt() {
        interruptCallCount += 1
        enqueuedChunks = []
    }
}
