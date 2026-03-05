function Invoke-Check {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckId,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$CheckName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [ValidateSet('WARN', 'FAIL')]
        [string]$OnErrorStatus = 'WARN'
    )

    try {
        $result = & $ScriptBlock

        if ($null -eq $result) {
            throw "Check '$CheckId' returned no result."
        }

        if (-not $result.PSObject.Properties.Match('CheckId').Count) {
            $result | Add-Member -NotePropertyName CheckId -NotePropertyValue $CheckId
        }

        if (-not $result.PSObject.Properties.Match('Section').Count) {
            $result | Add-Member -NotePropertyName Section -NotePropertyValue $Section
        }

        if (-not $result.PSObject.Properties.Match('CheckName').Count) {
            $result | Add-Member -NotePropertyName CheckName -NotePropertyValue $CheckName
        }

        if (-not $result.PSObject.Properties.Match('TimestampUtc').Count) {
            $result | Add-Member -NotePropertyName TimestampUtc -NotePropertyValue (Get-Date).ToUniversalTime()
        }

        return $result
    }
    catch {
        $message = "Check '$CheckId' failed: $($_.Exception.Message)"
        Write-Log -Level 'ERROR' -Message $message

        return New-CheckResult `
            -CheckId $CheckId `
            -Section $Section `
            -CheckName $CheckName `
            -Status $OnErrorStatus `
            -Summary 'Unable to evaluate this check due to runtime error.' `
            -Details $_.Exception.Message `
            -Evidence $null `
            -CanEvaluate $false `
            -ErrorMessage $_.Exception.Message
    }
}
