# Sentinel SOC Triage Autopilot

This package deploys an authorized Microsoft Sentinel incident triage agent with verified, append-only Logic App comment writeback.

The solution has two parts:

1. A Microsoft Security Copilot custom agent retrieves and analyzes one Sentinel incident, generates synchronized Markdown and HTML reports, and invokes the Logic App.
2. An Azure Logic App receives the HTML report, creates a Sentinel incident comment, prevents duplicate comments for the same report version, and verifies the writeback.

## Package Contents

| File | Purpose |
| --- | --- |
| `sentinel-soc-triage-autopilot.security-copilot.agent.md` | Security Copilot agent definition. |
| `sentinel-soc-triage-autopilot.agent.md` | Portable VS Code/GitHub Copilot agent definition. |
| `logic-app/infra/main.bicep` | Deploys the Logic App, managed identity, and Sentinel RBAC assignment. |
| `logic-app/infra/workflow-definition.json` | Defines the HTTP trigger and comment writeback workflow. |
| `logic-app/infra/main.parameters.sample.json` | Safe deployment parameter template. |
| `GENERIC-DEPLOYMENT-GUIDE.md` | Detailed environment-independent deployment instructions. |
| `OPERATOR-RUNBOOK.md` | Test execution and validation procedure. |

## Security Requirements

- Use only for authorized defensive security operations.
- Use a test or approved Sentinel incident for the first live validation.
- Never commit a signed Logic App callback URL, token, password, tenant secret, or production incident data.
- Configure the callback URL through the approved Security Copilot HTTP action or secret-management mechanism.
- The Logic App identity should receive only the required `Microsoft Sentinel Contributor` role at the intended workspace scope.
- The agent must not change incident status, severity, owner, tags, labels, bookmarks, tasks, automation rules, or other Sentinel/XDR objects.

## Deployment Order

Complete the deployment in this order:

1. Clone this repository and enter the package directory.
2. Set deployment variables.
3. Create and edit `logic-app/infra/main.parameters.json` locally from `main.parameters.sample.json`.
4. Validate JSON and compile `logic-app/infra/main.bicep`.
5. Deploy the Logic App at resource-group scope.
6. Capture the secure callback URL without printing or committing it.
7. Configure the callback in the Security Copilot HTTP action.
8. Replace placeholders in the selected agent definition.
9. Deploy the Security Copilot agent.
10. Run the approved test incident using the prompt below.
11. Verify the agent response, Sentinel comment, Logic App run, and duplicate prevention.

For the complete commands and checks, follow [GENERIC-DEPLOYMENT-GUIDE.md](GENERIC-DEPLOYMENT-GUIDE.md). For the operator test procedure, follow [OPERATOR-RUNBOOK.md](OPERATOR-RUNBOOK.md).

## Required Deployment Variables

Use placeholders in GitHub and set real values only in your local PowerShell session:

```powershell
$ErrorActionPreference = "Stop"
$SolutionRoot = "C:\Path\To\soc_playbooks\playbooks\sentinel-soc-triage-autopilot"
$SubscriptionId = "<AZURE_SUBSCRIPTION_ID>"
$TenantId = "<MICROSOFT_ENTRA_TENANT_ID>"
$ResourceGroupName = "<RESOURCE_GROUP_NAME>"
$WorkspaceName = "<SENTINEL_WORKSPACE_NAME>"
$Location = "<AZURE_REGION>"
$PlaybookName = "sentinel-incident-comment-upsert"
$TestIncidentNumber = "<APPROVED_TEST_INCIDENT_NUMBER>"

$InfraPath = Join-Path $SolutionRoot "logic-app\infra"
$ParametersPath = Join-Path $InfraPath "main.parameters.json"
$WorkspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
$LogicAppResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$PlaybookName"
```

## Logic App Deployment Commands

```powershell
Set-Location -Path $SolutionRoot
Copy-Item (Join-Path $InfraPath "main.parameters.sample.json") $ParametersPath -Force

az login --tenant $TenantId
az account set --subscription $SubscriptionId

Push-Location -Path $InfraPath
try {
  az bicep build --file ".\main.bicep" --stdout | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed" }
}
finally {
  Pop-Location
}

az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file (Join-Path $InfraPath "main.bicep") `
  --parameters "@$ParametersPath"
