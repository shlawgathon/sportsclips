"""
Video processing pipeline for streaming and chunking videos with sliding window approach.

This module provides functionality to download video streams, split them into
fixed-duration chunks, and process them with a sliding window for highlight detection
and optional live commentary generation. Uses queue-based architecture for independent
pipeline processing.
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

    async def _produce_chunks(
        self,
        video_url: str,
        is_live: bool,
        highlight_queue: asyncio.Queue[bytes | None],
        live_queue: asyncio.Queue[bytes | None] | None,
    ) -> None:
        """
        Producer: Download video chunks and distribute to consumer queues.

        Reads chunks from the video stream and puts them into queues for
        independent processing by highlight detection and live commentary pipelines.

        Args:
            video_url: URL of video to process
            is_live: Whether the video is a live stream
            highlight_queue: Queue for highlight detection pipeline
            live_queue: Queue for live commentary pipeline (None if disabled)
        """
        # Helper function to safely get next item from iterator
        def safe_next(it):
            try:
                return (True, next(it))
            except StopIteration:
                return (False, None)

        try:
            # Stream and chunk the video
            iterator = stream_and_chunk_video(
                url=video_url,
                chunk_duration=self.base_chunk_duration,
                format_selector=self.format_selector,
                additional_options=["--no-part"],
                is_live=is_live,
            )

            chunk_count = 0
            while True:
                has_next, chunk_data = await asyncio.to_thread(safe_next, iterator)
                if not has_next:
                    break

                chunk_count += 1
                logger.info(f"[Producer] Received chunk {chunk_count}")

                # Distribute chunk to both queues concurrently (non-blocking)
                # This ensures that if one queue is full, the other can still receive chunks
                put_tasks = [highlight_queue.put(chunk_data)]
                if live_queue:
                    put_tasks.append(live_queue.put(chunk_data))
                await asyncio.gather(*put_tasks)

            logger.info(f"[Producer] Finished downloading {chunk_count} chunks")

        except Exception as e:
            logger.error(f"[Producer] Error: {e}", exc_info=True)

        finally:
            # Signal completion by sending None sentinel to both queues concurrently
            completion_tasks = [highlight_queue.put(None)]
            if live_queue:
                completion_tasks.append(live_queue.put(None))
            await asyncio.gather(*completion_tasks)
            logger.info("[Producer] Sent completion signals to all queues")

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
        enable_live_commentary: bool = False,
        live_commentary_config: dict[str, Any] | None = None,
    ) -> None:
        """
        Process a video URL using queue-based architecture for independent pipeline processing.

        This method orchestrates three concurrent tasks:
        1. Producer: Downloads video chunks and distributes to queues
        2. Highlight Detection Consumer: Processes chunks with sliding window
        3. Live Commentary Consumer (optional): Generates AI commentary for each chunk

        The queue-based architecture allows each pipeline to process at its own pace,
        preventing faster pipelines from blocking slower ones.

        Args:
            video_url: URL of video to process
            ws: WebSocket connection object
            is_live: Whether the video is a live stream
            create_snippet_message: Function to create snippet message JSON
            create_complete_message: Function to create completion message JSON
            create_error_message: Function to create error message JSON
            enable_live_commentary: Whether to enable live commentary generation
            live_commentary_config: Configuration for live commentary (system_instruction, prompt, fps)
        """
        try:
            stream_type = "live stream" if is_live else "video"
            pipelines_enabled = []
            pipelines_enabled.append("Highlight Detection")
            if enable_live_commentary:
                pipelines_enabled.append("Live Commentary")

            logger.info(
                f"Starting queue-based pipeline for {stream_type}: {video_url}"
            )
            logger.info(f"Active pipelines: {', '.join(pipelines_enabled)}")
            logger.info(
                f"Window config: {self.window_size} chunks ({self.window_size * self.base_chunk_duration}s), "
                f"slide step: {self.slide_step} chunks"
            )

            # Create queues for independent pipeline processing
            highlight_queue: asyncio.Queue[bytes | None] = asyncio.Queue(maxsize=20)
            live_queue: asyncio.Queue[bytes | None] | None = None

            if enable_live_commentary:
                live_queue = asyncio.Queue(maxsize=20)

            # Create producer task (downloads and distributes chunks)
            producer_task = asyncio.create_task(
                self._produce_chunks(
                    video_url=video_url,
                    is_live=is_live,
                    highlight_queue=highlight_queue,
                    live_queue=live_queue,
                ),
                name="chunk_producer"
            )

            # Create highlight detection consumer task
            highlight_task = asyncio.create_task(
                self._process_highlights_from_queue(
                    queue=highlight_queue,
                    video_url=video_url,
                    ws=ws,
                    create_snippet_message=create_snippet_message,
                    create_complete_message=create_complete_message,
                    create_error_message=create_error_message,
                ),
                name="highlight_detection"
            )

            # Create live commentary consumer task (if enabled)
            live_task = None
            if enable_live_commentary and live_queue:
                config = live_commentary_config or {}
                system_instruction = config.get(
                    "system_instruction",
                    "You are an enthusiastic sports commentator providing live audio commentary."
                )
                prompt = config.get(
                    "prompt",
                    "Provide engaging sports commentary for this video."
                )
                live_fps = config.get("fps", 1.0)

                live_task = asyncio.create_task(
                    self._process_live_commentary_from_queue(
                        queue=live_queue,
                        video_url=video_url,
                        ws=ws,
                        system_instruction=system_instruction,
                        prompt=prompt,
                        fps=live_fps,
                    ),
                    name="live_commentary"
                )

            # Wait for all tasks to complete
            tasks = [producer_task, highlight_task]
            if live_task:
                tasks.append(live_task)

            results = await asyncio.gather(*tasks, return_exceptions=True)

            # Check for errors in any task
            for i, result in enumerate(results):
                if isinstance(result, Exception):
                    task_name = tasks[i].get_name()
                    logger.error(f"Task '{task_name}' failed: {result}", exc_info=result)
                    raise result

            logger.info("All pipelines completed successfully")

        except Exception as e:
            logger.error(f"Pipeline error: {e}", exc_info=True)
            await asyncio.to_thread(ws.send, create_error_message(str(e), video_url))

    async def _process_highlights_from_queue(
        self,
        queue: asyncio.Queue[bytes | None],
        video_url: str,
        ws: Any,
        create_snippet_message: Callable[[bytes, str, str, str], str],
        create_complete_message: Callable[[str], str],
        create_error_message: Callable[[str, str | None], str],
    ) -> None:
        """
        Consumer: Process chunks from queue for highlight detection using sliding window.

        Args:
            queue: Queue to read chunks from
            video_url: Source video URL
            ws: WebSocket connection for sending results
            create_snippet_message: Function to create snippet message JSON
            create_complete_message: Function to create completion message JSON
            create_error_message: Function to create error message JSON
        """
        try:
            logger.info("[Highlight Detection] Starting pipeline...")

            # Use a deque to cache chunks for sliding window
            max_cache_size = max(self.window_size * 3, 20)
            chunk_cache: deque[bytes] = deque(maxlen=max_cache_size)

            # Track chunk position for metadata
            total_chunks_received = 0
            current_window_start = 0
            highlight_count = 0
            last_processed_position = -1

            while True:
                # Get chunk from queue (None signals completion)
                chunk_data = await queue.get()
                if chunk_data is None:
                    logger.info("[Highlight Detection] Received completion signal")
                    break

                # Add chunk to cache
                chunk_cache.append(chunk_data)
                total_chunks_received += 1
                logger.info(
                    f"[Highlight Detection] Received chunk {total_chunks_received}, cache size: {len(chunk_cache)}"
                )

                # Check if we have enough chunks to form a complete window
                if len(chunk_cache) < self.window_size:
                    logger.debug(
                        f"[Highlight Detection] Waiting for more chunks ({len(chunk_cache)}/{self.window_size})"
                    )
                    continue

                # Calculate the window position in the cache
                cache_offset = total_chunks_received - len(chunk_cache)
                window_start_in_cache = current_window_start - cache_offset

                # Check if the window we want to process is still in cache
                if window_start_in_cache < 0:
                    window_start_in_cache = 0
                    current_window_start = cache_offset

                # Check if we have enough chunks in cache from this position
                if window_start_in_cache + self.window_size > len(chunk_cache):
                    logger.debug(
                        f"[Highlight Detection] Not enough chunks in cache for window at position {current_window_start}"
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
                    f"[Highlight Detection] Processing window: chunks {current_window_start}-{current_window_start + self.window_size - 1}"
                )

                # Save debug videos if enabled
                if self.debug_dir is not None:
                    for i, chunk in enumerate(window_chunks):
                        chunk_filename = f"window_{self.debug_window_count:04d}_0_chunk_{i:02d}.mp4"
                        chunk_filepath = self.debug_dir / chunk_filename
                        try:
                            with open(chunk_filepath, "wb") as f:
                                f.write(chunk)
                        except Exception as e:
                            logger.warning(f"Failed to save debug chunk {i}: {e}")

                    input_video = await asyncio.to_thread(self._concatenate_chunks, window_chunks)
                    self._save_debug_video(input_video, "1_input_window", self.debug_window_count)

                # Create metadata for this window
                metadata: dict[str, Any] = {
                    "src_video_url": video_url,
                    "window_start_chunk": current_window_start,
                    "window_end_chunk": current_window_start + self.window_size - 1,
                    "window_start_time": current_window_start * self.base_chunk_duration,
                    "window_end_time": (current_window_start + self.window_size) * self.base_chunk_duration,
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
                        f"[Highlight Detection] Result: {'HIGHLIGHT' if is_highlight else 'NO HIGHLIGHT'}"
                    )
                else:
                    logger.warning("[Highlight Detection] No detect_step configured")

                if is_highlight:
                    # Save detected highlight for debug
                    if self.debug_dir is not None:
                        detected_video = await asyncio.to_thread(self._concatenate_chunks, window_chunks)
                        self._save_debug_video(detected_video, "2_detected_highlight", self.debug_window_count)

                    # Step 2: Trim to actual highlight portions
                    trimmed_video = b""
                    if self.trim_step:
                        trim_result = self.trim_step(window_chunks, metadata)
                        if inspect.isawaitable(trim_result):
                            trimmed_video, metadata = await trim_result
                        else:
                            trimmed_video, metadata = trim_result
                        logger.info(f"[Highlight Detection] Trimmed video size: {len(trimmed_video)} bytes")
                        self._save_debug_video(trimmed_video, "3_trimmed", self.debug_window_count)
                    else:
                        logger.warning("[Highlight Detection] No trim_step configured")
                        trimmed_video = await asyncio.to_thread(self._concatenate_chunks, window_chunks)
                        self._save_debug_video(trimmed_video, "3_trimmed_fallback", self.debug_window_count)

                    # Step 3: Generate caption and description
                    title = f"Highlight {highlight_count + 1}"
                    description = f"Highlight from {metadata['window_start_time']}s-{metadata['window_end_time']}s"

                    if self.caption_step:
                        caption_result = self.caption_step(trimmed_video, metadata)
                        if inspect.isawaitable(caption_result):
                            title, description, metadata = await caption_result
                        else:
                            title, description, metadata = caption_result
                        logger.info(f"[Highlight Detection] Generated caption: {title}")
                    else:
                        logger.warning("[Highlight Detection] No caption_step configured")

                    # Save final video for debug
                    self._save_debug_video(trimmed_video, "4_final_output", self.debug_window_count)

                    # Send the highlight
                    snippet_msg = create_snippet_message(trimmed_video, video_url, title, description)
                    await asyncio.to_thread(ws.send, snippet_msg)

                    highlight_count += 1
                    logger.info(f"[Highlight Detection] Sent highlight {highlight_count}")

                    self.debug_window_count += 1

                    # Slide by entire window to avoid duplicate highlights
                    last_processed_position = current_window_start
                    current_window_start += self.window_size
                    logger.info(f"[Highlight Detection] Sliding by {self.window_size} chunks")
                else:
                    # No highlight, slide by step size
                    last_processed_position = current_window_start
                    current_window_start += self.slide_step
                    logger.info(f"[Highlight Detection] Sliding by {self.slide_step} chunks")

            # Send completion message
            await asyncio.to_thread(ws.send, create_complete_message(video_url))
            logger.info(
                f"[Highlight Detection] Complete! Total highlights: {highlight_count}, Total chunks: {total_chunks_received}"
            )

        except Exception as e:
            logger.error(f"[Highlight Detection] Error: {e}", exc_info=True)
            await asyncio.to_thread(ws.send, create_error_message(str(e), video_url))

    async def _process_live_commentary_from_queue(
        self,
        queue: asyncio.Queue[bytes | None],
        video_url: str,
        ws: Any,
        system_instruction: str,
        prompt: str,
        fps: float,
    ) -> None:
        """
        Consumer: Process 8-second chunks (2x 4-second base chunks) with Live API commentary.

        Buffering approach:
        1. Read 2 consecutive 4-second chunks from queue
        2. Concatenate them into a single 8-second chunk
        3. Extract frames at 4 FPS (~32 frames per 8-second chunk)
        4. Send all frames to Live API (~3.2 seconds to send)
        5. Send prompt requesting minimal 3-12 word commentary
        6. Collect complete audio response
        7. Package audio + video together
        8. Send as live_commentary_chunk message
        9. Repeat for next pair of chunks

        This approach is reliable and produces consistent 8-second results.

        Args:
            queue: Queue to read chunks from (4-second base chunks)
            video_url: Source video URL
            ws: WebSocket connection for sending results
            system_instruction: System instruction for Gemini model
            prompt: User prompt for commentary generation
            fps: Frames per second to extract from video chunks (default: 4.0)
        """
        from .live import stitch_audio_video, create_fragmented_mp4, extract_frames_from_chunk
        from .llm import GeminiLiveClient
        import base64
        import json
        import subprocess
        import tempfile

        def concatenate_video_chunks(chunk1: bytes, chunk2: bytes) -> bytes:
            """Concatenate two video chunks into one using ffmpeg."""
            with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f1:
                f1.write(chunk1)
                f1_path = f1.name

            with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f2:
                f2.write(chunk2)
                f2_path = f2.name

            with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f_out:
                out_path = f_out.name

            try:
                # Use ffmpeg concat protocol
                concat_cmd = [
                    'ffmpeg', '-y', '-i', f1_path, '-i', f2_path,
                    '-filter_complex', '[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[outv][outa]',
                    '-map', '[outv]', '-map', '[outa]',
                    '-c:v', 'libx264', '-c:a', 'aac',
                    out_path
                ]
                subprocess.run(concat_cmd, check=True, capture_output=True)

                with open(out_path, 'rb') as f:
                    return f.read()
            finally:
                import os
                os.unlink(f1_path)
                os.unlink(f2_path)
                os.unlink(out_path)

        live_client = None
        chunk_number = 0
        chunk_buffer: list[bytes] = []

        try:
            logger.info("[Live Commentary] Starting per-chunk commentary pipeline (8s chunks)...")

            # Create and connect Live API client once
            live_client = GeminiLiveClient(system_instruction=system_instruction)
            await live_client.connect()
            logger.info("[Live Commentary] ✓ Connected to Live API")

            # Process pairs of 4-second chunks as 8-second chunks
            while True:
                # Read a chunk from the queue
                chunk_data = await queue.get()
                if chunk_data is None:
                    # If we have a buffered chunk, process it alone
                    if chunk_buffer:
                        logger.info("[Live Commentary] Processing final buffered chunk alone")
                        chunk_number += 1
                        combined_chunk = chunk_buffer[0]
                        chunk_buffer.clear()
                    else:
                        logger.info("[Live Commentary] Received completion signal")
                        break
                else:
                    # Add to buffer
                    chunk_buffer.append(chunk_data)

                    # Wait until we have 2 chunks
                    if len(chunk_buffer) < 2:
                        continue

                    # Combine the two chunks
                    chunk_number += 1
                    logger.info(f"[Live Commentary] Combining 2 chunks into 8-second chunk {chunk_number}...")
                    combined_chunk = await asyncio.to_thread(
                        concatenate_video_chunks, chunk_buffer[0], chunk_buffer[1]
                    )
                    chunk_buffer.clear()

                logger.info(f"[Live Commentary] Processing 8-second chunk {chunk_number}...")

                try:
                    # Step 1: Extract frames from combined 8-second chunk
                    frames = await asyncio.to_thread(extract_frames_from_chunk, combined_chunk, fps)
                    if not frames:
                        logger.warning(f"[Live Commentary] No frames in chunk {chunk_number}, skipping")
                        continue

                    logger.info(f"[Live Commentary] Extracted {len(frames)} frames from 8-second chunk {chunk_number}")

                    # Step 2: Send frames to Live API
                    for i, frame in enumerate(frames, 1):
                        await live_client.send_frame(frame)
                    logger.info(f"[Live Commentary] Sent {len(frames)} frames to Live API")

                    # Step 3: Send prompt to trigger commentary
                    await live_client.send(prompt, end_of_turn=True)
                    logger.info("[Live Commentary] Sent prompt, collecting audio response...")

                    # Step 4: Collect complete audio response
                    # For 3-12 words at 24kHz, we expect ~20-60 chunks
                    audio_chunks: list[bytes] = []
                    async for audio_chunk in live_client.receive_audio_chunks():
                        audio_chunks.append(audio_chunk)
                        # Stop after reasonable limit for minimal commentary
                        if len(audio_chunks) >= 60:  # ~2-3 seconds of audio
                            break

                    audio_pcm = b"".join(audio_chunks)
                    logger.info(f"[Live Commentary] Collected {len(audio_chunks)} audio chunks ({len(audio_pcm):,} bytes)")

                    if not audio_pcm:
                        logger.warning(f"[Live Commentary] No audio generated for chunk {chunk_number}")
                        continue

                    # Step 5: Stitch audio with combined 8-second video
                    stitched_video = await asyncio.to_thread(
                        stitch_audio_video, combined_chunk, audio_pcm, 24000
                    )
                    logger.info(f"[Live Commentary] Stitched audio+video: {len(stitched_video):,} bytes")

                    # Step 6: Create fragmented MP4
                    fragmented_video = await asyncio.to_thread(
                        create_fragmented_mp4, stitched_video
                    )
                    logger.info(f"[Live Commentary] Created fragmented MP4: {len(fragmented_video):,} bytes")

                    # Step 7: Send as live_commentary_chunk message
                    message = json.dumps(
                        {
                            "type": "live_commentary_chunk",
                            "data": {
                                "video_data": base64.b64encode(fragmented_video).decode("utf-8"),
                                "metadata": {
                                    "src_video_url": video_url,
                                    "chunk_number": chunk_number,
                                    "format": "fragmented_mp4",
                                    "audio_sample_rate": 24000,
                                    "commentary_length_bytes": len(audio_pcm),
                                    "video_length_bytes": len(fragmented_video),
                                    "base_chunks_combined": 2,
                                    "total_duration_seconds": 8,
                                },
                            },
                        }
                    )

                    if hasattr(ws, "send"):
                        if asyncio.iscoroutinefunction(ws.send):
                            await ws.send(message)
                        else:
                            await asyncio.to_thread(ws.send, message)
                    else:
                        await asyncio.to_thread(ws.send, message)

                    logger.info(f"[Live Commentary] ✓ Sent chunk {chunk_number} with commentary")

                except Exception as e:
                    logger.error(f"[Live Commentary] Error processing chunk {chunk_number}: {e}", exc_info=True)
                    continue

            logger.info(f"[Live Commentary] Complete! Processed {chunk_number} chunks")

        except Exception as e:
            logger.error(f"[Live Commentary] Error: {e}", exc_info=True)
        finally:
            # Clean up Live API connection
            if live_client:
                try:
                    await live_client.disconnect()
                    logger.info("[Live Commentary] Disconnected")
                except Exception as e:
                    logger.error(f"[Live Commentary] Error disconnecting: {e}")


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
