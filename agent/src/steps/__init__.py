"""
Pipeline steps for video processing.

This module contains individual processing steps that can be chained
together in a video processing pipeline.
"""

from .caption_highlight import (
    CAPTION_HIGHLIGHT_PROMPT,
    HighlightCaptioner,
    caption_highlight_step,
)
from .detect_highlight import (
    HIGHLIGHT_DETECTION_PROMPT,
    HighlightDetector,
    detect_highlight_step,
    is_highlight_step,
)
from .trim_highlight import (
    TRIM_HIGHLIGHT_PROMPT,
    HighlightTrimmer,
    trim_highlight_step,
)

__all__ = [
    # Detect highlight
    "detect_highlight_step",
    "is_highlight_step",
    "HighlightDetector",
    "HIGHLIGHT_DETECTION_PROMPT",
    # Trim highlight
    "trim_highlight_step",
    "HighlightTrimmer",
    "TRIM_HIGHLIGHT_PROMPT",
    # Caption highlight
    "caption_highlight_step",
    "HighlightCaptioner",
    "CAPTION_HIGHLIGHT_PROMPT",
]
