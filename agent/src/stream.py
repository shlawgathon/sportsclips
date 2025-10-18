import json
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Generator


def get_cookies_path() -> str | None:
    """
    Get the path to the cookies.txt file if it exists.

    Returns:
        str | None: Path to cookies.txt if found, None otherwise
    """
    # Look for cookies.txt in the agent directory
    agent_dir = Path(__file__).parent.parent
    cookies_path = agent_dir / "cookies.txt"

    if cookies_path.exists():
        return str(cookies_path)

    return None


def is_live_stream(url: str) -> bool:
    """
    Check if a URL points to a live stream.

    Args:
        url: The video URL to check

    Returns:
        bool: True if the stream is live, False otherwise
    """
    # Create isolated cache directory for this yt-dlp instance
    temp_cache_dir = tempfile.mkdtemp(prefix=f"ytdlp_cache_{uuid.uuid4().hex[:8]}_")

    try:
        cmd = [
            "yt-dlp",
            "--dump-json",
            "--playlist-items",
            "1",
            "--no-warnings",
            "--quiet",
            "--cache-dir",
            temp_cache_dir,  # Use isolated cache directory
            "--no-part",  # Don't use .part files to avoid collisions
        ]

        # Add cookies if available
        cookies_path = get_cookies_path()
        if cookies_path:
            cmd.extend(["--cookies", cookies_path])

        cmd.append(url)

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode != 0:
            # If we can't determine, assume not live
            return False

        # Parse the JSON output
        try:
            info = json.loads(result.stdout)
            # Check various indicators that a stream is live
            is_live = info.get("is_live", False)
            live_status = info.get("live_status", "")

            return is_live or live_status in ["is_live", "is_upcoming"]
        except json.JSONDecodeError:
            return False

    except Exception:
        # If anything fails, assume not live
        return False
    finally:
        # Cleanup isolated cache directory
        try:
            import shutil

            shutil.rmtree(temp_cache_dir)
        except Exception:
            pass


