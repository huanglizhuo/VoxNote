import Foundation
import MLXAudioSTT
import MLXLLM
import MLXLMCommon

@MainActor
class ModelDownloadManager: ObservableObject {
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedModels: Set<String> = []
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadErrors: [String: String] = [:]

    private let cacheBaseDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }()

    private var progressTasks: [String: Task<Void, Never>] = [:]

    init() {
        checkDownloadedModels()
    }

    func checkDownloadedModels() {
        downloadedModels.removeAll()
        for model in ModelInfo.availableModels {
            if isModelCached(repoID: model.repoID) {
                downloadedModels.insert(model.id)
            }
        }
        for model in ModelInfo.availableSummarizationModels {
            if isModelCached(repoID: model.repoID) {
                downloadedModels.insert(model.id)
            }
        }
    }

    func isModelCached(repoID: String) -> Bool {
        // Check mlx-audio/ cache (primary path used by mlx-audio-swift)
        let mlxAudioName = repoID.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = cacheBaseDir.appendingPathComponent("mlx-audio/\(mlxAudioName)")
        if FileManager.default.fileExists(atPath: mlxAudioDir.appendingPathComponent("model.safetensors").path) {
            return true
        }

        // Check models-- cache (standard HuggingFace hub format)
        let dirName = "models--" + repoID.replacingOccurrences(of: "/", with: "--")
        let snapshotsDir = cacheBaseDir.appendingPathComponent(dirName).appendingPathComponent("snapshots")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path),
           !contents.isEmpty {
            return true
        }

        return false
    }

    func isDownloaded(_ modelInfo: ModelInfo) -> Bool {
        downloadedModels.contains(modelInfo.id)
    }

    func downloadModel(_ modelInfo: ModelInfo) async {
        isDownloading[modelInfo.id] = true
        downloadErrors[modelInfo.id] = nil
        downloadProgress[modelInfo.id] = 0

        do {
            switch modelInfo.modelType {
            case .asr:
                // Start file-system progress monitor for ASR models
                startProgressMonitor(for: modelInfo)
                let _ = try await Task.detached {
                    try await Qwen3ASRModel.fromPretrained(modelInfo.repoID)
                }.value
                stopProgressMonitor(for: modelInfo.id)

            case .summarization:
                // Use LLMModelFactory which provides real download progress callbacks
                let config = ModelConfiguration(id: modelInfo.repoID)
                let modelID = modelInfo.id
                let _ = try await LLMModelFactory.shared.loadContainer(configuration: config) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.isDownloading[modelID] == true else { return }
                        self.downloadProgress[modelID] = progress.fractionCompleted
                    }
                }
            }

            downloadedModels.insert(modelInfo.id)
            downloadProgress[modelInfo.id] = 1.0
        } catch {
            downloadErrors[modelInfo.id] = error.localizedDescription
            if modelInfo.modelType == .asr {
                stopProgressMonitor(for: modelInfo.id)
            }
        }

        isDownloading[modelInfo.id] = false
    }

    func deleteModel(_ modelInfo: ModelInfo) {
        // Delete mlx-audio/ cache
        let mlxAudioName = modelInfo.repoID.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = cacheBaseDir.appendingPathComponent("mlx-audio/\(mlxAudioName)")
        try? FileManager.default.removeItem(at: mlxAudioDir)

        // Delete models-- cache
        let dirName = "models--" + modelInfo.repoID.replacingOccurrences(of: "/", with: "--")
        let modelDir = cacheBaseDir.appendingPathComponent(dirName)
        try? FileManager.default.removeItem(at: modelDir)

        downloadedModels.remove(modelInfo.id)
        downloadProgress.removeValue(forKey: modelInfo.id)
    }

    // MARK: - Progress Monitoring (ASR only)

    /// Expected download sizes in bytes (approximate) for file-system progress tracking.
    private static let expectedSizes: [String: Int64] = [
        "qwen3-asr-0.6b-4bit": 500_000_000,
        "qwen3-asr-0.6b-5bit": 600_000_000,
        "qwen3-asr-0.6b-6bit": 700_000_000,
        "qwen3-asr-0.6b-8bit": 1_000_000_000,
        "qwen3-asr-0.6b-bf16": 1_400_000_000,
        "qwen3-asr-1.7b-4bit": 1_200_000_000,
        "qwen3-asr-1.7b-5bit": 1_400_000_000,
        "qwen3-asr-1.7b-6bit": 1_600_000_000,
        "qwen3-asr-1.7b-8bit": 2_000_000_000,
        "qwen3-asr-1.7b-bf16": 3_600_000_000,
        "qwen3-1.7b-8bit": 1_900_000_000,
    ]

    private func startProgressMonitor(for modelInfo: ModelInfo) {
        let modelID = modelInfo.id
        let repoID = modelInfo.repoID
        let expectedSize = Self.expectedSizes[modelID] ?? 1_000_000_000
        let cacheBase = cacheBaseDir

        progressTasks[modelID] = Task.detached { [weak self] in
            let dirName = "models--" + repoID.replacingOccurrences(of: "/", with: "--")
            let blobsDir = cacheBase.appendingPathComponent(dirName).appendingPathComponent("blobs")

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // poll every 0.5s
                guard !Task.isCancelled else { break }

                let currentSize = Self.directorySize(at: blobsDir)
                let fraction = min(Double(currentSize) / Double(expectedSize), 0.95)

                await MainActor.run { [weak self] in
                    guard let self, self.isDownloading[modelID] == true else { return }
                    if self.downloadProgress[modelID] ?? 0 < fraction {
                        self.downloadProgress[modelID] = fraction
                    }
                }
            }
        }
    }

    private func stopProgressMonitor(for modelID: String) {
        progressTasks[modelID]?.cancel()
        progressTasks.removeValue(forKey: modelID)
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
