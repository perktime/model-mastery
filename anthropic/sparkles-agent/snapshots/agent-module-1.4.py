"""Sparkles - The Cupcake ordering agent (completed through Module 1.4)"""

import asyncio
import json  # 👈 1.4
import os

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv

from agent_framework import Agent, MCPStreamableHTTPTool
from agent_framework.foundry import AnthropicFoundryClient

from receipt import make_receipt  # 👈 1.4

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

    # 3. Connect to the Cupcake Store MCP server (orders, stock)
    mcp_tool = MCPStreamableHTTPTool(
        name="cupcake-store",
        url=os.environ["CUPCAKE_MCP_URL"],
    )
    await mcp_tool.connect()

    # 4. Connect to the shop's knowledge base in Foundry IQ (policies)
    search_endpoint = os.environ["AZURE_SEARCH_ENDPOINT"].rstrip("/")
    search_token = get_bearer_token_provider(
        DefaultAzureCredential(), "https://search.azure.com/.default")
    kb_name = os.environ.get("KNOWLEDGE_BASE_NAME", "cupcake-store-kb")
    knowledge_tool = MCPStreamableHTTPTool(
        name="cupcake-knowledge-base",
        url=f"{search_endpoint}/knowledgebases/{kb_name}/mcp?api-version=2026-08-01-preview",
        header_provider=lambda _: {"Authorization": f"Bearer {search_token()}"},
        load_prompts=False,
    )
    await knowledge_tool.connect()

    # 5. Persona and welcome banner come from the MCP server
    instructions = await mcp_tool.get_prompt("agent_instructions")
    banner = await mcp_tool.get_prompt("welcome_banner")
    instructions += (
        "\n\nUse the cupcake-store tool for orders, stock, and order status. "
        "Use the cupcake-knowledge-base tool for store policies: hours, "
        "delivery, shipping, returns, allergens, loyalty, and bulk orders. "
        "Do not invent store information; look it up."
    )

    # 6. The agent, with two tool servers and a personality
    agent = Agent(
        client=chat_client,
        name="cupcake-agent",
        instructions=instructions,
        tools=[mcp_tool, knowledge_tool],
    )

    # 7. A session keeps the conversation history
    session = agent.create_session()
    print(banner)
    print("Type 'exit' to quit, or 'receipt' after ordering.\n")  # 👈 1.4

    response = await agent.run("hello", session=session)
    print(f"\033[1;35mSparkles:\033[0m\n{reply(response)}\n")
    last_reply = reply(response)  # 👈 1.4

    while True:
        user_input = input("\033[1;35mYou:\033[0m\n")
        if user_input.lower() in ("exit", "quit"):
            break
        if not user_input.strip():
            continue

        if user_input.lower() == "receipt":  # 👈 1.4
            receipt = make_receipt(last_reply)
            print("\n\033[1;32mReceipt (schema-valid):\033[0m")
            print(json.dumps(receipt, indent=2), "\n")
            continue

        response = await agent.run(user_input, session=session)
        last_reply = reply(response)  # 👈 1.4
        print(f"\n\033[1;35mSparkles:\033[0m\n{reply(response)}\n")

    await knowledge_tool.close()
    await mcp_tool.close()


if __name__ == "__main__":
    asyncio.run(main())
