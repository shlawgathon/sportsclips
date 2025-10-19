"""
Highlight captioning step using LLM-based video analysis.

This module provides a pipeline step that uses the Gemini agent to generate
engaging titles and descriptions for highlight videos.
"""

import asyncio
import logging
import os
import tempfile
from typing import Any

from ...llm import GeminiAgent
from .prompt import CAPTION_HIGHLIGHT_PROMPT

logger = logging.getLogger(__name__)


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


class HighlightCaptioner:
    """Generates titles and descriptions for highlight videos using LLM analysis."""

    def __init__(self, model_name: str = "gemini-2.5-flash"):
        """
        Initialize the highlight captioner.

        Args:
            model_name: Name of the Gemini model to use
        """
        self.agent = GeminiAgent(model_name=model_name)
        self.prompt = CAPTION_HIGHLIGHT_PROMPT

    async def generate_caption(
        self, video_data: bytes, metadata: dict[str, Any]
    ) -> tuple[str, str, dict[str, Any]]:
        """
        Generate title and description for a highlight video.

        Args:
            video_data: Trimmed highlight video bytes
            metadata: Window metadata

        Returns:
            Tuple of (title, description, updated_metadata)
        """
        try:
            # Generate captions with Gemini
            response = await _analyze_video_with_gemini(
                video_data, self.prompt, self.agent
            )

            logger.info(f"Caption response: {response}")

            # Parse the response
            title = ""
            description = ""

            for line in response.split("\n"):
                line = line.strip()
                if line.startswith("TITLE:"):
                    title = line.replace("TITLE:", "").strip()
                elif line.startswith("DESCRIPTION:"):
                    description = line.replace("DESCRIPTION:", "").strip()

            # Fallback if parsing failed
            if not title:
                start_time = metadata.get("window_start_time", 0)
                title = f"Highlight at {start_time}s"
                logger.warning("Failed to parse title from response, using fallback")

            if not description:
                start_time = metadata.get("window_start_time", 0)
                end_time = metadata.get("window_end_time", 0)
                description = f"Highlight detected from {start_time}s to {end_time}s"
                logger.warning(
                    "Failed to parse description from response, using fallback"
                )

            logger.info(f"Generated title: {title}")
            logger.info(f"Generated description: {description}")

            metadata["caption_method"] = "gemini_llm"
            metadata["caption_response"] = response

            return title, description, metadata

        except Exception as e:
            logger.error(f"Error in generate_caption: {e}", exc_info=True)

            # Fallback captions
            start_time = metadata.get("window_start_time", 0)
            end_time = metadata.get("window_end_time", 0)
            title = f"Highlight at {start_time}s"
            description = f"Highlight detected from {start_time}s to {end_time}s"

            metadata["caption_method"] = "error_fallback"
            metadata["caption_error"] = str(e)

            return title, description, metadata


# Global captioner instance (lazily initialized)
_captioner: HighlightCaptioner | None = None


def _get_captioner() -> HighlightCaptioner:
    """Get or create the global captioner instance."""
    global _captioner
    if _captioner is None:
        _captioner = HighlightCaptioner()
    return _captioner


def caption_highlight_step(
    video_data: bytes, metadata: dict[str, Any]
) -> tuple[str, str, dict[str, Any]]:
    """
    Pipeline step that generates title and description for a highlight.

    Uses Gemini LLM to analyze the trimmed highlight and generate an
    engaging title and description.

    Args:
        video_data: Trimmed highlight video bytes
        metadata: Window metadata

    Returns:
        Tuple of (title, description, updated_metadata)
    """
    logger.info("Running caption_highlight_step with Gemini LLM")

    captioner = _get_captioner()
    return _run_async(captioner.generate_caption(video_data, metadata))
