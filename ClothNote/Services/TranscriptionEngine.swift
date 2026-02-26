import Foundation
import MLXAudioSTT
import MLXAudioCore
import MLX

@MainActor
class TranscriptionEngine: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isTranscribing = false
    @Published var confirmedText = ""
    @Published var provisionalText = ""
    @Published var tokensPerSecond: Double = 0
    @Published var loadingModel = false
    @Published var activeSource: NoteSource?
    @Published var segments: [TranscriptSegment] = []
    @Published var unsegmentedText = ""

    private var model: Qwen3ASRModel?
    private var currentRepoID: String?

    // Thread-safe session access for feedAudio from audio thread
    private let _sessionRef = SessionRef()

    private final class SessionRef: @unchecked Sendable {
        var session: StreamingInferenceSession?
    }

    private var streamingSession: StreamingInferenceSession? {
        get { _sessionRef.session }
        set { _sessionRef.session = newValue }
    }

    // Segment tracking state
    private var lastRawConfirmed = ""
    private var lastFormattedConfirmed = ""
    private var lastSegmentedLength = 0
    private var recordingStartDate: Date?

    // MARK: - Model Loading

    func loadModel(repoID: String) async throws {
        if currentRepoID == repoID && model != nil { return }

        loadingModel = true
        defer { loadingModel = false }

        // Unload previous model
        model = nil
        currentRepoID = nil
        isModelLoaded = false

        let loaded = try await Task.detached {
            try await Qwen3ASRModel.fromPretrained(repoID)
        }.value
        model = loaded
        currentRepoID = repoID
        isModelLoaded = true
    }

    func unloadModel() {
        model = nil
        currentRepoID = nil
        isModelLoaded = false
    }

    // MARK: - File Transcription (Batch)

    func transcribeFile(url: URL, language: String = "auto") async throws -> String {
        guard let model else { throw TranscriptionError.modelNotLoaded }

        isTranscribing = true
        confirmedText = ""
        provisionalText = ""

        defer { isTranscribing = false }

        let capturedModel = model
        let output = try await Task.detached {
            let (_, audio) = try loadAudioArray(from: url)
            let params = STTGenerateParameters(language: language)
            return capturedModel.generate(audio: audio, generationParameters: params)
        }.value

        tokensPerSecond = output.generationTps
        confirmedText = TranscriptFormatter.applyLineBreaks(to: output.text)
        return confirmedText
    }

    // MARK: - File Transcription (Streaming tokens)

    func transcribeFileStreaming(url: URL, language: String = "auto") async throws {
        guard let model else { throw TranscriptionError.modelNotLoaded }

        isTranscribing = true
        confirmedText = ""
        provisionalText = ""

        let capturedModel = model
        let (audio, stream) = try await Task.detached {
            let (_, audio) = try loadAudioArray(from: url)
            let params = STTGenerateParameters(language: language)
            let stream = capturedModel.generateStream(audio: audio, generationParameters: params)
            return (audio, stream)
        }.value

        _ = audio // audio retained by stream
        for try await event in stream {
            switch event {
            case .token(let token):
                confirmedText += token
            case .info:
                break
            case .result(let output):
                confirmedText = TranscriptFormatter.applyLineBreaks(to: output.text)
                tokensPerSecond = output.generationTps
            }
        }

        confirmedText = TranscriptFormatter.applyLineBreaks(to: confirmedText)
        isTranscribing = false
    }

    // MARK: - Real-time Streaming

    func startStreamingTranscription(source: NoteSource, language: String = "auto") throws {
        guard let model else { throw TranscriptionError.modelNotLoaded }
        guard activeSource == nil else { throw TranscriptionError.alreadyRecording }

        confirmedText = ""
        provisionalText = ""
        isTranscribing = true
        activeSource = source
        segments = []
        unsegmentedText = ""
        lastRawConfirmed = ""
        lastFormattedConfirmed = ""
        lastSegmentedLength = 0
        recordingStartDate = Date()

        let config = StreamingConfig(
            delayPreset: .realtime,
            language: language
        )

        let session = StreamingInferenceSession(model: model, config: config)
        streamingSession = session

        Task { [weak self] in
            for await event in session.events {
                guard let self else { break }
                switch event {
                case .displayUpdate(let confirmed, let provisional):
                    self.updateConfirmedText(confirmed)
                    self.updateSegments(rawConfirmed: confirmed)
                    if self.provisionalText != provisional {
                        self.provisionalText = provisional
                    }
                case .confirmed(let text):
                    self.updateConfirmedText(text)
                    self.updateSegments(rawConfirmed: text)
                case .provisional(let text):
                    if self.provisionalText != text {
                        self.provisionalText = text
                    }
                case .stats(let stats):
                    self.tokensPerSecond = stats.tokensPerSecond
                case .ended(let fullText):
                    self.updateConfirmedText(fullText)
                    self.flushRemainingSegment(rawConfirmed: fullText)
                    self.unsegmentedText = ""
                    self.provisionalText = ""
                    self.isTranscribing = false
                    self.activeSource = nil
                }
            }
        }
    }

    /// Feed audio samples from the audio capture thread. Thread-safe.
    nonisolated func feedAudio(samples: [Float]) {
        _sessionRef.session?.feedAudio(samples: samples)
    }

    func stopStreaming() {
        streamingSession?.stop()
        streamingSession = nil
        // activeSource cleared by .ended event; clear as fallback
        if !isTranscribing {
            activeSource = nil
        }
    }

    func cancelStreaming() {
        streamingSession?.cancel()
        streamingSession = nil
        isTranscribing = false
        activeSource = nil
    }

    // MARK: - Confirmed Text Caching

    private func updateConfirmedText(_ rawConfirmed: String) {
        guard rawConfirmed != lastRawConfirmed else { return }
        lastRawConfirmed = rawConfirmed
        let formatted = TranscriptFormatter.applyLineBreaks(to: rawConfirmed)
        if formatted != lastFormattedConfirmed {
            lastFormattedConfirmed = formatted
            confirmedText = formatted
        }
    }

    // MARK: - Segment Tracking

    private func updateSegments(rawConfirmed: String) {
        guard rawConfirmed.count > lastSegmentedLength else { return }

        let newText = String(rawConfirmed.suffix(rawConfirmed.count - lastSegmentedLength))
        let sentences = TranscriptFormatter.splitIntoSentences(newText)

        guard !sentences.isEmpty else { return }

        let timestamp = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0

        // Only create segments for sentences that end in punctuation (complete sentences)
        // Hold back the last sentence if it doesn't end in punctuation
        let punctuationEndings = CharacterSet(charactersIn: ".!?。！？")
        var consumedLength = 0

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lastChar = trimmed.unicodeScalars.last,
                  punctuationEndings.contains(lastChar) else {
                // Incomplete sentence — don't consume it
                break
            }
            let segment = TranscriptSegment(timestamp: timestamp, text: trimmed)
            segments.append(segment)
            consumedLength += sentence.count
        }

        if consumedLength > 0 {
            // Advance lastSegmentedLength by the characters we consumed from rawConfirmed
            // We need to account for whitespace between sentences in the original text
            let consumedFromRaw = rawConfirmed.suffix(rawConfirmed.count - lastSegmentedLength)
            var remaining = String(consumedFromRaw)
            for sentence in sentences {
                guard !sentence.isEmpty else { continue }
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let lastChar = trimmed.unicodeScalars.last,
                      punctuationEndings.contains(lastChar) else {
                    break
                }
                if let range = remaining.range(of: trimmed) {
                    let advanceEnd = range.upperBound
                    // Also consume trailing whitespace
                    var endIdx = advanceEnd
                    while endIdx < remaining.endIndex && remaining[endIdx].isWhitespace {
                        endIdx = remaining.index(after: endIdx)
                    }
                    lastSegmentedLength += remaining.distance(from: remaining.startIndex, to: endIdx)
                    remaining = String(remaining[endIdx...])
                }
            }
        }

        // Update unsegmented tail (confirmed text not yet in a segment)
        let tail = rawConfirmed.count > lastSegmentedLength
            ? String(rawConfirmed.suffix(rawConfirmed.count - lastSegmentedLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        if unsegmentedText != tail {
            unsegmentedText = tail
        }
    }

    private func flushRemainingSegment(rawConfirmed: String) {
        guard rawConfirmed.count > lastSegmentedLength else { return }

        let remaining = String(rawConfirmed.suffix(rawConfirmed.count - lastSegmentedLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !remaining.isEmpty else { return }

        let timestamp = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let sentences = TranscriptFormatter.splitIntoSentences(remaining)

        if sentences.isEmpty {
            // Single unsplit chunk
            let segment = TranscriptSegment(timestamp: timestamp, text: remaining)
            segments.append(segment)
        } else {
            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let segment = TranscriptSegment(timestamp: timestamp, text: trimmed)
                segments.append(segment)
            }
        }
        lastSegmentedLength = rawConfirmed.count
    }

    // MARK: - Helpers

    var fullText: String {
        if provisionalText.isEmpty {
            return confirmedText
        }
        return confirmedText + provisionalText
    }

    enum TranscriptionError: LocalizedError {
        case modelNotLoaded
        case alreadyRecording
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "No model is loaded. Please download and select a model first."
            case .alreadyRecording:
                return "Another recording is already in progress. Stop it first."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }
}
