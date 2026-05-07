import Foundation
import AppKit
import Carbon.HIToolbox

/// Modifier key options for the dictation hotkey.
enum HotkeyTrigger: String, CaseIterable, Identifiable, Codable {
    case rightOption
    case leftOption
    case rightCommand
    case leftCommand
    case fn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption: return "Right Option (⌥)"
        case .leftOption: return "Left Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .leftCommand: return "Left Command (⌘)"
        case .fn: return "Fn / Globe"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return UInt16(kVK_RightOption)
        case .leftOption: return UInt16(kVK_Option)
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .leftCommand: return UInt16(kVK_Command)
        case .fn: return UInt16(kVK_Function)
        }
    }

    /// The modifier flag that is set when this key is held.
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption, .leftOption: return .option
        case .rightCommand, .leftCommand: return .command
        case .fn: return .function
        }
    }
}

/// Monitors global keyboard events to detect hold/release of a configurable modifier key.
@MainActor
final class HotkeyMonitor: ObservableObject {
    @Published var selectedTrigger: HotkeyTrigger = .rightOption
    @Published var isKeyHeld = false

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRunning = false
        isKeyHeld = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let trigger = selectedTrigger

        // Check if this event is for our target key code
        guard event.keyCode == trigger.keyCode else { return }

        let flagPresent = event.modifierFlags.contains(trigger.modifierFlag)

        if flagPresent && !isKeyHeld {
            // Key pressed
            isKeyHeld = true
            onKeyDown?()
        } else if !flagPresent && isKeyHeld {
            // Key released
            isKeyHeld = false
            onKeyUp?()
        }
    }
}
