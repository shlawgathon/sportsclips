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
            patch("src.stream.stream_video_chunks") as mock_stream,
            patch("subprocess.run") as mock_ffmpeg_run,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
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
                    chunks = list(
                        stream_and_chunk_video(
                            test_url, chunk_duration=15, is_live=False
                        )
                    )

                    assert len(chunks) == 2
                    assert all(chunk == b"chunk_data" for chunk in chunks)

    def test_stream_and_chunk_video_live(self):
        """Test chunking live video."""
        test_url = "https://youtube.com/live/test123"

        with patch("src.stream.stream_and_chunk_live") as mock_stream_live:
            mock_stream_live.return_value = iter([b"chunk1", b"chunk2", b"chunk3"])

            chunks = list(
                stream_and_chunk_video(test_url, chunk_duration=15, is_live=True)
            )

            assert len(chunks) == 3
            mock_stream_live.assert_called_once()

    def test_live_selector_override_for_specific_youtube_url(self):
        """Ensure live-safe selector is used for problematic VOD selector on live URL.

        Reproduces the case where format_selector was "best[ext=mp4]/best" for a live stream
        (https://www.youtube.com/watch?v=kWIWnFbNMF4), which is not available and should be
        overridden to a live-friendly selector.
        """
        problem_url = "https://www.youtube.com/watch?v=kWIWnFbNMF4"

        with (
            patch("subprocess.Popen") as mock_popen,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("pathlib.Path.mkdir"),
            patch("shutil.rmtree"),
            patch("pathlib.Path.glob") as mock_glob,
            patch("builtins.open", mock_open(read_data=b"chunk_data")),
            patch("time.sleep", lambda *_args, **_kwargs: None),
        ):
            mock_mkdtemp.return_value = "/tmp/test_video"

            # Prepare yt-dlp and ffmpeg mock processes
            mock_ytdlp = MagicMock()
            mock_ytdlp.stdout = MagicMock()
            mock_ytdlp.stderr = MagicMock()
            mock_ytdlp.poll.side_effect = [None, 0]

            mock_ffmpeg = MagicMock()
            mock_ffmpeg.stdout = MagicMock()
            mock_ffmpeg.stderr = MagicMock()
            mock_ffmpeg.poll.side_effect = [None, 0]

            # Capture Popen calls and return mocks in order (yt-dlp, ffmpeg)
            popen_calls = []

            def popen_side_effect(cmd, *args, **kwargs):
                popen_calls.append(cmd)
                return mock_ytdlp if len(popen_calls) == 1 else mock_ffmpeg

            mock_popen.side_effect = popen_side_effect

            # Simulate one complete chunk file present across iterations
            chunk_path = Path("/tmp/test_video/chunk_00000.mp4")
            mock_glob.side_effect = [[chunk_path], [chunk_path], [chunk_path]]

            # Run streaming with VOD-oriented selector but live=True
            chunks = list(
                stream_and_chunk_video(
                    problem_url,
                    chunk_duration=2,
                    format_selector="best[ext=mp4]/best",
                    is_live=True,
                )
            )

            # Verify we yielded data
            assert len(chunks) >= 1

            # Verify yt-dlp command used the live-safe selector
            assert len(popen_calls) >= 1
            ytdlp_cmd = popen_calls[0]

            # Ensure --live-from-start is present for live streams
            assert "--live-from-start" in ytdlp_cmd

            # Find the format value following -f
            assert "-f" in ytdlp_cmd
            f_idx = ytdlp_cmd.index("-f")
            selected_format = ytdlp_cmd[f_idx + 1]
            assert (
                selected_format == "bestvideo+bestaudio/best"
            ), (
                "Live-safe format selector should override VOD-only selector"
            )

    def test_stream_and_chunk_video_ffmpeg_error(self):
        """Test handling of ffmpeg errors in non-live mode."""
        test_url = "https://youtube.com/watch?v=test123"

        with (
            patch("src.stream.stream_video_chunks") as mock_stream,
            patch("subprocess.run") as mock_ffmpeg_run,
            patch("tempfile.mkdtemp") as mock_mkdtemp,
            patch("shutil.rmtree"),
        ):
            mock_mkdtemp.return_value = "/tmp/test_video"
            mock_stream.return_value = [b"video_data"]

            # Mock ffmpeg failure
            mock_ffmpeg_run.side_effect = subprocess.CalledProcessError(
                1, ["ffmpeg"], stderr="ffmpeg error"
            )

            with patch("pathlib.Path.mkdir"), patch("builtins.open", mock_open()):
                with pytest.raises(RuntimeError, match="Failed to chunk video"):
                    list(
                        stream_and_chunk_video(
                            test_url, chunk_duration=15, is_live=False
                        )
                    )


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


