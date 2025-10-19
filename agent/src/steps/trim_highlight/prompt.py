"""
Prompts and tool schemas for highlight trimming.
"""

import google.generativeai as genai

TRIM_HIGHLIGHT_PROMPT = """Analyze this video clip which contains a highlight moment. Your task is to identify the exact portion of the video that should be kept.

The video is divided into 7 segments of 2 seconds each (total 14 seconds):
- Segment 1: 0-2s
- Segment 2: 2-4s
- Segment 3: 4-6s
- Segment 4: 6-8s
- Segment 5: 8-10s
- Segment 6: 10-12s
- Segment 7: 12-14s

Identify which consecutive segments contain the actual highlight action. Include a brief buildup and follow-through, but exclude unnecessary footage before or after.

Use the report_trim_segments function to specify which segments to keep."""

# Tool/function declaration for highlight trimming
TRIM_HIGHLIGHT_TOOL = genai.protos.Tool(
    function_declarations=[
        genai.protos.FunctionDeclaration(
            name="report_trim_segments",
            description="Report which video segments should be kept for the highlight",
            parameters=genai.protos.Schema(
                type=genai.protos.Type.OBJECT,
                properties={
                    "start_segment": genai.protos.Schema(
                        type=genai.protos.Type.INTEGER,
                        description="Starting segment number (1-7, inclusive)",
                    ),
                    "end_segment": genai.protos.Schema(
                        type=genai.protos.Type.INTEGER,
                        description="Ending segment number (1-7, inclusive)",
                    ),
                    "reasoning": genai.protos.Schema(
                        type=genai.protos.Type.STRING,
                        description="Brief explanation of why these segments were selected",
                    ),
                },
                required=["start_segment", "end_segment"],
            ),
        )
    ]
)
