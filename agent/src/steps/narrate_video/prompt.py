"""
Prompts and tool schemas for video narration generation.
"""

from google.genai import types

NARRATE_VIDEO_PROMPT = """
Analyze this sports video clip and generate a brief, engaging narration script that captures the key action.

You will be provided a video clip that may have audio. Regardless of the audio, you should provide narration that is engaging and informative.

Even if the video clip doesn't look like it has live action, please always provide a narration.

Your narration should:
- Be 3-12 words maximum (short enough to speak in 5-7 seconds)
- Use present tense and action words
- Be conversational and enthusiastic like a sports commentator
- Include player names or team names when clearly identifiable
- Pull out the main key detail and another esoteric small detail about the play.

Examples of good narrations:
- "James drives hard to the basket for the layup! The lakers lead 10-8."
- "Three pointer from downtown! Steph Curry with another one!"
- "What a save by the goalkeeper! Lev Yashin saves another one!"
- "Touchdown! Frank Gore wins the game for the 49ers!"

{previous_narrations}

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
