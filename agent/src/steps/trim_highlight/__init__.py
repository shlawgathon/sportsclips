"""
Highlight trimming step module.
"""

from .prompt import TRIM_HIGHLIGHT_PROMPT
from .step import HighlightTrimmer, trim_highlight_step

__all__ = ["HighlightTrimmer", "trim_highlight_step", "TRIM_HIGHLIGHT_PROMPT"]
