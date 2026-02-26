import Foundation

@MainActor
class ModelManagerViewModel: ObservableObject {
    @Published var selectedModelID: String

    let models: [ModelInfo] = ModelInfo.availableModels
    let summarizationModels: [ModelInfo] = ModelInfo.availableSummarizationModels

    let downloadManager: ModelDownloadManager
    let transcriptionEngine: TranscriptionEngine
    let summarizationEngine: SummarizationEngine

    init(downloadManager: ModelDownloadManager, transcriptionEngine: TranscriptionEngine, summarizationEngine: SummarizationEngine) {
        self.downloadManager = downloadManager
        self.transcriptionEngine = transcriptionEngine
        self.summarizationEngine = summarizationEngine
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
        // After download, auto-load the model
        switch model.modelType {
        case .asr:
            if selectedModelID == model.id {
                try? await transcriptionEngine.loadModel(repoID: model.repoID)
            }
        case .summarization:
            try? await summarizationEngine.loadModel(repoID: model.repoID)
        }
    }

    func deleteModel(_ model: ModelInfo) {
        downloadManager.deleteModel(model)
        switch model.modelType {
        case .asr:
            if selectedModelID == model.id {
                transcriptionEngine.unloadModel()
            }
        case .summarization:
            summarizationEngine.unloadModel()
        }
    }

    func loadSelectedModelIfNeeded() async {
        guard let model = selectedModel, downloadManager.isDownloaded(model) else { return }
        try? await transcriptionEngine.loadModel(repoID: model.repoID)
    }

    func loadSummarizationModelIfNeeded() async {
        let summarizationModel = ModelInfo.defaultSummarizationModel
        guard downloadManager.isDownloaded(summarizationModel) else { return }
        try? await summarizationEngine.loadModel(repoID: summarizationModel.repoID)
    }
}
