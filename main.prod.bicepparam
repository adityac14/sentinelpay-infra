// =============================================================================
// SentinelPay Infrastructure - Prod Environment Parameters
// =============================================================================
// Parameter values for the prod environment deployment. Consumed by main.bicep
// via:
//
//   New-AzSubscriptionDeployment `
//     -Location canadacentral `
//     -TemplateFile main.bicep `
//     -TemplateParameterFile main.prod.bicepparam
//
// Prod uses the same SKUs as dev for now to keep running costs minimal.
// In a real fintech deployment, prod would use:
//   - S1 or higher App Service Plan (autoscaling, deployment slots, backups)
//   - Longer log retention (90+ days, often 365 for compliance)
//   - A separate Azure subscription, not just a separate resource group
// =============================================================================

using 'main.bicep'

param environment        = 'prod'
param location           = 'canadacentral'
param appServicePlanSku  = 'B1'
param logRetentionInDays = 30
