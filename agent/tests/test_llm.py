"""
Tests for the Gemini Agent scaffolding.

These tests verify the hook system and agent structure without requiring
actual Gemini API calls.
"""

import pytest

from src.llm import (
    AgentInput,
    AgentOutput,
    AudioInputHook,
    AudioOutputHook,
    GeminiAgent,
    ImageInputHook,
    ImageOutputHook,
    InputHook,
    ModalityType,
    OutputHook,
    TextInputHook,
    TextOutputHook,
    VideoInputHook,
    VideoOutputHook,
)


class TestModalityType:
    """Test ModalityType enum."""

    def test_modality_types_exist(self):
        """Test that all expected modality types are defined."""
        assert ModalityType.TEXT.value == "text"
        assert ModalityType.IMAGE.value == "image"
        assert ModalityType.VIDEO.value == "video"
        assert ModalityType.AUDIO.value == "audio"


class TestAgentInput:
    """Test AgentInput dataclass."""

    def test_create_agent_input(self):
        """Test creating an AgentInput instance."""
        input_data = AgentInput(
            modality=ModalityType.TEXT, data="Hello, world!", metadata={"lang": "en"}
        )

        assert input_data.modality == ModalityType.TEXT
        assert input_data.data == "Hello, world!"
        assert input_data.metadata == {"lang": "en"}

    def test_agent_input_without_metadata(self):
        """Test creating an AgentInput without metadata."""
        input_data = AgentInput(modality=ModalityType.VIDEO, data=b"video bytes")

        assert input_data.modality == ModalityType.VIDEO
        assert input_data.data == b"video bytes"
        assert input_data.metadata is None


class TestAgentOutput:
    """Test AgentOutput dataclass."""

    def test_create_agent_output(self):
        """Test creating an AgentOutput instance."""
        output_data = AgentOutput(
            modality=ModalityType.TEXT,
            data="Generated response",
            metadata={"model": "gemini-pro"},
        )

        assert output_data.modality == ModalityType.TEXT
        assert output_data.data == "Generated response"
        assert output_data.metadata == {"model": "gemini-pro"}


class TestInputHooks:
    """Test input hook implementations."""

    def test_text_input_hook(self):
        """Test TextInputHook processing."""
        hook = TextInputHook()
        assert hook.supports_modality() == ModalityType.TEXT

        result = hook.process("Test text")
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.TEXT
        assert result.data == "Test text"

    def test_video_input_hook_with_path(self):
        """Test VideoInputHook with file path."""
        hook = VideoInputHook()
        assert hook.supports_modality() == ModalityType.VIDEO

        result = hook.process("/path/to/video.mp4")
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.VIDEO
        assert result.data == "/path/to/video.mp4"
        assert result.metadata is not None
        assert "source" in result.metadata

    def test_video_input_hook_with_bytes(self):
        """Test VideoInputHook with bytes."""
        hook = VideoInputHook()
        video_bytes = b"fake video data"

        result = hook.process(video_bytes)
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.VIDEO
        assert result.data == video_bytes

    def test_audio_input_hook(self):
        """Test AudioInputHook processing."""
        hook = AudioInputHook()
        assert hook.supports_modality() == ModalityType.AUDIO

        result = hook.process("/path/to/audio.mp3")
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.AUDIO
        assert result.data == "/path/to/audio.mp3"

    def test_image_input_hook(self):
        """Test ImageInputHook processing."""
        hook = ImageInputHook()
        assert hook.supports_modality() == ModalityType.IMAGE

        result = hook.process("/path/to/image.jpg")
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.IMAGE
        assert result.data == "/path/to/image.jpg"


