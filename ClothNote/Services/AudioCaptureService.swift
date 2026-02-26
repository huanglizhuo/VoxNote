import Foundation
import AVFoundation
import CoreAudio

@MainActor
class AudioCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFileWriter: AudioFileWriter?
    private let targetSampleRate: Double = 16000
    private let resampleQueue = DispatchQueue(label: "com.clothnote.resample", qos: .userInitiated)

    func startCapture(deviceID: AudioDeviceID? = nil, outputFileURL: URL? = nil, onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        stop()

        if let outputFileURL {
            audioFileWriter = try AudioFileWriter(outputURL: outputFileURL)
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
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetSR = targetSampleRate

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSR,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.formatError
        }

        // Create a mono intermediate format at the input sample rate for resampling
        guard let monoInputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.formatError
        }

        let converter = AVAudioConverter(from: monoInputFormat, to: targetFormat)

        // Pre-allocate reusable output buffer for resampling (serial queue ensures safety)
        let ratio = targetSR / inputFormat.sampleRate
        let maxInputFrames: AVAudioFrameCount = 8192
        let maxOutputFrames = AVAudioFrameCount(Double(maxInputFrames) * ratio) + 16
        let reusableOutputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: maxOutputFrames)

        // Throttle level updates to ~15Hz
        var lastLevelTime: CFAbsoluteTime = 0

        // Tap callback runs on audio render thread
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, resampleQueue] buffer, _ in
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
                guard let converter = converter,
                      let outputBuffer = reusableOutputBuffer else { return }

                // Create a mono input buffer from copied channel-0 samples
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: monoInputFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
                inputBuffer.frameLength = AVAudioFrameCount(frameCount)
                if let dest = inputBuffer.floatChannelData?[0] {
                    inputSamples.withUnsafeBufferPointer { src in
                        _ = memcpy(dest, src.baseAddress!, frameCount * MemoryLayout<Float>.size)
                    }
                }

                let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio) + 16
                outputBuffer.frameLength = 0

                var conversionError: NSError?
                var consumed = false
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                if outputFrameCount <= outputBuffer.frameCapacity {
                    converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

                    if conversionError == nil,
                       let data = outputBuffer.floatChannelData?[0],
                       outputBuffer.frameLength > 0 {
                        let samples = Array(UnsafeBufferPointer(start: data, count: Int(outputBuffer.frameLength)))
                        self?.audioFileWriter?.write(samples: samples)
                        onSamples(samples)
                    }
                }
            }
        }

        try engine.start()
        isCapturing = true
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        resampleQueue.sync {
            audioFileWriter?.close()
            audioFileWriter = nil
        }
        isCapturing = false
        audioLevel = 0
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
