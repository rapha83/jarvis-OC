# JARVIS Voice

JARVIS Voice is a local-first macOS menu bar voice assistant for OpenClaw. The main experience runs natively on macOS: wake word, overlays, STT, TTS, diagnostics, hotkeys, screen/OCR context and OpenClaw streaming all happen in the Mac app. The older Python/Docker web server remains as a legacy iPad/Safari client.

> Status: personal assistant project under active development. The macOS app is the primary runtime; the Docker server is legacy.

## Architecture

```text
macOS menu bar app
  -> wake word "Jarvis"
  -> native STT: Apple Speech, SpeechAnalyzer fallback, or Whisper/Core ML
  -> OpenClaw /v1/chat/completions streaming
  -> TTS: TTSKit helper, Azure Neural, custom command, or Apple Speech
  -> voice/text overlay, diagnostics, screen/OCR context

iPad/Safari legacy client
  -> HTTPS/WSS
  -> server.py in Docker
  -> faster-whisper + edge-tts + OpenClaw
```

## Requirements

- macOS 15+ for the app bundle.
- OpenClaw gateway running locally, usually at `http://127.0.0.1:18789`.
- SwiftPM/Xcode command line tools for building the native app.
- Docker only if you still want the legacy iPad/Safari web client.

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

The app reads the OpenClaw token from `~/.openclaw/openclaw.json`; it does not copy that token into JARVIS preferences. Azure Speech keys and the legacy Jarvis client token are stored in the macOS Keychain.

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
- `Detector dedicado local`: legacy fallback.
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

## Legacy iPad/Safari Server

The legacy server is optional and is not used by the main macOS app flow.

Create `.env` from `.env.example` and set a strong, private `JARVIS_CLIENT_TOKEN`:

```bash
cp .env.example .env
```

The Docker compose file binds the legacy server to `127.0.0.1:8765` on the host by default. Keep it local-only unless the iPad/Safari client is actively needed.

If you intentionally access the legacy server from another device, first set a strong `JARVIS_CLIENT_TOKEN`, then change the compose port mapping to a LAN binding and set `JARVIS_CERT_CN` / `JARVIS_CERT_SAN` in `.env` to include the Mac hostname/IP used by that device.

Then run:

```bash
docker-compose up -d --build
```

Protected legacy endpoints reject requests when `JARVIS_CLIENT_TOKEN` is empty. The web client stores the token in browser `localStorage` under `jarvis_client_token`.

The legacy WebSocket client currently sends that token as a query parameter during the WebSocket handshake. Treat this flow as local-only: do not put it behind public proxies, shared logs, tunnels or an internet-facing endpoint.

Useful commands:

```bash
docker-compose logs -f jarvis-voice
docker-compose down
docker-compose ps
```

## Environment

| Variable | Required | Description |
|---|---:|---|
| `OPENCLAW_URL` | legacy | OpenClaw gateway for the Docker server. |
| `OPENCLAW_CONFIG` | no | Optional OpenClaw config path mounted into Docker. |
| `OPENCLAW_TOKEN` | legacy | OpenClaw bearer token for Docker mode. |
| `OPENCLAW_AGENT` | no | Default legacy agent, default `it-infrastructure-specialist`. |
| `JARVIS_CLIENT_TOKEN` | legacy yes | Required token for `/api/*` and `/ws` in legacy mode. |
| `HOST_IP` | no | Bind address for direct `server.py` runs, default `127.0.0.1`. Docker sets this to `0.0.0.0` inside the container while the host port remains loopback-only by default. |
| `JARVIS_CERT_CN` | no | Self-signed HTTPS certificate common name for Docker mode. |
| `JARVIS_CERT_SAN` | no | Self-signed HTTPS certificate subjectAltName for Docker mode. |
| `WHISPER_MODEL` | no | faster-whisper model for Docker mode. |
| `TTS_VOICE` | no | edge-tts voice for Docker mode. |

## Development

Validate syntax:

```bash
PYTHONPYCACHEPREFIX=/tmp/jarvis-pycache python3 -m py_compile server.py
node -c static/app.js
```

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
- backend authorization rules

## Known Limitations

- SpeechAnalyzer is still experimental on macOS 26 and may fall back to Apple Speech.
- Core ML wake word needs a trained model.
- TTSKit model startup can be heavy; the helper runs as a resident process to keep it warm.
- Docker/iPad mode requires HTTPS for Safari microphone access.
- Unsigned local builds may require opening the app manually from Finder or `open dist/JARVIS.app`.
