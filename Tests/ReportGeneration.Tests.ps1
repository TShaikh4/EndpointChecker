$repoRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $repoRoot -ChildPath 'Scripts/Shared/ConvertTo-ReportModel.ps1')
. (Join-Path -Path $repoRoot -ChildPath 'Templates/HtmlTemplate.ps1')
. (Join-Path -Path $repoRoot -ChildPath 'Scripts/Output/New-HtmlReport.ps1')
. (Join-Path -Path $repoRoot -ChildPath 'Scripts/Output/New-CsvReport.ps1')

Describe 'Report Generation' {
    BeforeEach {
        $script:checks = @(
            (New-CheckResult -CheckId 'S1' -Section 'System Overview' -CheckName 'CPU' -Status 'PASS' -Summary 'CPU OK' -Details 'CPU stable' -CanEvaluate $true),
            (New-CheckResult -CheckId 'S2' -Section 'Security Posture' -CheckName 'Firewall' -Status 'WARN' -Summary 'Firewall partially disabled' -Details 'Private profile disabled' -CanEvaluate $true),
            (New-CheckResult -CheckId 'S3' -Section 'User & Access Control' -CheckName 'Admins' -Status 'FAIL' -Summary 'Unexpected admin found' -Details 'userX in administrators' -CanEvaluate $true),
            (New-CheckResult -CheckId 'S4' -Section 'Patch Compliance' -CheckName 'Patch Age' -Status 'WARN' -Summary 'Pending data unavailable' -Details 'WUA COM unavailable' -CanEvaluate $false)
        )

        $script:report = ConvertTo-ReportModel -Checks $script:checks -Metadata @{ ComputerName = 'LAB-PC'; UserName = 'lab\\user'; IsAdministrator = $false; PowerShellVersion = '5.1'; StartedAtUtc = '2026-01-01T00:00:00Z' }
    }

    It 'creates HTML report containing required section headers and summary score' {
        $htmlPath = Join-Path -Path $TestDrive -ChildPath 'report.html'
        New-HtmlReport -ReportModel $report -OutputPath $htmlPath | Out-Null

        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        $htmlContent = Get-Content -Path $htmlPath -Raw

        $htmlContent | Should -Match 'System Overview'
        $htmlContent | Should -Match 'Security Posture'
        $htmlContent | Should -Match 'User & Access Control'
        $htmlContent | Should -Match 'Patch Compliance'
        $htmlContent | Should -Match 'Summary Score'
        $htmlContent | Should -Match '1 of 3 checks passed'
    }

    It 'creates CSV report only when requested by caller' {
        $htmlPath = Join-Path -Path $TestDrive -ChildPath 'only-html.html'
        $csvPath = Join-Path -Path $TestDrive -ChildPath 'optional.csv'

        New-HtmlReport -ReportModel $report -OutputPath $htmlPath | Out-Null

        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        Test-Path -LiteralPath $csvPath | Should -BeFalse

        New-CsvReport -Checks $checks -OutputPath $csvPath -ComputerName 'LAB-PC' | Out-Null
        Test-Path -LiteralPath $csvPath | Should -BeTrue
    }
}
