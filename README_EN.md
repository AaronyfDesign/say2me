# SenseDict

English | [中文](README.md)

A local dictation tool for macOS: double-tap Control to start dictation, tap the trigger again to stop (or let it auto-stop), and the recognized text is pasted at your cursor. Powered by the SenseVoice-Small model with sherpa-onnx inference — fully offline, your audio never leaves the machine.

## Features

- Customizable trigger: double-tap Control / Option / Command, or record any key combo
- Auto-stops after 30 seconds by default (configurable)
- Auto language detection (Chinese, Cantonese, English, Japanese, Korean), or lock to one
- Result pasted at the cursor (or copied to clipboard only)
- Menu bar resident, no Dock icon

## Requirements

- macOS 13+, Apple Silicon
- Xcode Command Line Tools (build time only)

## Quick Start

```bash
# 1. Download sherpa-onnx binaries (one-time)
mkdir -p vendor
curl -sL -o /tmp/sherpa.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.1/sherpa-onnx-v2.0.1-osx-arm64-shared.tar.bz2
tar xjf /tmp/sherpa.tar.bz2 -C vendor

# 2. Download the SenseVoice-Small int8 model (~230MB)
mkdir -p models/sense-voice
curl -sL -o models/sense-voice/model.int8.onnx \
  https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx
curl -sL -o models/sense-voice/tokens.txt \
  https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt

# 3. Build
./build.sh

# 4. Run
open build/SenseDict.app
```

## First-run Permissions

Two permissions are required:

1. **Accessibility** — for modifier double-tap detection and simulating Cmd+V.
   System Settings → Privacy & Security → Accessibility, enable SenseDict.
   If it shows as "unknown", quit the app and relaunch it, then re-check.
2. **Microphone** — prompted on first dictation.

After granting Accessibility, quit and relaunch the app for the event tap to become active.

## Usage

1. Double-tap Control (default) to start — you'll hear a chime and a "listening…" pill appears near the caret
2. Speak
3. Tap the same trigger once to finish (stop chime), or wait for the auto-stop
4. After ~0.5s the text is pasted at your cursor

Double-tap to start, single-tap to stop: only isolated presses count; typing, chords and scrolling never trigger it. Trigger activity within 0.3s after start is ignored (guards against the double-tap tail).

The settings panel (menu bar icon → Settings…) lets you change the trigger, language, inverse text normalization, insertion mode, and includes a "record 3s and recognize" test button.

## Project Layout

```
Sources/          Swift sources (no Xcode project; compiled with swiftc)
  main.swift            Menu bar entry point
  HotkeyCenter.swift    Modifier double-tap detection + custom hotkeys
  AudioRecorder.swift   Mic capture + WAV writing
  Recognizer.swift      sherpa-onnx CLI invocation
  DictationController.swift   State machine
  TextInserter.swift    Clipboard swap + simulated paste
  SettingsView.swift    Settings window (SwiftUI)
tests/smoke.swift       Headless end-to-end smoke test (decode→WAV→recognize)
build.sh                Build script
```

## Smoke Test

```bash
bash tests/smoke.sh
```

Synthesizes Chinese/English speech with the system `say` voice and runs it through the full pipeline — no mic or GUI needed.

## Known Limitations

- Recognition is non-streaming: results appear once per utterance, no incremental display
- No hotword / custom vocabulary support
- Paste mode briefly occupies the clipboard (~1.5s; original contents restored only if nothing else touched the board)
- The pill position uses the caret's Accessibility bounds, falling back to the mouse; some custom-drawn text fields may not be locatable
- Start/stop chimes use system sounds (Tink / Pop), can be turned off in settings
