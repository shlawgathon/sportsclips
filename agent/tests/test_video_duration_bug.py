"""
Test to verify and fix the video duration bug with -shortest flag.

This test creates an 8-second video and 3-second audio, stitches them together,
and verifies that the output video maintains the full 8-second duration
instead of being truncated to 3 seconds by the -shortest flag.
"""

import subprocess
import tempfile
from pathlib import Path

import pytest

from src.live import stitch_audio_video


def test_stitch_audio_video_preserves_video_duration():
    """
    Test that video duration is preserved when audio is shorter.

    This test verifies the fix for the issue where 8-second videos were being
    truncated to match shorter audio commentary (~3-4 seconds) due to the
    -shortest flag in ffmpeg.

    Expected behavior:
    - Input: 8-second video + 3-second audio
    - Output: 8-second video (audio plays for first 3 seconds, then silence)

    Bug behavior (with -shortest flag):
    - Input: 8-second video + 3-second audio
    - Output: 3-second video (truncated to match audio duration)
    """
    # Create a real 8-second test video
    temp_dir = Path(tempfile.mkdtemp(prefix="duration_test_"))

    try:
        # Generate 8-second black video at 30fps
        test_video = temp_dir / "test_8sec.mp4"
        cmd = [
            "ffmpeg",
            "-f",
            "lavfi",
            "-i",
            "color=c=black:s=640x480:d=8",
            "-vf",
            "fps=30",
            "-pix_fmt",
            "yuv420p",
            "-y",  # Overwrite output file
            str(test_video),
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            pytest.skip(f"Failed to create test video: {result.stderr}")

        # Read video data
        with open(test_video, "rb") as f:
            video_data = f.read()

        # Create 3 seconds of fake PCM audio (24kHz, 16-bit mono)
        # 3 seconds * 24000 samples/sec * 2 bytes/sample = 144,000 bytes
        audio_pcm = b"\x00\x01" * (24000 * 3)

        print("\n📹 Test setup:")
        print(f"   Input video: 8 seconds ({len(video_data):,} bytes)")
        print(f"   Input audio: 3 seconds ({len(audio_pcm):,} bytes)")

        # Stitch them together
        stitched_video = stitch_audio_video(video_data, audio_pcm, 24000)

        # Save stitched video for analysis
        output_video = temp_dir / "stitched.mp4"
        with open(output_video, "wb") as f:
            f.write(stitched_video)

        print(f"   Output video: {len(stitched_video):,} bytes")

        # Use ffprobe to check the duration
        ffprobe_cmd = [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(output_video),
        ]

        result = subprocess.run(ffprobe_cmd, capture_output=True, text=True)
        if result.returncode != 0:
            pytest.fail(f"ffprobe failed: {result.stderr}")

        duration = float(result.stdout.strip())
        print("\n📊 Result:")
        print(f"   Output video duration: {duration:.2f} seconds")

        # Check if video and audio streams exist
        stream_cmd = [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(output_video),
        ]

        result = subprocess.run(stream_cmd, capture_output=True, text=True)
        streams = result.stdout.strip().split("\n")
        print(f"   Streams found: {streams}")

        # The bug: with -shortest flag, duration would be ~3 seconds (matching audio)
        # The fix: without -shortest flag, duration should be ~8 seconds (original video)

        if duration < 7.0:
            print(
                f"\n❌ BUG CONFIRMED: Video was truncated to {duration:.2f}s (expected ~8s)"
            )
            print(
                "   Root cause: The -shortest flag in stitch_audio_video() is truncating"
            )
            print("   the video to match the shorter audio duration.")
            print("\n   Fix: Remove the -shortest flag from the ffmpeg command in")
            print("   /home/siyer/docs/sportsclips/agent/src/live.py:145")
            pytest.fail(
                f"Video duration is {duration:.2f}s but should be ~8s. "
                f"The -shortest flag is truncating the video to match the shorter audio."
            )
        else:
            print(
                f"\n✅ PASS: Video duration preserved at {duration:.2f}s (expected ~8s)"
            )
            print(
                "   The video maintains its original duration while audio plays for 3s"
            )
            assert duration >= 7.5, (
                f"Duration should be close to 8s, got {duration:.2f}s"
            )

    finally:
        # Cleanup
        import shutil

        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    # Run the test directly
    test_stitch_audio_video_preserves_video_duration()
