#!/usr/bin/env python3
"""
Command-line interface for video highlight detection pipeline.

This CLI allows you to process YouTube videos through the highlight detection
pipeline and save the filtered highlight clips to disk. It also supports
live audio commentary generation with real-time playback.
"""

import argparse
import asyncio
import logging
import subprocess
import sys
from datetime import datetime
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


class UnifiedWebSocketHandler:
    """
    Unified WebSocket handler for CLI that routes messages by type.

    Handles both highlight detection and live commentary messages,
    saving outputs to appropriate subdirectories and optionally
    playing audio commentary in real-time.
    """

    def __init__(self, output_dir: Path, enable_audio_playback: bool = True):
        """
        Initialize the unified WebSocket handler.

        Args:
            output_dir: Base output directory
            enable_audio_playback: Whether to play live commentary audio in real-time (default: True)
        """
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.enable_audio_playback = enable_audio_playback

        # Counters for different message types
        self.highlight_count = 0
        self.commentary_count = 0

        # Audio playback setup
        self.ffplay_process: subprocess.Popen[bytes] | None = None
        self.temp_fifo: Path | None = None

        # Ordered chunk playback tracking
        self.next_expected_chunk = 1  # Start expecting chunk 1
        self.chunk_buffer: dict[int, Path] = {}  # Buffer for out-of-order chunks
        self.buffering_initial_chunks = (
            True  # Wait for initial buffer before starting playback
        )
        self.initial_buffer_size = (
            3  # Number of chunks to buffer before starting playback
        )
        self.playback_started = False  # Track if we've started playing chunks

        logger.info(f"Output directory: {self.output_dir.absolute()}")

        # Set up ffplay for real-time audio playback if enabled
        if self.enable_audio_playback:
            self._setup_audio_player()

    def _setup_audio_player(self) -> None:
        """Set up temporary directory for audio playback."""
        try:
            # Create temp directory for audio files
            import tempfile

            temp_dir = tempfile.mkdtemp(prefix="live_audio_")
            self.temp_fifo = Path(temp_dir)

            logger.info("✓ Audio playback enabled (will play after processing)")

        except Exception as e:
            logger.warning(f"Failed to initialize audio playback: {e}")
            self.enable_audio_playback = False
            self.temp_fifo = None

    def send(self, message: str) -> None:
        """
        Handle messages from pipelines, routing by message type.

        Args:
            message: JSON message string
        """
        import json

        try:
            msg = json.loads(message)
            msg_type = msg.get("type")

            if msg_type == "snippet":
                self._handle_highlight(msg)
            elif msg_type == "live_commentary":
                self._handle_live_commentary(msg)
            elif msg_type == "live_commentary_chunk":
                self._handle_live_commentary_chunk(msg)
            elif msg_type == "snippet_complete":
                self._handle_completion(msg)
            elif msg_type == "error":
                self._handle_error(msg)
            else:
                logger.warning(f"Unknown message type: {msg_type}")

        except Exception as e:
            logger.error(f"Error processing message: {e}", exc_info=True)

    def _handle_highlight(self, msg: dict) -> None:
        """Handle highlight detection message."""
        import base64

        video_data = base64.b64decode(msg["data"]["video_data"])
        metadata = msg["data"]["metadata"]
        title = metadata["title"]
        description = metadata["description"]

        # Create highlights subdirectory
        highlights_dir = self.output_dir / "highlights"
        highlights_dir.mkdir(parents=True, exist_ok=True)

        # Save video file
        video_filename = f"highlight_{self.highlight_count:04d}.mp4"
        video_path = highlights_dir / video_filename
        with open(video_path, "wb") as f:
            f.write(video_data)

        # Save metadata file
        metadata_filename = f"highlight_{self.highlight_count:04d}.json"
        metadata_path = highlights_dir / metadata_filename
        with open(metadata_path, "w") as f:
            import json

            json.dump(
                {
                    "title": title,
                    "description": description,
                    "src_video_url": metadata.get("src_video_url", ""),
                    "video_file": video_filename,
                },
                f,
                indent=2,
            )

        logger.info(
            f"✓ Saved highlight {self.highlight_count + 1}:\n"
            f"  Video: highlights/{video_filename} ({len(video_data):,} bytes)\n"
            f'  Title: "{title}"\n'
            f'  Description: "{description}"\n'
            f"  Metadata: highlights/{metadata_filename}"
        )

        self.highlight_count += 1

    def _handle_live_commentary(self, msg: dict) -> None:
        """Handle live commentary message."""
        import base64

        video_data = base64.b64decode(msg["data"]["video_data"])
        metadata = msg["data"]["metadata"]

        # Create live_commentary subdirectory
        commentary_dir = self.output_dir / "live_commentary"
        commentary_dir.mkdir(parents=True, exist_ok=True)

        # Save video file
        video_filename = f"commentary_{self.commentary_count:04d}.mp4"
        video_path = commentary_dir / video_filename
        with open(video_path, "wb") as f:
            f.write(video_data)

        # Save metadata file
        metadata_filename = f"commentary_{self.commentary_count:04d}.json"
        metadata_path = commentary_dir / metadata_filename
        with open(metadata_path, "w") as f:
            import json

            json.dump(metadata, f, indent=2)

        logger.info(
            f"✓ Saved live commentary {self.commentary_count + 1}:\n"
            f"  Video: live_commentary/{video_filename} ({len(video_data):,} bytes)\n"
            f"  Audio sample rate: {metadata['audio_sample_rate']} Hz\n"
            f"  Commentary size: {metadata['commentary_length_bytes']:,} bytes\n"
            f"  Chunks processed: {metadata['num_chunks_processed']}\n"
            f"  Metadata: live_commentary/{metadata_filename}"
        )

        # Play audio if enabled
        if self.enable_audio_playback and self.temp_fifo:
            try:
                # Save to temp file and play with ffplay
                temp_audio_file = (
                    self.temp_fifo / f"temp_commentary_{self.commentary_count}.mp4"
                )
                with open(temp_audio_file, "wb") as f:
                    f.write(video_data)

                logger.info("  ♪ Playing audio commentary...")
                # Play audio in background (non-blocking)
                subprocess.Popen(
                    ["ffplay", "-nodisp", "-autoexit", str(temp_audio_file)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception as e:
                logger.warning(f"Could not play audio: {e}")

        self.commentary_count += 1

    def _handle_live_commentary_chunk(self, msg: dict) -> None:
        """
        Handle live commentary chunk message (real-time streaming with buffered playback).

        This method implements a buffering strategy for smooth playback:
        1. Buffer the first 3 chunks before starting playback
        2. Once buffer is filled, start playing chunks in sequential order
        3. Continue buffering and playing subsequent chunks to maintain smooth playback
        """
        import base64

        video_data = base64.b64decode(msg["data"]["video_data"])
        metadata = msg["data"]["metadata"]
        chunk_number = metadata["chunk_number"]

        # Create live_commentary subdirectory
        commentary_dir = self.output_dir / "live_commentary"
        commentary_dir.mkdir(parents=True, exist_ok=True)

        # Save video file for this chunk
        video_filename = f"chunk_{chunk_number:04d}.mp4"
        video_path = commentary_dir / video_filename
        with open(video_path, "wb") as f:
            f.write(video_data)

        logger.info(
            f"✓ Received live commentary chunk {chunk_number}:\n"
            f"  Video: live_commentary/{video_filename} ({len(video_data):,} bytes)\n"
            f"  Commentary: {metadata['commentary_length_bytes']:,} bytes"
        )

        # Always buffer the chunk first
        self.chunk_buffer[chunk_number] = video_path

        # Check if we've filled the initial buffer
        if self.buffering_initial_chunks:
            if len(self.chunk_buffer) >= self.initial_buffer_size:
                logger.info(
                    f"  ▶  Initial buffer filled ({len(self.chunk_buffer)} chunks), starting playback..."
                )
                self.buffering_initial_chunks = False
                self.playback_started = True
            else:
                logger.info(
                    f"  ⏸  Buffering chunk {chunk_number} ({len(self.chunk_buffer)}/{self.initial_buffer_size} chunks buffered)"
                )
                return

        # Playback mode: play chunks in order
        if self.playback_started:
            # Play all sequential chunks starting from next_expected_chunk
            while self.next_expected_chunk in self.chunk_buffer:
                buffered_path = self.chunk_buffer.pop(self.next_expected_chunk)
                self._play_chunk(self.next_expected_chunk, buffered_path)
                self.next_expected_chunk += 1

    def _play_chunk(self, chunk_number: int, video_path: Path) -> None:
        """Play a single chunk in order."""
        if self.enable_audio_playback and self.temp_fifo:
            try:
                logger.info(f"  ♪ Playing chunk {chunk_number} audio...")
                # Play audio in background (non-blocking)
                subprocess.Popen(
                    ["ffplay", "-nodisp", "-autoexit", str(video_path)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception as e:
                logger.warning(f"Could not play audio: {e}")

    def _handle_completion(self, msg: dict) -> None:
        """Handle completion message."""
        logger.info(
            f"\n{'=' * 60}\n"
            f"Highlight detection complete!\n"
            f"Highlights saved: {self.highlight_count}\n"
            f"{'=' * 60}"
        )

    def _handle_error(self, msg: dict) -> None:
        """Handle error message."""
        logger.error(f"Pipeline error: {msg.get('message', 'Unknown error')}")

    def close(self) -> None:
        """Clean up resources and print summary."""
        # Clean up temp directory
        if self.temp_fifo and self.temp_fifo.exists():
            try:
                import shutil

                shutil.rmtree(self.temp_fifo)
            except Exception:
                pass

        logger.info(
            f"\n{'=' * 60}\n"
            f"Processing complete!\n"
            f"Highlights saved: {self.highlight_count}\n"
            f"Live commentary clips: {self.commentary_count}\n"
            f"Output directory: {self.output_dir.absolute()}\n"
            f"{'=' * 60}"
        )


async def run_dual_mode(
    video_url: str,
    is_live: bool,
    base_chunk: int,
    window_size: int,
    slide_step: int,
    output_dir: Path,
    debug_dir: Path | None,
    enable_live_commentary: bool,
    enable_audio_playback: bool,
    commentary_prompt: str,
) -> None:
    """
    Run both highlight detection and live commentary pipelines concurrently.

    Both pipelines share the same video stream to avoid downloading twice.

    Args:
        video_url: URL of video to process
        is_live: Whether the video is a live stream
        base_chunk: Duration of each base chunk in seconds
        window_size: Number of chunks in sliding window
        slide_step: Number of chunks to slide when no highlight
        output_dir: Base output directory
        debug_dir: Directory to save intermediate debug videos
        enable_live_commentary: Whether to enable live commentary generation
        enable_audio_playback: Whether to play audio in real-time
        commentary_prompt: Prompt for live commentary generation
    """
    # Create single unified handler for all message types
    unified_handler = UnifiedWebSocketHandler(
        output_dir=output_dir,
        enable_audio_playback=enable_audio_playback,
    )

    from .api import (
        create_complete_message,
        create_error_message,
        create_snippet_message,
    )

    tasks = []

    logger.info(
        f"\n{'=' * 60}\n"
        f"Processing video: {video_url}\n"
        f"Mode: {'Live stream' if is_live else 'Video'}\n"
        f"Active pipelines: {2 if enable_live_commentary else 1}\n"
        f"  - Highlight detection → {output_dir / 'highlights'}\n"
        + (
            f"  - Live commentary (real-time) → {output_dir / 'live_commentary'}\n"
            if enable_live_commentary
            else ""
        )
        + "Note: Video will be downloaded once for highlights, streaming processed for live commentary\n"
        + f"{'=' * 60}\n"
    )

    try:
        # Task 1: Highlight detection pipeline
        logger.info("Starting highlight detection pipeline...")
        highlight_pipeline = create_highlight_pipeline(
            base_chunk_duration=base_chunk,
            window_size=window_size,
            slide_step=slide_step,
            debug_dir=debug_dir,
        )

        highlight_task = asyncio.create_task(
            highlight_pipeline.process_video_url(
                video_url=video_url,
                ws=unified_handler,
                is_live=is_live,
                create_snippet_message=create_snippet_message,
                create_complete_message=create_complete_message,
                create_error_message=create_error_message,
                enable_live_commentary=enable_live_commentary,
            ),
            name="highlight_detection",
        )
        tasks.append(highlight_task)

        # Wait for all tasks to complete
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Check for errors
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                task_name = tasks[i].get_name()
                logger.error(f"Task '{task_name}' failed: {result}", exc_info=result)

    finally:
        # Clean up handler
        unified_handler.close()


def main() -> None:
    """Main CLI entrypoint."""
    parser = argparse.ArgumentParser(
        description="Process videos through the highlight detection pipeline with optional live commentary",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process a YouTube video with highlight detection only
  python -m src.cli https://www.youtube.com/watch?v=VIDEO_ID

  # Process with both highlight detection AND live commentary
  python -m src.cli --enable-live-commentary https://www.youtube.com/watch?v=VIDEO_ID

  # Process a live stream with both pipelines
  python -m src.cli --live --enable-live-commentary https://www.youtube.com/watch?v=VIDEO_ID

  # Disable real-time audio playback (only save files)
  python -m src.cli --enable-live-commentary --no-audio-playback VIDEO_URL

  # Use custom window settings
  python -m src.cli --base-chunk 3 --window-size 5 VIDEO_URL

  # Custom commentary prompt
  python -m src.cli --enable-live-commentary --commentary-prompt "Provide detailed analysis..." VIDEO_URL
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
        "--enable-live-commentary",
        action="store_true",
        help="Enable live commentary generation with Gemini Live API (runs concurrently with highlight detection)",
    )

    parser.add_argument(
        "--no-audio-playback",
        action="store_true",
        help="Disable real-time audio playback (only save files)",
    )

    parser.add_argument(
        "--commentary-prompt",
        type=str,
        default="Provide minimal sports commentary (3-12 words) describing the key action you see. Be natural and energetic!",
        help="Custom prompt for live commentary generation",
    )

    parser.add_argument(
        "--base-chunk",
        type=int,
        default=4,
        help="Duration of each base chunk in seconds (default: 4)",
    )

    parser.add_argument(
        "--window-size",
        type=int,
        default=9,
        help="Number of chunks in sliding window (default: 9)",
    )

    parser.add_argument(
        "--slide-step",
        type=int,
        default=3,
        help="Number of chunks to slide when no highlight (default: 3)",
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

    parser.add_argument(
        "--debug-videos",
        action="store_true",
        help="Save intermediate videos at each processing step for debugging",
    )

    args = parser.parse_args()

    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Create timestamped output directory
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(args.output_dir) / timestamp

    # Set debug directory if debug mode is enabled
    debug_dir = None
    if args.debug_videos:
        debug_dir = output_dir / "debug_vids"
        debug_dir.mkdir(parents=True, exist_ok=True)
        logger.info(
            f"Debug mode enabled - saving intermediate videos to: {debug_dir.absolute()}"
        )

    # Create pipeline config info
    logger.info(
        f"Pipeline configuration: "
        f"base_chunk={args.base_chunk}s, window={args.window_size} chunks, "
        f"slide={args.slide_step} chunks"
    )

    try:
        asyncio.run(
            run_dual_mode(
                video_url=args.video_url,
                is_live=args.live,
                base_chunk=args.base_chunk,
                window_size=args.window_size,
                slide_step=args.slide_step,
                output_dir=output_dir,
                debug_dir=debug_dir,
                enable_live_commentary=args.enable_live_commentary,
                enable_audio_playback=not args.no_audio_playback,
                commentary_prompt=args.commentary_prompt,
            )
        )
    except KeyboardInterrupt:
        logger.info("\n\nProcessing interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Pipeline error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
