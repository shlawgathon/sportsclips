"""
Flask WebSocket API for streaming video snippets.

This module provides a WebSocket endpoint that accepts a video URL and streams
back processed video snippets as base64-encoded MP4 data with metadata.
"""

import base64
import json
import logging
from typing import Any

from flask import Flask, request
from flask_sock import Sock

from .pipeline import create_highlight_pipeline

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app and WebSocket
app = Flask(__name__)
sock = Sock(app)

# Initialize video pipeline with sliding window
pipeline = create_highlight_pipeline(base_chunk_duration=2, window_size=7, slide_step=2)


def create_snippet_message(
    video_data: bytes, src_video_url: str, title: str, description: str
) -> str:
    """
    Create a JSON message containing a video snippet and metadata.

    Args:
        video_data: Raw MP4 video data
        src_video_url: Original source video URL
        title: Title/name of the snippet
        description: Description of the snippet content

    Returns:
        JSON string containing the snippet message
    """
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
    """
    Create a JSON error message.

    Args:
        error: Error description
        src_video_url: Original source video URL (optional)

    Returns:
        JSON string containing the error message
    """
    message: dict[str, Any] = {"type": "error", "message": error}
    if src_video_url:
        message["metadata"] = {"src_video_url": src_video_url}
    return json.dumps(message)


def create_complete_message(src_video_url: str) -> str:
    """
    Create a JSON completion message.

    Args:
        src_video_url: Original source video URL

    Returns:
        JSON string containing the completion message
    """
    message = {
        "type": "snippet_complete",
        "metadata": {"src_video_url": src_video_url},
    }
    return json.dumps(message)


def process_video_and_generate_snippets(video_url: str, ws: Any, is_live: bool) -> None:
    """
    Process a video URL and generate snippets, streaming them via WebSocket.

    Downloads the video, splits it into 15-second chunks, and streams each
    chunk back through the WebSocket.

    Args:
        video_url: URL of the video to process
        ws: WebSocket connection object
        is_live: Whether the video is a live stream
    """
    # Use the pipeline to process the video
    pipeline.process_video_url(
        video_url=video_url,
        ws=ws,
        is_live=is_live,
        create_snippet_message=create_snippet_message,
        create_complete_message=create_complete_message,
        create_error_message=create_error_message,
    )


@sock.route("/ws/video-snippets")
def video_snippets(ws: Any) -> None:
    """
    WebSocket endpoint for streaming video snippets.

    Accepts 'video_url' and 'is_live' query parameters and streams back processed
    video snippets as JSON messages containing base64-encoded MP4 data and metadata.

    Query Parameters:
        video_url (str): URL of the video to process
        is_live (bool): Whether the video is a live stream

    WebSocket Message Format:
        Snippet: {"type": "snippet", "data": {"video_data": "...", "metadata": {...}}}
        Error: {"type": "error", "message": "...", "metadata": {...}}
        Complete: {"type": "snippet_complete", "metadata": {...}}
    """
    # Get video_url from query parameters
    video_url = request.args.get("video_url")
    is_live_str = request.args.get("is_live")

    if not video_url:
        error_msg = create_error_message("Missing required parameter: video_url")
        ws.send(error_msg)
        logger.warning("WebSocket connection missing video_url parameter")
        return

    if is_live_str is None:
        error_msg = create_error_message("Missing required parameter: is_live")
        ws.send(error_msg)
        logger.warning("WebSocket connection missing is_live parameter")
        return

    # Parse is_live as boolean
    is_live = is_live_str.lower() in ("true", "1", "yes")

    logger.info(f"New WebSocket connection for video: {video_url} (is_live={is_live})")

    # Process video and stream snippets
    process_video_and_generate_snippets(video_url, ws, is_live)


@app.route("/health")
def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "healthy"}


def run_server(host: str = "0.0.0.0", port: int = 5000, debug: bool = False) -> None:
    """
    Run the Flask application.

    Args:
        host: Host to bind to
        port: Port to bind to
        debug: Enable debug mode
    """
    logger.info(f"Starting server on {host}:{port}")
    app.run(host=host, port=port, debug=debug)


if __name__ == "__main__":
    run_server(debug=True)
