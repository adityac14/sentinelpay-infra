// =============================================================================
// SentinelPay Infrastructure - Main Orchestrator
// =============================================================================
// Provisions the full SentinelPay Azure footprint for a single environment.
// Deployed at subscription scope so this template can create the resource
// group itself, ensuring the entire environment is reproducible from code.
//
// Deployed as:
//   New-AzSubscriptionDeployment `
//     -Location canadacentral `
//     -TemplateFile bicep/main.bicep `
//     -TemplateParameterFile bicep/main.dev.bicepparam
// =============================================================================

targetScope = 'subscription'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Deployment environment. Drives resouce naming and SKU selection.')
@allowed([
  'dev'
  'prod'
])
param environment string

@description('Azure region for all resources in this deployment.')
param location string = 'canadacentral'

@description('App service plan SKU. B1 is the smallest tier that supports managed indeitity & Key Vault references.')
@allowed([
  'B1'
  'B2'
  'S1'
  'S2'
  'P1v3'
])
param appServicePlanSku string = 'B1'

@description('Log Analytics workspace retention in days. 30 is the minimum billable tier.')
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 30

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

// Workload identifier, drives all resource names for consistency
var workload = 'sentinelpay'

// Resource group name follows Microsoft's recommended pattern: rg-{worload}-{env}
var resourceGroupName = 'rg-${workload}-${environment}'

// Tags applied to every resource in this deployment for cost tracking, ownership and lifecycle management
var commonTags = {
  workload: workload
  environment: environment
  managedBy: 'bicep'
  repository: 'sentinelpay-infra'
  costCenter: 'engineering'
}

// -----------------------------------------------------------------------------
// Resource Group
// -----------------------------------------------------------------------------

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

// -----------------------------------------------------------------------------
// Module: Monitoring
// Deployed first so other modules can stream diagnostics into the workspace.
// -----------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring-${environment}'
  scope: resourceGroup
  params: {
    workload: workload
    environment: environment
    location: location
    logRetentionInDays: logRetentionInDays
    tags: commonTags
  }
}

// -----------------------------------------------------------------------------
// Module: Key Vault
// Deployed before the App Service so the managed identity can be granted
// access during App Service creation.
// -----------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault-${environment}'
  scope: resourceGroup
  params: {
    workload: workload
    environment: environment
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkSpaceId
    tags: commonTags
  }
}

// -----------------------------------------------------------------------------
// Module: App Service
// Last in the chain because it depends on Key Vault for secret references
// and Application Insights for telemetry.
// -----------------------------------------------------------------------------
module app 'modules/app.bicep' = {
  name: 'deploy-app-${environment}'
  scope: resourceGroup
  params: {
    workload: workload
    environment: environment
    location: location
    appServicePlanSku: appServicePlanSku
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    logAnalyticsWorkSpaceId: monitoring.outputs.logAnalyticsWorkspaceId
    tags: commonTags
  }
}

// -----------------------------------------------------------------------------
// Outputs
// Surface useful values for downstream tooling, CI/CD logs, and operators.
// -----------------------------------------------------------------------------
@description('The name of the resouce group containing all SentinelPay resources')
output resouceGroupName string = resourceGroup.name

@description('The default hostname of the deployed App Service.')
output appServiceHostname string = app.outputs.appServiceHostname

@description('The name of the Key Vault for this environment.')
output keyVaultName string = keyVault.outputsKeyVaultName

@description('The name of the Application Insights instance for this environment.')
output applicationInsightsName string = monitoring.outputs.applicationInsightsName
