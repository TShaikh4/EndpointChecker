function Get-StatusFromThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Value,

        [Parameter(Mandatory = $true)]
        [double]$WarnThreshold,

        [Parameter(Mandatory = $true)]
        [double]$FailThreshold,

        [switch]$WarnInclusive,
        [switch]$FailInclusive
    )

    if ($FailInclusive) {
        if ($Value -ge $FailThreshold) {
            return 'FAIL'
        }
    }
    elseif ($Value -gt $FailThreshold) {
        return 'FAIL'
    }

    if ($WarnInclusive) {
        if ($Value -ge $WarnThreshold) {
            return 'WARN'
        }
    }
    elseif ($Value -gt $WarnThreshold) {
        return 'WARN'
    }

    return 'PASS'
}

function Get-UptimeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$UptimeDays,

        [Parameter(Mandatory = $true)]
        [int]$WarnDays
    )

    if ($UptimeDays -gt $WarnDays) {
        return 'WARN'
    }

    return 'PASS'
}

function Get-PatchAgeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$PatchAgeDays,

        [Parameter(Mandatory = $true)]
        [int]$FailDays
    )

    if ($PatchAgeDays -gt $FailDays) {
        return 'FAIL'
    }

    return 'PASS'
}
