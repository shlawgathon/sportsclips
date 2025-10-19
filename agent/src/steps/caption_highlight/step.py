"""
Highlight captioning step using LLM-based video analysis.

This module provides a pipeline step that uses the Gemini agent to generate
engaging titles and descriptions for highlight videos.
"""

import logging
import os
import tempfile
from typing import Any

from ...llm import GeminiAgent
from .prompt import CAPTION_HIGHLIGHT_PROMPT, CAPTION_HIGHLIGHT_TOOL

logger = logging.getLogger(__name__)


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
        max_retries = 3
        last_error = None

        try:
            # Save video to temp file for Gemini
            with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_file:
                temp_file.write(video_data)
                temp_path = temp_file.name

            try:
                # Retry up to 3 times to get a valid caption
                for attempt in range(max_retries):
                    try:
                        logger.info(
                            f"Caption generation attempt {attempt + 1}/{max_retries}"
                        )

                        # Generate captions with Gemini using function calling
                        response = await self.agent.generate_from_video(
                            video_input=temp_path,
                            prompt=self.prompt,
                            tools=[CAPTION_HIGHLIGHT_TOOL],
                        )

                        logger.info(
                            f"Caption response (attempt {attempt + 1}): {response}"
                        )

                        # Extract function call response
                        if (
                            isinstance(response, dict)
                            and response.get("name") == "report_highlight_caption"
                        ):
                            args = response.get("args", {})
                            title = args.get("title", "")
                            description = args.get("description", "")
                            key_action = args.get("key_action", "")

                            # Validate that we got both title and description
                            if title and description:
                                logger.info(f"Generated title: {title}")
                                logger.info(f"Generated description: {description}")
                                if key_action:
                                    logger.info(f"Key action: {key_action}")

                                metadata["caption_method"] = "gemini_function_calling"
                                metadata["key_action"] = key_action
                                metadata["caption_attempts"] = attempt + 1

                                return title, description, metadata
                            else:
                                # Missing required fields, retry
                                logger.warning(
                                    f"Attempt {attempt + 1}: Missing required fields "
                                    f"(title={bool(title)}, description={bool(description)}). "
                                    f"Will retry..."
                                )
                                last_error = (
                                    "Missing title or description in function call"
                                )
                                continue
                        else:
                            # Unexpected response format, retry
                            logger.warning(
                                f"Attempt {attempt + 1}: Unexpected response format: {response}. "
                                f"Will retry..."
                            )
                            last_error = f"Unexpected response format: {response}"
                            continue

                    except Exception as e:
                        logger.warning(
                            f"Attempt {attempt + 1} failed with error: {e}. "
                            f"Will retry..."
                            if attempt < max_retries - 1
                            else f"Final attempt failed: {e}"
                        )
                        last_error = str(e)
                        continue

                # All retries exhausted, use fallback
                logger.error(
                    f"All {max_retries} attempts failed. Last error: {last_error}. "
                    f"Using fallback captions."
                )
                start_time = metadata.get("window_start_time", 0)
                end_time = metadata.get("window_end_time", 0)
                title = f"Highlight at {start_time}s"
                description = f"Highlight detected from {start_time}s to {end_time}s"
                metadata["caption_method"] = "retry_exhausted_fallback"
                metadata["caption_attempts"] = max_retries
                metadata["last_error"] = last_error
                return title, description, metadata

            finally:
                # Clean up temp file
                try:
                    os.unlink(temp_path)
                except Exception as e:
                    logger.warning(f"Failed to delete temp file {temp_path}: {e}")

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


async def caption_highlight_step(
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
    result: tuple[str, str, dict[str, Any]] = await captioner.generate_caption(
        video_data, metadata
    )
    return result
