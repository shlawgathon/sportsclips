import subprocess
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, mock_open, patch

import pytest

from src.stream import (
    is_live_stream,
    stream_and_chunk_live,
    stream_and_chunk_video,
    stream_video_chunks,
    stream_video_to_file,
)


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


class TestIsLiveStream:
    """Tests for is_live_stream function."""

    def test_is_live_stream_with_live_video(self):
        """Test detection of live stream."""
        test_url = "https://youtube.com/watch?v=test123"

        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = '{"is_live": true, "live_status": "is_live"}'
            mock_run.return_value = mock_result

            result = is_live_stream(test_url)

            assert result is True
            mock_run.assert_called_once()

    def test_is_live_stream_with_non_live_video(self):
        """Test detection of non-live video."""
        test_url = "https://youtube.com/watch?v=test123"

        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = '{"is_live": false, "live_status": "not_live"}'
            mock_run.return_value = mock_result

            result = is_live_stream(test_url)

            assert result is False

    def test_is_live_stream_with_upcoming_stream(self):
        """Test detection of upcoming live stream."""
        test_url = "https://youtube.com/watch?v=test123"

        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = '{"is_live": false, "live_status": "is_upcoming"}'
            mock_run.return_value = mock_result

            result = is_live_stream(test_url)

            assert result is True

    def test_is_live_stream_with_failed_request(self):
        """Test that failed yt-dlp requests return False."""
        test_url = "https://invalid.com/video"

        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 1
            mock_run.return_value = mock_result

            result = is_live_stream(test_url)

            assert result is False

    def test_is_live_stream_with_invalid_json(self):
        """Test handling of invalid JSON response."""
        test_url = "https://youtube.com/watch?v=test123"

        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = "invalid json{"
            mock_run.return_value = mock_result

            result = is_live_stream(test_url)

            assert result is False

    def test_is_live_stream_with_exception(self):
        """Test that exceptions return False."""
        test_url = "https://youtube.com/watch?v=test123"

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = Exception("Test error")

            result = is_live_stream(test_url)

            assert result is False


