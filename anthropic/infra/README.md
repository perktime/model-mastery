# Sparkles workshop infrastructure

Infrastructure for the [Anthropic workshop](../README.md), not an agent
deployment. All Bicep artifacts live in this directory. Nothing here changes the
lab code or reads or updates `anthropic/.env`.

**Important: new Foundry accounts disable API-key authentication. The current lab
scripts still require `FOUNDRY_API_KEY` and will not run against these new accounts
until the keyless client changes described below are implemented and tested.**
Generating or compiling this infrastructure does not complete that migration.

## What this creates

- A resource group (optional), an AIServices S0 Foundry account, and a project,
  both with system-assigned identities.
- Two sequential Claude deployments: `claude-sonnet-5-5` and `claude-haiku-5-5`.
  Both default to version `1`, GlobalStandard, and capacity `25`.
- Azure AI Search, defaulting to Free in East US, with semantic ranking and
  Entra ID authentication only (API keys are disabled).
- Optional workspace-based Application Insights and a PerGB2018 Log Analytics
  workspace with 30-day retention; monitoring is enabled by default.
- An Application Insights project connection unless an existing connection name
  is supplied. This connection uses the Insights connection string through a
  secure `ApiKey` parameter, matching the original workshop infrastructure;
  its metadata includes `ApiType: Azure`, the Insights resource ID, and the
  Insights resource's actual location. Claude inference still uses Entra ID.
  An optional dashboard provides links to
  monitoring views; it does not create availability tests or populate metrics
  without application telemetry.
- An optional connection to an **already deployed** Claude evaluator, plus
  explicitly configured additional project connections.

No hosted or prompt agents, capability hosts, containers, ACR, Bing resources,
storage accounts, Blob containers, embedding models, or networking are created.
Sparkles and its build loop remain local. Claude's web search does not need a
separate Bing grounding resource.

### Why no storage?

[Ingestion](../foundry-iq/ingest_foundry_iq.py) reads
[the local store document](../foundry-iq/docs/cupcake-store-info.md) and uploads
chunks directly into Search. [Cloud evaluation](../sparkles-evals/run_cloud_eval.py)
submits JSONL rows inline. Neither requires a customer-managed Blob container.
The separately hosted Cupcake Store MCP service uses **Table Storage** for
configuration and orders. That service and its storage are outside this scope.
The existing [MCP](../cupcake-mcp-setup.md) and
[evaluator](../eval-endpoint/README.md) runbooks use ACR; those deployment paths
are deliberately not automated here.

## Prerequisites and availability

- Azure CLI and Bicep CLI (`az bicep install` if absent). The offline tests also
  need Bash and `jq`; no Python packages are needed for infrastructure validation.
- An Azure subscription eligible for Claude in Foundry, with the necessary
  Marketplace permissions, model access, and quota.
- The deployer needs subscription permissions to create the resource group and
  deployments, resource-management permissions in every target group, and
  `Microsoft.Authorization/roleAssignments/write` at the assigned scopes.
  Contributor alone cannot create role assignments. Use an appropriately scoped
  RBAC administrator/Owner or arrange grants with an administrator.
- Resource providers: `Microsoft.CognitiveServices`, `Microsoft.Search`,
  `Microsoft.Insights`, `Microsoft.OperationalInsights`, and `Microsoft.Portal`
  only if the dashboard is enabled. Have an administrator register missing
  providers separately.
- Real organization name, ISO two-letter country code, and lowercase industry
  attestation values. Deploying Claude with `modelProviderData` accepts provider
  terms; review the [official starter-kit terms guidance][claude-deploy] before
  deployment. Do not copy the offline test's organization into a real deployment.

The Foundry/account/model location defaults to East US 2. Search defaults to
East US **independently**: the [Search region table][search-regions] identifies
East US as supporting Free-tier agentic retrieval and semantic ranking, and
flags capacity restrictions for new services in East US 2. Free supports no
Search managed identity and only one Free service per subscription. The local
ingestion principal does not need a Search managed identity. Set `searchSku` to
`basic` explicitly when Free is unavailable; there is no automatic paid upgrade.

The defaults request Claude Sonnet 5.5 and Haiku 5.5; verify both in the
[current model catalog][claude-models].
Model definitions use the official starter kit's Anthropic format, version `1`,
and model-provider attestation shape. Catalog presence is **not** confirmation
of subscription eligibility, regional deployment availability, or remaining
quota. Confirm the selected model/version/SKU/capacity in the target region
before deployment using the Foundry catalog and quota page. For an existing
account, also check the read-only
`az cognitiveservices account list-models --name <account-name> --resource-group <resource-group> --output table`.
If unavailable, stop and explicitly configure a supported
choice; these templates do not silently substitute models or regions.

