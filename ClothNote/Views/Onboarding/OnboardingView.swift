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

            VStack(spacing: 8) {
                Text("To get started, download the default ASR model:")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(defaultModel.name)
                        .font(.headline)
                    Text("\(defaultModel.sizeDescription) — \(defaultModel.languages.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: 350)
                .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            if isDownloading {
                VStack(spacing: 8) {
                    let progress = downloadManager.downloadProgress[defaultModel.id] ?? 0
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)
                    Text(progress > 0
                         ? "Downloading model... \(Int(progress * 100))%"
                         : "Preparing download...")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if let error = downloadManager.downloadErrors[defaultModel.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)

                Button("Retry") {
                    startDownload()
                }
                .controlSize(.large)
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
        .frame(minWidth: 500, minHeight: 400)
    }

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
