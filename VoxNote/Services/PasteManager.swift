import AppKit
import CoreGraphics
import Carbon.HIToolbox
import os.log

private let pasteLogger = Logger(subsystem: "com.voxnote", category: "PasteManager")

/// How recognized text is delivered to the target input field.
enum InputMethod: String, CaseIterable, Identifiable, Codable {
    case paste      // Clipboard + AppleScript Cmd+V
    case typing     // CGEvent simulated keystrokes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paste: return "粘贴 (Cmd+V)"
        case .typing: return "模拟键入"
        }
    }

    var description: String {
        switch self {
        case .paste: return "通过剪贴板和 Cmd+V 粘贴，速度快但会短暂占用剪贴板"
        case .typing: return "逐字符模拟键盘输入，不占用剪贴板但速度较慢"
        }
    }
}

/// Outputs recognized text into the currently focused input field.
final class PasteManager {

    /// Insert text into the focused input field using the specified method.
    @MainActor
    static func pasteText(_ text: String, method: InputMethod = .paste, targetApp: NSRunningApplication? = nil) async {
        // 1. Activate the target app so it receives the events
        if let app = targetApp {
            app.activate()
            pasteLogger.info("Activating target app: \(app.localizedName ?? "unknown") pid=\(app.processIdentifier)")
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }

        // 2. Wait for all modifier keys to be released.
        await waitForModifierRelease()

        // 3. Deliver text using the chosen method
        switch method {
        case .paste:
            await pasteViaClipboard(text)
        case .typing:
            pasteLogger.info("Typing \(text.count) characters via CGEvent")
            typeText(text)
        }
    }

    // MARK: - Modifier Key Wait

    private static func waitForModifierRelease() async {
        let maxWaitNs: UInt64 = 2_000_000_000
        let pollIntervalNs: UInt64 = 50_000_000
        var waited: UInt64 = 0
        while waited < maxWaitNs {
            let flags = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn])
            if flags.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: pollIntervalNs)
            waited += pollIntervalNs
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms grace
    }

    // MARK: - Paste via Clipboard + AppleScript

    private static func pasteViaClipboard(_ text: String) async {
        pasteLogger.info("Pasting \(text.count) chars via clipboard + AppleScript")
        let pasteboard = NSPasteboard.general
        let backup = backupPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let writtenChangeCount = pasteboard.changeCount

        let pasted = executeAppleScriptPaste()

        if pasted {
            pasteLogger.info("AppleScript paste succeeded")
        } else {
            pasteLogger.warning("AppleScript paste failed")
            // Restore clipboard since paste didn't work
            restorePasteboard(pasteboard, items: backup)
            return
        }

        // Wait for paste to be processed, then restore clipboard
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        if pasteboard.changeCount == writtenChangeCount {
            restorePasteboard(pasteboard, items: backup)
        }
    }

    private static func executeAppleScriptPaste() -> Bool {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else {
            pasteLogger.error("Failed to create AppleScript")
            return false
        }
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            pasteLogger.error("AppleScript error: \(error)")
            return false
        }
        return true
    }

    // MARK: - Type via CGEvent

    private static func typeText(_ text: String) {
        guard let source = CGEventSource(stateID: .privateState) else {
            pasteLogger.error("Failed to create CGEventSource")
            return
        }

        for char in text.utf16 {
            var unichar = char

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }

            keyDown.flags = []
            keyUp.flags = []

            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            Thread.sleep(forTimeInterval: 0.005) // 5ms per char
        }
    }

    // MARK: - Clipboard Backup / Restore

    private struct PasteboardBackupItem {
        let typesAndData: [(NSPasteboard.PasteboardType, Data)]
    }

    private static func backupPasteboard(_ pasteboard: NSPasteboard) -> [PasteboardBackupItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.map { item in
            let pairs: [(NSPasteboard.PasteboardType, Data)] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return PasteboardBackupItem(typesAndData: pairs)
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [PasteboardBackupItem]) {
        guard !items.isEmpty else { return }

        pasteboard.clearContents()

        let restoredItems: [NSPasteboardItem] = items.map { backup in
            let item = NSPasteboardItem()
            for (type, data) in backup.typesAndData {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
