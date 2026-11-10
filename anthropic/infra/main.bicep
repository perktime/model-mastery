targetScope = 'subscription'

import { ModelDeployments } from './core/ai/ai-project.bicep'
import { ConnectionConfiguration } from './core/ai/connection.bicep'

@minLength(1)
@maxLength(40)
param environmentName string
param resourceGroupName string = 'rg-${environmentName}'
param createResourceGroup bool = true
@description('Resource group and monitoring location. Model deployments use foundryLocation.')
param location string = 'eastus2'
@description('Foundry account/project/model location; models cannot move independently of their account.')
param foundryLocation string = location
@description('East US supports Free-tier semantic ranking and agentic retrieval. Verify current capacity.')
param searchLocation string = 'eastus'
@minLength(36)
@maxLength(36)
param developerPrincipalId string
@allowed(['User', 'Group', 'ServicePrincipal'])
param developerPrincipalType string = 'User'
@description('Account/project roles are created only for a new Foundry account.')
param assignDeveloperRoles bool = true
@description('Disable when these Search grants are already managed outside this deployment.')
param assignSearchRoles bool = true
@description('Disable when monitoring grants are already managed outside this deployment.')
param assignMonitoringRoles bool = true
param tags object = {}

param useExistingFoundryProject bool = false
param existingFoundryResourceGroupName string = resourceGroupName
param existingFoundryAccountName string = ''
param existingFoundryProjectName string = ''

@description('Required real organization attestation for new Claude deployments; unused with an existing project.')
@minLength(1)
param claudeOrganizationName string
@minLength(2)
@maxLength(2)
param claudeCountryCode string
@allowed(['technology', 'finance', 'healthcare', 'education', 'retail', 'manufacturing', 'government', 'media', 'other'])
param claudeIndustry string
param modelDeployments ModelDeployments = {
  sonnet: {
    name: 'claude-sonnet-5-5'
    model: 'claude-sonnet-5-5'
    version: '1'
    capacity: 25
    sku: 'GlobalStandard'
  }
  haiku: {
    name: 'claude-haiku-5-5'
    model: 'claude-haiku-5-5'
    version: '1'
    capacity: 25
    sku: 'GlobalStandard'
  }
}

param existingSearchName string = ''
param searchResourceGroupName string = resourceGroupName
@allowed(['free', 'basic'])
param searchSku string = 'free'
param knowledgeBaseName string = 'cupcake-store-kb'

param enableMonitoring bool = true
param monitoringResourceGroupName string = resourceGroupName
param existingLogAnalyticsName string = ''
param existingApplicationInsightsName string = ''
@description('An existing project connection to reuse. Its target must match the selected Application Insights.')
param existingMonitoringConnectionName string = ''
param monitoringConnectionName string = 'sparkles-application-insights'
param dashboardName string = ''

@description('Existing trusted Cupcake Store MCP URL, including its /mcp/ trailing slash. Empty leaves it unconfigured.')
param cupcakeMcpUrl string = ''
param enableEvaluatorConnection bool = false
param evaluatorEndpointUrl string = ''
param evaluatorConnectionName string = 'mm-eval-endpoint'
@secure()
param evaluatorEndpointApiKey string = ''
param additionalConnections ConnectionConfiguration[] = []
@secure()
param connectionCredentials object = {}

var abbreviations = loadJsonContent('./abbreviations.json')
var suffix = uniqueString(subscription().subscriptionId, resourceGroupName, environmentName)
var resourceTags = union(tags, {
  'azd-env-name': environmentName
})
var accountName = '${abbreviations.foundryAccount}-sparkles-${suffix}'
var projectName = '${abbreviations.foundryProject}-sparkles-${suffix}'
var searchName = empty(existingSearchName) ? '${abbreviations.searchService}-sparkles-${suffix}' : existingSearchName
var workspaceName = empty(existingLogAnalyticsName)
  ? '${abbreviations.logAnalytics}-sparkles-${suffix}'
  : existingLogAnalyticsName
var insightsName = empty(existingApplicationInsightsName)
  ? '${abbreviations.applicationInsights}-sparkles-${suffix}'
  : existingApplicationInsightsName

resource group 'Microsoft.Resources/resourceGroups@2024-03-01' = if (createResourceGroup) {
  name: resourceGroupName
  location: location
  tags: resourceTags
}

