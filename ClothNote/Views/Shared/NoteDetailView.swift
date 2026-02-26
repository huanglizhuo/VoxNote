import SwiftUI
import AppKit
import Translation

struct NoteDetailView: View {
    let note: Note
    let noteStore: NoteStore
    let transcriptionEngine: TranscriptionEngine
    let summarizationEngine: SummarizationEngine
    @Binding var selection: SidebarSelection?

    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var selectedTab = 0
    @State private var isRefining = false
    @State private var refineError: String?

    // Translation state
    @State private var showTranslation = false
    @State private var translateError: String?
    @State private var liveTranslations: [String: String] = [:]
    @State private var translationConfig: TranslationSession.Configuration?

    // Summarization state
    @State private var isSummarizing = false

    @AppStorage("translationTargetLanguage") private var translationTargetLanguage: String = TranslationLanguage.disabled.rawValue

    private var audioURL: URL? {
        noteStore.audioFileURL(for: note)
    }

    private var savedTranslations: [String: String] {
        note.segmentTranslations ?? [:]
    }

    private var effectiveTranslations: [String: String] {
        liveTranslations.isEmpty ? savedTranslations : liveTranslations
    }

    private var hasTranslations: Bool {
        !effectiveTranslations.isEmpty || note.translatedRefinedContent != nil
    }

    private var translationLanguageDisplay: String {
        if let lang = note.translationLanguage {
            return TranslationLanguage(rawValue: lang)?.displayName ?? lang
        }
        return TranslationLanguage(rawValue: translationTargetLanguage)?.displayName ?? ""
    }

    private var activeTabContent: String {
        if selectedTab == 1 {
            if showTranslation, let t = note.translatedRefinedContent {
                let original = note.refinedContent ?? ""
                return original.isEmpty ? t : original + "\n\n---\n\n" + t
            }
            return note.refinedContent ?? ""
        }
        // Live transcript tab
        if showTranslation, !effectiveTranslations.isEmpty, let segments = note.segments {
            return segments.map { segment in
                var line = segment.text
                if let t = effectiveTranslations[segment.id.uuidString] {
                    line += "\n" + t
                }
                return line
            }.joined(separator: "\n\n")
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
                        note.deviceName ?? (note.source == .microphone ? "Microphone" : "Vox Record"),
                        systemImage: note.source == .microphone && note.deviceName == nil ? "mic" : "waveform.and.mic"
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

                    // Translation toggle
                    if hasTranslations {
                        Toggle(isOn: $showTranslation) {
                            Label("Show Translation", systemImage: "character.bubble")
                        }
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
            .padding()

            // Summary section (if available)
            if let summary = note.summary {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Summary", systemImage: "text.quote")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text(summary)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

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

                // Translate
                Picker("", selection: $translationTargetLanguage) {
                    ForEach(TranslationLanguage.allCases.filter { $0 != .disabled }) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)

                Button {
                    triggerTranslation()
                } label: {
                    Label(hasTranslations ? "Re-translate" : "Translate", systemImage: "character.bubble")
                }
                .disabled(translationTargetLanguage == TranslationLanguage.disabled.rawValue)

                // Summarize
                Button {
                    summarizeNote()
                } label: {
                    if isSummarizing {
                        Label("Summarizing...", systemImage: "text.quote")
                    } else {
                        Label(note.summary == nil ? "Summarize" : "Re-summarize", systemImage: "text.quote")
                    }
                }
                .disabled(!summarizationEngine.isModelLoaded || isSummarizing)

                Button(role: .destructive) {
                    deleteNote()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding()
        }
        .translationTask(translationConfig) { session in
            defer { translationConfig = nil }
            do {
                try await session.prepareTranslation()
            } catch {
                translateError = error.localizedDescription
                return
            }
            await performTranslation(session: session)
        }
        .onAppear {
            liveTranslations = note.segmentTranslations ?? [:]
        }
        .onChange(of: note.segmentTranslations) {
            liveTranslations = note.segmentTranslations ?? [:]
        }
    }

    // MARK: - Tab Views

    private var liveTranscriptTab: some View {
        ScrollView {
            if let segments = note.segments, !segments.isEmpty {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments) { segment in
                        segmentRow(segment)
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

    @ViewBuilder
    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Text(segment.formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(segment.text)
                    .textSelection(.enabled)
            }
            if showTranslation, let translation = effectiveTranslations[segment.id.uuidString], !translation.isEmpty {
                Text(translation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 58)
            }
        }
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
                VStack(alignment: .leading, spacing: 12) {
                    Text(refined)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showTranslation {
                        if let translation = note.translatedRefinedContent {
                            Divider()
                            Text("Translation (\(translationLanguageDisplay))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(translation)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
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

    // MARK: - Translation Actions

    private func triggerTranslation() {
        guard let lang = TranslationLanguage(rawValue: translationTargetLanguage),
              lang != .disabled,
              let localeLanguage = lang.localeLanguage else { return }
        translationConfig = TranslationSession.Configuration(source: nil, target: localeLanguage)
    }

    private func performTranslation(session: TranslationSession) async {
        liveTranslations = [:]
        translateError = nil

        if let segments = note.segments, !segments.isEmpty {
            let requests = segments.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString)
            }
            do {
                for try await response in session.translate(batch: requests) {
                    if let key = response.clientIdentifier {
                        liveTranslations[key] = response.targetText
                    }
                }
            } catch {
                translateError = error.localizedDescription
                return
            }
        } else if !note.content.isEmpty {
            if let response = try? await session.translate(note.content) {
                liveTranslations["content"] = response.targetText
            }
        }

        var updated = note
        updated.segmentTranslations = liveTranslations
        updated.translationLanguage = translationTargetLanguage
        noteStore.save(updated)
        showTranslation = true
    }

    // MARK: - Summarization

    private func summarizeNote() {
        let text = note.segments?.map(\.text).joined(separator: " ") ?? note.content
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSummarizing = true
        Task {
            let summary = try? await summarizationEngine.summarize(text: text)
            var updated = note
            updated.summary = summary
            noteStore.save(updated)
            isSummarizing = false
        }
    }

    // MARK: - Other Actions

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
