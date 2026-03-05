$repoRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $repoRoot -ChildPath 'Scripts/Shared/Get-StatusFromThreshold.ps1')

Describe 'Threshold Logic' {
    It 'returns expected disk status at boundary values (80/81/90/91)' {
        Get-StatusFromThreshold -Value 80 -WarnThreshold 80 -FailThreshold 90 | Should -Be 'PASS'
        Get-StatusFromThreshold -Value 81 -WarnThreshold 80 -FailThreshold 90 | Should -Be 'WARN'
        Get-StatusFromThreshold -Value 90 -WarnThreshold 80 -FailThreshold 90 | Should -Be 'WARN'
        Get-StatusFromThreshold -Value 91 -WarnThreshold 80 -FailThreshold 90 | Should -Be 'FAIL'
    }

    It 'returns expected uptime status for 7 and >7 day values' {
        Get-UptimeStatus -UptimeDays 7 -WarnDays 7 | Should -Be 'PASS'
        Get-UptimeStatus -UptimeDays 7.1 -WarnDays 7 | Should -Be 'WARN'
    }

    It 'returns expected patch age status for 30 and 31 day values' {
        Get-PatchAgeStatus -PatchAgeDays 30 -FailDays 30 | Should -Be 'PASS'
        Get-PatchAgeStatus -PatchAgeDays 31 -FailDays 30 | Should -Be 'FAIL'
    }
}
