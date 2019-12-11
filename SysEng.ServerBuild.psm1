<#
CREATE VM(s)

The function New-SysEngVM will loop through the provided PSCustomObject and create each VM. It will create
it in the specified vCenter, using the speicified template, on the specified cluster and datastore.
#>
function New-SysEngVM {

    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$VMConfiguration
    )


    $VMName = $VMConfiguration.VMName
    $Server = Get-VIServer -Server $VMConfiguration.vCenter
    $Template = Get-Template -Name $VMConfiguration.Template -Server $Server
    $ResourcePool = Get-Cluster -Name $VMConfiguration.Cluster -Server $Server
    $Datastore = Get-Datastore -Name $VMConfiguration.Datastore -Server $Server

    Write-Host "$((Get-Date).ToString()) | Creating $VMName"
    New-VM -Name $VMName `
            -Server $Server `
            -Template $Template `
            -ResourcePool $ResourcePool `
            -Datastore $Datastore `
            -DiskStorageFormat Thin `
            -RunAsync | Out-Null
}


<#
CHECK FOR CLONING TASKS

The Wait-SysEngCloneTask function is just a loop that is checking for any running cloning tasks. The
script will pause here until all cloning tasks have been completed.
#>
function Wait-SysEngCloneTask {

    while($true) {

        Start-Sleep 60
        $Task = Get-Task -Status Running | Where-Object {$_.Name -eq 'CloneVM_Task'}

        if($Task) {

            Write-Host " "
            $Task

        } else {
            
            Write-Host "`n$((Get-Date).ToString()) | Virtual Machine(s) have been created."
            break
        }
    }
}


<#
CONFIGURE VM(s)

The Set-SysEngVM function will loop through the newly created VM(s) and configure the following:

- Guest ID
- MemoryGB
- CPU
- NIC (Checks for an existing distributed switch and assigns the specified VLAN. If no distributed switch
exists, the function loops through the standard switches until it finds a port group on the specified VLAN.)
- Adds additional disks if specified
- Powers on VM(s)
#>
function Set-SysEngVM {

    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$VM
    )


    $VMName = $VM.VMName
    $GuestId = $VM.GuestID
    $Memory = $VM.MemoryGB
    $NumCpu = $VM.NumCpu
    $VLAN = $VM.VLAN
    $AdditionalDisks = $VM.AdditionalDisks
    $Capacity = $VM.CapacityGB
    $Datastore = $VM.Datastore
    $VCenter = $VM.vCenter

    # Configure guestID, memory and CPU
    Write-Host "$((Get-Date).ToString()) | Configuring $VMName"
    Set-VM -VM $VMName -Server $VCenter -GuestId $GuestId -MemoryGB $Memory -NumCpu $NumCpu -Confirm:$false -RunAsync | Out-Null

    # Configure network adapter
    $VSwitch = Get-VM $VMName -Server $VCenter | Get-VMHost | Get-VDSwitch

    if($VSwitch) {

        $PortGroup = Get-VDPortgroup -VDSwitch $VSwitch -Server $VCenter | Where-Object {$_.VlanConfiguration.VlanId -eq $VLAN}
        Get-NetworkAdapter -VM $VMName -Server $VCenter | Set-NetworkAdapter -Portgroup $PortGroup -Confirm:$false | Out-Null
        Get-NetworkAdapter -VM $VMName -Server $VCenter | Set-NetworkAdapter -StartConnected:$true -Type Vmxnet3 -WakeOnLan:$true -Confirm:$false -RunAsync | Out-Null
        
    } else {

        $VSwitch = Get-VM $VMName -Server $VCenter | Get-VMHost | Get-VirtualSwitch

        foreach($StandardSwitch in $VSwitch) {

            $VLan_temp = $StandardSwitch | Get-VirtualPortGroup | Where-Object {$_.VlanId -eq $VLAN}

            if($VLan_temp) {

                $PortGroup = $VLan_temp
                Get-NetworkAdapter -VM $VMName -Server $VCenter | Set-NetworkAdapter -Portgroup $PortGroup -Confirm:$false | Out-Null
                Get-NetworkAdapter -VM $VMName -Server $VCenter | Set-NetworkAdapter -StartConnected:$true -Type Vmxnet3 -WakeOnLan:$true -Confirm:$false -RunAsync | Out-Null
            }
        }
    }

    # Add more disks
    if($AdditionalDisks -eq "TRUE") {
            
        New-HardDisk -VM $VMName -CapacityGB $Capacity -Datastore $Datastore -StorageFormat Thin -Server $VCenter | Out-Null
    }

    # Power on VM(s)
    Write-Host "$((Get-Date).ToString()) | Powering on $VMName"
    Start-VM -VM $VMName -Confirm:$false -RunAsync | Out-Null
}


