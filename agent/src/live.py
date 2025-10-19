"""
Live video processing with real-time audio commentary using Gemini Live API.

This module provides functionality to process video chunks in real-time,
extract frames, send them to the Gemini Live API, and receive audio commentary
that is then stitched back with the video for streaming output.
"""

import asyncio
import logging
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any

from PIL import Image

from .llm import GeminiLiveClient

logger = logging.getLogger(__name__)


def extract_frames_from_chunk(chunk_data: bytes, fps: float = 1.0) -> list[Image.Image]:
    """
    Extract frames from a video chunk using ffmpeg.

    Args:
        chunk_data: Video chunk bytes (MP4 format)
        fps: Frames per second to extract (default: 1.0)

    Returns:
        list[Image.Image]: List of PIL Images representing frames

    Raises:
        RuntimeError: If ffmpeg fails to extract frames
    """
    unique_id = uuid.uuid4().hex[:8]
    temp_dir = tempfile.mkdtemp(prefix=f"extract_frames_{unique_id}_")

    try:
        temp_path = Path(temp_dir)

        # Write chunk to temp file
        input_file = temp_path / "input.mp4"
        with open(input_file, "wb") as f:
            f.write(chunk_data)

        # Extract frames to JPEG files
        output_pattern = str(temp_path / "frame_%04d.jpg")
        cmd = [
            "ffmpeg",
            "-i",
            str(input_file),
            "-vf",
            f"fps={fps}",
            "-q:v",
            "2",  # High quality JPEG
            output_pattern,
        ]

        try:
            subprocess.run(
                cmd, capture_output=True, text=True, check=True, cwd=str(temp_path)
            )
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to extract frames: {e.stderr}")

        # Load extracted frames
        frame_files = sorted(temp_path.glob("frame_*.jpg"))
        frames = []
        for frame_file in frame_files:
            frames.append(
                Image.open(frame_file).copy()
            )  # Copy to avoid file handle issues

        return frames

    finally:
        # Cleanup
        try:
            import shutil

            shutil.rmtree(temp_dir)
        except Exception:
            pass


def extract_audio_from_chunk(chunk_data: bytes) -> bytes:
    """
    Extract audio track from a video chunk as PCM data.

    Args:
        chunk_data: Video chunk bytes (MP4 format)

    Returns:
        bytes: Audio data in 16-bit PCM format at 16kHz, or empty bytes if no audio

    Raises:
        RuntimeError: If ffmpeg fails to extract audio
    """
    unique_id = uuid.uuid4().hex[:8]
    temp_dir = tempfile.mkdtemp(prefix=f"extract_audio_{unique_id}_")

    try:
        temp_path = Path(temp_dir)

        # Write chunk to temp file
        input_file = temp_path / "input.mp4"
        with open(input_file, "wb") as f:
            f.write(chunk_data)

        # Extract audio as PCM
        output_file = temp_path / "audio.pcm"
        cmd = [
            "ffmpeg",
            "-i",
            str(input_file),
            "-vn",  # No video
            "-acodec",
            "pcm_s16le",  # 16-bit PCM
            "-ar",
            "16000",  # 16kHz sample rate
            "-ac",
            "1",  # Mono
            str(output_file),
        ]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, cwd=str(temp_path)
            )
            # If no audio stream exists, ffmpeg will fail - that's okay
            if result.returncode != 0:
                logger.debug(f"No audio in chunk or extraction failed: {result.stderr}")
                return b""
        except subprocess.CalledProcessError:
            return b""

        # Read PCM data
        if output_file.exists():
            with open(output_file, "rb") as f:
                return f.read()
        return b""

    finally:
        # Cleanup
        try:
            import shutil

            shutil.rmtree(temp_dir)
        except Exception:
            pass


