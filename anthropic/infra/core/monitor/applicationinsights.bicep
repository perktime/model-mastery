param location string
param tags object
param name string
param useExisting bool = false
param workspaceResourceId string = ''
param developerPrincipalId string
@allowed(['User', 'Group', 'ServicePrincipal'])
param developerPrincipalType string
param assignDeveloperRoles bool = true

resource insights 'Microsoft.Insights/components@2020-02-02' = if (!useExisting) {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceResourceId
  }
}

resource existingInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: name
}

var monitoringReader = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
)

resource developerReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignDeveloperRoles) {
  name: guid(existingInsights.id, developerPrincipalId, monitoringReader)
  scope: existingInsights
  properties: {
    principalId: developerPrincipalId
    principalType: developerPrincipalType
    roleDefinitionId: monitoringReader
  }
  dependsOn: [
    insights
  ]
}

output id string = existingInsights.id
output name string = existingInsights.name
output location string = useExisting ? existingInsights.location : insights!.location
output connectionString string = useExisting
  ? existingInsights.properties.ConnectionString
  : insights!.properties.ConnectionString
output workspaceId string = useExisting ? existingInsights.properties.WorkspaceResourceId : workspaceResourceId
