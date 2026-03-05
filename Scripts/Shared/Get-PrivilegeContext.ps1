function Get-PrivilegeContext {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        return [pscustomobject]@{
            UserName           = $identity.Name
            IsAdministrator    = [bool]$isAdministrator
            AuthenticationType = $identity.AuthenticationType
            IsSystem           = [bool]$identity.IsSystem
            ErrorMessage       = $null
        }
    }
    catch {
        return [pscustomobject]@{
            UserName           = $env:USERNAME
            IsAdministrator    = $false
            AuthenticationType = $null
            IsSystem           = $false
            ErrorMessage       = $_.Exception.Message
        }
    }
}