def stitch_audio_video(
    video_data: bytes, audio_pcm: bytes, audio_sample_rate: int = 24000
) -> bytes:
    """
    Stitch audio (PCM format) with video, replacing the original audio track.

    Args:
        video_data: Video bytes (MP4 format)
        audio_pcm: Audio data in 16-bit PCM format
        audio_sample_rate: Sample rate of the PCM audio (default: 24000 for Gemini output)

    Returns:
        bytes: MP4 video with new audio track

    Raises:
        RuntimeError: If ffmpeg fails to stitch audio and video
    """
    unique_id = uuid.uuid4().hex[:8]
    temp_dir = tempfile.mkdtemp(prefix=f"stitch_{unique_id}_")

    try:
        temp_path = Path(temp_dir)

        # Write video to temp file
        video_file = temp_path / "video.mp4"
        with open(video_file, "wb") as f:
            f.write(video_data)

        # Write PCM audio to temp file
        audio_file = temp_path / "audio.pcm"
        with open(audio_file, "wb") as f:
            f.write(audio_pcm)

        # Stitch using ffmpeg
        output_file = temp_path / "output.mp4"
        cmd = [
            "ffmpeg",
            "-i",
            str(video_file),
            "-f",
            "s16le",  # 16-bit PCM input format
            "-ar",
            str(audio_sample_rate),
            "-ac",
            "1",  # Mono
            "-i",
            str(audio_file),
            "-c:v",
            "copy",  # Copy video stream
            "-c:a",
            "aac",  # Encode audio to AAC
            "-map",
            "0:v:0",  # Video from first input
            "-map",
            "1:a:0",  # Audio from second input
            "-shortest",  # Match shortest stream duration
            str(output_file),
        ]

        try:
            subprocess.run(
                cmd, capture_output=True, text=True, check=True, cwd=str(temp_path)
            )
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to stitch audio and video: {e.stderr}")

        # Read the output
        with open(output_file, "rb") as f:
            return f.read()

    finally:
        # Cleanup
        try:
            import shutil

            shutil.rmtree(temp_dir)
        except Exception:
            pass


def create_fragmented_mp4(video_data: bytes) -> bytes:
    """
    Convert a regular MP4 to a fragmented MP4 (fMP4) suitable for streaming.

    Fragmented MP4s are better for streaming because they can be processed
    incrementally without waiting for the entire file.

    Args:
        video_data: Regular MP4 video bytes

    Returns:
        bytes: Fragmented MP4 video bytes

    Raises:
        RuntimeError: If ffmpeg fails to create fragmented MP4
    """
    unique_id = uuid.uuid4().hex[:8]
    temp_dir = tempfile.mkdtemp(prefix=f"fragment_{unique_id}_")

    try:
        temp_path = Path(temp_dir)

        # Write input video
        input_file = temp_path / "input.mp4"
        with open(input_file, "wb") as f:
            f.write(video_data)

        # Create fragmented MP4
        output_file = temp_path / "output.mp4"
        cmd = [
            "ffmpeg",
            "-i",
            str(input_file),
            "-c",
            "copy",  # Copy streams without re-encoding
            "-movflags",
            "frag_keyframe+empty_moov+default_base_moof",  # Fragmentation flags
            "-f",
            "mp4",
            str(output_file),
        ]

        try:
            subprocess.run(
                cmd, capture_output=True, text=True, check=True, cwd=str(temp_path)
            )
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to create fragmented MP4: {e.stderr}")

        # Read the output
        with open(output_file, "rb") as f:
            return f.read()

    finally:
        # Cleanup
        try:
            import shutil

            shutil.rmtree(temp_dir)
        except Exception:
            pass


