import Foundation
import Accelerate
import AVFoundation

class AudioNormalizer {
    static func normalize(fileURL: URL) async throws {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NormalizationError.bufferCreation
        }
        
        try file.read(into: buffer)
        
        guard let channelData = buffer.floatChannelData else {
            throw NormalizationError.missingChannelData
        }
        
        let channelCount = Int(format.channelCount)
        let length = vDSP_Length(buffer.frameLength)
        
        // 1. Find the maximum absolute value across all channels
        var globalMaxAmp: Float = 0.0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            var maxVal: Float = 0.0
            vDSP_maxmgv(data, 1, &maxVal, length)
            globalMaxAmp = max(globalMaxAmp, maxVal)
        }
        
        // Avoid division by zero if audio is completely silent
        guard globalMaxAmp > 0 else { return }
        
        // Target peak amplitude (e.g., -0.5 dBFS)
        let targetPeak: Float = pow(10, -0.5 / 20.0)
        
        // Compute gain
        var gain = targetPeak / globalMaxAmp
        
        // Limit maximum gain to prevent amplifying silence/background noise into loud static
        let maxGain: Float = 15.0 // ~+23dB max boost
        if gain > maxGain {
            gain = maxGain
        }
        
        // If it's already clipping or very close, don't boost
        guard gain > 1.05 else { return }
        
        // 2. Apply gain to all channels
        var gainScalar = gain
        for channel in 0..<channelCount {
            let data = channelData[channel]
            vDSP_vsmul(data, 1, &gainScalar, data, 1, length)
        }
        
        // 3. Write back to a temporary file
        let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let outFile = try AVAudioFile(forWriting: tempURL, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        try outFile.write(from: buffer)
        
        // 4. Replace original file
        let fm = FileManager.default
        _ = try fm.replaceItemAt(fileURL, withItemAt: tempURL)
    }
    
    enum NormalizationError: Error {
        case bufferCreation
        case missingChannelData
    }
}
