"""
Prompts and tool schemas for highlight trimming.
"""

from google.genai import types

TRIM_HIGHLIGHT_PROMPT_TEMPLATE = """Analyze this video clip which contains a highlight moment. Your task is to identify the exact portion of the video that should be kept.

The video is divided into 7 chunks of 2 seconds each (total 14 seconds):
- Chunk 1: 0-2s
- Chunk 2: 2-4s
- Chunk 3: 4-6s
- Chunk 4: 6-8s
- Chunk 5: 8-10s
- Chunk 6: 10-12s
- Chunk 7: 12-14s

{detection_context}

Identify which consecutive segments contain the actual highlight action. Include a brief buildup and follow-through, but exclude unnecessary footage before or after. It is better to be conservative and include more of the footage.

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
                        description="Starting segment number (1-7, inclusive)",
                    ),
                    "end_segment": types.Schema(
                        type=types.Type.INTEGER,
                        description="Ending segment number (1-7, inclusive)",
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
