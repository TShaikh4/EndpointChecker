function Initialize-EndpointCheckerLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$VerboseLogging
    )

    $script:EndpointCheckerLogPath = $Path
    $script:EndpointCheckerVerboseLogging = $VerboseLogging.IsPresent

    $parentPath = Split-Path -Path $Path -Parent
    if ($parentPath -and -not (Test-Path -LiteralPath $parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line = "[$timestamp] [$Level] $Message"

    if ($script:EndpointCheckerLogPath) {
        Add-Content -Path $script:EndpointCheckerLogPath -Value $line
    }

    if ($Level -in @('WARN', 'ERROR') -or $script:EndpointCheckerVerboseLogging) {
        Write-Host $line
    }
}
