"""
Highlight detection step using LLM-based video analysis.

This module provides a pipeline step that uses the Gemini agent to determine
whether a video snippet contains interesting or highlight-worthy content.
"""

import asyncio
import logging
import os
import tempfile
from typing import Any

from ...llm import GeminiAgent
from .prompt import HIGHLIGHT_DETECTION_PROMPT

logger = logging.getLogger(__name__)


class HighlightDetector:
    """Detects highlights in video snippets using LLM analysis."""

    def __init__(self, model_name: str = "gemini-1.5-flash"):
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
                )

                # Parse the response
                response_clean = response.strip().upper()
                is_highlight = "YES" in response_clean

                logger.info(
                    f"Chunk {metadata.get('chunk_index', 'unknown')}: "
                    f"{'HIGHLIGHT' if is_highlight else 'NOT HIGHLIGHT'} (response: {response_clean})"
                )

                return is_highlight

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


def is_highlight_step(
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

    # Run async function in sync context
    loop = asyncio.get_event_loop()
    if loop.is_running():
        # If we're already in an async context, create a new event loop
        # This is a workaround for running async code from sync pipeline
        import concurrent.futures

        with concurrent.futures.ThreadPoolExecutor() as executor:
            future = executor.submit(
                asyncio.run, detector.is_highlight(video_data, metadata)
            )
            is_highlight = future.result()
    else:
        # Run in the current event loop
        is_highlight = loop.run_until_complete(
            detector.is_highlight(video_data, metadata)
        )

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
