"""
Tests for live.py module - video processing with Gemini Live API.
"""

import asyncio
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, mock_open, patch

import pytest
from PIL import Image

from src.live import (
    concatenate_chunks,
    create_fragmented_mp4,
    extract_audio_from_chunk,
    extract_frames_from_chunk,
    process_chunks_with_live_api,
    stitch_audio_video,
)

# Import websockets for full integration test
try:
    import websockets

    WEBSOCKETS_AVAILABLE = True
except ImportError:
    WEBSOCKETS_AVAILABLE = False


class TestExtractFramesFromChunk:
    """Tests for extract_frames_from_chunk function."""

    def test_extract_frames_basic(self):
        """Test basic frame extraction from video chunk."""
        # Create a minimal MP4 chunk (we'll mock ffmpeg)
        chunk_data = b"fake_mp4_data"

        with (
            patch("subprocess.run") as mock_run,
            patch("pathlib.Path.glob") as mock_glob,
            patch("PIL.Image.open") as mock_image_open,
        ):
            # Mock successful ffmpeg execution
            mock_run.return_value = MagicMock(returncode=0)

            # Mock frame files
            mock_glob.return_value = [
                Path("/tmp/frame_0001.jpg"),
                Path("/tmp/frame_0002.jpg"),
            ]

            # Mock PIL Image
            mock_img = MagicMock(spec=Image.Image)
            mock_image_open.return_value = mock_img

            frames = extract_frames_from_chunk(chunk_data, fps=1.0)

            assert len(frames) == 2
            assert mock_run.called
            # Verify ffmpeg command includes fps filter
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "ffmpeg" in ffmpeg_cmd
            assert "-vf" in ffmpeg_cmd

    def test_extract_frames_with_custom_fps(self):
        """Test frame extraction with custom FPS."""
        chunk_data = b"fake_mp4_data"

        with (
            patch("subprocess.run") as mock_run,
            patch("pathlib.Path.glob") as mock_glob,
            patch("PIL.Image.open") as mock_image_open,
        ):
            mock_run.return_value = MagicMock(returncode=0)
            mock_glob.return_value = [Path("/tmp/frame_0001.jpg")]

            mock_img = MagicMock(spec=Image.Image)
            mock_image_open.return_value = mock_img

            _frames = extract_frames_from_chunk(chunk_data, fps=2.0)

            # Verify FPS parameter is passed to ffmpeg
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "fps=2.0" in " ".join(ffmpeg_cmd)

    def test_extract_frames_ffmpeg_failure(self):
        """Test handling of ffmpeg failure."""
        chunk_data = b"invalid_data"

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="Invalid data"
            )

            with pytest.raises(RuntimeError, match="Failed to extract frames"):
                extract_frames_from_chunk(chunk_data)

    def test_extract_frames_empty_output(self):
        """Test handling when no frames are extracted."""
        chunk_data = b"fake_mp4_data"

        with (
            patch("subprocess.run") as mock_run,
            patch("pathlib.Path.glob") as mock_glob,
        ):
            mock_run.return_value = MagicMock(returncode=0)
            mock_glob.return_value = []  # No frames extracted

            frames = extract_frames_from_chunk(chunk_data)

            assert len(frames) == 0


class TestExtractAudioFromChunk:
    """Tests for extract_audio_from_chunk function."""

    def test_extract_audio_basic(self):
        """Test basic audio extraction from video chunk."""
        chunk_data = b"fake_mp4_with_audio"

        with (
            patch("subprocess.run") as mock_run,
            patch("builtins.open", mock_open(read_data=b"pcm_audio_data")),
            patch("pathlib.Path.exists") as mock_exists,
        ):
            mock_run.return_value = MagicMock(returncode=0)
            mock_exists.return_value = True

            audio_data = extract_audio_from_chunk(chunk_data)

            assert audio_data == b"pcm_audio_data"
            assert mock_run.called

            # Verify ffmpeg command includes PCM parameters
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "ffmpeg" in ffmpeg_cmd
            assert "pcm_s16le" in ffmpeg_cmd
            assert "16000" in ffmpeg_cmd  # Sample rate

    def test_extract_audio_no_audio_stream(self):
        """Test handling when video has no audio stream."""
        chunk_data = b"fake_mp4_no_audio"

        with patch("subprocess.run") as mock_run:
            # Simulate ffmpeg failure due to no audio stream
            mock_run.return_value = MagicMock(returncode=1, stderr="No audio stream")

            audio_data = extract_audio_from_chunk(chunk_data)

            assert audio_data == b""

    def test_extract_audio_ffmpeg_failure(self):
        """Test that ffmpeg failures return empty bytes."""
        chunk_data = b"invalid_data"

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="Error"
            )

            audio_data = extract_audio_from_chunk(chunk_data)

            assert audio_data == b""


