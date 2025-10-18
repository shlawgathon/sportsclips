"""
Highlight detection step module.
"""

from .prompt import HIGHLIGHT_DETECTION_PROMPT
from .step import HighlightDetector, is_highlight_step

__all__ = ["HighlightDetector", "is_highlight_step", "HIGHLIGHT_DETECTION_PROMPT"]
