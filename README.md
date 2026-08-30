# 💰 Azure Cost Visibility Dashboard (Azure + Terraform)

**Azure Monitor · Cost Management · Logic Apps · Log Analytics · Azure Workbooks · Terraform**

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.3.0-844FBA?logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-East%20US-0078D4?logo=microsoftazure&logoColor=white)
![Status](https://img.shields.io/badge/Status-Lab%20Ready-brightgreen)

A monitoring and alerting system that gives a business owner real-time visibility into their Azure spend — tracking usage across every service, firing email alerts before a budget threshold is crossed, and rolling it all up into a plain-language dashboard.

Watch me building this lab here:

[![CostDashboardLab](PASTE_THUMBNAIL_IMAGE_URL_HERE)](PASTE_LOOM_LINK_HERE)

---

## 🔗 Lab Overview

| Component | Details |
|---|---|
| Resource Group | `rg-cost-dashboard-[yourname]` |
| Region | East US |
| Resources | Log Analytics Workspace, Cost Management Budget, Action Group, Logic App, Azure Workbook |
| Deploy Time | ~5 min (Terraform) + ~10 min (portal: Logic App designer + Workbook) |
| Cost | Near-$0 at lab scale — this project *monitors* spend, it doesn't generate meaningful spend of its own |
| Relationship to other labs | Standalone — doesn't build on other labs |

---

## 🎯 Purpose of This Lab

Most small businesses move to Azure expecting it to be cheaper than running their own servers — then the bill arrives full of line items like `Microsoft.Compute/virtualMachines — $340` that nobody can interpret, predict, or explain. This lab closes that gap.

This project simulates how a real business would monitor and control cloud spend using:

- Azure Cost Management budgets with multi-threshold alerting
- Azure Monitor Action Groups for notification routing
- Logic Apps to turn a raw alert into a plain-language email
- Log Analytics for subscription activity history
- Azure Workbooks for an always-on visual dashboard
- Terraform IaC for the reproducible parts of the stack

You deploy the alerting pipeline end-to-end, wire the notification path together in the portal, and build a live spend dashboard — the same pattern a cost-conscious ops team would use to avoid a surprise invoice.

---

## ✅ Prerequisites

- [ ] [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- [ ] [Terraform](https://developer.hashicorp.com/terraform/downloads) **v1.3+** installed
- [ ] Active Azure subscription with Cost Management Contributor rights (see [Troubleshooting](#-troubleshooting) if you hit `AuthorizationFailed`)
- [ ] Git for Windows/macOS
- [ ] A local directory to store Terraform files

If you've already completed a previous lab in this series, Terraform and the Azure CLI are already installed — skip ahead to [Step 3](#️-step-3--configure-variables).

---

## 📁 Project Structure

```text
azure-cost-dashboard-lab/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── terraform.tfvars
└── .gitignore
```

---

## 🚀 Deployment Guide

### Step 1 — Clone This Repository

```powershell
git clone https://github.com/smarcecd/azure-cost-visibility-dashboard.git
cd azure-cost-visibility-dashboard
```

### Step 2 — Log In to Azure

```powershell
az login
az account set --subscription "Azure subscription 1"
az account show
```

### ⚙️ Step 3 — Configure Variables

Copy the example variables file and fill in your own values:

```hcl
yourname     = "yourname"
location     = "East US"
alert_email  = "your.email@example.com"
```

`yourname` keeps every resource name unique; `alert_email` is where budget-threshold notifications will land.

### 🏗️ Step 4 — Deploy Infrastructure

```powershell
terraform init
terraform plan     # expect 6 resources to add
terraform apply
```

After deployment, capture:

```powershell
terraform output logic_app_callback_url
terraform output action_group_id
```

### 🔧 Step 5 — Wire Up the Logic App (Portal)

Terraform provisions the Logic App container only — the trigger and email action are built in the visual designer, and the Office 365 connector requires an interactive sign-in Terraform can't automate.

1. Open `la-cost-alert-[yourname]` → **Logic app designer**
2. **Add a trigger** → search **HTTP** → **When a HTTP request is received** → Click **Save**
3. Copy the **HTTP POST URL**
4. Click the **+** → Select **New step** → Search for **Office 365 Outlook** → Select **Send an email (V2)** → sign in your Outlook account when prompted
5. Fill in **To**, **Subject** (`Azure Cost Alert — Budget Threshold Reached`), and **Body** (add dynamic content → `Body` from the HTTP trigger)
6. **Save**

Then attach the Logic App as a receiver on the Action Group:

```powershell
az monitor action-group update `
  --name ag-cost-alerts-yourname `
  --resource-group rg-cost-dashboard-yourname `
  --add-action logicapp la-webhook la-cost-alert-yourname `
  /subscriptions/<sub-id>/resourceGroups/rg-cost-dashboard-yourname/providers/Microsoft.Logic/workflows/la-cost-alert-yourname `
  <logic-app-callback-url>
```

### 📊 Step 6 — Build the Cost Dashboard (Azure Workbooks)

1. **Monitor** → **Workbooks** → **+ New**
2. **+ Add** → **Add query** → Data source: **Azure Resource Graph**
3. Paste:
   ```kusto
   resourcecontainers
   | where type == "microsoft.resources/subscriptions/resourcegroups"
   | project resourceGroup, location
   ```
4. **Run Query** → **Done Editing**
5. **+ Add** → **Add metric** → select subscription → resource type **Cost Management**
6. **Save** → name it `Cost Visibility Dashboard` → scope to your resource group → **Apply**

---

## 🧪 Step 7 — Validate the Alert Pipeline

Budget thresholds only fire on *actual* spend, so the fastest way to confirm the pipeline works end-to-end is to trigger a test notification manually rather than waiting for real usage.

| Check | Where | Expected Result |
|---|---|---|
| Resource group deployed | Portal → resource groups | `rg-cost-dashboard-[yourname]` with all 6 resources |
| Budget thresholds active | Cost Management → Budgets | 3 notifications at 25% / 50% / 100% of $200 |
| Action Group has both receivers | Monitor → Action groups | Email receiver + Logic App receiver |
| Logic App is live | Monitor → the Logic App | Status: **Enabled**, run history shows a successful test |
| Test alert email received | Your inbox | Formatted alert email from the Logic App, not a raw JSON payload |
| Workbook renders | Monitor → Workbooks | Spend broken out by resource group |

---

## 📘 What You Learn

| Skill | Why It Matters |
|---|---|
| **Terraform IaC** | Reproducible, version-controlled deployment of the monitoring stack |
| **Cost Management Budgets** | The actual mechanism that turns "check the portal sometimes" into "get notified automatically" |
| **Action Groups** | Decouples *who/what gets notified* from *what triggered the alert* — one group, many alert rules |
| **Logic Apps** | Translates a raw monitoring payload into a message a non-technical stakeholder can read |
| **Log Analytics** | Gives you a queryable history instead of a blank slate every time someone asks "what changed?" |
| **Azure Workbooks** | Turns Resource Graph + Cost Management data into a dashboard non-engineers will actually open |

---

## 🔧 Troubleshooting

| Error | Cause | Resolution |
|---|---|---|
| `BudgetStartDateInvalid` | `start_date` isn't the first of a current/future month | Update `start_date` in `main.tf` |
| `AuthorizationFailed` on budget | Account lacks Cost Management Contributor role | `az role assignment create --role "Cost Management Contributor" --assignee <your-email> --scope /subscriptions/<sub-id>` |
| Logic App email step asks for sign-in | Office 365 connector requires interactive auth | Sign in through the portal designer — Terraform can't automate this |
| Alert email never arrives | Budget thresholds require *actual* spend to cross the limit | Manually fire a test notification from the Action Group to verify delivery |

---

## 🏁 Final Notes

This lab is intentionally standalone — no other lab in the series depends on it, so it's safe to tear down as soon as you're done validating it.

```bash
# Full teardown
terraform destroy
```

This mirrors a pattern real teams use to stay ahead of cloud spend rather than reacting to it after the invoice lands.
