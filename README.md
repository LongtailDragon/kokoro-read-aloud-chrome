# Kokoro Read Aloud (Chrome Extension + Local TTS Server)

[![CI](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![Secret Scan](../../actions/workflows/secret-scan.yml/badge.svg)](../../actions/workflows/secret-scan.yml)

Kokoro Read Aloud lets you highlight text in Chrome, right-click, and play the selection through a local Kokoro text-to-speech server.

## What the project does

- Adds a Chrome context-menu command: **Read with Kokoro**.
- Sends selected text to a local HTTP server.
- Uses Kokoro TTS to generate audio and play it on your machine.
- Interrupts current speech when a new read request arrives.
- Includes optional watchdog scripts to keep the local server alive.

## Installation

### 1) Clone the repository

```bash
git clone <your-repo-url>
cd Kokoro
```

### 2) Install Python dependencies

Windows (PowerShell):

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install flask flask-cors sounddevice torch kokoro
```

Linux/macOS (bash):

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install flask flask-cors sounddevice torch kokoro
```

### 3) Load the extension in Chrome

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked**.
4. Select this repository folder (the one containing `manifest.json`).

### 4) Start the local server

Windows:

```powershell
.\start_kokoro_server.bat
```

Linux/macOS:

```bash
./start_kokoro_server.sh
```

## Usage examples

### Example 1: Basic read-aloud

1. Highlight text on any webpage.
2. Right-click and choose **Read with Kokoro**.
3. Audio plays locally.

### Example 2: Custom server options

Open the extension options page and configure:

- Server URL (default: `http://127.0.0.1:8765`)
- Voice
- Speed
- Maximum selected characters
- Optional API token

### Example 3: Direct API call (manual test)

```bash
curl -X POST "http://127.0.0.1:8765/speak" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <KOKORO_API_TOKEN-if-configured>" \
  -d '{"text":"Hello from Kokoro","voice":"af_heart","speed":1.0}'
```

## Configuration requirements

- Chrome extension permission to call local host (`127.0.0.1` / `localhost`).
- Python runtime with audio output support.
- Local Kokoro server running and reachable from Chrome.
- If token auth is enabled, the same token must be configured in server env and extension options.

## Environment variables

Use `.env.example` as a template.

- `KOKORO_API_TOKEN`: Optional bearer token for `/speak` and `/stop`.
- `KOKORO_ALLOWED_ORIGINS`: Optional comma-separated CORS allowlist.
- `KOKORO_MAX_REQUEST_CHARS`: Max text length accepted by `/speak`.
- `KOKORO_MAX_JSON_BODY_BYTES`: Max request body size.
- `KOKORO_EXPOSE_DEBUG_STATUS`: `true` exposes internal status details in `/health`.

Do not commit real secrets. Use placeholders in docs and env files.

## Known limitations

- Designed for local use; not intended as a multi-user internet service.
- Audio playback behavior depends on OS audio stack and device settings.
- Very large text selections can take significant time and memory.
- Voice availability and quality depend on installed Kokoro model/runtime setup.
- Browser pages that block script injection may provide truncated selection text fallback.

## Security notes

- Default bind host is loopback (`127.0.0.1`).
- Non-loopback bind without `KOKORO_API_TOKEN` is rejected.
- Error responses are sanitized; internal traces are not returned by default.
- See `SECURITY.md` for vulnerability reporting and hardening guidance.

## Project governance

- Contribution guide: `CONTRIBUTING.md`
- Changelog: `CHANGELOG.md`
- Security policy: `SECURITY.md`
- License: `LICENSE`

## Repository hygiene

- Secret scanning is automated with GitHub Actions (`.github/workflows/secret-scan.yml`).
- Basic CI validation runs on every push and pull request (`.github/workflows/ci.yml`).
- Runtime logs and temporary artifacts are ignored via `.gitignore`.

## License

MIT. See `LICENSE`.
