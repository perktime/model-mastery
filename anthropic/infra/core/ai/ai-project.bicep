@export()
type ModelDeployment = {
  @minLength(1)
  name: string
  @minLength(1)
  model: string
  @minLength(1)
  version: string
  @minValue(1)
  capacity: int
  sku: 'GlobalStandard' | 'DataZoneStandard'
}

@export()
type ModelDeployments = {
  sonnet: ModelDeployment
  haiku: ModelDeployment
}

param location string
param tags object
param accountName string
param projectName string
param modelDeployments ModelDeployments
@minLength(1)
param claudeOrganizationName string
@minLength(2)
@maxLength(2)
param claudeCountryCode string
@allowed(['technology', 'finance', 'healthcare', 'education', 'retail', 'manufacturing', 'government', 'media', 'other'])
param claudeIndustry string
param developerPrincipalId string
@allowed(['User', 'Group', 'ServicePrincipal'])
param developerPrincipalType string
param assignDeveloperRoles bool

var cognitiveServicesUserRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'a97b65f3-24c7-4388-baec-2e87135dc908'
)
var foundryUserRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)

resource account 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource developerInference 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignDeveloperRoles) {
  name: guid(account.id, developerPrincipalId, cognitiveServicesUserRole)
  scope: account
  properties: {
    principalId: developerPrincipalId
    principalType: developerPrincipalType
    roleDefinitionId: cognitiveServicesUserRole
  }
}

resource developerProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignDeveloperRoles) {
  name: guid(project.id, developerPrincipalId, foundryUserRole)
  scope: project
  properties: {
    principalId: developerPrincipalId
    principalType: developerPrincipalType
    roleDefinitionId: foundryUserRole
  }
}

@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview' = [
  for deployment in [modelDeployments.sonnet, modelDeployments.haiku]: {
    parent: account
    name: deployment.name
    sku: {
      name: deployment.sku
      capacity: deployment.capacity
    }
    properties: {
      model: {
        format: 'Anthropic'
        name: deployment.model
        version: deployment.version
      }
      // Required by the official Azure Claude starter kit; missing from published Bicep types.
      #disable-next-line BCP037
      modelProviderData: {
        organizationName: claudeOrganizationName
        countryCode: toUpper(claudeCountryCode)
        industry: claudeIndustry
      }
      versionUpgradeOption: 'NoAutoUpgrade'
      raiPolicyName: 'Microsoft.DefaultV2'
    }
    dependsOn: [
      project
      developerInference
    ]
  }
]

output accountId string = account.id
output accountName string = account.name
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output foundryEndpoint string = 'https://${account.name}.services.ai.azure.com/anthropic'
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output sonnetDeploymentName string = modelDeployments.sonnet.name
output haikuDeploymentName string = modelDeployments.haiku.name
