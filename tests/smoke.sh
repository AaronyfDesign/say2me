#!/bin/bash
# Headless smoke test: synthesize ZH/EN speech with `say`, run through the
# full Swift pipeline (decode -> WavWriter -> sherpa-onnx recognize).
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -O -parse-as-library \
  Sources/Prefs.swift Sources/HotkeyCenter.swift Sources/AudioRecorder.swift \
  Sources/Recognizer.swift Sources/TextInserter.swift Sources/DictationIndicator.swift Sources/DictationController.swift \
  Sources/SettingsView.swift Sources/ModelDownloader.swift tests/smoke.swift \
  -framework AppKit -framework AVFoundation -framework Carbon -framework ApplicationServices \
  -framework SwiftUI -framework Combine \
  -o tests/smoke

say -v Tingting '今天天气不错，我们去公园散步吧。' -o /tmp/sd_zh.aiff
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/sd_zh.aiff /tmp/sd_zh.wav
say -v Samantha 'Hello world, this is a local speech recognition test.' -o /tmp/sd_en.aiff
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/sd_en.aiff /tmp/sd_en.wav

echo "== ZH =="
./tests/smoke /tmp/sd_zh.wav zh
echo "== EN(auto) =="
./tests/smoke /tmp/sd_en.wav auto

rm -f /tmp/sd_zh.aiff /tmp/sd_zh.wav /tmp/sd_en.aiff /tmp/sd_en.wav
echo "SMOKE OK"
