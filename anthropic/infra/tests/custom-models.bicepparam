using '../main.bicep'

param environmentName = 'infra-validation'
param developerPrincipalId = '00000000-0000-0000-0000-000000000001'
param developerPrincipalType = 'ServicePrincipal'
param claudeOrganizationName = 'Offline validation only'
param claudeCountryCode = 'US'
param claudeIndustry = 'education'
param foundryLocation = 'swedencentral'
param searchLocation = 'swedencentral'
param searchSku = 'basic'
param modelDeployments = {
  sonnet: {
    name: 'workshop-reasoning'
    model: 'claude-sonnet-5-5'
    version: '1'
    capacity: 10
    sku: 'GlobalStandard'
  }
  haiku: {
    name: 'workshop-generator'
    model: 'claude-haiku-5-5'
    version: '1'
    capacity: 10
    sku: 'GlobalStandard'
  }
}
