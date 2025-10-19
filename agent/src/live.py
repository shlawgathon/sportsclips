"""
Live video processing utilities.

This module provides functionality to process video chunks:
- Extract frames from video chunks
- Stitch audio with video
- Create fragmented MP4s for streaming
"""

import logging
import subprocess
import tempfile
import uuid
from pathlib import Path

from PIL import Image

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


