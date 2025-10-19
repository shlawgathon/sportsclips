"""
Prompts and tool schemas for highlight detection.
"""

from google.genai import types

HIGHLIGHT_DETECTION_PROMPT = """Analyze this video clip and determine if it contains a highlight moment worthy of saving.

A highlight is:
- An exciting play or action (goals, dunks, touchdowns, impressive saves, etc.)
- A key moment in the game (close calls, dramatic moments)
- Exceptional athletic performance
- Crowd reactions to big moments

NOT a highlight:
- Standard gameplay with no notable action
- Replays of commercials or commentary
- Setup moments before action
- Timeout or break periods

Use the report_highlight_detection function to provide your assessment."""

# Tool/function declaration for highlight detection
HIGHLIGHT_DETECTION_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="report_highlight_detection",
            description="Report whether a video clip contains a highlight moment",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "is_highlight": types.Schema(
                        type=types.Type.BOOLEAN,
                        description="Whether this video contains a highlight moment",
                    ),
                    "confidence": types.Schema(
                        type=types.Type.STRING,
                        description="Confidence level: 'high', 'medium', or 'low'",
                        enum=["high", "medium", "low"],
                    ),
                    "reason": types.Schema(
                        type=types.Type.STRING,
                        description="Brief explanation of why this is or is not a highlight",
                    ),
                },
                required=["is_highlight", "confidence"],
            ),
        )
    ]
)