class TestOutputHooks:
    """Test output hook implementations."""

    def test_text_output_hook(self):
        """Test TextOutputHook processing."""
        hook = TextOutputHook()
        assert hook.supports_modality() == ModalityType.TEXT

        output = AgentOutput(modality=ModalityType.TEXT, data="Response text")
        result = hook.process(output)
        assert isinstance(result, str)
        assert result == "Response text"

    def test_video_output_hook(self):
        """Test VideoOutputHook processing."""
        hook = VideoOutputHook()
        assert hook.supports_modality() == ModalityType.VIDEO

        video_bytes = b"video output data"
        output = AgentOutput(modality=ModalityType.VIDEO, data=video_bytes)
        result = hook.process(output)
        assert isinstance(result, bytes)
        assert result == video_bytes

    def test_audio_output_hook(self):
        """Test AudioOutputHook processing."""
        hook = AudioOutputHook()
        assert hook.supports_modality() == ModalityType.AUDIO

        audio_bytes = b"audio output data"
        output = AgentOutput(modality=ModalityType.AUDIO, data=audio_bytes)
        result = hook.process(output)
        assert isinstance(result, bytes)
        assert result == audio_bytes

    def test_image_output_hook(self):
        """Test ImageOutputHook processing."""
        hook = ImageOutputHook()
        assert hook.supports_modality() == ModalityType.IMAGE

        image_bytes = b"image output data"
        output = AgentOutput(modality=ModalityType.IMAGE, data=image_bytes)
        result = hook.process(output)
        assert isinstance(result, bytes)
        assert result == image_bytes


class TestGeminiAgent:
    """Test GeminiAgent class."""

    def test_agent_initialization(self):
        """Test creating a GeminiAgent instance."""
        agent = GeminiAgent(api_key="test-key", model_name="gemini-pro")

        assert agent.api_key == "test-key"
        assert agent.model_name == "gemini-pro"
        assert len(agent.input_hooks) == 4  # text, video, audio, image
        assert len(agent.output_hooks) == 4  # text, video, audio, image

    def test_agent_default_hooks_registered(self):
        """Test that default hooks are registered."""
        agent = GeminiAgent()

        assert ModalityType.TEXT in agent.input_hooks
        assert ModalityType.VIDEO in agent.input_hooks
        assert ModalityType.AUDIO in agent.input_hooks
        assert ModalityType.IMAGE in agent.input_hooks

        assert ModalityType.TEXT in agent.output_hooks
        assert ModalityType.VIDEO in agent.output_hooks
        assert ModalityType.AUDIO in agent.output_hooks
        assert ModalityType.IMAGE in agent.output_hooks

    def test_register_custom_input_hook(self):
        """Test registering a custom input hook."""
        agent = GeminiAgent()

        class CustomTextHook(InputHook):
            def process(self, raw_input):
                return AgentInput(
                    modality=ModalityType.TEXT,
                    data=raw_input.upper(),  # Custom processing
                    metadata={"custom": True},
                )

            def supports_modality(self):
                return ModalityType.TEXT

        custom_hook = CustomTextHook()
        agent.register_input_hook(custom_hook)

        # Verify the custom hook is registered
        assert agent.input_hooks[ModalityType.TEXT] is custom_hook

    def test_register_custom_output_hook(self):
        """Test registering a custom output hook."""
        agent = GeminiAgent()

        class CustomTextOutputHook(OutputHook):
            def process(self, agent_output):
                return f"CUSTOM: {agent_output.data}"

            def supports_modality(self):
                return ModalityType.TEXT

        custom_hook = CustomTextOutputHook()
        agent.register_output_hook(custom_hook)

        # Verify the custom hook is registered
        assert agent.output_hooks[ModalityType.TEXT] is custom_hook

    def test_process_input_text(self):
        """Test processing text input."""
        agent = GeminiAgent()

        result = agent.process_input("Hello, AI!", ModalityType.TEXT)

        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.TEXT
        assert result.data == "Hello, AI!"

    def test_process_input_video(self):
        """Test processing video input."""
        agent = GeminiAgent()

        result = agent.process_input("/path/to/video.mp4", ModalityType.VIDEO)

        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.VIDEO
        assert result.data == "/path/to/video.mp4"

    def test_process_input_unsupported_modality(self):
        """Test processing input with unregistered modality."""
        agent = GeminiAgent()
        agent.input_hooks.clear()  # Remove all hooks

        with pytest.raises(ValueError, match="No input hook registered"):
            agent.process_input("data", ModalityType.TEXT)

    def test_process_output_text(self):
        """Test processing text output."""
        agent = GeminiAgent()

        output = AgentOutput(modality=ModalityType.TEXT, data="Generated text")
        result = agent.process_output(output)

        assert isinstance(result, str)
        assert result == "Generated text"

    def test_process_output_unsupported_modality(self):
        """Test processing output with unregistered modality."""
        agent = GeminiAgent()
        agent.output_hooks.clear()  # Remove all hooks

        output = AgentOutput(modality=ModalityType.TEXT, data="test")

        with pytest.raises(ValueError, match="No output hook registered"):
            agent.process_output(output)

    @pytest.mark.asyncio
    async def test_generate_placeholder(self):
        """Test generate method (placeholder implementation)."""
        agent = GeminiAgent()

        text_input = agent.process_input("Test prompt", ModalityType.TEXT)
        result = await agent.generate([text_input])

        assert isinstance(result, AgentOutput)
        assert result.modality == ModalityType.TEXT

    @pytest.mark.asyncio
    async def test_generate_text_convenience(self):
        """Test generate_text convenience method."""
        agent = GeminiAgent()

        result = await agent.generate_text("What is AI?")

        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_from_video_convenience(self):
        """Test generate_from_video convenience method."""
        agent = GeminiAgent()

        result = await agent.generate_from_video(
            "/path/to/video.mp4", "Describe this video"
        )

        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_from_audio_convenience(self):
        """Test generate_from_audio convenience method."""
        agent = GeminiAgent()

        result = await agent.generate_from_audio(
            "/path/to/audio.mp3", "Transcribe this"
        )

        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_multimodal(self):
        """Test generate_multimodal convenience method."""
        agent = GeminiAgent()

        result = await agent.generate_multimodal(
            text_prompts=["Analyze these"],
            images=["/path/to/img1.jpg", "/path/to/img2.jpg"],
            videos=["/path/to/video.mp4"],
            audios=["/path/to/audio.mp3"],
        )

        assert isinstance(result, str)


