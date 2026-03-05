$repoRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $repoRoot -ChildPath 'Scripts/Shared/ConvertTo-ReportModel.ps1')
. (Join-Path -Path $repoRoot -ChildPath 'Scripts/Output/New-CsvReport.ps1')

Describe 'EndpointChecker Data Model and Scoring' {
    It 'excludes non-evaluable checks from the score denominator' {
        $checks = @(
            (New-CheckResult -CheckId 'C1' -Section 'System Overview' -CheckName 'Check 1' -Status 'PASS' -Summary 'ok' -CanEvaluate $true),
            (New-CheckResult -CheckId 'C2' -Section 'Security Posture' -CheckName 'Check 2' -Status 'WARN' -Summary 'limited' -CanEvaluate $false),
            (New-CheckResult -CheckId 'C3' -Section 'Patch Compliance' -CheckName 'Check 3' -Status 'FAIL' -Summary 'bad' -CanEvaluate $true)
        )

        $report = ConvertTo-ReportModel -Checks $checks -Metadata @{ ComputerName = 'TESTPC'; UserName = 'tester'; IsAdministrator = $false; PowerShellVersion = '5.1'; StartedAtUtc = '2026-01-01T00:00:00Z' }

        $report.Summary.Evaluated | Should -Be 2
        $report.Summary.Passed | Should -Be 1
        $report.Summary.Failed | Should -Be 1
        $report.Summary.NotEvaluated | Should -Be 1
    }

    It 'writes CSV rows with normalized UTC timestamps' {
        $check = New-CheckResult -CheckId 'CSV-1' -Section 'System Overview' -CheckName 'CSV Check' -Status 'PASS' -Summary 'ok' -CanEvaluate $true
        $check.TimestampUtc = [datetime]'2026-01-02T03:04:05Z'

        $csvPath = Join-Path -Path $TestDrive -ChildPath 'endpointchecker.csv'
        New-CsvReport -Checks @($check) -OutputPath $csvPath -ComputerName 'TESTPC' | Out-Null

        Test-Path -LiteralPath $csvPath | Should -BeTrue

        $rows = Import-Csv -Path $csvPath
        $rows.Count | Should -Be 1
        $rows[0].TimestampUtc | Should -Match '2026-01-02T03:04:05\.0000000Z'
        $rows[0].ComputerName | Should -Be 'TESTPC'
    }
}

Describe 'EndpointChecker Smoke Test' {
    $entryScript = Join-Path -Path $repoRoot -ChildPath 'EndpointChecker.ps1'
    $isWindows = $env:OS -eq 'Windows_NT'
    $runSmoke = $env:ENDPOINTCHECKER_RUN_SMOKE -eq '1'

    It 'runs end-to-end and creates a non-empty HTML report' -Skip:(-not ($isWindows -and $runSmoke)) {
        $outputDir = Join-Path -Path $TestDrive -ChildPath 'Artifacts'
        & $entryScript -OutputDir $outputDir -Format 'HTML' -VerboseLogging

        $htmlFiles = @(Get-ChildItem -Path $outputDir -Filter 'EndpointChecker_*.html')
        $htmlFiles.Count | Should -BeGreaterThan 0
        $htmlFiles[0].Length | Should -BeGreaterThan 0
    }
}
