// =============================================================================
// SentinelPay Infrastructure - Dev Environment Parameters
// =============================================================================
// Parameter values for the dev environment deployment. Consumed by main.bicep
// via:
//
//   New-AzSubscriptionDeployment `
//     -Location canadacentral `
//     -TemplateFile main.bicep `
//     -TemplateParameterFile main.dev.bicepparam
//
// Dev intentionally uses the smallest SKUs and shortest retention to minimize
// cost. Promotion to production-grade settings happens via main.prod.bicepparam.
// =============================================================================

using 'main.bicep'

param environment        = 'dev'
param location           = 'canadacentral'
param appServicePlanSku  = 'B1'
param logRetentionInDays = 30
