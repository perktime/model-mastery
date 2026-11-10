# Model Mastery

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft-foundry/model-mastery)

Model Mastery brings together two complementary learning paths on Microsoft Foundry:

- Model-specific deep dives that explore partner models and their unique capabilities.
- Foundry-focused experiences that cover end-to-end agent development, evaluation, routing, and optimization on Foundry.

Each lab is modular and can be run as a short, focused exercise in **60–90 minutes** or combined with related notebooks to form a longer **3–4 hour workshop**. This makes the content flexible for live training, classroom delivery, or self-paced learning.

The content is intended for learners comfortable with Python, terminals, and cloud basics and is designed to be useful in both guided sessions and asynchronous study.

## Dev container package proxies

Both dev container configurations set `PIP_INDEX_URL` to
`https://packagefeedproxy.microsoft.io/pypi/simple` and `NPM_CONFIG_REGISTRY` to
`https://packagefeedproxy.microsoft.io/npm/`. These settings apply to setup
commands and subsequent pip and npm installs inside the container.

After updating an existing Codespace or dev container, run **Dev Containers:
Rebuild Container** from the VS Code command palette to apply the settings and
rerun dependency installation.

<br/>

## Learning paths in the series

| # | Experience | Focus | Status | Start here |
|---|---|---|---|---|
| 1 | **Anthropic on Foundry** | Claude family deep dive | ✅ Ready | [`anthropic/`](./anthropic/) |
| 2 | **Cohere on Foundry** | Command A, Embed v4, Rerank v4 deep dive | ✅ Ready | [`cohere/README.md`](./cohere/README.md) |
| 3 | **Model router on Foundry Models** | End-to-end optimization and routing on Foundry | ✅ Ready | [`foundry/model-router`](./foundry/model-router) |
| 4 | **Agent builder on Foundry Models** | From Model Selection to Agent Optimization on Foundry | ✅ Ready | [`foundry/agent-builder`](./foundry/agent-builder) |

> Each learning path is fully self-contained. You can start with whichever model family you care about, or begin with a Foundry optimization track. Follow the setup steps in the folder you choose, and combine notebooks into a longer workshop whenever you want a deeper session.
