"""
Gemini Agent - Flexible scaffolding for multimodal AI interactions.

This module provides a flexible agent implementation that supports various input
and output modalities (text, image, video, audio) through a hook-based system.
"""

import asyncio
import io
import os
import subprocess
import wave
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Optional, Union
from urllib.request import urlopen

from google import genai
from google.genai import types
from PIL import Image


class ModalityType(Enum):
    """Supported modality types for Gemini agent."""

    TEXT = "text"
    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"


@dataclass
class AgentInput:
    """Container for agent input with modality information."""

    modality: ModalityType
    data: Any  # Can be str, bytes, Path, or any custom type
    metadata: Optional[dict[str, Any]] = None

    def __repr__(self) -> str:
        data_preview = (
            str(self.data)[:50] + "..."
            if isinstance(self.data, str) and len(str(self.data)) > 50
            else self.data
        )
        return f"AgentInput(modality={self.modality}, data={data_preview}, metadata={self.metadata})"


@dataclass
class AgentOutput:
    """Container for agent output with modality information."""

    modality: ModalityType
    data: Any  # Can be str, bytes, or any custom type
    metadata: Optional[dict[str, Any]] = None

    def __repr__(self) -> str:
        data_preview = (
            str(self.data)[:50] + "..."
            if isinstance(self.data, str) and len(str(self.data)) > 50
            else self.data
        )
        return f"AgentOutput(modality={self.modality}, data={data_preview}, metadata={self.metadata})"


class InputHook(ABC):
    """Abstract base class for input processing hooks."""

    @abstractmethod
    def process(self, raw_input: Any) -> AgentInput:
        """
        Process raw input into standardized AgentInput format.

        Args:
            raw_input: Raw input data in any format

        Returns:
            AgentInput: Processed input ready for the agent
        """
        pass

    @abstractmethod
    def supports_modality(self) -> ModalityType:
        """Return the modality type this hook handles."""
        pass


class OutputHook(ABC):
    """Abstract base class for output processing hooks."""

    @abstractmethod
    def process(self, agent_output: AgentOutput) -> Any:
        """
        Process agent output into desired format.

        Args:
            agent_output: Output from the agent

        Returns:
            Any: Processed output in the desired format
        """
        pass

    @abstractmethod
    def supports_modality(self) -> ModalityType:
        """Return the modality type this hook handles."""
        pass


class TextInputHook(InputHook):
    """Hook for processing text input."""

    def process(self, raw_input: str) -> AgentInput:
        """Process text input."""
        return AgentInput(modality=ModalityType.TEXT, data=raw_input)

    def supports_modality(self) -> ModalityType:
        return ModalityType.TEXT


class VideoInputHook(InputHook):
    """Hook for processing video input."""

    def process(self, raw_input: Union[bytes, Path, str]) -> AgentInput:
        """
        Process video input.

        Args:
            raw_input: Can be bytes, file path, or URL

        Returns:
            AgentInput with video data
        """
        metadata = {}
        if isinstance(raw_input, (Path, str)):
            metadata["source"] = str(raw_input)
            # In actual implementation, you might read the file or validate URL
        return AgentInput(
            modality=ModalityType.VIDEO, data=raw_input, metadata=metadata
        )

    def supports_modality(self) -> ModalityType:
        return ModalityType.VIDEO


class AudioInputHook(InputHook):
    """Hook for processing audio input."""

    def process(self, raw_input: Union[bytes, Path, str]) -> AgentInput:
        """
        Process audio input.

        Args:
            raw_input: Can be bytes, file path, or URL

        Returns:
            AgentInput with audio data
        """
        metadata = {}
        if isinstance(raw_input, (Path, str)):
            metadata["source"] = str(raw_input)
        return AgentInput(
            modality=ModalityType.AUDIO, data=raw_input, metadata=metadata
        )

    def supports_modality(self) -> ModalityType:
        return ModalityType.AUDIO


