import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "personal.say2me", category: "insert")

/// Inserts recognized text at the current focus:
///  - paste mode: temporarily swaps the clipboard, simulates Cmd+V, restores
///  - clipboard mode: only copies to the clipboard
///
/// Pasteboard read timing matters: many apps (Electron, IMEs) read the
/// clipboard asynchronously after receiving Cmd+V, so the previous contents
/// must not be restored too early. We wait 1.5s and restore only if the
/// board is untouched since our write (changeCount) and still holds our text.
enum TextInserter {
    private struct SavedItem {
        var data: [NSPasteboard.PasteboardType: Data]
    }
    private struct Saved {
        var items: [SavedItem] = []
        var valid = false
    }

    /// Returns true if text was pasted (requires Accessibility);
    /// false means it was only copied to the clipboard.
    @discardableResult
    static func insert(_ text: String, paste: Bool) -> Bool {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let afterWrite = pb.changeCount

        guard paste, AXIsProcessTrusted() else {
            log.warning("not pasted (paste=\(paste, privacy: .public), axTrusted=\(AXIsProcessTrusted(), privacy: .public)); text is on the clipboard")
            return false
        }

        // give the pasteboard write a beat to settle before synthesizing paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9 /* v */, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            log.info("Cmd+V posted, textLen=\(text.count, privacy: .public)")
        }

        // restore the previous clipboard late, and only if nothing else
        // (the target app, or the user) wrote to the board meanwhile
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard saved.valid, !saved.items.isEmpty else { return }
            guard pb.changeCount == afterWrite else { return } // someone else wrote
            guard pb.string(forType: .string) == text else { return } // consumed/replaced
            pb.clearContents()
            let objs: [NSPasteboardItem] = saved.items.map { si in
                let item = NSPasteboardItem()
                for (type, d) in si.data { item.setData(d, forType: type) }
                return item
            }
            pb.writeObjects(objs)
            log.info("clipboard restored")
        }
        return true
    }

    private static func snapshot(_ pb: NSPasteboard) -> Saved {
        var sp = Saved()
        sp.valid = true
        guard let items = pb.pasteboardItems, !items.isEmpty else { return sp }
        for item in items {
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) {
                    data[type] = d
                }
            }
            if !data.isEmpty { sp.items.append(SavedItem(data: data)) }
        }
        return sp
    }
}