class TestCustomHooks:
    """Test custom hook implementations."""

    def test_custom_preprocessing_hook(self):
        """Test custom input hook with preprocessing."""

        class UppercaseTextHook(InputHook):
            """Hook that uppercases text input."""

            def process(self, raw_input):
                return AgentInput(
                    modality=ModalityType.TEXT,
                    data=raw_input.upper(),
                    metadata={"preprocessed": "uppercase"},
                )

            def supports_modality(self):
                return ModalityType.TEXT

        agent = GeminiAgent()
        agent.register_input_hook(UppercaseTextHook())

        result = agent.process_input("hello world", ModalityType.TEXT)

        assert result.data == "HELLO WORLD"
        assert result.metadata["preprocessed"] == "uppercase"

    def test_custom_postprocessing_hook(self):
        """Test custom output hook with postprocessing."""

        class MarkdownOutputHook(OutputHook):
            """Hook that formats output as markdown."""

            def process(self, agent_output):
                return f"# Response\n\n{agent_output.data}"

            def supports_modality(self):
                return ModalityType.TEXT

        agent = GeminiAgent()
        agent.register_output_hook(MarkdownOutputHook())

        output = AgentOutput(modality=ModalityType.TEXT, data="Simple text")
        result = agent.process_output(output)

        assert result.startswith("# Response")
        assert "Simple text" in result


class TestAgentInputOutputRepr:
    """Test __repr__ methods for AgentInput and AgentOutput."""

    def test_agent_input_repr_short_text(self):
        """Test AgentInput repr with short text."""
        input_data = AgentInput(modality=ModalityType.TEXT, data="Short text")
        repr_str = repr(input_data)
        assert "AgentInput" in repr_str
        assert "Short text" in repr_str
        assert "TEXT" in repr_str

    def test_agent_input_repr_long_text(self):
        """Test AgentInput repr truncates long text."""
        long_text = "x" * 100
        input_data = AgentInput(modality=ModalityType.TEXT, data=long_text)
        repr_str = repr(input_data)
        assert "..." in repr_str
        # Should not contain the full text
        assert long_text not in repr_str

    def test_agent_output_repr_short_text(self):
        """Test AgentOutput repr with short text."""
        output_data = AgentOutput(modality=ModalityType.TEXT, data="Short output")
        repr_str = repr(output_data)
        assert "AgentOutput" in repr_str
        assert "Short output" in repr_str

    def test_agent_output_repr_long_text(self):
        """Test AgentOutput repr truncates long text."""
        long_text = "y" * 100
        output_data = AgentOutput(modality=ModalityType.TEXT, data=long_text)
        repr_str = repr(output_data)
        assert "..." in repr_str