`foundryLocation` controls the account, project, and model deployments together.
A model deployment cannot be placed independently in another region under the
same account. `searchLocation` and monitoring's `location` are independent.
This template targets Azure public cloud, not sovereign-cloud DNS suffixes.

## Parameters

Required: `environmentName`, `developerPrincipalId` (Entra **object** ID, not
application/client ID), `claudeOrganizationName`, `claudeCountryCode`, and
`claudeIndustry`. Attestation parameters remain required but are unused in
existing-project mode.

| Parameter | Default / behavior |
| --- | --- |
| `resourceGroupName` | `rg-{environmentName}` |
| `createResourceGroup` | `true`; set `false` to leave an existing group and its tags untouched |
| `location` / `foundryLocation` / `searchLocation` | `eastus2` / `location` / `eastus` |
| `developerPrincipalType` | `User`; also `Group` or `ServicePrincipal` |
| `useExistingFoundryProject` | `false` |
| `existingFoundryAccountName`, `existingFoundryProjectName` | Required when reusing Foundry |
| `existingFoundryResourceGroupName` | Target resource group; same subscription only |
| `modelDeployments` | Object with required `sonnet` and `haiku` definitions: `name`, `model`, `version`, `capacity`, `sku` |
| `existingSearchName`, `searchResourceGroupName` | Empty means create Search; group defaults to target group |
| `searchSku`, `knowledgeBaseName` | `free`, `cupcake-store-kb` |
| `enableMonitoring` | `true`; `false` disables workspace, Insights, its connection, and dashboard |
| `monitoringResourceGroupName` | Target resource group |
| `existingLogAnalyticsName` | Reuse a workspace when creating new Insights |
| `existingApplicationInsightsName` | Reuse Insights and its actual workspace; do not create an unused workspace |
| `existingMonitoringConnectionName` | Reuse a project connection without recreating it; it must target the chosen Insights resource |
| `dashboardName` | Empty: no dashboard |
| `assignDeveloperRoles` | New Foundry account/project grants; no effect on existing Foundry |
| `assignSearchRoles`, `assignMonitoringRoles` | `true`; disable if grants are already managed externally |
| `cupcakeMcpUrl` | Existing trusted URL, including `/mcp/`; no service deployment |
| `enableEvaluatorConnection` | `false`; explicitly enable with a nonempty endpoint URL and secure API key |
| `evaluatorConnectionName` | `mm-eval-endpoint` |
| `additionalConnections`, `connectionCredentials` | Typed connection list and a separate secure key map |
| `tags` | Additional tags; `azd-env-name` is always set to the environment name |

Other target resource groups must already exist. Only `resourceGroupName` can be
created by this template. Existing Foundry must be an AIServices account with
project management, a custom subdomain, and a system-assigned project identity.
Existing resources must already support the lab: reusing Search does not enable
semantic ranking or change its authentication, SKU, or region; reusing Foundry
does not change authentication, deploy models, or create account/project grants.
Existing Application Insights must be workspace-based.
For existing deployments, configure `modelDeployments.sonnet.name` and
`modelDeployments.haiku.name` to match their actual deployment names.

Role assignment IDs are deterministic across reruns. Azure can reject a grant
already created with a different assignment ID: disable the corresponding
`assign*Roles` switch and keep that grant externally managed instead of attempting
to create a duplicate. Existing Insights retains its workspace; arrange Log
Analytics read permission on that workspace separately if needed.

### Permissions granted

| Principal | Scope | Role |
| --- | --- | --- |
| Developer | New Foundry account | Cognitive Services User (`a97b65f3-24c7-4388-baec-2e87135dc908`) for Claude inference |
| Developer | New Foundry project | Foundry User (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) for project/evaluation operations |
| Ingestion developer | Search | Search Service Contributor (`7ca78c08-252a-4471-8644-bb5ff32d4ba0`) and Search Index Data Contributor (`8ebe5a00-799e-43f5-93ac-243d3dce84a7`) |
| Developer | Created/referenced workspace module | Log Analytics Reader (`73c42c96-874c-492b-b04d-ab87d138a893`) |
| Developer | Application Insights | Monitoring Reader (`43d0d8ad-25c7-4714-9337-8ba259a9fe05`) |

The documented built-in inference role is not inference-only: it also permits
account reads and key listing. The template does not exercise those permissions
and new accounts disable key authentication. No OpenAI-specific grants are used.
The account/project identities receive no unnecessary Search, Blob, inference,
or Log Analytics roles: local callers perform those operations. These runtime
roles do not give the developer subscription-wide deployment/RBAC administration.
Allow time for role propagation before testing.

