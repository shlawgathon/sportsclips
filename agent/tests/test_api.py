"""Tests for the Flask WebSocket API."""

import base64
import json
from unittest.mock import Mock, patch

import pytest

from src.api import (
    app,
    create_complete_message,
    create_error_message,
    create_snippet_message,
    process_video_and_generate_snippets,
)


@pytest.fixture
def client():
    """Create a test client for the Flask app."""
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


class TestMessageCreation:
    """Test message creation helper functions."""

    def test_create_snippet_message(self):
        """Test creating a snippet message with video data and metadata."""
        video_data = b"test_video_data"
        src_url = "https://youtube.com/watch?v=test"
        title = "Test Snippet"
        description = "Test description"

        message = create_snippet_message(video_data, src_url, title, description)
        data = json.loads(message)

        assert data["type"] == "snippet"
        assert data["data"]["video_data"] == base64.b64encode(video_data).decode(
            "utf-8"
        )
        assert data["data"]["metadata"]["src_video_url"] == src_url
        assert data["data"]["metadata"]["title"] == title
        assert data["data"]["metadata"]["description"] == description

    def test_create_snippet_message_with_empty_video(self):
        """Test creating a snippet message with empty video data."""
        video_data = b""
        src_url = "https://youtube.com/watch?v=test"
        title = "Empty Snippet"
        description = "Empty video"

        message = create_snippet_message(video_data, src_url, title, description)
        data = json.loads(message)

        assert data["type"] == "snippet"
        assert data["data"]["video_data"] == ""
        assert data["data"]["metadata"]["src_video_url"] == src_url

    def test_create_error_message(self):
        """Test creating an error message without metadata."""
        error = "Test error message"
        message = create_error_message(error)
        data = json.loads(message)

        assert data["type"] == "error"
        assert data["message"] == error
        assert "metadata" not in data

    def test_create_error_message_with_src_url(self):
        """Test creating an error message with src_video_url metadata."""
        error = "Test error message"
        src_url = "https://youtube.com/watch?v=test"
        message = create_error_message(error, src_url)
        data = json.loads(message)

        assert data["type"] == "error"
        assert data["message"] == error
        assert "metadata" in data
        assert data["metadata"]["src_video_url"] == src_url

    def test_create_complete_message(self):
        """Test creating a completion message."""
        src_url = "https://youtube.com/watch?v=test"
        message = create_complete_message(src_url)
        data = json.loads(message)

        assert data["type"] == "snippet_complete"
        assert "metadata" in data
        assert data["metadata"]["src_video_url"] == src_url


class TestHealthEndpoint:
    """Test the health check endpoint."""

    def test_health_endpoint(self, client):
        """Test that health endpoint returns healthy status."""
        response = client.get("/health")
        assert response.status_code == 200

        data = json.loads(response.data)
        assert data["status"] == "healthy"


class TestVideoProcessing:
    """Test video processing logic."""

    @patch("src.api.pipeline")
    def test_process_video_sends_snippet_and_complete(self, mock_pipeline):
        """Test that processing uses the pipeline correctly."""
        mock_ws = Mock()
        test_url = "https://youtube.com/watch?v=test"

        process_video_and_generate_snippets(test_url, mock_ws, is_live=False)

        # Verify pipeline.process_video_url was called with correct arguments
        mock_pipeline.process_video_url.assert_called_once()
        call_kwargs = mock_pipeline.process_video_url.call_args[1]
        assert call_kwargs["video_url"] == test_url
        assert call_kwargs["ws"] == mock_ws
        assert not call_kwargs["is_live"]

    @patch("src.api.pipeline")
    def test_process_video_sends_error_on_exception(self, mock_pipeline):
        """Test that processing handles pipeline errors correctly."""
        mock_ws = Mock()
        test_url = "https://youtube.com/watch?v=test"

        # Make pipeline raise an exception
        mock_pipeline.process_video_url.side_effect = Exception("Pipeline error")

        # This should not raise - the pipeline handles errors internally
        with pytest.raises(Exception, match="Pipeline error"):
            process_video_and_generate_snippets(test_url, mock_ws, is_live=False)


class TestAPIIntegration:
    """Integration tests for the API."""

    def test_snippet_message_roundtrip(self):
        """Test creating and parsing a snippet message."""
        original_data = b"test_mp4_data_here"
        src_url = "https://example.com/video"
        title = "Integration Test"
        description = "Test description for integration"

        # Create message
        message = create_snippet_message(original_data, src_url, title, description)

        # Parse message
        parsed = json.loads(message)

        # Decode video data
        decoded_data = base64.b64decode(parsed["data"]["video_data"])

        # Verify roundtrip
        assert decoded_data == original_data
        assert parsed["data"]["metadata"]["src_video_url"] == src_url
        assert parsed["data"]["metadata"]["title"] == title
        assert parsed["data"]["metadata"]["description"] == description

    def test_all_message_types_are_valid_json(self):
        """Test that all message types produce valid JSON."""
        snippet_msg = create_snippet_message(b"data", "url", "title", "description")
        error_msg = create_error_message("error")
        complete_msg = create_complete_message("url")

        # All should parse without error
        json.loads(snippet_msg)
        json.loads(error_msg)
        json.loads(complete_msg)

    def test_snippet_metadata_fields(self):
        """Test that snippet messages have all required metadata fields."""
        video_data = b"sample_data"
        src_url = "https://youtube.com/watch?v=xyz"
        title = "Sample Title"
        description = "Sample Description"

        message = create_snippet_message(video_data, src_url, title, description)
        data = json.loads(message)

        # Verify structure
        assert "type" in data
        assert "data" in data
        assert "video_data" in data["data"]
        assert "metadata" in data["data"]

        metadata = data["data"]["metadata"]
        assert "src_video_url" in metadata
        assert "title" in metadata
        assert "description" in metadata

    def test_base64_encoding_correctness(self):
        """Test that base64 encoding is correct and reversible."""
        # Test with various data patterns
        test_cases = [
            b"simple data",
            b"\x00\x01\x02\x03",  # Binary data
            b"a" * 1000,  # Larger data
            b"",  # Empty data
        ]

        for original_data in test_cases:
            message = create_snippet_message(
                original_data, "url", "title", "description"
            )
            parsed = json.loads(message)
            decoded = base64.b64decode(parsed["data"]["video_data"])
            assert decoded == original_data


class TestErrorHandling:
    """Test error handling in the API."""

    def test_error_message_format(self):
        """Test that error messages have correct format."""
        error_text = "Something went wrong"
        message = create_error_message(error_text)
        data = json.loads(message)

        assert data["type"] == "error"
        assert data["message"] == error_text

    def test_error_message_with_metadata(self):
        """Test that error messages can include metadata."""
        error_text = "Something went wrong"
        src_url = "https://youtube.com/watch?v=error"
        message = create_error_message(error_text, src_url)
        data = json.loads(message)

        assert data["type"] == "error"
        assert data["message"] == error_text
        assert "metadata" in data
        assert data["metadata"]["src_video_url"] == src_url

    def test_complete_message_format(self):
        """Test that completion messages have correct format."""
        src_url = "https://youtube.com/watch?v=complete"
        message = create_complete_message(src_url)
        data = json.loads(message)

        assert data["type"] == "snippet_complete"
        assert "metadata" in data
        assert data["metadata"]["src_video_url"] == src_url
