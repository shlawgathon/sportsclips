"""
Highlight trimming step using LLM-based video analysis.

This module provides a pipeline step that uses the Gemini agent to identify
which portions of a video window contain the actual highlight action.
"""

import asyncio
import logging
import os
import re
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any

from ...llm import GeminiAgent
from .prompt import TRIM_HIGHLIGHT_PROMPT

logger = logging.getLogger(__name__)


def _concatenate_chunks(chunks: list[bytes]) -> bytes:
    """
    Concatenate multiple video chunks into a single video file using ffmpeg.

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


async def _analyze_video_with_gemini(
    video_data: bytes, prompt: str, agent: GeminiAgent
) -> str:
    """
    Analyze video using Gemini LLM.

    Args:
        video_data: Raw video bytes
        prompt: Analysis prompt
        agent: GeminiAgent instance

    Returns:
        LLM response text
    """
    # Save video data to a temporary file for Gemini to process
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_file:
        temp_file.write(video_data)
        temp_path = temp_file.name

    try:
        # Use the agent to analyze the video
        response = await agent.generate_from_video(
            video_input=temp_path,
            prompt=prompt,
        )
        return response.strip()

    finally:
        # Clean up temp file
        try:
            os.unlink(temp_path)
        except Exception as e:
            logger.warning(f"Failed to delete temp file {temp_path}: {e}")


def _run_async(coro):
    """
    Run async function in sync context.

    Args:
        coro: Coroutine to run

    Returns:
        Result from coroutine
    """
    loop = asyncio.get_event_loop()
    if loop.is_running():
        # If we're already in an async context, create a new event loop
        # This is a workaround for running async code from sync pipeline
        import concurrent.futures

        with concurrent.futures.ThreadPoolExecutor() as executor:
            future = executor.submit(asyncio.run, coro)
            return future.result()
    else:
        # Run in the current event loop
        return loop.run_until_complete(coro)


class HighlightTrimmer:
    """Trims highlight videos to relevant portions using LLM analysis."""

    def __init__(self, model_name: str = "gemini-2.5-flash"):
        """
        Initialize the highlight trimmer.

        Args:
            model_name: Name of the Gemini model to use
        """
        self.agent = GeminiAgent(model_name=model_name)
        self.prompt = TRIM_HIGHLIGHT_PROMPT

    async def trim_highlight(
        self, window_chunks: list[bytes], metadata: dict[str, Any]
    ) -> tuple[bytes, dict[str, Any]]:
        """
        Trim a video window to the actual highlight portions.

        Args:
            window_chunks: List of video chunks
            metadata: Window metadata

        Returns:
            Tuple of (trimmed_video_data, updated_metadata)
        """
        try:
            # Concatenate all chunks for analysis
            full_window_video = _concatenate_chunks(window_chunks)

            # Ask Gemini which chunks to keep
            response = await _analyze_video_with_gemini(
                full_window_video, self.prompt, self.agent
            )

            logger.info(f"Trim response: {response}")

            # Parse the response (expected format: "START-END" like "2-5")
            try:
                response_clean = response.strip()
                if "-" in response_clean:
                    # Extract just the number range, handling potential extra text
                    match = re.search(r"(\d+)-(\d+)", response_clean)
                    if match:
                        start_chunk = int(match.group(1))
                        end_chunk = int(match.group(2))

                        # Validate range
                        start_chunk = max(1, min(start_chunk, 7))
                        end_chunk = max(1, min(end_chunk, 7))

                        if start_chunk > end_chunk:
                            start_chunk, end_chunk = end_chunk, start_chunk
                    else:
                        raise ValueError("Could not parse chunk range")
                else:
                    raise ValueError("Response does not contain a range")

                # Convert to 0-indexed
                start_idx = start_chunk - 1
                end_idx = end_chunk  # end_chunk is inclusive, so we don't subtract 1

                logger.info(
                    f"Trimming to chunks {start_chunk}-{end_chunk} "
                    f"(indices {start_idx}:{end_idx})"
                )

                # Extract and concatenate the selected chunks
                selected_chunks = window_chunks[start_idx:end_idx]
                trimmed_video = _concatenate_chunks(selected_chunks)

                metadata["trim_method"] = "gemini_llm"
                metadata["trim_response"] = response_clean
                metadata["trimmed_chunk_start"] = start_chunk
                metadata["trimmed_chunk_end"] = end_chunk
                metadata["trimmed_chunk_count"] = len(selected_chunks)

                return trimmed_video, metadata

            except (ValueError, IndexError) as e:
                logger.warning(
                    f"Failed to parse trim response '{response}': {e}. Using all chunks."
                )
                # Fallback: use all chunks
                metadata["trim_method"] = "gemini_llm_fallback"
                metadata["trim_response"] = response
                metadata["trim_error"] = str(e)
                metadata["trimmed_chunk_count"] = len(window_chunks)
                return full_window_video, metadata

        except Exception as e:
            logger.error(f"Error in trim_highlight: {e}", exc_info=True)
            # Fallback: concatenate all chunks
            trimmed_video = _concatenate_chunks(window_chunks)
            metadata["trim_method"] = "error_fallback"
            metadata["trim_error"] = str(e)
            metadata["trimmed_chunk_count"] = len(window_chunks)
            return trimmed_video, metadata


# Global trimmer instance (lazily initialized)
_trimmer: HighlightTrimmer | None = None


def _get_trimmer() -> HighlightTrimmer:
    """Get or create the global trimmer instance."""
    global _trimmer
    if _trimmer is None:
        _trimmer = HighlightTrimmer()
    return _trimmer


def trim_highlight_step(
    window_chunks: list[bytes], metadata: dict[str, Any]
) -> tuple[bytes, dict[str, Any]]:
    """
    Pipeline step that trims a video window to actual highlight portions.

    Uses Gemini LLM to identify which chunks contain the highlight and
    concatenates only those chunks.

    Args:
        window_chunks: List of 7 video chunks (2 seconds each)
        metadata: Window metadata

    Returns:
        Tuple of (trimmed_video_data, updated_metadata)
    """
    logger.info("Running trim_highlight_step with Gemini LLM")

    trimmer = _get_trimmer()
    return _run_async(trimmer.trim_highlight(window_chunks, metadata))