```

After deployment, validate that the Logic App is enabled, provisioned successfully, has a system-assigned identity, and that the identity has `Microsoft Sentinel Contributor` on `$WorkspaceResourceId`.

## Security Copilot Configuration

Deploy `sentinel-soc-triage-autopilot.security-copilot.agent.md` as the Security Copilot custom agent. Before deployment:

- Replace the subscription, resource group, workspace, workspace resource ID, and Logic App resource ID placeholders.
- Configure the Logic App callback in the approved HTTP action or secret mechanism.
- Do not put the signed callback URL in the agent markdown, prompt, GitHub, or a ticket.
- Enable Sentinel incident and alert retrieval, KQL/Log Analytics, and HTTP POST capabilities.
- Enable Defender XDR enrichment when available.

The agent must send the canonical `SecurityIncident.IncidentName` as `incidentId`, not only the human incident number.

## Expected Successful Result

The Security Copilot response must contain exactly two sections:

```text
SECTION - Analyst Readable Report
<Markdown report>

SECTION - Writeback Execution Result
LogicAppExecuted: yes
SentinelCommentFormat: HTML
SentinelCommentBodySent: yes
CommentUpdateStatus: Done-CreatedNew
CommentTarget: <non-empty comment id>
CommentUpdateAttempts: 1
ReportVersion: <vUTC timestamp>
GeneratedUtc: <UTC ISO-8601 timestamp>
IncidentIdSent: <canonical incident resource name/GUID>
IncidentNumberSent: <test incident number>
Verified: true
FailureReason: none
```

The Sentinel comment must contain the HTML report, the exact report version, the start marker `=== INCIDENT TRIAGE REPORT ===`, and the end marker `=== END OF REPORT ===`.

## Exact End-to-End Prompt

Replace `<APPROVED_TEST_INCIDENT_NUMBER>` with the approved positive Sentinel incident number. Do not add a callback URL to the prompt.

```text
Use the Sentinel SOC Triage Autopilot (Security Copilot) agent for incident <APPROVED_TEST_INCIDENT_NUMBER>.

Perform complete triage for exactly this incident. Resolve the incident number to the canonical SecurityIncident.IncidentName, review the incident and priority alerts, extract and deduplicate entities, perform the required bounded corroboration, and state every evidence gap explicitly.

Generate synchronized HTML and Markdown reports using one reportVersion and one generatedUtc value. Invoke the configured Logic App callback exactly once after local report fidelity checks. Send only the HTML report in commentBody. Do not directly call Sentinel comments APIs. Do not change incident status, severity, owner, tags, labels, bookmarks, tasks, or any other Sentinel or XDR object.

If the callback receives a retryable transport error, HTTP 408, 429, or 5xx, retry at most once with the identical reportVersion, generatedUtc, incidentId, incidentNumber, and commentBody. Do not retry after any valid Logic App response.

Return exactly two sections: SECTION - Analyst Readable Report and SECTION - Writeback Execution Result. The writeback result must include LogicAppExecuted, SentinelCommentFormat, SentinelCommentBodySent, CommentUpdateStatus, CommentTarget, CommentUpdateAttempts, ReportVersion, GeneratedUtc, IncidentIdSent, IncidentNumberSent, Verified, and FailureReason.
```

## Validation Checklist

- [ ] JSON parsing passes.
- [ ] Bicep compilation passes.
- [ ] Logic App is `Enabled` and `Succeeded`.
- [ ] Managed identity has the expected workspace role.
- [ ] Security Copilot agent is deployed with required capabilities.
- [ ] Approved test incident returns exactly two response sections.
- [ ] `CommentUpdateStatus` is `Done-CreatedNew`.
- [ ] `Verified` is `true`.
- [ ] Sentinel comment contains the matching report version.
- [ ] Reusing the same report version does not create a duplicate comment.
- [ ] No secrets are present in the GitHub repository.