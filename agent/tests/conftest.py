"""
Pytest configuration for loading environment variables from .env file.
"""

from pathlib import Path

from dotenv import load_dotenv


def pytest_configure(config):
    """
    Load environment variables from .env file before running tests.

    This hook runs before any tests are collected or executed.
    """
    # Get the agent directory (parent of tests directory)
    agent_dir = Path(__file__).parent.parent
    env_file = agent_dir / ".env"

    # Load .env file if it exists
    if env_file.exists():
        load_dotenv(env_file)
        print(f"\n✓ Loaded environment variables from {env_file}")
    else:
        print(f"\n⚠ Warning: .env file not found at {env_file}")
