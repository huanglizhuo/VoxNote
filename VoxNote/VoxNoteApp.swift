import SwiftUI
import AppKit

/// Shared app state accessible for view model initialization
@MainActor
final class AppState {
    static let shared = AppState()

    let transcriptionEngine = TranscriptionEngine()
    let summarizationEngine = SummarizationEngine()
    let downloadManager = ModelDownloadManager()
    let deviceManager = AudioDeviceManager()
    let captureService = AudioCaptureService()
    let noteStore = NoteStore()
    let dictationService: DictationService

    private init() {
        dictationService = DictationService(transcriptionEngine: transcriptionEngine)
    }
}

@main
struct VoxNoteApp: App {
    private let appState = AppState.shared
    @AppStorage("dictationEnabled") private var dictationEnabled = false
    @AppStorage("dictationHotkey") private var dictationHotkey = HotkeyTrigger.rightOption.rawValue
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("VoxNote", id: "main") {
            ContentView()
                .environmentObject(appState.transcriptionEngine)
                .environmentObject(appState.summarizationEngine)
                .environmentObject(appState.downloadManager)
                .environmentObject(appState.deviceManager)
                .environmentObject(appState.captureService)
                .environmentObject(appState.noteStore)
                .environmentObject(appState.dictationService)
                .frame(minWidth: 720, minHeight: 500)
                .task {
                    // Restore dictation hotkey and enabled state on launch
                    if let trigger = HotkeyTrigger(rawValue: dictationHotkey) {
                        appState.dictationService.hotkeyMonitor.selectedTrigger = trigger
                    }
                    if dictationEnabled {
                        appState.dictationService.enableDictation()
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Start/Stop Recording") {
                    // Handled by individual views via keyboard shortcut
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // Menu bar icon — since LSUIElement hides the Dock icon, this is
        // the primary way to access the app.
        MenuBarExtra {
            MenuBarMenu(dictationService: appState.dictationService) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            Image(systemName: "waveform.circle")
        }

        Settings {
            DictationSettingsView(dictationService: appState.dictationService)
        }
    }
}

// MARK: - Menu Bar Menu

private struct MenuBarMenu: View {
    @ObservedObject var dictationService: DictationService
    let showMainWindow: () -> Void

    var body: some View {
        Button("打开 VoxNote") {
            showMainWindow()
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        Toggle("听写模式", isOn: Binding(
            get: { dictationService.isListening },
            set: { enabled in
                if enabled {
                    dictationService.enableDictation()
                } else {
                    dictationService.disableDictation()
                }
            }
        ))

        if dictationService.isDictating {
            Label("听写中...", systemImage: "mic.fill")
        } else if dictationService.isProcessing {
            Label("识别中...", systemImage: "ellipsis.circle")
        }

        Divider()

        Button("退出 VoxNote") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
