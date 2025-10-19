"""
Prompts for highlight trimming.
"""

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

Respond ONLY with the segment range in this format: "START-END" where START and END are segment numbers (1-7).
For example: "2-5" means keep segments 2, 3, 4, and 5.
Another example: "1-7" means keep all segments.
Another example: "3-6" means keep segments 3, 4, 5, and 6."""