async def process_chunks_with_live_api_streaming(
    chunks: list[bytes],
    websocket: Any,
    system_instruction: str = "You are a helpful sports commentator providing live audio commentary.",
    prompt: str = "Provide engaging sports commentary for this video.",
    fps: float = 1.0,
) -> None:
    """
    Process video chunks with Gemini Live API and stream results in real-time.

    This function processes each chunk individually:
    1. Extract frames from a chunk
    2. Send frames to Gemini Live API
    3. Receive audio commentary for that chunk
    4. Stitch audio with the chunk's video
    5. Send fragmented MP4 immediately via websocket
    6. Repeat for next chunk

    Args:
        chunks: List of video chunk bytes (MP4 format)
        websocket: WebSocket connection for streaming output
        system_instruction: System instruction for the Gemini model
        prompt: User prompt for commentary generation
        fps: Frames per second to extract from each chunk (default: 1.0)

    Raises:
        RuntimeError: If processing fails
    """
    logger.info(f"Starting real-time streaming for {len(chunks)} chunks")

    # Initialize Live API client
    client = GeminiLiveClient(system_instruction=system_instruction)

    try:
        # Connect to Live API
        await client.connect()

        # Send initial prompt
        await client.send_text(prompt)

        # Process each chunk in real-time
        for i, chunk in enumerate(chunks):
            logger.info(f"Streaming chunk {i + 1}/{len(chunks)}")

            # Extract frames from chunk
            frames = await asyncio.to_thread(extract_frames_from_chunk, chunk, fps)
            logger.debug(f"Extracted {len(frames)} frames from chunk {i + 1}")

            # Send frames to Live API
            for frame in frames:
                await client.send_video_frame(frame)
                await asyncio.sleep(0.05)  # Small delay

            # Collect audio for this chunk (with timeout to avoid hanging)
            chunk_audio: list[bytes] = []
            try:
                # Use asyncio.wait_for to prevent infinite waiting
                async with asyncio.timeout(10.0):  # 10 second timeout per chunk
                    async for audio_data in client.receive_audio_stream():
                        chunk_audio.append(audio_data)
                        # Break after receiving some audio (heuristic)
                        if (
                            len(chunk_audio) > 10
                        ):  # Adjust based on expected audio length
                            break
            except asyncio.TimeoutError:
                logger.warning(f"Audio timeout for chunk {i + 1}, continuing...")

            if chunk_audio:
                # Concatenate audio for this chunk
                audio_pcm = b"".join(chunk_audio)
                logger.debug(
                    f"Received {len(audio_pcm)} bytes of audio for chunk {i + 1}"
                )

                # Stitch audio with this chunk's video
                stitched_video = await asyncio.to_thread(
                    stitch_audio_video,
                    chunk,
                    audio_pcm,
                    audio_sample_rate=24000,
                )

                # Create fragmented MP4 for streaming
                fragmented_video = await asyncio.to_thread(
                    create_fragmented_mp4, stitched_video
                )

                # Send immediately via websocket
                if hasattr(websocket, "send"):
                    await asyncio.to_thread(websocket.send, fragmented_video)
                else:
                    # Assume it's already async
                    await websocket.send(fragmented_video)

                logger.info(f"Sent chunk {i + 1} ({len(fragmented_video)} bytes)")
            else:
                # No audio received, send original chunk
                logger.warning(f"No audio for chunk {i + 1}, sending original")
                fragmented_video = await asyncio.to_thread(create_fragmented_mp4, chunk)
                if hasattr(websocket, "send"):
                    await asyncio.to_thread(websocket.send, fragmented_video)
                else:
                    await websocket.send(fragmented_video)

        logger.info("Real-time streaming complete")

    finally:
        # Disconnect from Live API
        await client.disconnect()


