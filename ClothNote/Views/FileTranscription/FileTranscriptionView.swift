import SwiftUI
import Translation

struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel

    @State private var translationText = ""
    @State private var showTranslation = false
    @State private var translationConfig: TranslationSession.Configuration?
    @AppStorage("translationTargetLanguage") private var translationTargetLanguage: String = TranslationLanguage.disabled.rawValue

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("File Transcription")
                        .font(.title2.bold())
                    Spacer()
                }

                // Drop zone / file selection
                FileDropZone(selectedFileURL: viewModel.selectedFileURL) { url in
                    viewModel.handleDrop(url: url)
                } onBrowse: {
                    viewModel.selectFile()
                }

                HStack(spacing: 16) {
                    Button {
                        Task {
                            await viewModel.transcribe()
                            translationText = ""
                            showTranslation = false
                        }
                    } label: {
                        Label("Transcribe", systemImage: "waveform")
                    }
                    .controlSize(.large)
                    .disabled(viewModel.selectedFileURL == nil || viewModel.isTranscribing)

                    if viewModel.isTranscribing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Transcribing...")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.tokensPerSecond > 0 {
                        Text(String(format: "%.1f tok/s", viewModel.tokensPerSecond))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    // Translation controls (only when transcription is done)
                    if !viewModel.transcriptionText.isEmpty {
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
                            Label(translationText.isEmpty ? "Translate" : "Re-translate", systemImage: "character.bubble")
                        }
                        .disabled(translationTargetLanguage == TranslationLanguage.disabled.rawValue)
                    }
                }

                if let error = viewModel.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()

            Divider()

            // Transcript + optional translation
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.transcriptionText.isEmpty && !viewModel.isTranscribing {
                        Text("Transcript will appear here after processing.")
                            .foregroundStyle(.tertiary)
                    } else if viewModel.isTranscribing {
                        Text(viewModel.transcriptionEngine.confirmedText)
                            .textSelection(.enabled)
                        if viewModel.transcriptionEngine.confirmedText.isEmpty {
                            Text("Processing...")
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    } else {
                        Text(viewModel.transcriptionText)
                            .textSelection(.enabled)

                        if showTranslation && !translationText.isEmpty {
                            Divider()
                            Text("Translation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(translationText)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary.opacity(0.85))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(.background)
            .padding()

            Divider()

            // Actions
            HStack {
                Button {
                    viewModel.copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.transcriptionText.isEmpty)

                Button {
                    viewModel.exportAsText()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.transcriptionText.isEmpty)

                Spacer()

                if !translationText.isEmpty {
                    Toggle(isOn: $showTranslation) {
                        Label("Translation", systemImage: "character.bubble")
                    }
                    .toggleStyle(.button)
                }
            }
            .padding()
        }
        .translationTask(translationConfig) { session in
            defer { translationConfig = nil }
            do {
                try await session.prepareTranslation()
            } catch {
                return
            }
            if let response = try? await session.translate(viewModel.transcriptionText) {
                translationText = response.targetText
                showTranslation = !translationText.isEmpty
            }
        }
    }

    private func triggerTranslation() {
        guard let lang = TranslationLanguage(rawValue: translationTargetLanguage),
              lang != .disabled,
              let localeLanguage = lang.localeLanguage else { return }
        translationConfig = TranslationSession.Configuration(source: nil, target: localeLanguage)
    }
}