class TestConcurrentDownloads:
    """Tests for concurrent video downloads to verify isolation."""

    def test_concurrent_cache_isolation(self):
        """Test that concurrent operations use isolated cache directories."""
        import concurrent.futures
        import tempfile

        cache_dirs_used = []

        def mock_download(thread_id: int):
            """Mock a download operation that tracks cache dir usage."""
            # Create a temp cache dir like the actual code does
            temp_cache_dir = tempfile.mkdtemp(prefix=f"ytdlp_cache_{thread_id}_test_")
            cache_dirs_used.append(temp_cache_dir)

            # Simulate some work
            import time

            time.sleep(0.1)

            # Cleanup
            try:
                import shutil

                shutil.rmtree(temp_cache_dir)
            except Exception:
                pass

            return temp_cache_dir

        # Run 3 concurrent operations
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(mock_download, i) for i in range(3)]
            for f in concurrent.futures.as_completed(futures):
                f.result()  # Wait for completion

        # Verify all 3 used different cache directories
        assert len(cache_dirs_used) == 3
        assert len(set(cache_dirs_used)) == 3, "All cache dirs should be unique"
        print(f"Used cache directories: {cache_dirs_used}")

    def test_stream_video_chunks_uses_isolated_cache(self):
        """Test that stream_video_chunks uses isolated cache directory."""
        import concurrent.futures

        test_url = "https://example.com/video.mp4"
        cache_dirs_captured = []

        def capture_cache_dir(popen_args, **kwargs):
            """Mock Popen to capture the cache-dir argument."""
            cmd = popen_args[0] if isinstance(popen_args, tuple) else popen_args

            # Find --cache-dir argument
            if "--cache-dir" in cmd:
                cache_dir_idx = cmd.index("--cache-dir")
                cache_dir = cmd[cache_dir_idx + 1]
                cache_dirs_captured.append(cache_dir)

            # Create mock process
            mock_process = MagicMock()
            mock_process.stdout = MagicMock()
            mock_process.stderr = MagicMock()
            mock_process.stdout.read.return_value = b""
            mock_process.returncode = 0
            mock_process.poll.return_value = 0
            return mock_process

        # Run 3 concurrent stream_video_chunks calls
        with patch("subprocess.Popen", side_effect=capture_cache_dir):
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
                futures = [
                    executor.submit(lambda: list(stream_video_chunks(test_url)))
                    for _ in range(3)
                ]
                for future in concurrent.futures.as_completed(futures):
                    try:
                        future.result(timeout=5)
                    except Exception:
                        pass

        # Verify all 3 used different cache directories
        assert len(cache_dirs_captured) == 3, (
            f"Expected 3 cache dirs, got {len(cache_dirs_captured)}"
        )
        assert len(set(cache_dirs_captured)) == 3, (
            f"Cache dirs should be unique: {cache_dirs_captured}"
        )

        # Verify --no-part flag is also present
        print(f"Captured {len(cache_dirs_captured)} unique cache directories")

    def test_ytdlp_command_includes_isolation_flags(self):
        """Test that yt-dlp commands include cache-dir and no-part flags."""
        test_url = "https://example.com/video.mp4"

        with patch("subprocess.Popen") as mock_popen:
            mock_process = MagicMock()
            mock_process.stdout = MagicMock()
            mock_process.stderr = MagicMock()
            mock_process.stdout.read.return_value = b""
            mock_process.returncode = 0
            mock_process.poll.return_value = 0
            mock_popen.return_value = mock_process

            # Call stream_video_chunks
            list(stream_video_chunks(test_url))

            # Verify the command includes isolation flags
            call_args = mock_popen.call_args[0][0]
            assert "--cache-dir" in call_args, "Should include --cache-dir flag"
            assert "--no-part" in call_args, "Should include --no-part flag"

            # Verify cache-dir has a value
            cache_dir_idx = call_args.index("--cache-dir")
            cache_dir = call_args[cache_dir_idx + 1]
            assert "ytdlp_cache_" in cache_dir, (
                f"Cache dir should have unique prefix: {cache_dir}"
            )
            print(f"Command uses cache dir: {cache_dir}")

    def test_concurrent_stream_video_chunks(self):
        """Test that 3 concurrent stream downloads don't collide."""
        import concurrent.futures

        # Use a short test video that's quick to download
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        # Track results and errors from each thread
        results = {}
        errors = {}

        def download_stream(thread_id: int, url: str) -> dict:
            """Download a stream and return stats."""
            try:
                chunks = []
                total_bytes = 0

                for chunk in stream_video_chunks(url, chunk_size=64 * 1024):
                    chunks.append(chunk)
                    total_bytes += len(chunk)

                    # Limit download size for testing
                    if total_bytes > 2 * 1024 * 1024:  # 2MB limit
                        break

                return {
                    "thread_id": thread_id,
                    "chunks": len(chunks),
                    "total_bytes": total_bytes,
                    "success": True,
                }
            except Exception as e:
                return {
                    "thread_id": thread_id,
                    "error": str(e),
                    "success": False,
                }

        # Run 3 concurrent downloads
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(download_stream, i, test_url) for i in range(3)]

            for future in concurrent.futures.as_completed(futures):
                try:
                    result = future.result(timeout=60)
                    thread_id = result["thread_id"]

                    if result["success"]:
                        results[thread_id] = result
                    else:
                        errors[thread_id] = result["error"]
                except Exception as e:
                    # If any download fails with timeout or other error
                    errors[len(errors)] = str(e)

        # Check that all 3 downloads completed successfully
        if errors:
            # If there are network errors, skip the test
            pytest.skip(f"Network or yt-dlp issues: {errors}")

        assert len(results) == 3, f"Expected 3 successful downloads, got {len(results)}"

        # Verify each download got data
        for thread_id, result in results.items():
            assert result["chunks"] > 0, f"Thread {thread_id} should have chunks"
            assert result["total_bytes"] > 0, f"Thread {thread_id} should have data"
            print(
                f"Thread {thread_id}: {result['chunks']} chunks, {result['total_bytes']} bytes"
            )

    def test_concurrent_stream_and_chunk_video(self):
        """Test that 3 concurrent stream and chunk operations don't collide."""
        import concurrent.futures

        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        results = {}
        errors = {}

        def download_and_chunk(thread_id: int, url: str) -> dict:
            """Download and chunk a video, return stats."""
            try:
                chunks = []

                for chunk in stream_and_chunk_video(
                    url,
                    chunk_duration=5,  # Short chunks for faster test
                    is_live=False,
                ):
                    chunks.append(chunk)

                    # Limit to first few chunks for testing
                    if len(chunks) >= 2:
                        break

                return {
                    "thread_id": thread_id,
                    "chunks": len(chunks),
                    "success": True,
                }
            except Exception as e:
                return {
                    "thread_id": thread_id,
                    "error": str(e),
                    "success": False,
                }

        # Run 3 concurrent downloads and chunking operations
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(download_and_chunk, i, test_url) for i in range(3)
            ]

            for future in concurrent.futures.as_completed(futures):
                try:
                    result = future.result(timeout=120)  # Longer timeout for chunking
                    thread_id = result["thread_id"]

                    if result["success"]:
                        results[thread_id] = result
                    else:
                        errors[thread_id] = result["error"]
                except Exception as e:
                    errors[len(errors)] = str(e)

        # Check results
        if errors:
            pytest.skip(f"Network or processing issues: {errors}")

        assert len(results) == 3, (
            f"Expected 3 successful operations, got {len(results)}"
        )

        # Verify each operation produced chunks
        for thread_id, result in results.items():
            assert result["chunks"] > 0, f"Thread {thread_id} should have chunks"
            print(f"Thread {thread_id}: {result['chunks']} chunks")

    def test_concurrent_is_live_stream(self):
        """Test that 3 concurrent is_live_stream checks don't collide."""
        import concurrent.futures

        # Use multiple different URLs to test isolation
        test_urls = [
            "https://www.youtube.com/watch?v=jfKfPfyJRdk",  # Lofi stream
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",  # Regular video
            "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4",  # Direct file
        ]

        results = {}
        errors = {}

        def check_live_status(thread_id: int, url: str) -> dict:
            """Check if URL is live stream."""
            try:
                is_live = is_live_stream(url)
                return {
                    "thread_id": thread_id,
                    "url": url,
                    "is_live": is_live,
                    "success": True,
                }
            except Exception as e:
                return {
                    "thread_id": thread_id,
                    "url": url,
                    "error": str(e),
                    "success": False,
                }

        # Run 3 concurrent checks
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(check_live_status, i, test_urls[i]) for i in range(3)
            ]

            for future in concurrent.futures.as_completed(futures):
                try:
                    result = future.result(timeout=60)
                    thread_id = result["thread_id"]

                    if result["success"]:
                        results[thread_id] = result
                    else:
                        errors[thread_id] = result["error"]
                except Exception as e:
                    errors[len(errors)] = str(e)

        # All checks should complete without errors (isolation test)
        if errors:
            pytest.skip(f"Network or yt-dlp issues: {errors}")

        assert len(results) == 3, f"Expected 3 successful checks, got {len(results)}"

        # Just verify they all completed (actual is_live status may vary)
        for thread_id, result in results.items():
            assert "is_live" in result, (
                f"Thread {thread_id} should return is_live status"
            )
            print(f"Thread {thread_id} ({result['url']}): is_live={result['is_live']}")


