import SwiftUI

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

    private init() {}
}

@main
struct ClothNoteApp: App {
    private let appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState.transcriptionEngine)
                .environmentObject(appState.summarizationEngine)
                .environmentObject(appState.downloadManager)
                .environmentObject(appState.deviceManager)
                .environmentObject(appState.captureService)
                .environmentObject(appState.noteStore)
                .frame(minWidth: 720, minHeight: 500)
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
    }
}
