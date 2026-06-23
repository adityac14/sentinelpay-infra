// =============================================================================
// SentinelPay Infrastructure - Key Vault Module
// =============================================================================
// Provisions a Key Vault for a single environment with:
//
//   - RBAC-based access control  : Role assignments replace legacy access
//                                  policies, giving finer-grained control
//                                  and a consistent IAM model across Azure.
//
//   - Diagnostic settings        : Every read, write, and delete operation
//                                  against this vault is logged to the Log
//                                  Analytics workspace for audit purposes.
//                                  In a fintech context this is the access
//                                  audit trail for stored secrets.
//
// The vault itself holds no secrets at deploy time. The MongoDB Atlas
// connection string is seeded manually after the first successful deploy
// using the Azure Portal or PowerShell. This is intentional: secret values
// must never be committed to source control or passed as Bicep parameters.
// =============================================================================

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Workload identifier used to build resouce names.')
param workload string

@description('Deployment environment (dev or prod)')
@allowed([
  'dev'
  'prod'
])
param environment string

@description('Azure region for all resources in this module.')
param location string

@description('Resource ID of the Log Analytics workspace for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('Resource tags inherited from the root orchestrator.')
param tags object

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

// Key Vault names must be globally unique, 3-24 characters, alphanumeric and
// hyphens only. A deterministic 6-character suffix derived from the
// subscription ID and environment prevents naming collisions across tenants
// without producing a different name on every deploy.
var uniqueSuffix = substring(uniqueString(subscription().subscriptionId, environment), 0, 5)
var keyVaultName = 'kv-${workload}-${environment}-${uniqueSuffix}'
var keyVaultDiagnosticName = 'diag-kv-${workload}-${environment}'

// Built-in role definition ID for Key Vault Secrets User.
// This role grants read-only access to secret values, which is the minimum
// permission the App Service managed identity needs to retrieve secrets.
// Using the built-in role ID avoids a dependency on the role name, which can vary across sovereign clouds.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// -----------------------------------------------------------------------------
// Resources
// -----------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2026-03-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      // Standard tier supports all secret, key, and certificate operations
      // required for this project. Premium adds HSM-backed keys which are
      // out of scope here.
      name: 'standard'
    }
    tenantId: subscription().tenantId
    // RBAC mode replaces the legacy access policy model. It is the
    // Microsoft-recommended approach as it integrates with Entra ID role
    // assignments and supports Conditional Access policies.
    enableRbacAuthorization: true
    // Soft delete retains deleted secrets for 7 days (minimum), preventing
    // accidental permanent deletion. Required in most compliance frameworks.
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Purge protection prevents permanent deletion of the vault or its secrets
    // during the soft-delete retention period, even by administrators.
    // This is a hard requirement in PCI-DSS and SOC 2 environments.
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Grants the App Service managed identity read-only access to secrets in
// this vault. Scoped to the vault level rather than individual secrets for
// operational simplicity. In a production environment with many secrets,
// scoping to individual secrets provides a tighter blast radius.
// Note: The App Service managed identity principal ID is passed from the
// app module. This role assignment is declared here (in the Key Vault module)
// so the vault and its access policy are provisioned as a single logical unit.
// The App module outputs its principal ID which main.bicep passes back here
// via a second deployment pass. To keep module ordering simple, this role
// assignment is instead handled in the app module using the vault name output.

// Diagnostic settings capture every operation against this Key Vault:
// secret reads, writes, deletes, and authentication failures. This is the
// audit trail that a compliance team would review to answer "who accessed
// the MongoDB connection string and when."
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: keyVaultDiagnosticName
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        // AuditEvent captures all data-plane operations: secret get, set,
        // delete, and authentication events. This is the primary audit log.
        category: 'AuditEvent'
        enabled: true
      }
      {
        // AzurePolicyEvaluationDetails captures Azure Policy compliance
        // checks against this vault, useful for governance reporting.
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
      }
    ]
    metrics: [
      {
        // ServiceAPI metrics capture request counts, latency, and error rates
        // for all Key Vault API calls, enabling performance monitoring.
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Name of the Key Vault. Passed to the App Service module for Key Vault reference configuration.')
output keyVaultName string = keyVault.name

@description('Resource ID of the Key Vault.')
output keyVaultId string = keyVault.id

@description('URI of the Key Vault. Used to construct Key Vault reference URIs in App Service app settings.')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Built-in Key Vault Secrets User role definition ID for role assignments in the App module.')
output keyVaultSecretsUserRoleId string = keyVaultSecretsUserRoleId
