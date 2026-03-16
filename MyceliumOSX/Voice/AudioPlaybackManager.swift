import AVFoundation
import Foundation

/// Plays back PCM audio received from Gemini Live API (24kHz, 16-bit LE mono).
@Observable
final class AudioPlaybackManager: AudioPlaying {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlaying = false

    /// Gemini Live response audio format: 24kHz, mono, 16-bit integer
    private let responseFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: true
    )!

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: responseFormat)
    }

    func start() throws {
        guard !isPlaying else { return }
        try engine.start()
        playerNode.play()
        isPlaying = true
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isPlaying = false
    }

    /// Enqueue PCM audio data for playback.
    func enqueue(pcmData: Data) {
        if !isPlaying {
            try? start()
        }

        let frameCount = pcmData.count / MemoryLayout<Int16>.size

        guard let buffer = AVAudioPCMBuffer(pcmFormat: responseFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        pcmData.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            guard let dst = buffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, pcmData.count)
        }

        playerNode.scheduleBuffer(buffer)
    }

    /// Interrupt playback (for barge-in).
    func interrupt() {
        playerNode.stop()
        playerNode.play() // Reset to accept new buffers
    }

    deinit {
        stop()
    }
}
