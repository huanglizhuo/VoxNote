import SwiftUI

enum SidebarSelection: Hashable {
    case voxRecord
    case fileTranscription
    case modelManager
    case note(UUID)
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        List(selection: $selection) {
            Section("Recording") {
                HStack {
                    Label("Vox Record", systemImage: "waveform.and.mic")
                    Spacer()
                    if transcriptionEngine.activeSource != nil {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .tag(SidebarSelection.voxRecord)
            }

            
            Section("Import") {
                Label("File Transcription", systemImage: "doc.text")
                    .tag(SidebarSelection.fileTranscription)
            }

            Section("Settings") {
                Label("Model Manager", systemImage: "arrow.down.circle")
                    .tag(SidebarSelection.modelManager)
            }
            
            Section("Recorded Vox Notes") {
                if noteStore.notes.isEmpty {
                    Text("No notes yet")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                } else {
                    ForEach(sortedNotes) { note in
                        noteRow(note)
                            .tag(SidebarSelection.note(note.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteNote(note)
                                }
                            }
                    }
                }
            }

        }
        .listStyle(.sidebar)
    }

    private var sortedNotes: [Note] {
        noteStore.notes.sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: note.source == .microphone ? "mic" : "waveform.and.mic")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(note.title)
                    .lineLimit(1)
            }

            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(formattedDate(note.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if note.duration > 0 {
                    Text(formattedDuration(note.duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func deleteNote(_ note: Note) {
        if case .note(note.id) = selection {
            selection = nil
        }
        noteStore.delete(note)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