## Validate locally (no Azure changes)

From the repository root:

```bash
bash anthropic/infra/tests/validate.sh
```

This compiles and lints the module graph, compiles eight parameter fixtures
(default, monitoring off, existing project/Search/Insights/workspace, evaluator
and additional connections, custom models), and asserts template contracts:
secure parameters, no key outputs, keyless new accounts, serial models,
conditional guards, matching Foundry outputs, and excluded resource types.
Temporary compiled files are removed. Tests use non-secret sentinel values and
must **not** be deployed.

This is offline validation, not ARM deployment validation, a quota check, or a
runtime smoke test. No `az deployment validate`, what-if, ingestion, evaluation,
model inference, resource creation, or deletion is performed by the tests.

## Intended deployment commands (documentation only)

Nothing automatically runs the following commands. Deployment changes Azure
resources and may incur costs. Review the configuration and authentication
prerequisites first.

### Ordinary Azure CLI

Create your own untracked parameter file outside this directory (do not use the
azd substitution file directly with Azure CLI). A minimal `sparkles.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": { "value": "my-sparkles" },
    "developerPrincipalId": { "value": "<your-entra-object-id>" },
    "claudeOrganizationName": { "value": "<real organization>" },
    "claudeCountryCode": { "value": "<ISO country code>" },
    "claudeIndustry": { "value": "education" }
  }
}
```

After review, from the repository root:

```bash
az login
az account set --subscription "<subscription-id>"
az deployment sub create \
  --name sparkles-infra \
  --location eastus2 \
  --template-file anthropic/infra/main.bicep \
  --parameters @/absolute/path/to/sparkles.parameters.json
```

Use secure deployment tooling or a protected parameter file for evaluator keys
and `connectionCredentials`; do not put real keys in shell history or committed
JSON. API-key connection entries require a matching secure key-map entry
(`credentialKey`, or the connection name). Missing map entries cause an explicit
deployment expression error; blank keys fail the module's minimum-length check.
Connection names must be distinct from each other and the monitoring/evaluator
connection names. Supported connection authentication is `AAD`, `None`, and
`ApiKey`; add another method only when this lab actually needs it.

### Azure Developer CLI

`main.parameters.json` is **azd-only**: azd resolves `${VARIABLE=default}` and
converts values to template parameter types. Azure CLI does not perform that
substitution. Optional complex settings such as `modelDeployments` and
`additionalConnections` should be native JSON objects/arrays in a reviewed
parameter file, not JSON embedded in an environment-variable string.

The `azure.yaml` in this directory sets `infra.provider: bicep`, `infra.path: .`,
and `infra.module: main`, because the Bicep template is alongside it. Run the
commands below from `anthropic/infra`. If configuring an azd project at the
repository root instead, use `infra.path: anthropic/infra`; for an `azure.yaml`
inside `anthropic/`, use `infra.path: infra`. Do not replace another workshop's
azd configuration.

Initial setup is:

```bash
cd anthropic/infra
azd auth login
azd env new my-sparkles
azd env set AZURE_RESOURCE_GROUP rg-my-sparkles
azd env set AZURE_LOCATION eastus2
azd env set FOUNDRY_LOCATION eastus2
azd env set AZURE_PRINCIPAL_ID "<your-entra-object-id>"
azd env set CLAUDE_ORGANIZATION_NAME "<real organization>"
azd env set CLAUDE_COUNTRY_CODE "<ISO country code>"
azd env set CLAUDE_INDUSTRY education
# Only after reviewing costs, terms, and the keyless migration:
azd provision
```

`AZURE_LOCATION` must be saved in the selected azd environment, even though
Bicep defaults resource locations to East US 2. azd also uses this value for the
subscription deployment's metadata location; a template parameter default does
not supply that location. If validation reports that the deployment's
`location` property is missing, run `azd env set AZURE_LOCATION eastus2`
from this directory before retrying.

The parameter file also maps `CREATE_RESOURCE_GROUP`, `ASSIGN_DEVELOPER_ROLES`,
`ASSIGN_SEARCH_ROLES`, `ASSIGN_MONITORING_ROLES`, `USE_EXISTING_AI_PROJECT`,
`EXISTING_FOUNDRY_ACCOUNT_NAME`, `EXISTING_FOUNDRY_PROJECT_NAME`,
`EXISTING_AZURE_SEARCH_NAME`, `AZURE_SEARCH_SKU`, `KNOWLEDGE_BASE_NAME`,
`ENABLE_MONITORING`, existing monitoring names,
`APPLICATIONINSIGHTS_DASHBOARD_NAME`, `CUPCAKE_MCP_URL`, and evaluator settings.
For cross-resource-group reuse, explicitly add the corresponding
template parameters to your reviewed azd parameter configuration.
Keep local azd environment files out of source control, especially if setting
the evaluator key. No Foundry or Search keys are retrieved or exported.

