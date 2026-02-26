import SwiftUI

struct OnboardingView: View {
    @ObservedObject var downloadManager: ModelDownloadManager
    let onComplete: () -> Void

    @State private var isDownloading = false

    private var defaultModel: ModelInfo { ModelInfo.defaultModel }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to ClothNote")
                .font(.largeTitle.bold())

            Text("On-device speech recognition for your meetings.\nNo data leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()
                .frame(maxWidth: 300)

            VStack(spacing: 12) {
                Text("Download the speech recognition model to get started:")
                    .foregroundStyle(.secondary)

                // ASR model card
                modelCard(
                    title: defaultModel.name,
                    subtitle: "\(defaultModel.sizeDescription) — \(defaultModel.languages.joined(separator: ", "))",
                    badge: "Required",
                    badgeColor: .accentColor
                )

                Text("Translation uses Apple's built-in system framework — no download needed.\nOptional summarization model available in Model Manager.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isDownloading {
                downloadProgressSection
            } else if hasError {
                errorSection
            } else {
                Button("Download & Get Started") {
                    startDownload()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            Button("Skip for now") {
                onComplete()
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 540, minHeight: 420)
    }

    // MARK: - Subviews

    private func modelCard(title: String, subtitle: String, badge: String, badgeColor: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(badgeColor)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if downloadManager.isDownloaded(defaultModel) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .frame(maxWidth: 400)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var downloadProgressSection: some View {
        VStack(spacing: 12) {
            progressRow(label: "Speech Recognition", modelID: defaultModel.id, model: defaultModel)
        }
        .frame(maxWidth: 400)
    }

    private func progressRow(label: String, modelID: String, model: ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let progress = downloadManager.downloadProgress[modelID] ?? 0
            let isDone = downloadManager.isDownloaded(model)
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: isDone ? 1.0 : progress)
                .progressViewStyle(.linear)
        }
    }

    private var hasError: Bool {
        downloadManager.downloadErrors[defaultModel.id] != nil
    }

    private var errorSection: some View {
        VStack(spacing: 8) {
            if let error = downloadManager.downloadErrors[defaultModel.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Button("Retry") {
                startDownload()
            }
            .controlSize(.large)
        }
    }

    // MARK: - Actions

    private func startDownload() {
        isDownloading = true
        Task {
            await downloadManager.downloadModel(defaultModel)
            isDownloading = false
            if downloadManager.isDownloaded(defaultModel) {
                onComplete()
            }
        }
    }
}
