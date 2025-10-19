"""
Highlight detection step module.
"""

from .prompt import HIGHLIGHT_DETECTION_PROMPT
from .step import HighlightDetector, detect_highlight_step, is_highlight_step

__all__ = [
    "HighlightDetector",
    "detect_highlight_step",
    "is_highlight_step",
    "HIGHLIGHT_DETECTION_PROMPT",
]
