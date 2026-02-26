import Foundation

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []

    private let notesDirectory: URL
    let audioDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        notesDirectory = appSupport.appendingPathComponent("ClothNote/notes", isDirectory: true)
        audioDirectory = notesDirectory.appendingPathComponent("audio", isDirectory: true)

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        loadAll()
    }

    func audioFileURL(for note: Note) -> URL? {
        guard let fileName = note.audioFileName else { return nil }
        let url = audioDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Public API

    func save(_ note: Note) {
        var updated = note
        updated.updatedAt = Date()

        if let index = notes.firstIndex(where: { $0.id == updated.id }) {
            notes[index] = updated
        } else {
            notes.append(updated)
        }

        writeToDisk(updated)
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        let fileURL = fileURL(for: note.id)
        try? FileManager.default.removeItem(at: fileURL)

        // Remove associated audio file
        if let audioFileName = note.audioFileName {
            let audioURL = audioDirectory.appendingPathComponent(audioFileName)
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    func notes(for source: NoteSource) -> [Note] {
        notes
            .filter { $0.source == source }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Persistence

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        notes = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Note? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Note.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func writeToDisk(_ note: Note) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(note) else { return }
        try? data.write(to: fileURL(for: note.id))
    }

    private func fileURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}
