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
                VStack(alignment: .leading, spacing: 16) {
                    // ASR Models section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASR Models")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

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

                    Divider()

                    // Summarization Models section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summarization Models")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(viewModel.summarizationModels) { model in
                            ModelCardView(
                                model: model,
                                isSelected: false,
                                isDownloaded: downloadManager.isDownloaded(model),
                                isDownloading: downloadManager.isDownloading[model.id] == true,
                                downloadProgress: downloadManager.downloadProgress[model.id] ?? 0,
                                downloadError: downloadManager.downloadErrors[model.id],
                                onSelect: nil,
                                onDownload: {
                                    Task { await viewModel.downloadModel(model) }
                                },
                                onDelete: {
                                    viewModel.deleteModel(model)
                                }
                            )
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Status bar
            VStack(spacing: 4) {
                HStack {
                    asrStatusView
                    Spacer()
                }
                HStack {
                    summarizationStatusView
                    Spacer()
                }
            }
            .font(.caption)
            .padding()
        }
    }

    // MARK: - Status Views

    private var asrStatusView: some View {
        Group {
            if viewModel.transcriptionEngine.loadingModel {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Loading ASR model...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.transcriptionEngine.isModelLoaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("ASR model ready: \(viewModel.selectedModel?.name ?? "Unknown")")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text("No ASR model loaded")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summarizationStatusView: some View {
        Group {
            if viewModel.summarizationEngine.loadingModel {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Loading summarization model...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.summarizationEngine.isModelLoaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Summarization model ready: \(ModelInfo.defaultSummarizationModel.name)")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text("No summarization model loaded")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