class TestStitchAudioVideo:
    """Tests for stitch_audio_video function."""

    def test_stitch_audio_video_basic(self):
        """Test basic audio/video stitching."""
        video_data = b"fake_video"
        audio_pcm = b"fake_audio_pcm"

        with (
            patch("subprocess.run") as mock_run,
            patch("builtins.open", mock_open(read_data=b"stitched_output")),
        ):
            mock_run.return_value = MagicMock(returncode=0)

            result = stitch_audio_video(video_data, audio_pcm, audio_sample_rate=24000)

            assert result == b"stitched_output"
            assert mock_run.called

            # Verify ffmpeg command parameters
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "ffmpeg" in ffmpeg_cmd
            assert "24000" in ffmpeg_cmd  # Sample rate
            assert "aac" in ffmpeg_cmd  # Audio codec

    def test_stitch_audio_video_custom_sample_rate(self):
        """Test stitching with custom sample rate."""
        video_data = b"fake_video"
        audio_pcm = b"fake_audio_pcm"

        with (
            patch("subprocess.run") as mock_run,
            patch("builtins.open", mock_open(read_data=b"output")),
        ):
            mock_run.return_value = MagicMock(returncode=0)

            stitch_audio_video(video_data, audio_pcm, audio_sample_rate=16000)

            # Verify custom sample rate is used
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "16000" in ffmpeg_cmd

    def test_stitch_audio_video_ffmpeg_failure(self):
        """Test handling of ffmpeg failure during stitching."""
        video_data = b"fake_video"
        audio_pcm = b"fake_audio_pcm"

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="Stitch error"
            )

            with pytest.raises(RuntimeError, match="Failed to stitch audio and video"):
                stitch_audio_video(video_data, audio_pcm)


class TestCreateFragmentedMp4:
    """Tests for create_fragmented_mp4 function."""

    def test_create_fragmented_mp4_basic(self):
        """Test basic fragmented MP4 creation."""
        video_data = b"regular_mp4_data"

        with (
            patch("subprocess.run") as mock_run,
            patch("builtins.open", mock_open(read_data=b"fragmented_mp4")),
        ):
            mock_run.return_value = MagicMock(returncode=0)

            result = create_fragmented_mp4(video_data)

            assert result == b"fragmented_mp4"
            assert mock_run.called

            # Verify fragmentation flags
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "ffmpeg" in ffmpeg_cmd
            assert "-movflags" in ffmpeg_cmd
            assert "frag_keyframe" in " ".join(ffmpeg_cmd)

    def test_create_fragmented_mp4_ffmpeg_failure(self):
        """Test handling of ffmpeg failure."""
        video_data = b"invalid_data"

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="Fragment error"
            )

            with pytest.raises(RuntimeError, match="Failed to create fragmented MP4"):
                create_fragmented_mp4(video_data)


class TestConcatenateChunks:
    """Tests for concatenate_chunks function."""

    def test_concatenate_empty_list(self):
        """Test concatenating empty chunk list."""
        chunks = []
        result = concatenate_chunks(chunks)
        assert result == b""

    def test_concatenate_single_chunk(self):
        """Test concatenating single chunk."""
        chunks = [b"single_chunk"]
        result = concatenate_chunks(chunks)
        assert result == b"single_chunk"

    def test_concatenate_multiple_chunks(self):
        """Test concatenating multiple chunks."""
        chunks = [b"chunk1", b"chunk2", b"chunk3"]

        with (
            patch("subprocess.run") as mock_run,
            patch("builtins.open", mock_open(read_data=b"concatenated")),
        ):
            mock_run.return_value = MagicMock(returncode=0)

            result = concatenate_chunks(chunks)

            assert result == b"concatenated"
            assert mock_run.called

            # Verify ffmpeg concat command
            ffmpeg_cmd = mock_run.call_args[0][0]
            assert "ffmpeg" in ffmpeg_cmd
            assert "-f" in ffmpeg_cmd
            assert "concat" in ffmpeg_cmd

    def test_concatenate_ffmpeg_failure_fallback(self):
        """Test that ffmpeg failure returns first chunk as fallback."""
        chunks = [b"chunk1", b"chunk2", b"chunk3"]

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="Concat error"
            )

            result = concatenate_chunks(chunks)

            # Should return first chunk as fallback
            assert result == b"chunk1"


