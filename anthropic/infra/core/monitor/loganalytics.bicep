param location string
param tags object
param name string
param useExisting bool = false
param developerPrincipalId string
@allowed(['User', 'Group', 'ServicePrincipal'])
param developerPrincipalType string
param assignDeveloperRoles bool = true

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (!useExisting) {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource existingWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: name
}

var logAnalyticsReader = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '73c42c96-874c-492b-b04d-ab87d138a893'
)

resource developerReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignDeveloperRoles) {
  name: guid(existingWorkspace.id, developerPrincipalId, logAnalyticsReader)
  scope: existingWorkspace
  properties: {
    principalId: developerPrincipalId
    principalType: developerPrincipalType
    roleDefinitionId: logAnalyticsReader
  }
  dependsOn: [
    workspace
  ]
}

output id string = existingWorkspace.id
output name string = existingWorkspace.name
