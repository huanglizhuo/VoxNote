import SwiftUI

struct SystemAudioView: View {
    @ObservedObject var viewModel: SystemAudioViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("System Audio Capture")
                        .font(.title2.bold())
                    Spacer()
                }

                // Device picker
                devicePickerRow

                if !viewModel.hasBlackHole {
                    blackHoleWarning
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
        .sheet(isPresented: $viewModel.showSetupGuide) {
            BlackHoleSetupGuide()
        }
    }

    // MARK: - Subviews

    private var devicePickerRow: some View {
        HStack {
            Picker("Input Device:", selection: $viewModel.selectedDevice) {
                Text("Select a device...").tag(nil as AudioDevice?)
                ForEach(viewModel.deviceManager.inputDevices) { device in
                    HStack {
                        Text(device.name)
                        if device.isBlackHole {
                            Text("(BlackHole)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(device as AudioDevice?)
                }
            }
            .frame(maxWidth: 350)

            Button {
                viewModel.deviceManager.refreshDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh devices")
        }
    }

    private var blackHoleWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("BlackHole not detected.")
                .foregroundStyle(.secondary)
            Button("Setup Guide") {
                viewModel.showSetupGuide = true
            }
            .buttonStyle(.link)
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

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
            .disabled(viewModel.selectedDevice == nil || otherSourceRecording)
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
        if let source = viewModel.transcriptionEngine.activeSource, source != .systemAudio {
            return true
        }
        return false
    }
}
