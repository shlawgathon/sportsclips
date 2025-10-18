#!/usr/bin/env python3
"""
Test WebSocket client for manually testing the Flask API.
Tests sending a video URL and receiving 15-second chunks with metadata.
Saves received MP4 chunks to the video_output directory.
"""

import base64
import json
import sys
from pathlib import Path

import websocket

# Output directory for saved videos
OUTPUT_DIR = Path(__file__).parent.parent / "video_output"


def ensure_output_dir():
    """Ensure the output directory exists."""
    OUTPUT_DIR.mkdir(exist_ok=True)
    print(f"Output directory: {OUTPUT_DIR}")


def save_video_chunk(video_data_b64: str, chunk_number: int, title: str) -> str:
    """
    Save a base64-encoded video chunk to disk.

    Args:
        video_data_b64: Base64-encoded video data
        chunk_number: Chunk number for filename
        title: Title of the chunk

    Returns:
        Path to the saved file
    """
    # Decode base64 video data
    video_data = base64.b64decode(video_data_b64)

    # Create filename
    safe_title = "".join(
        c if c.isalnum() or c in (" ", "-", "_") else "_" for c in title
    )
    filename = f"chunk_{chunk_number:03d}_{safe_title}.mp4"
    filepath = OUTPUT_DIR / filename

    # Write to file
    with open(filepath, "wb") as f:
        f.write(video_data)

    return str(filepath)


# Counter for chunks
chunk_counter = 0


def on_message(ws, message):
    """Handle incoming WebSocket messages."""
    global chunk_counter

    try:
        data = json.loads(message)
        msg_type = data.get("type")

        if msg_type == "snippet":
            chunk_counter += 1

            # Extract metadata
            metadata = data.get("data", {}).get("metadata", {})
            video_data = data.get("data", {}).get("video_data", "")
            title = metadata.get("title", f"chunk_{chunk_counter}")

            print(f"\n✓ Received snippet chunk {chunk_counter}:")
            print(f"  - Title: {title}")
            print(f"  - Description: {metadata.get('description')}")
            print(f"  - Source URL: {metadata.get('src_video_url')}")
            print(f"  - Video data size: {len(video_data)} bytes (base64)")

            # Save video chunk
            try:
                filepath = save_video_chunk(video_data, chunk_counter, title)
                print(f"  - Saved to: {filepath}")
            except Exception as e:
                print(f"  - Error saving video: {e}")

        elif msg_type == "snippet_complete":
            metadata = data.get("metadata", {})
            print("\n✓ Processing complete!")
            print(f"  - Source URL: {metadata.get('src_video_url')}")
            print(f"  - Total chunks received: {chunk_counter}")

        elif msg_type == "error":
            error_msg = data.get("message", "Unknown error")
            print(f"\n✗ Error: {error_msg}")
            metadata = data.get("metadata", {})
            if metadata:
                print(f"  - Source URL: {metadata.get('src_video_url')}")

    except json.JSONDecodeError:
        print(f"Failed to parse message: {message}")
    except Exception as e:
        print(f"Error handling message: {e}")


def on_error(ws, error):
    """Handle WebSocket errors."""
    # Only print actual errors, not normal close operations
    error_str = str(error)
    if "fin=1 opcode=8" not in error_str:
        print(f"\n✗ WebSocket error: {error}")


def on_close(ws, close_status_code, close_msg):
    """Handle WebSocket close."""
    print("\n✓ WebSocket connection closed")
    if close_status_code and close_status_code not in (1000, 1001):
        print(f"  - Status: {close_status_code}, Message: {close_msg}")


def on_open(ws):
    """Handle WebSocket open."""
    print("✓ WebSocket connection established")
    print("Waiting for video chunks...\n")


def test_video_processing(video_url: str, is_live: bool = False):
    """
    Test the Flask API by sending a video URL and receiving chunks.

    Args:
        video_url: URL of the video to process
        is_live: Whether the video is a live stream
    """
    global chunk_counter
    chunk_counter = 0

    # Ensure output directory exists
    ensure_output_dir()

    # Construct WebSocket URL with query parameters
    ws_url = f"ws://localhost:5000/ws/video-snippets?video_url={video_url}&is_live={str(is_live).lower()}"

    print("=" * 70)
    print("Testing Flask WebSocket API")
    print("=" * 70)
    print(f"Video URL: {video_url}")
    print(f"Is Live: {is_live}")
    print(f"WebSocket URL: {ws_url}")
    print("=" * 70)

    # Create WebSocket connection
    ws = websocket.WebSocketApp(
        ws_url,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
        on_open=on_open,
    )

    # Run WebSocket client
    ws.run_forever()


if __name__ == "__main__":
    # Use a short test video by default (a public domain video)
    # You can replace this with any YouTube URL or other supported video URL

    if len(sys.argv) > 1:
        test_url = sys.argv[1]
    else:
        # Short test video (about 30 seconds, should give us 2 chunks)
        test_url = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        print(f"No URL provided, using default test video: {test_url}")

    # Check if is_live flag is provided
    is_live = len(sys.argv) > 2 and sys.argv[2].lower() in ("true", "1", "yes")

    try:
        test_video_processing(test_url, is_live)
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
