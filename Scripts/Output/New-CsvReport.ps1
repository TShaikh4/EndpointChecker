function New-CsvReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Checks,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $rows = foreach ($check in $Checks) {
        [pscustomobject]@{
            TimestampUtc = if ($check.TimestampUtc) { ([datetime]$check.TimestampUtc).ToUniversalTime().ToString('o') } else { '' }
            ComputerName = $ComputerName
            Section      = $check.Section
            CheckId      = $check.CheckId
            CheckName    = $check.CheckName
            Status       = $check.Status
            CanEvaluate  = $check.CanEvaluate
            Summary      = $check.Summary
            Details      = ConvertTo-CompactString -Value $check.Details
        }
    }

    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    return $OutputPath
}
