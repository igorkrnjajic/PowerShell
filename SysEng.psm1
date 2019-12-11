<#
Unfortunately, this file is required the import the VMware.PowerCLI module because importing it via
PSD file is not possible due to a known PowerShell bug tracked under:

https://github.com/PowerShell/PowerShell/issues/2607

As you'll see, this bug has been addressed under #3594 and will be resolved in PowerShell v6.0.0-beta.
#>

if(!(Get-Module VMware.PowerCLI)) {

    Write-Warning -Message "Due to a PowerShell v5.1 bug, the SysEng module cannot import the required VMware.PowerCLI $(
    )module automatically. This module relies heavily on the VMware.PowerCLI module and it needs to be imported before $(
    )any SysEng commands are executed. Please refer to the URL below for more details on the bug:

    https://github.com/PowerShell/PowerShell/issues/2607"
}