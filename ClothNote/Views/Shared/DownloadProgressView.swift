import SwiftUI

struct DownloadProgressView: View {
    let modelInfo: ModelInfo
    @ObservedObject var downloadManager: ModelDownloadManager

    var body: some View {
        VStack(spacing: 8) {
            if downloadManager.isDownloading[modelInfo.id] == true {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading \(modelInfo.name)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = downloadManager.downloadErrors[modelInfo.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
