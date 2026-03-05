function ConvertTo-HtmlSafe {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Get-StatusCssClass {
    [CmdletBinding()]
    param(
        [string]$Status
    )

    switch ($Status) {
        'PASS' { return 'status-pass' }
        'WARN' { return 'status-warn' }
        'FAIL' { return 'status-fail' }
        default { return 'status-warn' }
    }
}

function New-HtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ReportModel,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $metadataItems = @(
        [pscustomobject]@{ Label = 'Computer Name'; Value = $ReportModel.Metadata.ComputerName },
        [pscustomobject]@{ Label = 'User Context'; Value = $ReportModel.Metadata.UserName },
        [pscustomobject]@{ Label = 'Is Administrator'; Value = $ReportModel.Metadata.IsAdministrator },
        [pscustomobject]@{ Label = 'PowerShell Version'; Value = $ReportModel.Metadata.PowerShellVersion },
        [pscustomobject]@{ Label = 'Scan Started (UTC)'; Value = $ReportModel.Metadata.StartedAtUtc },
        [pscustomobject]@{ Label = 'Report Generated (UTC)'; Value = $ReportModel.GeneratedAtUtc }
    )

    $metaHtml = ($metadataItems | ForEach-Object {
            "<div class='meta-item'><div class='meta-label'>$([System.Net.WebUtility]::HtmlEncode($_.Label))</div><div class='meta-value'>$([System.Net.WebUtility]::HtmlEncode([string]$_.Value))</div></div>"
        }) -join [Environment]::NewLine

    $sectionBlocks = foreach ($sectionName in $ReportModel.SectionOrder) {
        $section = $ReportModel.Sections | Where-Object { $_.Name -eq $sectionName } | Select-Object -First 1
        if ($null -eq $section) {
            continue
        }

        $rows = foreach ($check in $section.Checks) {
            $statusClass = Get-StatusCssClass -Status $check.Status
            $details = ConvertTo-HtmlSafe -Text $check.Details
            $summary = ConvertTo-HtmlSafe -Text $check.Summary
            $canEvaluateText = if ($check.CanEvaluate) { 'Yes' } else { 'No' }
            $errorText = if ($check.ErrorMessage) {
                "<br/><small class='mono'>Error: $([System.Net.WebUtility]::HtmlEncode([string]$check.ErrorMessage))</small>"
            }
            else {
                ''
            }

            "<tr><td>$([System.Net.WebUtility]::HtmlEncode($check.CheckName))</td><td><span class='status-pill $statusClass'>$([System.Net.WebUtility]::HtmlEncode($check.Status))</span></td><td>$summary</td><td>$details$errorText</td><td>$canEvaluateText</td></tr>"
        }

        if ($rows.Count -eq 0) {
            $rows = @('<tr><td colspan="5">No checks in this section.</td></tr>')
        }

        @"
<section>
    <div class='section-header'>
        <h2>$([System.Net.WebUtility]::HtmlEncode($sectionName))</h2>
    </div>
    <div class='section-body'>
        <table>
            <thead>
                <tr>
                    <th>Check</th>
                    <th>Status</th>
                    <th>Summary</th>
                    <th>Details</th>
                    <th>Evaluated</th>
                </tr>
            </thead>
            <tbody>
                $($rows -join [Environment]::NewLine)
            </tbody>
        </table>
    </div>
</section>
"@
    }

    $notEvaluatedRows = foreach ($check in $ReportModel.NotEvaluatedChecks) {
        "<tr><td>$([System.Net.WebUtility]::HtmlEncode($check.Section))</td><td>$([System.Net.WebUtility]::HtmlEncode($check.CheckName))</td><td>$([System.Net.WebUtility]::HtmlEncode($check.Summary))</td><td>$([System.Net.WebUtility]::HtmlEncode([string]$check.ErrorMessage))</td></tr>"
    }

    if ($notEvaluatedRows.Count -eq 0) {
        $notEvaluatedRows = @('<tr><td colspan="4">All checks were evaluated.</td></tr>')
    }

    $css = Get-EndpointCheckerHtmlCss

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>EndpointChecker Report</title>
    <style>
$css
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>EndpointChecker Report</h1>
            <div class="subtitle">System health and compliance scan results for $([System.Net.WebUtility]::HtmlEncode([string]$ReportModel.Metadata.ComputerName))</div>
            <div class="meta-grid">
                $metaHtml
            </div>
        </header>

        $($sectionBlocks -join [Environment]::NewLine)

        <section>
            <div class='section-header'>
                <h2>Checks Not Evaluated</h2>
            </div>
            <div class='section-body'>
                <table>
                    <thead>
                        <tr>
                            <th>Section</th>
                            <th>Check</th>
                            <th>Reason</th>
                            <th>Error</th>
                        </tr>
                    </thead>
                    <tbody>
                        $($notEvaluatedRows -join [Environment]::NewLine)
                    </tbody>
                </table>
            </div>
        </section>

        <section>
            <div class='section-header'>
                <h2>Summary Score</h2>
            </div>
            <div class='section-body'>
                <div><strong>$($ReportModel.Summary.Passed) of $($ReportModel.Summary.Evaluated) checks passed</strong></div>
                <div class='summary-grid'>
                    <div class='summary-card'>
                        <div class='label'>Passed</div>
                        <div class='value'>$($ReportModel.Summary.Passed)</div>
                    </div>
                    <div class='summary-card'>
                        <div class='label'>Warnings</div>
                        <div class='value'>$($ReportModel.Summary.Warnings)</div>
                    </div>
                    <div class='summary-card'>
                        <div class='label'>Failed</div>
                        <div class='value'>$($ReportModel.Summary.Failed)</div>
                    </div>
                    <div class='summary-card'>
                        <div class='label'>Not Evaluated</div>
                        <div class='value'>$($ReportModel.Summary.NotEvaluated)</div>
                    </div>
                </div>
                <div class='footer-note'>EndpointChecker v1 report generated at $([System.Net.WebUtility]::HtmlEncode([string]$ReportModel.GeneratedAtUtc)).</div>
            </div>
        </section>
    </div>
</body>
</html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    return $OutputPath
}