module newFoundry './core/ai/ai-project.bicep' = if (!useExistingFoundryProject) {
  name: 'sparkles-foundry-${suffix}'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: foundryLocation
    tags: resourceTags
    accountName: accountName
    projectName: projectName
    modelDeployments: modelDeployments
    claudeOrganizationName: claudeOrganizationName
    claudeCountryCode: claudeCountryCode
    claudeIndustry: claudeIndustry
    developerPrincipalId: developerPrincipalId
    developerPrincipalType: developerPrincipalType
    assignDeveloperRoles: assignDeveloperRoles
  }
  dependsOn: [
    group
  ]
}

module existingFoundry './core/ai/existing-ai-project.bicep' = if (useExistingFoundryProject) {
  name: 'sparkles-existing-foundry-${suffix}'
  scope: resourceGroup(existingFoundryResourceGroupName)
  params: {
    accountName: existingFoundryAccountName
    projectName: existingFoundryProjectName
    sonnetDeploymentName: modelDeployments.sonnet.name
    haikuDeploymentName: modelDeployments.haiku.name
  }
  dependsOn: [
    group
  ]
}

var foundry = {
  accountName: useExistingFoundryProject ? existingFoundry!.outputs.accountName : newFoundry!.outputs.accountName
  accountId: useExistingFoundryProject ? existingFoundry!.outputs.accountId : newFoundry!.outputs.accountId
  projectName: useExistingFoundryProject ? existingFoundry!.outputs.projectName : newFoundry!.outputs.projectName
  projectId: useExistingFoundryProject ? existingFoundry!.outputs.projectId : newFoundry!.outputs.projectId
  projectPrincipalId: useExistingFoundryProject
    ? existingFoundry!.outputs.projectPrincipalId
    : newFoundry!.outputs.projectPrincipalId
  foundryEndpoint: useExistingFoundryProject
    ? existingFoundry!.outputs.foundryEndpoint
    : newFoundry!.outputs.foundryEndpoint
  projectEndpoint: useExistingFoundryProject
    ? existingFoundry!.outputs.projectEndpoint
    : newFoundry!.outputs.projectEndpoint
  sonnetDeploymentName: useExistingFoundryProject
    ? existingFoundry!.outputs.sonnetDeploymentName
    : newFoundry!.outputs.sonnetDeploymentName
  haikuDeploymentName: useExistingFoundryProject
    ? existingFoundry!.outputs.haikuDeploymentName
    : newFoundry!.outputs.haikuDeploymentName
}
var foundryResourceGroup = useExistingFoundryProject ? existingFoundryResourceGroupName : resourceGroupName

module search './core/search/azure_ai_search.bicep' = {
  name: 'sparkles-search-${suffix}'
  scope: resourceGroup(searchResourceGroupName)
  params: {
    location: searchLocation
    tags: resourceTags
    name: searchName
    useExisting: !empty(existingSearchName)
    sku: searchSku
    developerPrincipalId: developerPrincipalId
    developerPrincipalType: developerPrincipalType
    assignDeveloperRoles: assignSearchRoles
  }
  dependsOn: [
    group
  ]
}

module workspace './core/monitor/loganalytics.bicep' = if (enableMonitoring && empty(existingApplicationInsightsName)) {
  name: 'sparkles-workspace-${suffix}'
  scope: resourceGroup(monitoringResourceGroupName)
  params: {
    location: location
    tags: resourceTags
    name: workspaceName
    useExisting: !empty(existingLogAnalyticsName)
    developerPrincipalId: developerPrincipalId
    developerPrincipalType: developerPrincipalType
    assignDeveloperRoles: assignMonitoringRoles
  }
  dependsOn: [
    group
  ]
}

module insights './core/monitor/applicationinsights.bicep' = if (enableMonitoring) {
  name: 'sparkles-insights-${suffix}'
  scope: resourceGroup(monitoringResourceGroupName)
  params: {
    location: location
    tags: resourceTags
    name: insightsName
    useExisting: !empty(existingApplicationInsightsName)
    workspaceResourceId: enableMonitoring && empty(existingApplicationInsightsName) ? workspace!.outputs.id : ''
    developerPrincipalId: developerPrincipalId
    developerPrincipalType: developerPrincipalType
    assignDeveloperRoles: assignMonitoringRoles
  }
  dependsOn: [
    group
  ]
}

