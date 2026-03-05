function ConvertTo-EndpointCheckerDate {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
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

function Get-NetAccountsNumericValue {
    [CmdletBinding()]
    param(
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    if ($Line -match '(?i)never') {
        return 0
    }

    $match = [regex]::Match($Line, '\d+')
    if ($match.Success) {
        return [int]$match.Value
    }

    return $null
}

function Get-SecurityPosture {
    [CmdletBinding()]
    param(
        [int]$PatchFailDays = 30
    )

    $section = 'Security Posture'
    $checks = @()

    $checks += Invoke-Check -CheckId 'SEC-FIREWALL' -Section $section -CheckName 'Windows Firewall Profiles' -ScriptBlock {
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop)
        $expectedProfiles = @('Domain', 'Private', 'Public')

        $disabledProfiles = @()
        $missingProfiles = @()

        foreach ($profileName in $expectedProfiles) {
            $profile = $profiles | Where-Object { $_.Name -eq $profileName } | Select-Object -First 1
            if ($null -eq $profile) {
                $missingProfiles += $profileName
                continue
            }

            if (-not $profile.Enabled) {
                $disabledProfiles += $profileName
            }
        }

        $problemCount = $disabledProfiles.Count + $missingProfiles.Count
        $status = if ($problemCount -eq 0) {
            'PASS'
        }
        elseif ($problemCount -eq 1) {
            'WARN'
        }
        else {
            'FAIL'
        }

        $summary = if ($problemCount -eq 0) {
            'All firewall profiles are enabled.'
        }
        elseif ($missingProfiles.Count -gt 0) {
            "Firewall profile issues detected. Disabled: $($disabledProfiles -join ', '); Missing: $($missingProfiles -join ', ')."
        }
        else {
            "Firewall profile issues detected. Disabled: $($disabledProfiles -join ', ')."
        }

        New-CheckResult `
            -CheckId 'SEC-FIREWALL' `
            -Section $section `
            -CheckName 'Windows Firewall Profiles' `
            -Status $status `
            -Summary $summary `
            -Details 'Domain, Private, and Public firewall profiles were evaluated.' `
            -Evidence @{ DisabledProfiles = $disabledProfiles; MissingProfiles = $missingProfiles } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SEC-WINDOWS-UPDATES' -Section $section -CheckName 'Last Windows Update and Pending Count' -ScriptBlock {
        $rawHotFixes = @(Get-HotFix -ErrorAction Stop)
        $hotFixes = foreach ($fix in $rawHotFixes) {
            $installedOn = ConvertTo-EndpointCheckerDate -Value $fix.InstalledOn
            if ($installedOn) {
                [pscustomobject]@{
                    HotFixId    = $fix.HotFixID
                    InstalledOn = $installedOn
                }
            }
        }

        $sortedHotFixes = @($hotFixes | Sort-Object -Property InstalledOn -Descending)
        $latestHotFix = $sortedHotFixes | Select-Object -First 1

        if ($null -eq $latestHotFix) {
            return New-CheckResult `
                -CheckId 'SEC-WINDOWS-UPDATES' `
                -Section $section `
                -CheckName 'Last Windows Update and Pending Count' `
                -Status 'WARN' `
                -Summary 'Unable to determine last installed Windows update.' `
                -Details 'Get-HotFix did not provide parsable install dates.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $pendingCount = $null
        $pendingError = $null
        try {
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            $pendingCount = $searchResult.Updates.Count
        }
        catch {
            $pendingError = $_.Exception.Message
        }

        $patchAgeDays = [Math]::Floor(((Get-Date) - $latestHotFix.InstalledOn).TotalDays)

        $status = 'PASS'
        $canEvaluate = $true
        if ($patchAgeDays -gt $PatchFailDays) {
            $status = 'FAIL'
        }
        elseif ($pendingCount -gt 5) {
            $status = 'WARN'
        }

        if ($pendingError) {
            $status = 'WARN'
            $canEvaluate = $false
        }

        $summary = "Latest installed update $($latestHotFix.HotFixId) is $patchAgeDays days old"
        if ($pendingCount -ne $null) {
            $summary = "$summary; pending updates: $pendingCount"
        }
        else {
            $summary = "$summary; pending updates unavailable"
        }

        $details = if ($pendingError) {
            "Pending update check unavailable: $pendingError"
        }
        else {
            'Latest patch date and pending software update count were collected.'
        }

        New-CheckResult `
            -CheckId 'SEC-WINDOWS-UPDATES' `
            -Section $section `
            -CheckName 'Last Windows Update and Pending Count' `
            -Status $status `
            -Summary $summary `
            -Details $details `
            -Evidence @{ LatestHotFixId = $latestHotFix.HotFixId; LatestInstalledOn = $latestHotFix.InstalledOn; PatchAgeDays = $patchAgeDays; PendingUpdates = $pendingCount; PendingError = $pendingError } `
            -CanEvaluate $canEvaluate
    }

    $checks += Invoke-Check -CheckId 'SEC-GUEST-ACCOUNT' -Section $section -CheckName 'Guest Account Status' -ScriptBlock {
        $guestEnabled = $null
        $source = $null

        if (Get-Command -Name Get-LocalUser -ErrorAction SilentlyContinue) {
            try {
                $guest = Get-LocalUser -Name 'Guest' -ErrorAction Stop
                $guestEnabled = [bool]$guest.Enabled
                $source = 'Get-LocalUser'
            }
            catch {
                Write-Log -Level 'WARN' -Message "Get-LocalUser Guest query failed: $($_.Exception.Message)"
            }
        }

        if ($null -eq $guestEnabled) {
            try {
                $guestAdsi = [ADSI]("WinNT://{0}/Guest,user" -f $env:COMPUTERNAME)
                $flags = [int]$guestAdsi.UserFlags.Value
                $guestEnabled = (($flags -band 0x2) -eq 0)
                $source = 'ADSI'
            }
            catch {
                Write-Log -Level 'WARN' -Message "ADSI Guest query failed: $($_.Exception.Message)"
            }
        }

        if ($null -eq $guestEnabled) {
            return New-CheckResult `
                -CheckId 'SEC-GUEST-ACCOUNT' `
                -Section $section `
                -CheckName 'Guest Account Status' `
                -Status 'WARN' `
                -Summary 'Unable to determine Guest account status.' `
                -Details 'Guest account could not be queried using available methods.' `
                -Evidence @{ Source = $source } `
                -CanEvaluate $false
        }

        $status = if ($guestEnabled) { 'FAIL' } else { 'PASS' }
        $summary = if ($guestEnabled) { 'Guest account is enabled.' } else { 'Guest account is disabled.' }

        New-CheckResult `
            -CheckId 'SEC-GUEST-ACCOUNT' `
            -Section $section `
            -CheckName 'Guest Account Status' `
            -Status $status `
            -Summary $summary `
            -Details ("Detection method: $source") `
            -Evidence @{ GuestEnabled = $guestEnabled; Source = $source } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SEC-LOCKOUT-POLICY' -Section $section -CheckName 'Account Lockout Policy' -ScriptBlock {
        $netAccountsOutput = @(net accounts 2>&1)

        $thresholdLine = $netAccountsOutput | Where-Object { $_ -match '(?i)lockout threshold' } | Select-Object -First 1
        $durationLine = $netAccountsOutput | Where-Object { $_ -match '(?i)lockout duration' } | Select-Object -First 1
        $windowLine = $netAccountsOutput | Where-Object { $_ -match '(?i)lockout observation window' } | Select-Object -First 1

        $threshold = Get-NetAccountsNumericValue -Line $thresholdLine
        $duration = Get-NetAccountsNumericValue -Line $durationLine
        $window = Get-NetAccountsNumericValue -Line $windowLine

        if ($null -eq $threshold) {
            return New-CheckResult `
                -CheckId 'SEC-LOCKOUT-POLICY' `
                -Section $section `
                -CheckName 'Account Lockout Policy' `
                -Status 'WARN' `
                -Summary 'Unable to parse account lockout policy.' `
                -Details 'net accounts output did not contain parsable lockout threshold.' `
                -Evidence @{ RawOutput = $netAccountsOutput } `
                -CanEvaluate $false
        }

        $status = 'PASS'
        if ($threshold -le 0) {
            $status = 'FAIL'
        }
        elseif ($duration -le 0) {
            $status = 'FAIL'
        }
        elseif ($threshold -gt 10) {
            $status = 'WARN'
        }

        $summary = "Lockout threshold: $threshold, duration: $duration, observation window: $window"

        New-CheckResult `
            -CheckId 'SEC-LOCKOUT-POLICY' `
            -Section $section `
            -CheckName 'Account Lockout Policy' `
            -Status $status `
            -Summary $summary `
            -Details 'Policy values were parsed from net accounts.' `
            -Evidence @{ Threshold = $threshold; DurationMinutes = $duration; ObservationWindowMinutes = $window } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SEC-PASSWORD-COMPLEXITY' -Section $section -CheckName 'Password Complexity Policy' -ScriptBlock {
        $tempDirectory = [System.IO.Path]::GetTempPath()
        if ([string]::IsNullOrWhiteSpace($tempDirectory)) {
            $tempDirectory = '.'
        }

        $tempFile = Join-Path -Path $tempDirectory -ChildPath ("endpointchecker_secpol_{0}.inf" -f ([guid]::NewGuid().ToString('N')))

        try {
            & secedit /export /cfg $tempFile /quiet | Out-Null

            if (-not (Test-Path -LiteralPath $tempFile)) {
                throw 'Security policy export file was not created.'
            }

            $policyLine = Get-Content -Path $tempFile -ErrorAction Stop | Where-Object { $_ -match '^\s*PasswordComplexity\s*=\s*\d+\s*$' } | Select-Object -First 1
            if (-not $policyLine) {
                return New-CheckResult `
                    -CheckId 'SEC-PASSWORD-COMPLEXITY' `
                    -Section $section `
                    -CheckName 'Password Complexity Policy' `
                    -Status 'WARN' `
                    -Summary 'Unable to parse PasswordComplexity policy value.' `
                    -Details 'Security policy export did not include PasswordComplexity.' `
                    -Evidence @{} `
                    -CanEvaluate $false
            }

            $value = [int]([regex]::Match($policyLine, '\d+').Value)
            $status = if ($value -eq 1) { 'PASS' } else { 'FAIL' }
            $summary = if ($value -eq 1) { 'Password complexity policy is enabled.' } else { 'Password complexity policy is disabled.' }

            return New-CheckResult `
                -CheckId 'SEC-PASSWORD-COMPLEXITY' `
                -Section $section `
                -CheckName 'Password Complexity Policy' `
                -Status $status `
                -Summary $summary `
                -Details 'PasswordComplexity value extracted from exported local security policy.' `
                -Evidence @{ PasswordComplexity = $value } `
                -CanEvaluate $true
        }
        finally {
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $checks += Invoke-Check -CheckId 'SEC-AUTO-LOGIN' -Section $section -CheckName 'Auto-Login Registry Setting' -ScriptBlock {
        $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

        try {
            $autoAdminValue = (Get-ItemProperty -Path $registryPath -Name 'AutoAdminLogon' -ErrorAction Stop).AutoAdminLogon
            $defaultUser = $null
            try {
                $defaultUser = (Get-ItemProperty -Path $registryPath -Name 'DefaultUserName' -ErrorAction Stop).DefaultUserName
            }
            catch {
                $defaultUser = $null
            }
        }
        catch {
            return New-CheckResult `
                -CheckId 'SEC-AUTO-LOGIN' `
                -Section $section `
                -CheckName 'Auto-Login Registry Setting' `
                -Status 'WARN' `
                -Summary 'Unable to read AutoAdminLogon registry value.' `
                -Details $_.Exception.Message `
                -Evidence @{ RegistryPath = $registryPath } `
                -CanEvaluate $false `
                -ErrorMessage $_.Exception.Message
        }

        $autoLoginEnabled = ([string]$autoAdminValue -eq '1')
        $status = if ($autoLoginEnabled) { 'FAIL' } else { 'PASS' }
        $summary = if ($autoLoginEnabled) { 'Auto-login is enabled in Winlogon settings.' } else { 'Auto-login is disabled.' }

        New-CheckResult `
            -CheckId 'SEC-AUTO-LOGIN' `
            -Section $section `
            -CheckName 'Auto-Login Registry Setting' `
            -Status $status `
            -Summary $summary `
            -Details 'AutoAdminLogon registry value was evaluated.' `
            -Evidence @{ AutoAdminLogon = [string]$autoAdminValue; DefaultUserName = $defaultUser } `
            -CanEvaluate $true
    }

    return $checks
}
