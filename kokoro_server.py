import argparse
import itertools
import logging
import os
import re
import threading
import time
from dataclasses import dataclass, field
from ipaddress import ip_address

import sounddevice as sd
import torch
from flask import Flask, jsonify, request
from flask_cors import CORS
from kokoro import KPipeline


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_VOICE = "af_heart"
DEFAULT_SPEED = 1.0
MAX_REQUEST_CHARS = int(os.getenv("KOKORO_MAX_REQUEST_CHARS", "200000"))
MAX_JSON_BODY_BYTES = int(os.getenv("KOKORO_MAX_JSON_BODY_BYTES", "250000"))
API_TOKEN = os.getenv("KOKORO_API_TOKEN", "").strip()
EXPOSE_DEBUG_STATUS = os.getenv("KOKORO_EXPOSE_DEBUG_STATUS", "false").strip().lower() == "true"

ALLOWED_LANG_RE = re.compile(r"^[a-z]{1,8}$")
ALLOWED_VOICE_RE = re.compile(r"^[a-z]{2}_[a-z0-9]+$")


@dataclass
class ServerState:
    pipeline: KPipeline | None = None
    lang: str = "a"
    device: str = "cuda" if torch.cuda.is_available() else "cpu"
    state_lock: threading.Lock = field(default_factory=threading.Lock)
    playback_lock: threading.Lock = field(default_factory=threading.Lock)
    current_stop: threading.Event | None = None
    current_thread: threading.Thread | None = None
    request_ids: itertools.count = field(default_factory=lambda: itertools.count(1))
    last_status: dict = field(default_factory=lambda: {"state": "idle"})


state = ServerState()
app = Flask(__name__)
default_origins = ["chrome-extension://*", "http://localhost:*", "http://127.0.0.1:*"]
origins_env = os.getenv("KOKORO_ALLOWED_ORIGINS", "")
allowed_origins = [origin.strip() for origin in origins_env.split(",") if origin.strip()] or default_origins
CORS(app, resources={r"/*": {"origins": allowed_origins}})


def require_auth() -> bool:
    if not API_TOKEN:
        return True
    authz = request.headers.get("Authorization", "")
    return authz == f"Bearer {API_TOKEN}"


@app.get("/health")
def health():
    with state.state_lock:
        speaking = state.current_thread is not None and state.current_thread.is_alive()
        last_status = dict(state.last_status)
    payload = {
        "ok": True,
        "service": "kokoro-read-aloud-server",
        "device": state.device,
        "cuda_available": torch.cuda.is_available(),
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
        "pipeline_loaded": state.pipeline is not None,
        "speaking": speaking,
        "auth_required": bool(API_TOKEN),
    }
    if EXPOSE_DEBUG_STATUS:
        payload["last_status"] = last_status
    return jsonify(payload)


@app.post("/stop")
def stop():
    if not require_auth():
        return jsonify({"ok": False, "error": "Unauthorized."}), 401
    cancel_current_read()
    return jsonify({"ok": True})


@app.post("/speak")
def speak():
    if not require_auth():
        return jsonify({"ok": False, "error": "Unauthorized."}), 401

    if not request.is_json:
        return jsonify({"ok": False, "error": "Content-Type must be application/json."}), 415
    if request.content_length and request.content_length > MAX_JSON_BODY_BYTES:
        return jsonify({"ok": False, "error": "Request body too large."}), 413

    payload = request.get_json(silent=True) or {}
    text = str(payload.get("text", "")).strip()
    voice = str(payload.get("voice", DEFAULT_VOICE)).strip() or DEFAULT_VOICE
    try:
        speed = float(payload.get("speed", DEFAULT_SPEED))
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "Speed must be a number."}), 400

    lang = str(payload.get("lang", state.lang)).strip() or state.lang

    if not text:
        return jsonify({"ok": False, "error": "No text provided."}), 400
    # Keep a high guardrail so accidental huge selections do not lock up the
    # local TTS process.
    if len(text) > MAX_REQUEST_CHARS:
        return jsonify({"ok": False, "error": f"Text is too long. Limit is {MAX_REQUEST_CHARS:,} characters."}), 400
    if speed < 0.5 or speed > 2.0:
        return jsonify({"ok": False, "error": "Speed must be between 0.5 and 2.0."}), 400
    if not ALLOWED_LANG_RE.fullmatch(lang):
        return jsonify({"ok": False, "error": "Invalid language code."}), 400
    if not ALLOWED_VOICE_RE.fullmatch(voice):
        return jsonify({"ok": False, "error": "Invalid voice identifier."}), 400

    request_id = start_new_read(text=text, voice=voice, speed=speed, lang=lang)
    return jsonify({"ok": True, "accepted": True, "request_id": request_id, "device": state.device})


