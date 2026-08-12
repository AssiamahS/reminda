import Foundation
import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceRecorder {
    var transcript = ""
    var isRecording = false
    var errorText: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        transcript = ""
        errorText = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.errorText = "Speech recognition not allowed — enable it in Settings."
                    return
                }
                self.begin()
            }
        }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorText = "Speech recognition unavailable right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                Task { @MainActor in
                    if let text { self.transcript = text }
                    if final || error != nil { self.finish() }
                }
            }
        } catch {
            errorText = "Mic failed: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        request?.endAudio()
        finish()
    }

    private func finish() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
