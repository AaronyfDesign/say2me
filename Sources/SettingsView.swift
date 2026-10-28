import SwiftUI
import Carbon

// MARK: - Hotkey recorder (captures custom key combos)

struct HotkeyRecorderView: View {
    @ObservedObject var prefs: Prefs
    @State private var recording = false

    var body: some View {
        HStack {
            if recording {
                Text("按下想要的组合键…")
                    .foregroundColor(.secondary)
                Button("取消") { recording = false }
            } else {
                Button(recordButtonLabel) { recording = true }
            }
        }
        .background(KeyCatcher(active: recording) { keyCode, mods in
            prefs.customKeyCode = Int(keyCode)
            prefs.customModifiers = Int(mods)
            recording = false
        })
    }

    private var recordButtonLabel: String {
        if prefs.customKeyCode == 0 { return "录制快捷键" }
        return HotkeyRecorderView.keyLabel(keyCode: UInt32(prefs.customKeyCode),
                        modifiers: UInt32(prefs.customModifiers))
    }

    static func keyLabel(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ code: UInt32) -> String {
        switch code {
        case 0: return "A"; case 11: return "B"; case 38: return "J"
        case 40: return "K"; case 37: return "L"; case 32: return "U"
        case 34: return "I"; case 31: return "O"; case 35: return "P"
        case 33: return "N"; case 30: return "M"
        case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"
        case 7: return "X"; case 8: return "C"; case 9: return "V"
        case 12: return "Q"; case 13: return "W"; case 14: return "E"
        case 15: return "R"; case 16: return "Y"; case 17: return "T"
        case 18: return "1"; case 19: return "2"; case 20: return "3"
        case 21: return "4"; case 22: return "5"; case 23: return "6"
        case 26: return "7"; case 27: return "8"; case 28: return "9"
        case 25: return "0"; case 36: return "↩"; case 49: return "Space"
        case 51: return "⌫"; case 53: return "Esc"; case 122: return "F1"
        case 120: return "F2"; case 99: return "F3"; case 118: return "F4"
        case 96: return "F5"; case 97: return "F6"; case 98: return "F7"
        case 100: return "F8"; case 101: return "F9"; case 109: return "F10"
        case 103: return "F11"; case 111: return "F12"
        default: return "Key \(code)"
        }
    }
}

private struct KeyCatcher: NSViewRepresentable {
    let active: Bool
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> NSView { KeyCatchView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatchView)?.configure(active: active,
                                             onCapture: onCapture)
    }

    final class KeyCatchView: NSView {
        var active = false
        var onCapture: ((UInt32, UInt32) -> Void)?

        func configure(active: Bool, onCapture: @escaping (UInt32, UInt32) -> Void) {
            self.active = active
            self.onCapture = onCapture
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard active else { return super.keyDown(with: event) }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
            onCapture?(UInt32(event.keyCode), mods)
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var controller: DictationController
    @State private var testResult = ""

    var body: some View {
        Form {
            Section("触发方式") {
                Picker("快捷键", selection: $prefs.triggerMode) {
                    Text("双击 Control").tag("doubleCtrl")
                    Text("双击 Option").tag("doubleOpt")
                    Text("双击 Command").tag("doubleCmd")
                    Text("自定义组合键").tag("custom")
                }
                if prefs.triggerMode == "custom" {
                    HotkeyRecorderView(prefs: prefs)
                }
                Text("双击开始听写，再次按同一键结束；也可在设置中改用自定义组合键。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("录音") {
                Stepper("自动结束：\(prefs.autoStopSeconds) 秒",
                        value: $prefs.autoStopSeconds, in: 5...120, step: 5)
            }
            Section("识别") {
                Picker("语言", selection: $prefs.language) {
                    Text("自动检测").tag("auto")
                    Text("中文").tag("zh")
                    Text("粤语").tag("yue")
                    Text("英语").tag("en")
                    Text("日语").tag("ja")
                    Text("韩语").tag("ko")
                }
                Toggle("数字规整（如“三点五”→“3.5”）", isOn: $prefs.useITN)
                Toggle("听写起止提示音", isOn: $prefs.soundFeedback)
            }
            Section("文本插入") {
                Picker("插入方式", selection: $prefs.insertMode) {
                    Text("自动粘贴到光标处").tag("paste")
                    Text("仅复制到剪贴板").tag("clipboard")
                }
            }
            Section("测试") {
                HStack {
                    Button("录 3 秒并识别") {
                        controller.recordForTest(seconds: 3) { text in
                            testResult = text
                        }
                    }
                    .disabled(controller.state != .idle)
                    if controller.state != .idle {
                        ProgressView()
                            .controlSize(.small)
                        Text(controller.state == .recording ? "录音中…" : "识别中…")
                            .foregroundColor(.secondary)
                    }
                }
                Text(testResult.isEmpty ? "（点击上方按钮测试识别效果）" : testResult)
                    .font(.callout)
                    .foregroundColor(testResult.hasPrefix("（") ? .secondary : .primary)
            }
            Section("高级") {
                HStack {
                    Text("模型目录")
                    TextField("自动", text: $prefs.modelDir)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("sherpa CLI")
                    TextField("自动", text: $prefs.cliPath)
                        .textFieldStyle(.roundedBorder)
                }
                Text("留空则自动在应用同级目录与 homebrew 路径中查找。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("权限状态") {
                Text(permissionSummary)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Button("打开系统设置 → 隐私与安全性") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
                }
            }
            if !controller.lastError.isEmpty {
                Section("最近错误") {
                    Text(controller.lastError)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
    }

    private var permissionSummary: String {
        var s: [String] = []
        s.append(AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary) as Bool ? "辅助功能：已授予" : "辅助功能：未授予（无法自动粘贴）")
        s.append("麦克风：在首次听写时系统会询问")
        return s.joined(separator: "，")
    }
}
