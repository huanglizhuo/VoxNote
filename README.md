# VoxNote

<img src="assets/AppIcon.png" alt="VoxNote App Icon" width="100" />

VoxNote is a macOS app for turning audio into clear notes.

## Main Features

- Record from microphone or system audio.
- Import audio files and transcribe them quickly.
- Generate a live transcript and a refined note view.
- Translate, re-summarize, and manage outputs in one place.
- Review past recordings with playback and export tools.

## How to Use

1. Install BlackHole from the official repo:  
   https://github.com/ExistentialAudio/BlackHole
2. Open **Audio MIDI Setup** and create a **Multi-Output Device**.

<img src="assets/blackhole-create-multi-output.png" alt="Create Multi-Output Device" width="300" />


3. In the Multi-Output Device settings, check **BlackHole 2ch** and your speaker/headphones output.

<img src="assets/blackhole-multi-output-options.png" alt="Multi-Output Device Settings" width="500" />

4. Set that Multi-Output Device as your macOS sound output.

<img src="assets/blackhole-use-for-sound-output.png" alt="Use Multi-Output for Sound Output" width="200" />

5. Start VoxNote and select the created output device as the recording source.

<img src="assets/screenshot.png" alt="VoxNote Screenshot" width="600" />


## TODOs

- [ ] add blackhole usage guide UI.
- [ ] refine UI.
- [ ] support customize the summary prompt.
- [ ] support word level timestamp hightlight for playing the record.
- [ ] support more mlx llm models.
- [ ] support system level shorcut to start/stop recording.
- [ ] support status bar menu.
