"""
Prompts and tool schemas for highlight trimming.
"""

from google.genai import types

TRIM_HIGHLIGHT_PROMPT_TEMPLATE = """I'm showing you 9 separate video segments (Chunk 1 through Chunk 9) in order, each exactly 4 seconds long (total 36 seconds of footage).

Each video you see corresponds to one chunk:
- Chunk 1: 0-4s (first video)
- Chunk 2: 4-8s (second video)
- Chunk 3: 8-12s (third video)
- Chunk 4: 12-16s (fourth video)
- Chunk 5: 16-20s (fifth video)
- Chunk 6: 20-24s (sixth video)
- Chunk 7: 24-28s (seventh video)
- Chunk 8: 28-32s (eighth video)
- Chunk 9: 32-36s (ninth video)

{detection_context}

Your task: Identify which consecutive chunks contain the actual highlight action.
- Include brief buildup (typically 1-2 chunks before the peak action)
- Include follow-through (typically 1 chunk after)
- Exclude dead time before or after the action
- Be conservative: when in doubt, include the chunk

Use the report_trim_segments function to specify which segments to keep."""

# Default prompt without detection context
TRIM_HIGHLIGHT_PROMPT = TRIM_HIGHLIGHT_PROMPT_TEMPLATE.format(detection_context="")

# Tool/function declaration for highlight trimming
TRIM_HIGHLIGHT_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="report_trim_segments",
            description="Report which video segments should be kept for the highlight",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "start_segment": types.Schema(
                        type=types.Type.INTEGER,
                        description="Starting segment number (1-9, inclusive)",
                    ),
                    "end_segment": types.Schema(
                        type=types.Type.INTEGER,
                        description="Ending segment number (1-9, inclusive)",
                    ),
                    "reasoning": types.Schema(
                        type=types.Type.STRING,
                        description="Brief explanation of why these segments were selected",
                    ),
                },
                required=["start_segment", "end_segment"],
            ),
        )
    ]
)
