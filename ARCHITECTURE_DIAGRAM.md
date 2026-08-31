# Azure Cost Visibility Dashboard Terraform Lab — Architecture Documentation

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Resource Topology](#2-resource-topology)
3. [Component Descriptions](#3-component-descriptions)
4. [Budget & Alert Threshold Design](#4-budget--alert-threshold-design)
5. [Action Group & Notification Routing](#5-action-group--notification-routing)
6. [Logic App Workflow Design](#6-logic-app-workflow-design)
7. [Deployment Flow](#7-deployment-flow)
8. [Project Folder Tree](#8-project-folder-tree)
9. [Portal Configuration Steps](#9-portal-configuration-steps)
10. [Technology Stack Summary](#10-technology-stack-summary)

---

## 1. High-Level Overview

This lab provisions a **cost-monitoring and alerting pipeline** entirely through **Terraform on Azure**, using **Azure Monitor**, **Cost Management**, **Logic Apps**, and **Azure Workbooks** to turn raw subscription spend into a plain-language email alert and a live dashboard.

[![explanation](PASTE_THUMBNAIL_IMAGE_URL_HERE)](PASTE_LOOM_LINK_HERE)

**Design Goals:**
- Infrastructure-as-code for everything that's reproducible — the alert pipeline's plumbing
- Portal-driven configuration only where it's genuinely required — the Logic App's interactive email connector
- No credentials stored anywhere — this lab has nothing that qualifies as a secret
- Repeatable, destroyable, and re-deployable with `terraform apply`

---

## 2. Resource Topology

This lab has no virtual network, no compute, and no data plane to secure — it operates entirely at the subscription/monitoring layer. There is no equivalent to a VNet/subnet/NSG design here; the "network" is the notification path.

### Subscription-Scoped Resources

| Resource                  | Scope                          | Notes                                        |
|----------------------------|---------------------------------|-----------------------------------------------|
| Consumption Budget         | Subscription                   | Not resource-group-scoped — watches total subscription spend |
| Diagnostic Setting         | Subscription (activity log)    | `target_resource_id` is the subscription itself |
| Log Analytics Workspace    | Resource Group                 | `rg-cost-dashboard-[yourname]`                |
| Action Group               | Resource Group                 | `rg-cost-dashboard-[yourname]`                |
| Logic App Workflow         | Resource Group                 | `rg-cost-dashboard-[yourname]`                |

> **Note:** the budget watching the *whole subscription* rather than just this resource group is intentional — a resource-group-scoped budget would miss spend from every other project running in the same subscription, defeating the point of a cost-visibility tool.

### Notification Path (the "network" of this lab)

```text
Budget (subscription-scoped)
   │  crosses 25% / 50% / 100% of $200
   ▼
Action Group  (ag-cost-alerts-[yourname])
   │
   ├──► Email Receiver ─────────────► owner's inbox directly
   │
   └──► Logic App Receiver ────────► HTTP trigger
                                        │
                                        ▼
                                 Send an email (V2)
                                        │
                                        ▼
                                 formatted alert email
```

---

## 3. Component Descriptions

### Log Analytics Workspace — `law-cost-[yourname]`

Stores subscription activity log data forwarded by the diagnostic setting. No VMs, no agents, no data collection rules — this is log ingestion only, at the cheapest applicable tier.

| Setting             | Value          | Why                                                        |
|----------------------|----------------|-------------------------------------------------------------|
| SKU                  | `PerGB2018`    | Pay only for data ingested — no flat monthly fee            |
| Retention             | 30 days        | Minimum allowed value — keeps lab-scale cost negligible      |

---

### Consumption Budget — `budget-cost-[yourname]`

The subscription-level watcher. Doesn't do anything by itself — it exists purely to evaluate spend against thresholds and hand off to the Action Group when one is crossed.

| Setting        | Value       | Why                                                  |
|-----------------|-------------|-------------------------------------------------------|
| Amount          | $200        | The ceiling — thresholds below are percentages of this |
| Time Grain      | Monthly     | Matches Azure's own billing cycle                      |
| Start Date      | 1st of month, RFC3339 | Required format — anything else fails at the API level |

---

### Action Group — `ag-cost-alerts-[yourname]`

The single point of control for "who/what gets notified." One Action Group, attached to all three budget notifications, with two receivers:

| Receiver Type   | Target                          | Added By       |
|------------------|----------------------------------|-----------------|
| Email            | `var.alert_email`                | Terraform       |
| Logic App        | `la-cost-alert-[yourname]`       | Azure CLI, post-deploy |

---

### Logic App — `la-cost-alert-[yourname]`

Terraform provisions the container only. The trigger and action are added in the visual designer, because the Office 365 Outlook connector requires an interactive sign-in that Terraform has no mechanism to perform.

```text
[HTTP trigger: When a HTTP request is received]
                │
                ▼
[Action: Send an email (V2) — Office 365 Outlook]
    To:      var.alert_email
    Subject: "Azure Cost Alert — Budget Threshold Reached"
    Body:    dynamic content → Body field from the HTTP trigger
```

---

### Azure Workbook — "Cost Visibility Dashboard"

Not a Terraform resource at all — built entirely in the portal, backed by two data sources:

| Query Type            | Source                  | Purpose                                  |
|------------------------|--------------------------|--------------------------------------------|
| Resource Graph query   | `resourcecontainers`     | Lists resource groups and locations         |
| Metric tile            | Cost Management          | Shows spend broken out by service/RG/week   |

---

## 4. Budget & Alert Threshold Design

```text
$200 monthly budget
│
├── 25%  ($50)   ─► notification ─► Action Group   "early warning"
├── 50%  ($100)  ─► notification ─► Action Group   "getting real"
└── 100% ($200)  ─► notification ─► Action Group   "hard stop"
```

| Threshold | Operator     | Threshold Type | Rationale                                             |
|-----------|--------------|------------------|--------------------------------------------------------|
| 25%       | GreaterThan  | Actual           | First signal — plenty of runway left to react          |
| 50%       | GreaterThan  | Actual           | Mid-month checkpoint — spend is accelerating           |
| 100%      | GreaterThan  | Actual           | Budget fully consumed — immediate attention needed      |

All three notifications route to the same Action Group — thresholds differ in *when* they fire, not *who* they notify.

---

## 5. Action Group & Notification Routing

```text
azurerm_monitor_action_group.email_alerts
│
├── email_receiver
│     name: "owner-email"
│     use_common_alert_schema: true
│
└── (added post-deploy via Azure CLI)
      logicapp receiver
      name: "la-webhook"
      callback_url: <logic_app_callback_url output>
```

**Why one Action Group instead of one per threshold?** Notification targets rarely change per-threshold — the owner wants the same email/Logic App regardless of whether it's the 25% or 100% alert. Centralizing in one Action Group means updating the notification path once instead of three times.

---

## 6. Logic App Workflow Design

```text
Trigger: When a HTTP request is received
   │
   │  (Action Group calls this URL when it fires)
   ▼
Action: Send an email (V2)
   │
   ├── To: alert_email
   ├── Subject: "Azure Cost Alert — Budget Threshold Reached"
   └── Body: {dynamic content: trigger Body}
   │
   ▼
Email delivered to inbox
```

**Why Terraform doesn't define the workflow definition itself:** `azurerm_logic_app_workflow` can technically accept a `workflow_schema`/`parameters` payload authored in raw Workflow Definition Language, but doing so trades a five-minute visual-designer task for a much harder-to-maintain JSON blob — and still can't complete the Office 365 connector's OAuth handshake non-interactively. Provisioning the container in Terraform and finishing the logic in the designer is the pragmatic split.

---

## 7. Deployment Flow

```text
terraform init
      │
      ▼
terraform plan
      │  Reads current subscription/tenant via azurerm_client_config
      │  Validates all resources / shows plan (6 resources)
      ▼
terraform apply
      │
      │ Phase 1 — Foundation
      ├──► Resource Group
      └──► Log Analytics Workspace
      │
      │ Phase 2 — Alerting Plumbing
      ├──► Action Group (email receiver only, for now)
      ├──► Consumption Budget (3 notifications → Action Group)
      └──► Logic App Workflow (empty container)
      │
      │ Phase 3 — Observability
      └──► Diagnostic Setting (subscription activity log → Log Analytics)
      │
      ▼
[Terraform apply complete — 6 resources deployed]
      │
      │ Manual, portal-only (not Terraform)
      ├──► Build Logic App trigger + email action in designer
      ├──► az monitor action-group update --add-action logicapp ...
      └──► Build Azure Workbook (Resource Graph + Cost Management)
```

### Dependency Graph (Simplified)

```text
resource_group
    ├─► log_analytics_workspace ──► diagnostic_setting
    ├─► action_group ──► consumption_budget (references action_group.id)
    └─► logic_app_workflow ──► (wired to action_group post-deploy, outside Terraform)
```

---

## 8. Project Folder Tree

```text
azure-cost-dashboard-lab/
│
├── main.tf                     # Resource group, Log Analytics, budget, action group, logic app, diagnostics
├── variables.tf                # Input variable declarations
├── outputs.tf                  # Output values (workspace ID, callback URL, IDs)
├── terraform.tfvars            # Variable values (non-secret)
├── terraform.tfvars.example    # Template for the above
├── providers.tf                # AzureRM provider config
├── versions.tf                 # Required provider version constraints
│
├── docs/
│   ├── PROJECT_OVERVIEW.md
│   ├── ARCHITECTURE_DIAGRAM.md   ◄── (this file)
│   ├── DEPLOYMENT_GUIDE.md
│   └── TROUBLESHOOTING.md
│
└── .gitignore                  # Excludes *.tfstate, *.tfvars, .terraform/
```

> Unlike the file server lab, there are no `modules/` or `scripts/` directories — this lab has no child modules and no PowerShell automation. Everything Terraform touches lives in a flat root module; everything else is a portal step.

---

## 9. Portal Configuration Steps

There is no PowerShell automation in this lab — the two steps that Terraform can't complete are done by hand in the Azure portal.

**Logic App Designer** — completes the alert-to-email translation

Responsibilities:
- Add an HTTP trigger ("When a HTTP request is received")
- Add an action: Office 365 Outlook → "Send an email (V2)"
- Sign in interactively to authorize the Outlook connector
- Save, then copy the HTTP POST URL for use in the Action Group CLI command

```powershell
az monitor action-group update `
  --name ag-cost-alerts-yourname `
  --resource-group rg-cost-dashboard-yourname `
  --add-action logicapp la-webhook la-cost-alert-yourname `
  /subscriptions/<sub-id>/resourceGroups/rg-cost-dashboard-yourname/providers/Microsoft.Logic/workflows/la-cost-alert-yourname `
  <logic-app-callback-url>
```

**Azure Workbooks** — completes the dashboard

Responsibilities:
- Add a Resource Graph query listing resource groups
- Add a Cost Management metric tile scoped to the subscription
- Save the workbook against the lab's resource group

---

## 10. Technology Stack Summary

| Layer                | Technology                                      |
|-----------------------|--------------------------------------------------|
| Cloud Platform        | Microsoft Azure                                  |
| IaC Tool              | Terraform (AzureRM provider ~3.x)                |
| Cost Governance        | Azure Cost Management (Consumption Budget)       |
| Alerting               | Azure Monitor (Action Group)                     |
| Automation / Messaging | Azure Logic Apps (Office 365 Outlook connector)  |
| Observability           | Log Analytics Workspace                          |
| Dashboarding            | Azure Workbooks (Resource Graph + Cost Management)|
| Version Control         | Git (`.gitignore` excludes state/tfvars)         |