class TestProcessChunksWithLiveApi:
    """Tests for process_chunks_with_live_api function."""

    @pytest.mark.asyncio
    async def test_process_chunks_basic(self):
        """Test basic processing of chunks with Live API."""
        chunks = [b"chunk1", b"chunk2"]
        mock_ws = MagicMock()

        # Mock frame extraction
        mock_frame = MagicMock(spec=Image.Image)

        with (
            patch(
                "src.live.extract_frames_from_chunk", return_value=[mock_frame]
            ) as _mock_extract,
            patch("src.live.concatenate_chunks", return_value=b"concat_video"),
            patch("src.live.stitch_audio_video", return_value=b"stitched_video"),
            patch("src.live.create_fragmented_mp4", return_value=b"fragmented_video"),
            patch("src.live.GeminiLiveClient") as mock_client_class,
        ):
            # Mock GeminiLiveClient
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client

            # Mock audio stream
            async def mock_audio_stream():
                yield b"audio_chunk1"
                yield b"audio_chunk2"

            mock_client.receive_audio_stream = mock_audio_stream
            mock_client.connect = AsyncMock()
            mock_client.disconnect = AsyncMock()
            mock_client.send_text = AsyncMock()
            mock_client.send_video_frame = AsyncMock()

            await process_chunks_with_live_api(
                chunks=chunks,
                websocket=mock_ws,
                video_url="https://example.com/video.mp4",
                prompt="Test prompt",
                fps=1.0,
            )

            # Verify client was connected
            mock_client.connect.assert_called_once()

            # Verify frames were sent
            assert mock_client.send_video_frame.call_count == len(chunks)

            # Verify websocket send was called with JSON message
            assert mock_ws.send.called
            sent_message = mock_ws.send.call_args[0][0]

            # Parse and validate JSON message
            import json

            msg = json.loads(sent_message)
            assert msg["type"] == "live_commentary"
            assert "video_data" in msg["data"]
            assert (
                msg["data"]["metadata"]["src_video_url"]
                == "https://example.com/video.mp4"
            )
            assert msg["data"]["metadata"]["format"] == "fragmented_mp4"

    @pytest.mark.asyncio
    async def test_process_chunks_with_custom_parameters(self):
        """Test processing with custom parameters."""
        chunks = [b"chunk1"]
        mock_ws = MagicMock()
        custom_instruction = "Custom sports commentator"
        custom_prompt = "Custom prompt"

        mock_frame = MagicMock(spec=Image.Image)

        with (
            patch("src.live.extract_frames_from_chunk", return_value=[mock_frame]),
            patch("src.live.concatenate_chunks", return_value=b"video"),
            patch("src.live.stitch_audio_video", return_value=b"video"),
            patch("src.live.create_fragmented_mp4", return_value=b"video"),
            patch("src.live.GeminiLiveClient") as mock_client_class,
        ):
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client

            # Mock empty audio stream
            async def mock_audio_stream():
                if False:
                    yield

            mock_client.receive_audio_stream = mock_audio_stream
            mock_client.connect = AsyncMock()
            mock_client.disconnect = AsyncMock()
            mock_client.send_text = AsyncMock()
            mock_client.send_video_frame = AsyncMock()

            await process_chunks_with_live_api(
                chunks=chunks,
                websocket=mock_ws,
                video_url="https://example.com/video.mp4",
                system_instruction=custom_instruction,
                prompt=custom_prompt,
                fps=2.0,
            )

            # Verify custom system instruction was used
            assert (
                mock_client_class.call_args[1]["system_instruction"]
                == custom_instruction
            )

            # Verify custom prompt was sent
            mock_client.send_text.assert_called_with(custom_prompt)

    @pytest.mark.asyncio
    async def test_process_chunks_connection_error(self):
        """Test handling of connection errors."""
        chunks = [b"chunk1"]
        mock_ws = MagicMock()

        with patch("src.live.GeminiLiveClient") as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client

            # Simulate connection error
            mock_client.connect.side_effect = RuntimeError("Connection failed")

            with pytest.raises(RuntimeError, match="Connection failed"):
                await process_chunks_with_live_api(
                    chunks=chunks,
                    websocket=mock_ws,
                    video_url="https://example.com/video.mp4",
                )

    @pytest.mark.asyncio
    async def test_process_chunks_cleanup_on_error(self):
        """Test that client is disconnected even on error."""
        chunks = [b"chunk1"]
        mock_ws = MagicMock()
        mock_frame = MagicMock(spec=Image.Image)

        with (
            patch("src.live.extract_frames_from_chunk", return_value=[mock_frame]),
            patch("src.live.concatenate_chunks", return_value=b"video"),
            patch(
                "src.live.stitch_audio_video",
                side_effect=RuntimeError("Stitch error"),
            ),
            patch("src.live.GeminiLiveClient") as mock_client_class,
        ):
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client

            async def mock_audio_stream():
                yield b"audio"

            mock_client.receive_audio_stream = mock_audio_stream
            mock_client.connect = AsyncMock()
            mock_client.disconnect = AsyncMock()
            mock_client.send_text = AsyncMock()
            mock_client.send_video_frame = AsyncMock()

            with pytest.raises(RuntimeError, match="Stitch error"):
                await process_chunks_with_live_api(
                    chunks=chunks,
                    websocket=mock_ws,
                    video_url="https://example.com/video.mp4",
                )

            # Verify disconnect was called despite error
            mock_client.disconnect.assert_called_once()


