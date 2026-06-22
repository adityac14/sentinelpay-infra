// =============================================================================
// SentinelPay Infrastructure - Monitoring Module
// =============================================================================
// Provisions the full observability stack for a single environment:
//
//   - Log Analytics Workspace  : Central Azure Monitor data store. All logs
//                                and metrics from every resource in this
//                                environment flow here for unified querying.
//
//   - Application Insights     : Application-level telemetry for SentinelPay.
//                                Captures HTTP requests, response times,
//                                exceptions, and dependency calls to MongoDB.
//
// Deployed first in the module chain because both Key Vault and App Service
// stream their diagnostic logs into the workspace provisioned here.
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

@description('Azure region for all resources in this module')
param location string

@description('Number of days to retain logs in the Log Analytics workspace. min: 30, max 730.')
@minValue(30)
@maxValue(730)
param logRetentionInDays int

@description('Resource tags inherited from the root orchestrator.')
param tags object

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

// Resource names follow the pattern: {type-prefix}-{workload}-{env}
// Log Analytics prefix 'log' and App Insights prefix 'appi' are Microsoft recommended abbreviations from the Azure naming convention guide.
var logAnalyticsWorkspaceName = 'log-${workload}-${environment}'
var applicationInsightsName = 'appi-${workload}-${environment}'

// -----------------------------------------------------------------------------
// Resources
// -----------------------------------------------------------------------------

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      // PerGB2018 is the modern pay-as-you-go tier. The first 5GB of data
      // ingested per month is free, making it cost-effective for this project.
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
    features: {
      // Disabling local authentication enforces Entra ID (managed identity)
      // as the only way to query the workspace, a security best practice.
      disableLocalAuth: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  // 'web' is the correct kind for a Node.js HTTP API regardless of whether
  // it runs in a browser. This drives the correct experience in the Portal.
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    // Disabling local authentication means the App Service must use its 
    // managed identity to write telemetry, no instrumentation keys needed.
    DisableLocalAuth: false
    RetentionInDays: logRetentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Diagnostic settings route Log Analytics workspace's own activity logs
// back into itself for a complete audit trail of who quried what and when.
resource logAnalyticsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${logAnalyticsWorkspaceName}'
  scope: logAnalyticsWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        // Captures all queries run against this workspace, useful for
        // auditing who is querying logs and how frequently.
        category: 'Audit'
        enabled: true
      }
      {
        // Captures summary metrics about workspace health and data ingestion
        category: 'SummaryLogs'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
// These values are consumed by the Key Vault and App Service modules. 
// Passing them as outputs (rather than reconstructing them) ensures
// all modules reference the same resources without hardcoding IDs

@description('Resource ID of the Log Analytics workspace. Passed to Key Vault & App Service diagnostic settings.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Name of the Log Analytics workspace.')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Connection string for Application INsights. Injected into App Service app settings.')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Name of the Application Insights instance.')
output applicationInsightsName string = applicationInsights.name

@description('Resource ID of the Application Insights instance.')
output applicationInsightsId string = applicationInsights.id
