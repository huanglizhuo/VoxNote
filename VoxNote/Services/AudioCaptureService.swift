import Foundation
import AVFoundation
import CoreAudio
import os.log

private let captureLogger = Logger(subsystem: "com.voxnote", category: "AudioCaptureService")

@MainActor
class AudioCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFileWriter: AudioFileWriter?
    private var outputFileURL: URL?
    private let asrSampleRate: Double = 16000
    private let resampleQueue = DispatchQueue(label: "com.voxnote.resample", qos: .userInitiated)

    func startCapture(deviceID: AudioDeviceID? = nil, outputFileURL: URL? = nil, onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        stop()

        self.outputFileURL = outputFileURL

        let engine = AVAudioEngine()
        audioEngine = engine

        // Set specific input device if provided (e.g. BlackHole)
        if let deviceID = deviceID {
            captureLogger.info("startCapture requested with deviceID=\(deviceID)")
            guard let audioUnit = engine.inputNode.audioUnit else {
                throw CaptureError.deviceNotFound
            }
            var devID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                captureLogger.error("AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice) failed status=\(status)")
                throw CaptureError.deviceNotFound
            }
        }

        let captureNode = engine.inputNode
        let tapFormat = captureNode.inputFormat(forBus: 0)
        captureLogger.info("capture node=inputNode tapFormat sr=\(tapFormat.sampleRate, format: .fixed(precision: 0)) ch=\(tapFormat.channelCount) interleaved=\(tapFormat.isInterleaved)")

        if let outputFileURL {
            // Save with the captured device format (sample rate + channel count).
            audioFileWriter = try AudioFileWriter(
                outputURL: outputFileURL,
                sampleRate: tapFormat.sampleRate,
                channels: tapFormat.channelCount
            )
            captureLogger.info("file writer configured path=\(outputFileURL.path, privacy: .public) sr=\(tapFormat.sampleRate, format: .fixed(precision: 0)) ch=\(tapFormat.channelCount)")
        } else {
            audioFileWriter = nil
        }

        guard let asrTargetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asrSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.formatError
        }

        // Create a mono intermediate format at the input sample rate for resampling
        guard let monoInputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: tapFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.formatError
        }

        let asrConverter = AVAudioConverter(from: monoInputFormat, to: asrTargetFormat)
        // Pre-allocate reusable output buffers for resampling (serial queue ensures safety)
        let maxInputFrames: AVAudioFrameCount = 8192

        let asrRatio = asrSampleRate / tapFormat.sampleRate
        let maxAsrOutputFrames = AVAudioFrameCount(Double(maxInputFrames) * asrRatio) + 16
        let reusableAsrOutputBuffer = AVAudioPCMBuffer(pcmFormat: asrTargetFormat, frameCapacity: maxAsrOutputFrames)

        // Throttle level updates to ~15Hz
        var lastLevelTime: CFAbsoluteTime = 0
        var loggedBufferFormat = false
        var peakLogCount = 0
        var fileGainLogCount = 0

        // Tap callback runs on audio render thread.
        // Use explicit tapFormat to avoid runtime sample-rate mismatch between writer config and delivered buffers.
        captureNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self, resampleQueue] buffer, _ in
            if !loggedBufferFormat {
                loggedBufferFormat = true
                captureLogger.info("first tap buffer format sr=\(buffer.format.sampleRate, format: .fixed(precision: 0)) ch=\(buffer.format.channelCount) interleaved=\(buffer.format.isInterleaved) frames=\(buffer.frameLength)")
            }
            // Pick the dominant channel instead of always channel 0 (important for BlackHole 16ch / right-only audio).
            guard let inputSamples = Self.extractDominantMonoSamples(from: buffer) else { return }
            let frameCount = inputSamples.count
            guard frameCount > 0 else { return }

            // Calculate RMS level from selected mono samples (cheap math — ok on audio thread).
            var rms: Float = 0
            var peak: Float = 0
            for i in 0..<frameCount {
                let sample = inputSamples[i]
                rms += sample * sample
                peak = max(peak, abs(sample))
            }
            rms = sqrt(rms / Float(frameCount))
            if peakLogCount < 5 {
                peakLogCount += 1
                captureLogger.info("tap level snapshot peak=\(peak, format: .fixed(precision: 5)) rms=\(rms, format: .fixed(precision: 5)) frames=\(frameCount)")
            }

            let now = CFAbsoluteTimeGetCurrent()
            if now - lastLevelTime >= 0.066 { // ~15Hz
                lastLevelTime = now
                DispatchQueue.main.async {
                    self?.audioLevel = rms
                }
            }

            // Copy captured channels for file writing on a background queue.
            let rawFileChannelSamples = Self.extractChannelSamples(from: buffer)

            resampleQueue.async { [weak self] in
                guard let asrConverter = asrConverter,
                      let asrOutputBuffer = reusableAsrOutputBuffer else { return }

                if var fileChannelSamples = rawFileChannelSamples {
                    // BlackHole captures can be extremely quiet; boost file path only.
                    let gain = Self.computeFileGain(for: fileChannelSamples)
                    if gain > 1.01 {
                        for channel in 0..<fileChannelSamples.count {
                            for i in 0..<fileChannelSamples[channel].count {
                                let boosted = fileChannelSamples[channel][i] * gain
                                fileChannelSamples[channel][i] = min(max(boosted, -1), 1)
                            }
                        }
                    }
                    if fileGainLogCount < 5 {
                        fileGainLogCount += 1
                        captureLogger.info("file path gain=\(gain, format: .fixed(precision: 2))")
                    }
                    self?.audioFileWriter?.write(channelSamples: fileChannelSamples)
                }

                // Create a mono input buffer from the selected dominant channel.
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: monoInputFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
                inputBuffer.frameLength = AVAudioFrameCount(frameCount)
                if let dest = inputBuffer.floatChannelData?[0] {
                    inputSamples.withUnsafeBufferPointer { src in
                        _ = memcpy(dest, src.baseAddress!, frameCount * MemoryLayout<Float>.size)
                    }
                }

                // Resample to 16kHz for ASR (file saving stays in original device format).
                let asrOutputFrameCount = AVAudioFrameCount(Double(frameCount) * asrRatio) + 16
                asrOutputBuffer.frameLength = 0

                var asrConsumed = false
                let asrInputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    if asrConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    asrConsumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                if asrOutputFrameCount <= asrOutputBuffer.frameCapacity {
                    var conversionError: NSError?
                    asrConverter.convert(to: asrOutputBuffer, error: &conversionError, withInputFrom: asrInputBlock)

                    if conversionError == nil,
                       let data = asrOutputBuffer.floatChannelData?[0],
                       asrOutputBuffer.frameLength > 0 {
                        let asrSamples = Array(UnsafeBufferPointer(start: data, count: Int(asrOutputBuffer.frameLength)))
                        onSamples(asrSamples)
                    }
                }
            }
        }

        try engine.start()
        captureLogger.info("AVAudioEngine started successfully")
        isCapturing = true
    }

    func stop() {
        if let engine = audioEngine {
            let captureNode = engine.mainMixerNode.numberOfInputs > 0 ? engine.mainMixerNode : engine.inputNode
            captureNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        resampleQueue.sync {
            audioFileWriter?.close()
            audioFileWriter = nil
        }
        isCapturing = false
        audioLevel = 0

        // Normalize the created file seamlessly in the background
        if let fileURL = outputFileURL {
            Task.detached {
                do {
                    try await AudioNormalizer.normalize(fileURL: fileURL)
                } catch {
                    print("Normalization failed: \(error)")
                }
            }
        }
    }

    private nonisolated static func extractDominantMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return nil }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        // Most CoreAudio capture formats here are non-interleaved Float32.
        if !buffer.format.isInterleaved {
            var bestChannel = 0
            var bestEnergy: Float = -.greatestFiniteMagnitude
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                var energy: Float = 0
                for s in samples {
                    energy += s * s
                }
                if energy > bestEnergy {
                    bestEnergy = energy
                    bestChannel = channel
                }
            }
            return Array(UnsafeBufferPointer(start: channelData[bestChannel], count: frameCount))
        }

        // Fallback for interleaved buffers: pick the channel with highest energy.
        let interleaved = UnsafeBufferPointer(start: channelData[0], count: frameCount * channelCount)
        var energies = [Float](repeating: 0, count: channelCount)
        for frame in 0..<frameCount {
            let base = frame * channelCount
            for channel in 0..<channelCount {
                let sample = interleaved[base + channel]
                energies[channel] += sample * sample
            }
        }
        guard let bestChannel = energies.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return nil
        }
        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            mono[frame] = interleaved[frame * channelCount + bestChannel]
        }
        return mono
    }

    private nonisolated static func extractChannelSamples(from buffer: AVAudioPCMBuffer) -> [[Float]]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return nil }

        if !buffer.format.isInterleaved {
            return (0..<channelCount).map { channel in
                Array(UnsafeBufferPointer(start: channelData[channel], count: frameCount))
            }
        }

        let interleaved = UnsafeBufferPointer(start: channelData[0], count: frameCount * channelCount)
        var channels = Array(repeating: [Float](repeating: 0, count: frameCount), count: channelCount)
        for frame in 0..<frameCount {
            let base = frame * channelCount
            for channel in 0..<channelCount {
                channels[channel][frame] = interleaved[base + channel]
            }
        }
        return channels
    }

    private nonisolated static func computeFileGain(for channels: [[Float]]) -> Float {
        var peak: Float = 0
        for channel in channels {
            for sample in channel {
                peak = max(peak, abs(sample))
            }
        }
        guard peak > 0 else { return 1 }
        let targetPeak: Float = 0.25
        let maxGain: Float = 64
        return min(max(targetPeak / peak, 1), maxGain)
    }

    enum CaptureError: LocalizedError {
        case formatError
        case deviceNotFound

        var errorDescription: String? {
            switch self {
            case .formatError: return "Failed to create audio format."
            case .deviceNotFound: return "Audio device not found or unavailable."
            }
        }
    }
}
