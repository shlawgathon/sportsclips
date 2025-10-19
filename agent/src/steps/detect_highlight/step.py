"""
Highlight detection step using LLM-based video analysis.

This module provides a pipeline step that uses the Gemini agent to determine
whether a video snippet contains interesting or highlight-worthy content.
"""

import logging
import os
import tempfile
from typing import Any

from ...llm import GeminiAgent
from .prompt import HIGHLIGHT_DETECTION_PROMPT, HIGHLIGHT_DETECTION_TOOL

logger = logging.getLogger(__name__)


class HighlightDetector:
    """Detects highlights in video snippets using LLM analysis."""

    def __init__(self, model_name: str = "gemini-2.5-flash"):
        """
        Initialize the highlight detector.

        Args:
            model_name: Name of the Gemini model to use (default: gemini-1.5-flash)
        """
        self.agent = GeminiAgent(model_name=model_name)
        self.prompt = HIGHLIGHT_DETECTION_PROMPT

    async def is_highlight(self, video_data: bytes, metadata: dict[str, Any]) -> bool:
        """
        Determine if a video snippet is a highlight.

        Args:
            video_data: Raw video bytes
            metadata: Video metadata dict

        Returns:
            bool: True if the video is a highlight, False otherwise
        """
        try:
            # Save video data to a temporary file for Gemini to process
            with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_file:
                temp_file.write(video_data)
                temp_path = temp_file.name

            try:
                # Use the agent to analyze the video
                logger.info(
                    f"Analyzing video snippet (chunk {metadata.get('chunk_index', 'unknown')})"
                )

                response = await self.agent.generate_from_video(
                    video_input=temp_path,
                    prompt=self.prompt,
                    tools=[HIGHLIGHT_DETECTION_TOOL],
                )

                # Extract function call response
                if (
                    isinstance(response, dict)
                    and response.get("name") == "report_highlight_detection"
                ):
                    args = response.get("args", {})
                    is_highlight: bool = bool(args.get("is_highlight", False))
                    confidence = args.get("confidence", "unknown")
                    reason = args.get("reason", "")

                    logger.info(
                        f"Chunk {metadata.get('chunk_index', 'unknown')}: "
                        f"{'HIGHLIGHT' if is_highlight else 'NOT HIGHLIGHT'} "
                        f"(confidence: {confidence}, reason: {reason})"
                    )

                    # Store detection details for downstream steps
                    metadata["detection_confidence"] = confidence
                    metadata["detection_reason"] = reason

                    return is_highlight
                else:
                    # Fallback if function calling didn't work
                    logger.warning(f"Unexpected response format: {response}")
                    return True

            finally:
                # Clean up temp file
                try:
                    os.unlink(temp_path)
                except Exception as e:
                    logger.warning(f"Failed to delete temp file {temp_path}: {e}")

        except Exception as e:
            logger.error(f"Error analyzing video: {e}", exc_info=True)
            # Default to including the clip if analysis fails
            return True


# Global detector instance (lazily initialized)
_detector: HighlightDetector | None = None


def _get_detector() -> HighlightDetector:
    """Get or create the global detector instance."""
    global _detector
    if _detector is None:
        _detector = HighlightDetector()
    return _detector


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
    import subprocess
    import uuid
    from pathlib import Path

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


async def detect_highlight_step(
    window_chunks: list[bytes], metadata: dict[str, Any]
) -> tuple[bool, dict[str, Any]]:
    """
    Pipeline step for sliding window highlight detection.

    Determines if a window of video chunks contains a highlight by
    concatenating the chunks and analyzing with the Gemini LLM.

    Args:
        window_chunks: List of video chunks (typically 9 chunks of 4 seconds each)
        metadata: Window metadata

    Returns:
        Tuple of (is_highlight, updated_metadata)
    """
    logger.info("Running detect_highlight_step with Gemini LLM")

    try:
        # Concatenate chunks for analysis
        window_video = _concatenate_chunks(window_chunks)

        # Create a temporary file for analysis
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_file:
            temp_file.write(window_video)
            temp_path = temp_file.name

        try:
            # Analyze with Gemini
            detector = _get_detector()
            response = await detector.agent.generate_from_video(
                video_input=temp_path,
                prompt=detector.prompt,
                tools=[HIGHLIGHT_DETECTION_TOOL],
            )

            # Extract function call response
            if (
                isinstance(response, dict)
                and response.get("name") == "report_highlight_detection"
            ):
                args = response.get("args", {})
                is_highlight: bool = bool(args.get("is_highlight", False))
                confidence = args.get("confidence", "unknown")
                reason = args.get("reason", "")

                logger.info(
                    f"Detection result: {'HIGHLIGHT' if is_highlight else 'NO HIGHLIGHT'} "
                    f"(confidence: {confidence}, reason: {reason})"
                )

                metadata["detection_method"] = "gemini_llm"
                metadata["is_highlight"] = is_highlight
                metadata["detection_confidence"] = confidence
                metadata["detection_reason"] = reason

                return is_highlight, metadata
            else:
                # Fallback if function calling didn't work
                logger.warning(f"Unexpected response format: {response}")
                metadata["detection_method"] = "gemini_llm"
                metadata["is_highlight"] = True
                return True, metadata

        finally:
            # Clean up temp file
            try:
                os.unlink(temp_path)
            except Exception as e:
                logger.warning(f"Failed to delete temp file {temp_path}: {e}")

    except Exception as e:
        logger.error(f"Error in detect_highlight_step: {e}", exc_info=True)
        # Default to not highlight on error to avoid false positives
        metadata["detection_method"] = "error"
        metadata["detection_error"] = str(e)
        return False, metadata


async def is_highlight_step(
    video_data: bytes, metadata: dict[str, Any]
) -> tuple[bytes, dict[str, Any]]:
    """
    Pipeline step that filters out non-highlight clips.

    This is a modulation function compatible with VideoPipeline.add_modulation().
    It analyzes the video using an LLM and only passes through clips that are
    determined to be highlights.

    Args:
        video_data: Raw video bytes
        metadata: Video metadata dict

    Returns:
        Tuple of (video_data, metadata) if it's a highlight, or (empty bytes, metadata)
        with is_highlight=False in metadata if not.
    """
    detector = _get_detector()

    # Await async detector directly
    is_highlight = await detector.is_highlight(video_data, metadata)

    # Update metadata
    metadata["is_highlight"] = is_highlight
    metadata["filtered_by"] = "highlight_detector"

    # If not a highlight, return empty bytes to signal filtering
    if not is_highlight:
        logger.info(
            f"Filtering out non-highlight chunk {metadata.get('chunk_index', 'unknown')}"
        )
        return b"", metadata

    logger.info(
        f"Passing through highlight chunk {metadata.get('chunk_index', 'unknown')}"
    )
    return video_data, metadata
