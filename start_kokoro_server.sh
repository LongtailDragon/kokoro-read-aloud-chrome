#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON_BIN=""
if [ -x "$SCRIPT_DIR/.venv/bin/python" ]; then
  PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  echo "Python 3 was not found. Install Python or create a .venv folder in the repository root." >&2
  exit 1
fi

port_is_open() {
  "$PYTHON_BIN" - <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.25)
try:
    sys.exit(0 if sock.connect_ex(("127.0.0.1", 8765)) == 0 else 1)
finally:
    sock.close()
PY
}

if port_is_open; then
  exit 0
fi

export PYTHONDONTWRITEBYTECODE=1
exec "$PYTHON_BIN" -u kokoro_server.py