class TestLiveApiIntegration:
    """Integration tests with real Gemini Live API."""

    @pytest.mark.asyncio
    async def test_real_gemini_live_api_with_short_clip(self):
        """
        Real integration test using actual Gemini Live API.

        This test:
        1. Takes a short 2-second video clip from assets
        2. Processes it through the real Gemini Live API
        3. Receives audio commentary
        4. Stitches audio with video
        5. Saves output to video_output/live_video_audio_output_test.mp4
        """
        import os
        import subprocess

        # Check if API key is available
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set - skipping real API test")

        # Load test video from assets
        test_video_dir = Path(__file__).parent / "assets"
        test_videos = sorted(list(test_video_dir.glob("*.mp4")))[:1]

        if not test_videos:
            pytest.skip("No test videos available in assets folder")

        # Create a 2-second clip from the test video
        print("\n📹 Creating 2-second test clip...")
        temp_dir = Path(tempfile.mkdtemp(prefix="live_test_"))
        try:
            short_clip = temp_dir / "short_clip.mp4"

            # Use ffmpeg to extract first 2 seconds
            cmd = [
                "ffmpeg",
                "-i",
                str(test_videos[0]),
                "-t",
                "2",  # Duration: 2 seconds
                "-c",
                "copy",  # Copy streams without re-encoding
                str(short_clip),
            ]

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                pytest.skip(f"Failed to create short clip: {result.stderr}")

            # Read the short clip
            with open(short_clip, "rb") as f:
                chunk_data = f.read()

            print(f"   Created {len(chunk_data)} byte clip")

            # Process with real Gemini Live API
            print("\n🚀 Processing with Gemini Live API...")

            from src.llm import GeminiLiveClient

            client = GeminiLiveClient(
                system_instruction="You are a sports commentator. Provide brief, exciting commentary."
            )

            try:
                await client.connect()
                await client.send_text("Provide brief commentary for this sports clip.")

                # Extract and send frames
                print("   Extracting frames...")
                frames = await asyncio.to_thread(
                    extract_frames_from_chunk, chunk_data, fps=1.0
                )
                print(f"   Sending {len(frames)} frames to Live API...")

                for frame in frames:
                    await client.send_video_frame(frame)
                    await asyncio.sleep(0.1)

                # Collect audio with timeout
                print("   Collecting audio commentary...")
                audio_chunks = []
                try:
                    async with asyncio.timeout(15.0):  # 15 second timeout
                        async for audio_data in client.receive_audio_stream():
                            audio_chunks.append(audio_data)
                            # Stop after receiving reasonable amount
                            if len(audio_chunks) >= 20:
                                break
                except asyncio.TimeoutError:
                    print("   ⚠️  Audio collection timeout")

                if audio_chunks:
                    audio_pcm = b"".join(audio_chunks)
                    print(f"   ✅ Received {len(audio_pcm)} bytes of audio")

                    # Stitch audio with video
                    print("\n🔗 Stitching audio and video...")
                    final_video = await asyncio.to_thread(
                        stitch_audio_video,
                        chunk_data,
                        audio_pcm,
                        audio_sample_rate=24000,
                    )

                    # Save to video_output
                    output_dir = Path(__file__).parent.parent / "video_output"
                    output_dir.mkdir(parents=True, exist_ok=True)
                    output_file = output_dir / "live_video_audio_output_test.mp4"

                    with open(output_file, "wb") as f:
                        f.write(final_video)

                    print(f"\n💾 Saved output to: {output_file}")
                    print(f"   File size: {len(final_video):,} bytes")

                    # Verify with ffprobe
                    try:
                        import json

                        ffprobe_cmd = [
                            "ffprobe",
                            "-v",
                            "quiet",
                            "-print_format",
                            "json",
                            "-show_streams",
                            str(output_file),
                        ]

                        result = subprocess.run(
                            ffprobe_cmd, capture_output=True, text=True, timeout=10
                        )

                        if result.returncode == 0:
                            probe_data = json.loads(result.stdout)
                            streams = probe_data.get("streams", [])

                            video_streams = [
                                s for s in streams if s.get("codec_type") == "video"
                            ]
                            audio_streams = [
                                s for s in streams if s.get("codec_type") == "audio"
                            ]

                            print("\n📊 Output verification:")
                            print(f"   📺 Video streams: {len(video_streams)}")
                            print(f"   🎵 Audio streams: {len(audio_streams)}")

                            assert len(video_streams) > 0, "Should have video stream"
                            assert len(audio_streams) > 0, "Should have audio stream"

                            print("\n✅ Real Gemini Live API integration test passed!")

                    except Exception as e:
                        print(f"   ⚠️  Could not verify with ffprobe: {e}")

                else:
                    pytest.fail("No audio received from Gemini Live API")

            finally:
                await client.disconnect()

        finally:
            # Cleanup
            import shutil

            shutil.rmtree(temp_dir, ignore_errors=True)


