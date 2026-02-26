import SwiftUI

struct TranscriptionTextView: View {
    let segments: [TranscriptSegment]
    let unsegmentedText: String
    let provisionalText: String
    let isTranscribing: Bool
    let isReversed: Bool
    var segmentTranslations: [UUID: String] = [:]
    var showTranslation: Bool = false

    /// Segment-based init for live recording views
    init(
        segments: [TranscriptSegment],
        unsegmentedText: String = "",
        provisionalText: String,
        isTranscribing: Bool,
        isReversed: Bool = false,
        segmentTranslations: [UUID: String] = [:],
        showTranslation: Bool = false
    ) {
        self.segments = segments
        self.unsegmentedText = unsegmentedText
        self.provisionalText = provisionalText
        self.isTranscribing = isTranscribing
        self.isReversed = isReversed
        self.segmentTranslations = segmentTranslations
        self.showTranslation = showTranslation
    }

    /// Backward-compatible init for file transcription (wraps text in a single segment)
    init(confirmedText: String, provisionalText: String, isTranscribing: Bool) {
        if confirmedText.isEmpty {
            self.segments = []
        } else {
            self.segments = [TranscriptSegment(timestamp: 0, text: confirmedText)]
        }
        self.unsegmentedText = ""
        self.provisionalText = provisionalText
        self.isTranscribing = isTranscribing
        self.isReversed = false
    }

    private var hasContent: Bool {
        !segments.isEmpty || !unsegmentedText.isEmpty || !provisionalText.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !hasContent {
                        placeholderView
                    } else {
                        if isReversed {
                            provisionalLine
                            unsegmentedLine
                            ForEach(segments.reversed()) { segment in
                                segmentRow(segment)
                            }
                        } else {
                            ForEach(segments) { segment in
                                segmentRow(segment)
                            }
                            unsegmentedLine
                            provisionalLine
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .onChange(of: segments.count) {
                if !isReversed {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: provisionalText) {
                if !isReversed {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var placeholderView: some View {
        if isTranscribing {
            Text("Listening...")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            Text("Transcript will appear here.")
                .foregroundStyle(.secondary)
        }
    }

    private let timestampWidth: CGFloat = 52

    @ViewBuilder
    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                if segments.count > 1 || segment.timestamp > 0 {
                    Text(segment.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: timestampWidth, alignment: .leading)
                }
                Text(segment.text)
                    .textSelection(.enabled)
            }

            if showTranslation {
                if let translation = segmentTranslations[segment.id], !translation.isEmpty {
                    Text(translation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, segments.count > 1 || segment.timestamp > 0 ? timestampWidth + 6 : 0)
                }
            }
        }
    }

    @ViewBuilder
    private var unsegmentedLine: some View {
        if !unsegmentedText.isEmpty {
            Text(unsegmentedText)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var provisionalLine: some View {
        if !provisionalText.isEmpty {
            Text(provisionalText)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}
