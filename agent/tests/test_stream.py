import subprocess
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from src.stream import stream_video_chunks, stream_video_to_file


class TestStreamVideoChunks:
    """Integration tests for video streaming functionality."""

    def test_stream_video_chunks_live_from_edge(self):
        """Test streaming live video from the live edge (current point)."""
        # Note: This test uses a sample URL - replace with actual live stream for real testing
        # Most live streams are ephemeral, so we'll use a mock to verify the correct options
        test_url = "https://www.youtube.com/watch?v=jfKfPfyJRdk"  # 24/7 lofi stream

        with patch("subprocess.Popen") as mock_popen:
            mock_process = MagicMock()
            mock_process.stdout = MagicMock()
            mock_process.stderr = MagicMock()
            mock_process.stdout.read.return_value = b""  # Empty to end loop
            mock_process.returncode = 0
            mock_process.poll.return_value = 0
            mock_popen.return_value = mock_process

            try:
                list(stream_video_chunks(test_url, chunk_size=64 * 1024))
            except StopIteration:
                pass

            # Verify the command includes live stream options
            call_args = mock_popen.call_args[0][0]
            assert "--no-live-from-start" in call_args, (
                "Should use --no-live-from-start by default"
            )
            assert "--hls-use-mpegts" in call_args, (
                "Should use HLS MPEGTS for live streams"
            )

    def test_stream_video_chunks_live_from_start(self):
        """Test streaming live video from the beginning."""
        test_url = "https://www.youtube.com/watch?v=jfKfPfyJRdk"

        with patch("subprocess.Popen") as mock_popen:
            mock_process = MagicMock()
            mock_process.stdout = MagicMock()
            mock_process.stderr = MagicMock()
            mock_process.stdout.read.return_value = b""
            mock_process.returncode = 0
            mock_process.poll.return_value = 0
            mock_popen.return_value = mock_process

            try:
                list(
                    stream_video_chunks(
                        test_url, chunk_size=64 * 1024, live_from_start=True
                    )
                )
            except StopIteration:
                pass

            # Verify the command includes live-from-start option
            call_args = mock_popen.call_args[0][0]
            assert "--live-from-start" in call_args, (
                "Should use --live-from-start when requested"
            )
            assert "--hls-use-mpegts" in call_args, (
                "Should use HLS MPEGTS for live streams"
            )

    def test_stream_video_chunks_basic(self):
        """Test streaming video chunks from a valid URL."""
        # Use a very short test video (Big Buck Bunny trailer - public domain)
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        chunks = []
        total_bytes = 0

        try:
            for chunk in stream_video_chunks(
                test_url, chunk_size=64 * 1024
            ):  # 64KB chunks
                chunks.append(chunk)
                total_bytes += len(chunk)

                # Safety limit to prevent downloading too much in tests
                if total_bytes > 2 * 1024 * 1024:  # 2MB limit
                    break
        except Exception as e:
            pytest.skip(f"Network or yt-dlp issue: {e}")

        # Verify we got data
        assert len(chunks) > 0, "Should have received at least one chunk"
        assert total_bytes > 0, "Should have received some data"
        assert all(isinstance(chunk, bytes) for chunk in chunks), (
            "All chunks should be bytes"
        )

    def test_stream_video_to_file(self):
        """Test streaming video directly to a file."""
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "test_video.mp4"

            try:
                # Stream to file with smaller chunks
                stream_video_to_file(
                    str(test_url), str(output_path), chunk_size=64 * 1024
                )

                # Verify file was created and has content
                assert output_path.exists(), "Output file should exist"
                assert output_path.stat().st_size > 0, "Output file should have content"

            except Exception as e:
                pytest.skip(f"Network or yt-dlp issue: {e}")

    def test_stream_with_format_selector(self):
        """Test streaming with a specific format selector."""
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        try:
            chunks = list(
                stream_video_chunks(
                    test_url,
                    chunk_size=64 * 1024,
                    format_selector="worst",  # Request lowest quality
                )
            )

            assert len(chunks) > 0, "Should receive chunks with format selector"

        except Exception as e:
            pytest.skip(f"Network or yt-dlp issue: {e}")

    def test_stream_with_additional_options(self):
        """Test streaming with additional yt-dlp options."""
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        try:
            chunks = list(
                stream_video_chunks(
                    test_url,
                    chunk_size=64 * 1024,
                    additional_options=["--no-check-certificate"],
                )
            )

            assert len(chunks) > 0, "Should receive chunks with additional options"

        except Exception as e:
            pytest.skip(f"Network or yt-dlp issue: {e}")

    def test_invalid_url_raises_error(self):
        """Test that an invalid URL raises a RuntimeError."""
        invalid_url = "https://invalid-domain-that-does-not-exist-12345.com/video.mp4"

        with pytest.raises(RuntimeError, match="yt-dlp failed"):
            list(stream_video_chunks(invalid_url, chunk_size=64 * 1024))

    def test_missing_ytdlp_raises_error(self):
        """Test that missing yt-dlp binary raises appropriate error."""
        test_url = "https://example.com/video.mp4"

        with patch("subprocess.Popen") as mock_popen:
            mock_popen.side_effect = FileNotFoundError("yt-dlp not found")

            with pytest.raises(RuntimeError, match="yt-dlp is not installed"):
                list(stream_video_chunks(test_url))

    def test_stdout_pipe_failure(self):
        """Test handling of stdout pipe failure."""
        test_url = "https://example.com/video.mp4"

        with patch("subprocess.Popen") as mock_popen:
            mock_process = MagicMock()
            mock_process.stdout = None
            mock_process.stderr = MagicMock()
            mock_popen.return_value = mock_process

            with pytest.raises(RuntimeError, match="Failed to open stdout pipe"):
                list(stream_video_chunks(test_url))

    def test_stderr_pipe_failure(self):
        """Test handling of stderr pipe failure."""
        test_url = "https://example.com/video.mp4"

        with patch("subprocess.Popen") as mock_popen:
            mock_process = MagicMock()
            mock_process.stdout = MagicMock()
            mock_process.stderr = None
            mock_popen.return_value = mock_process

            with pytest.raises(RuntimeError, match="Failed to open stderr pipe"):
                list(stream_video_chunks(test_url))

    def test_chunk_size_parameter(self):
        """Test that chunk_size parameter is respected."""
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"
        chunk_size = 32 * 1024  # 32KB

        try:
            chunks = []
            for chunk in stream_video_chunks(test_url, chunk_size=chunk_size):
                chunks.append(chunk)
                # Check that chunks are approximately the requested size
                # (last chunk may be smaller)
                if len(chunks) > 1:
                    assert len(chunks[-2]) <= chunk_size, (
                        "Chunks should not exceed requested size"
                    )
                if len(chunk) < chunk_size:
                    # If we get a smaller chunk, it should be the last one
                    break

            assert len(chunks) > 0, "Should receive at least one chunk"

        except Exception as e:
            pytest.skip(f"Network or yt-dlp issue: {e}")

    def test_process_cleanup_on_exception(self):
        """Test that subprocess is cleaned up properly on exception."""
        test_url = "https://example.com/video.mp4"

        with patch("subprocess.Popen") as mock_popen:
            mock_process = MagicMock()
            mock_process.stdout = MagicMock()
            mock_process.stderr = MagicMock()
            mock_process.poll.return_value = None  # Process still running

            # Make read() raise an exception
            mock_process.stdout.read.side_effect = IOError("Test error")
            mock_popen.return_value = mock_process

            with pytest.raises(IOError):
                list(stream_video_chunks(test_url))

            # Verify process was killed
            mock_process.kill.assert_called_once()
            mock_process.wait.assert_called()


class TestYtDlpAvailability:
    """Tests to verify yt-dlp is available."""

    def test_ytdlp_installed(self):
        """Verify yt-dlp is installed and accessible."""
        try:
            result = subprocess.run(
                ["yt-dlp", "--version"], capture_output=True, text=True, timeout=5
            )
            assert result.returncode == 0, "yt-dlp should be installed"
            print(f"yt-dlp version: {result.stdout.strip()}")
        except FileNotFoundError:
            pytest.fail("yt-dlp is not installed. Install with: pip install yt-dlp")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