class TestInputHookEdgeCases:
    """Test edge cases for input hooks."""

    def test_audio_input_hook_with_bytes(self):
        """Test AudioInputHook with raw bytes."""
        hook = AudioInputHook()
        audio_bytes = b"fake audio data"

        result = hook.process(audio_bytes)
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.AUDIO
        assert result.data == audio_bytes
        # Should not have metadata for bytes
        assert result.metadata == {}

    def test_image_input_hook_with_bytes(self):
        """Test ImageInputHook with raw bytes."""
        hook = ImageInputHook()
        image_bytes = b"fake image data"

        result = hook.process(image_bytes)
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.IMAGE
        assert result.data == image_bytes
        assert result.metadata == {}

    def test_video_input_hook_with_path_object(self):
        """Test VideoInputHook with Path object."""
        from pathlib import Path

        hook = VideoInputHook()
        video_path = Path("/path/to/video.mp4")

        result = hook.process(video_path)
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.VIDEO
        assert result.data == video_path
        assert "source" in result.metadata
        assert result.metadata["source"] == str(video_path)

    def test_audio_input_hook_with_path_object(self):
        """Test AudioInputHook with Path object."""
        from pathlib import Path

        hook = AudioInputHook()
        audio_path = Path("/path/to/audio.mp3")

        result = hook.process(audio_path)
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.AUDIO
        assert "source" in result.metadata

    def test_image_input_hook_with_path_object(self):
        """Test ImageInputHook with Path object."""
        from pathlib import Path

        hook = ImageInputHook()
        image_path = Path("/path/to/image.jpg")

        result = hook.process(image_path)
        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.IMAGE
        assert "source" in result.metadata


class TestOutputHookEdgeCases:
    """Test edge cases for output hooks."""

    def test_video_output_hook_with_non_bytes(self):
        """Test VideoOutputHook with non-bytes data returns empty bytes."""
        hook = VideoOutputHook()
        output = AgentOutput(modality=ModalityType.VIDEO, data="not bytes")

        result = hook.process(output)
        assert isinstance(result, bytes)
        assert result == b""

    def test_audio_output_hook_with_non_bytes(self):
        """Test AudioOutputHook with non-bytes data returns empty bytes."""
        hook = AudioOutputHook()
        output = AgentOutput(modality=ModalityType.AUDIO, data="not bytes")

        result = hook.process(output)
        assert isinstance(result, bytes)
        assert result == b""

    def test_image_output_hook_with_non_bytes(self):
        """Test ImageOutputHook with non-bytes data returns empty bytes."""
        hook = ImageOutputHook()
        output = AgentOutput(modality=ModalityType.IMAGE, data="not bytes")

        result = hook.process(output)
        assert isinstance(result, bytes)
        assert result == b""


