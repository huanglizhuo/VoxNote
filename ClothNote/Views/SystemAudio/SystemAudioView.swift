import SwiftUI
import Translation

struct SystemAudioView: View {
    @ObservedObject var viewModel: SystemAudioViewModel

    @State private var translationConfig: TranslationSession.Configuration?
    @State private var liveTranslationContinuation: AsyncStream<(id: UUID, text: String)>.Continuation?
    @State private var segmentTranslations: [UUID: String] = [:]
    @State private var showTranslation = false
    @State private var isPulsing = false
    @AppStorage("translationTargetLanguage") private var targetLanguageRaw: String = "disabled"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Vox Record")
                        .font(.title2.bold())
                    Spacer()
                }

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
                isReversed: viewModel.isReversed,
                segmentTranslations: segmentTranslations,
                showTranslation: showTranslation
            )
            .padding()

            Divider()

            // Actions
            HStack {
                Button {
                    viewModel.copyToClipboard(segmentTranslations: segmentTranslations, showTranslation: showTranslation)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.transcriptionEngine.fullText.isEmpty)

                Button {
                    viewModel.exportAsText(segmentTranslations: segmentTranslations, showTranslation: showTranslation)
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
        .translationTask(translationConfig) { session in
            defer {
                liveTranslationContinuation = nil
                print("[Translation] 🔚 translationTask ended — continuation cleared")
            }
            print("[Translation] 🔧 translationTask fired — calling prepareTranslation()")
            do {
                try await session.prepareTranslation()
                print("[Translation] ✅ prepareTranslation() succeeded")
            } catch {
                // Non-fatal: prepareTranslation may fail for auto-detect source or if the
                // language pack isn't installed yet. Individual translate() calls will
                // trigger the system download UI as needed.
                print("[Translation] ⚠️  prepareTranslation() failed (continuing anyway): \(error)")
            }
            let (stream, continuation) = AsyncStream<(id: UUID, text: String)>.makeStream()
            liveTranslationContinuation = continuation
            print("[Translation] 🔄 live translation loop active — waiting for segments")
            for await item in stream {
                guard !Task.isCancelled else { break }
                do {
                    let r = try await session.translate(item.text)
                    print("[Translation] ✅ \(item.id) → \"\(String(r.targetText.prefix(40)))\"")
                    segmentTranslations[item.id] = r.targetText
                } catch {
                    print("[Translation] ❌ translate failed for \(item.id): \(error)")
                }
            }
        }
        .onChange(of: viewModel.transcriptionEngine.segments) { old, new in
            guard showTranslation else { return }
            guard new.count > old.count else { return }
            let newSegs = Array(new.dropFirst(old.count))
            print("[Translation] 📝 \(newSegs.count) new segment(s) | continuation=\(liveTranslationContinuation != nil ? "active" : "nil") | lang=\(targetLanguageRaw)")
            for seg in newSegs {
                let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if liveTranslationContinuation != nil {
                    print("[Translation] 🔤 queuing \(seg.id): \"\(String(trimmed.prefix(40)))\"")
                    liveTranslationContinuation?.yield((id: seg.id, text: trimmed))
                } else {
                    print("[Translation] ⚠️  continuation nil — segment \(seg.id) dropped")
                }
            }
        }
        .onChange(of: viewModel.isRecording) { _, recording in
            isPulsing = recording
        }
        .onAppear {
            isPulsing = viewModel.isRecording
            print("[Translation] 👀 onAppear — stored lang='\(targetLanguageRaw)' | config=\(translationConfig != nil ? "set" : "nil")")
            let lang = TranslationLanguage(rawValue: targetLanguageRaw) ?? .disabled
            if let locale = lang.localeLanguage {
                translationConfig = TranslationSession.Configuration(source: nil, target: locale)
                showTranslation = true
                print("[Translation] ✅ onAppear set translationConfig for locale=\(locale)")
            } else {
                print("[Translation] ℹ️  onAppear — lang is disabled, no config set")
            }
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
            // Recording button — animation + timer baked into the label
            Button {
                if viewModel.isRecording {
                    let noteID = viewModel.currentRecordingNoteID
                    let currentTranslations = segmentTranslations
                    let lang = targetLanguageRaw
                    viewModel.stopRecording()
                    if let noteID, !currentTranslations.isEmpty {
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            viewModel.saveTranslations(currentTranslations, language: lang, to: noteID)
                        }
                    }
                } else {
                    segmentTranslations = [:]
                    showTranslation = targetLanguageRaw != TranslationLanguage.disabled.rawValue
                    print("[Translation] ▶️ recording started — showTranslation=\(showTranslation) | continuation=\(liveTranslationContinuation != nil ? "active" : "nil") | lang=\(targetLanguageRaw)")
                    viewModel.startRecording()
                }
            } label: {
                if viewModel.isRecording, let startDate = viewModel.recordingStartDate {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.3 : 0.8)
                            .animation(
                                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                        Text("Stop")
                        TimelineView(.periodic(from: startDate, by: 1)) { ctx in
                            Text(elapsedString(ctx.date.timeIntervalSince(startDate)))
                                .monospacedDigit()
                        }
                    }
                } else {
                    Label("Start Recording", systemImage: "record.circle")
                }
            }
            .controlSize(.large)
            .tint(viewModel.isRecording ? .red : .accentColor)
            .disabled(viewModel.selectedDevice == nil || otherSourceRecording)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            if viewModel.transcriptionEngine.tokensPerSecond > 0, viewModel.isRecording {
                Text(String(format: "%.1f tok/s", viewModel.transcriptionEngine.tokensPerSecond))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            translationControls
        }
    }

    // Language picker + translation toggle — together so picking a language auto-shows translations
    private var translationControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "character.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $targetLanguageRaw) {
                ForEach(TranslationLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)
            .onChange(of: targetLanguageRaw) { _, raw in
                let lang = TranslationLanguage(rawValue: raw) ?? .disabled
                translationConfig = lang.localeLanguage.map {
                    TranslationSession.Configuration(source: nil, target: $0)
                }
                showTranslation = lang != .disabled
                print("[Translation] 🌐 language picker changed to '\(raw)' — config=\(translationConfig != nil ? "set" : "nil") showTranslation=\(showTranslation)")
            }

            Toggle(isOn: $showTranslation) {
                Label("Translation", systemImage: "character.bubble")
            }
            .toggleStyle(.button)
            .disabled(targetLanguageRaw == TranslationLanguage.disabled.rawValue)
        }
    }

    private var otherSourceRecording: Bool {
        viewModel.transcriptionEngine.activeSource != nil && !viewModel.isRecording
    }

    private func elapsedString(_ elapsed: TimeInterval) -> String {
        let total = Int(max(0, elapsed))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
