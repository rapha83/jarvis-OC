# Security Policy

## Reporting

Please report security issues privately through GitHub private vulnerability reporting when available. If that is not enabled, open a private issue/contact path before posting exploit details publicly.

## Sensitive Data

JARVIS can handle voice transcripts, agent responses, OCR text, local app/window context and provider credentials. Do not attach diagnostics publicly unless you have reviewed or redacted them.

Secrets must not be committed:

- `.env`
- OpenClaw tokens
- Azure Speech keys
- TLS private keys/certificates
- exported diagnostics/log bundles

The macOS app stores provider secrets in Keychain and reads OpenClaw gateway credentials from the local OpenClaw configuration.

## Public Repository Scope

The public repository is scoped to the native macOS app. Local legacy web/Docker files, environment files, diagnostics exports, build products and private assistant configuration should remain untracked.