class TestTempFileCleanup:
    """Tests to ensure temporary files are cleaned up properly."""

    def test_extract_frames_cleanup(self):
        """Test that temporary directories are cleaned up after frame extraction."""
        chunk_data = b"fake_data"

        with (
            patch("subprocess.run") as mock_run,
            patch("pathlib.Path.glob") as mock_glob,
            patch("PIL.Image.open") as mock_image,
            patch("shutil.rmtree") as mock_rmtree,
        ):
            mock_run.return_value = MagicMock(returncode=0)
            mock_glob.return_value = []
            mock_image.return_value = MagicMock(spec=Image.Image)

            extract_frames_from_chunk(chunk_data)

            # Verify cleanup was called
            mock_rmtree.assert_called_once()

    def test_concatenate_cleanup(self):
        """Test that temporary directories are cleaned up after concatenation."""
        chunks = [b"chunk1", b"chunk2"]

        with (
            patch("subprocess.run") as mock_run,
            patch("builtins.open", mock_open(read_data=b"output")),
            patch("shutil.rmtree") as mock_rmtree,
        ):
            mock_run.return_value = MagicMock(returncode=0)

            concatenate_chunks(chunks)

            # Verify cleanup was called
            mock_rmtree.assert_called_once()


@pytest.mark.skipif(not WEBSOCKETS_AVAILABLE, reason="websockets library not available")
class TestFullWebSocketIntegration:
    """Full end-to-end integration tests with real WebSocket connections."""

    @pytest.mark.asyncio
    async def test_websocket_integration_with_mocked_live_api(self):
        """
        Full integration test with real WebSocket server and client.

        This test:
        1. Spins up a real WebSocket server
        2. Connects a client
        3. Processes real video chunks through the live API (mocked)
        4. Verifies the client receives audio+video stream
        """
        received_data = []
        server_started = asyncio.Event()

        async def websocket_server_handler(websocket):
            """WebSocket server that receives the processed video."""
            server_started.set()
            try:
                # Receive data from the live API processing
                async for message in websocket:
                    # Messages are now JSON strings
                    if isinstance(message, str):
                        received_data.append(message.encode("utf-8"))
                        print(f"Server received message ({len(message)} chars)")
                    elif isinstance(message, bytes):
                        received_data.append(message)
                        print(f"Server received {len(message)} bytes")
            except websockets.exceptions.ConnectionClosed:
                # Connection closed normally
                pass
            except Exception as e:
                print(f"Server error: {e}")

        # Start WebSocket server on localhost
        server = await websockets.serve(websocket_server_handler, "localhost", 8765)

        try:
            await asyncio.sleep(0.1)  # Give server time to start

            # Connect WebSocket client
            async with websockets.connect("ws://localhost:8765") as websocket:
                # Load real test video chunks from assets
                test_video_dir = Path(__file__).parent / "assets"
                test_videos = sorted(list(test_video_dir.glob("*.mp4")))[
                    :1
                ]  # Use first video

                if not test_videos:
                    pytest.skip("No test videos available in assets folder")

                chunks = []
                with open(test_videos[0], "rb") as f:
                    chunks.append(f.read())

                print(f"Processing {len(chunks)} video chunks")

                # Mock the Live API client to simulate receiving audio
                with (
                    patch("src.live.GeminiLiveClient") as mock_client_class,
                ):
                    mock_client = AsyncMock()
                    mock_client_class.return_value = mock_client

                    # Simulate receiving audio from Live API (finite stream)
                    async def mock_audio_stream():
                        # Generate some fake PCM audio data and then stop
                        yield b"\x00\x01" * 24000  # 1 second of 24kHz 16-bit mono PCM
                        # Stream ends here (no more yields)

                    mock_client.receive_audio_stream = mock_audio_stream
                    mock_client.connect = AsyncMock()
                    mock_client.disconnect = AsyncMock()
                    mock_client.send_text = AsyncMock()
                    mock_client.send_video_frame = AsyncMock()

                    # Process chunks with mocked Live API (with timeout)
                    try:
                        async with asyncio.timeout(30.0):  # 30 second timeout
                            await process_chunks_with_live_api(
                                chunks=chunks,
                                websocket=websocket,
                                video_url="https://example.com/test_video.mp4",
                                system_instruction="Test commentator",
                                prompt="Test prompt",
                                fps=1.0,
                            )
                    except asyncio.TimeoutError:
                        pytest.fail("Test timed out - websocket send may be blocking")

                    # Give server time to receive all data
                    await asyncio.sleep(0.5)

            # Verify we received data
            assert len(received_data) > 0, "Should have received data via WebSocket"

            print("\n✅ WebSocket integration test passed!")
            print(f"   Received {len(received_data)} message(s)")

            # Parse JSON message
            import base64
            import json

            first_message = received_data[0].decode("utf-8")
            msg = json.loads(first_message)

            print(f"   Message type: {msg['type']}")
            assert msg["type"] == "live_commentary", (
                "Should receive live_commentary message"
            )

            # Extract video data from JSON
            video_data = base64.b64decode(msg["data"]["video_data"])
            print(f"   Total video bytes: {len(video_data)}")

            # Verify the data looks like a valid MP4 (should start with ftyp)
            assert b"ftyp" in video_data[:100], "Data should be valid MP4 format"
            print("   ✅ Validated MP4 format signature")

            # Save the received video for manual inspection
            output_dir = Path(__file__).parent.parent / "video_output"
            output_dir.mkdir(parents=True, exist_ok=True)
            output_file = output_dir / "websocket_test_output.mp4"

            with open(output_file, "wb") as f:
                f.write(video_data)

            print(f"   💾 Saved output to: {output_file}")

            # Verify the output has both video and audio streams
            try:
                ffprobe_cmd = [
                    "ffprobe",
                    "-v",
                    "quiet",
                    "-print_format",
                    "json",
                    "-show_streams",
                    str(output_file),
                ]

                result = subprocess.run(
                    ffprobe_cmd, capture_output=True, text=True, timeout=10
                )

                if result.returncode == 0:
                    probe_data = json.loads(result.stdout)
                    streams = probe_data.get("streams", [])

                    video_streams = [
                        s for s in streams if s.get("codec_type") == "video"
                    ]
                    audio_streams = [
                        s for s in streams if s.get("codec_type") == "audio"
                    ]

                    print(f"   📺 Video streams: {len(video_streams)}")
                    print(f"   🎵 Audio streams: {len(audio_streams)}")

                    assert len(video_streams) > 0, (
                        "Should have at least one video stream"
                    )
                    assert len(audio_streams) > 0, (
                        "Should have at least one audio stream"
                    )

                    print("   ✅ Verified both audio and video streams present!")

            except Exception as e:
                print(f"   ⚠️  Could not verify streams with ffprobe: {e}")

        finally:
            # Clean up server
            server.close()
            await server.wait_closed()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
