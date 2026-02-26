import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
class FileTranscriptionViewModel: ObservableObject {
    @Published var selectedFileURL: URL?
    @Published var transcriptionText = ""
    @Published var isTranscribing = false
    @Published var error: String?
    @Published var tokensPerSecond: Double = 0

    let transcriptionEngine: TranscriptionEngine

    init(transcriptionEngine: TranscriptionEngine) {
        self.transcriptionEngine = transcriptionEngine
    }

    var selectedFileName: String? {
        selectedFileURL?.lastPathComponent
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.wav,
            UTType.mp3,
            UTType.aiff,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio,
        ]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
            error = nil
        }
    }

    func handleDrop(url: URL) {
        selectedFileURL = url
        error = nil
    }

    func transcribe() async {
        guard let url = selectedFileURL else {
            error = "No file selected."
            return
        }
        guard transcriptionEngine.isModelLoaded else {
            error = "No model loaded. Please download and select a model first."
            return
        }

        isTranscribing = true
        error = nil
        transcriptionText = ""

        do {
            try await transcriptionEngine.transcribeFileStreaming(url: url)
            transcriptionText = transcriptionEngine.confirmedText
            tokensPerSecond = transcriptionEngine.tokensPerSecond
        } catch {
            self.error = error.localizedDescription
        }

        isTranscribing = false
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptionText, forType: .string)
    }

    func exportAsText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? transcriptionText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
