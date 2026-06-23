# SentinelPay Infra

Azure infrastructure for the [SentinelPay API](https://github.com/adityac14/sentinelpay-core), defined as code using Bicep and deployed through GitHub Actions across two environments. This project streamlines SentinelPay's deployment by provisioning every Azure resource through Infrastructure as Code, the kind of posture a compliance-driven Canadian fintech would actually require.

**Companion project to SentinelPay**, a payment risk assessment REST API inspired by Symcor's Payee Verify product and Canada's Real-Time Rail rollout. This repository provisions the cloud infrastructure SentinelPay runs on.

---

## The Problem

SentinelPay was originally deployed by hand. App Service was provisioned through the Azure Portal, the MongoDB Atlas connection string was pasted into App Service configuration, GitHub Actions deployed the application code, and that was it. It worked, but the deployment process itself lived only in the Portal and in memory.

A Canadian financial institution would not deploy a payment risk service this way. Specifically:

| What was missing | Why it matters in fintech |
|---|---|
| **No Infrastructure as Code** | The deployment existed only in the Portal. Rebuilding it required manually retracing clicks, and configuration drift accumulated silently. |
| **Secrets in App Service config** | Connection strings sat in plain configuration with no rotation story and no access audit trail. |
| **No dev environment** | Every change went to the same instance the world sees. Nowhere safe to test infrastructure changes. |
| **Scattered telemetry** | Logs landed in App Service, traces didn't exist, no central place to correlate "the app errored at 2am" with "Key Vault was accessed at 1:59am". |
| **Manual deployment** | No what-if previews, no approval gates, no automated rollback path. |

This project closes those gaps.

---

## The Solution

A Bicep repository that provisions SentinelPay's infrastructure as code, twice, once for `dev` and once for `prod`, from the same templates with different parameter files. Secrets move into Key Vault, App Service authenticates to it via system-assigned managed identity, and centralized monitoring captures both application telemetry and platform diagnostics. GitHub Actions runs the deployments with OIDC federated credentials, runs `what-if` previews against both environments on every pull request, and gates `prod` deployments behind a manual approval.

---

## Architecture

```
GitHub repo (Bicep + workflows)
       |
       v
GitHub Actions
  |-- PR: what-if against dev AND prod
  |-- Merge to main: deploy to dev
  +-- Manual approval: deploy to prod
       |
       v
+-------------------------------------------------------------+
|                    Azure subscription                       |
+-----------------------------+-------------------------------+
|   rg-sentinelpay-dev        |   rg-sentinelpay-prod         |
|   +------------------+      |   +------------------+        |
|   |  App Service B1  |      |   |  App Service B1  |        |
|   |  Managed identity|--+   |   |  Managed identity|--+     |
|   +------------------+  |   |   +------------------+  |     |
|   +------------------+  |   |   +------------------+  |     |
|   |   Key Vault      |<-+   |   |   Key Vault      |<-+     |
|   |   (Mongo URI)    |      |   |   (Mongo URI)    |        |
|   +------------------+      |   +------------------+        |
|   +------------------+      |   +------------------+        |
|   |  App Insights    |      |   |  App Insights    |        |
|   |  Log Analytics   |      |   |  Log Analytics   |        |
|   +------------------+      |   +------------------+        |
+-----------------------------+-------------------------------+
                              |
                              v
                      MongoDB Atlas
                      (external SaaS, shared cluster)
```

---

## Repository Structure

```
sentinelpay-infra/
+-- main.bicep                          # Root orchestrator (subscription scope)
+-- main.dev.bicepparam                 # Dev parameters (B1 SKU, dev naming)
+-- main.prod.bicepparam                # Prod parameters (B1 SKU, prod naming)
+-- modules/
|   +-- monitoring.bicep                # Log Analytics + App Insights + diagnostics
|   +-- keyvault.bicep                  # Key Vault with RBAC and audit diagnostics
|   +-- app.bicep                       # App Service + plan + managed identity + RBAC
+-- .github/
|   +-- workflows/
|       +-- infra.yml                   # OIDC auth, what-if on PR, deploy on merge
+-- docs/
|   +-- architecture.png                # Architecture diagram
+-- README.md
```

---

## Cloud Concepts Covered

| Concept | Where it lives in the project |
|---|---|
| **Infrastructure as Code** | Bicep modules with parameter files for dev/prod |
| **Compute** | App Service (Linux, Node.js 22) |
| **Secrets management** | Key Vault with RBAC, Key Vault references in App Service settings |
| **Identity & access** | System-assigned managed identity, Key Vault Secrets User role assignment |
| **Monitoring** | Log Analytics workspace + Application Insights + diagnostic settings on App Service and Key Vault |
| **CI/CD** | GitHub Actions with OIDC federated credentials, `what-if` on PR for both environments, approval gate before prod |
| **Multi-environment** | Same Bicep, different `.bicepparam` files, dynamic resource naming |

---

## Tech Stack

| Layer | Technology |
|---|---|
| **IaC language** | Bicep |
| **Cloud platform** | Microsoft Azure |
| **CI/CD** | GitHub Actions |
| **Auth to Azure** | OIDC federated credentials (no stored service principal secrets) |
| **Region** | Canada Central |
| **Application** | [SentinelPay API](https://github.com/adityac14/sentinelpay-core) (Node.js 22, TypeScript, Express) |
| **Database** | MongoDB Atlas (Azure-hosted, external to this Bicep, shared cluster with separate databases per environment) |

---

## Resource Naming

All resources follow Microsoft's recommended type-prefix abbreviations. Key Vault and App Service names include a deterministic unique suffix because they must be globally unique across Azure. The suffix length adjusts dynamically (5 characters for dev, 4 for prod) to keep both Key Vault names at exactly 24 characters.

| Resource | Dev | Prod |
|---|---|---|
| Resource group | `rg-sentinelpay-dev` | `rg-sentinelpay-prod` |
| App Service plan | `asp-sentinelpay-dev` | `asp-sentinelpay-prod` |
| App Service | `app-sentinelpay-dev-{suffix}` | `app-sentinelpay-prod-{suffix}` |
| Key Vault | `kv-sentinelpay-dev-{suffix}` | `kv-sentinelpay-prod-{suffix}` |
| Log Analytics | `log-sentinelpay-dev` | `log-sentinelpay-prod` |
| Application Insights | `appi-sentinelpay-dev` | `appi-sentinelpay-prod` |

---

## Deployment

### Prerequisites

* Azure subscription with Owner role
* Azure PowerShell module (`Az`) installed locally
* Bicep CLI installed locally
* A GitHub repository with Actions enabled
* An Entra ID app registration with OIDC federated credentials configured for both `dev` and `prod` environments
* GitHub repository secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
* GitHub environments: `dev` (auto-deploy) and `prod` (required reviewer)
* A MongoDB Atlas cluster with separate databases for dev and prod

### Local deployment

**PowerShell:**

```powershell
# Dev
New-AzSubscriptionDeployment `
  -Location canadacentral `
  -TemplateFile main.bicep `
  -TemplateParameterFile main.dev.bicepparam

# Prod
New-AzSubscriptionDeployment `
  -Location canadacentral `
  -TemplateFile main.bicep `
  -TemplateParameterFile main.prod.bicepparam
```

**What-if preview (dry run):**

```powershell
# Dev
New-AzSubscriptionDeployment `
  -Location canadacentral `
  -TemplateFile main.bicep `
  -TemplateParameterFile main.dev.bicepparam `
  -WhatIf

# Prod
New-AzSubscriptionDeployment `
  -Location canadacentral `
  -TemplateFile main.bicep `
  -TemplateParameterFile main.prod.bicepparam `
  -WhatIf
```

### Automated deployment (CI/CD)

* Open a pull request: GitHub Actions validates the Bicep and runs `what-if` against both dev and prod, posting the results as a PR comment
* Merge to `main`: automatic deploy to dev
* Approve the `prod` environment in the Actions UI: deploy to prod

### Post-deployment: seeding secrets

After the first deployment, the Key Vault exists but is empty. The MongoDB connection string must be seeded manually (secret values are never committed to source control):

```powershell
# Grant yourself write access to the vault (RBAC mode requires explicit assignment)
New-AzRoleAssignment `
  -ObjectId "<your-user-object-id>" `
  -RoleDefinitionName "Key Vault Secrets Officer" `
  -Scope "/subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.KeyVault/vaults/<vault-name>"

# Seed the MongoDB connection string (secret name must match the Key Vault reference in app.bicep)
Set-AzKeyVaultSecret `
  -VaultName "<vault-name>" `
  -Name "mongodb-uri" `
  -SecretValue (ConvertTo-SecureString "<connection-string>" -AsPlainText -Force)
```

---

## Design Decisions

A few things this project deliberately does *not* do, and why:

**No VNet or private endpoints.** Adding production-grade networking (private endpoints on Key Vault, VNet integration on App Service, private DNS zones) is a significant scope addition. MongoDB Atlas is an external SaaS that cannot be reached via Azure private endpoint anyway, so the security upside of partial networking is limited. This is the highest-priority item in *what I'd add next*.

**No automated secret rotation.** Rotating the MongoDB connection string requires coordination with MongoDB Atlas's API, which is external to Azure. Out of scope for the current iteration.

**No backup or disaster recovery configuration.** MongoDB Atlas provides its own backup, and App Service is stateless. There's nothing meaningful to back up at the Azure layer for this particular application.

**No custom alerting rules.** Log Analytics and App Insights are provisioned and collecting data, but specific KQL alert rules (failed Key Vault access spikes, latency thresholds, error rate jumps) are out of scope. Adding them is a natural follow-up.

These are not omissions, they are scoped-out items with clear next-step paths.

---

## What I'd Add Next

In rough priority order, ranked by what would move the project closest to a real fintech production posture:

1. **NAT Gateway for stable egress IP.** SentinelPay's MongoDB Atlas allowlist currently has to track App Service outbound IPs, which aren't guaranteed stable. A NAT Gateway with VNet integration gives the App Service a single fixed egress IP, allowlisted once.
2. **Private endpoint on Key Vault.** Take Key Vault off the public internet entirely. Requires a VNet, private DNS zone, and VNet integration on the App Service.
3. **KQL-based alert rules.** Failed authentication spikes on Key Vault, latency P95 thresholds on App Service, error rate jumps. Each rule fires an Action Group that emails the on-call.
4. **Separate Azure subscriptions for dev and prod.** Resource group isolation is fine for now, subscription isolation is the real production boundary.
5. **Bicep linter and security scanning in CI.** Adding `psrule-rules-azure` or `checkov` would catch misconfigurations before they hit Azure.
6. **Automated secret rotation.** A Function App on a timer trigger that rotates the MongoDB connection string via Atlas's API and writes the new value into Key Vault.

---

## Author

**Aditya Chattopadhyay**
* LinkedIn: [linkedin.com/in/aditya-chattopadhyay](https://www.linkedin.com/in/aditya-chattopadhyay/)
* Related project: [SentinelPay API](https://github.com/adityac14/sentinelpay-core)
