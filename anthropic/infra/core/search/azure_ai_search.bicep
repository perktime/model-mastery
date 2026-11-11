param location string
param tags object
param name string
param useExisting bool = false
@allowed(['free', 'basic'])
param sku string = 'free'
param developerPrincipalId string
@allowed(['User', 'Group', 'ServicePrincipal'])
param developerPrincipalType string
param assignDeveloperRoles bool = true

resource search 'Microsoft.Search/searchServices@2025-05-01' = if (!useExisting) {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'Default'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
    semanticSearch: 'free'
  }
}

resource existingSearch 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: name
}

var roles = [
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
]

resource ingestionRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in roles: if (assignDeveloperRoles) {
    name: guid(
      existingSearch.id,
      developerPrincipalId,
      subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
    )
    scope: existingSearch
    properties: {
      principalId: developerPrincipalId
      principalType: developerPrincipalType
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
    }
    dependsOn: [
      search
    ]
  }
]

output id string = existingSearch.id
output name string = existingSearch.name
output endpoint string = 'https://${name}.search.windows.net'
