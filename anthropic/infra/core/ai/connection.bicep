@export()
type ConnectionConfiguration = {
  @minLength(1)
  name: string
  @minLength(1)
  category: string
  @minLength(1)
  target: string
  authType: 'AAD' | 'None' | 'ApiKey'
  credentialKey: string?
  metadata: object?
  isSharedToAll: bool?
}

param accountName string
param projectName string
param configuration ConnectionConfiguration
@secure()
@minLength(1)
param apiKey string?

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' existing = {
  parent: account
  name: projectName
}

resource connection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01' = {
  parent: project
  name: configuration.name
  properties: union(
    {
      category: configuration.category
      target: configuration.target
      metadata: configuration.?metadata ?? {}
      isSharedToAll: configuration.?isSharedToAll ?? false
    },
    configuration.authType == 'ApiKey'
      ? {
          authType: 'ApiKey'
          credentials: {
            key: apiKey
          }
        }
      : {
          authType: configuration.authType
        }
  )
}

output id string = connection.id
output name string = connection.name
