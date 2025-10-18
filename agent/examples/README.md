# Examples

This directory contains example scripts for testing and demonstrating the Flask API functionality.

## test_websocket_client.py

A WebSocket client for manually testing the Flask video processing API. This script:
- Connects to the Flask WebSocket endpoint
- Sends a video URL (live or non-live)
- Receives 15-second video chunks with metadata
- Saves MP4 files to `agent/video_output/`

### Usage

First, start the Flask server:
```bash
cd agent
python -m src.api
```

Then run the test client in another terminal:

```bash
# Test with default video
python agent/examples/test_websocket_client.py

# Test with a specific video URL
python agent/examples/test_websocket_client.py "https://www.youtube.com/watch?v=VIDEO_ID"

# Test with a live stream
python agent/examples/test_websocket_client.py "https://www.youtube.com/watch?v=LIVE_VIDEO_ID" true
```

### Output

Video chunks are saved to `agent/video_output/` with filenames like:
- `chunk_001_Chunk 1.mp4`
- `chunk_002_Chunk 2.mp4`
- etc.

Each chunk is approximately 15 seconds long and includes metadata:
- Title
- Description (timestamp range)
- Source video URL