def cancel_current_read():
    with state.state_lock:
        stop_event = state.current_stop
        old_thread = state.current_thread
        state.last_status = {"state": "cancel_requested", "at": time.time()}

    if stop_event is not None:
        stop_event.set()
    sd.stop()

    # Do not wait for the old worker here. The new /speak request should return
    # immediately; the new worker will take the playback lock as soon as the old
    # worker finishes unwinding from sd.stop().


def start_new_read(text: str, voice: str, speed: float, lang: str) -> int:
    cancel_current_read()
    stop_event = threading.Event()
    request_id = next(state.request_ids)
    worker = threading.Thread(
        target=read_worker,
        kwargs={
            "request_id": request_id,
            "text": text,
            "voice": voice,
            "speed": speed,
            "lang": lang,
            "stop_event": stop_event,
        },
        daemon=True,
    )

    with state.state_lock:
        state.current_stop = stop_event
        state.current_thread = worker
        state.last_status = {"state": "starting", "request_id": request_id, "at": time.time()}

    worker.start()
    return request_id


def read_worker(request_id: int, text: str, voice: str, speed: float, lang: str, stop_event: threading.Event):
    started = time.perf_counter()
    chunks = 0
    try:
        # Kokoro and the sound device are shared process-wide resources. Keep only
        # one worker inside generation/playback at a time; new requests cancel the
        # old worker first, then wait here only if it is still cleaning up.
        with state.playback_lock:
            if stop_event.is_set():
                mark_status("cancelled", request_id, chunks, started)
                return

            ensure_pipeline(lang)
            mark_status("speaking", request_id, chunks, started)

            for _graphemes, _phonemes, audio in state.pipeline(text, voice=voice, speed=speed):
                if stop_event.is_set():
                    mark_status("cancelled", request_id, chunks, started)
                    return
                chunks += 1
                sd.play(audio, 24000)
                sd.wait()
                if stop_event.is_set():
                    mark_status("cancelled", request_id, chunks, started)
                    return

            mark_status("finished", request_id, chunks, started)
    except Exception as exc:
        app.logger.exception("Read worker failed for request_id=%s", request_id)
        with state.state_lock:
            state.last_status = {
                "state": "error",
                "request_id": request_id,
                "elapsed_seconds": round(time.perf_counter() - started, 3),
            }


def mark_status(status: str, request_id: int, chunks: int, started: float):
    with state.state_lock:
        state.last_status = {
            "state": status,
            "request_id": request_id,
            "chunks": chunks,
            "elapsed_seconds": round(time.perf_counter() - started, 3),
        }


def ensure_pipeline(lang: str):
    # Rebuild the pipeline only when the requested language changes.
    if state.pipeline is None or lang != state.lang:
        state.lang = lang
        state.pipeline = KPipeline(lang_code=lang, device=state.device)


def parse_args():
    parser = argparse.ArgumentParser(description="Local Kokoro TTS HTTP server for Chrome extension.")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
    return parser.parse_args()


@app.errorhandler(Exception)
def handle_unexpected_error(_exc):
    app.logger.exception("Unhandled server error")
    return jsonify({"ok": False, "error": "Internal server error."}), 500


def host_is_loopback(host: str) -> bool:
    if host in {"localhost", "127.0.0.1", "::1"}:
        return True
    try:
        return ip_address(host).is_loopback
    except ValueError:
        return False


def main():
    args = parse_args()
    if args.device == "auto":
        state.device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        state.device = args.device

    if state.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA requested, but torch.cuda.is_available() is False.")
    if not host_is_loopback(args.host) and not API_TOKEN:
        raise RuntimeError("Refusing non-loopback bind without KOKORO_API_TOKEN set.")

    app.config["PROPAGATE_EXCEPTIONS"] = False
    app.logger.setLevel(logging.INFO)

    print("Kokoro Read Aloud server")
    print(f"Device: {state.device}")
    if state.device == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(0)}")
    print(f"Listening on http://{args.host}:{args.port}")
    print(f"Auth token required: {'yes' if API_TOKEN else 'no'}")
    print("Loading Kokoro pipeline now so the first browser read is responsive...")
    ensure_pipeline(state.lang)
    print("Kokoro pipeline loaded.")
    print("Keep this window open while using the Chrome right-click menu.")
    print("New read requests interrupt the current read immediately.")

    app.run(host=args.host, port=args.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
