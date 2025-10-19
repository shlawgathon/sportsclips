"""
Tests for the highlight trimming step.

These tests verify the trim_highlight functionality including:
- Chunk concatenation
- LLM-based trimming with function calling
- Fallback behaviors
- Error handling
"""

import os
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from src.steps.trim_highlight import (
    TRIM_HIGHLIGHT_PROMPT,
    HighlightTrimmer,
    trim_highlight_step,
)
from src.steps.trim_highlight.prompt import (
    TRIM_HIGHLIGHT_PROMPT_TEMPLATE,
    TRIM_HIGHLIGHT_TOOL,
)
from src.steps.trim_highlight.step import _concatenate_chunks


class TestConcatenateChunks:
    """Test the _concatenate_chunks utility function."""

    def test_concatenate_empty_chunks(self):
        """Test concatenating empty list returns empty bytes."""
        result = _concatenate_chunks([])
        assert result == b""

    def test_concatenate_single_chunk(self):
        """Test concatenating single chunk returns that chunk."""
        chunk = b"fake video data"
        result = _concatenate_chunks([chunk])
        assert result == chunk

    @pytest.mark.asyncio
    async def test_concatenate_multiple_chunks_with_real_videos(self):
        """Test concatenating multiple video chunks (integration test)."""
        # Get test video assets
        assets_dir = Path(__file__).parent / "assets"
        test_video1 = assets_dir / "test_video1.mp4"
        test_video2 = assets_dir / "test_video2.mp4"

        if not test_video1.exists() or not test_video2.exists():
            pytest.skip("Test video assets not found")

        # Read video chunks
        with open(test_video1, "rb") as f:
            chunk1 = f.read()
        with open(test_video2, "rb") as f:
            chunk2 = f.read()

        # Concatenate
        result = _concatenate_chunks([chunk1, chunk2])

        # Verify result is valid video data (has MP4 header)
        assert len(result) > 0
        # MP4 files typically start with ftyp box
        assert b"ftyp" in result[:100]

    def test_concatenate_handles_ffmpeg_error(self):
        """Test that concatenate falls back gracefully on ffmpeg error."""
        # Create fake chunks that won't concatenate properly
        fake_chunks = [b"not a real video 1", b"not a real video 2"]

        # Should fall back to returning first chunk
        result = _concatenate_chunks(fake_chunks)
        assert result == fake_chunks[0]


class TestTrimHighlightPrompt:
    """Test trim highlight prompt templates and tools."""

    def test_trim_highlight_prompt_exists(self):
        """Test that trim highlight prompt is defined."""
        assert isinstance(TRIM_HIGHLIGHT_PROMPT, str)
        assert len(TRIM_HIGHLIGHT_PROMPT) > 0

    def test_trim_highlight_prompt_template_format(self):
        """Test that prompt template can be formatted with detection context."""
        detection_context = "\nTest context\n"
        formatted = TRIM_HIGHLIGHT_PROMPT_TEMPLATE.format(
            detection_context=detection_context
        )
        assert detection_context in formatted
        assert "Chunk 1" in formatted
        assert "Chunk 9" in formatted

    def test_trim_highlight_prompt_without_context(self):
        """Test default prompt without detection context."""
        assert "{detection_context}" not in TRIM_HIGHLIGHT_PROMPT
        assert "Chunk 1" in TRIM_HIGHLIGHT_PROMPT

    def test_trim_highlight_tool_structure(self):
        """Test that trim highlight tool has correct structure."""
        assert TRIM_HIGHLIGHT_TOOL is not None
        assert len(TRIM_HIGHLIGHT_TOOL.function_declarations) == 1

        func = TRIM_HIGHLIGHT_TOOL.function_declarations[0]
        assert func.name == "report_trim_segments"
        assert "start_segment" in func.parameters.properties
        assert "end_segment" in func.parameters.properties
        assert "reasoning" in func.parameters.properties


