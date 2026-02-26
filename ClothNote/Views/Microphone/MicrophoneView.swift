import SwiftUI

struct MicrophoneView: View {
    @ObservedObject var viewModel: MicrophoneViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Microphone Recording")
                        .font(.title2.bold())
                    Spacer()
                }

                controlsRow

                if let error = viewModel.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()

            Divider()

            // Transcript
            TranscriptionTextView(
                segments: viewModel.transcriptionEngine.segments,
                unsegmentedText: viewModel.transcriptionEngine.unsegmentedText,
                provisionalText: viewModel.transcriptionEngine.provisionalText,
                isTranscribing: viewModel.isRecording,
                isReversed: viewModel.isReversed
            )
            .padding()

            Divider()

            // Actions
            HStack {
                Button {
                    viewModel.copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.transcriptionEngine.fullText.isEmpty)

                Button {
                    viewModel.exportAsText()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.transcriptionEngine.fullText.isEmpty)

                Spacer()

                Button {
                    viewModel.isReversed.toggle()
                } label: {
                    Label(
                        viewModel.isReversed ? "Oldest First" : "Newest First",
                        systemImage: viewModel.isReversed ? "arrow.down" : "arrow.up"
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Subviews

    private var controlsRow: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.toggleRecording()
            } label: {
                Label(
                    viewModel.isRecording ? "Stop" : "Start Recording",
                    systemImage: viewModel.isRecording ? "stop.circle.fill" : "record.circle"
                )
            }
            .controlSize(.large)
            .tint(viewModel.isRecording ? .red : .accentColor)
            .disabled(otherSourceRecording)
            .keyboardShortcut("r", modifiers: .command)

            if viewModel.isRecording {
                RecordingDot()
            }

            if let startDate = viewModel.recordingStartDate, viewModel.isRecording {
                RecordingTimerView(startDate: startDate)
            }

            Spacer()

            if viewModel.transcriptionEngine.tokensPerSecond > 0, viewModel.isRecording {
                Text(String(format: "%.1f tok/s", viewModel.transcriptionEngine.tokensPerSecond))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var otherSourceRecording: Bool {
        if let source = viewModel.transcriptionEngine.activeSource, source != .microphone {
            return true
        }
        return false
    }
}