async def process_chunks_with_live_api(
    chunks: list[bytes],
    websocket: Any,
    system_instruction: str = "You are a helpful sports commentator providing live audio commentary.",
    prompt: str = "Provide engaging sports commentary for this video.",
    fps: float = 1.0,
) -> None:
    """
    Process video chunks with Gemini Live API and stream results via websocket.

    This function:
    1. Takes video chunks (from stream.py format)
    2. Extracts frames from each chunk
    3. Sends frames to Gemini Live API
    4. Receives audio commentary
    5. Stitches audio back with video
    6. Sends fragmented MP4 through websocket

    Args:
        chunks: List of video chunk bytes (MP4 format)
        websocket: WebSocket connection for streaming output
        system_instruction: System instruction for the Gemini model
        prompt: User prompt for commentary generation
        fps: Frames per second to extract from each chunk (default: 1.0)

    Raises:
        RuntimeError: If processing fails
    """
    logger.info(f"Processing {len(chunks)} chunks with Gemini Live API")

    # Initialize Live API client
    client = GeminiLiveClient(system_instruction=system_instruction)

    try:
        # Connect to Live API
        await client.connect()

        # Send initial prompt
        await client.send_text(prompt)

        # Track all audio chunks for the entire video
        all_audio_chunks: list[bytes] = []

        # Process each chunk: extract frames and send to Live API
        for i, chunk in enumerate(chunks):
            logger.info(f"Processing chunk {i + 1}/{len(chunks)}")

            # Extract frames from chunk
            frames = await asyncio.to_thread(extract_frames_from_chunk, chunk, fps)
            logger.debug(f"Extracted {len(frames)} frames from chunk {i + 1}")

            # Send each frame to Live API
            for frame in frames:
                await client.send_video_frame(frame)
                await asyncio.sleep(0.1)  # Small delay to avoid overwhelming API

        # Collect all audio output
        logger.info("Collecting audio commentary from Live API...")
        async for audio_chunk in client.receive_audio_stream():
            all_audio_chunks.append(audio_chunk)

        # Concatenate all audio
        complete_audio_pcm = b"".join(all_audio_chunks)
        logger.info(f"Received {len(complete_audio_pcm)} bytes of audio")

        # Concatenate all video chunks
        concatenated_video = await asyncio.to_thread(concatenate_chunks, chunks)

        # Stitch audio with video
        logger.info("Stitching audio with video...")
        final_video = await asyncio.to_thread(
            stitch_audio_video,
            concatenated_video,
            complete_audio_pcm,
            audio_sample_rate=24000,  # Gemini outputs 24kHz audio
        )

        # Create fragmented MP4 for streaming
        logger.info("Creating fragmented MP4...")
        fragmented_video = await asyncio.to_thread(create_fragmented_mp4, final_video)

        # Send via websocket (handle both sync and async websockets)
        logger.info(f"Sending {len(fragmented_video)} bytes via websocket")
        if hasattr(websocket, "send"):
            # Check if send is a coroutine
            if asyncio.iscoroutinefunction(websocket.send):
                await websocket.send(fragmented_video)
            else:
                await asyncio.to_thread(websocket.send, fragmented_video)
        else:
            # Fallback
            await asyncio.to_thread(websocket.send, fragmented_video)

    finally:
        # Disconnect from Live API
        await client.disconnect()


def concatenate_chunks(chunks: list[bytes]) -> bytes:
    """
    Concatenate multiple video chunks into a single video file.

    Args:
        chunks: List of video chunk bytes

    Returns:
        bytes: Concatenated video data

    Raises:
        RuntimeError: If concatenation fails
    """
    if not chunks:
        return b""

    if len(chunks) == 1:
        return chunks[0]

    unique_id = uuid.uuid4().hex[:8]
    temp_dir = tempfile.mkdtemp(prefix=f"concat_{unique_id}_")

    try:
        temp_path = Path(temp_dir)

        # Write each chunk to a temp file
        chunk_files = []
        for i, chunk in enumerate(chunks):
            chunk_file = temp_path / f"chunk_{i:03d}.mp4"
            with open(chunk_file, "wb") as f:
                f.write(chunk)
            chunk_files.append(chunk_file)

        # Create concat list file
        concat_list = temp_path / "concat_list.txt"
        with open(concat_list, "w") as f:
            for chunk_file in chunk_files:
                f.write(f"file '{chunk_file.name}'\n")

        # Concatenate using ffmpeg
        output_file = temp_path / "output.mp4"
        cmd = [
            "ffmpeg",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_list),
            "-c:v",
            "copy",
            "-c:a",
            "copy",
            str(output_file),
        ]

        subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            cwd=str(temp_path),
        )

        # Read the concatenated result
        with open(output_file, "rb") as f:
            return f.read()

    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to concatenate chunks: {e.stderr}")
        # Fallback: just return the first chunk
        return chunks[0] if chunks else b""
    finally:
        # Cleanup
        try:
            import shutil

            shutil.rmtree(temp_dir)
        except Exception:
            pass
