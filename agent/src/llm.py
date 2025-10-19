"""
Gemini Agent - Flexible scaffolding for multimodal AI interactions.

This module provides a flexible agent implementation that supports various input
and output modalities (text, image, video, audio) through a hook-based system.
"""

import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Optional, Union
from urllib.request import urlopen

from google import genai
from google.genai import types


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

            # Prepare generation arguments
            generate_kwargs: dict[str, Any] = {
                "model": self.model_name,
                "contents": content_parts,
            }

            if gen_config:
                generate_kwargs["config"] = types.GenerateContentConfig(**gen_config)

            if tools:
                generate_kwargs["tools"] = tools

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
