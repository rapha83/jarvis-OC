# JARVIS Voice

JARVIS Voice is a local-first macOS menu bar voice assistant for OpenClaw. Wake word, overlays, STT, TTS, diagnostics, hotkeys, screen/OCR context and OpenClaw streaming all run in the native Mac app.

> Status: personal assistant project under active development.

## Architecture

```text
macOS menu bar app
  -> wake word "Jarvis"
  -> native STT: Apple Speech, SpeechAnalyzer fallback, or Whisper/Core ML
  -> OpenClaw /v1/chat/completions streaming
  -> TTS: TTSKit helper, Azure Neural, custom command, or Apple Speech
  -> voice/text overlay, diagnostics, screen/OCR context
```

## Requirements

- macOS 15+ for the app bundle.
- OpenClaw gateway running locally, usually at `http://127.0.0.1:18789`.
- SwiftPM/Xcode command line tools for building the native app.

Optional native models can be placed under:

- `~/Library/Application Support/JARVIS/WhisperCoreML`
- `~/Library/Application Support/JARVIS/TTSKit`
- `~/Library/Application Support/JARVIS/WakeWord/JarvisWakeWord.mlmodelc`

Without local Whisper/TTSKit models, the linked runtimes may download/cache models on first use. Without `JarvisWakeWord.mlmodelc`, the Core ML wake-word engine falls back to Apple Speech.

## Build The macOS App

```bash
./script/build_and_run.sh build
open dist/JARVIS.app
```

Or build and open:

```bash
./script/build_and_run.sh run
```

The app reads the OpenClaw token from `~/.openclaw/openclaw.json`; it does not copy that token into JARVIS preferences. Azure Speech keys are stored in the macOS Keychain.

## macOS Features

- Wake word: default `Jarvis`.
- Global hotkeys for voice and text command overlay.
- Right Control push-to-talk toggle.
- Native text overlay above the Dock, with voice or text response mode.
- Native OpenClaw streaming with short conversation history.
- TTS by sentence/phrase for lower perceived latency.
- Barge-in and response cancellation.
- Agent picker and local voice/text commands to switch agents.
- Optional screen context and OCR via ScreenCaptureKit + Vision.
- Diagnostics, event timeline and TTS provider telemetry.
- Start at login via `SMAppService`.

## STT And Wake Word

Available command STT engines:

- `Apple Speech`: current most reliable default.
- `SpeechAnalyzer macOS 26`: experimental. It checks/downloads Apple assets and attempts native transcription first, but falls back to Apple Speech if it returns empty or fails.
- `Whisper/Core ML`: local WhisperKit/Argmax path when a compatible model is available.

Available wake-word engines:

- `Apple Speech`: default.
- `SpeechAnalyzer macOS 26`: experimental and currently falls back for continuous wake listening.
- `Detector dedicado local`: local fallback.
- `Core ML Jarvis`: requires a trained `JarvisWakeWord.mlmodelc`.

## TTS

Available TTS providers:

- `TTSKit Neural`: local neural TTS through `JarvisTTSHelper`.
- `Azure Neural (F0)`: optional cloud TTS with free-tier-compatible configuration.
- `TTS local por comando`: run a local command that writes an audio file.
- `Apple Speech` / `Apple Neural/Enhanced`: local fallback.

Azure settings are optional. If key, region or quota fail, JARVIS falls back to Apple Speech.

## Privacy

JARVIS is local-first, but some configured providers can send data outside the machine:

- OpenClaw receives the command text, short conversation history and optional OCR text.
- Azure Neural receives text only when the Azure TTS provider is selected.
- The app never sends screenshots directly to OpenClaw; OCR extracts text locally first.
- Diagnostics normally redact sensitive fields. When detailed logging is enabled, diagnostics can include command text, agent responses, app/window names and OCR snippets.

Detailed logging is disabled by default. Enable `Logging detalhado` only while troubleshooting, and turn it off before exporting or sharing logs publicly.

Logs live in:

```text
~/Library/Logs/JARVIS/diagnostics.jsonl
```

## Development

Build SwiftPM:

```bash
SWIFTPM_CACHE_PATH=.swiftpm-cache CLANG_MODULE_CACHE_PATH=.clang-cache swift build --package-path macos/JarvisMenuBar
```

Package app:

```bash
./script/build_and_run.sh build
```

Swift tests are not present yet. Recommended first tests:

- `WakeWordGate`
- `AgentSwitchCommand`
- `NativeVoiceDirectiveParser`
- `CommandPreflightFilter`
- `NativeOpenClawClient`

## Known Limitations

- SpeechAnalyzer is still experimental on macOS 26 and may fall back to Apple Speech.
- Core ML wake word needs a trained model.
- TTSKit model startup can be heavy; the helper runs as a resident process to keep it warm.
- Unsigned local builds may require opening the app manually from Finder or `open dist/JARVIS.app`.
