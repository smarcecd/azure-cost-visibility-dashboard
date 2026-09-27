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
- [ ] The account you use to access the Azure Portal as Admin, must have an active Outlook mailbox.

If you've already completed a previous lab in this series, Terraform and the Azure CLI should be already installed.

---

## 📁 Project Structure

```text
azure-cost-dashboard-lab/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
└── terraform.tfvars
```

---

## 🚀 Deployment Guide

### Step 1 — Clone This Repository

```powershell
git clone https://github.com/smarcecd/azure-cost-visibility-dashboard.git
```
Access to the new created folder
```powershell
cd azure-cost-visibility-dashboard
```

### Step 2 — Log In to Azure

```powershell
az login
```

### ⚙️ Step 3 — Configure Variables

Update your information ont **terraform.tfvars**. Copy the example variables file and fill in your own values:

```hcl
yourname     = "yourname"
location     = "East US"
alert_email  = "your.email@example.com"
```

`yourname` keeps every resource name unique; `alert_email` is where budget-threshold notifications will land.

Also, update the **start_date** on the **main.tf** file to the date your are doing the lab or a day after.

### 🏗️ Step 4 — Deploy Infrastructure

```powershell
terraform init
```
```powershell
terraform plan   
```
```powershell
terraform apply
```


### 🔧 Step 5 — Configure the Logic App (Portal)

Terraform provisions the Logic App container only — the trigger and email action are built in the visual designer, and the Office 365 connector requires an interactive sign-in Terraform can't automate.

1. Open `la-cost-alert-[yourname]` → Development Tools → **Logic app designer**
2. **Add a trigger** → Search and Select **When a HTTP request is received** → Click **Save**
3. Copy the **HTTP URL**
4. Click the **+** → Select **Add New Interaction** → Search for **Office 365 Outlook** → Select **Send an email (V2)** → sign in your Outlook account when prompted
5. Fill in **To**, **Subject** (`Azure Cost Alert — Budget Threshold Reached`)
6. **Body** add dynamic content → `Body` from the HTTP trigger or paste:
   
```powershell
   Azure Cost Alert Triggered 🚨

Your Azure cost threshold has been reached.

**Details:**
@{json(triggerBody())}

Check your Azure Cost Management dashboard for more information.
```

7. **Save**

 

 ### 🔧 Step 6 — Attach the Logic App as a receiver on the Action Group

 **Option 1:** 

 1. Got to Home → **Monitor** → **Alerts** → **Action groups** → ag-cost-alerts-yourname
 2. Click **Edit** and scroll down to **Actions** and Fill in:<br>
        Action name: `logic-app-alert` <br>
        Action type: `Logic App` <br>
        Logic App: Select `la-cost-alert-yourname` <br>
 

 **Option 2:** You can also do it trough the Azure Portal and click on **Cloud Shell**, select **Bash** and paste:

```powershell
az monitor action-group update \
  --name ag-cost-alerts-yourname \
  --resource-group rg-cost-dashboard-yourname \
  --add-action webhook la-webhook \
    "<logic-app-callback-url>"
```


### 📊 Step 7 — Build the Cost Dashboard (Azure Workbooks)

1. In the Azure portal search for **Monitor** → Select  **Workbooks** → Click **+ New**
2. Lists every resource group in your subscription, shows its Azure region, counts how many resources it contains, and sorts the groups from most to least populated.
   Click **+ Add** → **Add query** → Data source: **Azure Resource Graph** → Subscriptions: **Your Subscription**
   Paste:
```powershell
  resourcecontainers
| where type == "microsoft.resources/subscriptions/resourcegroups"
| join kind=leftouter (
    resources
    | summarize resourceCount = count() by resourceGroup
) on resourceGroup
| project resourceGroup, location, resourceCount
| order by resourceCount desc
```

3. Lists every resource in your subscription along with its type, resource group, location, and key tag‑based cost attributes (environment, owner, costCenter), then sorts them by cost center and owner to support chargeback and cost‑allocation visibility.
   Click **+ Add** → **Add query** → Data source: **Azure Resource Graph** → Subscriptions: **Your Subscription**
   Paste:
