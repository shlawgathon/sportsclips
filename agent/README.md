# Agent

Clean and simple Flask + WebSocket service for streaming video snippets.

## Quickstart (uv)

Use uv to install deps and run the app from the `agent` directory.

1) Install uv (if needed): https://docs.astral.sh/uv/

2) From this folder:

```
cd agent
uv sync
```

3) Run the Flask app with uv:

- Using Flask CLI (recommended):

```
uv run flask --app src.api run --host 0.0.0.0 --port 5000 --debug
```

- Or run the module directly:

```
uv run python -m src.api
```

The app starts on http://127.0.0.1:5000.

## Verify

Health check:

```
curl http://127.0.0.1:5000/health
```

Expected response: `{ "status": "healthy" }`

## WebSocket Endpoint

- URL: `ws://127.0.0.1:5000/ws/video-snippets?video_url=<url>&is_live=<true|false>`
- Message formats and details: see `agent/docs/api-spec.md`.

## Environment Variables (optional)

If you plan to use Gemini features in `src/llm.py`, set your API key:

```
cp .env.example .env
# edit .env and set GEMINI_API_KEY
```

## Notes

- Python 3.12 is required (enforced via `pyproject.toml`). uv will handle it.
- The Flask application instance is defined in `agent/src/api.py:23` (`app`).
