# Sentinel SOC Triage Autopilot Operator Runbook

Use this standalone runbook for the first approved live validation. It performs one real incident triage and normally writes one automation-generated comment to the selected Microsoft Sentinel incident.

## Files Used

| File | Operator use |
| --- | --- |
| `sentinel-soc-triage-autopilot.security-copilot.agent.md` | Deploy as the Microsoft Security Copilot agent. |
| `logic-app/infra/main.bicep` | Azure Logic App deployment source. |
| `logic-app/infra/workflow-definition.json` | HTTP trigger and comment writeback workflow source. |
| `logic-app/infra/main.parameters.json` | Target Azure deployment parameters. |
| `GENERIC-DEPLOYMENT-GUIDE.md` | Full generic deployment and configuration instructions. |

## Environment Variables

```text
Subscription ID: <AZURE_SUBSCRIPTION_ID>
Tenant ID:       <MICROSOFT_ENTRA_TENANT_ID>
Resource group:  <RESOURCE_GROUP_NAME>
Workspace name:  <SENTINEL_WORKSPACE_NAME>
Logic App:       <LOGIC_APP_NAME>
Test incident:   <TEST_INCIDENT_NUMBER>
```

Replace the placeholders with the approved deployment values. Use an approved positive Sentinel incident number.

## Safety Requirements

- Use only an approved test incident or an incident with recorded comment-write approval.
- The Logic App callback URL is a secret. Never put it in this runbook, the prompt, chat, screenshots, tickets, or source control.
- The previously embedded callback URL must be regenerated and removed before production use.
- Do not change incident status, severity, owner, tags, labels, bookmarks, tasks, automation rules, or other Sentinel/XDR objects.
- The only permitted external write is the configured Logic App comment callback.

## Preflight Checklist

- [ ] Approval to write an automation comment is recorded.
- [ ] The selected incident is in the intended Sentinel workspace.
- [ ] `main.bicep` compiles successfully.
- [ ] `workflow-definition.json` and `main.parameters.json` parse successfully.
- [ ] Logic App is `Enabled` with provisioning state `Succeeded`.
- [ ] Logic App has a system-assigned managed identity.
- [ ] Identity has `Microsoft Sentinel Contributor` on the intended workspace.
- [ ] Security Copilot has Sentinel retrieval, KQL, and HTTP POST capabilities.
- [ ] No signed callback URL is present in source-controlled files.
- [ ] Test incident number is valid and approved.

## Optional Azure Preflight

Run from the solution folder. These commands are read-only apart from subscription selection.

```powershell
cd "c:\Users\PrashantRangi\OneDrive - IT Ingredients\Documents\Agents\sentinel\AI Security\Custom Agents\Sentinel SOC Triage Autopilot"
az account set --subscription $SubscriptionId
$id = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$PlaybookName"
$raw = az rest --method get --url "https://management.azure.com$id`?api-version=2019-05-01" --only-show-errors | ConvertFrom-Json
[pscustomobject]@{ Name=$raw.name; State=$raw.properties.state; ProvisioningState=$raw.properties.provisioningState; IdentityType=$raw.identity.type; PrincipalId=$raw.identity.principalId } | Format-List
```

Expected values: `State=Enabled`, `ProvisioningState=Succeeded`, and `IdentityType=SystemAssigned`.

Validate the role assignment using the returned principal ID:

```powershell
$workspace = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
$principal = "<PRINCIPAL_ID_FROM_PREVIOUS_COMMAND>"
az role assignment list `
  --assignee-object-id $principal `
  --scope $workspace `
  --include-inherited `
  --query "[?roleDefinitionName=='Microsoft Sentinel Contributor'].{Role:roleDefinitionName,Scope:scope,PrincipalType:principalType}" `
  -o table
```

Expected result: `Microsoft Sentinel Contributor` at the Sentinel workspace scope.

## Execute the Agent

1. Open Microsoft Security Copilot.
2. Select `Sentinel SOC Triage Autopilot (Security Copilot)`.
3. Copy the exact prompt from the section below.
4. Replace `1647` with `<TEST_INCIDENT_NUMBER>`.
5. Submit once and wait for the complete response.

Do not include the callback URL in the prompt or submit a second request while the first run is active.

## Exact Runtime Prompt

