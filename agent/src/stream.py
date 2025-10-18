import subprocess
import sys
from typing import Generator


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
    # Build yt-dlp command
    cmd = [
        "yt-dlp",
        "-f",
        format_selector,
        "-o",
        "-",  # Output to stdout
        "--quiet",  # Suppress yt-dlp output
        "--no-warnings",
    ]

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
