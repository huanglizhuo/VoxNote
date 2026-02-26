import Foundation
import os.log
import MLXLLM
import MLXLMCommon

private let logger = Logger(subsystem: "com.voxnote", category: "SummarizationEngine")

@MainActor
class SummarizationEngine: ObservableObject {
    @Published var isModelLoaded = false
    @Published var loadingModel = false
    @Published var isSummarizing = false

    private var modelContainer: ModelContainer?
    private var currentRepoID: String?

    // MARK: - Model Loading

    func loadModel(repoID: String = "mlx-community/Qwen3-1.7B-8bit") async throws {
        if currentRepoID == repoID && modelContainer != nil {
            logger.info("[\(repoID)] already loaded, skipping")
            return
        }

        logger.info("[\(repoID)] loadModel started")
        let t0 = Date()

        loadingModel = true
        defer {
            loadingModel = false
            logger.info("[\(repoID)] loadModel finished in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        }

        modelContainer = nil
        currentRepoID = nil
        isModelLoaded = false

        let config = ModelConfiguration(id: repoID)
        let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
            logger.info("[\(repoID)] loadContainer progress: \(String(format: "%.0f%%", progress.fractionCompleted * 100))")
        }

        modelContainer = container
        currentRepoID = repoID
        isModelLoaded = true
        logger.info("[\(repoID)] model ready")
    }

    func unloadModel() {
        modelContainer = nil
        currentRepoID = nil
        isModelLoaded = false
    }

    // MARK: - Summarization

    func summarize(text: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard let container = modelContainer else { throw SummarizationError.modelNotLoaded }

        isSummarizing = true
        defer { isSummarizing = false }

        let t0 = Date()
        logger.info("summarize: \(text.count) chars")

        let params = GenerateParameters(temperature: 0.3, topP: 1.0, repetitionPenalty: 1.0)
        let userInput = buildSummarizationInput(text: text)

        let lmInput = try await container.prepare(input: userInput)

        let stream = try await container.generate(input: lmInput, parameters: params)
        var result = ""
        for await generation in stream {
            if case .chunk(let chunk) = generation {
                result += chunk
            }
        }

        logger.info("summarize done in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")

        let cleaned = stripThinkingBlocks(result)
        return cleaned
    }

    // MARK: - Private

    private func buildSummarizationInput(text: String) -> UserInput {
        let system = """
            You are a concise summarizer. Output only a clear, well-structured summary of the provided text. \
            Do not include any preamble, explanation, or commentary — just the summary itself.
            """
        return UserInput(chat: [
            .system(system),
            .user("/no_think\nSummarize the following:\n\n\(text)"),
        ])
    }

    private func stripThinkingBlocks(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Errors

    enum SummarizationError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Summarization model is not loaded."
            }
        }
    }
}
