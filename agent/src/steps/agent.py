"""
Agent step functions for the sliding window pipeline.

These are the three processing steps used in the sliding window pipeline:
1. detect_highlight_step: Determines if a window contains a highlight
2. trim_highlight_step: Trims the window to the actual highlight portions
3. caption_highlight_step: Generates title and description for the highlight

These are placeholder implementations that will be replaced with actual
LLM-based logic for highlight detection, trimming, and captioning.
"""

import logging
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


def detect_highlight_step(
    window_chunks: list[bytes], metadata: dict[str, Any]
) -> tuple[bool, dict[str, Any]]:
    """
    Step 1: Determine if a window contains a highlight.

    This is a PLACEHOLDER implementation that always returns True.
    Replace this with actual LLM-based detection logic.

    Args:
        window_chunks: List of 7 video chunks (2 seconds each)
        metadata: Window metadata

    Returns:
        Tuple of (is_highlight, updated_metadata)
    """
    logger.info("Running detect_highlight_step (PLACEHOLDER)")

    # TODO: Implement actual detection logic
    # 1. Concatenate chunks or process individually
    # 2. Send to LLM (e.g., Gemini) for analysis
    # 3. Parse response to determine if it's a highlight

    # Placeholder: Always return True for testing
    metadata["detection_method"] = "placeholder"
    return True, metadata


def trim_highlight_step(
    window_chunks: list[bytes], metadata: dict[str, Any]
) -> tuple[bytes, dict[str, Any]]:
    """
    Step 2: Trim the window to the actual highlight portions.

    This is a PLACEHOLDER implementation that concatenates all chunks.
    Replace this with actual LLM-based trimming logic.

    Args:
        window_chunks: List of 7 video chunks (2 seconds each)
        metadata: Window metadata

    Returns:
        Tuple of (trimmed_video_data, updated_metadata)
    """
    logger.info("Running trim_highlight_step (PLACEHOLDER)")

    # TODO: Implement actual trimming logic
    # 1. Ask LLM which chunks contain the highlight
    # 2. Identify start and end chunks
    # 3. Concatenate only the relevant chunks
    # 4. Optionally, do frame-level trimming within chunks

    # Placeholder: Concatenate all chunks
    trimmed_video = _concatenate_chunks(window_chunks)
    metadata["trim_method"] = "placeholder_concat_all"
    metadata["trimmed_chunk_count"] = len(window_chunks)

    return trimmed_video, metadata


def caption_highlight_step(
    video_data: bytes, metadata: dict[str, Any]
) -> tuple[str, str, dict[str, Any]]:
    """
    Step 3: Generate title and description for the highlight.

    This is a PLACEHOLDER implementation that generates generic captions.
    Replace this with actual LLM-based captioning logic.

    Args:
        video_data: Trimmed highlight video bytes
        metadata: Window metadata

    Returns:
        Tuple of (title, description, updated_metadata)
    """
    logger.info("Running caption_highlight_step (PLACEHOLDER)")

    # TODO: Implement actual captioning logic
    # 1. Send video to LLM
    # 2. Request analysis and caption generation
    # 3. Parse response for title and description

    # Placeholder: Generate generic caption
    start_time = metadata.get("window_start_time", 0)
    end_time = metadata.get("window_end_time", 0)

    title = f"Highlight at {start_time}s"
    description = f"Highlight detected from {start_time}s to {end_time}s"

    metadata["caption_method"] = "placeholder"

    return title, description, metadata


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
