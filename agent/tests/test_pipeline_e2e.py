"""
End-to-end tests for the video processing pipeline.

These tests verify that the sliding window pipeline works for highlight detection.
"""

import json
from unittest.mock import Mock, patch

import pytest

from src.api import (
    create_complete_message,
    create_error_message,
    create_snippet_message,
)
from src.pipeline import SlidingWindowPipeline, create_highlight_pipeline


class TestSlidingWindowPipelineUnit:
    """Unit tests for the SlidingWindowPipeline class."""

    def test_pipeline_initialization(self):
        """Test that pipeline initializes with correct defaults."""
        pipeline = SlidingWindowPipeline()
        assert pipeline.base_chunk_duration == 2
        assert pipeline.window_size == 7
        assert pipeline.slide_step == 2
        assert pipeline.format_selector == "best[ext=mp4]/best"
        assert pipeline.detect_step is None
        assert pipeline.trim_step is None
        assert pipeline.caption_step is None

    def test_pipeline_custom_settings(self):
        """Test pipeline initialization with custom settings."""
        pipeline = SlidingWindowPipeline(
            base_chunk_duration=3, window_size=5, slide_step=1
        )
        assert pipeline.base_chunk_duration == 3
        assert pipeline.window_size == 5
        assert pipeline.slide_step == 1

    def test_set_detect_step(self):
        """Test setting the detect step function."""
        pipeline = SlidingWindowPipeline()

        def dummy_detect(chunks, metadata):
            return True, metadata

        pipeline.set_detect_step(dummy_detect)
        assert pipeline.detect_step == dummy_detect

    def test_set_trim_step(self):
        """Test setting the trim step function."""
        pipeline = SlidingWindowPipeline()

        def dummy_trim(chunks, metadata):
            return b"trimmed", metadata

        pipeline.set_trim_step(dummy_trim)
        assert pipeline.trim_step == dummy_trim

    def test_set_caption_step(self):
        """Test setting the caption step function."""
        pipeline = SlidingWindowPipeline()

        def dummy_caption(data, metadata):
            return "title", "description", metadata

        pipeline.set_caption_step(dummy_caption)
        assert pipeline.caption_step == dummy_caption

    def test_concatenate_chunks_single_chunk(self):
        """Test concatenating a single chunk returns it unchanged."""
        pipeline = SlidingWindowPipeline()
        chunks = [b"single_chunk"]
        result = pipeline._concatenate_chunks(chunks)
        assert result == b"single_chunk"

    def test_concatenate_chunks_empty(self):
        """Test concatenating empty list returns empty bytes."""
        pipeline = SlidingWindowPipeline()
        result = pipeline._concatenate_chunks([])
        assert result == b""

    def test_create_highlight_pipeline(self):
        """Test creating a highlight pipeline."""
        pipeline = create_highlight_pipeline()
        assert isinstance(pipeline, SlidingWindowPipeline)
        assert pipeline.base_chunk_duration == 2
        assert pipeline.window_size == 7
        assert pipeline.slide_step == 2
        # Steps should be configured
        assert pipeline.detect_step is not None
        assert pipeline.trim_step is not None
        assert pipeline.caption_step is not None

    def test_create_highlight_pipeline_custom_settings(self):
        """Test creating a highlight pipeline with custom settings."""
        pipeline = create_highlight_pipeline(
            base_chunk_duration=3, window_size=5, slide_step=1
        )
        assert pipeline.base_chunk_duration == 3
        assert pipeline.window_size == 5
        assert pipeline.slide_step == 1


