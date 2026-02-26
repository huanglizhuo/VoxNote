import Foundation

enum ModelType {
    case asr
    case summarization
}

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let repoID: String
    let sizeDescription: String
    let languages: [String]
    let isDefault: Bool
    let modelType: ModelType

    init(id: String, name: String, repoID: String, sizeDescription: String, languages: [String], isDefault: Bool, modelType: ModelType = .asr) {
        self.id = id
        self.name = name
        self.repoID = repoID
        self.sizeDescription = sizeDescription
        self.languages = languages
        self.isDefault = isDefault
        self.modelType = modelType
    }

    // Required by Hashable (modelType is not hashable via enum synthesis automatically,
    // but since ModelInfo is used as a value type with id, we hash by id)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ModelInfo, rhs: ModelInfo) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - ASR Models

    static let availableModels: [ModelInfo] = [
        // 1.7B variants (large to small)
        ModelInfo(
            id: "qwen3-asr-1.7b-bf16",
            name: "Qwen3 ASR 1.7B (bf16)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-bf16",
            sizeDescription: "~3.6 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-1.7b-8bit",
            name: "Qwen3 ASR 1.7B (8-bit)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-8bit",
            sizeDescription: "~2 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-1.7b-6bit",
            name: "Qwen3 ASR 1.7B (6-bit)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-6bit",
            sizeDescription: "~1.6 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-1.7b-5bit",
            name: "Qwen3 ASR 1.7B (5-bit)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-5bit",
            sizeDescription: "~1.4 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-1.7b-4bit",
            name: "Qwen3 ASR 1.7B (4-bit)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-4bit",
            sizeDescription: "~1.2 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        // 0.6B variants (large to small)
        ModelInfo(
            id: "qwen3-asr-0.6b-bf16",
            name: "Qwen3 ASR 0.6B (bf16)",
            repoID: "mlx-community/Qwen3-ASR-0.6B-bf16",
            sizeDescription: "~1.4 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-0.6b-8bit",
            name: "Qwen3 ASR 0.6B (8-bit)",
            repoID: "mlx-community/Qwen3-ASR-0.6B-8bit",
            sizeDescription: "~1 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: true
        ),
        ModelInfo(
            id: "qwen3-asr-0.6b-6bit",
            name: "Qwen3 ASR 0.6B (6-bit)",
            repoID: "mlx-community/Qwen3-ASR-0.6B-6bit",
            sizeDescription: "~0.7 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-0.6b-5bit",
            name: "Qwen3 ASR 0.6B (5-bit)",
            repoID: "mlx-community/Qwen3-ASR-0.6B-5bit",
            sizeDescription: "~0.6 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
        ModelInfo(
            id: "qwen3-asr-0.6b-4bit",
            name: "Qwen3 ASR 0.6B (4-bit)",
            repoID: "mlx-community/Qwen3-ASR-0.6B-4bit",
            sizeDescription: "~0.5 GB",
            languages: ["Chinese", "English", "Japanese", "Korean", "Cantonese"],
            isDefault: false
        ),
    ]

    static var defaultModel: ModelInfo {
        availableModels.first(where: { $0.isDefault })!
    }

    // MARK: - Summarization Models

    static let availableSummarizationModels: [ModelInfo] = [
        ModelInfo(
            id: "qwen3-1.7b-8bit",
            name: "Qwen3 1.7B (8-bit) — Summarization",
            repoID: "mlx-community/Qwen3-1.7B-8bit",
            sizeDescription: "~1.9 GB",
            languages: ["EN", "ZH", "JA", "FR", "and more"],
            isDefault: true,
            modelType: .summarization
        )
    ]

    static var defaultSummarizationModel: ModelInfo {
        availableSummarizationModels.first(where: { $0.isDefault })!
    }
}
