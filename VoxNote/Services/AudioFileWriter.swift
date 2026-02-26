import Foundation
import AVFoundation

class AudioFileWriter {
    private var audioFile: AVAudioFile?
    private let format: AVAudioFormat

    init(outputURL: URL, sampleRate: Double, channels: AVAudioChannelCount) throws {
        // The internal buffer will work with float32 samples.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            throw AudioFileWriterError.formatError
        }

        // The file on disk will be written as standard 16-bit PCM.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        self.format = format
        self.audioFile = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: true)
    }

    func write(samples: [Float]) {
        write(channelSamples: [samples])
    }

    func write(channelSamples: [[Float]]) {
        guard let audioFile = audioFile else { return }
        guard !channelSamples.isEmpty else { return }
        guard channelSamples.count == Int(format.channelCount) else { return }

        let frameCount = channelSamples[0].count
        guard frameCount > 0 else { return }
        guard channelSamples.allSatisfy({ $0.count == frameCount }) else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let interleavedData = buffer.floatChannelData?[0] else { return }
        let channelCount = channelSamples.count

        if channelCount == 1 {
            channelSamples[0].withUnsafeBufferPointer { src in
                _ = memcpy(interleavedData, src.baseAddress!, frameCount * MemoryLayout<Float>.size)
            }
        } else {
            for frame in 0..<frameCount {
                let base = frame * channelCount
                for channel in 0..<channelCount {
                    interleavedData[base + channel] = channelSamples[channel][frame]
                }
            }
        }

        try? audioFile.write(from: buffer)
    }

    func close() {
        audioFile = nil
    }

    enum AudioFileWriterError: LocalizedError {
        case formatError

        var errorDescription: String? {
            switch self {
            case .formatError: return "Failed to create audio format for file writing."
            }
        }
    }
}
