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

The macOS app stores provider secrets in Keychain. The legacy Docker server reads secrets from environment variables.

## Legacy Server

The Python/Docker server is legacy and should be treated as a local-network service. Set `JARVIS_CLIENT_TOKEN` before enabling `/api/*` or `/ws`, and prefer loopback binding unless the iPad/Safari client is actively needed.
