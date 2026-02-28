import SwiftUI

struct ContentView: View {
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var summarizationEngine: SummarizationEngine
    @EnvironmentObject var downloadManager: ModelDownloadManager
    @EnvironmentObject var deviceManager: AudioDeviceManager
    @EnvironmentObject var captureService: AudioCaptureService
    @EnvironmentObject var noteStore: NoteStore

    @State private var selection: SidebarSelection? = .voxRecord
    @State private var showOnboarding = false

    @StateObject private var modelManagerVM: ModelManagerViewModel
    @StateObject private var fileTranscriptionVM: FileTranscriptionViewModel
    @StateObject private var systemAudioVM: SystemAudioViewModel

    init() {
        _modelManagerVM = StateObject(wrappedValue: ModelManagerViewModel(
            downloadManager: AppState.shared.downloadManager,
            transcriptionEngine: AppState.shared.transcriptionEngine,
            summarizationEngine: AppState.shared.summarizationEngine
        ))
        _fileTranscriptionVM = StateObject(wrappedValue: FileTranscriptionViewModel(
            transcriptionEngine: AppState.shared.transcriptionEngine
        ))
        _systemAudioVM = StateObject(wrappedValue: SystemAudioViewModel(
            transcriptionEngine: AppState.shared.transcriptionEngine,
            captureService: AppState.shared.captureService,
            deviceManager: AppState.shared.deviceManager,
            noteStore: AppState.shared.noteStore,
            speakerDiarizationService: AppState.shared.speakerDiarizationService
        ))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            Group {
                switch selection {
                case .voxRecord:
                    SystemAudioView(viewModel: systemAudioVM)
                case .fileTranscription:
                    FileTranscriptionView(viewModel: fileTranscriptionVM)
                case .modelManager:
                    ModelManagerView(viewModel: modelManagerVM, downloadManager: AppState.shared.downloadManager)
                case .note(let id):
                    if let note = noteStore.notes.first(where: { $0.id == id }) {
                        NoteDetailView(
                            note: note,
                            noteStore: noteStore,
                            transcriptionEngine: transcriptionEngine,
                            summarizationEngine: summarizationEngine,
                            selection: $selection
                        )
                    } else {
                        Text("Note not found")
                            .foregroundStyle(.secondary)
                    }
                case nil:
                    Text("Select an item from the sidebar")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    if transcriptionEngine.isTranscribing {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if transcriptionEngine.isModelLoaded {
                        Text(modelManagerVM.selectedModel?.name ?? "")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(downloadManager: downloadManager) {
                showOnboarding = false
                Task {
                    await modelManagerVM.loadSelectedModelIfNeeded()
                    await modelManagerVM.loadSummarizationModelIfNeeded()
                }
            }
        }
        .task {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                let hasAnyModel = ModelInfo.availableModels.contains { downloadManager.isDownloaded($0) }
                if !hasAnyModel {
                    showOnboarding = true
                }
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }

            await modelManagerVM.loadSelectedModelIfNeeded()
            await modelManagerVM.loadSummarizationModelIfNeeded()
        }
    }
}