class ImageInputHook(InputHook):
    """Hook for processing image input."""

    def process(self, raw_input: Union[bytes, Path, str]) -> AgentInput:
        """
        Process image input.

        Args:
            raw_input: Can be bytes, file path, or URL

        Returns:
            AgentInput with image data
        """
        metadata = {}
        if isinstance(raw_input, (Path, str)):
            metadata["source"] = str(raw_input)
        return AgentInput(
            modality=ModalityType.IMAGE, data=raw_input, metadata=metadata
        )

    def supports_modality(self) -> ModalityType:
        return ModalityType.IMAGE


class TextOutputHook(OutputHook):
    """Hook for processing text output."""

    def process(self, agent_output: AgentOutput) -> str:
        """Process text output."""
        return str(agent_output.data)

    def supports_modality(self) -> ModalityType:
        return ModalityType.TEXT


class VideoOutputHook(OutputHook):
    """Hook for processing video output."""

    def process(self, agent_output: AgentOutput) -> bytes:
        """
        Process video output.

        Returns:
            bytes: Video data as bytes
        """
        if isinstance(agent_output.data, bytes):
            return agent_output.data
        # In actual implementation, handle different output formats
        return bytes()

    def supports_modality(self) -> ModalityType:
        return ModalityType.VIDEO


class AudioOutputHook(OutputHook):
    """Hook for processing audio output."""

    def process(self, agent_output: AgentOutput) -> bytes:
        """
        Process audio output.

        Returns:
            bytes: Audio data as bytes
        """
        if isinstance(agent_output.data, bytes):
            return agent_output.data
        return bytes()

    def supports_modality(self) -> ModalityType:
        return ModalityType.AUDIO


class ImageOutputHook(OutputHook):
    """Hook for processing image output."""

    def process(self, agent_output: AgentOutput) -> bytes:
        """
        Process image output.

        Returns:
            bytes: Image data as bytes
        """
        if isinstance(agent_output.data, bytes):
            return agent_output.data
        return bytes()

    def supports_modality(self) -> ModalityType:
        return ModalityType.IMAGE


