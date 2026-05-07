import Foundation
import AppKit
import SwiftUI
import Combine
import os.log

private let dictationLogger = Logger(subsystem: "com.voxnote", category: "DictationService")

/// Coordinates hotkey listening, audio capture, ASR transcription, and paste-to-input for
/// the "hold key to dictate" feature.
@MainActor
final class DictationService: ObservableObject {
    @Published var isListening = false
    @Published var isDictating = false
    @Published var isProcessing = false
    @Published var lastError: String?

    let hotkeyMonitor = HotkeyMonitor()
    let permissionManager = PermissionManager()

    private let transcriptionEngine: TranscriptionEngine
    private let micCaptureService = AudioCaptureService()
    private var overlayPanel: NSPanel?
    private var permissionCancellable: AnyCancellable?
    /// The application that was in the foreground when dictation started.
    /// We restore focus to this app before typing the recognized text.
    private var previousApp: NSRunningApplication?

    init(transcriptionEngine: TranscriptionEngine) {
        self.transcriptionEngine = transcriptionEngine
        setupHotkeyCallbacks()
        // Forward permissionManager changes so SwiftUI views update
        permissionCancellable = permissionManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - Enable / Disable

    func enableDictation() {
        permissionManager.refreshStatus()
        dictationLogger.info("Accessibility granted: \(self.permissionManager.isAccessibilityGranted)")

        if !permissionManager.isAccessibilityGranted {
            // Prompt for accessibility — needed for pasting into other apps.
            permissionManager.checkAccessibility(prompt: true)
            // Still start listening even if not yet granted; the user may
            // grant it from System Settings while the app is running.
            // We'll check again at paste time and warn if still not granted.
            dictationLogger.warning("Accessibility not yet granted — paste may fail")
        }

        hotkeyMonitor.start()
        isListening = true
        lastError = nil
        dictationLogger.info("Dictation enabled with trigger: \(self.hotkeyMonitor.selectedTrigger.rawValue)")
    }

    func disableDictation() {
        hotkeyMonitor.stop()
        if isDictating {
            cancelDictation()
        }
        isListening = false
        dictationLogger.info("Dictation disabled")
    }

    // MARK: - Hotkey Callbacks

    private func setupHotkeyCallbacks() {
        hotkeyMonitor.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startDictation()
            }
        }
        hotkeyMonitor.onKeyUp = { [weak self] in
            Task { @MainActor in
                self?.stopDictationAndPaste()
            }
        }
    }

    // MARK: - Dictation Flow

    private func startDictation() {
        guard !isDictating else { return }

        guard transcriptionEngine.isModelLoaded else {
            playSound(.basso)
            lastError = "模型未加载"
            dictationLogger.warning("Cannot start dictation: model not loaded")
            return
        }

        guard transcriptionEngine.activeSource == nil else {
            playSound(.basso)
            lastError = "另一个录音正在进行中"
            dictationLogger.warning("Cannot start dictation: another recording is active")
            return
        }

        // Remember which app currently has focus so we can restore it before typing.
        previousApp = NSWorkspace.shared.frontmostApplication
        dictationLogger.info("Previous app: \(self.previousApp?.localizedName ?? "nil")")

        do {
            try transcriptionEngine.startStreamingTranscription(source: .microphone)

            let engine = transcriptionEngine
            try micCaptureService.startCapture(deviceID: nil, outputFileURL: nil) { samples in
                engine.feedAudio(samples: samples)
            }

            isDictating = true
            lastError = nil
            playSound(.tink)
            showOverlay()
            dictationLogger.info("Dictation started")
        } catch {
            lastError = error.localizedDescription
            playSound(.basso)
            dictationLogger.error("Failed to start dictation: \(error.localizedDescription)")
        }
    }

    private func stopDictationAndPaste() {
        guard isDictating else { return }

        isDictating = false
        isProcessing = true

        micCaptureService.stop()
        transcriptionEngine.stopStreaming()
        playSound(.pop)
        dictationLogger.info("Dictation stopped, waiting for final text")

        Task {
            // Wait for the transcription engine to finish processing
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if !transcriptionEngine.isTranscribing { break }
            }

            let text = transcriptionEngine.confirmedText
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Hide the overlay BEFORE pasting so our floating panel does not
            // intercept or misdirect the synthetic Cmd+V event.
            isProcessing = false
            hideOverlay()

            if !text.isEmpty {
                // Re-check accessibility right before pasting
                permissionManager.refreshStatus()
                if !permissionManager.isAccessibilityGranted {
                    dictationLogger.error("Accessibility not granted at paste time — opening settings")
                    lastError = "需要辅助功能权限：请在系统设置中授权 VoxNote"
                    permissionManager.openAccessibilitySettings()
                    // Still put text on clipboard so user can manually paste
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    playSound(.basso)
                } else {
                    let method = InputMethod(rawValue: UserDefaults.standard.string(forKey: "dictationInputMethod") ?? "") ?? .paste
                    dictationLogger.info("Pasting text (\(text.count) chars) via \(method.rawValue)")
                    await PasteManager.pasteText(text, method: method, targetApp: self.previousApp)
                }
            } else {
                dictationLogger.info("No text recognized, skipping paste")
            }
            self.previousApp = nil
        }
    }

    private func cancelDictation() {
        micCaptureService.stop()
        transcriptionEngine.cancelStreaming()
        isDictating = false
        isProcessing = false
        hideOverlay()
    }

    // MARK: - Sound Feedback

    private enum SoundName: String {
        case tink = "Tink"
        case pop = "Pop"
        case basso = "Basso"
    }

    private func playSound(_ name: SoundName) {
        NSSound(named: NSSound.Name(name.rawValue))?.play()
    }

    // MARK: - Overlay Panel

    private func showOverlay() {
        guard overlayPanel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = DictationOverlayContent(service: self)
        panel.contentView = NSHostingView(rootView: overlayView)

        if let screen = NSScreen.main {
            let x = (screen.frame.width - 140) / 2 + screen.frame.origin.x
            let y = screen.frame.origin.y + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        overlayPanel = panel
    }

    private func hideOverlay() {
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
    }
}

// MARK: - Overlay SwiftUI Content

private struct DictationOverlayContent: View {
    @ObservedObject var service: DictationService

    var body: some View {
        HStack(spacing: 8) {
            if service.isDictating {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6), radius: 4)
                Text("听写中...")
                    .font(.system(size: 13, weight: .medium))
            } else if service.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("识别中...")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
