# Video Snippet API Specification

## Overview
Flask-based WebSocket API for streaming video snippets with metadata.

## WebSocket Endpoint

### `GET /ws/video-snippets`

Accepts a video URL and streams back processed video snippets as MP4 files with metadata.

#### Protocol
WebSocket (ws:// or wss://)

#### Request Parameters

Query parameters:
- `video_url` (string, required): URL of the source video to process
- `is_live` (boolean, required): Whether the video is a live stream

#### Response Messages

The server streams JSON messages. Six message types are defined:

##### Snippet Message (Highlight Detection)
```json
{
  "type": "snippet",
  "data": {
    "video_data": "<base64-encoded-mp4-data>",
    "metadata": {
      "src_video_url": "string",
      "title": "string",
      "description": "string"
    }
  }
}
```

**Fields:**
- `type`: Always `"snippet"`
- `data.video_data`: Base64-encoded MP4 video data
- `data.metadata.src_video_url`: Original source video URL
- `data.metadata.title`: Title/name of the snippet
- `data.metadata.description`: Description of the snippet content

##### Live Commentary Chunk Message
```json
{
  "type": "live_commentary_chunk",
  "data": {
    "video_data": "<base64-encoded-mp4-data>",
    "metadata": {
      "src_video_url": "string",
      "chunk_number": 1,
      "format": "fragmented_mp4",
      "audio_sample_rate": 24000,
      "commentary_length_bytes": 123456,
      "video_length_bytes": 234567,
      "base_chunks_combined": 2,
      "total_duration_seconds": 8,
      "narration_text": "string"
    }
  }
}
```

**Fields:**
- `type`: Always `"live_commentary_chunk"`
- `data.video_data`: Base64-encoded fragmented MP4 video data with AI-generated audio commentary
- `data.metadata.src_video_url`: Original source video URL
- `data.metadata.chunk_number`: Sequential chunk number for ordered playback (starts at 1)
- `data.metadata.format`: Video format (always "fragmented_mp4")
- `data.metadata.audio_sample_rate`: Sample rate of the generated audio commentary (24000 Hz)
- `data.metadata.commentary_length_bytes`: Size of the raw audio commentary in bytes
- `data.metadata.video_length_bytes`: Size of the final video with commentary in bytes
- `data.metadata.base_chunks_combined`: Number of 4-second base chunks combined into this chunk (always 2)
- `data.metadata.total_duration_seconds`: Total duration of the combined chunk in seconds (always 8)
- `data.metadata.narration_text`: The text narration that was converted to speech

##### Error Message
```json
{
  "type": "error",
  "message": "string",
  "metadata": {
    "src_video_url": "string"
  }
}
```

**Fields:**
- `type`: Always `"error"`
- `message`: Error description
- `metadata.src_video_url`: Original source video URL (if available)

##### Completion Message
```json
{
  "type": "snippet_complete",
  "metadata": {
    "src_video_url": "string"
  }
}
```

**Fields:**
- `type`: Always `"snippet_complete"`
- `metadata.src_video_url`: Original source video URL

#### Behavior

1. Client connects to WebSocket endpoint with `video_url` and `is_live` query parameters
2. Server processes the video through two concurrent pipelines:
   - **Highlight Detection Pipeline**: Identifies and extracts interesting segments
   - **Live Commentary Pipeline**: Generates AI audio commentary using selective frame streaming
3. Server sends messages as processing progresses:
   - Zero or more `snippet` messages as highlights are detected
   - Zero or more `live_commentary_chunk` messages with video segments + AI commentary (sent every ~4 seconds)
4. Server sends a `snippet_complete` message when highlight detection finishes successfully
5. Server sends an `error` message if processing fails
6. Connection may be closed by client or server after completion/error

**Live Commentary Streaming Strategy**:
- The pipeline sends frames from 2 video chunks to the Gemini Live API every 4 seconds
- Audio commentary is continuously generated and buffered
- Every 4 seconds, buffered audio is packaged with buffered video chunks
- Each package is sent as a `live_commentary_chunk` message with a sequential `chunk_number`
- This approach prevents API overload while providing intermittent audio commentary

**Client Buffering Recommendation**:
- Clients should buffer the first 3 chunks before starting playback
- This ensures smooth, continuous playback without stuttering
- Chunks should be played in sequential order based on their `chunk_number`

**Message Ordering**: Messages from different pipelines may arrive in any order. Clients should handle messages based on their `type` field and not assume any specific ordering between `snippet` and `live_commentary_chunk` messages.

#### Error Conditions

- Missing `video_url` parameter: Returns `error` message
- Missing `is_live` parameter: Returns `error` message
- Invalid video URL: Returns `error` message
- Video processing failure: Returns `error` message

## HTTP Endpoint

### `GET /health`

Health check endpoint.

#### Response
```json
{
  "status": "healthy"
}
```
