import SwiftUI

struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel

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
                }

                if let error = viewModel.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()

            Divider()

            // Transcript
            ScrollView {
                VStack(alignment: .leading) {
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
            }
            .padding()
        }
    }
}
