# AGENTS.md — jarvis-voice

JARVIS Voice is a local-first macOS menu bar assistant for OpenClaw. The native macOS app is the public runtime; legacy Python/Docker web files are local-only and should stay untracked.

## Primary Runtime

```text
macOS app -> native STT/TTS -> OpenClaw gateway -> agent/tools
```

Key paths:

- `macos/JarvisMenuBar/`: SwiftUI menu bar app.
- `macos/JarvisMenuBar/Sources/Jarvis/App/JarvisAppModel.swift`: central app model, grouped by settings/diagnostics, STT, wake word, text/agent commands, TTS and voice flow.
- `macos/JarvisMenuBar/Sources/Jarvis/Services/`: native services.
- `script/build_and_run.sh`: builds/packages `dist/JARVIS.app`.

## Development Commands

```bash
SWIFTPM_CACHE_PATH=.swiftpm-cache CLANG_MODULE_CACHE_PATH=.clang-cache swift build --package-path macos/JarvisMenuBar
./script/build_and_run.sh build
```

## Safety Notes

- Do not commit `.env`, TLS keys/certs, build output, logs, diagnostics exports, `.claude/`, `.codex/`, local legacy Docker/web files or local model bundles.
- Azure Speech keys belong in Keychain, never source.
- Detailed diagnostics may include transcripts, agent responses and OCR text. Disable detailed logging before exporting logs for public sharing.
- Prefer small, focused changes. Preserve the native macOS flow.
