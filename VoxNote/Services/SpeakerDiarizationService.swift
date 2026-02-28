import Foundation
import MLXAudioVAD
import MLX
import os.log

@MainActor
class SpeakerDiarizationService: ObservableObject {
    @Published var isRunning = false
    @Published var error: String?

    private let logger = Logger(subsystem: "com.voxnote", category: "Diarization")
    private var model: SortformerModel?
    private let repoID = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"

    func loadModelIfNeeded() async {
        guard model == nil else {
            logger.info("[Diarization] model already loaded, skipping")
            return
        }
        logger.info("[Diarization] loading model: \(self.repoID)")
        do {
            let repoID = self.repoID
            model = try await Task.detached {
                try await SortformerModel.fromPretrained(repoID)
            }.value
            logger.info("[Diarization] model loaded successfully")
        } catch {
            logger.error("[Diarization] model load failed: \(error)")
            self.error = "Diarization model failed to load: \(error.localizedDescription)"
        }
    }

    func diarize(samples: [Float], sampleRate: Int = 16_000) async -> [DiarizationSegment] {
        logger.info("[Diarization] diarize() called — samples=\(samples.count) sampleRate=\(sampleRate) modelLoaded=\(self.model != nil)")
        guard let model else {
            logger.warning("[Diarization] model is nil, returning empty")
            return []
        }
        guard !isRunning else {
            logger.info("[Diarization] already running, skipping this call")
            return []
        }
        isRunning = true
        defer { isRunning = false }
        do {
            let audio = MLXArray(samples)
            logger.info("[Diarization] running generate()…")
            let result = try await Task.detached { [audio] in
                try await model.generate(audio: audio, sampleRate: sampleRate, threshold: 0.5)
            }.value
            logger.info("[Diarization] generate() done — segments=\(result.segments.count) numSpeakers=\(result.numSpeakers)")
            for seg in result.segments {
                logger.info("[Diarization]   speaker=\(seg.speaker) start=\(seg.start, format: .fixed(precision: 2)) end=\(seg.end, format: .fixed(precision: 2))")
            }
            return result.segments
        } catch {
            logger.error("[Diarization] generate() failed: \(error)")
            self.error = "Diarization failed: \(error.localizedDescription)"
            return []
        }
    }
}
