<#
.SYNOPSIS

Connects to vCenters specified in a PSCustomObject.


.DESCRIPTION

This command will loop through the specified PS Custom Object and connect to each specified vCenter. It will pass
the credentials that were used to run the command and if the authentication fails, it will prompt the user for
alternate credentials.

To specify your own default values for the -VCenter parameter, edit the CSV file located in the module base directory:

"$((Get-Module SysEng).ModuleBase)\vCenters.csv"


.PARAMETER VCenters

Takes a PSCustomObject that contains an array of vCenters a user wants to connect to. Please note, the PSCustomObject
needs to possess a key called "vCenter". See EXAMPLES for more details.

NOTE: If no argument is passed to the -VCenter parameter, then default values are parsed from a CSV file located under:

"$((Get-Module SysEng).ModuleBase)\vCenters.csv"


.INPUTS

None. You cannot pipe objects to Connect-SysEngToVCenters command.


.OUTPUTS

The command will list the vCenters it is attempting to connect to.


.EXAMPLE

PS> $vCenters_Custom_Ojbect = Import-Csv C:\path\to\csv\file.csv
PS> $vCenters_Custom_Ojbect

vCenter
-------
vcenter01.acme.local
vcenter02.acme.local
vcenter03.acme.local
vcenter04.acme.local
vcenter05.acme.local

PS> Connect-SysEngToVCenters -VCenters $vCenters_Custom_Ojbect

.EXAMPLE

PS> Connect-SysEngToVCenters -VCenters (Import-Csv "C:\path\to\csv\file.csv")
#>

function Connect-SysEngToVCenters {

    param(

        [PSCustomObject]$VCenters = (Import-Csv "$((Get-Module SysEng).ModuleBase)\vCenters.csv")
    )


    Write-Host "NOTE: The script will try and connect to the vCenter(s) using your current credentials." `
                "If it fails, it will prompt you for alternate credentials." -ForegroundColor White -BackgroundColor Black
    Read-Host("Press `"Enter`" to continue or `"CTRL + C`" to quit") | Out-Null

    $VCenters | Select-Object vCenter -Unique | ForEach-Object {

        Write-Host "$((Get-Date).ToString()) | Connecting to $($_.vCenter)"
        Connect-VIServer $_.vCenter | Out-Null
    }
}