```text
Use the Sentinel SOC Triage Autopilot (Security Copilot) agent for incident 1647.

Perform complete triage for exactly this incident. Resolve incident number 1647 to the canonical SecurityIncident.IncidentName, review the incident and priority alerts, extract and deduplicate entities, perform the required bounded corroboration, and state every evidence gap explicitly.

Generate synchronized HTML and Markdown reports using one reportVersion and one generatedUtc value. Invoke the configured Logic App callback exactly once after local report fidelity checks. Send only the HTML report in commentBody. Do not directly call Sentinel comments APIs. Do not change incident status, severity, owner, tags, labels, bookmarks, tasks, or any other Sentinel or XDR object.

If the callback receives a retryable transport error, HTTP 408, 429, or 5xx, retry at most once with the identical reportVersion, generatedUtc, incidentId, incidentNumber, and commentBody. Do not retry after any valid Logic App response.

Return exactly the two required sections: SECTION - Analyst Readable Report and SECTION - Writeback Execution Result. The writeback result must include LogicAppExecuted, SentinelCommentFormat, SentinelCommentBodySent, CommentUpdateStatus, CommentTarget, CommentUpdateAttempts, ReportVersion, GeneratedUtc, IncidentIdSent, IncidentNumberSent, Verified, and FailureReason.
```

## Validate the Response

The response must contain exactly `SECTION - Analyst Readable Report` followed by `SECTION - Writeback Execution Result`.

For a successful new-comment test, require:

```text
LogicAppExecuted: yes
SentinelCommentFormat: HTML
SentinelCommentBodySent: yes
CommentUpdateStatus: Done-CreatedNew
CommentTarget: <non-empty comment id>
CommentUpdateAttempts: 1
ReportVersion: <vUTC timestamp>
GeneratedUtc: <UTC ISO-8601 timestamp>
IncidentIdSent: <canonical SecurityIncident.IncidentName>
IncidentNumberSent: <TEST_INCIDENT_NUMBER>
Verified: true
FailureReason: none
```

Confirm the analyst report starts with `=== INCIDENT TRIAGE REPORT ===`, ends with `=== END OF REPORT ===`, uses Markdown tables, includes findings and gaps, and exposes no callback URL or secret.

## Validate the Sentinel Comment

Open the approved incident in Microsoft Sentinel and confirm one new automation-generated comment exists for the report version. Confirm the body uses simple HTML tables, contains the same report version, starts with `=== INCIDENT TRIAGE REPORT ===`, ends with `=== END OF REPORT ===`, and contains no visible literal `\\n` or `` `n`` text.

## Validate the Logic App Run

Inspect the matching run in Azure Portal or with:

```powershell
$runs = az rest --method get --url "https://management.azure.com$id/runs?api-version=2019-05-01" --only-show-errors | ConvertFrom-Json
$runs.value | ForEach-Object { [pscustomobject]@{ Status=$_.properties.status; StartTime=$_.properties.startTime; EndTime=$_.properties.endTime } } | Format-Table -AutoSize
```

The matching run should show overall `Succeeded`, successful `HTTP_List_comments`, successful creation or duplicate branch, successful `HTTP_Verify_comments`, successful `Filter_Verification`, and final business result `Done-CreatedNew` with `verified: true`.

An overall run status of `Succeeded` alone is insufficient because the workflow can complete technically while setting `Failed-Validation` after verification.

## Idempotency Test

After the first successful test, reuse the identical report version and payload through an approved controlled mechanism. Expected result: no second comment, existing comment target returned, status `Done-CreatedNew` under the current compatibility contract, and verification remains successful.

## Failure Handling

| Result | Action |
| --- | --- |
| `Failed-Validation` | Inspect marker, report version, comment body, and verification results. Do not manually post until understood. |
| `Failed-Authorization` | Verify managed identity and workspace role assignment. |
| `Failed-ToolUnavailable` | Verify Sentinel, KQL, HTTP capability, and Logic App connectivity. |
| `Failed-Unknown` | Inspect the failed action. Retry only for transport errors, 408, 429, or 5xx. |
| Retryable transport/HTTP error | Retry at most once with identical report version, timestamp, incident ID, incident number, and comment body. |

Never call Sentinel comments APIs directly as a fallback.

## Closeout Record

Record this in the approved change or test ticket. Do not include callback URLs, tokens, raw incident data, or sensitive telemetry.

```text
Test incident number: <TEST_INCIDENT_NUMBER>
Execution time UTC: <UTC timestamp>
Logic App run ID: <run ID>
Report version: <report version>
Overall run status: <Succeeded/other>
Writeback status: <Done-CreatedNew/Failed-*>
Verified: <true/false>
Comment target: <target or unknown>
Duplicate test result: <passed/failed/not run>
Failure reason: <none or concise reason>
```

## Completion Checklist

- [ ] Approved test incident was used.
- [ ] Agent returned exactly two required sections.
- [ ] Canonical incident ID was sent.
- [ ] HTML comment was created or the expected existing comment was found.
- [ ] Report version was verified in Sentinel comments.
- [ ] Writeback status was `Done-CreatedNew`.
- [ ] `Verified` was `true`.
- [ ] Duplicate behavior was tested or marked not run.
- [ ] No secrets were recorded in the closeout ticket.