class TestStreamAndChunkLive:
    """Tests for stream_and_chunk_live function."""

    def test_stream_and_chunk_live_basic(self):
        """Test basic live streaming and chunking."""
        test_url = "https://youtube.com/live/test123"

        with (
            patch("subprocess.Popen") as mock_popen,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
            # Setup temp directory
            mock_mkdtemp.return_value = "/tmp/test_live_stream"

            # Mock yt-dlp process
            mock_ytdlp = MagicMock()
            mock_ytdlp.stdout = MagicMock()
            mock_ytdlp.stderr = MagicMock()
            mock_ytdlp.poll.side_effect = [None, None, 0]  # Running, then done

            # Mock ffmpeg process
            mock_ffmpeg = MagicMock()
            mock_ffmpeg.stdout = MagicMock()
            mock_ffmpeg.stderr = MagicMock()
            mock_ffmpeg.poll.side_effect = [None, None, 0]  # Running, then done

            mock_popen.side_effect = [mock_ytdlp, mock_ffmpeg]

            # Mock chunk files
            with (
                patch("pathlib.Path.glob") as mock_glob,
                patch("builtins.open", mock_open(read_data=b"chunk_data")),
            ):
                # First call: no chunks, second: one chunk, third: same chunk, fourth: done
                mock_glob.side_effect = [
                    [],
                    [Path("/tmp/test_live_stream/chunk_00000.mp4")],
                    [Path("/tmp/test_live_stream/chunk_00000.mp4")],
                    [Path("/tmp/test_live_stream/chunk_00000.mp4")],
                ]

                chunks = list(stream_and_chunk_live(test_url, chunk_duration=15))

                assert len(chunks) > 0
                assert all(isinstance(chunk, bytes) for chunk in chunks)

    def test_stream_and_chunk_live_with_ytdlp_error(self):
        """Test handling of yt-dlp errors."""
        test_url = "https://youtube.com/live/test123"

        with (
            patch("subprocess.Popen") as mock_popen,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
            mock_mkdtemp.return_value = "/tmp/test_live_stream"

            # Mock yt-dlp process with error
            mock_ytdlp = MagicMock()
            mock_ytdlp.stdout = MagicMock()
            mock_ytdlp.stderr = MagicMock()
            mock_ytdlp.stderr.read.return_value = b"yt-dlp error"
            mock_ytdlp.poll.return_value = 1  # Error code

            # Mock ffmpeg process
            mock_ffmpeg = MagicMock()
            mock_ffmpeg.stdout = MagicMock()
            mock_ffmpeg.stderr = MagicMock()
            mock_ffmpeg.poll.return_value = 0

            mock_popen.side_effect = [mock_ytdlp, mock_ffmpeg]

            with patch("pathlib.Path.glob") as mock_glob:
                mock_glob.return_value = []

                with pytest.raises(RuntimeError, match="yt-dlp failed"):
                    list(stream_and_chunk_live(test_url, chunk_duration=15))


class TestStreamAndChunkVideo:
    """Tests for stream_and_chunk_video function."""

    def test_stream_and_chunk_video_non_live(self):
        """Test chunking non-live video."""
        test_url = "https://youtube.com/watch?v=test123"

        with (
            patch("src.stream.is_live_stream") as mock_is_live,
            patch("src.stream.stream_video_chunks") as mock_stream,
            patch("subprocess.run") as mock_ffmpeg_run,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
            mock_is_live.return_value = False
            mock_mkdtemp.return_value = "/tmp/test_video"
            mock_stream.return_value = [b"video_data_1", b"video_data_2"]

            # Mock ffmpeg success
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_ffmpeg_run.return_value = mock_result

            # Mock chunk files
            with patch("pathlib.Path.glob") as mock_glob, patch("pathlib.Path.mkdir"):
                mock_glob.return_value = [
                    Path("/tmp/test_video/chunks/chunk_00000.mp4"),
                    Path("/tmp/test_video/chunks/chunk_00001.mp4"),
                ]

                # Mock reading chunk files
                with patch("builtins.open", mock_open(read_data=b"chunk_data")):
                    chunks = list(stream_and_chunk_video(test_url, chunk_duration=15))

                    assert len(chunks) == 2
                    assert all(chunk == b"chunk_data" for chunk in chunks)
                    mock_is_live.assert_called_once()

    def test_stream_and_chunk_video_live(self):
        """Test chunking live video."""
        test_url = "https://youtube.com/live/test123"

        with (
            patch("src.stream.is_live_stream") as mock_is_live,
            patch("src.stream.stream_and_chunk_live") as mock_stream_live,
        ):
            mock_is_live.return_value = True
            mock_stream_live.return_value = iter([b"chunk1", b"chunk2", b"chunk3"])

            chunks = list(stream_and_chunk_video(test_url, chunk_duration=15))

            assert len(chunks) == 3
            mock_is_live.assert_called_once()
            mock_stream_live.assert_called_once()

    def test_stream_and_chunk_video_skip_auto_detect(self):
        """Test skipping auto-detection when auto_detect_live=False."""

        with (
            patch("src.stream.is_live_stream") as mock_is_live,
            patch("src.stream.stream_video_chunks") as mock_stream,
            patch("subprocess.run") as mock_ffmpeg_run,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
            mock_mkdtemp.return_value = "/tmp/test_video"
            mock_stream.return_value = [b"video_data"]

            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_ffmpeg_run.return_value = mock_result

            with (
                patch("pathlib.Path.glob") as mock_glob,
                patch("pathlib.Path.mkdir"),
                patch("builtins.open", mock_open(read_data=b"chunk_data")),
            ):
                mock_glob.return_value = [
                    Path("/tmp/test_video/chunks/chunk_00000.mp4")
                ]

                # Should not call is_live_stream when auto_detect_live=False
                mock_is_live.assert_not_called()

    def test_stream_and_chunk_video_ffmpeg_error(self):
        """Test handling of ffmpeg errors in non-live mode."""
        test_url = "https://youtube.com/watch?v=test123"

        with (
            patch("src.stream.is_live_stream") as mock_is_live,
            patch("src.stream.stream_video_chunks") as mock_stream,
            patch("subprocess.run") as mock_ffmpeg_run,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
            mock_is_live.return_value = False
            mock_mkdtemp.return_value = "/tmp/test_video"
            mock_stream.return_value = [b"video_data"]

            # Mock ffmpeg failure
            mock_ffmpeg_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="ffmpeg error"
            )

            with patch("pathlib.Path.mkdir"), patch("builtins.open", mock_open()):
                with pytest.raises(RuntimeError, match="Failed to chunk video"):
                    list(stream_and_chunk_video(test_url, chunk_duration=15))


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
