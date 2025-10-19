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
)
from .narrate_video import (
    NARRATE_VIDEO_PROMPT,
    NARRATE_VIDEO_TOOL,
    VideoNarrator,
    narrate_video_step,
)
from .speak_text import TextSpeaker, speak_text_step
from .trim_highlight import (
    TRIM_HIGHLIGHT_PROMPT,
    HighlightTrimmer,
    trim_highlight_step,
)

__all__ = [
    # Detect highlight
    "detect_highlight_step",
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
    # Narrate video
    "narrate_video_step",
    "VideoNarrator",
    "NARRATE_VIDEO_PROMPT",
    "NARRATE_VIDEO_TOOL",
    # Speak text
    "speak_text_step",
    "TextSpeaker",
]
