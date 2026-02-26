import SwiftUI

struct ModelManagerView: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @ObservedObject var downloadManager: ModelDownloadManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Model Manager")
                    .font(.title2.bold())
                Spacer()
                Button {
                    downloadManager.checkDownloadedModels()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh download status")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.models) { model in
                        ModelCardView(
                            model: model,
                            isSelected: viewModel.selectedModelID == model.id,
                            isDownloaded: downloadManager.isDownloaded(model),
                            isDownloading: downloadManager.isDownloading[model.id] == true,
                            downloadProgress: downloadManager.downloadProgress[model.id] ?? 0,
                            downloadError: downloadManager.downloadErrors[model.id],
                            onSelect: {
                                Task { await viewModel.selectModel(model) }
                            },
                            onDownload: {
                                Task { await viewModel.downloadModel(model) }
                            },
                            onDelete: {
                                viewModel.deleteModel(model)
                            }
                        )
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                if viewModel.transcriptionEngine.loadingModel {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading model...")
                        .foregroundStyle(.secondary)
                } else if viewModel.transcriptionEngine.isModelLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Model ready: \(viewModel.selectedModel?.name ?? "Unknown")")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.secondary)
                    Text("No model loaded")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)
            .padding()
        }
    }
}
