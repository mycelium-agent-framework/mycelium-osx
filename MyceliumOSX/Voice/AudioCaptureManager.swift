import AVFoundation
import Foundation

/// Captures microphone audio as 16-bit PCM, 16kHz mono for Gemini Live API.
@Observable
final class AudioCaptureManager: AudioCapturing {
    private let engine = AVAudioEngine()
    private var isCapturing = false

    /// Called with each chunk of PCM data (16-bit LE, 16kHz mono).
    var onAudioChunk: ((Data) -> Void)?

    /// Current audio level (0.0 to 1.0) for UI feedback.
    var audioLevel: Float = 0.0

    /// Target format for Gemini Live: 16kHz, mono, 16-bit integer
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    /// Request microphone permission explicitly.
    /// On macOS 14+, even non-sandboxed apps must request authorization.
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            print("[AudioCapture] Microphone access denied. Open System Settings > Privacy > Microphone.")
            return false
        @unknown default:
            return false
        }
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        // Check mic permission synchronously — caller should have awaited requestPermission() first
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            print("[AudioCapture] Microphone not authorized (status: \(status.rawValue)). Cannot capture.")
            return
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install a tap that converts to our target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[AudioCapture] Could not create format converter")
            return
        }

        // Tap at the input node's native format, then convert
        let bufferSize: AVAudioFrameCount = 1600 // 100ms at 16kHz
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.convertAndDeliver(buffer: buffer, converter: converter)
        }

        try engine.start()
        isCapturing = true
        print("[AudioCapture] Microphone capture started.")
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        print("[AudioCapture] Microphone capture stopped.")
    }

    private func convertAndDeliver(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        // Calculate output frame count based on sample rate ratio
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            print("[AudioCapture] Conversion error: \(error)")
            return
        }

        // Extract raw PCM bytes
        guard let channelData = outputBuffer.int16ChannelData else { return }
        let frameCount = Int(outputBuffer.frameLength)
        let byteCount = frameCount * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)

        // Compute RMS audio level for UI feedback
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = Float(samples[i]) / Float(Int16.max)
            sum += sample * sample
        }
        let rms = sqrt(sum / max(Float(frameCount), 1))
        // Smooth and clamp to 0-1
        let level = min(rms * 3.0, 1.0) // amplify for visibility
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }

        onAudioChunk?(data)
    }

    deinit {
        stopCapture()
    }
}