def stream_and_chunk_live(
    url: str,
    chunk_duration: int = 15,
    format_selector: str = "best[ext=mp4]/best",
    additional_options: list[str] | None = None,
) -> Generator[bytes, None, None]:
    """
    Stream a live video and yield fixed-duration chunks in real-time using ffmpeg.

    For live streams, this will:
    1. Download all existing content up to the current live point
    2. Split it into chunks and yield them quickly
    3. Continue to chunk new content in real-time as the stream progresses

    Args:
        url: The live stream URL
        chunk_duration: Duration of each chunk in seconds (default: 15)
        format_selector: yt-dlp format selector (default: "best")
        additional_options: Additional yt-dlp command-line options

    Yields:
        bytes: Video chunk data (complete MP4 files)
    """
    # Create unique temp directory with UUID to avoid collisions
    unique_id = uuid.uuid4().hex[:8]
    temp_dir = tempfile.mkdtemp(prefix=f"live_stream_{unique_id}_")

    try:
        temp_path = Path(temp_dir)

        # Create isolated cache directory for this yt-dlp instance
        cache_dir = temp_path / "yt-dlp-cache"
        cache_dir.mkdir()

        # Build yt-dlp command to stream from live start
        ytdlp_cmd = [
            "yt-dlp",
            "--live-from-start",  # Start from beginning of live stream
            "-o",
            "-",  # Output to stdout
            "--quiet",
            "--no-warnings",
            "--cache-dir",
            str(cache_dir),  # Use isolated cache directory
            "--no-part",  # Don't use .part files to avoid collisions
        ]

        # Add cookies if available
        cookies_path = get_cookies_path()
        if cookies_path:
            ytdlp_cmd.extend(["--cookies", cookies_path])

        # Only add format selector if it's not the default
        # Live streams with --live-from-start work best without explicit format selection
        # as yt-dlp will choose appropriate DASH formats automatically
        if format_selector and format_selector != "best[ext=mp4]/best":
            ytdlp_cmd.extend(["-f", format_selector])

        if additional_options:
            ytdlp_cmd.extend(additional_options)

        ytdlp_cmd.append(url)

        # Build ffmpeg command to chunk the stream in real-time
        output_pattern = temp_path / "chunk_%05d.mp4"
        ffmpeg_cmd = [
            "ffmpeg",
            "-i",
            "pipe:0",  # Read from stdin
            "-c",
            "copy",  # Copy without re-encoding
            "-f",
            "segment",
            "-segment_time",
            str(chunk_duration),
            "-segment_format",
            "mp4",
            "-reset_timestamps",
            "1",
            "-strftime",
            "0",
            "-segment_list",
            str(temp_path / "segments.txt"),
            "-segment_list_flags",
            "live",
            str(output_pattern),
        ]

        # Start yt-dlp process
        ytdlp_process = subprocess.Popen(
            ytdlp_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Start ffmpeg process, reading from yt-dlp's output
        # Use temp_dir as cwd to prevent -Frag files from conflicting in concurrent operations
        ffmpeg_process = subprocess.Popen(
            ffmpeg_cmd,
            stdin=ytdlp_process.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=temp_dir,
        )

        # Close yt-dlp stdout in parent to allow proper pipe behavior
        if ytdlp_process.stdout:
            ytdlp_process.stdout.close()

        # Track which chunks we've already yielded
        yielded_chunks = set()

        # Keep monitoring for new chunks until the stream ends
        while True:
            # Check if processes are still running
            ytdlp_status = ytdlp_process.poll()
            ffmpeg_status = ffmpeg_process.poll()

            # Find all chunk files
            chunk_files = sorted(temp_path.glob("chunk_*.mp4"))

            # Yield any new chunks
            for chunk_file in chunk_files:
                if chunk_file not in yielded_chunks:
                    # Wait a moment to ensure the chunk is complete
                    # (ffmpeg may still be writing to it)
                    import time

                    time.sleep(0.5)

                    # Check if this is likely the last/current chunk being written
                    # by seeing if there's a newer chunk
                    newer_chunks = [f for f in chunk_files if f > chunk_file]
                    if newer_chunks or ffmpeg_status is not None:
                        # This chunk is complete, read and yield it
                        try:
                            with open(chunk_file, "rb") as f:
                                chunk_data = f.read()

                            if chunk_data:
                                yielded_chunks.add(chunk_file)
                                yield chunk_data
                        except Exception:
                            # If we can't read the chunk, skip it
                            pass

            # If both processes have ended, yield any remaining chunks and exit
            if ytdlp_status is not None and ffmpeg_status is not None:
                # Give ffmpeg a moment to finish writing the last chunk
                import time

                time.sleep(1)

                # Yield any final chunks
                final_chunks = sorted(temp_path.glob("chunk_*.mp4"))
                for chunk_file in final_chunks:
                    if chunk_file not in yielded_chunks:
                        try:
                            with open(chunk_file, "rb") as f:
                                chunk_data = f.read()
                            if chunk_data:
                                yield chunk_data
                        except Exception:
                            pass

                break

            # Sleep briefly before checking again
            import time

            time.sleep(2)

        # Check for errors
        if ytdlp_status != 0:
            stderr = (
                ytdlp_process.stderr.read().decode("utf-8")
                if ytdlp_process.stderr
                else ""
            )
            raise RuntimeError(
                f"yt-dlp failed with return code {ytdlp_status}: {stderr}"
            )

        if ffmpeg_status != 0:
            stderr = (
                ffmpeg_process.stderr.read().decode("utf-8")
                if ffmpeg_process.stderr
                else ""
            )
            raise RuntimeError(
                f"ffmpeg failed with return code {ffmpeg_status}: {stderr}"
            )

    finally:
        # Cleanup
        try:
            import shutil

            shutil.rmtree(temp_dir)
        except Exception:
            pass


def stream_video_chunks(
    url: str,
    chunk_size: int = 1024 * 1024,  # 1MB chunks by default
    format_selector: str = "best",
    additional_options: list[str] | None = None,
    live_from_start: bool = False,
) -> Generator[bytes, None, None]:
    """
    Stream video chunks from a URL using yt-dlp.

    Args:
        url: The video URL to stream from
        chunk_size: Size of each chunk to yield in bytes (default: 1MB)
        format_selector: yt-dlp format selector (default: "best")
        additional_options: Additional yt-dlp command-line options
        live_from_start: For live streams, start from beginning instead of live edge.
                        Default False (jumps to live edge for live videos)

    Yields:
        bytes: Video data chunks

    Example:
        >>> # Stream regular video
        >>> for chunk in stream_video_chunks("https://example.com/video"):
        ...     # Process or write chunk
        ...     pass

        >>> # Stream live video from current point (default)
        >>> for chunk in stream_video_chunks("https://youtube.com/live/..."):
        ...     # Gets chunks from live edge
        ...     pass

        >>> # Stream live video from start
        >>> for chunk in stream_video_chunks("https://youtube.com/live/...", live_from_start=True):
        ...     # Gets chunks from beginning of stream
        ...     pass
    """
    # Create isolated cache directory for this yt-dlp instance
    temp_cache_dir = tempfile.mkdtemp(prefix=f"ytdlp_cache_{uuid.uuid4().hex[:8]}_")

    try:
        # Build yt-dlp command
        cmd = [
            "yt-dlp",
            "-f",
            format_selector,
            "-o",
            "-",  # Output to stdout
            "--quiet",  # Suppress yt-dlp output
            "--no-warnings",
            "--cache-dir",
            temp_cache_dir,  # Use isolated cache directory
            "--no-part",  # Don't use .part files to avoid collisions
        ]

        # Add cookies if available
        cookies_path = get_cookies_path()
        if cookies_path:
            cmd.extend(["--cookies", cookies_path])

        # Add live stream handling options
        if live_from_start:
            cmd.append("--live-from-start")
        else:
            # Default: jump to live edge for live streams
            cmd.append("--no-live-from-start")

        # Add HLS/MPEGTS support for live streams
        cmd.append("--hls-use-mpegts")

        # Add any additional options
        if additional_options:
            cmd.extend(additional_options)

        cmd.append(url)

        try:
            # Start yt-dlp process with stdout as pipe
            process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=chunk_size
            )

            # Ensure stdout is available
            if process.stdout is None:
                raise RuntimeError("Failed to open stdout pipe")
            if process.stderr is None:
                raise RuntimeError("Failed to open stderr pipe")

            # Stream chunks from stdout
            while True:
                chunk = process.stdout.read(chunk_size)
                if not chunk:
                    break
                yield chunk

            # Wait for process to complete and check for errors
            process.wait()
            if process.returncode != 0:
                stderr_output = process.stderr.read().decode("utf-8")
                raise RuntimeError(
                    f"yt-dlp failed with return code {process.returncode}: {stderr_output}"
                )

        except FileNotFoundError:
            raise RuntimeError(
                "yt-dlp is not installed. Install it with: pip install yt-dlp"
            ) from None
        except Exception:
            # Clean up process if still running
            if "process" in locals() and process.poll() is None:
                process.kill()
                process.wait()
            raise
    finally:
        # Cleanup isolated cache directory
        try:
            import shutil

            shutil.rmtree(temp_cache_dir)
        except Exception:
            pass


