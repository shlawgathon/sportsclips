"""
Prompts and tool schemas for highlight captioning.
"""

import google.generativeai as genai

CAPTION_HIGHLIGHT_PROMPT = """Analyze this sports highlight video and generate a compelling title and description.

Create a short, exciting title (5-10 words) that captures the essence of the play. Use action words and be specific about what happened.

Write a brief description (1-2 sentences) that provides context and details about the highlight.

Also identify the key action or event that occurred.

Use the report_highlight_caption function to provide the title, description, and key action."""

# Tool/function declaration for highlight captioning
CAPTION_HIGHLIGHT_TOOL = genai.protos.Tool(
    function_declarations=[
        genai.protos.FunctionDeclaration(
            name="report_highlight_caption",
            description="Report the generated title, description, and key action for a sports highlight",
            parameters=genai.protos.Schema(
                type=genai.protos.Type.OBJECT,
                properties={
                    "title": genai.protos.Schema(
                        type=genai.protos.Type.STRING,
                        description="Short, exciting title (5-10 words) capturing the essence of the play",
                    ),
                    "description": genai.protos.Schema(
                        type=genai.protos.Type.STRING,
                        description="Brief description (1-2 sentences) providing context and details",
                    ),
                    "key_action": genai.protos.Schema(
                        type=genai.protos.Type.STRING,
                        description="The main action or event in the highlight",
                    ),
                },
                required=["title", "description"],
            ),
        )
    ]
)
