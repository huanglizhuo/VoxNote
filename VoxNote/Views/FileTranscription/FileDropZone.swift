import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    let selectedFileURL: URL?
    let onDrop: (URL) -> Void
    let onBrowse: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if let url = selectedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Change") {
                        onBrowse()
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Drop an audio file here")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("WAV, MP3, M4A, FLAC, AIFF")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Browse...") {
                        onBrowse()
                    }
                    .controlSize(.small)
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: selectedFileURL == nil ? [6, 3] : [])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        onDrop(url)
                    }
                }
            }
            return true
        }
    }
}
