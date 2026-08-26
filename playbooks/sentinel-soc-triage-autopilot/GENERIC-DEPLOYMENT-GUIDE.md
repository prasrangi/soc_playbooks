# Sentinel SOC Triage Autopilot Generic Deployment Guide

This GitHub-safe guide describes how to deploy and validate the Sentinel SOC Triage Autopilot in any authorized Azure environment. It contains no tenant-specific identifiers or callback secrets.

## Repository Files

| File | Purpose |
| --- | --- |
| `sentinel-soc-triage-autopilot.security-copilot.agent.md` | Microsoft Security Copilot agent definition. |
| `sentinel-soc-triage-autopilot.agent.md` | Portable VS Code/GitHub Copilot agent definition. |
| `logic-app/infra/main.bicep` | Consumption Logic App, managed identity, and RBAC deployment. |
| `logic-app/infra/workflow-definition.json` | HTTP trigger and Sentinel comment writeback workflow. |
| `logic-app/infra/main.parameters.sample.json` | Safe starting point for deployment parameters. |
| `logic-app/infra/main.parameters.json` | Local deployment parameters. Keep environment-specific and secret-free. |
| `OPERATOR-RUNBOOK.md` | Operator test and validation procedure. |

## Architecture

The solution has two independently deployed parts:

1. An Azure Logic App receives a report payload, creates an append-only Sentinel incident comment, and verifies the report version.
2. A Microsoft Security Copilot custom agent resolves and triages one incident, generates synchronized HTML and Markdown reports, and calls the Logic App.

The only permitted external write is the configured Logic App comment operation. The agent must not change incident status, severity, owner, tags, labels, bookmarks, tasks, automation rules, or other Sentinel/XDR objects.

## Required Variables

Set these values once at the top of each PowerShell session. Do not commit this block with real environment values to GitHub.

```powershell
$ErrorActionPreference = "Stop"

$SolutionRoot = "C:\Path\To\Sentinel-SOC-Triage-Autopilot"
$SubscriptionId = "<AZURE_SUBSCRIPTION_ID>"
$TenantId = "<MICROSOFT_ENTRA_TENANT_ID>"
$ResourceGroupName = "<RESOURCE_GROUP_NAME>"
$WorkspaceName = "<SENTINEL_WORKSPACE_NAME>"
$Location = "<AZURE_REGION>"
$PlaybookName = "sentinel-incident-comment-upsert"
$TestIncidentNumber = "<APPROVED_TEST_INCIDENT_NUMBER>"

$InfraPath = Join-Path $SolutionRoot "logic-app\infra"
$ParametersPath = Join-Path $InfraPath "main.parameters.json"
$SampleParametersPath = Join-Path $InfraPath "main.parameters.sample.json"
$WorkflowDefinitionPath = Join-Path $InfraPath "workflow-definition.json"
$LogicAppResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$PlaybookName"
$WorkspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
```

Use a secure local method for values such as subscription IDs and tenant IDs if organizational policy requires it. Never place a signed Logic App callback URL in this file, an agent file, a prompt, or source control.

## Prerequisites

- Azure CLI is installed and available as `az`.
- Bicep build support is available through Azure CLI.
- You are authorized to deploy to the target resource group.
- The target Log Analytics workspace already exists.
- You can assign `Microsoft Sentinel Contributor` to the Logic App identity at workspace scope.
- Microsoft Security Copilot is available in the target tenant.
- Sentinel incident and alert retrieval, KQL/Log Analytics, and HTTP POST capabilities are available to the agent.
- An approved non-production or test incident is available for writeback testing.

## 1. Set the Working Directory

```powershell
Set-Location -Path $SolutionRoot
if ((Get-Location).Path -ne (Resolve-Path $SolutionRoot).Path) {
  throw "Unable to use SolutionRoot: $SolutionRoot"
}
```

## 2. Prepare Parameters

Create the local parameter file from the sample:

```powershell
Copy-Item -Path $SampleParametersPath -Destination $ParametersPath -Force
```

