"""
Video processing pipeline for streaming and chunking videos with sliding window approach.

This module provides functionality to download video streams, split them into
fixed-duration chunks, and process them with a sliding window for highlight detection.
"""

import asyncio
import inspect
import logging
import subprocess
import tempfile
import uuid
from collections import deque
from pathlib import Path
from typing import Any, Callable

from .stream import stream_and_chunk_video
from .live import process_chunks_with_live_api

logger = logging.getLogger(__name__)


class SlidingWindowPipeline:
    """
    Pipeline for processing video with sliding window approach.

    This pipeline:
    1. Splits video into 4-second base chunks
    2. Creates 9-chunk sliding windows (36 seconds total)
    3. Processes each window through multiple steps
    4. Slides by 3 chunks if no highlight found, or by 9 chunks if highlight submitted
    """

    def __init__(
        self,
        base_chunk_duration: int = 4,
        window_size: int = 9,
        slide_step: int = 3,
        format_selector: str = "best[ext=mp4]/best",
        debug_dir: Path | None = None,
    ):
        """
        Initialize the sliding window pipeline.

        Args:
            base_chunk_duration: Duration of each base chunk in seconds (default: 4)
            window_size: Number of chunks in each window (default: 9, which is 36 seconds)
            slide_step: Number of chunks to slide when no highlight found (default: 3)
            format_selector: yt-dlp format selector for video quality
            debug_dir: Directory to save intermediate debug videos (default: None)
        """
        self.base_chunk_duration = base_chunk_duration
        self.window_size = window_size
        self.slide_step = slide_step
        self.format_selector = format_selector
        self.debug_dir = debug_dir
        self.debug_window_count = 0

        # Three processing steps
        self.detect_step: Callable[[list[bytes], dict[str, Any]], Any] | None = None
        self.trim_step: Callable[[list[bytes], dict[str, Any]], Any] | None = None
        self.caption_step: Callable[[bytes, dict[str, Any]], Any] | None = None

    def set_detect_step(
        self, func: Callable[[list[bytes], dict[str, Any]], Any]
    ) -> None:
        """
        Set the detection step function.

        Args:
            func: Function that takes (window_chunks, metadata) and returns (is_highlight, metadata)
        """
        self.detect_step = func

    def set_trim_step(
        self,
        func: Callable[[list[bytes], dict[str, Any]], Any],
    ) -> None:
        """
        Set the trim step function.

        Args:
            func: Function that takes (window_chunks, metadata) and returns (trimmed_video, metadata)
        """
        self.trim_step = func

    def set_caption_step(self, func: Callable[[bytes, dict[str, Any]], Any]) -> None:
        """
        Set the caption step function.

        Args:
            func: Function that takes (video_data, metadata) and returns (title, description, metadata)
        """
        self.caption_step = func

    def _save_debug_video(
        self, video_data: bytes, step_name: str, window_num: int
    ) -> None:
        """
        Save a debug video if debug mode is enabled.

        Args:
            video_data: Video data to save
            step_name: Name of the processing step (e.g., "1_input", "2_detected", "3_trimmed", "4_final")
            window_num: Window number for filename
        """
        if self.debug_dir is None or not video_data:
            return

        try:
            filename = f"window_{window_num:04d}_{step_name}.mp4"
            filepath = self.debug_dir / filename
            with open(filepath, "wb") as f:
                f.write(video_data)
            logger.info(
                f"  [DEBUG] Saved {step_name}: {filename} ({len(video_data):,} bytes)"
            )
        except Exception as e:
            logger.warning(f"Failed to save debug video {step_name}: {e}")

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
                "-c:v",
                "copy",
                "-c:a",
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

    async def process_video_url(
        self,
        video_url: str,
        ws: Any,
        is_live: bool,
        create_snippet_message: Callable[[bytes, str, str, str], str],
        create_complete_message: Callable[[str], str],
        create_error_message: Callable[[str, str | None], str],
    ) -> None:
        """
        Process a video URL with real-time sliding window approach.

        This method processes chunks as they arrive from the stream, caching them
        and beginning the sliding window process immediately without downloading
        the entire video upfront.

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
                f"Starting real-time sliding window pipeline for {stream_type}: {video_url}"
            )
            logger.info(
                f"Window size: {self.window_size} chunks ({self.window_size * self.base_chunk_duration}s), "
                f"Slide step: {self.slide_step} chunks"
            )

            # Use a deque to cache chunks with a maximum size to prevent unbounded memory growth
            # We need to keep at least window_size chunks, but we'll keep more for overlap handling
            max_cache_size = max(
                self.window_size * 3, 20
            )  # Keep at least 3 windows worth
            chunk_cache: deque[bytes] = deque(maxlen=max_cache_size)

            # Track absolute chunk position for metadata
            total_chunks_received = 0
            current_window_start = 0
            highlight_count = 0

            # Track whether we've already processed certain positions to handle overlap
            # This prevents processing the same window multiple times
            last_processed_position = -1

            # Stream and process chunks in real-time (from sync generator in a thread)
            iterator = stream_and_chunk_video(
                url=video_url,
                chunk_duration=self.base_chunk_duration,
                format_selector=self.format_selector,
                additional_options=["--no-part"],
                is_live=is_live,
            )

            while True:
                try:
                    chunk_data = await asyncio.to_thread(next, iterator)
                except StopIteration:
                    break
                # Add chunk to cache
                chunk_cache.append(chunk_data)
                total_chunks_received += 1
                logger.info(
                    f"Received chunk {total_chunks_received}, cache size: {len(chunk_cache)}"
                )

                # Check if we have enough chunks to form a complete window
                if len(chunk_cache) < self.window_size:
                    logger.debug(
                        f"Waiting for more chunks ({len(chunk_cache)}/{self.window_size})"
                    )
                    continue

                # Calculate the window position in the cache
                # We want to process windows starting from current_window_start
                # but our cache is a sliding window itself
                cache_offset = total_chunks_received - len(chunk_cache)
                window_start_in_cache = current_window_start - cache_offset

                # Check if the window we want to process is still in cache
                if window_start_in_cache < 0:
                    # The window start has fallen out of cache, move to the earliest available position
                    window_start_in_cache = 0
                    current_window_start = cache_offset

                # Check if we have enough chunks in cache from this position
                if window_start_in_cache + self.window_size > len(chunk_cache):
                    logger.debug(
                        f"Not enough chunks in cache for window at position {current_window_start}"
                    )
                    continue

                # Skip if we've already processed this position
                if current_window_start <= last_processed_position:
                    continue

                # Extract window from cache
                window_chunks = list(chunk_cache)[
                    window_start_in_cache : window_start_in_cache + self.window_size
                ]

                logger.info(
                    f"Processing window: chunks {current_window_start}-{current_window_start + self.window_size - 1} "
                    f"(time: {current_window_start * self.base_chunk_duration}s-"
                    f"{(current_window_start + self.window_size) * self.base_chunk_duration}s)"
                )

                # Save input window chunks for debug
                if self.debug_dir is not None:
                    # Save individual chunks
                    for i, chunk in enumerate(window_chunks):
                        chunk_filename = (
                            f"window_{self.debug_window_count:04d}_0_chunk_{i:02d}.mp4"
                        )
                        chunk_filepath = self.debug_dir / chunk_filename
                        try:
                            with open(chunk_filepath, "wb") as f:
                                f.write(chunk)
                            logger.debug(
                                f"  [DEBUG] Saved chunk {i}: {chunk_filename} ({len(chunk):,} bytes)"
                            )
                        except Exception as e:
                            logger.warning(f"Failed to save debug chunk {i}: {e}")

                    # Save concatenated input window
                    input_video = await asyncio.to_thread(
                        self._concatenate_chunks, window_chunks
                    )
                    self._save_debug_video(
                        input_video, "1_input_window", self.debug_window_count
                    )

                # Create metadata for this window
                metadata: dict[str, Any] = {
                    "src_video_url": video_url,
                    "window_start_chunk": current_window_start,
                    "window_end_chunk": current_window_start + self.window_size - 1,
                    "window_start_time": current_window_start
                    * self.base_chunk_duration,
                    "window_end_time": (current_window_start + self.window_size)
                    * self.base_chunk_duration,
                    "base_chunk_duration": self.base_chunk_duration,
                }

                # Step 1: Detect if this window contains a highlight
                is_highlight = False
                if self.detect_step:
                    detect_result = self.detect_step(window_chunks, metadata)
                    if inspect.isawaitable(detect_result):
                        is_highlight, metadata = await detect_result
                    else:
                        is_highlight, metadata = detect_result
                    logger.info(
                        f"Detection result: {'HIGHLIGHT' if is_highlight else 'NO HIGHLIGHT'}"
                    )
                else:
                    logger.warning("No detect_step configured, skipping detection")

                if is_highlight:
                    # Save detected highlight window for debug
                    if self.debug_dir is not None:
                        detected_video = await asyncio.to_thread(
                            self._concatenate_chunks, window_chunks
                        )
                        self._save_debug_video(
                            detected_video,
                            "2_detected_highlight",
                            self.debug_window_count,
                        )

                    # Step 2: Trim to actual highlight portions
                    trimmed_video = b""
                    if self.trim_step:
                        trim_result = self.trim_step(window_chunks, metadata)
                        if inspect.isawaitable(trim_result):
                            trimmed_video, metadata = await trim_result
                        else:
                            trimmed_video, metadata = trim_result
                        logger.info(f"Trimmed video size: {len(trimmed_video)} bytes")

                        # Save trimmed video for debug
                        self._save_debug_video(
                            trimmed_video, "3_trimmed", self.debug_window_count
                        )
                    else:
                        # Default: concatenate all chunks in window
                        logger.warning(
                            "No trim_step configured, concatenating all chunks"
                        )
                        trimmed_video = await asyncio.to_thread(
                            self._concatenate_chunks, window_chunks
                        )

                        # Save concatenated video for debug
                        self._save_debug_video(
                            trimmed_video, "3_trimmed_fallback", self.debug_window_count
                        )

                    # Step 3: Generate caption and description
                    title = f"Highlight {highlight_count + 1}"
                    description = (
                        f"Highlight from {metadata['window_start_time']}s-"
                        f"{metadata['window_end_time']}s"
                    )

                    if self.caption_step:
                        caption_result = self.caption_step(trimmed_video, metadata)
                        if inspect.isawaitable(caption_result):
                            title, description, metadata = await caption_result
                        else:
                            title, description, metadata = caption_result
                        logger.info(f"Generated caption: {title}")
                    else:
                        logger.warning(
                            "No caption_step configured, using default caption"
                        )

                    # Save final video before sending for debug
                    self._save_debug_video(
                        trimmed_video, "4_final_output", self.debug_window_count
                    )

                    # Send the highlight
                    snippet_msg = create_snippet_message(
                        trimmed_video,
                        video_url,
                        title,
                        description,
                    )
                    await asyncio.to_thread(ws.send, snippet_msg)

                    highlight_count += 1
                    logger.info(f"Sent highlight {highlight_count} to client")

                    # Increment debug window counter for highlights
                    self.debug_window_count += 1

                    # Slide by entire window to avoid duplicate highlights
                    last_processed_position = current_window_start
                    current_window_start += self.window_size
                    logger.info(
                        f"Sliding by {self.window_size} chunks (highlight found)"
                    )
                else:
                    # No highlight, slide by step size
                    last_processed_position = current_window_start
                    current_window_start += self.slide_step
                    logger.info(f"Sliding by {self.slide_step} chunks (no highlight)")

            # Send completion message
            await asyncio.to_thread(ws.send, create_complete_message(video_url))
            logger.info(
                f"Pipeline processing complete. Total highlights: {highlight_count}, Total chunks: {total_chunks_received}"
            )

        except Exception as e:
            logger.error(f"Pipeline error: {e}", exc_info=True)
            await asyncio.to_thread(ws.send, create_error_message(str(e), video_url))

    async def process_video_url_with_live_api(
        self,
        video_url: str,
        ws: Any,
        is_live: bool,
        system_instruction: str = "You are a helpful sports commentator providing live audio commentary.",
        prompt: str = "Provide engaging sports commentary for this video.",
        fps: float = 1.0,
        create_error_message: Callable[[str, str | None], str] | None = None,
    ) -> None:
        """
        Process a video URL using Gemini Live API for real-time audio commentary.

        This method:
        1. Streams and chunks the video (same as process_video_url)
        2. Collects chunks in memory
        3. Sends them to Gemini Live API via live.py
        4. Receives audio commentary
        5. Stitches audio with video
        6. Sends fragmented MP4 through websocket

        Args:
            video_url: URL of video to process
            ws: WebSocket connection object
            is_live: Whether the video is a live stream
            system_instruction: System instruction for Gemini model
            prompt: User prompt for commentary generation
            fps: Frames per second to extract from video chunks (default: 1.0)
            create_error_message: Optional function to create error message JSON
        """
        try:
            stream_type = "live stream" if is_live else "video"
            logger.info(
                f"Starting Live API processing for {stream_type}: {video_url}"
            )

            # Collect all chunks from the video
            chunks: list[bytes] = []
            iterator = stream_and_chunk_video(
                url=video_url,
                chunk_duration=self.base_chunk_duration,
                format_selector=self.format_selector,
                additional_options=["--no-part"],
                is_live=is_live,
            )

            logger.info("Collecting video chunks...")
            while True:
                try:
                    chunk_data = await asyncio.to_thread(next, iterator)
                    chunks.append(chunk_data)
                    logger.debug(f"Collected chunk {len(chunks)}")
                except StopIteration:
                    break

            logger.info(f"Collected {len(chunks)} chunks, processing with Live API...")

            # Process chunks with Live API
            await process_chunks_with_live_api(
                chunks=chunks,
                websocket=ws,
                system_instruction=system_instruction,
                prompt=prompt,
                fps=fps,
            )

            logger.info("Live API processing complete")

        except Exception as e:
            logger.error(f"Live API pipeline error: {e}", exc_info=True)
            if create_error_message:
                await asyncio.to_thread(ws.send, create_error_message(str(e), video_url))


def create_highlight_pipeline(
    base_chunk_duration: int = 4,
    window_size: int = 9,
    slide_step: int = 3,
    debug_dir: Path | None = None,
) -> SlidingWindowPipeline:
    """
    Create a sliding window pipeline configured for highlight detection.

    This pipeline:
    - Processes videos in 4-second base chunks (configurable)
    - Uses 9-chunk sliding windows (36 seconds total)
    - Applies 3-step processing: detect, trim, caption
    - Slides by 3 chunks when no highlight, or by full window when highlight found

    Args:
        base_chunk_duration: Duration of each base chunk in seconds (default: 4)
        window_size: Number of chunks per window (default: 9)
        slide_step: Chunks to slide when no highlight (default: 3)
        debug_dir: Directory to save intermediate debug videos (default: None)

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
        debug_dir=debug_dir,
    )

    # Set up the three processing steps
    pipeline.set_detect_step(detect_highlight_step)
    pipeline.set_trim_step(trim_highlight_step)
    pipeline.set_caption_step(caption_highlight_step)

    return pipeline
