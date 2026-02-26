import SwiftUI
import AVFoundation

struct AudioPlayerBar: View {
    let audioURL: URL

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Slider(value: $progress, in: 0...max(duration, 0.01)) { editing in
                if !editing {
                    player?.currentTime = progress
                }
            }

            Text(formatTime(isPlaying ? progress : duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: audioURL) {
            stopPlayback()
            setupPlayer()
        }
    }

    private func setupPlayer() {
        do {
            let p = try AVAudioPlayer(contentsOf: audioURL)
            p.prepareToPlay()
            duration = p.duration
            progress = 0
            player = p
        } catch {
            player = nil
            duration = 0
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            if player.currentTime >= player.duration - 0.1 {
                player.currentTime = 0
                progress = 0
            }
            player.play()
            startTimer()
            isPlaying = true
        }
    }

    private func stopPlayback() {
        player?.stop()
        stopTimer()
        isPlaying = false
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let player = player else { return }
            progress = player.currentTime
            if !player.isPlaying {
                isPlaying = false
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
