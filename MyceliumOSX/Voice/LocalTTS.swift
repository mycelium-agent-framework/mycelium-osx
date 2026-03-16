import AVFoundation
import Foundation

/// Local text-to-speech using macOS built-in AVSpeechSynthesizer.
/// Provides a consistent voice identity for Vivian.
@Observable
final class LocalTTS: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    /// The voice identifier to use. Set once to establish Vivian's voice identity.
    var voiceIdentifier: String

    /// Whether currently speaking.
    private(set) var isSpeaking = false

    /// Called when speech completes.
    var onFinished: (() -> Void)?

    override init() {
        // Pick a good default English voice
        // Prefer "Samantha" (enhanced) or "Zoe" for a warm female voice
        let preferred = ["com.apple.voice.enhanced.en-US.Samantha",
                         "com.apple.voice.premium.en-US.Zoe",
                         "com.apple.voice.enhanced.en-US.Zoe",
                         "com.apple.voice.compact.en-US.Samantha"]

        let availableIds = Set(AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map(\.identifier))

        voiceIdentifier = preferred.first(where: { availableIds.contains($0) })
            ?? AVSpeechSynthesisVoice.speechVoices()
                .first(where: { $0.language.hasPrefix("en") })?.identifier
            ?? ""

        super.init()
        synthesizer.delegate = self
    }

    /// Speak text aloud as Vivian.
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// List available English voices (for settings/selection).
    static func availableVoices() -> [(id: String, name: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { (id: $0.identifier, name: $0.name) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        onFinished?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
