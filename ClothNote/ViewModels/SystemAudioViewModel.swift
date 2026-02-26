import Foundation
import AppKit
import Combine

@MainActor
class SystemAudioViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var selectedDevice: AudioDevice?
    @Published var showSetupGuide = false
    @Published var error: String?
    @Published var recordingStartDate: Date?
    @Published var isReversed = true

    let transcriptionEngine: TranscriptionEngine
    let captureService: AudioCaptureService
    let deviceManager: AudioDeviceManager
    let noteStore: NoteStore

    private var currentRecordingNoteID: UUID?
    private var autoSaveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(transcriptionEngine: TranscriptionEngine, captureService: AudioCaptureService, deviceManager: AudioDeviceManager, noteStore: NoteStore) {
        self.transcriptionEngine = transcriptionEngine
        self.captureService = captureService
        self.deviceManager = deviceManager
        self.noteStore = noteStore

        // Forward engine changes so views re-render when transcript text updates
        transcriptionEngine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        if let blackHole = deviceManager.blackHoleDevices.first {
            selectedDevice = blackHole
        }
    }

    var hasBlackHole: Bool {
        !deviceManager.blackHoleDevices.isEmpty
    }

    func startRecording() {
        guard let device = selectedDevice else {
            error = "No audio device selected."
            return
        }

        guard transcriptionEngine.isModelLoaded else {
            error = "No model loaded. Please download and select a model first."
            return
        }

        guard transcriptionEngine.activeSource == nil else {
            error = "Another recording is already in progress. Stop it first."
            return
        }

        do {
            var note = Note(source: .systemAudio)
            note.audioFileName = "\(note.id.uuidString).wav"
            noteStore.save(note)
            currentRecordingNoteID = note.id
            recordingStartDate = Date()

            let audioURL = noteStore.audioDirectory.appendingPathComponent(note.audioFileName!)
            try transcriptionEngine.startStreamingTranscription(source: .systemAudio)
            let engine = transcriptionEngine
            try captureService.startCapture(deviceID: device.id, outputFileURL: audioURL) { samples in
                engine.feedAudio(samples: samples)
            }
            isRecording = true
            error = nil

            startAutoSave()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stopRecording() {
        captureService.stop()
        transcriptionEngine.stopStreaming()

        let noteID = currentRecordingNoteID
        let startDate = recordingStartDate
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self else { return }
            self.finishRecording(noteID: noteID, startDate: startDate)
        }
    }

    private func finishRecording(noteID: UUID?, startDate: Date?) {
        autoSaveTask?.cancel()
        autoSaveTask = nil

        if let noteID, var note = noteStore.notes.first(where: { $0.id == noteID }) {
            note.content = transcriptionEngine.confirmedText
            let engineSegments = transcriptionEngine.segments
            if !engineSegments.isEmpty {
                note.segments = engineSegments
            }
            if let startDate {
                note.duration = Date().timeIntervalSince(startDate)
            }
            noteStore.save(note)
        }

        isRecording = false
        currentRecordingNoteID = nil
        recordingStartDate = nil
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptionEngine.fullText, forType: .string)
    }

    func exportAsText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? transcriptionEngine.fullText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Auto-save

    private func startAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self else { break }
                guard let noteID = self.currentRecordingNoteID,
                      var note = self.noteStore.notes.first(where: { $0.id == noteID }) else { continue }
                note.content = self.transcriptionEngine.confirmedText
                let engineSegments = self.transcriptionEngine.segments
                if !engineSegments.isEmpty {
                    note.segments = engineSegments
                }
                if let startDate = self.recordingStartDate {
                    note.duration = Date().timeIntervalSince(startDate)
                }
                self.noteStore.save(note)
            }
        }
    }
}