class TestHighlightTrimmer:
    """Test HighlightTrimmer class."""

    @pytest.fixture
    def trimmer(self):
        """Create a HighlightTrimmer instance for testing."""
        return HighlightTrimmer(model_name="gemini-2.5-flash")

    def test_trimmer_initialization(self, trimmer):
        """Test that trimmer initializes correctly."""
        assert trimmer is not None
        assert trimmer.agent is not None
        assert trimmer.prompt == TRIM_HIGHLIGHT_PROMPT

    @pytest.mark.asyncio
    async def test_trim_highlight_with_valid_response(self, trimmer):
        """Test trim_highlight with valid LLM response."""
        # Create fake video chunks
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]

        metadata = {
            "window_start_chunk": 0,
            "window_end_chunk": 8,
            "base_chunk_duration": 4,
        }

        # Mock the agent's generate method to return a valid function call
        mock_response = {
            "name": "report_trim_segments",
            "args": {
                "start_segment": 3,
                "end_segment": 7,
                "reasoning": "Peak action occurs in chunks 3-7",
            },
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            # Mock _concatenate_chunks to avoid ffmpeg dependency
            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"trimmed video data"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                # Verify results
                assert result_video == b"trimmed video data"
                assert result_metadata["trim_method"] == "gemini_multi_video"
                assert result_metadata["trimmed_chunk_start"] == 3
                assert result_metadata["trimmed_chunk_end"] == 7
                assert (
                    result_metadata["trimmed_chunk_count"] == 5
                )  # chunks 3-7 (indices 2-6)
                assert "Peak action" in result_metadata["trim_reasoning"]

                # Verify concatenate was called with correct chunks (indices 2:7)
                mock_concat.assert_called_once()
                called_chunks = mock_concat.call_args[0][0]
                assert len(called_chunks) == 5

    @pytest.mark.asyncio
    async def test_trim_highlight_with_detection_context(self, trimmer):
        """Test trim_highlight includes detection context in prompt."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]

        metadata = {
            "detection_reason": "Goal scored",
            "detection_confidence": "high",
        }

        mock_response = {
            "name": "report_trim_segments",
            "args": {"start_segment": 4, "end_segment": 6, "reasoning": "Goal moment"},
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"trimmed data"

                await trimmer.trim_highlight(fake_chunks, metadata)

                # Verify generate was called
                mock_generate.assert_called_once()

                # Check that the text input contains detection context
                call_args = mock_generate.call_args[0][0]
                # Last input should be the text prompt
                text_input = call_args[-1]
                assert text_input.modality.value == "text"
                assert "Detection Analysis" in text_input.data or "high" in str(
                    call_args
                )

    @pytest.mark.asyncio
    async def test_trim_highlight_validates_segment_range(self, trimmer):
        """Test trim_highlight validates and fixes invalid segment ranges."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        # Test case 1: start > end (should swap)
        mock_response = {
            "name": "report_trim_segments",
            "args": {
                "start_segment": 7,
                "end_segment": 3,  # Invalid: end before start
                "reasoning": "Should be swapped",
            },
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"trimmed data"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                # Should swap the values
                assert result_metadata["trimmed_chunk_start"] == 3
                assert result_metadata["trimmed_chunk_end"] == 7

    @pytest.mark.asyncio
    async def test_trim_highlight_clamps_out_of_range_segments(self, trimmer):
        """Test trim_highlight clamps segments to valid range (1-9)."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        # Test with out-of-range values
        mock_response = {
            "name": "report_trim_segments",
            "args": {
                "start_segment": 0,  # Too low
                "end_segment": 15,  # Too high
                "reasoning": "Out of range",
            },
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"trimmed data"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                # Should clamp to valid range
                assert result_metadata["trimmed_chunk_start"] == 1
                assert result_metadata["trimmed_chunk_end"] == 9

    @pytest.mark.asyncio
    async def test_trim_highlight_with_unexpected_response_format(self, trimmer):
        """Test trim_highlight handles unexpected response format gracefully."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        # Mock unexpected response (not a function call)
        mock_response = "Some unexpected text response"

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"fallback video data"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                # Should fall back to using all chunks
                assert result_video == b"fallback video data"
                assert result_metadata["trim_method"] == "function_call_fallback"
                assert result_metadata["trimmed_chunk_count"] == 9

    @pytest.mark.asyncio
    async def test_trim_highlight_handles_exception(self, trimmer):
        """Test trim_highlight handles exceptions gracefully."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        # Mock an exception during generation
        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_generate.side_effect = Exception("API error")

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"error fallback data"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                # Should fall back to all chunks
                assert result_video == b"error fallback data"
                assert result_metadata["trim_method"] == "error_fallback"
                assert "API error" in result_metadata["trim_error"]
                assert result_metadata["trimmed_chunk_count"] == 9


class TestTrimHighlightStep:
    """Test the trim_highlight_step function (pipeline integration)."""

    @pytest.mark.asyncio
    async def test_trim_highlight_step_basic(self):
        """Test trim_highlight_step function works as expected."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {"window_start_chunk": 0}

        # Mock the trimmer
        with patch(
            "src.steps.trim_highlight.step.HighlightTrimmer"
        ) as mock_trimmer_class:
            mock_trimmer_instance = MagicMock()
            mock_trimmer_class.return_value = mock_trimmer_instance

            mock_trimmer_instance.trim_highlight = AsyncMock(
                return_value=(b"trimmed data", {"trimmed": True})
            )

            result_video, result_metadata = await trim_highlight_step(
                fake_chunks, metadata
            )

            # Verify results
            assert result_video == b"trimmed data"
            assert result_metadata["trimmed"] is True

    @pytest.mark.asyncio
    async def test_trim_highlight_step_reuses_trimmer_instance(self):
        """Test that trim_highlight_step reuses the same trimmer instance."""
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        with patch("src.steps.trim_highlight.step._trimmer", None):
            with patch(
                "src.steps.trim_highlight.step.HighlightTrimmer"
            ) as mock_trimmer_class:
                mock_trimmer_instance = MagicMock()
                mock_trimmer_class.return_value = mock_trimmer_instance
                mock_trimmer_instance.trim_highlight = AsyncMock(
                    return_value=(b"data", {})
                )

                # Call twice
                await trim_highlight_step(fake_chunks, metadata)
                await trim_highlight_step(fake_chunks, metadata)

                # Should only create one instance
                assert mock_trimmer_class.call_count == 1


class TestTrimHighlightIntegration:
    """Integration tests with real Gemini API (requires API key)."""

    @pytest.fixture
    def trimmer_with_api(self):
        """Create a trimmer with API key for integration tests."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            pytest.skip("GEMINI_API_KEY not set in environment")
        return HighlightTrimmer(model_name="gemini-2.5-flash")

    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_trim_highlight_with_real_videos(self, trimmer_with_api):
        """Test trim_highlight with real video assets and API (slow test)."""
        # Get test video assets
        assets_dir = Path(__file__).parent / "assets"
        test_video = assets_dir / "test_video_3.mp4"

        if not test_video.exists():
            pytest.skip("Test video asset not found")

        # For this test, use the same video 9 times as chunks
        # (in real usage, these would be different 4-second segments)
        with open(test_video, "rb") as f:
            video_data = f.read()

        fake_chunks = [video_data] * 9

        metadata = {
            "window_start_chunk": 0,
            "detection_reason": "Test highlight",
        }

        # This will make a real API call
        result_video, result_metadata = await trimmer_with_api.trim_highlight(
            fake_chunks, metadata
        )

        # Verify results
        assert len(result_video) > 0
        assert "trim_method" in result_metadata
        assert "trimmed_chunk_count" in result_metadata

        # Should have selected some subset of chunks (or all)
        assert 1 <= result_metadata["trimmed_chunk_count"] <= 9

        # Verify the trimmed video is actually smaller than concatenating all 9 chunks
        # (unless Gemini selected all chunks)
        if result_metadata["trimmed_chunk_count"] < 9:
            # The result should be smaller than all 9 chunks combined
            expected_max_size = len(video_data) * 9
            assert len(result_video) < expected_max_size

            # The result should be at least as large as the number of chunks selected
            # (accounting for some overhead from re-encoding)
            expected_min_size = (
                len(video_data) * result_metadata["trimmed_chunk_count"] * 0.5
            )
            assert len(result_video) > expected_min_size

        print(f"\nTrim result: {result_metadata}")
        print(f"Original chunk size: {len(video_data):,} bytes")
        print(f"Trimmed video size: {len(result_video):,} bytes")
        print(
            f"Expected size for {result_metadata['trimmed_chunk_count']} chunks: ~{len(video_data) * result_metadata['trimmed_chunk_count']:,} bytes"
        )


class TestTrimHighlightEdgeCases:
    """Test edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_trim_single_chunk_selection(self):
        """Test trimming to a single chunk."""
        trimmer = HighlightTrimmer()
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        mock_response = {
            "name": "report_trim_segments",
            "args": {
                "start_segment": 5,
                "end_segment": 5,  # Single chunk
                "reasoning": "Action in one chunk only",
            },
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"single chunk"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                assert result_metadata["trimmed_chunk_start"] == 5
                assert result_metadata["trimmed_chunk_end"] == 5
                assert result_metadata["trimmed_chunk_count"] == 1

    @pytest.mark.asyncio
    async def test_trim_all_chunks_selection(self):
        """Test trimming that keeps all chunks."""
        trimmer = HighlightTrimmer()
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        mock_response = {
            "name": "report_trim_segments",
            "args": {
                "start_segment": 1,
                "end_segment": 9,  # All chunks
                "reasoning": "Entire sequence is important",
            },
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"all chunks"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                assert result_metadata["trimmed_chunk_start"] == 1
                assert result_metadata["trimmed_chunk_end"] == 9
                assert result_metadata["trimmed_chunk_count"] == 9

    @pytest.mark.asyncio
    async def test_trim_with_empty_reasoning(self):
        """Test trimming with empty reasoning field."""
        trimmer = HighlightTrimmer()
        fake_chunks = [f"chunk{i}".encode() * 100 for i in range(9)]
        metadata = {}

        mock_response = {
            "name": "report_trim_segments",
            "args": {
                "start_segment": 3,
                "end_segment": 6,
                "reasoning": "",  # Empty reasoning
            },
        }

        with patch.object(
            trimmer.agent, "generate", new_callable=AsyncMock
        ) as mock_generate:
            mock_output = MagicMock()
            mock_output.data = mock_response
            mock_generate.return_value = mock_output

            with patch(
                "src.steps.trim_highlight.step._concatenate_chunks"
            ) as mock_concat:
                mock_concat.return_value = b"trimmed"

                result_video, result_metadata = await trimmer.trim_highlight(
                    fake_chunks, metadata
                )

                # Should still work with empty reasoning
                assert result_metadata["trim_reasoning"] == ""
                assert result_metadata["trimmed_chunk_count"] == 4
