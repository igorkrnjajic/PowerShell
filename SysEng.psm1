<#
Unfortunately, this file is required the import the VMware.PowerCLI module because importing it via
PSD file is not possible due to a known PowerShell bug tracked under:

https://github.com/PowerShell/PowerShell/issues/2607

As you'll see, this bug has been addressed under #3594 and will be resolved in PowerShell v6.0.0-beta.
#>

Import-Module VMware.PowerCLI