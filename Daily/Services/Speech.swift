import Foundation
import Speech
import AVFoundation

/// Live speech-to-text with the microphone (Apple's on-device recognizer when available).
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    /// 0…1, for drawing a level meter.
    @Published var level: Float = 0
    @Published var errorText: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Text that was already there before this round of listening.
    private var prefix = ""

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        errorText = nil
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status == .authorized) }
        }
        guard speechOK else {
            errorText = "Allow Speech Recognition for Daily in Settings to talk to it."
            return
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else {
            errorText = "Allow the microphone for Daily in Settings to talk to it."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognition isn't available right now. You can type instead."
            return
        }

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = SpeechRecognizer.rms(buffer)
                Task { @MainActor in self?.level = level }
            }
            engine.prepare()
            try engine.start()

            prefix = transcript.isEmpty ? "" : transcript + " "
            self.engine = engine
            self.request = request
            isListening = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = (result?.isFinal ?? false) || error != nil
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = self.prefix + text }
                    if finished { self.stop() }
                }
            }
        } catch {
            errorText = "Couldn't start the microphone: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isListening = false
        level = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        return min(max(rms * 12, 0), 1)
    }
}