```powershell
    resources
| project name,
         type,
         resourceGroup,
         location,
         environment = tostring(tags.environment),
         owner       = tostring(tags.owner),
         costCenter  = tostring(tags.costCenter)
| order by costCenter asc, owner asc
```

4. It counts how many resources exist for each resource type in your subscription and sorts those types from most to least common.
   Click **+ Add** → **Add query** → Data source: **Azure Resource Graph** → Subscriptions: **Your Subscription**
   Paste:
```powershell
   resources
| summarize count() by type
| order by count_ desc
```

5. **Save** → name it `Cost Visibility Dashboard` → scope to your resource group → **Save As**

---

## 🧪 Step 8 — Validate the Alert Pipeline

Budget thresholds only fire on *actual* spend, so the fastest way to confirm the pipeline works end-to-end is to trigger a test notification manually rather than waiting for real usage. <br>


 **- Resource group deployed**   <br>
 
 
Portal → Resource Groups → `rg-cost-dashboard-[yourname]`  → Action Group, Logic App and Log Analytics Workspace 

<img width="791" height="389" alt="RG_cost-dashboard" src="https://github.com/user-attachments/assets/76ab1b72-6bec-4995-b3eb-7407cfdcde35" /> <br>


***

 **- Budget thresholds active**  <br>
 
 
 Subscriptions → Your Subscription Name → Budgets → 3 notifications at 25% / 50% / 100% of $200  <br>

<img width="928" height="347" alt="budgets1" src="https://github.com/user-attachments/assets/c1b1f174-a445-404c-a21f-11db16bb7350" /> <br>
 <img width="637" height="409" alt="budgets2" src="https://github.com/user-attachments/assets/c0ccbe55-29f8-42b0-b39f-ebc6382e6218" /> <br>


***

 **- Action Group has both receivers** <br>
 
 
 Monitor → Action groups →  Email receiver + Logic App receiver | Webhook receiver <br>
 
 <img width="822" height="223" alt="action group" src="https://github.com/user-attachments/assets/d90d74da-988c-4f65-ba93-227688c2b422" /> <br>

 
***

**- Logic App is live**  <br>

Home → Logic Apps | Status: **Enabled**:   <br>


<img width="865" height="199" alt="logic app" src="https://github.com/user-attachments/assets/b2774b6c-bf4b-4957-a048-7b06e31d658c" />


Run history shows a successful test:   <br>

<img width="946" height="164" alt="Screenshot 2026-09-26 230438" src="https://github.com/user-attachments/assets/3b71d4bd-f843-4c18-ab58-fac0fecbff4e" />


<img width="560" height="327" alt="Screenshot 2026-09-26 230554" src="https://github.com/user-attachments/assets/8782dc77-3118-4703-8a42-798d90560e5e" />


Test alert email received in Your inbox:  <br>


<img width="596" height="259" alt="Screenshot 2026-09-26 230809" src="https://github.com/user-attachments/assets/74e018ef-109c-410b-8cf1-780526e1d586" />


***

**- Workbook renders**

Monitor → Workbooks → Spend broken out by resource group 

<img width="596" height="304" alt="Screenshot 2026-09-26 231210" src="https://github.com/user-attachments/assets/615dff41-2ef3-4d73-a41e-ee7503deaf0a" />

***

**- Log Analytics Workspace**

Home → Log Analytics workspaces → law-cost-yourname → Overview 

Workspace with status Active and tags showing managed_by: terraform. 

<img width="871" height="343" alt="Screenshot 2026-09-26 232652" src="https://github.com/user-attachments/assets/701a691a-ec6b-4b73-bb0b-068aff0e851f" />


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
| Alert email never arrives | Budget thresholds require *actual* spend to cross the limit | Manually fire a test notification from the Action Group to verify delivery, check Spam or Junk folder|

---

## 🏁 Final Notes

This lab is intentionally standalone — no other lab in the series depends on it, so it's safe to tear down as soon as you're done validating it.

```bash
# Full teardown
terraform destroy -auto-approve
```

This mirrors a pattern real teams use to stay ahead of cloud spend rather than reacting to it after the invoice lands.