module monitoringConnection './core/ai/connection.bicep' = if (enableMonitoring && empty(existingMonitoringConnectionName)) {
  name: 'sparkles-monitoring-connection-${suffix}'
  scope: resourceGroup(foundryResourceGroup)
  params: {
    accountName: foundry.accountName
    projectName: foundry.projectName
    configuration: {
      name: monitoringConnectionName
      category: 'AppInsights'
      target: enableMonitoring ? insights!.outputs.id : ''
      authType: 'ApiKey'
      metadata: {
        ApiType: 'Azure'
        ResourceId: enableMonitoring ? insights!.outputs.id : ''
        location: enableMonitoring ? insights!.outputs.location : ''
      }
    }
    apiKey: enableMonitoring ? insights!.outputs.connectionString : null
  }
}

module dashboard './core/monitor/applicationinsights-dashboard.bicep' = if (enableMonitoring && !empty(dashboardName)) {
  name: 'sparkles-dashboard-${suffix}'
  scope: resourceGroup(monitoringResourceGroupName)
  params: {
    name: dashboardName
    location: location
    tags: resourceTags
    applicationInsightsId: enableMonitoring ? insights!.outputs.id : ''
  }
}

module evaluatorConnection './core/ai/connection.bicep' = if (enableEvaluatorConnection) {
  name: 'sparkles-evaluator-connection-${suffix}'
  scope: resourceGroup(foundryResourceGroup)
  params: {
    accountName: foundry.accountName
    projectName: foundry.projectName
    configuration: {
      name: evaluatorConnectionName
      category: 'ApiKey'
      target: evaluatorEndpointUrl
      authType: 'ApiKey'
    }
    apiKey: evaluatorEndpointApiKey
  }
}

module customConnections './core/ai/connection.bicep' = [
  for (configuration, index) in additionalConnections: {
    name: 'sparkles-connection-${suffix}-${index}'
    scope: resourceGroup(foundryResourceGroup)
    params: {
      accountName: foundry.accountName
      projectName: foundry.projectName
      configuration: configuration
      apiKey: configuration.authType == 'ApiKey'
        ? connectionCredentials[configuration.?credentialKey ?? configuration.name]
        : null
    }
  }
]

output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_RESOURCE_GROUP_ID string = subscriptionResourceId('Microsoft.Resources/resourceGroups', resourceGroupName)
output FOUNDRY_RESOURCE_GROUP string = foundryResourceGroup
output FOUNDRY_ACCOUNT_NAME string = foundry.accountName
output FOUNDRY_ACCOUNT_ID string = foundry.accountId
output FOUNDRY_PROJECT_NAME string = foundry.projectName
output FOUNDRY_PROJECT_ID string = foundry.projectId
output FOUNDRY_PROJECT_PRINCIPAL_ID string = foundry.projectPrincipalId
output AZURE_AI_PROJECT_ENDPOINT string = foundry.projectEndpoint
output FOUNDRY_ENDPOINT string = foundry.foundryEndpoint
output FOUNDRY_MODEL_DEPLOYMENT string = foundry.sonnetDeploymentName
output FOUNDRY_HAIKU_DEPLOYMENT string = foundry.haikuDeploymentName
output AZURE_SEARCH_ENDPOINT string = search.outputs.endpoint
output AZURE_SEARCH_NAME string = search.outputs.name
output AZURE_SEARCH_ID string = search.outputs.id
output KNOWLEDGE_BASE_NAME string = knowledgeBaseName
output APPLICATIONINSIGHTS_CONNECTION_STRING string = enableMonitoring ? insights!.outputs.connectionString : ''
output APPLICATIONINSIGHTS_RESOURCE_ID string = enableMonitoring ? insights!.outputs.id : ''
output LOG_ANALYTICS_RESOURCE_ID string = enableMonitoring ? insights!.outputs.workspaceId : ''
output APPLICATIONINSIGHTS_CONNECTION_NAME string = enableMonitoring
  ? (empty(existingMonitoringConnectionName) ? monitoringConnection!.outputs.name : existingMonitoringConnectionName)
  : ''
output DASHBOARD_RESOURCE_ID string = enableMonitoring && !empty(dashboardName) ? dashboard!.outputs.id : ''
output CUPCAKE_MCP_URL string = cupcakeMcpUrl
output EVAL_ENDPOINT_CONNECTION string = enableEvaluatorConnection ? evaluatorConnection!.outputs.name : ''
output EVAL_ENDPOINT_URL string = enableEvaluatorConnection ? evaluatorEndpointUrl : ''
output CUSTOM_CONNECTION_IDS array = [for (_, index) in additionalConnections: customConnections[index].outputs.id]