class TestSlidingWindowIntegration:
    """Integration tests for the sliding window pipeline."""

    @patch("src.pipeline.stream_and_chunk_video")
    def test_pipeline_sliding_window_logic(self, mock_stream_and_chunk):
        """Test that pipeline correctly implements sliding window logic."""
        pipeline = SlidingWindowPipeline(
            base_chunk_duration=2, window_size=3, slide_step=1
        )

        # Create mock chunks (simulate 6 chunks = 12 seconds of video)
        mock_chunks = [
            b"chunk_0",
            b"chunk_1",
            b"chunk_2",
            b"chunk_3",
            b"chunk_4",
            b"chunk_5",
        ]
        mock_stream_and_chunk.return_value = iter(mock_chunks)

        # Track which windows were processed
        processed_windows = []

        def track_detect(chunks, metadata):
            processed_windows.append(
                (metadata["window_start_chunk"], metadata["window_end_chunk"])
            )
            # No highlights detected
            return False, metadata

        pipeline.set_detect_step(track_detect)

        mock_ws = Mock()
        test_url = "https://example.com/test.mp4"

        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url=test_url,
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # With 6 chunks, window_size=3, slide_step=1, we should process:
        # Window 0-2, 1-3, 2-4, 3-5 (4 windows)
        assert len(processed_windows) == 4
        assert processed_windows[0] == (0, 2)
        assert processed_windows[1] == (1, 3)
        assert processed_windows[2] == (2, 4)
        assert processed_windows[3] == (3, 5)

        # Should only send completion message (no highlights)
        assert mock_ws.send.call_count == 1
        last_msg = json.loads(mock_ws.send.call_args_list[-1][0][0])
        assert last_msg["type"] == "snippet_complete"

    @patch("src.pipeline.stream_and_chunk_video")
    def test_pipeline_highlight_detection_and_skip(self, mock_stream_and_chunk):
        """Test that pipeline skips window when highlight is detected."""
        pipeline = SlidingWindowPipeline(
            base_chunk_duration=2, window_size=3, slide_step=1
        )

        # Create mock chunks
        mock_chunks = [
            b"chunk_0",
            b"chunk_1",
            b"chunk_2",
            b"chunk_3",
            b"chunk_4",
            b"chunk_5",
        ]
        mock_stream_and_chunk.return_value = iter(mock_chunks)

        processed_windows = []

        def detect_first_window(chunks, metadata):
            window_start = metadata["window_start_chunk"]
            processed_windows.append(window_start)
            # Detect highlight only in first window
            return window_start == 0, metadata

        def dummy_trim(chunks, metadata):
            return b"trimmed_video", metadata

        def dummy_caption(data, metadata):
            return "Test Highlight", "Test Description", metadata

        pipeline.set_detect_step(detect_first_window)
        pipeline.set_trim_step(dummy_trim)
        pipeline.set_caption_step(dummy_caption)

        mock_ws = Mock()
        test_url = "https://example.com/test.mp4"

        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url=test_url,
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # Should process: window 0 (highlight, skip to 3), then 3
        # Windows processed: 0, 3
        assert 0 in processed_windows
        assert 3 in processed_windows
        # Should NOT process windows 1, 2 (skipped due to highlight)
        assert 1 not in processed_windows
        assert 2 not in processed_windows

        # Should send: 1 highlight + 1 completion
        assert mock_ws.send.call_count == 2

        # First message should be the highlight
        first_msg = json.loads(mock_ws.send.call_args_list[0][0][0])
        assert first_msg["type"] == "snippet"

        # Last message should be completion
        last_msg = json.loads(mock_ws.send.call_args_list[-1][0][0])
        assert last_msg["type"] == "snippet_complete"

    @patch("src.pipeline.stream_and_chunk_video")
    def test_pipeline_metadata_tracking(self, mock_stream_and_chunk):
        """Test that pipeline correctly tracks metadata for windows."""
        pipeline = SlidingWindowPipeline(base_chunk_duration=2, window_size=3)

        mock_chunks = [b"chunk_0", b"chunk_1", b"chunk_2"]
        mock_stream_and_chunk.return_value = iter(mock_chunks)

        captured_metadata = []

        def capture_metadata(chunks, metadata):
            captured_metadata.append(metadata.copy())
            return False, metadata

        pipeline.set_detect_step(capture_metadata)

        mock_ws = Mock()
        test_url = "https://example.com/test.mp4"

        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url=test_url,
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # Should have processed 1 window (0-2)
        assert len(captured_metadata) == 1

        metadata = captured_metadata[0]
        assert metadata["src_video_url"] == test_url
        assert metadata["window_start_chunk"] == 0
        assert metadata["window_end_chunk"] == 2
        assert metadata["window_start_time"] == 0
        assert metadata["window_end_time"] == 6  # 3 chunks * 2 seconds
        assert metadata["base_chunk_duration"] == 2