Edit `logic-app/infra/main.parameters.json` and replace the placeholders:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "playbookName": {
      "value": "<LOGIC_APP_NAME>"
    },
    "location": {
      "value": "<AZURE_REGION>"
    },
    "workspaceName": {
      "value": "<SENTINEL_WORKSPACE_NAME>"
    }
  }
}
```

The `workspaceName` value must be the existing Sentinel/Log Analytics workspace name in `$ResourceGroupName`. The `playbookName` value must match `$PlaybookName`.

## 3. Validate Source Files

```powershell
Set-Location -Path $SolutionRoot
Get-Content -Raw -Path $WorkflowDefinitionPath | ConvertFrom-Json | Out-Null
Get-Content -Raw -Path $ParametersPath | ConvertFrom-Json | Out-Null
Get-Content -Raw -Path $SampleParametersPath | ConvertFrom-Json | Out-Null
Write-Output "JSON parse: PASS"
```

Compile the Bicep template:

```powershell
Push-Location -Path $InfraPath
try {
  az bicep build --file ".\main.bicep" --stdout | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed" }
  Write-Output "Bicep build: PASS"
}
finally {
  Pop-Location
}
```

Check that secrets are absent from tracked content:

```powershell
Get-ChildItem -Path $SolutionRoot -Recurse -File |
  Select-String -Pattern "LogicAppCallbackUrl:\s*https://|https://[^\s`\"]*triggers/manual/paths/invoke|client_secret|password" |
  Select-Object Path, LineNumber
```

Expected GitHub-safe result: no live signed callback URL, password, or client secret is found.

## 4. Sign In and Select the Subscription

```powershell
az login --tenant $TenantId
az account set --subscription $SubscriptionId
az account show --query "{subscriptionId:id,subscriptionName:name,tenantId:tenantId,user:user.name}" -o json
```

Confirm the returned subscription and tenant match the values selected for this deployment.

## 5. Deploy the Logic App

```powershell
Set-Location -Path $SolutionRoot
az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file (Join-Path $InfraPath "main.bicep") `
  --parameters "@$ParametersPath"
```

The deployment creates or updates:

- A Consumption Logic App.
- A system-assigned managed identity.
- A workspace-scoped `Microsoft Sentinel Contributor` role assignment.
- A secure manual-trigger callback URL output.

Store the callback URL only in the approved Security Copilot HTTP action or secret-management mechanism. Do not print it or commit it.

## 6. Validate the Deployed Resource

```powershell
$logicApp = az rest `
  --method get `
  --url "https://management.azure.com$LogicAppResourceId`?api-version=2019-05-01" `
  --only-show-errors | ConvertFrom-Json

[pscustomobject]@{
  Name = $logicApp.name
  State = $logicApp.properties.state
  ProvisioningState = $logicApp.properties.provisioningState
  Location = $logicApp.location
  IdentityType = $logicApp.identity.type
  PrincipalId = $logicApp.identity.principalId
} | Format-List
```

Expected values:

```text
State:             Enabled
ProvisioningState: Succeeded
IdentityType:      SystemAssigned
```

Validate the role assignment:

```powershell
$principalId = $logicApp.identity.principalId
az role assignment list `
  --assignee-object-id $principalId `
  --scope $WorkspaceResourceId `
  --include-inherited `
  --query "[?roleDefinitionName=='Microsoft Sentinel Contributor'].{Role:roleDefinitionName,Scope:scope,PrincipalType:principalType}" `
  -o table
```

Expected result: `Microsoft Sentinel Contributor` at `$WorkspaceResourceId`.

## 7. Validate the Live Workflow Contract

```powershell
$schema = $logicApp.properties.definition.triggers.manual.inputs.schema
$actions = @($logicApp.properties.definition.actions.PSObject.Properties.Name)

[pscustomobject]@{
  ManualTrigger = ($null -ne $logicApp.properties.definition.triggers.manual)
  ResponseAction = ($null -ne $logicApp.properties.definition.actions.Response)
  CreateCommentAction = ($null -ne $logicApp.properties.definition.actions.Condition_List_succeeded.actions.Condition_Has_existing_comment.else.actions.HTTP_Create_new_comment)
  RequiredFieldCount = @($schema.required).Count
  RequiredFields = $schema.required -join ", "
  ActionCount = $actions.Count
} | Format-List
```

Expected required fields:

```text
subscriptionId, resourceGroupName, workspaceName, incidentId,
incidentNumber, reportVersion, generatedUtc, commentBody, mode
```

## 8. Deploy the Security Copilot Agent

Use `sentinel-soc-triage-autopilot.security-copilot.agent.md` as the Security Copilot agent definition.

Before deployment:

- Replace every environment placeholder with values from the approved deployment.
- Confirm the workspace resource ID uses `$SubscriptionId`, `$ResourceGroupName`, and `$WorkspaceName`.
- Confirm the Logic App resource ID uses `$LogicAppResourceId`.
- Confirm the comment marker is exactly `=== INCIDENT TRIAGE REPORT ===`.
- Remove any live callback URL from the markdown file.

