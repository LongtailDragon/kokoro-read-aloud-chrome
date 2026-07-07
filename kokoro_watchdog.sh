#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/kokoro_watchdog.log"
SERVER_LOG="$LOG_DIR/kokoro_server.log"
SERVER_ERR_LOG="$LOG_DIR/kokoro_server.err.log"
CHECK_SECONDS=30
STARTUP_TIMEOUT_SECONDS=120

mkdir -p "$LOG_DIR"

python_bin=""
if [ -x "$SCRIPT_DIR/.venv/bin/python" ]; then
  python_bin="$SCRIPT_DIR/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  python_bin="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  python_bin="$(command -v python)"
else
  echo "Python 3 was not found. Install Python or create a .venv folder in the repository root." >&2
  exit 1
fi

log_line() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$1" >>"$WATCHDOG_LOG"
}

health_ok() {
  "$python_bin" - <<'PY'
import json
import sys
import urllib.request

try:
    with urllib.request.urlopen("http://127.0.0.1:8765/health", timeout=3) as response:
        payload = json.loads(response.read().decode("utf-8"))
    sys.exit(0 if payload.get("ok") is True else 1)
except Exception:
    sys.exit(1)
PY
}

start_server() {
  if health_ok; then
    return 0
  fi

  log_line "Starting Kokoro server."
  "$python_bin" -u "$SCRIPT_DIR/kokoro_server.py" >"$SERVER_LOG" 2>"$SERVER_ERR_LOG" &
  server_pid=$!
  log_line "Started Kokoro server PID $server_pid."

  deadline=$((SECONDS + STARTUP_TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if health_ok; then
      log_line "Kokoro server is healthy."
      return 0
    fi
    sleep 3
  done

  log_line "ERROR: Kokoro server did not become healthy within ${STARTUP_TIMEOUT_SECONDS} seconds."
  return 1
}

log_line 'Watchdog started.'
while true; do
  if ! health_ok; then
    log_line 'Health check failed.'
    start_server || true
  fi
  sleep "$CHECK_SECONDS"
done