<#
CONFIGURE GUEST OS

The Set-SysEngGuest function will loop through the newly created VM(s) and configure the following:
- Remove any auto-assigned APIPA address
- Assign the specified IPv4 address and prefix
- Disable IPv6
- Assign specified DNS servers
- Attempt to join guest OS to specified domain and place it in the specified OU
#>

function Set-SysEngGuest {

    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$VM,
        [PSCredential]$LocalCreds
    )


    $VMName = $VM.VMName
    $IPAddress = $VM.IPAddress
    $DNS = $VM.DNS.Replace(" ","")
    $DefaultGateway = $VM.DefaultGateway
    $Prefix = $VM.Prefix
    $Domain = $VM.Domain
    $OU = $VM.OU
    $DomainCreds = $VM.DomainCreds

    
    # Get VMXNET3 interface alias from guest
    $GetVMXNET3Interface = "(Get-NetIPConfiguration | ?{`$_.InterfaceDescription -eq 'vmxnet3 Ethernet Adapter'}).InterfaceAlias"
    $Interface = Invoke-VMScript -VM $VMName -ScriptText $GetVMXNET3Interface -GuestCredential $LocalCreds
    $Interface = $Interface.ScriptOutput.Trim()

    # Removing APIPA address, setting new IP and disabling IPv6
    $setGuestIP = "
        Remove-NetIPAddress -InterfaceAlias $Interface -Confirm:`$false -ea SilentlyContinue
        New-NetIPAddress -IPAddress $IPAddress -InterfaceAlias $Interface -DefaultGateway $DefaultGateway -AddressFamily IPv4 -Type Unicast -PrefixLength $Prefix
        Set-NetAdapterBinding -Name $Interface -ComponentID ms_tcpip6 -Enabled:`$false -Confirm:`$false
    "
    Write-Host "$((Get-Date).ToString()) | Configuring IP on $VMName"
    Invoke-VMScript -VM $VMName -ScriptText $setGuestIP -GuestCredential $LocalCreds -RunAsync | Out-Null

    # Configuring DNS
    $setGuestDNS = "
        Set-DnsClientServerAddress -InterfaceAlias $Interface -ServerAddresses $DNS -Confirm:`$false
    "
    Write-Host "$((Get-Date).ToString()) | Configuring DNS on $VMName"
    Invoke-VMScript -VM $VMName -ScriptText $setGuestDNS -GuestCredential $LocalCreds -RunAsync | Out-Null

    # Add guest to domain
    $UserName = $DomainCreds.Credentials.Username
    $Password = $DomainCreds.Credentials.GetNetworkCredential().Password
    $AddGuestToDomain = "
        Start-Sleep 15
        `$creds = [System.Management.Automation.PSCredential]::new(`'$UserName`', (ConvertTo-SecureString `'$Password`' -AsPlainText -Force))
        Add-Computer -Credential `$creds -DomainName $Domain -OUPath `'$OU`' -NewName $VMName -Restart | out-file C:\log.log
    "
    Write-Host "$((Get-Date).ToString()) | Adding $VMName to $Domain"
    Invoke-VMScript -VM $VMName -ScriptText $AddGuestToDomain -GuestCredential $LocalCreds -RunAsync
}


<#
GET CREDENTIALS FOR EACH DOMAIN

The Get-DomainCredentials function will loop through the specified domains and collect credentials, so
it can join the newly created VM(s) to the specified domains.
#>
function Get-DomainCredentials {

    param(
        [Parameter(Mandatory=$true)]
        [Array]$Domains
    )

    $DomainCredentials = @()

    $Domains | ForEach-Object {

        Write-Host "Getting credentials for $($_.Domain) domain"

        $TempObj = [PSCustomObject]@{
            
            "Domain"=$_.Domain;
            "Credentials"=(Get-Credential -Message "Enter domain credentials for $($_.Domain):")
        }

        $DomainCredentials += $TempObj
    }

    return $DomainCredentials
}


<#
CREATE ADM GROUP

