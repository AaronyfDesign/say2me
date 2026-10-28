import Foundation
import AppKit
import Carbon
import ApplicationServices
import os

private let log = Logger(subsystem: "personal.say2me", category: "hotkey")

/// Ground-truth file logger: unified log has proven unreliable for this app.
func dbg(_ s: String) {
    let path = "/tmp/say2me-debug.log"
    let line = "\(Date().timeIntervalSince1970) \(s)\n"
    let data = line.data(using: .utf8) ?? Data()
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// Global trigger handling:
///  - idle:      double-tap of a modifier key starts dictation
///  - recording: a single isolated press of the same modifier stops it
///  - or a custom key combination via Carbon RegisterEventHotKey
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onTrigger: (() -> Void)?
    var isRecordingProvider: () -> Bool = { false }
    var recordingStartedAtProvider: () -> Date? = { nil }

    /// Only "isolated" presses count: a press is isolated when no other key,
    /// scroll or other modifier chorded with it. Any non-target key event
    /// invalidates the previous clean press.
    ///
    /// The release of the press that fired the trigger is fully disarmed so
    /// trailing taps right after a double-tap can never stop (or restart)
    /// dictation by accident. While recording, a clean single release stops
    /// dictation, but only after a small grace period (0.3s) so the tail of
    /// the starting double-tap cannot cut the recording short.
    private final class DoubleTapDetector {
        let targetCodes: Set<CGKeyCode>
        let window: TimeInterval
        let grace: TimeInterval
        let isRecording: () -> Bool
        let recordingStartedAt: () -> Date?

        private var lastCleanPressDate: Date?
        private var currentPressDirty = false
        private var suppressUntilKeyUp = false
        private var targetDown = false

        init(targetCodes: Set<CGKeyCode>,
             window: TimeInterval = 0.45,
             grace: TimeInterval = 0.3,
             isRecording: @escaping () -> Bool,
             recordingStartedAt: @escaping () -> Date?) {
            self.targetCodes = targetCodes
            self.window = window
            self.grace = grace
            self.isRecording = isRecording
            self.recordingStartedAt = recordingStartedAt
        }

        // returns true when the trigger should fire
        func flagsChanged(keycode: CGKeyCode, isDown: Bool) -> Bool {
            guard targetCodes.contains(keycode) else {
                currentPressDirty = true
                lastCleanPressDate = nil
                return false
            }
            if isDown {
                if suppressUntilKeyUp { return false }
                if !targetDown { // fresh press of the target modifier
                    targetDown = true
                    let now = Date()
                    if let last = lastCleanPressDate, now.timeIntervalSince(last) < window {
                        suppressUntilKeyUp = true
                        lastCleanPressDate = nil
                        return true // double-tap: trigger!
                    }
                    currentPressDirty = false
                }
                // repeated flagsChanged for an already-held key: ignore
            } else {
                let wasTriggerPress = suppressUntilKeyUp
                suppressUntilKeyUp = false
                targetDown = false
                if wasTriggerPress {
                    // release of the press that fired the trigger: fully disarm
                    return false
                }
                if !currentPressDirty {
                    if isRecording(), let started = recordingStartedAt(),
                       Date().timeIntervalSince(started) > grace {
                        // single isolated press while recording: stop
                        lastCleanPressDate = nil
                        return true
                    }
                    lastCleanPressDate = Date()
                } else {
                    lastCleanPressDate = nil
                    currentPressDirty = false
                }
            }
            return false
        }

        func otherKeyDown() {
            currentPressDirty = true
            lastCleanPressDate = nil
        }
        func scrollWheel() {
            currentPressDirty = true
            lastCleanPressDate = nil
        }
        func reset() {
            lastCleanPressDate = nil
            currentPressDirty = false
            suppressUntilKeyUp = false
            targetDown = false
        }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var detector: DoubleTapDetector?
    private var currentMode: String = ""
    private var trustPollTimer: Timer?
    private(set) var isTapActive = false
    /// Delivery self-test: a tap can be created yet receive zero events when
    /// Input Monitoring is missing. This flag reflects actual delivery.
    private(set) var isTapHealthy = false
    private static let selfTestKeyCode: Int64 = 47 // unused keycode marker

    /// Post a synthetic marker event; handleTap flips isTapHealthy on receipt.
    func runDeliverySelfTest() {
        guard tap != nil else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(Self.selfTestKeyCode),
                        keyDown: false)!
        e.type = .flagsChanged
        e.flags = []
        e.post(tap: .cghidEventTap)
    }

    // MARK: - Carbon hotkey

    private var carbonHotKey: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var carbonID: UInt32 = 0

    // MARK: - Public

    var currentTriggerIsDoubleTap: Bool {
        currentMode != "custom"
    }

    func reload() {
        let mode = Prefs.shared.triggerMode
        currentMode = mode
        let providers = (
            isRecording: { HotkeyCenter.shared.isRecordingProvider() },
            startedAt: { HotkeyCenter.shared.recordingStartedAtProvider() }
        )
        switch mode {
        case "doubleCtrl":
            detector = DoubleTapDetector(targetCodes: [59, 62],
                                         isRecording: providers.isRecording,
                                         recordingStartedAt: providers.startedAt)
        case "doubleOpt":
            detector = DoubleTapDetector(targetCodes: [58, 61],
                                         isRecording: providers.isRecording,
                                         recordingStartedAt: providers.startedAt)
        case "doubleCmd":
            detector = DoubleTapDetector(targetCodes: [55, 54],
                                         isRecording: providers.isRecording,
                                         recordingStartedAt: providers.startedAt)
        default:
            detector = nil
        }

        unregisterCarbon()
        if mode == "custom" {
            registerCarbon(keyCode: UInt32(Prefs.shared.customKeyCode),
                          modifiers: UInt32(Prefs.shared.customModifiers))
        }
    }

    func start(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger

        var hotKeySpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                        eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            HotkeyCenter.shared.handleCarbonHotKey(event)
        }, 1, &hotKeySpec, nil, &handlerRef)

        reload()
        bootstrapTap()
    }

    /// Create the event tap as soon as Accessibility is granted.
    /// If not granted yet, prompt once and poll every second — no relaunch
    /// needed once the user toggles us on in System Settings.
    private func bootstrapTap() {
        if AXIsProcessTrusted() {
            createTap()
            return
        }
        log.warning("AX not trusted yet; prompting for Accessibility")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if AXIsProcessTrusted() {
                t.invalidate()
                HotkeyCenter.shared.createTap()
            }
        }
    }

    private func createTap() {
        guard tap == nil else { return }
        let eventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, _ -> Unmanaged<CGEvent>? in
                HotkeyCenter.shared.handleTap(proxy, type, event)
            },
            userInfo: nil
        ) else {
            log.error("event tap creation failed even though AX reported trusted")
            return
        }
        tap = t
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        isTapActive = true
        isTapHealthy = false
        dbg("event tap started, added to main runloop common modes")
        log.info("event tap started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.runDeliverySelfTest()
        }
    }

    private func handleTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        dbg("handleTap type=\(type.rawValue)")
        log.info("handleTap type=\(type.rawValue, privacy: .public)")
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passRetained(event)
        }
        guard let det = detector, currentMode != "custom" else {
            return Unmanaged.passRetained(event)
        }
        switch type {
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == Self.selfTestKeyCode {
                isTapHealthy = true
                dbg("SELFTEST received — tap delivery OK")
                return Unmanaged.passRetained(event)
            }
            log.info("flagsChanged code=\(code) down=\(event.flags.intersection([.maskControl, .maskAlternate, .maskCommand]) != [], privacy: .public)")
            dbg("flagsChanged code=\(code) flags=\(event.flags.rawValue)")
            let modifier: CGEventFlags
            switch code {
            case 59, 62: modifier = .maskControl
            case 58, 61: modifier = .maskAlternate
            case 55, 54: modifier = .maskCommand
            default:
                _ = det.flagsChanged(keycode: CGKeyCode(code), isDown: false)
                return Unmanaged.passRetained(event)
            }
            let isDown = event.flags.intersection(modifier) == modifier
            if det.flagsChanged(keycode: CGKeyCode(code), isDown: isDown) {
                fire()
            }
        case .keyDown:
            det.otherKeyDown()
        case .scrollWheel:
            det.scrollWheel()
        default:
            break
        }
        return Unmanaged.passRetained(event)
    }

    private func fire() {
        let mode = currentMode
        dbg("TRIGGER FIRED mode=\(mode)")
        log.info("trigger fired (mode=\(mode, privacy: .public))")
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }

    // MARK: - Carbon

    private func registerCarbon(keyCode: UInt32, modifiers: UInt32) {
        guard keyCode != 0 else { return }
        let hkID = EventHotKeyID(signature: OSType(0x53444354) /* 'SDCT' */, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            carbonHotKey = ref
            carbonID = hkID.id
        } else {
            log.error("RegisterEventHotKey failed status=\(status)")
        }
    }

    private func unregisterCarbon() {
        if let ref = carbonHotKey {
            UnregisterEventHotKey(ref)
            carbonHotKey = nil
        }
    }

    private func handleCarbonHotKey(_ event: EventRef?) -> OSStatus {
        var hkID = EventHotKeyID()
        GetEventParameter(event, UInt32(kEventParamDirectObject),
                          UInt32(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &hkID)
        if hkID.id == carbonID {
            fire()
            return noErr
        }
        return OSStatus(eventNotHandledErr)
    }
}