Enable or configure:

1. Microsoft Sentinel incident and alert retrieval.
2. KQL or Log Analytics queries against the target workspace.
3. HTTP POST action capability to the Logic App callback.
4. Defender XDR enrichment when available.

The agent must send the canonical `SecurityIncident.IncidentName` as `incidentId`, not only the human incident number.

## 9. Run the Approved Test

Use the standalone [OPERATOR-RUNBOOK.md](OPERATOR-RUNBOOK.md) for the detailed operator procedure.

The test must use an approved incident and must verify:

- A valid incident produces exactly two final response sections.
- The response reports `LogicAppExecuted: yes`.
- The response reports `CommentUpdateStatus: Done-CreatedNew`.
- The response reports `Verified: true`.
- `IncidentIdSent` is the canonical incident resource name/GUID.
- The Sentinel comment contains the HTML report and matching report version.
- Reusing the same report version does not create a duplicate comment.

## Exact Generic Runtime Prompt

Replace `<TEST_INCIDENT_NUMBER>` with the approved test incident number before submitting. Do not add a callback URL.

```text
Use the Sentinel SOC Triage Autopilot (Security Copilot) agent for incident <TEST_INCIDENT_NUMBER>.

Perform complete triage for exactly this incident. Resolve the incident number to the canonical SecurityIncident.IncidentName, review the incident and priority alerts, extract and deduplicate entities, perform the required bounded corroboration, and state every evidence gap explicitly.

Generate synchronized HTML and Markdown reports using one reportVersion and one generatedUtc value. Invoke the configured Logic App callback exactly once after local report fidelity checks. Send only the HTML report in commentBody. Do not directly call Sentinel comments APIs. Do not change incident status, severity, owner, tags, labels, bookmarks, tasks, or any other Sentinel or XDR object.

If the callback receives a retryable transport error, HTTP 408, 429, or 5xx, retry at most once with the identical reportVersion, generatedUtc, incidentId, incidentNumber, and commentBody. Do not retry after any valid Logic App response.

Return exactly two sections: SECTION - Analyst Readable Report and SECTION - Writeback Execution Result. The writeback result must include LogicAppExecuted, SentinelCommentFormat, SentinelCommentBodySent, CommentUpdateStatus, CommentTarget, CommentUpdateAttempts, ReportVersion, GeneratedUtc, IncidentIdSent, IncidentNumberSent, Verified, and FailureReason.
```

## 10. Validate Run History

```powershell
$runs = az rest `
  --method get `
  --url "https://management.azure.com$LogicAppResourceId/runs?api-version=2019-05-01" `
  --only-show-errors | ConvertFrom-Json

if (@($runs.value).Count -eq 0) {
  Write-Output "RecentRuns=0"
}
else {
  $runs.value | ForEach-Object {
    [pscustomobject]@{
      Status = $_.properties.status
      StartTime = $_.properties.startTime
      EndTime = $_.properties.endTime
    }
  } | Format-Table -AutoSize
}
```

An overall Logic App run status of `Succeeded` is not sufficient by itself. Confirm the final business response is `Done-CreatedNew`, `verified: true`, and has the same report version that was sent.

## Completion Criteria

- [ ] Deployment parameters contain only approved environment values and no secrets.
- [ ] JSON parsing passes.
- [ ] Bicep compilation passes.
- [ ] Logic App is `Enabled` and `Succeeded`.
- [ ] Managed identity has `Microsoft Sentinel Contributor` at the intended workspace scope.
- [ ] Live trigger contract contains all required fields.
- [ ] Security Copilot agent has Sentinel, KQL, and HTTP capabilities.
- [ ] Approved test incident produces a verified comment.
- [ ] Duplicate report version does not create a duplicate comment.
- [ ] No callback URL or other secret is committed to GitHub.

## GitHub Publishing Checklist

Before pushing this repository:

```powershell
Set-Location -Path $SolutionRoot
Get-ChildItem -Recurse -File |
  Select-String -Pattern "LogicAppCallbackUrl:\s*https://|https://[^\s`\"]*triggers/manual/paths/invoke|client_secret|password" |
  Select-Object Path, LineNumber
```

The command must return no live secrets. Keep `main.parameters.json` local or provide a sanitized example file if the repository requires a tracked parameter file.