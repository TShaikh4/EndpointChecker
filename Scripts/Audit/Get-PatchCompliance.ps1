function ConvertTo-PatchDate {
    [CmdletBinding()]
    param(
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [datetime]) {
        return [datetime]$Value
    }

    $parsedDate = $null
    if ([datetime]::TryParse([string]$Value, [ref]$parsedDate)) {
        return $parsedDate
    }

    return $null
}

function Get-InstalledHotFixesWithDates {
    [CmdletBinding()]
    param()

    $rawFixes = @(Get-HotFix -ErrorAction Stop)
    $parsedFixes = foreach ($fix in $rawFixes) {
        $date = ConvertTo-PatchDate -Value $fix.InstalledOn
        if ($date) {
            [pscustomobject]@{
                HotFixId    = $fix.HotFixID
                Description = $fix.Description
                InstalledOn = $date
            }
        }
    }

    return @($parsedFixes | Sort-Object -Property InstalledOn -Descending)
}

function Get-PatchCompliance {
    [CmdletBinding()]
    param(
        [int]$PatchFailDays = 30
    )

    $section = 'Patch Compliance'
    $checks = @()

    $checks += Invoke-Check -CheckId 'PAT-RECENT-UPDATES' -Section $section -CheckName 'Recently Installed Updates' -ScriptBlock {
        $hotFixes = @(Get-InstalledHotFixesWithDates)

        if ($hotFixes.Count -eq 0) {
            return New-CheckResult `
                -CheckId 'PAT-RECENT-UPDATES' `
                -Section $section `
                -CheckName 'Recently Installed Updates' `
                -Status 'WARN' `
                -Summary 'No installed updates with parsable dates were found.' `
                -Details 'Get-HotFix returned no date-usable records.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $recent = @($hotFixes | Select-Object -First 10)
        $mostRecent = $recent | Select-Object -First 1

        $details = ($recent | ForEach-Object {
                "{0} ({1})" -f $_.HotFixId, $_.InstalledOn.ToString('yyyy-MM-dd')
            }) -join '; '

        New-CheckResult `
            -CheckId 'PAT-RECENT-UPDATES' `
            -Section $section `
            -CheckName 'Recently Installed Updates' `
            -Status 'PASS' `
            -Summary ("Found {0} installed updates with dates. Most recent: {1} on {2}" -f $hotFixes.Count, $mostRecent.HotFixId, $mostRecent.InstalledOn.ToString('yyyy-MM-dd')) `
            -Details $details `
            -Evidence @{ RecentUpdates = $recent; TotalParsedUpdates = $hotFixes.Count } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'PAT-UPDATE-AGE' -Section $section -CheckName 'No Updates Installed in 30+ Days' -ScriptBlock {
        $hotFixes = @(Get-InstalledHotFixesWithDates)

        if ($hotFixes.Count -eq 0) {
            return New-CheckResult `
                -CheckId 'PAT-UPDATE-AGE' `
                -Section $section `
                -CheckName 'No Updates Installed in 30+ Days' `
                -Status 'WARN' `
                -Summary 'Unable to determine update recency.' `
                -Details 'No installed update with a parsable date was found.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $latest = $hotFixes | Select-Object -First 1
        $ageDays = [Math]::Floor(((Get-Date) - $latest.InstalledOn).TotalDays)
        $status = Get-PatchAgeStatus -PatchAgeDays $ageDays -FailDays $PatchFailDays

        $summary = if ($status -eq 'FAIL') {
            "Latest update is $ageDays days old (threshold: $PatchFailDays days)."
        }
        else {
            "Latest update is $ageDays days old."
        }

        New-CheckResult `
            -CheckId 'PAT-UPDATE-AGE' `
            -Section $section `
            -CheckName 'No Updates Installed in 30+ Days' `
            -Status $status `
            -Summary $summary `
            -Details ("Latest update: $($latest.HotFixId) installed on $($latest.InstalledOn.ToString('yyyy-MM-dd')).") `
            -Evidence @{ LatestUpdate = $latest; PatchAgeDays = $ageDays; ThresholdDays = $PatchFailDays } `
            -CanEvaluate $true
    }

    return $checks
}
