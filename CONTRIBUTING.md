# Contributing

Thanks for helping improve Kokoro Read Aloud.

## Development setup

1. Clone the repo and enter the project directory.
2. Create and activate a Python virtual environment.
3. Install dependencies:
   - `flask`
   - `flask-cors`
   - `sounddevice`
   - `torch`
   - `kokoro`
4. Load the extension in Chrome via `chrome://extensions` and **Load unpacked**.

## Branch and PR guidelines

1. Create a feature branch from `main`.
2. Keep changes focused and include docs updates when behavior changes.
3. Run local checks before opening a PR:
   - `python -m py_compile kokoro_server.py`
4. Open a pull request with:
   - Problem statement
   - Approach summary
   - Testing notes
   - Screenshots (if UI/options changed)

## Security and secrets

- Do not commit API keys, tokens, or credentials.
- Use `.env.example` placeholders only.
- If you discover a vulnerability, follow `SECURITY.md` and report privately.

## Coding expectations

- Keep defaults safe for local usage.
- Avoid machine-specific absolute paths.
- Preserve backward compatibility for extension settings where possible.
- Prefer clear errors and never expose stack traces to clients in normal operation.
