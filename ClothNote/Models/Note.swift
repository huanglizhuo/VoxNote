import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var source: NoteSource
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var segments: [TranscriptSegment]?
    var audioFileName: String?
    var refinedContent: String?

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 50 { return trimmed }
        return String(trimmed.prefix(50)) + "..."
    }

    init(
        id: UUID = UUID(),
        title: String? = nil,
        content: String = "",
        source: NoteSource,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        duration: TimeInterval = 0,
        segments: [TranscriptSegment]? = nil,
        audioFileName: String? = nil,
        refinedContent: String? = nil
    ) {
        self.id = id
        self.title = title ?? Self.defaultTitle(for: createdAt)
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.segments = segments
        self.audioFileName = audioFileName
        self.refinedContent = refinedContent
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

enum NoteSource: String, Codable, CaseIterable {
    case microphone
    case systemAudio
}
