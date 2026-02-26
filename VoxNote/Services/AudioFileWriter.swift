import Foundation
import AVFoundation

class AudioFileWriter {
    private var audioFile: AVAudioFile?
    private let format: AVAudioFormat

    init(outputURL: URL, sampleRate: Double = 48000) throws {
        // The internal buffer will work with float32 samples.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileWriterError.formatError
        }

        // The file on disk will be written as standard 16-bit PCM.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        self.format = format
        self.audioFile = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(samples: [Float]) {
        guard let audioFile = audioFile else { return }
        guard !samples.isEmpty else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                _ = memcpy(channelData, src.baseAddress!, samples.count * MemoryLayout<Float>.size)
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
