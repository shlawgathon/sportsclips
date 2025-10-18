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

#### Response Messages

The server streams JSON messages. Three message types are defined:

##### Snippet Message
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

1. Client connects to WebSocket endpoint with `video_url` query parameter
2. Server processes the video and identifies interesting segments
3. Server sends zero or more `snippet` messages as segments are processed
4. Server sends one `snippet_complete` message when processing finishes successfully
5. Server sends one `error` message if processing fails
6. Connection may be closed by client or server after completion/error

#### Error Conditions

- Missing `video_url` parameter: Returns `error` message
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
