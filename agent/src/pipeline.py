"""
Video processing pipeline for streaming and chunking videos.

This module provides functionality to download video streams, split them into
fixed-duration chunks, and send them through a WebSocket connection.
"""

import logging
from typing import Any, Callable

from .stream import stream_and_chunk_video

logger = logging.getLogger(__name__)


class VideoPipeline:
    """Pipeline for processing video streams and generating chunks."""

    def __init__(
        self,
        chunk_duration: int = 15,
        format_selector: str = "best[ext=mp4]/best",
    ):
        """
        Initialize the video pipeline.

        Args:
            chunk_duration: Duration of each video chunk in seconds (default: 15)
            format_selector: yt-dlp format selector for video quality
        """
        self.chunk_duration = chunk_duration
        self.format_selector = format_selector
        self.modulation_functions: list[
            Callable[[bytes, dict[str, Any]], tuple[bytes, dict[str, Any]]]
        ] = []

    def add_modulation(
        self,
        func: Callable[[bytes, dict[str, Any]], tuple[bytes, dict[str, Any]]],
    ) -> None:
        """
        Add a modulation function to the pipeline.

        Modulation functions transform video chunks and their metadata.
        They receive (video_data, metadata) and return (modified_video_data, modified_metadata).

        Args:
            func: Function that takes (video_data, metadata) and returns (video_data, metadata)
        """
        self.modulation_functions.append(func)

    def _apply_modulations(
        self, video_data: bytes, metadata: dict[str, Any]
    ) -> tuple[bytes, dict[str, Any]]:
        """
        Apply all modulation functions to video data and metadata.

        Args:
            video_data: Raw video bytes
            metadata: Video metadata dict

        Returns:
            Tuple of (modified_video_data, modified_metadata)
        """
        for func in self.modulation_functions:
            video_data, metadata = func(video_data, metadata)
        return video_data, metadata

    def process_video_url(
        self,
        video_url: str,
        ws: Any,
        is_live: bool,
        create_snippet_message: Callable[[bytes, str, str, str], str],
        create_complete_message: Callable[[str], str],
        create_error_message: Callable[[str, str | None], str],
    ) -> None:
        """
        Process a video URL: download, chunk, and send through WebSocket.

        Args:
            video_url: URL of video to process
            ws: WebSocket connection object
            is_live: Whether the video is a live stream
            create_snippet_message: Function to create snippet message JSON
            create_complete_message: Function to create completion message JSON
            create_error_message: Function to create error message JSON
        """

        try:
            stream_type = "live stream" if is_live else "video"
            logger.info(f"Starting pipeline for {stream_type}: {video_url}")

            # Stream and chunk the video using the provided is_live parameter
            logger.info(
                f"Processing {stream_type} into {self.chunk_duration}-second chunks"
            )

            chunk_index = 0
            for chunk_data in stream_and_chunk_video(
                url=video_url,
                chunk_duration=self.chunk_duration,
                format_selector=self.format_selector,
                additional_options=["--no-part"],  # Don't use .part files
                is_live=is_live,
            ):
                logger.info(f"Processing chunk {chunk_index + 1}")

                # Create metadata (we don't know total_chunks for live streams yet)
                metadata: dict[str, Any] = {
                    "src_video_url": video_url,
                    "chunk_index": chunk_index,
                    "duration_seconds": self.chunk_duration,
                }

                # Apply modulation functions
                chunk_data, metadata = self._apply_modulations(chunk_data, metadata)

                # Skip if chunk was filtered out (empty data)
                if len(chunk_data) == 0:
                    logger.info(f"Chunk {chunk_index + 1} was filtered out, skipping")
                    chunk_index += 1
                    continue

                # Create and send snippet message
                title = f"Chunk {chunk_index + 1}"
                description = (
                    f"Video chunk {chunk_index + 1} "
                    f"({chunk_index * self.chunk_duration}-"
                    f"{(chunk_index + 1) * self.chunk_duration}s)"
                )

                snippet_msg = create_snippet_message(
                    chunk_data,
                    video_url,
                    title,
                    description,
                )

                ws.send(snippet_msg)
                logger.info(f"Sent chunk {chunk_index + 1} to client")

                chunk_index += 1

            # Send completion message
            ws.send(create_complete_message(video_url))
            logger.info("Pipeline processing complete")

        except Exception as e:
            logger.error(f"Pipeline error: {e}", exc_info=True)
            ws.send(create_error_message(str(e), video_url))


def create_default_pipeline(chunk_duration: int = 15) -> VideoPipeline:
    """
    Create a pipeline with default settings.

    Args:
        chunk_duration: Duration of each video chunk in seconds (default: 15)

    Returns:
        Configured VideoPipeline instance
    """
    return VideoPipeline(chunk_duration=chunk_duration)


def create_highlight_pipeline(chunk_duration: int = 3) -> VideoPipeline:
    """
    Create a pipeline configured for highlight detection.

    This pipeline processes videos in 3-second chunks and uses an LLM to
    determine whether each chunk contains a highlight moment. Only highlights
    are passed through to the client.

    Args:
        chunk_duration: Duration of each video chunk in seconds (default: 3)

    Returns:
        Configured VideoPipeline instance with highlight detection
    """
    from .steps import is_highlight_step

    pipeline = VideoPipeline(chunk_duration=chunk_duration)
    pipeline.add_modulation(is_highlight_step)
    return pipeline
