import Foundation
import AppKit
import AVFoundation

/// Dictation state machine: idle -> recording -> transcribing -> idle.
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum State { case idle, recording, transcribing }
    @Published private(set) var state: State = .idle
    @Published var lastResult: String = ""
    @Published var lastError: String = ""

    private(set) var startedAt: Date?
    private let recorder = AudioRecorder()
    private var timer: Timer?

    private init() {}

    /// Toggle via hotkey: start when idle, stop-and-transcribe when recording.
    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .transcribing: break
        }
    }

    func start() {
        guard state == .idle else { return }
        dbg("start requested")
        requestMic { granted in
            guard granted else {
                dbg("mic DENIED — cannot record")
                self.lastError = "麦克风权限被拒绝（系统设置 → 隐私与安全性 → 麦克风）"
                NSSound.beep()
                return
            }
            do {
                try self.recorder.start()
                self.startedAt = Date()
                self.setState(.recording)
                self.playChime(.start)
                self.scheduleAutoStop(seconds: Prefs.shared.autoStopSeconds)
                dbg("recording started")
            } catch {
                dbg("recorder.start failed: \(error)")
                self.lastError = "录音启动失败：\(error.localizedDescription)"
                NSSound.beep()
            }
        }
    }

    func stop() {
        guard state == .recording else { return }
        timer?.invalidate(); timer = nil
        let samples = recorder.stop()
        setState(.transcribing)
        playChime(.stop)
        guard samples.count > 1600 else { // < 0.1s of audio: treat as cancel
            setState(.idle)
            return
        }
        transcribe(samples: samples)
    }

    /// Used by the settings "test" button: record fixed duration, then
    /// transcribe WITHOUT inserting (result is shown in the UI instead).
    func recordForTest(seconds: Double, completion: @escaping (String) -> Void) {
        guard state == .idle else { return }
        requestMic { granted in
            guard granted else {
                completion("（麦克风权限被拒绝）")
                return
            }
            do {
                try self.recorder.start()
                self.startedAt = Date()
                self.setState(.recording)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    let samples = self.recorder.stop()
                    self.timer?.invalidate(); self.timer = nil
                    self.setState(.idle)
                    guard samples.count > 1600 else {
                        completion("（录音太短）")
                        return
                    }
                    self.transcribe(samples: samples) { text in
                        completion(text)
                    }
                }
            } catch {
                completion("启动失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private enum Chime { case start, stop }

    private func playChime(_ kind: Chime) {
        guard Prefs.shared.soundFeedback else { return }
        // system sound set; falls back to a beep if missing
        let name = kind == .start ? "Tink" : "Pop"
        if let s = NSSound(named: NSSound.Name(name)) {
            s.volume = 0.6
            s.play()
        } else {
            NSSound.beep()
        }
    }

    private func setState(_ s: State) {
        state = s
        DictationIndicator.shared.update(state: s)
    }

    private func transcribe(samples: [Float], completion: ((String) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            dbg("transcribe begin, samples=\(samples.count)")
            let wavURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("say2me-\(UUID().uuidString).wav")
            do {
                try WavWriter.write(samples: samples, to: wavURL)
                defer { try? FileManager.default.removeItem(at: wavURL) }
                guard let cli = Prefs.resolveCliPath(),
                      let modelDir = Prefs.resolveModelDir() else {
                    throw Recognizer.RecognizerError.cliMissing
                }
                let text = try Recognizer.run(
                    wavPath: wavURL.path,
                    config: .init(cliPath: cli, modelDir: modelDir,
                                 language: Prefs.shared.language,
                                 useITN: Prefs.shared.useITN))
                DispatchQueue.main.async {
                    self?.setState(.idle)
                    self?.lastResult = text
                    dbg("transcribe ok: \(text)")
                    if let c = completion {
                        c(text)
                    } else if !text.isEmpty {
                        let pasted = TextInserter.insert(text,
                                                         paste: Prefs.shared.insertMode == "paste")
                        if !pasted && Prefs.shared.insertMode == "paste" {
                            self?.lastError = "未能自动粘贴（辅助功能未授权？），文本已复制到剪贴板"
                        }
                    }
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                DispatchQueue.main.async {
                    self?.setState(.idle)
                    self?.lastError = msg
                    NSSound.beep()
                    completion?("")
                }
            }
        }
    }

    private func scheduleAutoStop(seconds: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds),
                                     repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    private func requestMic(_ handler: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            dbg("mic permission result=\(granted)")
            DispatchQueue.main.async { handler(granted) }
        }
    }
}
