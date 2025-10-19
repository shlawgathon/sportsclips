"""
Prompts and tool schemas for highlight captioning.
"""

from google.genai import types

CAPTION_HIGHLIGHT_PROMPT = """
Analyze this sports highlight video and generate a compelling title and description. This title and description will be used for a short form video.

Ensure you look closely at the videos to identify the key players and teams to include in your deliverables.

Here are your key deliverables:
- Create a short, exciting title (5-10 words) that captures the essence of the play. Use action words and be specific about what happened. Include the specifics about the players or teams involved in the play.
- Write a brief description (1-2 sentences) that provides context and details about the highlight. Include information about why the moment is so significant to the game.
- Also identify the key action or event that occurred for classification later.

Use the report_highlight_caption function to provide the title, description, and key action."""

# Tool/function declaration for highlight captioning
CAPTION_HIGHLIGHT_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="report_highlight_caption",
            description="Report the generated title, description, and key action for a sports highlight",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "title": types.Schema(
                        type=types.Type.STRING,
                        description="Short, exciting title (5-10 words) capturing the essence of the play",
                    ),
                    "description": types.Schema(
                        type=types.Type.STRING,
                        description="Brief description (1-2 sentences) providing context and details",
                    ),
                    "key_action": types.Schema(
                        type=types.Type.STRING,
                        description="The main action or event in the highlight (3-4 words)",
                    ),
                },
                required=["title", "description"],
            ),
        )
    ]
)
