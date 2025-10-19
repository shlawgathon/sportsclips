"""
Tests for the Gemini Live API client.

These tests verify the live streaming functionality, including
video input and audio output streaming via WebSocket.
"""

import os
from pathlib import Path
from typing import AsyncIterator

import pytest
from PIL import Image

from src.llm import GeminiLiveClient


class TestGeminiLiveClientInitialization:
    """Test GeminiLiveClient initialization."""

    def test_live_client_initialization(self):
        """Test creating a GeminiLiveClient instance."""
        client = GeminiLiveClient(
            api_key="test-key",
            model_name="gemini-live-2.5-flash-preview",
        )

        assert client.api_key == "test-key"
        assert client.model_name == "gemini-live-2.5-flash-preview"
        assert "commentator" in client.system_instruction.lower()

    def test_live_client_with_custom_instruction(self):
        """Test live client with custom system instruction."""
        custom_instruction = "You are a game show host."
        client = GeminiLiveClient(
            api_key="test-key", system_instruction=custom_instruction
        )

        assert client.system_instruction == custom_instruction

    def test_live_client_with_env_api_key(self):
        """Test that client picks up API key from environment."""
        # This test assumes GEMINI_API_KEY is set in environment
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")

        client = GeminiLiveClient()
        assert client.api_key == api_key


class TestGeminiLiveClientConnection:
    """Test WebSocket connection functionality."""

    @pytest.fixture
    def client_with_api(self):
        """Create a client with API key from environment."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return GeminiLiveClient(api_key=api_key)

    @pytest.mark.asyncio
    async def test_connect_and_disconnect(self, client_with_api):
        """Test establishing and closing WebSocket connection."""
        await client_with_api.connect()
        assert client_with_api._session is not None

        await client_with_api.disconnect()
        assert client_with_api._session is None

    @pytest.mark.asyncio
    async def test_context_manager(self, client_with_api):
        """Test using client as async context manager."""
        async with client_with_api as client:
            assert client._session is not None

        # After exiting context, session should be closed
        assert client_with_api._session is None

    @pytest.mark.asyncio
    async def test_connect_with_custom_config(self, client_with_api):
        """Test connecting with custom configuration."""
        await client_with_api.connect(
            response_modalities=["AUDIO"],
            temperature=0.8,
        )
        assert client_with_api._session is not None
        await client_with_api.disconnect()

    @pytest.mark.asyncio
    async def test_connect_without_api_key_raises_error(self):
        """Test that connecting without API key raises error."""
        client = GeminiLiveClient(api_key=None)
        client._client = None

        with pytest.raises(ValueError, match="Client not initialized"):
            await client.connect()


class TestGeminiLiveClientSending:
    """Test sending data to the Live API."""

    @pytest.fixture
    def client_with_api(self):
        """Create a client with API key from environment."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return GeminiLiveClient(api_key=api_key)

    @pytest.mark.asyncio
    async def test_send_text_without_session_raises_error(self, client_with_api):
        """Test that sending text without session raises error."""
        with pytest.raises(ValueError, match="Session not connected"):
            await client_with_api.send_text("Test")

    @pytest.mark.asyncio
    async def test_send_video_without_session_raises_error(self, client_with_api):
        """Test that sending video without session raises error."""
        with pytest.raises(ValueError, match="Session not connected"):
            await client_with_api.send_video_frame(b"video data")

    @pytest.mark.asyncio
    async def test_send_audio_without_session_raises_error(self, client_with_api):
        """Test that sending audio without session raises error."""
        with pytest.raises(ValueError, match="Session not connected"):
            await client_with_api.send_audio_chunk(b"audio data")

    @pytest.mark.asyncio
    async def test_send_text_with_session(self, client_with_api):
        """Test sending text input after connecting."""
        async with client_with_api:
            # Should not raise an error
            await client_with_api.send_text(
                "Please provide commentary on the following video."
            )

    @pytest.mark.asyncio
    async def test_send_video_frame(self, client_with_api):
        """Test sending video frame data."""
        import io

        from PIL import Image

        # Create a simple test image (100x100 red square)
        test_image = Image.new("RGB", (100, 100), color="red")

        # Convert to bytes
        img_bytes = io.BytesIO()
        test_image.save(img_bytes, format="JPEG")
        img_bytes.seek(0)
        frame_data = img_bytes.read()

        async with client_with_api:
            # Should not raise an error
            await client_with_api.send_video_frame(frame_data)


