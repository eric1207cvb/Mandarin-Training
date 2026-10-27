import Foundation
import Speech
import Combine
import AVFoundation

// MARK: - Speech Input Manager
class SpeechInputManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    
    private var silenceTimer: Timer?
    private var startGeneration = 0
    private var isCleaningUp = false
    private var hasInputTap = false
    
    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        SpeechManager.shared.stop()
        startGeneration += 1
        let generation = startGeneration
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.startGeneration == generation else { return }
                guard status == .authorized else {
                    self.errorMessage = "請至設定開啟語音權限"
                    return
                }
                self.requestMicrophoneAccess(generation: generation)
            }
        }
    }
    
    private func requestMicrophoneAccess(generation: Int) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.startGeneration == generation else { return }
                guard granted else {
                    self.errorMessage = "請至設定開啟麥克風權限"
                    return
                }
                self.beginCapture()
            }
        }
    }
    
    private func beginCapture() {
        cleanupSpeechSession()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "無法啟動麥克風"
            print("Audio Session Error: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                guard let self else { return }
                if let transcript {
                    self.transcribedText = transcript
                    self.resetSilenceTimer()
                }
                if failed || isFinal {
                    self.stopRecording()
                }
            }
        }
        
        removeInputTapIfNeeded()
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasInputTap = true
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            transcribedText = ""
            errorMessage = nil
            isRecording = true
        } catch {
            errorMessage = "無法啟動麥克風"
            print("Audio Engine Start Error: \(error)")
            cleanupSpeechSession()
        }
    }
    
    func stopRecording() {
        startGeneration += 1
        guard !isCleaningUp else { return }
        isCleaningUp = true
        cleanupSpeechSession()
        isCleaningUp = false
        isRecording = false
    }
    
    private func cleanupSpeechSession() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }
        removeInputTapIfNeeded()
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func removeInputTapIfNeeded() {
        guard hasInputTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInputTap = false
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.stopRecording()
        }
    }
}
