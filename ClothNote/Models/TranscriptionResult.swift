import Foundation

struct TranscriptionResult: Identifiable {
    let id = UUID()
    let text: String
    let source: AudioSourceType
    let date: Date
    let duration: TimeInterval?
    let tokensPerSecond: Double?
    let language: String?
}
