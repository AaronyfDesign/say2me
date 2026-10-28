import Foundation

// User preferences, backed by UserDefaults.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    // "doubleCtrl" | "doubleOpt" | "doubleCmd" | "custom"
    @Published var triggerMode: String {
        didSet { d.set(triggerMode, forKey: "triggerMode"); HotkeyCenter.shared.reload() }
    }
    // Custom hotkey (used when triggerMode == "custom")
    @Published var customKeyCode: Int {
        didSet { d.set(customKeyCode, forKey: "customKeyCode"); HotkeyCenter.shared.reload() }
    }
    @Published var customModifiers: Int {
        didSet { d.set(customModifiers, forKey: "customModifiers"); HotkeyCenter.shared.reload() }
    }
    @Published var autoStopSeconds: Int {
        didSet { d.set(autoStopSeconds, forKey: "autoStopSeconds") }
    }
    // "paste" | "clipboard"
    @Published var insertMode: String {
        didSet { d.set(insertMode, forKey: "insertMode") }
    }
    // "auto" | "zh" | "en" | "ja" | "ko" | "yue"
    @Published var language: String {
        didSet { d.set(language, forKey: "language") }
    }
    @Published var useITN: Bool {
        didSet { d.set(useITN, forKey: "useITN") }
    }
    // Play a chime when dictation starts/stops (like system dictation)
    @Published var soundFeedback: Bool {
        didSet { d.set(soundFeedback, forKey: "soundFeedback") }
    }
    // Optional overrides; empty = auto-resolve
    @Published var modelDir: String {
        didSet { d.set(modelDir, forKey: "modelDir") }
    }
    @Published var cliPath: String {
        didSet { d.set(cliPath, forKey: "cliPath") }
    }

    private init() {
        d.register(defaults: [
            "triggerMode": "doubleCtrl",
            "customKeyCode": 49,          // space
            "customModifiers": 0x0800,    // option
            "autoStopSeconds": 30,
            "insertMode": "paste",
            "language": "auto",
            "useITN": true,
            "soundFeedback": true,
            "modelDir": "",
            "cliPath": "",
        ])
        triggerMode = d.string(forKey: "triggerMode") ?? "doubleCtrl"
        customKeyCode = d.integer(forKey: "customKeyCode")
        customModifiers = d.integer(forKey: "customModifiers")
        autoStopSeconds = d.integer(forKey: "autoStopSeconds")
        insertMode = d.string(forKey: "insertMode") ?? "paste"
        language = d.string(forKey: "language") ?? "auto"
        useITN = d.bool(forKey: "useITN")
        soundFeedback = d.bool(forKey: "soundFeedback")
        modelDir = d.string(forKey: "modelDir") ?? ""
        cliPath = d.string(forKey: "cliPath") ?? ""
    }

    // MARK: - Path resolution

    /// Repo root inferred from app bundle: <repo>/build/SenseDict.app
    static func repoRoot() -> URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()   // SenseDict.app
            .deletingLastPathComponent()   // build/
    }

    static func resolveModelDir() -> String? {
        if !Prefs.shared.modelDir.isEmpty,
           FileManager.default.fileExists(atPath: Prefs.shared.modelDir + "/model.int8.onnx") {
            return Prefs.shared.modelDir
        }
        let candidates = [
            repoRoot().appendingPathComponent("models/sense-voice").path,
            NSString("~/sense-dict-models/sense-voice").expandingTildeInPath,
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c + "/model.int8.onnx") { return c }
        }
        return nil
    }

    static func resolveCliPath() -> String? {
        if !Prefs.shared.cliPath.isEmpty, FileManager.default.isExecutableFile(atPath: Prefs.shared.cliPath) {
            return Prefs.shared.cliPath
        }
        // any vendored sherpa-onnx osx-arm64 package next to the repo
        let vendor = repoRoot().appendingPathComponent("vendor")
        if let ents = try? FileManager.default.contentsOfDirectory(atPath: vendor.path) {
            for e in ents.sorted().reversed() where e.contains("osx-arm64") {
                let p = vendor.appendingPathComponent(e).appendingPathComponent("bin/sherpa-onnx-offline").path
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        for p in ["/opt/homebrew/bin/sherpa-onnx-offline", "/usr/local/bin/sherpa-onnx-offline"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}
