﻿<#
.SYNOPSIS

Connects to vCenters specified in a CSV file.


.DESCRIPTION

This command will loop through the specified PS Custom Object and connect to each specified vCenter. It will pass the credentials that were used to run the command and if the authentication fails, it will prompt the user for alternate credentials.


.PARAMETER VCenters

Takes a PS Custom Object that contains an array of vCenters a user wants to connect to.


.INPUTS

None. You cannot pipe objects to Connect-SysEngToVCenters command.


.OUTPUTS

The command will list the vCenters it is attempting to connect to.


.EXAMPLE

PS> Connect-SysEngToVCenters -VCenters $vCenters_Custom_Ojbect

.EXAMPLE

PS> Connect-SysEngToVCenters -VCenters (Import-Csv "C:\path\to\csv\file.csv")
#>

function Connect-SysEngToVCenters {

    param(

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$VCenters = (Import-Csv "$home\Documents\WindowsPowerShell\Modules\SysEng\vCenters.csv")
    )


    Write-Host "NOTE: The script will try and connect to the vCenter(s) using your current credentials." `
                "If it fails, it will prompt you for alternate credentials." -ForegroundColor White -BackgroundColor Black
    Read-Host("Press `"Enter`" to continue or `"CTRL + C`" to quit") | Out-Null

    $VCenters | Select-Object vCenter -Unique | ForEach-Object {

        Write-Host "$((Get-Date).ToString()) | Connecting to $($_.vCenter)"
        Connect-VIServer $_.vCenter | Out-Null
    }
}

Export-ModuleMember -Function Connect-SysEngToVCenters