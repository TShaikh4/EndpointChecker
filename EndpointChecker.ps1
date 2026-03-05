[CmdletBinding()]
param(
    [string]$OutputDir = '.\Artifacts',

    [ValidateSet('HTML', 'HTML+CSV')]
    [string]$Format = 'HTML',

    [int]$DiskWarnPercent = 80,
    [int]$DiskFailPercent = 90,
    [int]$UptimeWarnDays = 7,
    [int]$PatchFailDays = 30,
    [int]$InactiveDays = 90,

    [string[]]$ExpectedAdmins = @(
        'svc_it_ops'
    ),

    [switch]$VerboseLogging
)

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

$scriptFiles = @(
    'Scripts/Shared/Write-Log.ps1',
    'Scripts/Shared/Get-PrivilegeContext.ps1',
    'Scripts/Shared/Get-StatusFromThreshold.ps1',
    'Scripts/Shared/ConvertTo-ReportModel.ps1',
    'Scripts/Shared/Invoke-Check.ps1',
    'Templates/HtmlTemplate.ps1',
    'Scripts/Output/New-HtmlReport.ps1',
    'Scripts/Output/New-CsvReport.ps1',
    'Scripts/Core/Get-SystemOverview.ps1',
    'Scripts/Core/Get-SecurityPosture.ps1',
    'Scripts/Audit/Get-UserAccessControl.ps1',
    'Scripts/Audit/Get-PatchCompliance.ps1'
)

foreach ($relativePath in $scriptFiles) {
    $fullPath = Join-Path -Path $scriptRoot -ChildPath $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Required script file not found: $fullPath"
    }

    . $fullPath
}

$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
}
else {
    Join-Path -Path $scriptRoot -ChildPath $OutputDir
}

if (-not (Test-Path -LiteralPath $resolvedOutputDir)) {
    New-Item -Path $resolvedOutputDir -ItemType Directory -Force | Out-Null
}

$scanStartedUtc = (Get-Date).ToUniversalTime()
$timestampForFiles = (Get-Date).ToString('yyyyMMdd_HHmmss')
$computerName = $env:COMPUTERNAME
if (-not $computerName) {
    $computerName = [System.Environment]::MachineName
}

$logPath = Join-Path -Path $resolvedOutputDir -ChildPath ("EndpointChecker_{0}_{1}.log" -f $computerName, $timestampForFiles)
Initialize-EndpointCheckerLogger -Path $logPath -VerboseLogging:$VerboseLogging

Write-Log -Message 'EndpointChecker scan started.' -Level 'INFO'

$privilegeContext = Get-PrivilegeContext
Write-Log -Message ("Scan user context: {0}; IsAdministrator={1}" -f $privilegeContext.UserName, $privilegeContext.IsAdministrator) -Level 'INFO'

if ($privilegeContext.ErrorMessage) {
    Write-Log -Message ("Privilege context warning: {0}" -f $privilegeContext.ErrorMessage) -Level 'WARN'
}

$allChecks = @()

try {
    Write-Log -Message 'Running System Overview checks.' -Level 'INFO'
    $allChecks += Get-SystemOverview -DiskWarnPercent $DiskWarnPercent -DiskFailPercent $DiskFailPercent -UptimeWarnDays $UptimeWarnDays
}
catch {
    Write-Log -Message ("System Overview module failed: {0}" -f $_.Exception.Message) -Level 'ERROR'
}

try {
    Write-Log -Message 'Running Security Posture checks.' -Level 'INFO'
    $allChecks += Get-SecurityPosture -PatchFailDays $PatchFailDays
}
catch {
    Write-Log -Message ("Security Posture module failed: {0}" -f $_.Exception.Message) -Level 'ERROR'
}

try {
    Write-Log -Message 'Running User & Access Control checks.' -Level 'INFO'
    $allChecks += Get-UserAccessControl -ExpectedAdmins $ExpectedAdmins -InactiveDays $InactiveDays
}
catch {
    Write-Log -Message ("User & Access Control module failed: {0}" -f $_.Exception.Message) -Level 'ERROR'
}

try {
    Write-Log -Message 'Running Patch Compliance checks.' -Level 'INFO'
    $allChecks += Get-PatchCompliance -PatchFailDays $PatchFailDays
}
catch {
    Write-Log -Message ("Patch Compliance module failed: {0}" -f $_.Exception.Message) -Level 'ERROR'
}

if ($allChecks.Count -eq 0) {
    throw 'No checks were collected. Unable to generate report.'
}

$metadata = @{
    ComputerName     = $computerName
    UserName         = $privilegeContext.UserName
    IsAdministrator  = $privilegeContext.IsAdministrator
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    StartedAtUtc     = $scanStartedUtc.ToString('o')
}

$reportModel = ConvertTo-ReportModel -Checks $allChecks -Metadata $metadata

$htmlPath = Join-Path -Path $resolvedOutputDir -ChildPath ("EndpointChecker_{0}_{1}.html" -f $computerName, $timestampForFiles)
try {
    New-HtmlReport -ReportModel $reportModel -OutputPath $htmlPath | Out-Null
    Write-Log -Message ("HTML report written to {0}" -f $htmlPath) -Level 'INFO'
}
catch {
    Write-Log -Message ("Failed to generate HTML report: {0}" -f $_.Exception.Message) -Level 'ERROR'
    throw
}

$csvPath = $null
if ($Format -eq 'HTML+CSV') {
    $csvPath = Join-Path -Path $resolvedOutputDir -ChildPath ("EndpointChecker_{0}_{1}.csv" -f $computerName, $timestampForFiles)
    try {
        New-CsvReport -Checks $allChecks -OutputPath $csvPath -ComputerName $computerName | Out-Null
        Write-Log -Message ("CSV report written to {0}" -f $csvPath) -Level 'INFO'
    }
    catch {
        Write-Log -Message ("Failed to generate CSV report: {0}" -f $_.Exception.Message) -Level 'ERROR'
    }
}

$scanEndedUtc = (Get-Date).ToUniversalTime().ToString('o')
Write-Log -Message ("EndpointChecker scan completed at {0}." -f $scanEndedUtc) -Level 'INFO'
Write-Log -Message ("Summary score: {0}/{1} passed; warnings={2}; failed={3}; notEvaluated={4}" -f $reportModel.Summary.Passed, $reportModel.Summary.Evaluated, $reportModel.Summary.Warnings, $reportModel.Summary.Failed, $reportModel.Summary.NotEvaluated) -Level 'INFO'

Write-Host ("EndpointChecker completed. HTML report: {0}" -f $htmlPath)
if ($csvPath) {
    Write-Host ("CSV report: {0}" -f $csvPath)
}
Write-Host ("Log file: {0}" -f $logPath)
