import SwiftUI
import AppKit

struct NoteDetailView: View {
    let note: Note
    let noteStore: NoteStore
    let transcriptionEngine: TranscriptionEngine
    @Binding var selection: SidebarSelection?

    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var selectedTab = 0
    @State private var isRefining = false
    @State private var refineError: String?

    private var audioURL: URL? {
        noteStore.audioFileURL(for: note)
    }

    private var activeTabContent: String {
        if selectedTab == 1 {
            return note.refinedContent ?? ""
        }
        return note.content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    if isEditingTitle {
                        TextField("Title", text: $editedTitle, onCommit: {
                            commitRename()
                        })
                        .textFieldStyle(.plain)
                        .font(.title2.bold())
                    } else {
                        Text(note.title)
                            .font(.title2.bold())
                            .onTapGesture(count: 2) {
                                editedTitle = note.title
                                isEditingTitle = true
                            }
                    }
                    Spacer()

                    Label(
                        note.source == .microphone ? "Microphone" : "System Audio",
                        systemImage: note.source == .microphone ? "mic" : "speaker.wave.3"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(formattedDate(note.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if note.duration > 0 {
                        Text(formattedDuration(note.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .padding()

            // Audio player
            if let audioURL = audioURL {
                AudioPlayerBar(audioURL: audioURL)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Live Transcript").tag(0)
                Text("Refined Note").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Content
            if selectedTab == 0 {
                liveTranscriptTab
            } else {
                refinedNoteTab
            }

            Divider()

            // Actions
            HStack {
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(activeTabContent.isEmpty)

                Button {
                    exportAsText()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(activeTabContent.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    deleteNote()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding()
        }
    }

    // MARK: - Tab Views

    private var liveTranscriptTab: some View {
        ScrollView {
            if let segments = note.segments, !segments.isEmpty {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments) { segment in
                        HStack(alignment: .top, spacing: 6) {
                            Text(segment.formattedTimestamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(segment.text)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else if note.content.isEmpty {
                Text("No transcript content.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text(note.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding()
    }

    private var refinedNoteTab: some View {
        ScrollView {
            if isRefining {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Refining transcript...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if let refined = note.refinedContent, !refined.isEmpty {
                Text(refined)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if audioURL == nil {
                Text("No audio recording available for this note.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Text("Re-transcribe the saved audio using batch mode for better accuracy.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        refineTranscript()
                    } label: {
                        Label("Refine Transcript", systemImage: "wand.and.stars")
                    }
                    .disabled(!transcriptionEngine.isModelLoaded || transcriptionEngine.isTranscribing)

                    if let refineError {
                        Text(refineError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding()
    }

    // MARK: - Actions

    private func refineTranscript() {
        guard let audioURL = audioURL else { return }
        isRefining = true
        refineError = nil

        Task {
            do {
                let result = try await transcriptionEngine.transcribeFile(url: audioURL)
                var updated = note
                updated.refinedContent = result
                noteStore.save(updated)
                isRefining = false
            } catch {
                refineError = error.localizedDescription
                isRefining = false
            }
        }
    }

    private func commitRename() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var updated = note
            updated.title = trimmed
            noteStore.save(updated)
        }
        isEditingTitle = false
    }

    private func deleteNote() {
        selection = nil
        noteStore.delete(note)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeTabContent, forType: .string)
    }

    private func exportAsText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(note.title).txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? activeTabContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
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