class GeminiAgent:
    """
    Flexible Gemini agent with hook-based input/output processing.

    This agent supports multiple modalities (text, image, video, audio) through
    a hook system that allows customization of input processing and output formatting.
    """

    def __init__(self, api_key: Optional[str] = None, model_name: str = "gemini-pro"):
        """
        Initialize the Gemini agent.

        Args:
            api_key: Google API key for Gemini (optional, can use env var)
            model_name: Name of the Gemini model to use
        """
        self.api_key = api_key or os.getenv("GEMINI_API_KEY")
        self.model_name = model_name
        self.input_hooks: dict[ModalityType, InputHook] = {}
        self.output_hooks: dict[ModalityType, OutputHook] = {}
        self._client = None

        # Configure Gemini API client if key is available
        if self.api_key:
            self._client = genai.Client(api_key=self.api_key)

        # Register default hooks
        self._register_default_hooks()

    def _register_default_hooks(self) -> None:
        """Register default input and output hooks for all modalities."""
        # Input hooks
        self.register_input_hook(TextInputHook())
        self.register_input_hook(VideoInputHook())
        self.register_input_hook(AudioInputHook())
        self.register_input_hook(ImageInputHook())

        # Output hooks
        self.register_output_hook(TextOutputHook())
        self.register_output_hook(VideoOutputHook())
        self.register_output_hook(AudioOutputHook())
        self.register_output_hook(ImageOutputHook())

    def register_input_hook(self, hook: InputHook) -> None:
        """
        Register a custom input hook.

        Args:
            hook: Input hook to register
        """
        self.input_hooks[hook.supports_modality()] = hook

    def register_output_hook(self, hook: OutputHook) -> None:
        """
        Register a custom output hook.

        Args:
            hook: Output hook to register
        """
        self.output_hooks[hook.supports_modality()] = hook

    def process_input(self, raw_input: Any, modality: ModalityType) -> AgentInput:
        """
        Process raw input using the appropriate hook.

        Args:
            raw_input: Raw input data
            modality: Type of modality

        Returns:
            AgentInput: Processed input

        Raises:
            ValueError: If no hook is registered for the modality
        """
        if modality not in self.input_hooks:
            raise ValueError(f"No input hook registered for modality: {modality}")

        hook = self.input_hooks[modality]
        return hook.process(raw_input)

    def process_output(self, agent_output: AgentOutput) -> Any:
        """
        Process agent output using the appropriate hook.

        Args:
            agent_output: Output from the agent

        Returns:
            Any: Processed output

        Raises:
            ValueError: If no hook is registered for the modality
        """
        if agent_output.modality not in self.output_hooks:
            raise ValueError(
                f"No output hook registered for modality: {agent_output.modality}"
            )

        hook = self.output_hooks[agent_output.modality]
        return hook.process(agent_output)

    async def generate(
        self,
        inputs: list[AgentInput],
        output_modality: ModalityType = ModalityType.TEXT,
        tools: Optional[list[Any]] = None,
        **generation_config: Any,
    ) -> AgentOutput:
        """
        Generate output from inputs using the Gemini model.

        Args:
            inputs: List of processed inputs
            output_modality: Desired output modality
            tools: Optional list of tool/function declarations for function calling
            **generation_config: Additional generation configuration

        Returns:
            AgentOutput: Generated output (may contain function call)

        Raises:
            ValueError: If client is not initialized or input modality is unsupported
        """
        if not self._client:
            raise ValueError("Client not initialized. Please provide an API key.")

        # Build content list for Gemini using new SDK
        content_parts = []

        try:
            for agent_input in inputs:
                if agent_input.modality == ModalityType.TEXT:
                    content_parts.append(agent_input.data)
                elif agent_input.modality == ModalityType.IMAGE:
                    # Handle image input
                    if isinstance(agent_input.data, bytes):
                        # Use Part.from_bytes for image bytes
                        content_parts.append(
                            types.Part.from_bytes(
                                data=agent_input.data,
                                mime_type="image/jpeg",  # Default to JPEG
                            )
                        )
                    elif isinstance(agent_input.data, (str, Path)):
                        data_str = str(agent_input.data)
                        if data_str.startswith(("http://", "https://")):
                            # Load image from URL and use bytes
                            with urlopen(data_str) as response:
                                image_data = response.read()
                            content_parts.append(
                                types.Part.from_bytes(
                                    data=image_data, mime_type="image/jpeg"
                                )
                            )
                        else:
                            # Load from local file
                            with open(data_str, "rb") as f:
                                image_data = f.read()
                            # Determine mime type from extension
                            if data_str.lower().endswith(".png"):
                                mime_type = "image/png"
                            elif data_str.lower().endswith(
                                ".jpg"
                            ) or data_str.lower().endswith(".jpeg"):
                                mime_type = "image/jpeg"
                            else:
                                mime_type = "image/jpeg"
                            content_parts.append(
                                types.Part.from_bytes(
                                    data=image_data, mime_type=mime_type
                                )
                            )
                elif agent_input.modality in (ModalityType.VIDEO, ModalityType.AUDIO):
                    # For video/audio, use Part.from_bytes
                    file_bytes = None
                    mime_type = None

                    if isinstance(agent_input.data, bytes):
                        # Already bytes
                        file_bytes = agent_input.data
                        mime_type = (
                            "video/mp4"
                            if agent_input.modality == ModalityType.VIDEO
                            else "audio/mpeg"
                        )
                    elif isinstance(agent_input.data, (str, Path)):
                        # Read file from path
                        file_path = str(agent_input.data)
                        with open(file_path, "rb") as f:
                            file_bytes = f.read()

                        # Determine MIME type from extension
                        if file_path.endswith((".mp4", ".MP4")):
                            mime_type = "video/mp4"
                        elif file_path.endswith((".mp3", ".MP3")):
                            mime_type = "audio/mpeg"
                        elif file_path.endswith((".wav", ".WAV")):
                            mime_type = "audio/wav"
                        elif file_path.endswith((".ogg", ".OGG")):
                            mime_type = "audio/ogg"

                    # Create Part using from_bytes
                    if file_bytes and mime_type:
                        content_parts.append(
                            types.Part.from_bytes(data=file_bytes, mime_type=mime_type)
                        )

            # Build generation config dict for new SDK
            gen_config = {}
            if generation_config:
                # Map common config parameters
                if "temperature" in generation_config:
                    gen_config["temperature"] = generation_config["temperature"]
                if "max_output_tokens" in generation_config:
                    gen_config["max_output_tokens"] = generation_config[
                        "max_output_tokens"
                    ]
                if "top_p" in generation_config:
                    gen_config["top_p"] = generation_config["top_p"]
                if "top_k" in generation_config:
                    gen_config["top_k"] = generation_config["top_k"]

            # Add tools to config if provided
            if tools:
                gen_config["tools"] = tools

            # Prepare generation arguments
            generate_kwargs: dict[str, Any] = {
                "model": self.model_name,
                "contents": content_parts,
            }

            if gen_config:
                generate_kwargs["config"] = types.GenerateContentConfig(**gen_config)

            # Generate content using new SDK
            response = await self._client.aio.models.generate_content(**generate_kwargs)  # type: ignore[arg-type]

            # Check if response contains function calls
            if hasattr(response, "candidates") and response.candidates:
                candidate = response.candidates[0]
                if (
                    hasattr(candidate, "content")
                    and candidate.content
                    and hasattr(candidate.content, "parts")
                    and candidate.content.parts
                ):
                    for part in candidate.content.parts:
                        # Skip thinking parts (thought=True) - only process actual content
                        if hasattr(part, "thought") and part.thought:
                            continue

                        if hasattr(part, "function_call") and part.function_call:
                            # Return function call data
                            function_call = part.function_call
                            return AgentOutput(
                                modality=output_modality,
                                data={
                                    "name": function_call.name,
                                    "args": dict(function_call.args)
                                    if function_call.args
                                    else {},
                                },
                                metadata={
                                    "inputs": len(inputs),
                                    "config": generation_config,
                                    "model": self.model_name,
                                    "type": "function_call",
                                },
                            )

            # Handle different output modalities
            if output_modality == ModalityType.TEXT:
                # Extract text from response
                response_text = response.text
                return AgentOutput(
                    modality=output_modality,
                    data=response_text,
                    metadata={
                        "inputs": len(inputs),
                        "config": generation_config,
                        "model": self.model_name,
                        "type": "text",
                    },
                )
            elif output_modality == ModalityType.AUDIO:
                # For audio output, extract from inline_data if available
                if hasattr(response, "candidates") and response.candidates:
                    candidate = response.candidates[0]
                    if (
                        hasattr(candidate, "content")
                        and candidate.content
                        and hasattr(candidate.content, "parts")
                        and candidate.content.parts
                    ):
                        for part in candidate.content.parts:
                            if hasattr(part, "inline_data") and part.inline_data:
                                return AgentOutput(
                                    modality=output_modality,
                                    data=part.inline_data.data,
                                    metadata={
                                        "inputs": len(inputs),
                                        "config": generation_config,
                                        "model": self.model_name,
                                        "type": "audio",
                                        "mime_type": part.inline_data.mime_type,
                                    },
                                )
                # Fallback to empty audio if no inline_data
                return AgentOutput(
                    modality=output_modality,
                    data=b"",
                    metadata={
                        "inputs": len(inputs),
                        "config": generation_config,
                        "model": self.model_name,
                        "type": "audio",
                    },
                )
            else:
                # For other modalities, try to extract text as fallback
                return AgentOutput(
                    modality=output_modality,
                    data=response.text if hasattr(response, "text") else "",
                    metadata={
                        "inputs": len(inputs),
                        "config": generation_config,
                        "model": self.model_name,
                        "type": "other",
                    },
                )
        except Exception as e:
            raise ValueError(f"Failed to generate content: {str(e)}")

    async def generate_text(
        self, prompt: str, context_inputs: Optional[list[AgentInput]] = None
    ) -> str:
        """
        Convenience method for text generation.

        Args:
            prompt: Text prompt
            context_inputs: Optional additional context (images, videos, etc.)

        Returns:
            str: Generated text response
        """
        inputs = [self.process_input(prompt, ModalityType.TEXT)]
        if context_inputs:
            inputs.extend(context_inputs)

        output = await self.generate(inputs, output_modality=ModalityType.TEXT)
        result = self.process_output(output)
        assert isinstance(result, str)
        return result

    async def generate_from_video(
        self,
        video_input: Union[bytes, Path, str],
        prompt: str,
        tools: Optional[list[Any]] = None,
    ) -> Union[str, dict[str, Any]]:
        """
        Convenience method for video understanding.

        Args:
            video_input: Video data (bytes, path, or URL)
            prompt: Question or instruction about the video
            tools: Optional list of tool/function declarations for function calling

        Returns:
            str or dict: Generated text response, or function call data if tools provided
        """
        inputs = [
            self.process_input(video_input, ModalityType.VIDEO),
            self.process_input(prompt, ModalityType.TEXT),
        ]

        output = await self.generate(
            inputs, output_modality=ModalityType.TEXT, tools=tools
        )

        # If it's a function call, return the function call data directly
        if output.metadata and output.metadata.get("type") == "function_call":
            assert isinstance(output.data, dict)
            return output.data

        # Otherwise, return text
        result = self.process_output(output)
        assert isinstance(result, str)
        return result

    async def generate_from_audio(
        self, audio_input: Union[bytes, Path, str], prompt: str
    ) -> str:
        """
        Convenience method for audio understanding.

        Args:
            audio_input: Audio data (bytes, path, or URL)
            prompt: Question or instruction about the audio

        Returns:
            str: Generated text response
        """
        inputs = [
            self.process_input(audio_input, ModalityType.AUDIO),
            self.process_input(prompt, ModalityType.TEXT),
        ]

        output = await self.generate(inputs, output_modality=ModalityType.TEXT)
        result = self.process_output(output)
        assert isinstance(result, str)
        return result

    async def generate_multimodal(
        self,
        text_prompts: list[str],
        images: Optional[list[Union[bytes, Path, str]]] = None,
        videos: Optional[list[Union[bytes, Path, str]]] = None,
        audios: Optional[list[Union[bytes, Path, str]]] = None,
        output_modality: ModalityType = ModalityType.TEXT,
    ) -> Any:
        """
        Convenience method for multimodal generation.

        Args:
            text_prompts: List of text prompts
            images: Optional list of images
            videos: Optional list of videos
            audios: Optional list of audio files
            output_modality: Desired output modality

        Returns:
            Any: Generated output (processed through output hook)
        """
        inputs: list[AgentInput] = []

        # Process all text prompts
        for prompt in text_prompts:
            inputs.append(self.process_input(prompt, ModalityType.TEXT))

        # Process images
        if images:
            for img in images:
                inputs.append(self.process_input(img, ModalityType.IMAGE))

        # Process videos
        if videos:
            for vid in videos:
                inputs.append(self.process_input(vid, ModalityType.VIDEO))

        # Process audio
        if audios:
            for aud in audios:
                inputs.append(self.process_input(aud, ModalityType.AUDIO))

        output = await self.generate(inputs, output_modality=output_modality)
        return self.process_output(output)