## Outputs and post-provisioning steps

Outputs match these existing lab environment names; review and merge individual
non-secret values yourself. Never overwrite the entire environment file:

| Output | Lab use |
| --- | --- |
| `FOUNDRY_ENDPOINT` | Claude base URL ending in `/anthropic`, never `/v1/messages` |
| `FOUNDRY_MODEL_DEPLOYMENT`, `FOUNDRY_HAIKU_DEPLOYMENT` | Model deployment names |
| `AZURE_AI_PROJECT_ENDPOINT` | Cloud evaluation client |
| `AZURE_SEARCH_ENDPOINT`, `KNOWLEDGE_BASE_NAME` | Direct Foundry IQ MCP access |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Local OpenTelemetry; set `ENABLE_OTEL=1` separately |
| `CUPCAKE_MCP_URL` | Supplied existing store URL, including trailing slash |
| `EVAL_ENDPOINT_CONNECTION`, `EVAL_ENDPOINT_URL` | Optional existing evaluator integration |
| `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `FOUNDRY_ACCOUNT_NAME`, `FOUNDRY_PROJECT_NAME` | Deployment administration and connection scripts |

Resource IDs, tenant ID, project principal ID, actual Foundry resource group,
monitoring connection name, dashboard ID, and custom connection IDs are also
exported. For cross-group Foundry reuse, use `FOUNDRY_RESOURCE_GROUP` rather than
the infrastructure's group when running the existing connection script.
Disabled features return empty strings; custom connection IDs return an array.
No API keys, tokens, or connection credentials are outputs. The Application
Insights connection string is ingestion configuration, not an authorization
credential; treat it as operational configuration and avoid publishing it.

After a future deployment, **manually**:

1. Complete and test the keyless application changes below.
2. With the Search ingestion roles and `az login`, run the
   [existing ingestion workflow](../foundry-iq/README.md); it signs in with
   `az login` and uses no key.
   Preserve `minimal` retrieval reasoning effort, `extractiveData`, the text-only
   index, and MCP API version `2026-08-01-preview`.
3. Put only `AZURE_SEARCH_ENDPOINT` and `KNOWLEDGE_BASE_NAME` in the local
   `.env`. The Search service has API keys disabled, so there is no query key
   to create. The MCP client sends an Entra ID bearer token instead, so each
   person running the labs needs the Search Index Data Reader role (this
   template grants the deploying developer the ingestion roles). No Foundry
   Search connection replaces this direct MCP access.
4. Configure the external MCP URL and optionally enable local tracing.
   Look for local-loop spans in Application Insights, not hosted-agent traces.
5. To use the optional evaluator, supply a reachable trusted HTTPS `/evaluate`
   URL and a secure endpoint API key and enable its connection. Its `ApiKey`
   category/authentication matches
   [create_connection.py](../eval-endpoint/create_connection.py). Do not rerun
   that script for a connection already managed by Bicep.
6. Only then run model, knowledge-base, telemetry, and evaluation smoke tests.

### Keyless application follow-up (not implemented here)

The [official Claude authentication example][claude-auth] uses
`DefaultAzureCredential` with `get_bearer_token_provider` for
`https://ai.azure.com/.default`, passed as `azure_ad_token_provider` to
`AnthropicFoundry`. Use a refreshable provider, not a one-time token saved in
`.env`. For local development, sign in with `az login`; no client secret or
service principal is needed solely for interactive development.

The installed versions were checked without constructing a client or reading
environment secrets: `agent-framework-core` 1.17.0,
`agent-framework-anthropic` 1.0.0b260910, and `anthropic` 0.116.0.
The adapter's `AnthropicFoundryClient` accepts `azure_ad_token_provider` and
passes it through to `AsyncAnthropicFoundry`; it also accepts an
`anthropic_client` for explicit SDK-client injection. These versions match the
lab's framework requirements. Use that verified token-provider integration,
remove the explicit API-key argument, and check async credential lifecycle
and token refresh in the separate runtime migration. Do not silently fall back
to a stored key. Confirm stale key environment variables cannot override the
intended token-provider path. Recheck the signature if package versions change.

Affected executable sources:

