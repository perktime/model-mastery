using '../main.bicep'

param environmentName = 'infra-validation'
param developerPrincipalId = '00000000-0000-0000-0000-000000000001'
param claudeOrganizationName = 'Offline validation only'
param claudeCountryCode = 'US'
param claudeIndustry = 'education'
param existingSearchName = 'existing-search'
param searchResourceGroupName = 'existing-search-rg'
param assignSearchRoles = false
