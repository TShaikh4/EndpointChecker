function Get-SystemOverview {
    [CmdletBinding()]
    param(
        [int]$DiskWarnPercent = 80,
        [int]$DiskFailPercent = 90,
        [int]$UptimeWarnDays = 7
    )

    $section = 'System Overview'
    $checks = @()

    $checks += Invoke-Check -CheckId 'SYS-CPU-AVG60' -Section $section -CheckName 'CPU Usage (60s Average)' -ScriptBlock {
        $counter = Get-Counter -Counter '\Processor(_Total)\% Processor Time' -SampleInterval 5 -MaxSamples 12 -ErrorAction Stop
        $averageCpu = [Math]::Round((($counter.CounterSamples | Measure-Object -Property CookedValue -Average).Average), 2)

        $status = if ($averageCpu -gt 90) {
            'FAIL'
        }
        elseif ($averageCpu -ge 70) {
            'WARN'
        }
        else {
            'PASS'
        }

        New-CheckResult `
            -CheckId 'SYS-CPU-AVG60' `
            -Section $section `
            -CheckName 'CPU Usage (60s Average)' `
            -Status $status `
            -Summary ("Average CPU utilization over 60 seconds is {0}%" -f $averageCpu) `
            -Details 'Sampled every 5 seconds for 12 samples.' `
            -Evidence @{ AverageCpuPercent = $averageCpu; Samples = 12; SampleIntervalSeconds = 5 } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SYS-RAM-USAGE' -Section $section -CheckName 'RAM Usage' -ScriptBlock {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

        $totalMB = [Math]::Round(([double]$os.TotalVisibleMemorySize / 1024), 2)
        $freeMB = [Math]::Round(([double]$os.FreePhysicalMemory / 1024), 2)
        $usedMB = [Math]::Round(($totalMB - $freeMB), 2)
        $usedPercent = if ($totalMB -gt 0) {
            [Math]::Round(($usedMB / $totalMB) * 100, 2)
        }
        else {
            0
        }

        $status = if ($usedPercent -gt 90) {
            'FAIL'
        }
        elseif ($usedPercent -ge 75) {
            'WARN'
        }
        else {
            'PASS'
        }

        New-CheckResult `
            -CheckId 'SYS-RAM-USAGE' `
            -Section $section `
            -CheckName 'RAM Usage' `
            -Status $status `
            -Summary ("RAM usage is {0}% ({1} MB used of {2} MB total)" -f $usedPercent, $usedMB, $totalMB) `
            -Details ("Free memory: {0} MB" -f $freeMB) `
            -Evidence @{ TotalMB = $totalMB; UsedMB = $usedMB; FreeMB = $freeMB; UsedPercent = $usedPercent } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SYS-DISK-USAGE' -Section $section -CheckName 'Disk Usage per Drive' -ScriptBlock {
        $drives = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)

        if ($drives.Count -eq 0) {
            return New-CheckResult `
                -CheckId 'SYS-DISK-USAGE' `
                -Section $section `
                -CheckName 'Disk Usage per Drive' `
                -Status 'WARN' `
                -Summary 'No fixed drives were detected.' `
                -Details 'Disk usage check could not be evaluated.' `
                -Evidence @{} `
                -CanEvaluate $false
        }

        $driveDetails = @()
        foreach ($drive in $drives) {
            $sizeGB = if ($drive.Size) { [Math]::Round(([double]$drive.Size / 1GB), 2) } else { 0 }
            $freeGB = if ($drive.FreeSpace) { [Math]::Round(([double]$drive.FreeSpace / 1GB), 2) } else { 0 }
            $usedPercent = if ($drive.Size -gt 0) {
                [Math]::Round(((( [double]$drive.Size - [double]$drive.FreeSpace) / [double]$drive.Size) * 100), 2)
            }
            else {
                0
            }

            $driveStatus = Get-StatusFromThreshold -Value $usedPercent -WarnThreshold $DiskWarnPercent -FailThreshold $DiskFailPercent

            $driveDetails += [pscustomobject]@{
                Drive       = $drive.DeviceID
                Label       = $drive.VolumeName
                SizeGB      = $sizeGB
                FreeGB      = $freeGB
                UsedPercent = $usedPercent
                Status      = $driveStatus
            }
        }

        $overallStatus = if (@($driveDetails | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0) {
            'FAIL'
        }
        elseif (@($driveDetails | Where-Object { $_.Status -eq 'WARN' }).Count -gt 0) {
            'WARN'
        }
        else {
            'PASS'
        }

        $detailsText = ($driveDetails | ForEach-Object {
                "{0}: {1}% used ({2} GB free of {3} GB)" -f $_.Drive, $_.UsedPercent, $_.FreeGB, $_.SizeGB
            }) -join '; '

        New-CheckResult `
            -CheckId 'SYS-DISK-USAGE' `
            -Section $section `
            -CheckName 'Disk Usage per Drive' `
            -Status $overallStatus `
            -Summary 'Disk usage evaluated for all fixed drives.' `
            -Details $detailsText `
            -Evidence $driveDetails `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SYS-UPTIME' -Section $section -CheckName 'System Uptime' -ScriptBlock {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

        $lastBoot = $os.LastBootUpTime
        if ($lastBoot -isnot [datetime]) {
            $lastBoot = [Management.ManagementDateTimeConverter]::ToDateTime([string]$lastBoot)
        }

        $uptime = (Get-Date) - $lastBoot
        $uptimeDays = [Math]::Round($uptime.TotalDays, 2)
        $status = Get-UptimeStatus -UptimeDays $uptimeDays -WarnDays $UptimeWarnDays

        New-CheckResult `
            -CheckId 'SYS-UPTIME' `
            -Section $section `
            -CheckName 'System Uptime' `
            -Status $status `
            -Summary ("System uptime is {0} days" -f $uptimeDays) `
            -Details ("Last boot time: {0}" -f $lastBoot.ToString('yyyy-MM-dd HH:mm:ss')) `
            -Evidence @{ LastBootTime = $lastBoot; UptimeDays = $uptimeDays; WarnThresholdDays = $UptimeWarnDays } `
            -CanEvaluate $true
    }

    $checks += Invoke-Check -CheckId 'SYS-OS-BUILD' -Section $section -CheckName 'OS Version and Build' -ScriptBlock {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $registryInfo = $null

        try {
            $registryInfo = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        }
        catch {
            Write-Log -Level 'WARN' -Message "Unable to read detailed OS registry metadata: $($_.Exception.Message)"
        }

        $productName = if ($registryInfo -and $registryInfo.ProductName) { $registryInfo.ProductName } else { $os.Caption }
        $version = if ($registryInfo -and $registryInfo.DisplayVersion) { $registryInfo.DisplayVersion } else { $os.Version }
        $buildNumber = if ($registryInfo -and $registryInfo.CurrentBuild) { $registryInfo.CurrentBuild } else { $os.BuildNumber }
        $ubr = if ($registryInfo -and ($registryInfo.PSObject.Properties.Name -contains 'UBR')) { $registryInfo.UBR } else { $null }

        $summary = if ($ubr -ne $null) {
            "OS: $productName ($version), build $buildNumber.$ubr"
        }
        else {
            "OS: $productName ($version), build $buildNumber"
        }

        New-CheckResult `
            -CheckId 'SYS-OS-BUILD' `
            -Section $section `
            -CheckName 'OS Version and Build' `
            -Status 'PASS' `
            -Summary $summary `
            -Details 'Operating system metadata collected successfully.' `
            -Evidence @{ ProductName = $productName; Version = $version; BuildNumber = $buildNumber; UBR = $ubr } `
            -CanEvaluate $true
    }

    return $checks
}
