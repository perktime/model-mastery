@minLength(2)
param accountName string
@minLength(2)
param projectName string
param sonnetDeploymentName string
param haikuDeploymentName string

resource account 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' existing = {
  parent: account
  name: projectName
}

var endpointBase = 'https://${account.properties.customSubDomainName}.services.ai.azure.com'

output accountId string = account.id
output accountName string = account.name
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output foundryEndpoint string = '${endpointBase}/anthropic'
output projectEndpoint string = '${endpointBase}/api/projects/${project.name}'
output sonnetDeploymentName string = sonnetDeploymentName
output haikuDeploymentName string = haikuDeploymentName
