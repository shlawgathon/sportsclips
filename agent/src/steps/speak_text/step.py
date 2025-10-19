"""
Text-to-speech step using Gemini Live API.

This module provides a pipeline step that converts text narration to speech
using the Gemini Live API, which produces natural-sounding audio.
"""

import logging
from typing import Any

from ...llm import GeminiLiveClient

logger = logging.getLogger(__name__)


class TextSpeaker:
    """Converts text to speech using Gemini Live API."""

    def __init__(self, system_instruction: str | None = None):
        """
        Initialize the text speaker.

        Args:
            system_instruction: Optional system instruction for the Live API
        """
        self.system_instruction = system_instruction or (
            "You are a sports commentator. When given text, speak it naturally "
            "and enthusiastically as if you're providing live sports commentary."
        )

    async def speak_text(
        self, text: str, metadata: dict[str, Any]
    ) -> tuple[bytes, dict[str, Any]]:
        """
        Convert text to speech using Gemini Live API.

        Args:
            text: Text to convert to speech
            metadata: Video metadata

        Returns:
            Tuple of (audio_pcm_bytes, updated_metadata)
        """
        live_client = None
        try:
            logger.info(f"Converting text to speech: '{text}'")

            # Create and connect to Live API
            live_client = GeminiLiveClient(system_instruction=self.system_instruction)
            await live_client.connect()
            logger.info("Connected to Gemini Live API for text-to-speech")

            # Send the text prompt asking the model to speak it
            prompt = f"Please speak the following text naturally: {text}"
            await live_client.send(prompt, end_of_turn=True)
            logger.info("Sent text to Live API, waiting for audio response...")

            # Collect audio response
            audio_chunks: list[bytes] = []
            async for audio_chunk in live_client.receive_audio_chunks():
                audio_chunks.append(audio_chunk)
                # Limit collection for reasonable speech duration (3-12 words ~2-3 seconds)
                if len(audio_chunks) >= 60:
                    break

            audio_pcm = b"".join(audio_chunks)
            logger.info(
                f"Collected {len(audio_chunks)} audio chunks ({len(audio_pcm):,} bytes)"
            )

            if not audio_pcm:
                logger.warning("No audio generated from Live API")
                metadata["speech_method"] = "failed_no_audio"
                return b"", metadata

            metadata["speech_method"] = "gemini_live_api"
            metadata["audio_chunks_count"] = len(audio_chunks)
            metadata["audio_bytes"] = len(audio_pcm)

            return audio_pcm, metadata

        except Exception as e:
            logger.error(f"Error in speak_text: {e}", exc_info=True)
            metadata["speech_method"] = "error"
            metadata["speech_error"] = str(e)
            return b"", metadata

        finally:
            # Clean up Live API connection
            if live_client:
                try:
                    await live_client.disconnect()
                    logger.info("Disconnected from Live API")
                except Exception as e:
                    logger.error(f"Error disconnecting from Live API: {e}")


async def speak_text_step(
    text: str, metadata: dict[str, Any], system_instruction: str | None = None
) -> tuple[bytes, dict[str, Any]]:
    """
    Pipeline step that converts text to speech using Gemini Live API.

    Args:
        text: Text to convert to speech
        metadata: Video metadata
        system_instruction: Optional system instruction for the Live API

    Returns:
        Tuple of (audio_pcm_bytes, updated_metadata)
    """
    logger.info("Running speak_text_step with Gemini Live API")

    speaker = TextSpeaker(system_instruction=system_instruction)
    result: tuple[bytes, dict[str, Any]] = await speaker.speak_text(text, metadata)
    return result
