# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- GitHub Actions secret scanning workflow.
- GitHub Actions CI workflow for syntax and manifest validation.
- MIT license file.
- Security policy and vulnerability reporting guidance.
- Environment variable template (`.env.example`).
- Contributor guide.

### Changed
- README expanded for public release quality and completeness.
- Optional bearer token support added to extension options and request headers.
- Scheduled task registration script now resolves paths relative to script location.

### Security
- `/speak` and `/stop` support optional bearer token auth when `KOKORO_API_TOKEN` is set.
- Input validation hardened for content type, size, speed, voice, and language fields.
- Server now returns sanitized internal error responses.
- Non-loopback bind without token is refused.
