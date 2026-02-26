import Foundation
import AVFoundation
import CoreAudio

@MainActor
class AudioCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFileWriter: AudioFileWriter?
    private var outputFileURL: URL?
    private let asrSampleRate: Double = 16000
    private let fileSampleRate: Double = 48000
    private let resampleQueue = DispatchQueue(label: "com.voxnote.resample", qos: .userInitiated)

    func startCapture(deviceID: AudioDeviceID? = nil, outputFileURL: URL? = nil, onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        stop()

        if let outputFileURL {
            self.outputFileURL = outputFileURL
            audioFileWriter = try AudioFileWriter(outputURL: outputFileURL, sampleRate: fileSampleRate)
        } else {
            self.outputFileURL = nil
        }

        let engine = AVAudioEngine()
        audioEngine = engine

        // Set specific input device if provided (e.g. BlackHole)
        if let deviceID = deviceID {
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
                throw CaptureError.deviceNotFound
            }
            
            // Re-query the input format after assigning the device
            // to ensure AVAudioEngine picks up the 16ch/48kHz structure
            let newHWFormat = engine.inputNode.inputFormat(forBus: 0)
            
            // Connect the input node to the main mixer node.
            // This forces the engine to build a graph that naturally downmixes 16 channels to standard stereo/mono
            let mixer = engine.mainMixerNode
            engine.connect(engine.inputNode, to: mixer, format: newHWFormat)
        }

        let captureNode = deviceID == nil ? engine.inputNode : engine.mainMixerNode
        let tapFormat = captureNode.outputFormat(forBus: 0) // Dynamically grab the real format, avoiding hardware mismatch

        guard let asrTargetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asrSampleRate,
            channels: 1,
            interleaved: false
        ), let fileTargetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: fileSampleRate,
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
        let fileConverter = AVAudioConverter(from: monoInputFormat, to: fileTargetFormat)

        // Pre-allocate reusable output buffers for resampling (serial queue ensures safety)
        let maxInputFrames: AVAudioFrameCount = 8192

        let asrRatio = asrSampleRate / tapFormat.sampleRate
        let maxAsrOutputFrames = AVAudioFrameCount(Double(maxInputFrames) * asrRatio) + 16
        let reusableAsrOutputBuffer = AVAudioPCMBuffer(pcmFormat: asrTargetFormat, frameCapacity: maxAsrOutputFrames)

        let fileRatio = fileSampleRate / tapFormat.sampleRate
        let maxFileOutputFrames = AVAudioFrameCount(Double(maxInputFrames) * fileRatio) + 16
        let reusableFileOutputBuffer = AVAudioPCMBuffer(pcmFormat: fileTargetFormat, frameCapacity: maxFileOutputFrames)

        // Throttle level updates to ~15Hz
        var lastLevelTime: CFAbsoluteTime = 0

        // Tap callback runs on audio render thread (use nil format so Engine supplies actual mixer node format dynamically)
        captureNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self, resampleQueue] buffer, _ in
            // Calculate RMS level (cheap math — ok on audio thread)
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return }
                var rms: Float = 0
                for i in 0..<frameLength {
                    rms += channelData[i] * channelData[i]
                }
                rms = sqrt(rms / Float(frameLength))

                let now = CFAbsoluteTimeGetCurrent()
                if now - lastLevelTime >= 0.066 { // ~15Hz
                    lastLevelTime = now
                    DispatchQueue.main.async {
                        self?.audioLevel = rms
                    }
                }
            }

            // Copy channel 0 data on audio thread, then dispatch resampling to background
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            let inputSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            resampleQueue.async { [weak self] in
                guard let asrConverter = asrConverter,
                      let asrOutputBuffer = reusableAsrOutputBuffer,
                      let fileConverter = fileConverter,
                      let fileOutputBuffer = reusableFileOutputBuffer else { return }

                // Create a mono input buffer from copied channel-0 samples
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: monoInputFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
                inputBuffer.frameLength = AVAudioFrameCount(frameCount)
                if let dest = inputBuffer.floatChannelData?[0] {
                    inputSamples.withUnsafeBufferPointer { src in
                        _ = memcpy(dest, src.baseAddress!, frameCount * MemoryLayout<Float>.size)
                    }
                }

                // --- 1. Resample to 48kHz for File Writing ---
                let fileOutputFrameCount = AVAudioFrameCount(Double(frameCount) * fileRatio) + 16
                fileOutputBuffer.frameLength = 0

                var fileConsumed = false
                let fileInputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    if fileConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    fileConsumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                if fileOutputFrameCount <= fileOutputBuffer.frameCapacity {
                    var conversionError: NSError?
                    fileConverter.convert(to: fileOutputBuffer, error: &conversionError, withInputFrom: fileInputBlock)

                    if conversionError == nil,
                       let data = fileOutputBuffer.floatChannelData?[0],
                       fileOutputBuffer.frameLength > 0 {
                        let fileSamples = Array(UnsafeBufferPointer(start: data, count: Int(fileOutputBuffer.frameLength)))
                        self?.audioFileWriter?.write(samples: fileSamples)
                    }
                }

                // --- 2. Resample to 16kHz for ASR ---
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
