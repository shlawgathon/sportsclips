"""
Prompts and tool schemas for highlight captioning.
"""

from google.genai import types

CAPTION_HIGHLIGHT_PROMPT = """Analyze this sports highlight video and generate a compelling title and description.

Create a short, exciting title (5-10 words) that captures the essence of the play. Use action words and be specific about what happened.

Write a brief description (1-2 sentences) that provides context and details about the highlight.

Also identify the key action or event that occurred.

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
                        description="The main action or event in the highlight",
                    ),
                },
                required=["title", "description"],
            ),
        )
    ]
)
