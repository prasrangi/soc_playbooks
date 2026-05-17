# SOC Playbooks

This repository contains SOC playbooks for common security investigation and response scenarios. The goal is to provide clear, repeatable, and analyst-friendly workflows that can be used manually or integrated into automation platforms.

## Purpose

These playbooks are intended to help security teams:

- Investigate incidents in a consistent way
- Reduce analyst decision fatigue
- Standardize evidence collection and verdicting
- Improve incident response speed and quality
- Support future automation and orchestration

## Planned playbooks

This repository is being built as a modular collection of SOC playbooks. Planned playbooks include:

- Malware investigation
- Phishing investigation
- Identity compromise investigation
- Threat intelligence investigation
- SaaS or cloud app compromise investigation
- Ransomware investigation
- Data exfiltration investigation
- Privileged account abuse investigation

## Repository structure

Example structure:

```text
/
├─ README.md
├─ playbooks/
│  ├─ SOC_malware_investigation.md
│  ├─ SOC_phishing_investigation.md
│  ├─ SOC_identity_compromise_investigation.md
│  ├─ CTI_investigation_playbook.md
│  └─ ...
├─ scripts/
│  └─ Invoke-IncidentWriteback.ps1
└─ docs/
   └─ setup.md
```

## Design principles

These playbooks are designed with the following principles:

- Keep playbooks simple and practical
- Focus on evidence-driven investigation
- Prefer clear decision points over long narrative guidance
- Separate common standards from incident-specific workflows
- Make playbooks easy to use in both analyst-led and automated workflows
- Improve continuously based on lessons learned

## How to use this repository

- Use each playbook for the incident type it is designed for
- Update environment-specific values before use, such as workspace names, tags, API paths, and automation references
- Test all response actions in a lab or non-production environment before production rollout
- If scripts are included, review authentication, permissions, and secret handling before use
- Keep organization-specific settings outside the public version of the repository where possible

## Before production use

Before consuming any playbook in this repository, review and update:

- Microsoft Sentinel workspace names
- Tenant-specific API or portal references
- Incident classification, determination, and status values
- Tag names and internal naming conventions
- Script paths and automation tool references
- Authentication and secret handling methods
- Approval requirements for containment or write-back actions

## Scripts and automation

Some playbooks may use helper scripts for actions such as:

- Incident write-back
- Tagging
- Classification updates
- Status updates
- Entity lookups
- Response actions

Store reusable scripts in the `scripts/` folder and update playbooks to reference the correct local path.

## Security note

Do not store real credentials, secrets, tenant-specific sensitive values, or production incident data in this repository. If any helper script uses authentication, replace hard-coded values with secure methods such as environment variables, managed identities, or secret stores before use.

## Contribution approach

When adding a new playbook:

- Keep the scope limited to one incident type
- Follow a consistent structure
- Include prerequisites, investigation steps, output format, and action guidance
- Keep environment-specific values easy to find and replace
- Prefer clarity over completeness

## Status

This repository is currently under active development and will expand over time as additional SOC playbooks are added and refined.
