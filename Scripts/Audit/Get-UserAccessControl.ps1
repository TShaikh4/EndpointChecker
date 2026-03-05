function ConvertTo-NormalizedPrincipalName {
    [CmdletBinding()]
    param(
        [string]$Identity
    )

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return ''
    }

    $value = $Identity.Trim()

    if ($value.Contains('\\')) {
        $value = $value.Split('\\')[-1]
    }

    return $value.ToLowerInvariant()
}

function ConvertTo-EndpointCheckerWmiDate {
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

    try {
        return [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)
    }
    catch {
        $parsed = $null
        if ([datetime]::TryParse([string]$Value, [ref]$parsed)) {
            return $parsed
        }
    }

    return $null
}

function Get-EndpointCheckerLocalUsers {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-LocalUser -ErrorAction SilentlyContinue) {
        try {
            return @(Get-LocalUser -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        Name      = $_.Name
                        Enabled   = [bool]$_.Enabled
                        LastLogon = ConvertTo-EndpointCheckerWmiDate -Value $_.LastLogon
                    }
                })
        }
        catch {
            Write-Log -Level 'WARN' -Message "Get-LocalUser failed: $($_.Exception.Message)"
        }
    }

    $wmiUsers = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop)
    return @($wmiUsers | ForEach-Object {
            [pscustomobject]@{
                Name      = $_.Name
                Enabled   = -not [bool]$_.Disabled
                LastLogon = $null
            }
        })
}

function Get-EndpointCheckerLastLogonMap {
    [CmdletBinding()]
    param()

    $map = @{}

    try {
        $profiles = @(Get-CimInstance -ClassName Win32_NetworkLoginProfile -Filter 'LocalAccount=True' -ErrorAction Stop)
        foreach ($profile in $profiles) {
            $name = [string]$profile.Name
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $lastLogon = ConvertTo-EndpointCheckerWmiDate -Value $profile.LastLogon
            if ($null -eq $lastLogon) {
                continue
            }

            if (-not $map.ContainsKey($name) -or $lastLogon -gt $map[$name]) {
                $map[$name] = $lastLogon
            }
        }
    }
    catch {
        Write-Log -Level 'WARN' -Message "Unable to query Win32_NetworkLoginProfile: $($_.Exception.Message)"
    }

    return $map
}

function Resolve-EndpointCheckerLocalUserLogons {
    [CmdletBinding()]
    param()

    $users = @(Get-EndpointCheckerLocalUsers)
    $lastLogonMap = Get-EndpointCheckerLastLogonMap

    $resolved = foreach ($user in $users) {
        $lastLogon = $null
        $source = $null

        if ($user.LastLogon) {
            $lastLogon = ConvertTo-EndpointCheckerWmiDate -Value $user.LastLogon
            $source = 'LocalUser'
        }

        if ($null -eq $lastLogon -and $lastLogonMap.ContainsKey($user.Name)) {
            $lastLogon = $lastLogonMap[$user.Name]
            $source = 'NetworkLoginProfile'
        }

        [pscustomobject]@{
            Name      = $user.Name
            Enabled   = [bool]$user.Enabled
            LastLogon = $lastLogon
            Source    = $source
        }
    }

    return @($resolved)
}

function Get-EndpointCheckerAdministratorsMembers {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        try {
            $localMembers = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop)
            return @($localMembers | ForEach-Object {
                    $memberName = if ($_.Name) { [string]$_.Name } else { [string]$_.SID }
                    [pscustomobject]@{
                        Name         = $memberName
                        Source       = 'Get-LocalGroupMember'
                        IsUnresolved = ($memberName -match '^S-\d-\d+')
                    }
                })
        }
        catch {
            Write-Log -Level 'WARN' -Message "Get-LocalGroupMember failed: $($_.Exception.Message)"
        }
    }

    try {
        $group = [ADSI]("WinNT://{0}/Administrators,group" -f $env:COMPUTERNAME)
        $members = @($group.psbase.Invoke('Members'))
        if ($members.Count -gt 0) {
            return @($members | ForEach-Object {
                    $name = $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
                    [pscustomobject]@{
                        Name         = [string]$name
                        Source       = 'ADSI'
                        IsUnresolved = ([string]$name -match '^S-\d-\d+')
                    }
                })
        }
    }
    catch {
        Write-Log -Level 'WARN' -Message "ADSI Administrators group query failed: $($_.Exception.Message)"
    }

    $netOutput = @(net localgroup Administrators 2>&1)
    $parsedMembers = @()
    $capture = $false

    foreach ($line in $netOutput) {
        if ($line -match '^-{3,}') {
            $capture = $true
            continue
        }

        if (-not $capture) {
            continue
        }

        if ($line -match '(?i)^The command completed successfully') {
            break
        }

        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $memberName = $line.Trim()
            $parsedMembers += [pscustomobject]@{
                Name         = $memberName
                Source       = 'net localgroup'
                IsUnresolved = ($memberName -match '^S-\d-\d+' -or $memberName -match '^\*S-\d-\d+')
            }
        }
    }

    return $parsedMembers
}

