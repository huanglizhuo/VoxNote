import SwiftUI

struct RecordingTimerView: View {
    let startDate: Date

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted(elapsed))
            .monospacedDigit()
            .font(.caption)
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startDate)
            }
            .onAppear {
                elapsed = Date().timeIntervalSince(startDate)
            }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