- [agent.py](../sparkles-agent/agent.py), [catering.py](../sparkles-agent/catering.py),
  [receipt.py](../sparkles-agent/receipt.py), and snapshots
  [1.1](../sparkles-agent/snapshots/agent-module-1.1.py),
  [1.2](../sparkles-agent/snapshots/agent-module-1.2.py),
  [1.3](../sparkles-agent/snapshots/agent-module-1.3.py),
  [1.4](../sparkles-agent/snapshots/agent-module-1.4.py).
- [Loop common client](../sparkles-loop/common.py) and
  [standalone web search](../sparkles-loop/websearch.py).
- [Knowledge-base verification](../foundry-iq/verify_knowledge_base.py).
- [Evaluator service](../eval-endpoint/eval_endpoint.py), if its separately
  managed deployment is migrated. That service would need its own managed
  identity, inference grant, and matching authentication code; this template
  does not deploy or assign roles to it.

Related instructions requiring updates in that separate migration:
[standalone setup](../standalone/SETUP.md), [Lab 1](../standalone/lab1.md),
Skillable modules [1.1](../skillable/lab1/module-1.1.md),
[1.2](../skillable/lab1/module-1.2.md), [1.3](../skillable/lab1/module-1.3.md),
[1.4](../skillable/lab1/module-1.4.md), and the
[evaluator deployment guide](../eval-endpoint/README.md).
Leave `FOUNDRY_API_KEY` in the existing environment files untouched; leaving it
present is not a request to use it. The evaluation project's SDK and Search
ingestion already support `DefaultAzureCredential` and should retain that
behavior. Test every migrated surface before claiming end-to-end keyless support.

## Costs and teardown ownership

Claude inference and evaluation incur model charges; monitoring incurs ingestion
and retention charges. Basic Search is a continuously billed service; Free is
limited and does not guarantee available regional capacity. Existing external
MCP/evaluator services retain their separate compute/storage costs.

Keep a record of what this deployment owns. Deleting a deployment record does
not delete its resources. Delete only newly created resources after reviewing
dependencies and retention needs. Delete the resource group only if it was
created for this workshop and contains no shared/existing resources. Reused
Foundry, Search, monitoring, external services, and their data belong to their
original owners; do not delete them. Remove deployment-owned connections and
role assignments individually when they were added to shared resources.

## API choices and sources

Resource API versions are explicit: Cognitive Services account/project/model
`2025-10-01-preview` follows the official Claude starter kit; connections use
`2026-05-01` as in the repository's existing evaluator connection script; Search
uses `2025-05-01`, Insights `2020-02-02`, Log Analytics `2023-09-01`, dashboard
`2020-09-01-preview`, and role assignments `2022-04-01`.

One documented type-schema gap is deliberately suppressed, not silently omitted:
the published Bicep deployment type lacks `modelProviderData`, although the
[official Claude deployment sample][claude-bicep] requires it. The single
`BCP037` suppression is limited to that property. Compilation cannot certify
provider behavior; confirm API/model availability before a real deployment.

- [Claude provisioning, prerequisites, and provider terms][claude-deploy]
- [Claude model catalog][claude-models]
- [Claude SDK Entra authentication][claude-auth]
- [Foundry inference RBAC][inference-rbac]
- [AI/Search built-in role definitions][ai-roles]
- [Monitoring built-in roles][monitor-roles]
- [Search management schema][search-schema] and [regional support][search-regions]
- [Project connection schema][connection-schema]
- [Agent Framework Anthropic guide][framework-auth]
- [azd project discovery and infra path][azd-schema]

[claude-deploy]: https://learn.microsoft.com/azure/developer/ai/how-to/deploy-claude-foundry
[claude-bicep]: https://github.com/Azure-Samples/claude/blob/main/infra-bicep/infra/foundry.bicep
[claude-models]: https://learn.microsoft.com/azure/foundry/foundry-models/concepts/claude-models
[claude-auth]: https://learn.microsoft.com/azure/foundry/foundry-models/how-to/use-foundry-models-claude
[inference-rbac]: https://learn.microsoft.com/azure/foundry/foundry-models/how-to/configure-entra-id
[ai-roles]: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning
[monitor-roles]: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/monitor
[search-schema]: https://learn.microsoft.com/azure/templates/microsoft.search/2025-05-01/searchservices
[search-regions]: https://learn.microsoft.com/azure/search/search-region-support
[connection-schema]: https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-05-01/accounts/projects/connections
[framework-auth]: https://learn.microsoft.com/agent-framework/integrations/by-component/model-providers/anthropic
[azd-schema]: https://learn.microsoft.com/azure/developer/azure-developer-cli/azd-schema
