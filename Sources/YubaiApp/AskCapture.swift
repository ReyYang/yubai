import Foundation
import Observation
import AVFoundation
import Speech
import Network

@MainActor @Observable final class AskConnectivity {
    var connected = true
    private var monitor: NWPathMonitor?
    private var generation = UUID()
    func start() {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { connected = true; return }
        #endif
        guard monitor == nil else { return }
        let token = UUID(); generation = token
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.connected = connected
            }
        }
        self.monitor = monitor
        monitor.start(queue: DispatchQueue(label: "app.yubai.connectivity"))
    }
    func stop() { generation = UUID(); monitor?.cancel(); monitor = nil }
}

@MainActor @Observable final class AskVoiceCapture {
    var transcript = ""
    var recording = false
    var errorText = ""
    var permissionDenied = false
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    private var generation = UUID()
    var available: Bool { recognizer?.isAvailable == true && AVCaptureDevice.default(for: .audio) != nil }
    func refreshPermissions() {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        permissionDenied = speech == .denied || speech == .restricted || microphone == .denied || microphone == .restricted
    }
    func start() async {
        stop(); let token = UUID(); generation = token; errorText = ""; transcript = ""
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard generation == token, !Task.isCancelled else { return }
        refreshPermissions()
        guard speech else { return }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == token, !Task.isCancelled else { return }
        refreshPermissions()
        guard mic else { return }
        guard let recognizer, recognizer.isAvailable else { errorText = "语音暂时不可用"; return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain: "YubaiVoice", code: 1) }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true; engine.prepare(); try engine.start(); recording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true || error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch { stop(); errorText = "这次没能开始听写，可以再试一次或直接打字。" }
    }
    func stop() {
        generation = UUID(); engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
