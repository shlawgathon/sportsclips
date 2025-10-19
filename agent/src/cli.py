#!/usr/bin/env python3
"""
Command-line interface for video highlight detection pipeline.

This CLI allows you to process YouTube videos through the highlight detection
pipeline and save the filtered highlight clips to disk.
"""

import argparse
import logging
import sys
from pathlib import Path

from dotenv import load_dotenv

from .pipeline import create_highlight_pipeline

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


class MockWebSocket:
    """Mock WebSocket for CLI usage that saves videos to disk."""

    def __init__(self, output_dir: Path):
        """
        Initialize the mock WebSocket.

        Args:
            output_dir: Directory to save output video files
        """
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.saved_count = 0
        logger.info(f"Output directory: {self.output_dir.absolute()}")

    def send(self, message: str) -> None:
        """
        Handle 'send' calls from the pipeline.

        Args:
            message: JSON message from pipeline
        """
        import json

        try:
            msg = json.loads(message)

            if msg["type"] == "snippet":
                # Save the highlight to disk
                import base64

                video_data = base64.b64decode(msg["data"]["video_data"])
                title = msg["data"]["metadata"]["title"]

                output_filename = f"highlight_{self.saved_count:04d}.mp4"
                output_path = self.output_dir / output_filename

                with open(output_path, "wb") as f:
                    f.write(video_data)

                logger.info(
                    f"✓ Saved highlight {self.saved_count + 1}: {output_filename} "
                    f'({len(video_data)} bytes) - "{title}"'
                )

                self.saved_count += 1

            elif msg["type"] == "snippet_complete":
                logger.info(
                    f"\n{'=' * 60}\n"
                    f"Pipeline processing complete!\n"
                    f"Highlights saved: {self.saved_count}\n"
                    f"Output directory: {self.output_dir.absolute()}\n"
                    f"{'=' * 60}"
                )

            elif msg["type"] == "error":
                logger.error(f"Pipeline error: {msg['message']}")

        except Exception as e:
            logger.error(f"Error processing message: {e}", exc_info=True)


def main() -> None:
    """Main CLI entrypoint."""
    parser = argparse.ArgumentParser(
        description="Process videos through the highlight detection pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process a YouTube video with highlight detection
  python -m src.cli https://www.youtube.com/watch?v=VIDEO_ID

  # Process a live stream
  python -m src.cli --live https://www.youtube.com/watch?v=VIDEO_ID

  # Use custom window settings
  python -m src.cli --base-chunk 3 --window-size 5 VIDEO_URL

  # Specify custom output directory
  python -m src.cli --output-dir ./my_highlights VIDEO_URL
        """,
    )

    parser.add_argument(
        "video_url",
        help="URL of the video to process (YouTube or other supported platform)",
    )

    parser.add_argument(
        "--live",
        action="store_true",
        help="Process as a live stream",
    )

    parser.add_argument(
        "--base-chunk",
        type=int,
        default=2,
        help="Duration of each base chunk in seconds (default: 2)",
    )

    parser.add_argument(
        "--window-size",
        type=int,
        default=7,
        help="Number of chunks in sliding window (default: 7)",
    )

    parser.add_argument(
        "--slide-step",
        type=int,
        default=2,
        help="Number of chunks to slide when no highlight (default: 2)",
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default="video_output",
        help="Directory to save output video files (default: video_output)",
    )

    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose logging",
    )

    args = parser.parse_args()

    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Create pipeline
    logger.info(
        f"Creating sliding window pipeline "
        f"(base_chunk={args.base_chunk}s, window={args.window_size} chunks, "
        f"slide={args.slide_step} chunks)"
    )
    pipeline = create_highlight_pipeline(
        base_chunk_duration=args.base_chunk,
        window_size=args.window_size,
        slide_step=args.slide_step,
    )

    # Create mock WebSocket and process video
    mock_ws = MockWebSocket(output_dir=Path(args.output_dir))

    from .api import (
        create_complete_message,
        create_error_message,
        create_snippet_message,
    )

    try:
        pipeline.process_video_url(
            video_url=args.video_url,
            ws=mock_ws,
            is_live=args.live,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        )
    except KeyboardInterrupt:
        logger.info("\n\nProcessing interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Pipeline error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
