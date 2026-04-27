#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="JARVIS"
BUNDLE_ID="local.jarvis.voice.menubar"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/JarvisMenuBar"
DIST_DIR="$ROOT_DIR/dist"
export SWIFTPM_CACHE_PATH="$ROOT_DIR/.swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-cache"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
TTS_HELPER_BINARY="$APP_MACOS/JarvisTTSHelper"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_ICON="$ROOT_DIR/assets/jarvis-app-icon.png"
STATUS_ICON="$ROOT_DIR/assets/jarvis-menubar.png"
WHISPER_MODEL_DIR="${JARVIS_WHISPER_MODEL_DIR:-$HOME/Library/Application Support/JARVIS/WhisperCoreML}"
TTSKIT_MODEL_DIR="${JARVIS_TTSKIT_MODEL_DIR:-$HOME/Library/Application Support/JARVIS/TTSKit}"
WAKEWORD_MODEL_DIR="${JARVIS_WAKEWORD_MODEL_DIR:-$HOME/Library/Application Support/JARVIS/WakeWord}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR"
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_NAME"
HELPER_BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/JarvisTTSHelper"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -f "$HELPER_BUILD_BINARY" ]]; then
  cp "$HELPER_BUILD_BINARY" "$TTS_HELPER_BINARY"
  chmod +x "$TTS_HELPER_BINARY"
fi
swift "$ROOT_DIR/script/generate_app_icon.swift" "$APP_RESOURCES" "$SOURCE_ICON" "$STATUS_ICON"
if [[ -d "$WHISPER_MODEL_DIR" ]]; then
  mkdir -p "$APP_RESOURCES/WhisperCoreML"
  ditto "$WHISPER_MODEL_DIR" "$APP_RESOURCES/WhisperCoreML"
fi
if [[ -d "$TTSKIT_MODEL_DIR" ]]; then
  mkdir -p "$APP_RESOURCES/TTSKit"
  ditto "$TTSKIT_MODEL_DIR" "$APP_RESOURCES/TTSKit"
fi
if [[ -d "$WAKEWORD_MODEL_DIR/JarvisWakeWord.mlmodelc" ]]; then
  ditto "$WAKEWORD_MODEL_DIR/JarvisWakeWord.mlmodelc" "$APP_RESOURCES/JarvisWakeWord.mlmodelc"
elif [[ -f "$WAKEWORD_MODEL_DIR/JarvisWakeWord.mlmodel" ]]; then
  cp "$WAKEWORD_MODEL_DIR/JarvisWakeWord.mlmodel" "$APP_RESOURCES/JarvisWakeWord.mlmodel"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>JARVIS</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>JARVIS precisa acessar o microfone para detectar a palavra Jarvis e ouvir comandos de voz.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>JARVIS usa reconhecimento de fala do macOS para detectar a palavra Jarvis.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>JARVIS pode capturar a tela para ler texto com OCR quando voce ativar o contexto visual.</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build|package)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|package|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
