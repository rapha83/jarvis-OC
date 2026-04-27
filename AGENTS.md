# AGENTS.md — jarvis-voice

JARVIS Voice is a local-first macOS menu bar assistant for OpenClaw. The native macOS app is the primary runtime; the Python/Docker server is kept only for the legacy iPad/Safari web client.

## Primary Runtime

```text
macOS app -> native STT/TTS -> OpenClaw gateway -> agent/tools
```

Key paths:

- `macos/JarvisMenuBar/`: SwiftUI menu bar app.
- `macos/JarvisMenuBar/Sources/Jarvis/App/JarvisAppModel.swift`: central app model, grouped by settings/diagnostics, STT, wake word, text/agent commands, TTS and voice flow.
- `macos/JarvisMenuBar/Sources/Jarvis/Services/`: native services.
- `script/build_and_run.sh`: builds/packages `dist/JARVIS.app`.

## Legacy Runtime

```text
iPad/Safari -> HTTPS/WSS -> server.py (Docker) -> faster-whisper/edge-tts/OpenClaw
```

Legacy endpoints require `JARVIS_CLIENT_TOKEN`. Do not make the legacy server reachable on a LAN without a strong token.

## Development Commands

```bash
PYTHONPYCACHEPREFIX=/tmp/jarvis-pycache python3 -m py_compile server.py
node -c static/app.js
SWIFTPM_CACHE_PATH=.swiftpm-cache CLANG_MODULE_CACHE_PATH=.clang-cache swift build --package-path macos/JarvisMenuBar
./script/build_and_run.sh build
```

## Safety Notes

- Do not commit `.env`, TLS keys/certs, build output, logs, diagnostics exports, `.claude/`, `.codex/` or local model bundles.
- Azure Speech keys and legacy Jarvis client tokens belong in Keychain or environment variables, never source.
- Detailed diagnostics may include transcripts, agent responses and OCR text. Disable detailed logging before exporting logs for public sharing.
- Prefer small, focused changes. Preserve the native macOS flow and keep Docker/iPad behavior as legacy compatibility.
