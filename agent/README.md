# Sports Clips Agent

AI-powered video highlight detection and filtering pipeline for sports content.


### Setting up project

```bash
uv sync
```

```bash
cp .env.example .env
```

### Starting the server (ASGI)
```bash
uv run uvicorn src.api:app --host 0.0.0.0 --port 8000 --reload
```

### CLI Usage
```bash
# Basic usage
uv run python -m src.cli "VIDEO_URL"

# Custom chunk duration
uv run python -m src.cli --chunk-duration 5 "VIDEO_URL"

# Process live stream
uv run python -m src.cli --live "STREAM_URL"

# Save all chunks without filtering
uv run python -m src.cli --no-filter "VIDEO_URL"

# Custom output directory
uv run python -m src.cli --output-dir ./highlights "VIDEO_URL"
```
