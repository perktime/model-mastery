#!/usr/bin/env bash
set -euo pipefail

infra="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if command -v bicep >/dev/null 2>&1; then
  compiler="$(command -v bicep)"
else
  compiler="${AZURE_CONFIG_DIR:-$HOME/.azure}/bin/bicep"
fi
if [[ ! -x "$compiler" ]]; then
  printf 'Bicep CLI is missing. Install it with: az bicep install\n' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required for offline template assertions.\n' >&2
  exit 1
fi

temporary="$(mktemp -d)"
trap 'rm -f -- "$temporary"/*.json; rmdir -- "$temporary"' EXIT

"$compiler" build "$infra/main.bicep" --outfile "$temporary/main.json"
for fixture in "$infra"/tests/*.bicepparam; do
  "$compiler" build-params "$fixture" --outfile "$temporary/$(basename "$fixture" .bicepparam).json"
done

jq -e '
  def resource($type): first(.resources[] | select(.type == $type));
  .resources.newFoundry.properties.template as $foundry |
  .resources.existingFoundry.properties.template as $existing |
  .resources.search.properties.template as $search |
  .resources.insights.properties.template as $insights |
  .resources.monitoringConnection.properties.template as $connection |
  {
    matchingFoundryOutputs: (($foundry.outputs | keys) == ($existing.outputs | keys)),
    requiredLabOutputs: (([
      "AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "FOUNDRY_ACCOUNT_NAME",
      "FOUNDRY_PROJECT_NAME", "AZURE_AI_PROJECT_ENDPOINT", "FOUNDRY_ENDPOINT",
      "FOUNDRY_MODEL_DEPLOYMENT", "FOUNDRY_HAIKU_DEPLOYMENT", "AZURE_SEARCH_ENDPOINT",
      "KNOWLEDGE_BASE_NAME", "APPLICATIONINSIGHTS_CONNECTION_STRING", "CUPCAKE_MCP_URL",
      "EVAL_ENDPOINT_CONNECTION", "EVAL_ENDPOINT_URL"
    ] - (.outputs | keys)) | length == 0),
    claudeEndpointShape: ($foundry.outputs.foundryEndpoint.value |
      contains(".services.ai.azure.com/anthropic") and (contains("/v1/messages") | not)),
    existingFoundryReadOnly: (($existing.resources | length) == 0),
    monitoringDefault: (.parameters.enableMonitoring.defaultValue == true),
    evaluatorOptIn: (.parameters.enableEvaluatorConnection.defaultValue == false),
    freeSearchDefault: (.parameters.searchSku.defaultValue == "free"),
    sonnetDefault: (.parameters.modelDeployments.defaultValue.sonnet |
      .name == "claude-sonnet-5-5" and .model == "claude-sonnet-5-5"),
    haikuDefault: (.parameters.modelDeployments.defaultValue.haiku |
      .name == "claude-haiku-5-5" and .model == "claude-haiku-5-5"),
    secureEvaluatorKey: ((.parameters.evaluatorEndpointApiKey.type | ascii_downcase) == "securestring"),
    secureCredentialMap: ((.parameters.connectionCredentials.type | ascii_downcase) == "secureobject"),
    secureConnectionKey: (($connection.parameters.apiKey.type | ascii_downcase) == "securestring"),
    nonemptyConnectionKey: ($connection.parameters.apiKey.minLength == 1),
    keylessFoundry: ($foundry.resources.account.properties.disableLocalAuth == true),
    serialModels: ($foundry.resources.deployments.copy.mode == "serial" and $foundry.resources.deployments.copy.batchSize == 1),
    searchKeyCompatibility: (($search | resource("Microsoft.Search/searchServices")).properties.disableLocalAuth == false),
    searchEntraCompatibility: (($search | resource("Microsoft.Search/searchServices")).properties.authOptions.aadOrApiKey.aadAuthFailureMode == "http401WithBearerChallenge"),
    existingInsightsNotRecreated: (($insights | resource("Microsoft.Insights/components")).condition == "[not(parameters('\''useExisting'\''))]"),
    newFoundryGuard: (.resources.newFoundry.condition | contains("useExistingFoundryProject")),
    existingFoundryGuard: (.resources.existingFoundry.condition | contains("useExistingFoundryProject")),
    workspaceMonitoringGuard: (.resources.workspace.condition | contains("enableMonitoring")),
    workspaceReuseGuard: (.resources.workspace.condition | contains("existingApplicationInsightsName")),
    insightsMonitoringGuard: (.resources.insights.condition | contains("enableMonitoring")),
    connectionReuseGuard: (.resources.monitoringConnection.condition | contains("existingMonitoringConnectionName")),
    insightsConnectionCompatibility: (.resources.monitoringConnection.properties.parameters.configuration.value.authType == "ApiKey"),
    insightsConnectionAzureMetadata: (.resources.monitoringConnection.properties.parameters.configuration.value.metadata |
      .ApiType == "Azure" and (.ResourceId | startswith("[if(")) and (.location | startswith("[if("))),
    dashboardOptIn: (.resources.dashboard.condition | contains("dashboardName")),
    evaluatorGuard: (.resources.evaluatorConnection.condition | contains("enableEvaluatorConnection")),
    lazyWorkspaceReference: (.resources.insights.properties.parameters.workspaceResourceId |
      if type == "string" then . else .value end | startswith("[if(")),
    lazyInsightsReference: (.resources.monitoringConnection.properties.parameters.configuration.value.target | startswith("[if(")),
    noFoundryKeyOutput: (.outputs | has("FOUNDRY_API_KEY") | not),
    excludedResourceTypes: ([.. | objects | .type? | strings | select(startswith("Microsoft."))] |
      all(test("Microsoft\\.(Storage|ContainerRegistry|App)/|capabilityHosts"; "i") | not)),
    noKeyRetrieval: ([.. | strings] | all(test("listKeys\\(|listAdminKeys\\("; "i") | not))
  } |
  to_entries | map(select(.value != true)) |
  if length > 0 then error("Failed template contracts: " + (map(.key) | join(", "))) else true end
' "$temporary/main.json" >/dev/null

assert_json() {
  if ! jq -e "$2" "$3" >/dev/null; then
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
  fi
}

assert_json 'monitoring-disabled fixture' '.parameters.enableMonitoring.value == false' "$temporary/monitoring-disabled.json"
assert_json 'existing-project fixture' '.parameters.useExistingFoundryProject.value == true and .parameters.createResourceGroup.value == false' "$temporary/existing-project.json"
assert_json 'existing-search fixture' '.parameters.assignSearchRoles.value == false and .parameters.existingSearchName.value == "existing-search"' "$temporary/existing-search.json"
assert_json 'existing-monitoring fixture' '.parameters.existingMonitoringConnectionName.value == "existing-appinsights-connection"' "$temporary/existing-monitoring.json"
assert_json 'existing-workspace fixture' '.parameters.existingLogAnalyticsName.value == "existing-workspace"' "$temporary/existing-workspace.json"
assert_json 'evaluator-connections fixture' '.parameters.enableEvaluatorConnection.value == true and (.parameters.additionalConnections.value | length) == 3' "$temporary/evaluator-connections.json"
assert_json 'custom-models fixture' '.parameters.modelDeployments.value.sonnet.name == "workshop-reasoning" and .parameters.modelDeployments.value.sonnet.model == "claude-sonnet-5-5" and .parameters.modelDeployments.value.haiku.name == "workshop-generator" and .parameters.modelDeployments.value.haiku.model == "claude-haiku-5-5" and .parameters.searchSku.value == "basic"' "$temporary/custom-models.json"
assert_json 'no nested azd substitution' 'all(.parameters[].value | strings; test("\\$\\{[^}]*\\$\\{") | not)' "$infra/main.parameters.json"

printf 'PASS: compiled and linted infrastructure, eight parameter fixtures, and template assertions (offline only).\n'
