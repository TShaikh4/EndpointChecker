function ConvertTo-CompactString {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [string]) {
        return $Value
    }

    try {
        return ($Value | ConvertTo-Json -Depth 6 -Compress)
    }
    catch {
        return [string]$Value
    }
}

function New-CheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckId,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$CheckName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Summary,

        [string]$Details = '',

        $Evidence = $null,

        [bool]$CanEvaluate = $true,

        [string]$ErrorMessage = $null
    )

    return [pscustomobject]@{
        CheckId      = $CheckId
        Section      = $Section
        CheckName    = $CheckName
        Status       = $Status
        Summary      = $Summary
        Details      = $Details
        Evidence     = $Evidence
        CanEvaluate  = $CanEvaluate
        ErrorMessage = $ErrorMessage
        TimestampUtc = (Get-Date).ToUniversalTime()
    }
}

function Get-SummaryScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Checks
    )

    $evaluatedChecks = @($Checks | Where-Object { $_.CanEvaluate })
    $passedChecks = @($evaluatedChecks | Where-Object { $_.Status -eq 'PASS' })
    $warnChecks = @($evaluatedChecks | Where-Object { $_.Status -eq 'WARN' })
    $failedChecks = @($evaluatedChecks | Where-Object { $_.Status -eq 'FAIL' })
    $notEvaluatedChecks = @($Checks | Where-Object { -not $_.CanEvaluate })

    return [pscustomobject]@{
        Passed       = $passedChecks.Count
        Evaluated    = $evaluatedChecks.Count
        Warnings     = $warnChecks.Count
        Failed       = $failedChecks.Count
        NotEvaluated = $notEvaluatedChecks.Count
    }
}

function ConvertTo-ReportModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Checks,

        [Parameter(Mandatory = $true)]
        [hashtable]$Metadata
    )

    $sectionOrder = @(
        'System Overview',
        'Security Posture',
        'User & Access Control',
        'Patch Compliance'
    )

    $score = Get-SummaryScore -Checks $Checks

    $sections = foreach ($sectionName in $sectionOrder) {
        $sectionChecks = @($Checks | Where-Object { $_.Section -eq $sectionName })

        [pscustomobject]@{
            Name         = $sectionName
            Checks       = $sectionChecks
            Passed       = @($sectionChecks | Where-Object { $_.Status -eq 'PASS' -and $_.CanEvaluate }).Count
            Evaluated    = @($sectionChecks | Where-Object { $_.CanEvaluate }).Count
            Warnings     = @($sectionChecks | Where-Object { $_.Status -eq 'WARN' -and $_.CanEvaluate }).Count
            Failed       = @($sectionChecks | Where-Object { $_.Status -eq 'FAIL' -and $_.CanEvaluate }).Count
            NotEvaluated = @($sectionChecks | Where-Object { -not $_.CanEvaluate }).Count
        }
    }

    return [pscustomobject]@{
        GeneratedAtUtc     = (Get-Date).ToUniversalTime()
        Metadata           = [pscustomobject]$Metadata
        Checks             = $Checks
        Sections           = $sections
        SectionOrder       = $sectionOrder
        Summary            = $score
        NotEvaluatedChecks = @($Checks | Where-Object { -not $_.CanEvaluate })
    }
}
