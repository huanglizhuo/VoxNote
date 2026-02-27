import Foundation
import MLXAudioSTT
import MLXAudioCore
import MLX
import MLXAudioVAD

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
    private let fileASRSampleRate = 16_000
    private let forcedAlignerRepoID = "mlx-community/Qwen3-ForcedAligner-0.6B-8bit"

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
        let targetSampleRate = fileASRSampleRate
        let output = try await Task.detached {
            let (_, audio) = try loadAudioArray(from: url, sampleRate: targetSampleRate)
            let params = STTGenerateParameters(language: language)
            return capturedModel.generate(audio: audio, generationParameters: params)
        }.value

        tokensPerSecond = output.generationTps
        confirmedText = TranscriptFormatter.applyLineBreaks(to: output.text)
        return confirmedText
    }

    func transcribeFileWithForcedAlignment(
        url: URL,
        language: String = "auto",
        alignerLanguage: String = "auto"
    ) async throws -> (text: String, segments: [TranscriptSegment]) {
        guard let model else { throw TranscriptionError.modelNotLoaded }

        isTranscribing = true
        confirmedText = ""
        provisionalText = ""

        defer { isTranscribing = false }

        let capturedModel = model
        let targetSampleRate = fileASRSampleRate
        
        let (_, originalAudioArray) = try await Task.detached {
            try loadAudioArray(from: url, sampleRate: targetSampleRate)
        }.value
        let totalSamples = originalAudioArray.shape[0]
        // 4 minutes (240 seconds) to avoid 5 minute hard limit
        let maxChunkSamples = 240 * targetSampleRate 
        
        let alignerRepo = forcedAlignerRepoID
        var allFormattedText = ""
        var allAlignments: [LocalAlignItem] = []
        
        if totalSamples <= maxChunkSamples {
            // Short enough to process normally
            let (output, alignment) = try await Task.detached {
                let params = STTGenerateParameters(language: language)
                let output = capturedModel.generate(audio: originalAudioArray, generationParameters: params)
                let formattedText = TranscriptFormatter.applyLineBreaks(to: output.text)
                
                let aligner = try await Qwen3ForcedAlignerModel.fromPretrained(alignerRepo)
                let alignment = aligner.generate(audio: originalAudioArray, text: formattedText, language: alignerLanguage)
                return (output, alignment)
            }.value
            
            tokensPerSecond = output.generationTps
            allFormattedText = output.text // applyLineBreaks is done below dynamically
            
            allAlignments = alignment.items.map { 
                LocalAlignItem(text: $0.text, startTime: $0.startTime, endTime: $0.endTime) 
            }
        } else {
            // Chunking via SmartTurn
            var chunks: [(startTime: TimeInterval, audio: MLXArray)] = []
            
            let smartTurnModel = try await Task.detached {
                try await SmartTurnModel.fromPretrained("mlx-community/smart-turn-v3")
            }.value
            
            var currentStart = 0
            while currentStart < totalSamples {
                let remaining = totalSamples - currentStart
                if remaining <= maxChunkSamples {
                    chunks.append((
                        startTime: TimeInterval(currentStart) / TimeInterval(targetSampleRate),
                        audio: originalAudioArray[currentStart..<totalSamples]
                    ))
                    break
                }
                
                let searchEnd = currentStart + maxChunkSamples
                let searchDurationSamples = 60 * targetSampleRate // 60s backwards scan window
                let searchStart = max(currentStart + 10 * targetSampleRate, searchEnd - searchDurationSamples)
                
                var splitPoint = searchEnd
                var candidateEnd = searchEnd
                let step = 2 * targetSampleRate // 2 seconds scan increment
                
                while candidateEnd > searchStart {
                    // SmartTurn takes the latest 8 seconds of what it's given
                    let windowStart = max(currentStart, candidateEnd - 8 * targetSampleRate)
                    let mlxSlice = originalAudioArray[windowStart..<candidateEnd]
                    
                    let result = try await Task.detached {
                        try smartTurnModel.predictEndpoint(mlxSlice, sampleRate: targetSampleRate, threshold: 0.5)
                    }.value
                    
                    if result.prediction == 1 {
                        splitPoint = candidateEnd
                        break
                    }
                    candidateEnd -= step
                }
                
                chunks.append((
                    startTime: TimeInterval(currentStart) / TimeInterval(targetSampleRate),
                    audio: originalAudioArray[currentStart..<splitPoint]
                ))
                currentStart = splitPoint
            }
            
            // Process chunks sequentially to keep unified memory healthy
            let aligner = try await Task.detached {
                try await Qwen3ForcedAlignerModel.fromPretrained(alignerRepo)
            }.value
            
            for chunk in chunks {
                let (output, alignments, tps) = try await Task.detached {
                    let params = STTGenerateParameters(language: language)
                    let output = capturedModel.generate(audio: chunk.audio, generationParameters: params)
                    let formattedText = TranscriptFormatter.applyLineBreaks(to: output.text)
                    
                    let alignmentResult = aligner.generate(audio: chunk.audio, text: formattedText, language: alignerLanguage)
                    
                    let shifted = alignmentResult.items.map {
                        LocalAlignItem(
                            text: $0.text,
                            startTime: $0.startTime + chunk.startTime,
                            endTime: $0.endTime + chunk.startTime
                        )
                    }
                    return (output.text, shifted, output.generationTps)
                }.value
                
                if !allFormattedText.isEmpty {
                    allFormattedText += " "
                }
                allFormattedText += output
                allAlignments.append(contentsOf: alignments)
                
                await MainActor.run {
                    self.tokensPerSecond = tps
                    self.confirmedText = TranscriptFormatter.applyLineBreaks(to: allFormattedText)
                }
            }
        }

        let formattedAndBreakedText = TranscriptFormatter.applyLineBreaks(to: allFormattedText)
        confirmedText = formattedAndBreakedText

        return (text: formattedAndBreakedText, segments: alignedSegments(from: allAlignments))
    }

    // MARK: - File Transcription (Streaming tokens)

    func transcribeFileStreaming(url: URL, language: String = "auto") async throws {
        guard let model else { throw TranscriptionError.modelNotLoaded }

        isTranscribing = true
        confirmedText = ""
        provisionalText = ""

        let capturedModel = model
        let targetSampleRate = fileASRSampleRate
        let (audio, stream) = try await Task.detached {
            let (_, audio) = try loadAudioArray(from: url, sampleRate: targetSampleRate)
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

    private struct LocalAlignItem {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private func alignedSegments(from items: [LocalAlignItem]) -> [TranscriptSegment] {
        guard !items.isEmpty else { return [] }

        var segments: [TranscriptSegment] = []
        var currentWords: [String] = []
        var currentStart: TimeInterval?
        var lastEnd: TimeInterval = 0

        func flushCurrent() {
            guard let start = currentStart else { return }
            let text = currentWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                currentWords = []
                currentStart = nil
                return
            }
            segments.append(TranscriptSegment(timestamp: start, text: text))
            currentWords = []
            currentStart = nil
        }

        for item in items {
            let cleaned = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if currentStart == nil {
                currentStart = item.startTime
            }

            let gap = item.startTime - lastEnd
            if !currentWords.isEmpty && (currentWords.count >= 10 || gap > 1.5) {
                flushCurrent()
                currentStart = item.startTime
            }

            currentWords.append(cleaned)
            lastEnd = item.endTime
        }

        flushCurrent()
        return segments
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