def stream_and_chunk_video(
    url: str,
    chunk_duration: int = 15,
    format_selector: str = "best[ext=mp4]/best",
    additional_options: list[str] | None = None,
    is_live: bool = False,
) -> Generator[bytes, None, None]:
    """
    Stream and chunk a video, handling live vs non-live streams based on is_live parameter.

    For non-live streams:
        - Downloads the entire video
        - Chunks it all at once
        - Yields chunks quickly

    For live streams:
        - Chunks all existing content first
        - Continues chunking new content in real-time as stream progresses

    Args:
        url: The video URL
        chunk_duration: Duration of each chunk in seconds (default: 15)
        format_selector: yt-dlp format selector (default: "best")
        additional_options: Additional yt-dlp command-line options
        is_live: Whether the video is a live stream (default: False)

    Yields:
        bytes: Video chunk data (complete MP4 files)
    """
    # Use the is_live parameter to determine the processing method
    if is_live:
        # Use real-time chunking for live streams
        yield from stream_and_chunk_live(
            url=url,
            chunk_duration=chunk_duration,
            format_selector=format_selector,
            additional_options=additional_options,
        )
    else:
        # For non-live streams, download and chunk quickly
        # Create unique temp directory with UUID to avoid collisions
        unique_id = uuid.uuid4().hex[:8]
        temp_dir = tempfile.mkdtemp(prefix=f"video_stream_{unique_id}_")

        try:
            temp_path = Path(temp_dir)
            video_file = temp_path / "video.mp4"
            chunk_dir = temp_path / "chunks"
            chunk_dir.mkdir()

            # Download the complete video
            with open(video_file, "wb") as f:
                for chunk in stream_video_chunks(
                    url=url,
                    format_selector=format_selector,
                    additional_options=additional_options,
                ):
                    f.write(chunk)

            # Split into chunks using ffmpeg
            output_pattern = chunk_dir / "chunk_%05d.mp4"
            cmd = [
                "ffmpeg",
                "-i",
                str(video_file),
                "-c",
                "copy",  # Copy without re-encoding for speed
                "-f",
                "segment",
                "-segment_time",
                str(chunk_duration),
                "-reset_timestamps",
                "1",
                "-map",
                "0",
                str(output_pattern),
            ]

            # Use temp_dir as cwd to prevent -Frag files from conflicting in concurrent operations
            subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
                cwd=temp_dir,
            )

            # Yield all chunks
            chunk_files = sorted(chunk_dir.glob("chunk_*.mp4"))
            for chunk_file in chunk_files:
                with open(chunk_file, "rb") as f:
                    yield f.read()

        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to chunk video: {e.stderr}")
        except FileNotFoundError:
            raise RuntimeError(
                "ffmpeg is not installed. Install it with: sudo apt-get install ffmpeg"
            )
        finally:
            # Cleanup
            try:
                import shutil

                shutil.rmtree(temp_dir)
            except Exception:
                pass


def stream_video_to_file(
    url: str,
    output_path: str,
    chunk_size: int = 1024 * 1024,
    live_from_start: bool = False,
) -> None:
    """
    Stream video from URL and save to file.

    Args:
        url: The video URL to stream from
        output_path: Path to save the video file
        chunk_size: Size of each chunk to read/write in bytes
        live_from_start: For live streams, start from beginning instead of live edge
    """
    with open(output_path, "wb") as f:
        for chunk in stream_video_chunks(
            url, chunk_size=chunk_size, live_from_start=live_from_start
        ):
            f.write(chunk)
            # You could add progress tracking here
            print(f"Downloaded {f.tell()} bytes...", end="\r")
    print(f"\nVideo saved to {output_path}")


if __name__ == "__main__":
    # Example usage
    if len(sys.argv) < 2:
        print("Usage: python stream.py <video_url> [output_file]")
        sys.exit(1)

    video_url = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "output.mp4"

    print(f"Streaming video from: {video_url}")
    try:
        stream_video_to_file(video_url, output_file)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