function Get-UserAccessControl {
    [CmdletBinding()]
    param(
        [string[]]$ExpectedAdmins = @(),
        [int]$InactiveDays = 90
    )

    $section = 'User & Access Control'
    $checks = @()

    $checks += Invoke-Check -CheckId 'USR-LOCAL-ADMINS' -Section $section -CheckName 'Local Administrator Accounts' -ScriptBlock {
        $members = @(Get-EndpointCheckerAdministratorsMembers)

        if ($members.Count -eq 0) {
            return New-CheckResult `
                -CheckId 'USR-LOCAL-ADMINS' `
                -Section $section `
                -CheckName 'Local Administrator Accounts' `
                -Status 'WARN' `
                -Summary 'Unable to enumerate local Administrators group members.' `
                -Details 'No members were returned from available enumeration methods.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $builtInExpected = @(
            'administrator',
            'administrators',
            'domain admins',
            'enterprise admins',
            'system'
        )

        $expectedNormalized = @($builtInExpected + ($ExpectedAdmins | ForEach-Object { ConvertTo-NormalizedPrincipalName -Identity $_ })) | Sort-Object -Unique

        $unexpected = @()
        $unresolved = @()

        foreach ($member in $members) {
            $normalized = ConvertTo-NormalizedPrincipalName -Identity $member.Name

            if ($member.IsUnresolved) {
                $unresolved += $member.Name
                continue
            }

            if ([string]::IsNullOrWhiteSpace($normalized)) {
                continue
            }

            if ($expectedNormalized -notcontains $normalized) {
                $unexpected += $member.Name
            }
        }

        $status = if ($unexpected.Count -gt 0) {
            'FAIL'
        }
        elseif ($unresolved.Count -gt 0) {
            'WARN'
        }
        else {
            'PASS'
        }

        $summary = if ($unexpected.Count -gt 0) {
            "Unexpected local administrators detected: $($unexpected -join ', ')"
        }
        elseif ($unresolved.Count -gt 0) {
            "Some administrator members are unresolved: $($unresolved -join ', ')"
        }
        else {
            'No unexpected local administrators detected.'
        }

        $details = "Members: $((@($members.Name) -join ', '))"

        New-CheckResult `
            -CheckId 'USR-LOCAL-ADMINS' `
            -Section $section `
            -CheckName 'Local Administrator Accounts' `
            -Status $status `
            -Summary $summary `
            -Details $details `
            -Evidence @{ Members = $members; Unexpected = $unexpected; Unresolved = $unresolved; ExpectedNormalized = $expectedNormalized } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'USR-INACTIVE-ACCOUNTS' -Section $section -CheckName 'Inactive Local Accounts' -ScriptBlock {
        $users = @(Resolve-EndpointCheckerLocalUserLogons)

        if ($users.Count -eq 0) {
            return New-CheckResult `
                -CheckId 'USR-INACTIVE-ACCOUNTS' `
                -Section $section `
                -CheckName 'Inactive Local Accounts' `
                -Status 'WARN' `
                -Summary 'No local users were returned for inactivity analysis.' `
                -Details 'Local user enumeration returned zero rows.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $thresholdDate = (Get-Date).AddDays(-1 * $InactiveDays)
        $enabledUsers = @($users | Where-Object { $_.Enabled })

        $inactiveUsers = @($enabledUsers | Where-Object { $_.LastLogon -and $_.LastLogon -lt $thresholdDate })
        $unknownUsers = @($enabledUsers | Where-Object { -not $_.LastLogon })

        $status = if ($inactiveUsers.Count -gt 0) {
            'FAIL'
        }
        elseif ($unknownUsers.Count -gt 0) {
            'WARN'
        }
        else {
            'PASS'
        }

        $summary = if ($inactiveUsers.Count -gt 0) {
            "Inactive enabled local accounts found: $($inactiveUsers.Name -join ', ')"
        }
        elseif ($unknownUsers.Count -gt 0) {
            "Some enabled local accounts have no last-login data: $($unknownUsers.Name -join ', ')"
        }
        else {
            "No enabled local accounts inactive for more than $InactiveDays days."
        }

        $details = "Threshold date: $($thresholdDate.ToString('yyyy-MM-dd')); Enabled users evaluated: $($enabledUsers.Count)"

        New-CheckResult `
            -CheckId 'USR-INACTIVE-ACCOUNTS' `
            -Section $section `
            -CheckName 'Inactive Local Accounts' `
            -Status $status `
            -Summary $summary `
            -Details $details `
            -Evidence @{ InactiveUsers = $inactiveUsers; UnknownLastLogonUsers = $unknownUsers; ThresholdDate = $thresholdDate } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'USR-LAST-LOGIN' -Section $section -CheckName 'Last Login Timestamp per User' -ScriptBlock {
        $users = @(Resolve-EndpointCheckerLocalUserLogons)

        if ($users.Count -eq 0) {
            return New-CheckResult `
                -CheckId 'USR-LAST-LOGIN' `
                -Section $section `
                -CheckName 'Last Login Timestamp per User' `
                -Status 'WARN' `
                -Summary 'Unable to gather local user last-login records.' `
                -Details 'No local user records were returned.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $knownUsers = @($users | Where-Object { $_.LastLogon })
        $coveragePercent = [Math]::Round((($knownUsers.Count / $users.Count) * 100), 2)

        $status = if ($coveragePercent -ge 70) {
            'PASS'
        }
        else {
            'WARN'
        }

        $summary = "Last-login coverage is $coveragePercent% ($($knownUsers.Count) of $($users.Count) users)."

        $details = ($users | Sort-Object -Property Name | ForEach-Object {
                $stamp = if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Unknown' }
                "$($_.Name): $stamp"
            }) -join '; '

        New-CheckResult `
            -CheckId 'USR-LAST-LOGIN' `
            -Section $section `
            -CheckName 'Last Login Timestamp per User' `
            -Status $status `
            -Summary $summary `
            -Details $details `
            -Evidence @{ Users = $users; CoveragePercent = $coveragePercent } `
            -CanEvaluate $true
    }

    return $checks
}