class TestAgentGeneration:
    """Test agent generation methods comprehensively."""

    @pytest.mark.asyncio
    async def test_generate_with_output_modality(self):
        """Test generate with different output modality."""
        agent = GeminiAgent()
        text_input = agent.process_input("Test", ModalityType.TEXT)

        output = await agent.generate([text_input], output_modality=ModalityType.VIDEO)
        assert output.modality == ModalityType.VIDEO

    @pytest.mark.asyncio
    async def test_generate_with_config(self):
        """Test generate with generation config passed through."""
        agent = GeminiAgent()
        text_input = agent.process_input("Test", ModalityType.TEXT)

        output = await agent.generate(
            [text_input], temperature=0.7, max_tokens=100, top_p=0.9
        )
        assert output.metadata["config"]["temperature"] == 0.7
        assert output.metadata["config"]["max_tokens"] == 100
        assert output.metadata["config"]["top_p"] == 0.9

    @pytest.mark.asyncio
    async def test_generate_with_multiple_inputs(self):
        """Test generate with multiple inputs."""
        agent = GeminiAgent()
        text_input = agent.process_input("Describe this", ModalityType.TEXT)
        video_input = agent.process_input(b"video data", ModalityType.VIDEO)
        image_input = agent.process_input(b"image data", ModalityType.IMAGE)

        output = await agent.generate([text_input, video_input, image_input])
        assert output.metadata["inputs"] == 3

    @pytest.mark.asyncio
    async def test_generate_text_with_context(self):
        """Test generate_text with additional context inputs."""
        agent = GeminiAgent()
        image_input = agent.process_input(b"image data", ModalityType.IMAGE)

        result = await agent.generate_text(
            "What's in this image?", context_inputs=[image_input]
        )
        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_from_video_with_bytes(self):
        """Test generate_from_video with bytes input."""
        agent = GeminiAgent()
        video_bytes = b"fake video data"

        result = await agent.generate_from_video(video_bytes, "Describe this")
        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_from_audio_with_bytes(self):
        """Test generate_from_audio with bytes input."""
        agent = GeminiAgent()
        audio_bytes = b"fake audio data"

        result = await agent.generate_from_audio(audio_bytes, "Transcribe this")
        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_multimodal_with_all_modalities(self):
        """Test generate_multimodal with all input types."""
        agent = GeminiAgent()

        result = await agent.generate_multimodal(
            text_prompts=["First prompt", "Second prompt"],
            images=["img1.jpg", "img2.jpg"],
            videos=["vid.mp4"],
            audios=["aud.mp3"],
        )
        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_multimodal_text_only(self):
        """Test generate_multimodal with only text."""
        agent = GeminiAgent()

        result = await agent.generate_multimodal(text_prompts=["Just text"])
        assert isinstance(result, str)

    @pytest.mark.asyncio
    async def test_generate_multimodal_with_video_output(self):
        """Test generate_multimodal requesting video output."""
        agent = GeminiAgent()

        result = await agent.generate_multimodal(
            text_prompts=["Generate video"],
            output_modality=ModalityType.VIDEO,
        )
        # Output hook should return bytes for video
        assert isinstance(result, bytes)


class TestAgentProcessing:
    """Test agent processing methods."""

    def test_process_input_audio(self):
        """Test processing audio input."""
        agent = GeminiAgent()
        result = agent.process_input(b"audio data", ModalityType.AUDIO)

        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.AUDIO

    def test_process_input_image(self):
        """Test processing image input."""
        agent = GeminiAgent()
        result = agent.process_input("image.jpg", ModalityType.IMAGE)

        assert isinstance(result, AgentInput)
        assert result.modality == ModalityType.IMAGE

    def test_process_output_video(self):
        """Test processing video output."""
        agent = GeminiAgent()
        output = AgentOutput(modality=ModalityType.VIDEO, data=b"video bytes")

        result = agent.process_output(output)
        assert isinstance(result, bytes)

    def test_process_output_audio(self):
        """Test processing audio output."""
        agent = GeminiAgent()
        output = AgentOutput(modality=ModalityType.AUDIO, data=b"audio bytes")

        result = agent.process_output(output)
        assert isinstance(result, bytes)

    def test_process_output_image(self):
        """Test processing image output."""
        agent = GeminiAgent()
        output = AgentOutput(modality=ModalityType.IMAGE, data=b"image bytes")

        result = agent.process_output(output)
        assert isinstance(result, bytes)


class TestAgentInitialization:
    """Test agent initialization variations."""

    def test_agent_initialization_defaults(self):
        """Test agent with default parameters."""
        agent = GeminiAgent()

        assert agent.api_key is None
        assert agent.model_name == "gemini-pro"
        assert agent._model is None

    def test_agent_initialization_custom_model(self):
        """Test agent with custom model name."""
        agent = GeminiAgent(model_name="gemini-ultra")

        assert agent.model_name == "gemini-ultra"
