import Foundation

@MainActor
class ModelManagerViewModel: ObservableObject {
    @Published var selectedModelID: String
    let models: [ModelInfo] = ModelInfo.availableModels

    let downloadManager: ModelDownloadManager
    let transcriptionEngine: TranscriptionEngine

    init(downloadManager: ModelDownloadManager, transcriptionEngine: TranscriptionEngine) {
        self.downloadManager = downloadManager
        self.transcriptionEngine = transcriptionEngine
        self.selectedModelID = UserDefaults.standard.string(forKey: "selectedModelID") ?? ModelInfo.defaultModel.id
    }

    var selectedModel: ModelInfo? {
        ModelInfo.availableModels.first(where: { $0.id == selectedModelID })
    }

    func selectModel(_ model: ModelInfo) async {
        selectedModelID = model.id
        UserDefaults.standard.set(model.id, forKey: "selectedModelID")

        if downloadManager.isDownloaded(model) {
            try? await transcriptionEngine.loadModel(repoID: model.repoID)
        }
    }

    func downloadModel(_ model: ModelInfo) async {
        await downloadManager.downloadModel(model)
    }

    func deleteModel(_ model: ModelInfo) {
        downloadManager.deleteModel(model)
        if selectedModelID == model.id {
            transcriptionEngine.unloadModel()
        }
    }

    func loadSelectedModelIfNeeded() async {
        guard let model = selectedModel, downloadManager.isDownloaded(model) else { return }
        try? await transcriptionEngine.loadModel(repoID: model.repoID)
    }
}
