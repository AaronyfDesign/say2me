import SwiftUI
import AppKit
import AVFoundation
import Combine
import ApplicationServices

// MARK: - Menu bar UI

final class StatusBarController: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    let controller = DictationController.shared

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        HotkeyCenter.shared.isRecordingProvider = { DictationController.shared.state == .recording }
        HotkeyCenter.shared.recordingStartedAtProvider = { DictationController.shared.startedAt }
        HotkeyCenter.shared.start { [weak self] in
            self?.controller.toggle()
        }
        rebuildMenu()
        statusItem.menu?.delegate = self
        // Observe state changes to refresh icon + menu
        let ctr = controller
        ctr.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &bag)
        refreshIcon()
    }

    private var bag = Set<AnyCancellable>()
    private var cancellable: Any?

    private func refreshIcon() {
        let icon: NSImage
        switch controller.state {
        case .idle:
            icon = BrandIcon.menuIcon(for: .idle)
            icon.accessibilityDescription = "say2me 待机"
        case .recording:
            icon = BrandIcon.menuIcon(for: .recording)
            icon.accessibilityDescription = "say2me 录音中"
        case .transcribing:
            icon = BrandIcon.menuIcon(for: .transcribing)
            icon.accessibilityDescription = "say2me 识别中"
        }
        statusItem.button?.image = icon
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "开始/停止听写", action: #selector(toggle(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let axTrusted = AXIsProcessTrusted()
        let healthy = HotkeyCenter.shared.isTapHealthy
        let axItem = menu.addItem(withTitle: axTrusted ? "辅助功能：已授权 ✓" : "辅助功能：未授权（点击打开设置）",
                                   action: #selector(openAccessibility(_:)),
                                   keyEquivalent: "")
        axItem.isEnabled = true
        if HotkeyCenter.shared.currentTriggerIsDoubleTap && !healthy {
            let state = !HotkeyCenter.shared.isTapActive
                ? "未启动（需辅助功能授权）"
                : "已启动但收不到事件（需「输入监控」权限）"
            let warn = menu.addItem(withTitle: "⚠ 热键监听异常：\(state)",
                                    action: #selector(openInputMonitoring(_:)), keyEquivalent: "")
            warn.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings(_:)),
                     keyEquivalent: ",")
        let last = menu.addItem(withTitle: "上次识别结果：\(controller.lastResult.isEmpty ? "(空)" : controller.lastResult)",
                                 action: nil, keyEquivalent: "")
        last.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 say2me", action: #selector(quit(_:)),
                     keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func openAccessibility(_ sender: Any?) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @objc private func openInputMonitoring(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_InputMonitoring")!)
    }

    @objc private func toggle(_ sender: Any?) { controller.toggle() }

    @objc private func openSettings(_ sender: Any?) {
        if let w = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(self)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "say2me 设置"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(prefs: Prefs.shared,
                                                              controller: controller))
        w.center()
        settingsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(self)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

// MARK: - App bootstrap

final class AppDelegate: NSObject, NSApplicationDelegate {
    var bar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bar = StatusBarController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
_ = NSApplication.shared.run()
