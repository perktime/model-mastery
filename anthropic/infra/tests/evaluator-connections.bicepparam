using '../main.bicep'

param environmentName = 'infra-validation'
param developerPrincipalId = '00000000-0000-0000-0000-000000000001'
param claudeOrganizationName = 'Offline validation only'
param claudeCountryCode = 'US'
param claudeIndustry = 'education'
param enableEvaluatorConnection = true
param evaluatorEndpointUrl = 'https://example.invalid/evaluate'
param evaluatorEndpointApiKey = readEnvironmentVariable('INFRA_TEST_KEY', 'offline-test-value-not-a-secret')
param additionalConnections = [
  {
    name: 'test-aad'
    category: 'Custom'
    target: 'https://example.invalid/aad'
    authType: 'AAD'
  }
  {
    name: 'test-none'
    category: 'Custom'
    target: 'https://example.invalid/public'
    authType: 'None'
  }
  {
    name: 'test-key'
    category: 'ApiKey'
    target: 'https://example.invalid/key'
    authType: 'ApiKey'
    credentialKey: 'external-service'
  }
]
param connectionCredentials = {
  'external-service': readEnvironmentVariable('INFRA_TEST_KEY', 'offline-test-value-not-a-secret')
}
