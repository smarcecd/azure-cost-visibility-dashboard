# Azure Cost Visibility Dashboard Terraform Lab

Why this matters?
[![CostDashboardLab](PASTE_THUMBNAIL_IMAGE_URL_HERE)](PASTE_LOOM_LINK_HERE)

---

## Table of Contents

1. [Project Summary](#1-project-summary)
2. [Learning Objectives](#2-learning-objectives)
3. [Prerequisites](#3-prerequisites)
4. [Lab Environment at a Glance](#4-lab-environment-at-a-glance)
5. [Repository Structure](#5-repository-structure)
6. [Quick Start](#6-quick-start)
7. [Configuration Reference](#7-configuration-reference)
8. [Key Design Decisions](#8-key-design-decisions)
9. [What Gets Built](#9-what-gets-built)
10. [Validation Checklist](#10-validation-checklist)

---

## 1. Project Summary

This project is a **fully automated, Infrastructure-as-Code lab** that provisions a Azure cost-monitoring pipeline using **Terraform**. It simulates how a real business tracks cloud spend: a budget watches usage against defined thresholds, an alert fires and is translated into a plain-language email, and a live dashboard shows where the money is going — all wired together with a single `terraform apply` plus two short, one-time portal steps.

| Attribute          | Value                                                       |
|--------------------|-------------------------------------------------------------|
| **Purpose**        | Learn Terraform, Azure Cost Management, Monitor alerting, and Logic Apps end-to-end |
| **Cloud**          | Microsoft Azure                                             |
| **IaC Tool**       | Terraform (AzureRM provider ~3.x)                           |
| **Alerting Path**  | Budget → Action Group → Logic App → Email                  |
| **Dashboard**      | Azure Workbooks (Resource Graph + Cost Management)          |
| **Automation**     | Terraform for infra; portal designer for Logic App workflow |
| **Secrets**        | None required — no credentials stored in this lab           |
| **Estimated Cost** | Near-$0 — this project monitors spend, it doesn't generate meaningful spend of its own |

> **This is a lab environment.** It is not hardened for production use.
> Always run `terraform destroy` when you are done to avoid unnecessary Azure charges.

---

## 2. Learning Objectives

By completing this lab you will be able to:

### Terraform on Azure
- Write a Terraform configuration that provisions a monitoring/alerting pipeline rather than compute
- Use `data "azurerm_client_config"` to read your active subscription and tenant context
- Understand where Terraform's responsibility intentionally ends (infra) and the portal's begins (interactive, connector-based configuration)
- Manage implicit resource dependencies between an Action Group, a Budget, and a Logic App

### Azure Cost Management
- Configure a subscription-level budget with `azurerm_consumption_budget_subscription`
- Define multiple notification thresholds (`GreaterThan`, percentage-based) against a single budget
- Understand the difference between `Actual` and `Forecasted` threshold types

### Azure Monitor & Alerting
- Build a reusable Action Group as the single point of control for notification routing
- Understand the Action Group → webhook → Logic App pattern for turning a raw alert into a formatted message
- Forward subscription activity logs into Log Analytics for historical querying

### Logic Apps & Workbooks
- Provision a Logic App container in Terraform, then complete the trigger/action logic in the visual designer
- Wire an HTTP-triggered Logic App as an Action Group receiver via the Azure CLI
- Build an Azure Workbook backed by Azure Resource Graph and Cost Management queries

---

## 3. Prerequisites

### Azure Requirements

| Requirement                       | Notes                                        |
|-----------------------------------|----------------------------------------------|
| Azure Subscription                | Free tier or Pay-As-You-Go                   |
| Contributor role (or Owner)       | Required for Terraform to authenticate       |
| Cost Management Contributor role  | Required specifically for budget writes — a Contributor/Owner role does not automatically include it |
| Office 365 / Outlook account      | Used for the Logic App's email connector — sign-in happens interactively in the portal |

### Local Workstation Requirements

| Tool              | Minimum Version | Install                                                    |
|-------------------|-----------------|------------------------------------------------------------|
| Terraform CLI     | 1.3.x+          | https://developer.hashicorp.com/terraform/install          |
| Azure CLI         | 2.50+           | `winget install Microsoft.AzureCLI` / `brew install azure-cli` |
| Git               | Any             | https://git-scm.com                                        |
| VS Code (optional)| Any             | Recommended with the HashiCorp Terraform extension         |

### Authentication Setup

```bash
# 1. Login with Azure CLI
az login

# 2. Set your target subscription
az account set --subscription "<SUBSCRIPTION_ID>"
```

---

## 4. Lab Environment at a Glance

```
rg-cost-dashboard-[yourname]
 │
 ├─ Log Analytics Workspace      captures subscription activity logs
 ├─ Cost Management Budget        watches actual spend at $50 / $100 / $200
 ├─ Action Group                  routes notifications to email + Logic App
 ├─ Logic App                     formats a raw alert into a readable email
 └─ Azure Workbook                dashboard — spend by service, RG, and week
```

Shared services: none — this lab has no Key Vault or compute, by design.

### Resource Summary

| **Resource**              | **Terraform Type**                          | **Purpose**                                  |
|----------------------------|----------------------------------------------|-----------------------------------------------|
| Resource Group             | `azurerm_resource_group`                     | Container for the whole lab                   |
| Log Analytics Workspace    | `azurerm_log_analytics_workspace`            | Stores subscription activity/diagnostic data  |
| Action Group                | `azurerm_monitor_action_group`               | Defines notification targets (email + Logic App) |
| Consumption Budget         | `azurerm_consumption_budget_subscription`    | Watches spend, fires at 3 thresholds          |
| Logic App Workflow          | `azurerm_logic_app_workflow`                 | Container for the alert → email automation    |
| Diagnostic Setting          | `azurerm_monitor_diagnostic_setting`         | Forwards subscription activity log → Log Analytics |

### Budget Thresholds

| **Threshold** | **% of $200** | **Operator**   | **Routed To**       |
|---------------|----------------|-----------------|----------------------|
| $50           | 25%            | GreaterThan     | Action Group          |
| $100          | 50%            | GreaterThan     | Action Group          |
| $200          | 100%           | GreaterThan     | Action Group          |

---

## 5. Repository Structure

```text
azure-cost-dashboard-lab/
│
├── main.tf                     # Resource group, Log Analytics, budget, action group, logic app, diagnostics
├── variables.tf                # All input variable declarations
├── outputs.tf                  # Terraform outputs (workspace ID, callback URL, IDs)
├── terraform.tfvars            # Non-secret variable values
├── terraform.tfvars.example    # Template for the above
├── providers.tf                # AzureRM provider + features block
├── versions.tf                 # required_providers version pins
│
└── docs/
    ├── PROJECT_OVERVIEW.md     ◄── (this file)
    ├── ARCHITECTURE_DIAGRAM.md
    ├── DEPLOYMENT_GUIDE.md
    └── TROUBLESHOOTING.md
```

---

## 6. Quick Start

```powershell

# 1. Clone the repository
git clone https://github.com/smarcecd/azure-cost-dashboard-lab.git
cd azure-cost-dashboard-lab

# 2. Initialize Terraform (downloads providers)
terraform init

# 3. Review what will be created
terraform plan -var-file="terraform.tfvars"

# 4. Deploy the alerting pipeline (~2-3 minutes)
terraform apply -var-file="terraform.tfvars"

# 5. Grab the values you'll need for the portal steps
terraform output

# 6. Finish the Logic App trigger/action and the Workbook in the portal
#    (see Deployment Guide — these two steps can't be automated by Terraform)

```

Tip: The Terraform portion of this lab takes 2–3 minutes. The remaining time is entirely
portal work — wiring the Logic App designer and building the Workbook — both deliberately
left as click-through steps rather than Terraform resources.

---

## 7. Configuration Reference
terraform.tfvars (non-secret values)

```hcl

yourname     = "yourname"
location     = "East US"
alert_email  = "your.email@example.com"

```

### Secrets Required

None. Unlike infrastructure labs that store admin credentials in Key Vault, this lab has
no VM passwords or domain credentials to protect — the only sensitive-adjacent value is
`alert_email`, and it isn't a secret so much as a destination.

### Terraform Outputs

| **Output Name**              | **Description**                                           |
|-------------------------------|-------------------------------------------------------------|
| resource_group_name           | Name of the deployed resource group                         |
| log_analytics_workspace_id    | ID of the Log Analytics workspace                           |
| logic_app_callback_url        | HTTP endpoint to use when wiring the Logic App as an Action Group receiver |
| action_group_id               | ID of the Action Group, used when attaching the Logic App receiver |

---

## 8. Key Design Decisions

- **Why a budget resource instead of just a dashboard?**
A dashboard you have to remember to check is a dashboard nobody checks. The Cost Management
budget is what turns this from a "pull" pattern (someone opens the portal) into a "push"
pattern (an alert lands in an inbox), which is the actual point of the lab.

- **Why three thresholds instead of one?**
25/50/100% gives an early warning, a "this is getting real" nudge, and a hard stop — one
alert that only fires at 100% arrives too late to change anything about that month's spend.

- **Why a Logic App instead of the default Azure Monitor alert email?**
Azure Monitor's built-in alert emails are formatted for engineers — full of JSON payloads and
resource IDs. A business owner needs a sentence, not a payload. The Logic App is the
translation layer between "an alert fired" and "here's what that means."

- **Why does Terraform stop at the Logic App container?**
The trigger and action steps are built in the visual designer on purpose. That's an
intentional line between what belongs in code (reproducible infrastructure) and what's
genuinely easier — and in the case of the Office 365 connector's interactive sign-in,
required — to configure by hand.

- **Why forward activity logs to Log Analytics if the alert path doesn't need it?**
The budget/alert pipeline works without it, but without a Log Analytics destination there's
no history to query later when someone asks "what changed last month?" It's the difference
between reactive alerting and being able to look backward.

---

## 9. What Gets Built

A single `terraform apply` provisions the following:

- Azure Infrastructure (6 resources)
- 1× Resource Group
- 1× Log Analytics Workspace (30-day retention, `PerGB2018` SKU)
- 1× Action Group (email receiver, later extended with a Logic App receiver)
- 1× Consumption Budget (subscription-scoped, $200/month, 3 notification thresholds)
- 1× Logic App Workflow (container only — trigger/action added in the portal)
- 1× Diagnostic Setting (subscription activity log → Log Analytics)

Completed afterward in the portal (not Terraform):
- HTTP trigger + "Send an email (V2)" action added to the Logic App
- Logic App attached as a receiver on the Action Group via Azure CLI
- Azure Workbook built from a Resource Graph query and a Cost Management metric tile

---

## 10. Validation Checklist
After `terraform apply` and the portal steps complete, run through these checks:

**In the Portal**

[ ] Resource group `rg-cost-dashboard-[yourname]` exists with all 6 Terraform-managed resources

[ ] Cost Management → Budgets shows `budget-cost-[yourname]` with 3 notification thresholds

[ ] Monitor → Action groups shows `ag-cost-alerts-[yourname]` with both an email and a Logic App receiver

[ ] Monitor → the Logic App shows status **Enabled**, with an HTTP trigger and a Send-email action configured

[ ] Monitor → Workbooks shows `Cost Visibility Dashboard`, rendering spend by resource group

**Alert Path**

[ ] Manually trigger a test notification from the Action Group

[ ] ✔ Test email arrives formatted by the Logic App, not as a raw JSON alert payload

[ ] ✔ Log Analytics workspace shows activity log entries under **Logs**

**Teardown (when finished)**

[ ] `terraform destroy` removes the resource group, budget, Logic App, and Log Analytics workspace
