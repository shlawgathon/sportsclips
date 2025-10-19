"""
Prompts for highlight detection.
"""

HIGHLIGHT_DETECTION_PROMPT = """Analyze this 3-second video clip and determine if it contains a highlight moment worthy of saving.

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

Respond with ONLY "YES" if this is a highlight, or "NO" if it is not. No explanation needed."""
