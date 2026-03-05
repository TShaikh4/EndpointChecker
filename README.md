# EndpointChecker

EndpointChecker is a modular PowerShell 5.1 tool that scans a local Windows machine for system health and security compliance signals, then generates a clean report with per-check `PASS/WARN/FAIL` outcomes.

## Overview

The scanner collects endpoint data across four areas:

- System Overview
- Security Posture
- User & Access Control
- Patch Compliance

It is built to keep running even when certain checks are unavailable (for example, limited privileges or missing platform features), and clearly marks those checks as not evaluated.

## Core checks

### System Overview

- CPU usage average over 60 seconds
- RAM usage (used, free, total)
- Disk usage per fixed drive with warning/fail thresholds
- Uptime since last reboot
- OS version/build metadata

### Security Posture

- Firewall profile status (Domain/Private/Public)
- Latest installed update age and pending update count
- Guest account enabled/disabled
- Account lockout policy
- Password complexity policy
- Auto-login registry setting

### User & Access Control

- Local Administrators membership audit
- Inactive enabled local accounts (default 90+ days)
- Last login visibility per local user

### Patch Compliance

- Recently installed updates with dates
- Fails if latest patch age exceeds threshold (default 30 days)

## Output

### HTML report (default)

- Self-contained file with inline styles
- Color-coded status badges:
  - PASS = green
  - WARN = yellow
  - FAIL = red
- Includes summary score: `X of Y checks passed`
- Includes explicit `Checks Not Evaluated` section

### CSV report (optional)

- One row per check
- Useful for aggregation and machine-to-machine processing

### Run log

- Timestamped log file per execution
- Captures scan context, per-check errors, and output paths

## Project structure

```text
EndpointChecker/
  EndpointChecker.ps1
  Scripts/
    Core/
      Get-SystemOverview.ps1
      Get-SecurityPosture.ps1
    Audit/
      Get-UserAccessControl.ps1
      Get-PatchCompliance.ps1
    Shared/
      Invoke-Check.ps1
      Get-PrivilegeContext.ps1
      ConvertTo-ReportModel.ps1
      Get-StatusFromThreshold.ps1
      Write-Log.ps1
    Output/
      New-HtmlReport.ps1
      New-CsvReport.ps1
  Templates/
    HtmlTemplate.ps1
  Tests/
    *.Tests.ps1
  Artifacts/
```

## Result contract

Each check returns a normalized object with:

- `CheckId`
- `Section`
- `CheckName`
- `Status` (`PASS|WARN|FAIL`)
- `Summary`
- `Details`
- `Evidence`
- `CanEvaluate`
- `ErrorMessage`
- `TimestampUtc`

Scoring is calculated as:

- `Y` = evaluated checks (`CanEvaluate = true`)
- `X` = evaluated checks with `Status = PASS`
- WARN/FAIL reduce pass count
- Not-evaluated checks are excluded from denominator

## Requirements

- Windows PowerShell 5.1
- Local machine execution (v1)
- No required external PowerShell modules for scanner functionality
- Optional: `Pester` for test execution

## Usage

Run with defaults:

```powershell
.\EndpointChecker.ps1
```

Generate both HTML and CSV:

```powershell
.\EndpointChecker.ps1 -Format HTML+CSV -OutputDir .\Artifacts
```

Run with custom thresholds:

```powershell
.\EndpointChecker.ps1 `
  -DiskWarnPercent 80 `
  -DiskFailPercent 90 `
  -UptimeWarnDays 7 `
  -PatchFailDays 30 `
  -InactiveDays 90 `
  -ExpectedAdmins "svc_it_ops","helpdesk_admin" `
  -VerboseLogging
```

## Parameters

- `-OutputDir` default: `.\Artifacts`
- `-Format` values: `HTML`, `HTML+CSV`
- `-DiskWarnPercent` default: `80`
- `-DiskFailPercent` default: `90`
- `-UptimeWarnDays` default: `7`
- `-PatchFailDays` default: `30`
- `-InactiveDays` default: `90`
- `-ExpectedAdmins <string[]>` optional expected admin allowlist additions
- `-VerboseLogging` enables additional console logging

## Behavior and safety

- Per-check exception isolation: one failed check does not stop the scan
- Non-admin execution is supported with explicit degraded results
- Fatal exit occurs only if report generation fails
- v1 is reporting-only (no remediation actions)

## Testing

Run tests:

```powershell
Invoke-Pester -Path .\Tests -Output Detailed
```

Current coverage includes:

- Threshold boundary behavior
- Score normalization and denominator rules
- HTML/CSV report generation
- Optional smoke-test path for end-to-end execution

## Roadmap

- Separate remediation workflow with per-action confirmation
- Before/after metrics in remediation reports
- Optional remote endpoint support
- Additional SOC-focused modules (event log analytics, network monitoring, file integrity monitoring)

## License

Add a license file based on your intended usage before publishing.
