import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let downloadError: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.headline)
                        if model.isDefault {
                            Text("Default")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundColor(.accentColor)
                        }
                    }
                    Text(model.sizeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected && isDownloaded {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 4) {
                ForEach(model.languages, id: \.self) { lang in
                    Text(lang)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }
            }

            if let error = downloadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                    Text(downloadProgress > 0
                         ? "Downloading... \(Int(downloadProgress * 100))%"
                         : "Preparing download...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                if isDownloading {
                    Button("Downloading...", action: {})
                        .controlSize(.small)
                        .disabled(true)
                } else if isDownloaded {
                    if !isSelected {
                        Button("Select") { onSelect() }
                            .controlSize(.small)
                    }
                    Button("Delete", role: .destructive) { onDelete() }
                        .controlSize(.small)
                } else {
                    Button("Download") { onDownload() }
                        .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
