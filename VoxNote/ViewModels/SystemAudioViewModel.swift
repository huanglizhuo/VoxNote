import Foundation
import AppKit
import Combine
import SwiftUI
import AVFoundation
import os.log

@MainActor
class SystemAudioViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.voxnote", category: "SystemAudioViewModel")
    @Published var isRecording = false
    @Published var selectedDevice: AudioDevice?
    @Published var showSetupGuide = false
    @Published var error: String?
    @Published var recordingStartDate: Date?
    @Published var isReversed = true
    @Published var liveSpeakerLabels: [UUID: String] = [:]

    let transcriptionEngine: TranscriptionEngine
    let captureService: AudioCaptureService
    let deviceManager: AudioDeviceManager
    let noteStore: NoteStore
    let speakerDiarizationService: SpeakerDiarizationService

    private(set) var currentRecordingNoteID: UUID?
    private var autoSaveTask: Task<Void, Never>?
    private var liveDiarizationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var recordedSamples: [Float] = []

    init(transcriptionEngine: TranscriptionEngine, captureService: AudioCaptureService, deviceManager: AudioDeviceManager, noteStore: NoteStore, speakerDiarizationService: SpeakerDiarizationService) {
        self.transcriptionEngine = transcriptionEngine
        self.captureService = captureService
        self.deviceManager = deviceManager
        self.noteStore = noteStore
        self.speakerDiarizationService = speakerDiarizationService

        // Forward engine changes so views re-render when transcript text updates
        transcriptionEngine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Trigger live diarization whenever a new segment is confirmed
        transcriptionEngine.$segments
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] segs in
                guard let self, self.isRecording, !segs.isEmpty else { return }
                self.scheduleLiveDiarization()
            }
            .store(in: &cancellables)

        if let blackHole = deviceManager.blackHoleDevices.first {
            selectedDevice = blackHole
        }
    }

    var hasBlackHole: Bool {
        !deviceManager.blackHoleDevices.isEmpty
    }

    func startRecording() {
        guard let device = resolvedInputDevice() else {
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
            var note = Note(source: .systemAudio, deviceName: device.name)
            note.audioFileName = "\(note.id.uuidString).wav"
            noteStore.save(note)
            currentRecordingNoteID = note.id
            recordingStartDate = Date()

            let audioURL = noteStore.audioDirectory.appendingPathComponent(note.audioFileName!)
            try transcriptionEngine.startStreamingTranscription(source: .systemAudio)
            recordedSamples = []
            liveSpeakerLabels = [:]
            let engine = transcriptionEngine
            try captureService.startCapture(deviceID: device.id, outputFileURL: audioURL) { [weak self] samples in
                engine.feedAudio(samples: samples)
                Task { @MainActor [weak self] in
                    self?.recordedSamples.append(contentsOf: samples)
                }
            }
            isRecording = true
            error = nil

            startAutoSave()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resolvedInputDevice() -> AudioDevice? {
        guard let selectedDevice else { return nil }

        // Device IDs can change when aggregate/multi-output devices are recreated.
        if let exact = deviceManager.inputDevices.first(where: { $0.id == selectedDevice.id && $0.id != 0 }) {
            logger.info("Using selected input device id=\(exact.id) name=\(exact.name, privacy: .public) sr=\(exact.sampleRate, format: .fixed(precision: 0)) in=\(exact.inputChannels) out=\(exact.outputChannels)")
            return exact
        }
        if let byName = deviceManager.inputDevices.first(where: { $0.name == selectedDevice.name && $0.id != 0 }) {
            self.selectedDevice = byName
            logger.warning("Selected device id changed; remapped by name to id=\(byName.id) name=\(byName.name, privacy: .public)")
            return byName
        }
        if let firstBlackHole = deviceManager.blackHoleDevices.first(where: { $0.id != 0 }) {
            self.selectedDevice = firstBlackHole
            logger.warning("Selected device missing; fallback to BlackHole id=\(firstBlackHole.id) name=\(firstBlackHole.name, privacy: .public)")
            return firstBlackHole
        }
        logger.error("No valid input device available for recording")
        return nil
    }

    func stopRecording() {
        captureService.stop()
        transcriptionEngine.stopStreaming()
        liveDiarizationTask?.cancel()
        liveDiarizationTask = nil

        let noteID = currentRecordingNoteID
        let startDate = recordingStartDate
        let samples = recordedSamples
        recordedSamples = []
        logger.info("[Diarization] stopRecording — captured \(samples.count) samples for noteID=\(noteID?.uuidString ?? "nil")")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self else { return }
            self.finishRecording(noteID: noteID, startDate: startDate)
            await self.runDiarization(samples: samples, noteID: noteID)
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
            if let audioDuration = measuredAudioDuration(for: note) {
                note.duration = audioDuration
            } else if let startDate {
                note.duration = Date().timeIntervalSince(startDate)
            }
            noteStore.save(note)
        }

        isRecording = false
        currentRecordingNoteID = nil
        recordingStartDate = nil
    }

    private func measuredAudioDuration(for note: Note) -> TimeInterval? {
        guard let audioURL = noteStore.audioFileURL(for: note) else { return nil }
        guard let file = try? AVAudioFile(forReading: audioURL) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Double(file.length) / sampleRate
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Called by the view after recording stops to persist the Apple Translation results.
    func saveTranslations(_ translations: [UUID: String], language: String, to noteID: UUID) {
        guard !translations.isEmpty,
              var note = noteStore.notes.first(where: { $0.id == noteID }) else { return }
        note.segmentTranslations = Dictionary(uniqueKeysWithValues: translations.map { ($0.key.uuidString, $0.value) })
        note.translationLanguage = language
        noteStore.save(note)
    }

    func copyToClipboard(segmentTranslations: [UUID: String] = [:], showTranslation: Bool = false) {
        let text = buildCopyText(translations: segmentTranslations, showTranslation: showTranslation)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportAsText(segmentTranslations: [UUID: String] = [:], showTranslation: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? buildCopyText(translations: segmentTranslations, showTranslation: showTranslation)
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func buildCopyText(translations: [UUID: String] = [:], showTranslation: Bool = false) -> String {
        guard showTranslation && !translations.isEmpty else {
            return transcriptionEngine.fullText
        }
        return transcriptionEngine.segments.map { segment in
            var line = segment.text
            if let translation = translations[segment.id] {
                line += "\n" + translation
            }
            return line
        }.joined(separator: "\n\n")
    }

    // MARK: - Speaker Diarization

    private func scheduleLiveDiarization() {
        liveDiarizationTask?.cancel()
        let samples = recordedSamples
        let segments = transcriptionEngine.segments
        liveDiarizationTask = Task { [weak self] in
            // 0.5 s debounce — batch rapid segment arrivals
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.runLiveDiarization(samples: samples, segments: segments)
        }
    }

    private func runLiveDiarization(samples: [Float], segments: [TranscriptSegment]) async {
        guard !samples.isEmpty, !segments.isEmpty else { return }
        logger.info("[Diarization] live update — samples=\(samples.count) segments=\(segments.count)")
        await speakerDiarizationService.loadModelIfNeeded()
        let diarSegments = await speakerDiarizationService.diarize(samples: samples)
        guard !diarSegments.isEmpty else {
            logger.warning("[Diarization] live: no diar segments returned")
            return
        }
        var labels: [UUID: String] = [:]
        for seg in segments {
            let ts = Float(seg.timestamp)
            if let match = diarSegments.first(where: { $0.start <= ts && ts < $0.end }) {
                labels[seg.id] = speakerLabel(from: match.speaker)
            } else if let closest = diarSegments.min(by: { abs($0.start - ts) < abs($1.start - ts) }) {
                labels[seg.id] = speakerLabel(from: closest.speaker)
            }
        }
        logger.info("[Diarization] live: assigned \(labels.count) speaker labels")
        liveSpeakerLabels = labels
    }

    private func runDiarization(samples: [Float], noteID: UUID?) async {
        logger.info("[Diarization] runDiarization — samples=\(samples.count) noteID=\(noteID?.uuidString ?? "nil")")
        guard let noteID else { logger.warning("[Diarization] noteID is nil, aborting"); return }
        guard !samples.isEmpty else { logger.warning("[Diarization] samples is empty, aborting"); return }
        await speakerDiarizationService.loadModelIfNeeded()
        let diarSegments = await speakerDiarizationService.diarize(samples: samples)
        logger.info("[Diarization] diarize returned \(diarSegments.count) segments")
        guard !diarSegments.isEmpty else {
            logger.warning("[Diarization] no diarization segments returned, skipping speaker assignment")
            return
        }
        guard var note = noteStore.notes.first(where: { $0.id == noteID }) else {
            logger.error("[Diarization] note \(noteID.uuidString) not found in store")
            return
        }
        guard var segments = note.segments else {
            logger.warning("[Diarization] note has no segments")
            return
        }
        logger.info("[Diarization] mapping \(diarSegments.count) diar segments → \(segments.count) transcript segments")
        for i in segments.indices {
            let ts = Float(segments[i].timestamp)
            if let match = diarSegments.first(where: { $0.start <= ts && ts < $0.end }) {
                let label = speakerLabel(from: match.speaker)
                logger.info("[Diarization]   seg[\(i)] ts=\(ts, format: .fixed(precision: 2)) → \(label) (match start=\(match.start, format: .fixed(precision: 2)) end=\(match.end, format: .fixed(precision: 2)))")
                segments[i].speaker = label
            } else if let closest = diarSegments.min(by: { abs($0.start - ts) < abs($1.start - ts) }) {
                let label = speakerLabel(from: closest.speaker)
                logger.info("[Diarization]   seg[\(i)] ts=\(ts, format: .fixed(precision: 2)) → \(label) (fallback closest start=\(closest.start, format: .fixed(precision: 2)) end=\(closest.end, format: .fixed(precision: 2)))")
                segments[i].speaker = label
            }
        }
        note.segments = segments
        logger.info("[Diarization] saving note with speaker labels")
        noteStore.save(note)
    }

    private func speakerLabel(from speakerIndex: Int) -> String {
        return "Speaker \(speakerIndex + 1)"
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