class TestGeminiLiveClientReceiving:
    """Test receiving audio from the Live API."""

    @pytest.fixture
    def client_with_api(self):
        """Create a client with API key from environment."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return GeminiLiveClient(api_key=api_key)

    @pytest.mark.asyncio
    async def test_receive_without_session_raises_error(self, client_with_api):
        """Test that receiving without session raises error."""
        with pytest.raises(ValueError, match="Session not connected"):
            async for _ in client_with_api.receive_audio_stream():
                pass


class TestGeminiLiveClientE2E:
    """End-to-end tests with actual Live API calls."""

    @pytest.fixture
    def client_with_api(self):
        """Create a client with API key from environment."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return GeminiLiveClient(api_key=api_key)

    @pytest.mark.asyncio
    async def test_e2e_video_to_audio_generation(self, client_with_api):
        """Test generating audio commentary from a video file."""
        test_dir = Path(__file__).parent / "assets"
        video_path = test_dir / "test_video1.mp4"

        if not video_path.exists():
            pytest.skip("Test video not available in assets folder")

        async with client_with_api:
            audio_output = await client_with_api.generate_audio_from_video(
                video_path=video_path,
                prompt="Provide a brief sports commentary for this video clip.",
            )

        # Verify we got audio data back
        assert isinstance(audio_output, bytes)
        assert len(audio_output) > 0

        # Save output for manual verification
        output_path = test_dir / "test_live_output_audio.wav"
        with open(output_path, "wb") as f:
            f.write(audio_output)

        print(f"\n✅ E2E Live Test - Generated {len(audio_output)} bytes of audio")
        print(f"   Audio saved to: {output_path}")

    @pytest.mark.asyncio
    async def test_e2e_stream_video_with_audio_callback(self, client_with_api):
        """Test streaming video with callback for each audio chunk."""
        test_dir = Path(__file__).parent / "assets"
        video_path = test_dir / "test_video1.mp4"

        if not video_path.exists():
            pytest.skip("Test video not available in assets folder")

        # Track received audio chunks
        audio_chunks_received = []

        def audio_callback(chunk: bytes) -> None:
            """Callback to track received audio chunks."""
            audio_chunks_received.append(chunk)
            print(f"   Received audio chunk: {len(chunk)} bytes")

        async with client_with_api:
            audio_output = await client_with_api.stream_video_with_audio_output(
                video_source=video_path,
                on_audio_chunk=audio_callback,
                prompt="Describe what's happening in this sports clip.",
            )

        # Verify we received audio
        assert isinstance(audio_output, bytes)
        assert len(audio_output) > 0
        assert len(audio_chunks_received) > 0

        print(
            f"\n✅ E2E Live Test - Received {len(audio_chunks_received)} audio chunks"
        )
        print(f"   Total audio size: {len(audio_output)} bytes")

    @pytest.mark.asyncio
    async def test_e2e_multiple_videos_sequential(self, client_with_api):
        """Test processing multiple videos sequentially."""
        test_dir = Path(__file__).parent / "assets"
        video1_path = test_dir / "test_video1.mp4"
        video2_path = test_dir / "test_video2.mp4"

        if not video1_path.exists() or not video2_path.exists():
            pytest.skip("Test videos not available in assets folder")

        async with client_with_api:
            # Process first video
            audio1 = await client_with_api.generate_audio_from_video(
                video_path=video1_path,
                prompt="Comment on the first video.",
            )

            # Process second video (need to reconnect or send new content)
            audio2 = await client_with_api.generate_audio_from_video(
                video_path=video2_path,
                prompt="Comment on the second video.",
            )

        assert isinstance(audio1, bytes) and len(audio1) > 0
        assert isinstance(audio2, bytes) and len(audio2) > 0

        print("\n✅ E2E Live Test - Processed 2 videos")
        print(f"   Video 1 audio: {len(audio1)} bytes")
        print(f"   Video 2 audio: {len(audio2)} bytes")

    @pytest.mark.asyncio
    async def test_e2e_custom_system_instruction(self, client_with_api):
        """Test with custom system instruction."""
        test_dir = Path(__file__).parent / "assets"
        video_path = test_dir / "test_video1.mp4"

        if not video_path.exists():
            pytest.skip("Test video not available in assets folder")

        # Create client with custom instruction
        api_key = os.getenv("GEMINI_API_KEY")
        custom_client = GeminiLiveClient(
            api_key=api_key,
            system_instruction="You are an enthusiastic game show host. "
            "Use exciting language and sound effects.",
        )

        async with custom_client:
            audio_output = await custom_client.generate_audio_from_video(
                video_path=video_path,
                prompt="Introduce this exciting moment!",
            )

        assert isinstance(audio_output, bytes)
        assert len(audio_output) > 0

        # Save with different name
        output_path = test_dir / "test_live_custom_instruction_audio.wav"
        with open(output_path, "wb") as f:
            f.write(audio_output)

        print(
            f"\n✅ E2E Live Test - Custom instruction generated {len(audio_output)} bytes"
        )
        print(f"   Audio saved to: {output_path}")