The New-SysEngADMGroup function will loop through the newly created VM(s) and create an administrative AD
group that will serve for administrating the VM. The group will be placed in the OU that has been specified
in this function. You can specify your own OU by simply editing the -Path parameter in this function.
#>
function New-SysEngADMGroup {

    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Server
    )

    
    $GroupName = "ADM_$($Server.VMName)"
    $Credentials = $Server.DomainCreds.Credentials
    $DC = (Resolve-DnsName $Server.DNS.Split(',').Trim()[0]).NameHost

    if($Server.Domain -eq "acme.local") {

        Write-Host "$((Get-Date).ToString()) | Creating AD group $GroupName"
        New-ADGroup -Name $GroupName `
                    -DisplayName $GroupName `
                    -SamAccountName $GroupName `
                    -GroupCategory Security `
                    -GroupScope DomainLocal `
                    -Description "Administration - $($Server.VMName)" `
                    -Path "OU=ADM,OU=Groups,OU=Enterprise,DC=acme,DC=local" `
                    -Server $DC `
                    -Credential $Credentials
    }    
}


<#
ADD ADM GROUP TO LOCAL ADMINISTRATORS GROUP

The Add-SysEngADMGroup function will loop through the newly created VM(s) and add the ADM groups that were
created in the New-SysEngADMGroup function.
#>
function Add-SysEngADMGroup {

    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Server
    )

    $VMName = $Server.VMName.Trim()
    $Credentials = $Server.DomainCreds.Credentials
    $GroupName = "ADM_$($VMName)"
    $AddADMGroup = {
        
        param($d,$g)
        NET LOCALGROUP Administrators "$($d.Domain.Split('.')[0])\$g" /ADD
    }

    Write-Host "$((Get-Date).ToString()) | Adding $GroupName to $VMName"
    Invoke-Command $VMName -ScriptBlock $AddADMGroup -ArgumentList ($Server,$GroupName) -Credential $Credentials
}


#################
# MAIN FUNCTION #
#################

<#
.SYNOPSIS
Loops through the specified PSCustomObject and does the following:

- Creates the VM(s)
- Configures the newly created VM(s)
- Configures the guest OS on the newly created VM(s)

.DESCRIPTION
This script will loop through the specified PSCustomObject and perform the following tasks:

- [STAGE 1] Connect to vCenter(s)
    - Will loop through the PSCustomObject and attempt to connect to the the specified vCenters using credentials
    that were used to run the script. If authentication fails, the script will prompt the user for alternate credentials.

- [STAGE 2] Get Domain Credential(s)
    - Will loop through the PSCustomObject and collect credentials for each specified domain.

- [STAGE 3] Create specified VM(s)
    - Will be created on the specified vCenter
    - Will be created using the speicified template
    - Will be created on the speciried cluster and datastore
- Once stage 1 has been completed, the script will pause and wait for the new VM(s) to be created

- [STAGE 4] Configure newly created VM(s)
    - Will set the specified Guest ID
    - Will configure the specified MemoryGB
    - Will configure the specified CPU
    - Will confgiure the NIC
        - The script will check for an existing distributed switch and assigns the specified VLAN.
        - If no distributed switch exists, the function loops through the standard switches until it
        finds a port group on the specified VLAN.
    - Will add additional disks if specified
    - Will power on newly created VM(s)
- Once the newly created VM(s) have been powered on, the script will pause for 4 minutes

-[STAGE 5] Configure Guest OS
    - Will remove any auto-assigned APIPA addresses
    - Assign the specified IPv4 address with specified prefix
    - Disable IPv6
    - Assign specified DNS servers
    - Attempt to join the guest OS to specified domain and place it in the specified OU

- [STAGE 6] Create ADM Group
    - Will attempt to create an ADM group (Naming Convention: "ADM_<Hostname>") and place it in the
    specified OU. The default OU can be edited in the New-SysEngADMGroup function under the -Path parameter

- [STAGE 7] Add ADM Group to Guest OS
    - Will attempt to add the newly created ADM group to the local "Administrators" group on the newly created
    VM(s) via WinRM.

.PARAMETER Servers
Takes a PSCustomObject that contains an array of values related to the virtual machine builds. Please see
examples for more details and check out the example CSV template in the module base directory or at the below
URL.

https://github.com/igorkrnjajic/SysEng

.PARAMETER ConnectToVCenters
Boolean parameter is set to TRUE by default. Connects to the speicified vCenters.

.PARAMETER CreateVM
Boolean parameter is set to TRUE by default. Creates a VM with the specified name by cloning the specified template.

.PARAMETER ConfigureVM
Boolean parameter is set to TRUE by default. Configures the newly created VMs with the specified parameters.

.PARAMETER ConfigureGuest
Boolean parameter is set to TRUE by default. Configures the guest OS on the newly created VMs using the specified
parameters.

NOTE: If setting this parameter to True, ensure that you specify the -LocalCreds parameter as well.

.PARAMETER LocalCreds
Takes a PSCredential object that will grant access to the guest OS.

NOTE: Must be specified if the -ConfigureGuest and/or -AddADMGroup parameter is set to True.

