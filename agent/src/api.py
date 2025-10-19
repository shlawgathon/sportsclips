"""
ASGI WebSocket API for streaming video snippets using FastAPI + Uvicorn.

This module exposes an async WebSocket endpoint and runs each pipeline
in an isolated subprocess to avoid collisions.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import multiprocessing as mp
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect

from .pipeline import create_highlight_pipeline

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI apuv run uvicorn src.api:app --host 0.0.0.0 --port 8000 --reloadp
app = FastAPI(title="SportsClips Agent (ASGI)")

# Initialize a pipeline instance for direct programmatic calls and tests
pipeline = create_highlight_pipeline(base_chunk_duration=4, window_size=9, slide_step=3)


def create_snippet_message(
    video_data: bytes, src_video_url: str, title: str, description: str
) -> str:
    """Create a JSON message containing a video snippet and metadata."""
    message = {
        "type": "snippet",
        "data": {
            "video_data": base64.b64encode(video_data).decode("utf-8"),
            "metadata": {
                "src_video_url": src_video_url,
                "title": title,
                "description": description,
            },
        },
    }
    return json.dumps(message)


def create_error_message(error: str, src_video_url: str | None = None) -> str:
    """Create a JSON error message."""
    message: dict[str, Any] = {"type": "error", "message": error}
    if src_video_url:
        message["metadata"] = {"src_video_url": src_video_url}
    return json.dumps(message)


def create_complete_message(src_video_url: str) -> str:
    """Create a JSON completion message."""
    message = {
        "type": "snippet_complete",
        "metadata": {"src_video_url": src_video_url},
    }
    return json.dumps(message)


def process_video_and_generate_snippets(video_url: str, ws: Any, is_live: bool) -> None:
    """Programmatic entry used by tests; runs the async pipeline if needed."""
    import asyncio as _asyncio
    import inspect

    result = pipeline.process_video_url(
        video_url=video_url,
        ws=ws,
        is_live=is_live,
        create_snippet_message=create_snippet_message,
        create_complete_message=create_complete_message,
        create_error_message=create_error_message,
    )
    if inspect.isawaitable(result):
        _asyncio.run(result)


SENTINEL_DONE = "__PIPELINE_DONE__"


class QueueWebSocket:
    """Minimal ws-like object that pushes messages into a multiprocessing queue."""

    def __init__(self, queue: mp.Queue[str]):
        self._q = queue

    def send(self, message: str) -> None:
        self._q.put(message)


def _pipeline_worker(video_url: str, is_live: bool, q: mp.Queue[str]) -> None:
    """Worker process entrypoint to run the async pipeline."""
    try:
        child_pipeline = create_highlight_pipeline(
            base_chunk_duration=4, window_size=9, slide_step=3
        )
        ws = QueueWebSocket(q)

        async def run() -> None:
            await child_pipeline.process_video_url(
                video_url=video_url,
                ws=ws,
                is_live=is_live,
                create_snippet_message=create_snippet_message,
                create_complete_message=create_complete_message,
                create_error_message=create_error_message,
            )

        asyncio.run(run())
    except Exception as e:
        try:
            q.put(create_error_message(str(e), video_url))
        except Exception:
            pass
    finally:
        try:
            q.put(SENTINEL_DONE)
        except Exception:
            pass


@app.websocket("/ws/video-snippets")
async def video_snippets_ws(
    websocket: WebSocket,
    video_url: str = Query(...),
    is_live: bool = Query(...),
) -> None:
    """ASGI WebSocket endpoint that streams snippet messages."""
    await websocket.accept()

    ctx = mp.get_context("spawn")
    q: mp.Queue[str] = ctx.Queue()
    proc = ctx.Process(
        target=_pipeline_worker, args=(video_url, is_live, q), daemon=True
    )
    proc.start()

    try:
        while True:
            try:
                msg = await asyncio.to_thread(q.get, timeout=1.0)
            except Exception:
                if not proc.is_alive():
                    break
                continue

            if msg == SENTINEL_DONE:
                break

            await websocket.send_text(msg)

    except WebSocketDisconnect:
        pass
    finally:
        if proc.is_alive():
            proc.terminate()
        proc.join(timeout=5)

        try:
            while True:
                try:
                    q.get_nowait()
                except Exception:
                    break
            q.close()
        except Exception:
            pass


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "healthy"}


def run_server(host: str = "0.0.0.0", port: int = 8000, debug: bool = False) -> None:
    """Run the ASGI server with uvicorn."""
    import uvicorn

    uvicorn.run(app, host=host, port=port, log_level=("debug" if debug else "info"))


if __name__ == "__main__":
    run_server(debug=False)
