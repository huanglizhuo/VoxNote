import Foundation

struct TranscriptSegment: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: TimeInterval
    let text: String

    var formattedTimestamp: String {
        let totalSeconds = Int(timestamp)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "[%02d:%02d]", minutes, seconds)
    }

    init(id: UUID = UUID(), timestamp: TimeInterval, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}
