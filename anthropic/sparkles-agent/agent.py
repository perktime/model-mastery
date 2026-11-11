"""Sparkles - The Cupcake ordering agent (Module 1.1 starting point)

You will grow this file through Lab 1. Each module adds a small, marked
block. Completed versions of every module live in snapshots/ if you need
to catch up.
"""

import asyncio
import os

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv

from agent_framework import Agent
from agent_framework.foundry import AnthropicFoundryClient

# 1. Load settings from .env
load_dotenv()


def reply(response) -> str:
    """Sparkles' words, with a blank line between what it says before a tool
    call and its answer after (response.text runs them together)."""
    return "\n\n".join(m.text for m in response.messages if m.text)


async def main() -> None:
    # 2. The chat model: Claude on Microsoft Foundry, signed in with your Azure login
    chat_client = AnthropicFoundryClient(
        model=os.environ["FOUNDRY_MODEL_DEPLOYMENT"],
        azure_ad_token_provider=get_bearer_token_provider(
            DefaultAzureCredential(), "https://ai.azure.com/.default"),
        base_url=os.environ["FOUNDRY_ENDPOINT"],
    )

    # 3. The agent
    agent = Agent(client=chat_client, name="cupcake-agent")

    # 4. A session keeps the conversation history
    session = agent.create_session()
    print("Sparkles agent ready. Type 'exit' to quit.\n")

    while True:
        user_input = input("\033[1;35mYou:\033[0m\n")
        if user_input.lower() in ("exit", "quit"):
            break
        if not user_input.strip():
            continue
        response = await agent.run(user_input, session=session)
        print(f"\n\033[1;35mSparkles:\033[0m\n{reply(response)}\n")


if __name__ == "__main__":
    asyncio.run(main())
