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
from typing import Any

from .pipeline import VideoPipeline, create_highlight_pipeline
from .stream import stream_and_chunk_video

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


class CLIPipelineRunner:
    """Runs the video pipeline and saves output files to disk."""

    def __init__(self, output_dir: str = "video_output"):
        """
        Initialize the CLI pipeline runner.

        Args:
            output_dir: Directory to save output video files
        """
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"Output directory: {self.output_dir.absolute()}")

    def process_video_url(
        self,
        video_url: str,
        pipeline: VideoPipeline,
        is_live: bool = False,
    ) -> None:
        """
        Process a video URL through the pipeline and save results.

        Args:
            video_url: URL of video to process
            pipeline: VideoPipeline instance to use
            is_live: Whether the video is a live stream
        """
        try:
            stream_type = "live stream" if is_live else "video"
            logger.info(f"Starting pipeline for {stream_type}: {video_url}")
            logger.info(
                f"Processing {stream_type} into {pipeline.chunk_duration}-second chunks"
            )

            chunk_index = 0
            saved_count = 0

            for chunk_data in stream_and_chunk_video(
                url=video_url,
                chunk_duration=pipeline.chunk_duration,
                format_selector=pipeline.format_selector,
                additional_options=["--no-part"],
                is_live=is_live,
            ):
                logger.info(f"Processing chunk {chunk_index + 1}")

                # Create metadata
                metadata: dict[str, Any] = {
                    "src_video_url": video_url,
                    "chunk_index": chunk_index,
                    "duration_seconds": pipeline.chunk_duration,
                }

                # Apply modulation functions (filtering)
                chunk_data, metadata = pipeline._apply_modulations(chunk_data, metadata)

                # Skip if chunk was filtered out (empty data)
                if len(chunk_data) == 0:
                    logger.info(f"Chunk {chunk_index + 1} was filtered out, skipping")
                    chunk_index += 1
                    continue

                # Save the chunk to disk
                output_filename = (
                    f"highlight_{saved_count:04d}_chunk{chunk_index:04d}.mp4"
                )
                output_path = self.output_dir / output_filename

                with open(output_path, "wb") as f:
                    f.write(chunk_data)

                logger.info(
                    f"✓ Saved highlight {saved_count + 1}: {output_filename} "
                    f"({len(chunk_data)} bytes)"
                )

                saved_count += 1
                chunk_index += 1

            logger.info(
                f"\n{'=' * 60}\n"
                f"Pipeline processing complete!\n"
                f"Total chunks processed: {chunk_index}\n"
                f"Highlights saved: {saved_count}\n"
                f"Output directory: {self.output_dir.absolute()}\n"
                f"{'=' * 60}"
            )

        except KeyboardInterrupt:
            logger.info("\n\nProcessing interrupted by user")
            sys.exit(0)
        except Exception as e:
            logger.error(f"Pipeline error: {e}", exc_info=True)
            sys.exit(1)


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

  # Use custom chunk duration (default: 3 seconds for highlights)
  python -m src.cli --chunk-duration 5 VIDEO_URL

  # Specify custom output directory
  python -m src.cli --output-dir ./my_highlights VIDEO_URL

  # Disable highlight filtering (save all chunks)
  python -m src.cli --no-filter VIDEO_URL
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
        "--chunk-duration",
        type=int,
        default=3,
        help="Duration of each video chunk in seconds (default: 3)",
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default="video_output",
        help="Directory to save output video files (default: video_output)",
    )

    parser.add_argument(
        "--no-filter",
        action="store_true",
        help="Disable highlight filtering (save all chunks)",
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
    if args.no_filter:
        logger.info("Creating pipeline WITHOUT highlight filtering")
        from .pipeline import VideoPipeline

        pipeline = VideoPipeline(chunk_duration=args.chunk_duration)
    else:
        logger.info("Creating pipeline WITH highlight filtering")
        pipeline = create_highlight_pipeline(chunk_duration=args.chunk_duration)

    # Create runner and process video
    runner = CLIPipelineRunner(output_dir=args.output_dir)
    runner.process_video_url(
        video_url=args.video_url,
        pipeline=pipeline,
        is_live=args.live,
    )


if __name__ == "__main__":
    main()
