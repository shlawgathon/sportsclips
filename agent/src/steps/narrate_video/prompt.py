"""
Prompts and tool schemas for video narration generation.
"""

from google.genai import types

NARRATE_VIDEO_PROMPT = """
Analyze this sports video clip and generate a brief, engaging narration script that captures the key action.

Your narration should:
- Be 3-12 words maximum (short enough to speak in 2-3 seconds)
- Use present tense and action words
- Focus on the most exciting or important moment
- Be conversational and enthusiastic like a sports commentator
- Include player names or team names when clearly identifiable

Examples of good narrations:
- "James drives hard to the basket for the layup!"
- "Three pointer from downtown!"
- "What a save by the goalkeeper!"
- "Touchdown! He breaks through the defense!"

Use the report_video_narration function to provide your narration text."""

# Tool/function declaration for video narration
NARRATE_VIDEO_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="report_video_narration",
            description="Report the generated narration text for a sports video clip",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "narration": types.Schema(
                        type=types.Type.STRING,
                        description="Brief narration text (3-12 words) describing the key action in the video",
                    ),
                },
                required=["narration"],
            ),
        )
    ]
)