class TestGeminiLiveClientWAVConversion:
    """Test WAV file creation from PCM data."""

    def test_create_wav_from_pcm(self):
        """Test converting PCM data to WAV format."""
        client = GeminiLiveClient(api_key="test-key")

        # Create fake PCM data (16-bit samples)
        sample_count = 24000  # 1 second at 24kHz
        pcm_data = b"\x00\x01" * sample_count  # Fake 16-bit samples

        wav_data = client._create_wav_from_pcm(pcm_data)

        # Verify it's a valid WAV file
        assert isinstance(wav_data, bytes)
        assert len(wav_data) > len(pcm_data)  # WAV has header
        assert wav_data.startswith(b"RIFF")  # WAV file signature
        assert b"WAVE" in wav_data[:12]  # WAVE format

        print(f"\n✅ WAV Conversion - PCM {len(pcm_data)} -> WAV {len(wav_data)}")

    def test_create_wav_with_custom_params(self):
        """Test WAV creation with custom parameters."""
        client = GeminiLiveClient(api_key="test-key")

        pcm_data = b"\x00\x01" * 16000

        # Create with 16kHz sample rate
        wav_data = client._create_wav_from_pcm(pcm_data, sample_rate=16000, channels=1)

        assert isinstance(wav_data, bytes)
        assert wav_data.startswith(b"RIFF")


class TestGeminiLiveClientAsyncIterator:
    """Test async iterator support for video streaming."""

    @pytest.fixture
    def client_with_api(self):
        """Create a client with API key from environment."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return GeminiLiveClient(api_key=api_key)

    async def mock_video_stream(self) -> AsyncIterator[Image.Image]:
        """Mock async iterator that yields image frames."""
        from PIL import Image

        # Generate a few test frames (colored squares)
        colors = ["red", "green", "blue"]
        for color in colors:
            frame = Image.new("RGB", (100, 100), color=color)
            yield frame

    @pytest.mark.asyncio
    async def test_stream_video_chunks(self, client_with_api):
        """Test streaming video frames via async iterator."""
        async with client_with_api:
            # Stream image frames via async iterator
            audio_output = await client_with_api.stream_video_with_audio_output(
                video_source=self.mock_video_stream(),
                prompt="Comment on this video stream.",
            )

        assert isinstance(audio_output, bytes)
        print(f"\n✅ Stream Test - Generated {len(audio_output)} bytes from chunks")


class TestGeminiLiveClientErrorHandling:
    """Test error handling in the live client."""

    @pytest.fixture
    def client_with_api(self):
        """Create a client with API key from environment."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return GeminiLiveClient(api_key=api_key)

    @pytest.mark.asyncio
    async def test_generate_audio_without_connection_raises_error(
        self, client_with_api
    ):
        """Test that generating without connecting raises error."""
        test_dir = Path(__file__).parent / "assets"
        video_path = test_dir / "test_video1.mp4"

        if not video_path.exists():
            pytest.skip("Test video not available")

        # Don't connect - should raise error
        with pytest.raises(ValueError, match="Session not connected"):
            await client_with_api.generate_audio_from_video(
                video_path=video_path,
                prompt="Test",
            )

    @pytest.mark.asyncio
    async def test_invalid_video_path_handling(self, client_with_api):
        """Test handling of invalid video path."""
        async with client_with_api:
            # Try to process non-existent video
            with pytest.raises(FileNotFoundError):
                await client_with_api.generate_audio_from_video(
                    video_path="/nonexistent/video.mp4",
                    prompt="Test",
                )
