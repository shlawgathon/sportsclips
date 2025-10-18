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

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app and WebSocket
app = Flask(__name__)
sock = Sock(app)


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


def process_video_and_generate_snippets(video_url: str, ws: Any) -> None:
    """
    Process a video URL and generate snippets, streaming them via WebSocket.

    This is a placeholder implementation. In a real system, this would:
    1. Download/stream the video from the URL
    2. Use ML/AI to identify interesting segments
    3. Extract and encode those segments as MP4 files
    4. Stream each snippet back through the WebSocket

    Args:
        video_url: URL of the video to process
        ws: WebSocket connection object
    """
    # TODO: Implement actual video processing logic
    # This is a placeholder that demonstrates the API structure

    try:
        logger.info(f"Processing video: {video_url}")

        # Placeholder: In real implementation, process video and extract snippets
        # For now, send a mock snippet to demonstrate the API

        # Example snippet (would come from actual video processing)
        mock_video_data = b"mock_mp4_data"  # Replace with actual MP4 data

        snippet_message = create_snippet_message(
            video_data=mock_video_data,
            src_video_url=video_url,
            title="Placeholder Snippet",
            description="This is a placeholder. Implement video processing logic.",
        )

        ws.send(snippet_message)
        logger.info("Sent snippet to client")

        # Send completion message
        ws.send(create_complete_message(video_url))
        logger.info("Processing complete")

    except Exception as e:
        logger.error(f"Error processing video: {e}")
        ws.send(create_error_message(str(e), video_url))


@sock.route("/ws/video-snippets")
def video_snippets(ws: Any) -> None:
    """
    WebSocket endpoint for streaming video snippets.

    Accepts a 'video_url' query parameter and streams back processed video
    snippets as JSON messages containing base64-encoded MP4 data and metadata.

    Query Parameters:
        video_url (str): URL of the video to process

    WebSocket Message Format:
        Snippet: {"type": "snippet", "data": {"video_data": "...", "metadata": {...}}}
        Error: {"type": "error", "message": "...", "metadata": {...}}
        Complete: {"type": "snippet_complete", "metadata": {...}}
    """
    # Get video_url from query parameters
    video_url = request.args.get("video_url")

    if not video_url:
        error_msg = create_error_message("Missing required parameter: video_url")
        ws.send(error_msg)
        logger.warning("WebSocket connection missing video_url parameter")
        return

    logger.info(f"New WebSocket connection for video: {video_url}")

    # Process video and stream snippets
    process_video_and_generate_snippets(video_url, ws)


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
