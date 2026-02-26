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
    var refinedSegments: [TranscriptSegment]?
    var audioFileName: String?
    var refinedContent: String?
    var translationLanguage: String?
    var translatedRefinedContent: String?
    var segmentTranslations: [String: String]?  // segmentID.uuidString -> translated text
    var summary: String?
    var deviceName: String?  // name of the input device used for this recording

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
        refinedSegments: [TranscriptSegment]? = nil,
        audioFileName: String? = nil,
        refinedContent: String? = nil,
        translationLanguage: String? = nil,
        translatedRefinedContent: String? = nil,
        segmentTranslations: [String: String]? = nil,
        summary: String? = nil,
        deviceName: String? = nil
    ) {
        self.id = id
        self.title = title ?? Self.defaultTitle(for: createdAt)
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.segments = segments
        self.refinedSegments = refinedSegments
        self.audioFileName = audioFileName
        self.refinedContent = refinedContent
        self.translationLanguage = translationLanguage
        self.translatedRefinedContent = translatedRefinedContent
        self.segmentTranslations = segmentTranslations
        self.summary = summary
        self.deviceName = deviceName
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