.PARAMETER CreateADMGroup
Boolean parameter is set to TRUE by default. Creates an administrative group in the format "ADM_<Hostname>" and palces
it in the OU defined in the New-SysEngADMGroup function.

.PARAMETER AddADMGroup
Boolean parameter is set to TRUE by default. Adds the corresponding ADM group to the local "Administrators" group on
guest OS.

NOTE: If setting this parameter to True, ensure that you specify the -LocalCreds parameter as well.

.EXAMPLE
PS> $Servers = Import-Csv C:\path\to\server\build\template.csv
PS> $Servers

VMName          : TestVM
Domain          : acme.local
vCenter         : vcenter01.acme.local
Template        : TMPL_2016_GOLD
Cluster         : Cluster01
Datastore       : Datastore01
AdditionalDisks : TRUE
CapacityGB      : 60
GuestId         : windows9Server64Guest
MemoryGB        : 16
NumCpu          : 2
CoresPerSocket  : 1
VLAN            : 50
IPAddress       : 10.10.50.100
DefaultGateway  : 10.10.50.1
Prefix          : 24
DNS             : 8.8.8.8, 8.8.4.4
OU              : OU=Servers,DC=acme,DC=local


PS> Start-SysEngServerBuild -Servers $Servers -LocalCreds Administrator
#>

function Start-SysEngServerBuild {

    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Servers,
        [Boolean]$ConnectToVCenters=$true,
        [Boolean]$CreateVM=$true,
        [Boolean]$ConfigureVM=$true,
        [Boolean]$ConfigureGuest=$true,
        [PSCredential]$LocalCreds,
        [Boolean]$CreateADMGroup=$true,
        [Boolean]$AddADMGroup=$true
    )


    #[STAGE 1] Connect to vCenter(s)
    if($ConnectToVCenters) {

        Write-Host "`n[STAGE 1] Connect to vCenter(s)`n" -ForegroundColor Cyan
        Connect-SysEngToVCenters -VCenters $Servers
    }

    #[STAGE 2] Get Domain Credential(s)
    if($ConfigureGuest -or $CreateADMGroup -or $AddADMGroup) {

        Write-Host "`n[STAGE 2] Get Domain Credential(s)`n" -ForegroundColor Cyan
        $DomainCreds = Get-DomainCredentials -Domains ($Servers | Select-Object Domain -Unique)

        $Servers | ForEach-Object {

            $s = $_
            Add-Member -InputObject $s -MemberType NoteProperty -Name "DomainCreds" -Value ($DomainCreds | Where-Object {$_.Domain -eq $s.Domain})
        }
    }

    #[STAGE 3] Create VM(s)
    if($CreateVM) {

        Write-Host "`n[STAGE 3] Create VM(s)`n" -ForegroundColor Cyan
        
        $Servers | ForEach-Object {

            New-SysEngVM -VMConfiguration $_
        }

        Write-Host "$((Get-Date).ToString()) | Waiting for VM(s) to be created. Checking every 1 minute." -ForegroundColor Yellow
        Wait-SysEngCloneTask
    }

    #[STAGE 4] Configure VM(s)
    if($ConfigureVM) {

        Write-Host "`n[STAGE 4] Configure VM(s)`n" -ForegroundColor Cyan

        $Servers | ForEach-Object {

            Set-SysEngVM -VM $_
        }

        # Wait 4 minutes for VM(s) to power on
        Write-Host "$((Get-Date).ToString()) | Waiting for VMs to power on (4 minutes)." -ForegroundColor Yellow
        Start-Sleep 240
    }

    #[STAGE 5] Configure Guest(s)
    if($ConfigureGuest) {

        if($null -ne $LocalCreds) {

            Write-Host "`n[STAGE 5] Configure Guest(s)`n" -ForegroundColor Cyan

            $Servers | ForEach-Object {

                Set-SysEngGuest -VM $_ -LocalCreds $LocalCreds
            }
            
        } else {

            Throw "The -ConfigureGuest parameter is set to True, but the -LocalCreds parameter is Null."
        }
    }

    #[STAGE 6] Create ADM Group(s)
    if($CreateADMGroup) {

        Write-Host "`n[STAGE 6] Create ADM Group(s)`n" -ForegroundColor Cyan

        $Servers | ForEach-Object {

            New-SysEngADMGroup -Server $_
        }
    }

    #[STAGE 7] Add ADM Group to Server
    if($AddADMGroup) {

        Write-Host "`n[STAGE 7] Add ADM Group to Server`n" -ForegroundColor Cyan

        $Servers | ForEach-Object {

            Add-SysEngADMGroup -Server $_
        }
    }
}