class TestPipelineErrorHandling:
    """Test error handling in the pipeline."""

    def test_pipeline_sends_error_on_invalid_url(self):
        """Test that invalid URL triggers error message."""
        pipeline = SlidingWindowPipeline()
        mock_ws = Mock()

        invalid_url = (
            "https://this-domain-definitely-does-not-exist-12345.com/video.mp4"
        )

        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url=invalid_url,
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # Should send error message
        assert mock_ws.send.called
        last_msg = json.loads(mock_ws.send.call_args_list[-1][0][0])
        assert last_msg["type"] == "error"

    @patch("src.pipeline.stream_and_chunk_video")
    def test_pipeline_handles_processing_error(self, mock_stream_and_chunk):
        """Test that pipeline handles errors during processing."""
        pipeline = SlidingWindowPipeline()

        # Make stream fail
        mock_stream_and_chunk.side_effect = Exception("Download failed")

        mock_ws = Mock()
        test_url = "https://example.com/test.mp4"

        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url=test_url,
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # Error message should be sent
        last_msg = json.loads(mock_ws.send.call_args_list[-1][0][0])
        assert last_msg["type"] == "error"


class TestPipelineBasicFunctionality:
    """Basic functional tests to validate core assumptions."""

    @patch("src.pipeline.stream_and_chunk_video")
    def test_chunks_collected_correctly(self, mock_stream_and_chunk):
        """Validate that all chunks are collected before processing."""
        pipeline = SlidingWindowPipeline()

        mock_chunks = [b"chunk_0", b"chunk_1", b"chunk_2", b"chunk_3"]
        mock_stream_and_chunk.return_value = iter(mock_chunks)

        chunk_count_in_detect = []

        def count_chunks(chunks, metadata):
            chunk_count_in_detect.append(len(chunks))
            return False, metadata

        pipeline.set_detect_step(count_chunks)

        mock_ws = Mock()
        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url="https://example.com/test.mp4",
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # All detect calls should receive window_size chunks
        assert all(count == pipeline.window_size for count in chunk_count_in_detect)

    @patch("src.pipeline.stream_and_chunk_video")
    def test_window_slide_behavior_without_highlight(self, mock_stream_and_chunk):
        """Validate sliding by slide_step when no highlight."""
        pipeline = SlidingWindowPipeline(window_size=3, slide_step=2)

        # Need at least 7 chunks to see multiple slides
        mock_chunks = [f"chunk_{i}".encode() for i in range(10)]
        mock_stream_and_chunk.return_value = iter(mock_chunks)

        window_starts = []

        def track_windows(chunks, metadata):
            window_starts.append(metadata["window_start_chunk"])
            return False, metadata  # No highlights

        pipeline.set_detect_step(track_windows)

        mock_ws = Mock()
        import asyncio
        asyncio.run(pipeline.process_video_url(
            video_url="https://example.com/test.mp4",
            ws=mock_ws,
            is_live=False,
            create_snippet_message=create_snippet_message,
            create_complete_message=create_complete_message,
            create_error_message=create_error_message,
        ))

        # With slide_step=2, should slide: 0, 2, 4, 6
        assert window_starts[0] == 0
        assert window_starts[1] == 2
        assert window_starts[2] == 4
        assert window_starts[3] == 6


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
