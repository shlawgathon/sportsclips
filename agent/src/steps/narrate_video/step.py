"""
Video narration step using LLM-based video analysis.

This module provides a pipeline step that uses the Gemini agent to generate
brief narration text for video clips, which can then be converted to speech.
"""

import logging
import os
import tempfile
from typing import Any

from ...llm import GeminiAgent
from .prompt import NARRATE_VIDEO_PROMPT, NARRATE_VIDEO_TOOL

logger = logging.getLogger(__name__)


class VideoNarrator:
    """Generates narration text for video clips using LLM analysis."""

    def __init__(self, model_name: str = "gemini-2.5-flash"):
        """
        Initialize the video narrator.

        Args:
            model_name: Name of the Gemini model to use
        """
        self.agent = GeminiAgent(model_name=model_name)
        self.prompt = NARRATE_VIDEO_PROMPT

    async def generate_narration(
        self,
        video_data: bytes,
        metadata: dict[str, Any],
        previous_narrations: list[str] | None = None,
    ) -> tuple[str, dict[str, Any]]:
        """
        Generate narration text for a video clip.

        Args:
            video_data: Video clip bytes
            metadata: Video metadata
            previous_narrations: List of previous narration texts to avoid repetition

        Returns:
            Tuple of (narration_text, updated_metadata)
        """
        max_retries = 3
        last_error = None

        try:
            # Save video to temp file for Gemini
            with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_file:
                temp_file.write(video_data)
                temp_path = temp_file.name

            try:
                # Retry up to 3 times to get valid narration
                for attempt in range(max_retries):
                    try:
                        logger.info(
                            f"Narration generation attempt {attempt + 1}/{max_retries}"
                        )

                        # Build prompt by replacing the {previous_narrations} placeholder
                        if previous_narrations:
                            previous_narrations_text = f"""IMPORTANT: Avoid repetition! Here are the previous {len(previous_narrations)} narrations that were just generated:
{chr(10).join(f'- "{narr}"' for narr in previous_narrations)}

Focus on NEW aspects, different details, or different perspectives that haven't been covered yet."""
                        else:
                            previous_narrations_text = ""

                        prompt = self.prompt.replace(
                            "{previous_narrations}", previous_narrations_text
                        )

                        # Generate narration with Gemini using function calling
                        response = await self.agent.generate_from_video(
                            video_input=temp_path,
                            prompt=prompt,
                            tools=[NARRATE_VIDEO_TOOL],
                        )

                        logger.info(
                            f"Narration response (attempt {attempt + 1}): {response}"
                        )

                        # Extract function call response
                        if (
                            isinstance(response, dict)
                            and response.get("name") == "report_video_narration"
                        ):
                            args = response.get("args", {})
                            narration = args.get("narration", "")

                            # Validate that we got narration text
                            if narration:
                                logger.info(f"Generated narration: {narration}")

                                metadata["narration_method"] = "gemini_function_calling"
                                metadata["narration_attempts"] = attempt + 1
                                metadata["narration_text"] = narration

                                return narration, metadata
                            else:
                                # Missing narration, retry
                                logger.warning(
                                    f"Attempt {attempt + 1}: Missing narration text. "
                                    f"Will retry..."
                                )
                                last_error = "Missing narration in function call"
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
                    f"Using fallback narration."
                )
                narration = "Here's the action!"
                metadata["narration_method"] = "retry_exhausted_fallback"
                metadata["narration_attempts"] = max_retries
                metadata["last_error"] = last_error
                return narration, metadata

            finally:
                # Clean up temp file
                try:
                    os.unlink(temp_path)
                except Exception as e:
                    logger.warning(f"Failed to delete temp file {temp_path}: {e}")

        except Exception as e:
            logger.error(f"Error in generate_narration: {e}", exc_info=True)

            # Fallback narration
            narration = "Here's the action!"
            metadata["narration_method"] = "error_fallback"
            metadata["narration_error"] = str(e)

            return narration, metadata


# Global narrator instance (lazily initialized)
_narrator: VideoNarrator | None = None


def _get_narrator() -> VideoNarrator:
    """Get or create the global narrator instance."""
    global _narrator
    if _narrator is None:
        _narrator = VideoNarrator()
    return _narrator


async def narrate_video_step(
    video_data: bytes,
    metadata: dict[str, Any],
    previous_narrations: list[str] | None = None,
) -> tuple[str, dict[str, Any]]:
    """
    Pipeline step that generates narration text for a video clip.

    Uses Gemini LLM to analyze the video and generate brief,
    engaging narration text suitable for text-to-speech conversion.

    Args:
        video_data: Video clip bytes
        metadata: Video metadata
        previous_narrations: List of previous narration texts to avoid repetition

    Returns:
        Tuple of (narration_text, updated_metadata)
    """
    logger.info("Running narrate_video_step with Gemini LLM")
    if previous_narrations:
        logger.info(f"Using {len(previous_narrations)} previous narrations for context")

    narrator = _get_narrator()
    result: tuple[str, dict[str, Any]] = await narrator.generate_narration(
        video_data, metadata, previous_narrations
    )
    return result
