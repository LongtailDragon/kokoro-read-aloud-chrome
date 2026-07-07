# Security Policy

## Supported Versions

This project currently supports the `main` branch only.

## Reporting a Vulnerability

Please do not open public issues for security problems.

1. Email a private report to: `security@example.com` (replace with your real contact before publishing).
2. Include reproduction steps, impact, and affected versions.
3. If possible, include a proposed fix or mitigation.

Expected response targets:
- Initial acknowledgement: within 72 hours.
- Triage decision: within 7 days.
- Status updates: at least every 14 days until resolution.

## Security Design Notes

### Authentication
- The local server supports optional bearer-token authentication via `KOKORO_API_TOKEN`.
- When set, `/speak` and `/stop` require `Authorization: Bearer <token>`.
- `health` remains unauthenticated for local monitoring.

### Authorization
- By default, the server binds to loopback (`127.0.0.1`).
- Binding to non-loopback hosts without `KOKORO_API_TOKEN` is blocked.

### Input Validation
- JSON content type is required for `/speak`.
- Request body size is limited via `KOKORO_MAX_JSON_BODY_BYTES`.
- Text length is limited via `KOKORO_MAX_REQUEST_CHARS`.
- `speed`, `voice`, and `lang` fields are validated and rejected when malformed.

### File Uploads
- The server has no file upload endpoints.

### Debug and Unsafe Defaults
- Flask debug mode is disabled.
- Unhandled errors return generic messages.
- Internal exception details are not exposed unless `KOKORO_EXPOSE_DEBUG_STATUS=true`.
- No test credentials or admin backdoors are included.

## Hardening Checklist for Deployers

- Set `KOKORO_API_TOKEN` and configure the extension with the same token.
- Keep server binding on loopback unless you understand network exposure risks.
- Restrict CORS origins using `KOKORO_ALLOWED_ORIGINS` when needed.
- Avoid sharing runtime logs publicly; logs may reveal local environment metadata.
