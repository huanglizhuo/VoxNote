import SwiftUI

struct BlackHoleSetupGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("BlackHole Setup Guide")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("BlackHole is a virtual audio driver that lets ClothNote capture system audio (e.g., meeting audio from Zoom, browser, etc.).")
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                stepView(number: 1, title: "Install BlackHole", description: "Download and install BlackHole 2ch from the official website.") {
                    if let url = URL(string: "https://existential.audio/blackhole/") {
                        Button("Open BlackHole Website") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                stepView(number: 2, title: "Open Audio MIDI Setup", description: "Open the built-in Audio MIDI Setup app to configure audio routing.") {
                    Button("Open Audio MIDI Setup") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                    }
                }

                stepView(number: 3, title: "Create Multi-Output Device", description: "Click '+' at the bottom left, then 'Create Multi-Output Device'. Check both your speakers/headphones AND BlackHole 2ch. This routes audio to both your ears and ClothNote.")

                stepView(number: 4, title: "Set System Output", description: "In System Settings > Sound > Output, select the Multi-Output Device you just created.")

                stepView(number: 5, title: "Select BlackHole in ClothNote", description: "Back in ClothNote, select 'BlackHole 2ch' from the device picker and start recording.")
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 520)
    }

    private func stepView(number: Int, title: String, description: String, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }
}
