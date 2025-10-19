"""
Pipeline steps for video processing.

This module contains individual processing steps that can be chained
together in a video processing pipeline.
"""

from .agent import (
    caption_highlight_step,
    detect_highlight_step,
    trim_highlight_step,
)
from .interesting import (
    HIGHLIGHT_DETECTION_PROMPT,
    HighlightDetector,
    is_highlight_step,
)

__all__ = [
    "is_highlight_step",
    "HighlightDetector",
    "HIGHLIGHT_DETECTION_PROMPT",
    "detect_highlight_step",
    "trim_highlight_step",
    "caption_highlight_step",
]
