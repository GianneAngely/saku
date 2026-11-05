import AVFoundation
import Speech

/// Listens to the microphone and streams recognised words, on-device when the language supports it.
/// Asks for Microphone and Speech Recognition only when voice follow is switched on.
@MainActor
final class VoiceFollower {
    enum State: Equatable { case off, asking, listening, denied, unavailable }

    var onState: ((State) -> Void)?
    var onWords: (([String]) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var active = false
    private(set) var onDevice = false

    func start(locale: Locale) {
        active = true
        onState?(.asking)
        Task { @MainActor in
            let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            guard self.active else { return }
            guard speech && mic else { self.onState?(.denied); return }
            guard let r = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), r.isAvailable else {
                self.onState?(.unavailable)
                return
            }
            self.recognizer = r
            self.onDevice = r.supportsOnDeviceRecognition
            self.begin()
        }
    }

    private func begin() {
        guard active, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            onState?(.unavailable)
            return
        }
        onState?(.listening)
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let words = result?.bestTranscription.segments.map(\.substring) ?? []
            let done = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.active else { return }
                    if !words.isEmpty { self.onWords?(words) }
                    if done { self.restart() }
                }
            }
        }
    }

    /// Recognition tasks end after a pause or about a minute; start a fresh one while still following.
    private func restart() {
        stopAudio()
        guard active else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in MainActor.assumeIsolated { self?.begin() } }
    }

    private func stopAudio() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    func stop() {
        active = false
        stopAudio()
        onState?(.off)
    }
}
