"""
Video processing pipeline for streaming and chunking videos with sliding window approach.

This module provides functionality to download video streams, split them into
fixed-duration chunks, and process them with a sliding window for highlight detection.
"""

import logging
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any, Callable

from .stream import stream_and_chunk_video

logger = logging.getLogger(__name__)


class SlidingWindowPipeline:
    """
    Pipeline for processing video with sliding window approach.

    This pipeline:
    1. Splits video into 2-second base chunks
    2. Creates 7-chunk sliding windows (14 seconds total)
    3. Processes each window through multiple steps
    4. Slides by 2 chunks if no highlight found, or by 7 chunks if highlight submitted
    """

    def __init__(
        self,
        base_chunk_duration: int = 2,
        window_size: int = 7,
        slide_step: int = 2,
        format_selector: str = "best[ext=mp4]/best",
    ):
        """
        Initialize the sliding window pipeline.

        Args:
            base_chunk_duration: Duration of each base chunk in seconds (default: 2)
            window_size: Number of chunks in each window (default: 7, which is 14 seconds)
            slide_step: Number of chunks to slide when no highlight found (default: 2)
            format_selector: yt-dlp format selector for video quality
        """
        self.base_chunk_duration = base_chunk_duration
        self.window_size = window_size
        self.slide_step = slide_step
        self.format_selector = format_selector

        # Three processing steps
        self.detect_step: (
            Callable[[list[bytes], dict[str, Any]], tuple[bool, dict[str, Any]]] | None
        ) = None
        self.trim_step: (
            Callable[[list[bytes], dict[str, Any]], tuple[bytes, dict[str, Any]]] | None
        ) = None
        self.caption_step: (
            Callable[[bytes, dict[str, Any]], tuple[str, str, dict[str, Any]]] | None
        ) = None

    def set_detect_step(
        self, func: Callable[[list[bytes], dict[str, Any]], tuple[bool, dict[str, Any]]]
    ) -> None:
        """
        Set the detection step function.

        Args:
            func: Function that takes (window_chunks, metadata) and returns (is_highlight, metadata)
        """
        self.detect_step = func

    def set_trim_step(
        self,
        func: Callable[[list[bytes], dict[str, Any]], tuple[bytes, dict[str, Any]]],
    ) -> None:
        """
        Set the trim step function.

        Args:
            func: Function that takes (window_chunks, metadata) and returns (trimmed_video, metadata)
        """
        self.trim_step = func

    def set_caption_step(
        self, func: Callable[[bytes, dict[str, Any]], tuple[str, str, dict[str, Any]]]
    ) -> None:
        """
        Set the caption step function.

        Args:
            func: Function that takes (video_data, metadata) and returns (title, description, metadata)
        """
        self.caption_step = func

    def _concatenate_chunks(self, chunks: list[bytes]) -> bytes:
        """
        Concatenate multiple video chunks into a single video file.

        Args:
            chunks: List of video chunk bytes

        Returns:
            Concatenated video data
        """
        if not chunks:
            return b""

        if len(chunks) == 1:
            return chunks[0]

        # Create temp directory for concatenation
        unique_id = uuid.uuid4().hex[:8]
        temp_dir = tempfile.mkdtemp(prefix=f"concat_{unique_id}_")

        try:
            temp_path = Path(temp_dir)

            # Write each chunk to a temp file
            chunk_files = []
            for i, chunk in enumerate(chunks):
                chunk_file = temp_path / f"chunk_{i:03d}.mp4"
                with open(chunk_file, "wb") as f:
                    f.write(chunk)
                chunk_files.append(chunk_file)

            # Create concat list file
            concat_list = temp_path / "concat_list.txt"
            with open(concat_list, "w") as f:
                for chunk_file in chunk_files:
                    f.write(f"file '{chunk_file.name}'\n")

            # Concatenate using ffmpeg
            output_file = temp_path / "output.mp4"
            cmd = [
                "ffmpeg",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(concat_list),
                "-c",
                "copy",
                str(output_file),
            ]

            subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
                cwd=str(temp_path),
            )

            # Read the concatenated result
            with open(output_file, "rb") as f:
                return f.read()

        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to concatenate chunks: {e.stderr}")
            # Fallback: just return the first chunk
            return chunks[0] if chunks else b""
        finally:
            # Cleanup
            try:
                import shutil

                shutil.rmtree(temp_dir)
            except Exception:
                pass

    def process_video_url(
        self,
        video_url: str,
        ws: Any,
        is_live: bool,
        create_snippet_message: Callable[[bytes, str, str, str], str],
        create_complete_message: Callable[[str], str],
        create_error_message: Callable[[str, str | None], str],
    ) -> None:
        """
        Process a video URL with sliding window approach.

        Args:
            video_url: URL of video to process
            ws: WebSocket connection object
            is_live: Whether the video is a live stream
            create_snippet_message: Function to create snippet message JSON
            create_complete_message: Function to create completion message JSON
            create_error_message: Function to create error message JSON
        """
        try:
            stream_type = "live stream" if is_live else "video"
            logger.info(
                f"Starting sliding window pipeline for {stream_type}: {video_url}"
            )
            logger.info(
                f"Window size: {self.window_size} chunks ({self.window_size * self.base_chunk_duration}s), "
                f"Slide step: {self.slide_step} chunks"
            )

            # Collect all base chunks first
            all_chunks: list[bytes] = []
            for chunk_data in stream_and_chunk_video(
                url=video_url,
                chunk_duration=self.base_chunk_duration,
                format_selector=self.format_selector,
                additional_options=["--no-part"],
                is_live=is_live,
            ):
                all_chunks.append(chunk_data)
                logger.info(f"Collected base chunk {len(all_chunks)}")

            logger.info(f"Total base chunks collected: {len(all_chunks)}")

            # Process with sliding window
            window_start = 0
            highlight_count = 0

            while window_start + self.window_size <= len(all_chunks):
                window_end = window_start + self.window_size
                window_chunks = all_chunks[window_start:window_end]

                logger.info(
                    f"Processing window: chunks {window_start}-{window_end - 1} "
                    f"(time: {window_start * self.base_chunk_duration}s-"
                    f"{window_end * self.base_chunk_duration}s)"
                )

                # Create metadata for this window
                metadata: dict[str, Any] = {
                    "src_video_url": video_url,
                    "window_start_chunk": window_start,
                    "window_end_chunk": window_end - 1,
                    "window_start_time": window_start * self.base_chunk_duration,
                    "window_end_time": window_end * self.base_chunk_duration,
                    "base_chunk_duration": self.base_chunk_duration,
                }

                # Step 1: Detect if this window contains a highlight
                is_highlight = False
                if self.detect_step:
                    is_highlight, metadata = self.detect_step(window_chunks, metadata)
                    logger.info(
                        f"Detection result: {'HIGHLIGHT' if is_highlight else 'NO HIGHLIGHT'}"
                    )
                else:
                    logger.warning("No detect_step configured, skipping detection")

                if is_highlight:
                    # Step 2: Trim to actual highlight portions
                    trimmed_video = b""
                    if self.trim_step:
                        trimmed_video, metadata = self.trim_step(
                            window_chunks, metadata
                        )
                        logger.info(f"Trimmed video size: {len(trimmed_video)} bytes")
                    else:
                        # Default: concatenate all chunks in window
                        logger.warning(
                            "No trim_step configured, concatenating all chunks"
                        )
                        trimmed_video = self._concatenate_chunks(window_chunks)

                    # Step 3: Generate caption and description
                    title = f"Highlight {highlight_count + 1}"
                    description = (
                        f"Highlight from {metadata['window_start_time']}s-"
                        f"{metadata['window_end_time']}s"
                    )

                    if self.caption_step:
                        title, description, metadata = self.caption_step(
                            trimmed_video, metadata
                        )
                        logger.info(f"Generated caption: {title}")
                    else:
                        logger.warning(
                            "No caption_step configured, using default caption"
                        )

                    # Send the highlight
                    snippet_msg = create_snippet_message(
                        trimmed_video,
                        video_url,
                        title,
                        description,
                    )
                    ws.send(snippet_msg)

                    highlight_count += 1
                    logger.info(f"Sent highlight {highlight_count} to client")

                    # Slide by entire window to avoid duplicate highlights
                    window_start += self.window_size
                    logger.info(
                        f"Sliding by {self.window_size} chunks (highlight found)"
                    )
                else:
                    # No highlight, slide by step size
                    window_start += self.slide_step
                    logger.info(f"Sliding by {self.slide_step} chunks (no highlight)")

            # Send completion message
            ws.send(create_complete_message(video_url))
            logger.info(
                f"Pipeline processing complete. Total highlights: {highlight_count}"
            )

        except Exception as e:
            logger.error(f"Pipeline error: {e}", exc_info=True)
            ws.send(create_error_message(str(e), video_url))


def create_highlight_pipeline(
    base_chunk_duration: int = 2,
    window_size: int = 7,
    slide_step: int = 2,
) -> SlidingWindowPipeline:
    """
    Create a sliding window pipeline configured for highlight detection.

    This pipeline:
    - Processes videos in 2-second base chunks (configurable)
    - Uses 7-chunk sliding windows (14 seconds total)
    - Applies 3-step processing: detect, trim, caption
    - Slides by 2 chunks when no highlight, or by full window when highlight found

    Args:
        base_chunk_duration: Duration of each base chunk in seconds (default: 2)
        window_size: Number of chunks per window (default: 7)
        slide_step: Chunks to slide when no highlight (default: 2)

    Returns:
        Configured SlidingWindowPipeline instance
    """
    from .steps import (
        caption_highlight_step,
        detect_highlight_step,
        trim_highlight_step,
    )

    pipeline = SlidingWindowPipeline(
        base_chunk_duration=base_chunk_duration,
        window_size=window_size,
        slide_step=slide_step,
    )

    # Set up the three processing steps
    pipeline.set_detect_step(detect_highlight_step)
    pipeline.set_trim_step(trim_highlight_step)
    pipeline.set_caption_step(caption_highlight_step)

    return pipeline