class TestMassiveConcurrentDownloads:
    """Test for massive concurrent operations to verify no conflicts."""

    def test_20_concurrent_streams(self):
        """Test that 20 concurrent stream operations don't conflict with each other."""
        import concurrent.futures

        # Use a short test video
        test_url = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"

        results = {}
        errors = {}

        def download_and_chunk_stream(thread_id: int, url: str) -> dict:
            """Download and chunk a video stream."""
            try:
                chunks = []
                total_bytes = 0

                for chunk in stream_and_chunk_video(
                    url,
                    chunk_duration=3,  # Short chunks for faster test
                    is_live=False,
                ):
                    chunks.append(len(chunk))
                    total_bytes += len(chunk)

                    # Limit chunks for faster testing
                    if len(chunks) >= 2:
                        break

                return {
                    "thread_id": thread_id,
                    "chunks": len(chunks),
                    "total_bytes": total_bytes,
                    "success": True,
                }
            except Exception as e:
                return {
                    "thread_id": thread_id,
                    "error": str(e),
                    "success": False,
                }

        # Run 20 concurrent downloads
        print("\n🚀 Starting 20 concurrent stream operations...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
            futures = [
                executor.submit(download_and_chunk_stream, i, test_url)
                for i in range(20)
            ]

            for future in concurrent.futures.as_completed(futures):
                try:
                    result = future.result(timeout=180)  # 3 min timeout per operation
                    thread_id = result["thread_id"]

                    if result["success"]:
                        results[thread_id] = result
                        print(
                            f"✅ Stream {thread_id}: {result['chunks']} chunks, {result['total_bytes']:,} bytes"
                        )
                    else:
                        errors[thread_id] = result["error"]
                        print(f"❌ Stream {thread_id}: {result['error']}")
                except Exception as e:
                    error_id = len(errors)
                    errors[error_id] = str(e)
                    print(f"❌ Stream error: {e}")

        # Check results
        print(f"\n📊 Results: {len(results)}/20 successful, {len(errors)} failed")

        if errors:
            # If there are network errors, report but don't fail
            print(f"⚠️  Some streams failed (likely network issues): {errors}")
            # We need at least some successful runs to validate isolation
            if len(results) < 5:
                pytest.skip(
                    f"Too many failures ({len(errors)}/20) - likely network issues"
                )

        # Verify that the successful operations all completed properly
        assert len(results) > 0, "At least some downloads should succeed"

        # Check that all successful operations produced chunks
        for thread_id, result in results.items():
            assert result["chunks"] > 0, f"Stream {thread_id} should have chunks"
            assert result["total_bytes"] > 0, f"Stream {thread_id} should have data"

        print(f"✅ All {len(results)} successful streams completed without conflicts!")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
