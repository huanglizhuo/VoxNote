import Foundation

enum AudioSourceType: String, CaseIterable, Identifiable {
    case systemAudio = "System Audio"
    case microphone = "Microphone"
    case file = "File"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .systemAudio: return "speaker.wave.3"
        case .microphone: return "mic"
        case .file: return "doc.text"
        }
    }
}