class GeminiLiveClient:
    """
    Live API client for real-time audio streaming with Gemini.

    This client supports bidirectional streaming with video input and audio output,
    designed for live commentary scenarios. Uses the gemini-2.5-flash-native-audio-preview
    model for high-quality audio generation.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: str = "gemini-live-2.5-flash-preview",
        system_instruction: Optional[str] = None,
    ):
        """
        Initialize the Live API client.

        Args:
            api_key: Google API key for Gemini (optional, can use env var)
            model_name: Name of the Gemini model to use (default: gemini-live-2.5-flash-preview)
            system_instruction: Optional system instruction for the model behavior
        """
        self.api_key = api_key or os.getenv("GEMINI_API_KEY")
        self.model_name = model_name
        self.system_instruction = (
            system_instruction
            or "You are a helpful sports commentator providing live audio commentary."
        )
        self._client: Optional[genai.Client] = None
        self._session: Any = None
        self._connection_context: Optional[AbstractAsyncContextManager[Any]] = None

        if self.api_key:
            self._client = genai.Client(api_key=self.api_key)

    async def connect(
        self,
        response_modalities: Optional[list[str]] = None,
        **config_kwargs: Any,
    ) -> "GeminiLiveClient":
        """
        Establish WebSocket connection to the Live API.

        Args:
            response_modalities: List of desired output modalities (default: ["AUDIO"])
            **config_kwargs: Additional configuration parameters

        Returns:
            Self for context manager usage

        Raises:
            ValueError: If client is not initialized
        """
        if not self._client:
            raise ValueError("Client not initialized. Please provide an API key.")

        # Build configuration using types.LiveConnectConfig
        # Convert string modalities to types.Modality enum values
        modalities_list = response_modalities or ["AUDIO"]
        modality_objects = [getattr(types.Modality, m) for m in modalities_list]

        config = types.LiveConnectConfig(
            response_modalities=modality_objects,
            system_instruction=self.system_instruction,
            **config_kwargs,
        )

        # Store the connection context manager and enter it
        self._connection_context = self._client.aio.live.connect(
            model=self.model_name, config=config
        )
        self._session = await self._connection_context.__aenter__()

        return self

    async def disconnect(self) -> None:
        """Close the WebSocket connection."""
        if self._connection_context and self._session:
            await self._connection_context.__aexit__(None, None, None)
            self._session = None
            self._connection_context = None

    async def __aenter__(self) -> "GeminiLiveClient":
        """Context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """Context manager exit."""
        await self.disconnect()

    async def send_video_frame(
        self, frame_image: Union[Image.Image, bytes], mime_type: str = "image/jpeg"
    ) -> None:
        """
        Send video frame as an image to the model.

        Args:
            frame_image: PIL Image or image bytes
            mime_type: MIME type of the image data (default: image/jpeg)

        Raises:
            ValueError: If session is not connected
        """
        if not self._session:
            raise ValueError("Session not connected. Call connect() first.")

        # If bytes, convert to PIL Image
        if isinstance(frame_image, bytes):
            frame_image = Image.open(io.BytesIO(frame_image))

        # Send as image (video parameter accepts PIL.Image)
        await self._session.send_realtime_input(video=frame_image)

    async def send_audio_chunk(
        self, audio_data: bytes, sample_rate: int = 16000
    ) -> None:
        """
        Send audio chunk to the model.

        Args:
            audio_data: Audio bytes in 16-bit PCM format
            sample_rate: Sample rate in Hz (default: 16000)

        Raises:
            ValueError: If session is not connected
        """
        if not self._session:
            raise ValueError("Session not connected. Call connect() first.")

        await self._session.send_realtime_input(
            audio=types.Blob(data=audio_data, mime_type=f"audio/pcm;rate={sample_rate}")
        )

    async def send_text(self, text: str) -> None:
        """
        Send text input to the model.

        Args:
            text: Text prompt or instruction

        Raises:
            ValueError: If session is not connected
        """
        if not self._session:
            raise ValueError("Session not connected. Call connect() first.")

        await self._session.send_realtime_input(text=text)

    async def receive_audio_stream(self) -> AsyncIterator[bytes]:
        """
        Receive streaming audio output from the model.

        Yields:
            bytes: Audio data chunks in 16-bit PCM format at 24kHz

        Raises:
            ValueError: If session is not connected
        """
        if not self._session:
            raise ValueError("Session not connected. Call connect() first.")

        async for response in self._session.receive():
            # Check if response has data attribute directly
            if hasattr(response, "data") and response.data is not None:
                yield response.data
            # Also check for server_content structure
            elif hasattr(response, "server_content"):
                server_content = response.server_content
                if hasattr(server_content, "model_turn"):
                    model_turn = server_content.model_turn
                    if hasattr(model_turn, "parts"):
                        for part in model_turn.parts:
                            if hasattr(part, "inline_data") and part.inline_data:
                                # Yield the audio data
                                yield part.inline_data.data

    def _extract_frames_from_video(
        self, video_path: Union[str, Path], fps: float = 1.0
    ) -> list[Image.Image]:
        """
        Extract frames from video file using ffmpeg.

        Args:
            video_path: Path to video file
            fps: Frames per second to extract (default: 1.0 to match Live API processing)

        Returns:
            list[Image.Image]: List of PIL Images representing frames

        Raises:
            FileNotFoundError: If video file does not exist
            RuntimeError: If ffmpeg fails to extract frames
        """
        import tempfile

        video_path_obj = Path(video_path)

        # Check if file exists
        if not video_path_obj.exists():
            raise FileNotFoundError(f"Video file not found: {video_path}")

        video_path = str(video_path)
        frames = []

        # Create temporary directory for frames
        with tempfile.TemporaryDirectory() as tmpdir:
            output_pattern = os.path.join(tmpdir, "frame_%04d.jpg")

            # Use ffmpeg to extract frames
            cmd = [
                "ffmpeg",
                "-i",
                video_path,
                "-vf",
                f"fps={fps}",
                "-q:v",
                "2",  # High quality JPEG
                output_pattern,
            ]

            try:
                subprocess.run(cmd, capture_output=True, text=True, check=True)
            except subprocess.CalledProcessError as e:
                raise RuntimeError(f"Failed to extract frames: {e.stderr}")

            # Load extracted frames
            frame_files = sorted(Path(tmpdir).glob("frame_*.jpg"))
            for frame_file in frame_files:
                frames.append(Image.open(frame_file))

        return frames

    async def stream_video_with_audio_output(
        self,
        video_source: Union[str, Path, AsyncIterator[Image.Image]],
        on_audio_chunk: Optional[Callable[[bytes], None]] = None,
        prompt: Optional[str] = None,
        fps: float = 1.0,
    ) -> bytes:
        """
        Stream video input and receive audio commentary output.

        Args:
            video_source: Path to video file or async iterator of frame images
            on_audio_chunk: Optional callback for each audio chunk received
            prompt: Optional text prompt to guide the commentary
            fps: Frames per second to extract from video (default: 1.0)

        Returns:
            bytes: Complete audio output as WAV file bytes

        Raises:
            ValueError: If session is not connected
        """
        if not self._session:
            raise ValueError("Session not connected. Call connect() first.")

        # Send initial prompt if provided
        if prompt:
            await self.send_text(prompt)

        # Handle video source
        if isinstance(video_source, (str, Path)):
            # Extract frames from video file
            frames = self._extract_frames_from_video(video_source, fps=fps)

            # Send each frame
            for frame in frames:
                await self.send_video_frame(frame)
                # Small delay between frames to avoid overwhelming the API
                await asyncio.sleep(0.1)
        else:
            # Stream frame images
            async for frame in video_source:
                await self.send_video_frame(frame)
                await asyncio.sleep(0.1)

        # Collect audio output
        audio_chunks = []
        async for audio_chunk in self.receive_audio_stream():
            audio_chunks.append(audio_chunk)
            if on_audio_chunk:
                on_audio_chunk(audio_chunk)

        # Convert to WAV format
        return self._create_wav_from_pcm(b"".join(audio_chunks))

    def _create_wav_from_pcm(
        self, pcm_data: bytes, sample_rate: int = 24000, channels: int = 1
    ) -> bytes:
        """
        Convert raw PCM audio to WAV format.

        Args:
            pcm_data: Raw PCM audio bytes
            sample_rate: Sample rate in Hz (default: 24000 for output)
            channels: Number of audio channels (default: 1 for mono)

        Returns:
            bytes: WAV file bytes
        """
        wav_buffer = io.BytesIO()
        with wave.open(wav_buffer, "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_data)

        wav_buffer.seek(0)
        return wav_buffer.read()

    async def generate_audio_from_video(
        self, video_path: Union[str, Path], prompt: str
    ) -> bytes:
        """
        Convenience method to generate audio commentary from a video file.

        Args:
            video_path: Path to the video file
            prompt: Text prompt describing what kind of commentary to generate

        Returns:
            bytes: WAV audio file bytes

        Raises:
            ValueError: If session is not connected
        """
        if not self._session:
            raise ValueError("Session not connected. Call connect() first.")

        return await self.stream_video_with_audio_output(
            video_source=video_path, prompt=prompt
        )
