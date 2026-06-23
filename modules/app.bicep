// =============================================================================
// SentinelPay Infrastructure - App Service Module
// =============================================================================
// Provisions the compute layer for SentinelPay:
//
//   - App Service Plan          : The compute fabric (VM hosts) that runs
//                                 the App Service. SKU determines pricing,
//                                 scaling capability, and available features.
//
//   - App Service               : The Linux Node.js host running SentinelPay.
//                                 Has a system-assigned managed identity so
//                                 it can authenticate to Azure resources
//                                 without storing any credentials.
//
//   - Role Assignment           : Grants the App Service managed identity
//                                 the Key Vault Secrets User role on the
//                                 environment's Key Vault, enabling Key Vault
//                                 references in app settings.
//
//   - Diagnostic Settings       : Streams App Service platform logs, console
//                                 output, and HTTP access logs to the Log
//                                 Analytics workspace for centralized querying.
//
// Deployed last in the module chain because it depends on outputs from both
// the monitoring and Key Vault modules.
// =============================================================================

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Workload identifier used to build resource names.')
param workload string

@description('Deployment environment (dev or prod)')
@allowed([
  'dev'
  'prod'
])
param environment string

@description('Azure region for all resoruces in this module.')
param location string

@description('App Service Plan Sku. B1 is the smallest tier that supports managed identity and Key Vault references.')
@allowed([
  'B1'
  'B2'
  'S1'
  'S2'
  'P1v3'
])
param appServicePlanSku string

@description('Name of the Key Vault for this environment. Used to scope the role assignment and build Key Vault reference URIs.')
param keyVaultName string

@description('Application Insights connection string. Injected into App Service app settings so SentinelPay can send telemtry.')
@secure()
param applicationInsightsConnectionString string

@description('Resource ID of the Log Analytics workspace for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Resource tags inherited from the root orchestrator')
param tags object

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

// App Service names form a subdomain of azurewebsites.net so they must be
// globally unique. A deterministic 6-character suffix derived from the
// subscription ID and environment prevents collisions across tenants.
var suffixLength = environment == 'prod' ? 4 : 5
var uniqueSuffix = substring(uniqueString(subscription().subscriptionId, environment), 0, suffixLength)
var appServicePlanName = 'asp-${workload}-${environment}'
var appServiceName = 'app-${workload}-${environment}-${uniqueSuffix}'
var appServiceDiagnosticName = 'diag-app-${workload}-${environment}'

// Built-in role definition ID for Key Vault Secrets User. This role grants
// read-only access to secret values, the minimum permission required for
// the App Service to retrieve the MongoDB connection string via Key Vault
// references at runtime.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Node.js runtime version. Matches SentinelPay's package.json engine spec.
var nodeVersion = '22-lts'

// -----------------------------------------------------------------------------
// Existing Resources
// -----------------------------------------------------------------------------

// Reference the Key Vault provisioned by the keyvault module. Used as the
// scope for the role assignment below and to construct Key Vault reference
// URIs in app settings.
resource keyVault 'Microsoft.KeyVault/vaults@2026-03-01-preview' existing = {
  name: keyVaultName
}

// -----------------------------------------------------------------------------
// Resources
// -----------------------------------------------------------------------------

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    // Reserved must be true for Linux plans. This is an Azure quirk: the 
    // 'reserved' flag is what distinguishes a Linux plan from a Windows one.
    reserved: true
  }
}

resource appService 'Microsoft.Web/sites@2025-03-01' = {
  name: appServiceName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    // System-assigned managed identity has a lifecycle tied to this App
    // Service. When the App Service is deleted, the identity is cleaned up
    // automatically, no manual lifecycle management required.
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|${nodeVersion}'
      // Enforce TLS 1.2 as the minimum. TLS 1.0 and 1.1 are deprecated and
      // would fail any modern compliance audit (PCI-DSS, SOC 2).
      minTlsVersion: '1.2'
      // Disable FTPS deployment to enforce GitHub Actions as the only path
      // to deploy code. Removes a credential surface and audit gap.
      ftpsState: 'Disabled'
      http20Enabled: true
      // Always-On keeps the app warm. Not supported on B1 plans, so we
      // conditionally enable it only on higher tiers.
      alwaysOn: appServicePlanSku != 'B1' ? true : false
      appSettings: [
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~22'
        }
        {
          // Application Insights connection string. The Node.js SDK reads
          // this on startup and begins exporting telemetry automatically.
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          // Enables the App Insights extension for Node.js apps.
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          // Key Vault reference for the MongoDB Atlas connection string.
          // At runtime, App Service resolves this by authenticating to Key
          // Vault via the managed identity. The secret value never appears
          // in app settings, environment variables, or deployment logs.
          name: 'MONGODB_URI'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=mongodb-uri)'
        }
        {
          name: 'DB_NAME'
          value: environment == 'prod' ? 'sentinelpay' : 'sentinelpay_dev'
        }
        {
          // App Service sets this automatically; declaring it makes the
          // contract between platform and application explicit.
          name: 'PORT'
          value: '8080'
        }
      ]
    }
  }
}

// Role assignment granting the App Service managed identity read access to
// secrets in the Key Vault. The role assignment name is a deterministic GUID
// derived from the scope, principal, and role. This prevents duplicate role
// assignments on redeploy and provides a stable identifier.
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appService.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: appService.identity.principalId
    // ServicePrincipal is the correct principal type for managed identities,
    // both system-assigned and user-assigned. Setting this explicitly avoids
    // a race condition where Azure RBAC has not yet replicated the identity.
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings stream App Service platform logs, console output, and
// HTTP access logs into the Log Analytics workspace for unified querying
// alongside Key Vault audit logs and Application Insights telemetry.
resource appServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: appServiceDiagnosticName
  scope: appService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        // HTTP request logs: method, path, status code, latency.
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        // stdout from the Node.js process. SentinelPay's console.log
        // output lands here, essential for production debugging.
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        // stderr from the Node.js process: unhandled exceptions, process
        // crashes, and startup errors.
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        // Audit events such as configuration changes and deployment activity.
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        // Platform events: restarts, scaling, slot swaps. The primary
        // source for diagnosing availability issues.
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Default hostname of the App Service. Browse to https://{hostname} to reach SentinelPay.')
output appServiceHostname string = appService.properties.defaultHostName

@description('Name of the App Service.')
output appServiceName string = appService.name

@description('Resource ID of the App Service.')
output appServiceId string = appService.id

@description('Principal ID of the App Service managed identity. Useful for additional role assignments in future modules.')
output appServicePrincipalId string = appService.identity.principalId
