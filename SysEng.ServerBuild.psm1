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

The Set-SysEngWindowsGuest and Set-SysEngLinuxGuest function will loop through the newly created VM(s) and configure the following:
- Remove any auto-assigned APIPA address
- Assign the specified IPv4 address and prefix
- Assign specified DNS servers and suffixes
- Attempt to join guest OS to specified domain and place it in the specified OU
#>

function Set-SysEngWindowsGuest {

    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$VM,
        [Parameter(Mandatory=$true)][PSCredential]$LocalCreds
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

function Set-SysEngLinuxGuest {

    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$VM,
        [Parameter(Mandatory=$true)][PSCredential]$LocalCreds
    )

    $VMName = $VM.Name
    $IPAddress = $VM.IPAddress
    $DNS = $VM.DNS.Replace(" ","")
    $DefaultGateway = $VM.DefaultGateway
    $Prefix = $VM.Prefix
    $Domain = $VM.Domain
    $ConfigTemplate = Get-Content "$((Get-Module Syseng).ModuleBase)\Linux\100-ubuntu_20-04_tmpl.cfg" -Raw
    $ConfigFile = "$((Get-Module Syseng).ModuleBase)\Linux\100-$VMName.cfg"

    # Update config template with user's input
    $ConfigTemplate = $ConfigTemplate -replace "<hostname>",$VMName
    $ConfigTemplate = $ConfigTemplate -replace "<ip_addr>","$IPAddress/$Prefix"
    $ConfigTemplate = $ConfigTemplate -replace "<gw_addr>",$DefaultGateway
    $ConfigTemplate = $ConfigTemplate -replace "<dns_addr>",$DNS
    $ConfigTemplate = $ConfigTemplate -replace "<dns_suffix>",$Domain

    Write-Host "$((Get-Date).ToString()) | Copying `"100-$VMName.cfg`" to $VMName"
    New-Item -Path $ConfigFile -ItemType File -Value $ConfigTemplate | Out-Null
    Copy-VMGuestFile -Source $ConfigFile -Destination "/etc/cloud/cloud.cfg.d/" -LocalToGuest -VM $VMName -GuestCredential $LocalCreds
    Remove-Item $ConfigFile

    Invoke-VMScript -VM $VMName -ScriptText "cloud-init clean -lsr" -ScriptType Bash -GuestCredential $LocalCreds -RunAsync
}


<#
GET CREDENTIALS FOR EACH DOMAIN

The Get-DomainCredentials function will loop through the specified domains and collect credentials, so
it can join the newly created VM(s) to the specified domains.
#>
function Get-DomainCredentials {

    param(
        [Parameter(Mandatory=$true)][Array]$Domains
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
    - Assign specified DNS servers
    - Attempt to join the guest OS to specified domain and place it in the specified OU

.PARAMETER Servers
Takes a PSCustomObject that contains an array of values related to the virtual machine builds. Please see
examples for more details and check out the example CSV template in the module base directory or at the below
URL.

https://github.com/igorkrnjajic/SysEng

.PARAMETER SkipConnectToVCenters
Switch parameter will skip connecting to vCenters. Good to use if you're already connected to the vCenters.

.PARAMETER SkipCreateVM
Switch parameter will skip creating a new VM and move on to configuring an existing VM.

.PARAMETER SkipConfigureVM
Switch parameter will skip configuring the specified VM and move on to configuring the guest OS.

.PARAMETER SkipConfigureGuest
Swich parameter will skip configuring the guest OS on specified VM.

.PARAMETER LocalCreds
Takes a PSCredential object that will grant access to the guest OS. This parameter is mandatory if you want to configure the
guest OS and/or join a domain.

.PARAMETER CreateADMGroup
Boolean parameter is set to TRUE by default. Creates an administrative group in the format "ADM_<Hostname>" and palces
it in the OU defined in the New-SysEngADMGroup function.

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
        [Parameter(Mandatory=$true)][PSCustomObject]$Servers,
        [Switch]$SkipConnectToVCenters,
        [Switch]$SkipCreateVM,
        [Switch]$SkipConfigureVM,
        [Switch]$SkipConfigureGuest,
        [Switch]$JoinGuestToDomain,
        [PSCredential]$LocalCreds
    )


    #[STAGE 1] Connect to vCenter(s)
    if(!$SkipConnectToVCenters) {

        Write-Host "`n[STAGE 1] Connect to vCenter(s)`n" -ForegroundColor Cyan
        Connect-SysEngToVCenters -VCenters $Servers
    }

    #[STAGE 2] Get Domain Credential(s) and Local Credential
    if($JoinGuestToDomain) {

        if(!$LocalCreds) {

            $LocalCreds = Get-Credential -Message "Provide credentials for the guest OS:"
        }

        Write-Host "`n[STAGE 2] Get Domain Credential(s)`n" -ForegroundColor Cyan
        $DomainCreds = Get-DomainCredentials -Domains ($Servers | Select-Object Domain -Unique)

        $Servers | ForEach-Object {

            $s = $_
            Add-Member -InputObject $s -MemberType NoteProperty -Name "DomainCreds" -Value ($DomainCreds | Where-Object {$_.Domain -eq $s.Domain})
        }
    }

    #[STAGE 3] Create VM(s)
    if(!$SkipCreateVM) {

        Write-Host "`n[STAGE 3] Create VM(s)`n" -ForegroundColor Cyan
        
        $Servers | ForEach-Object {

            New-SysEngVM -VMConfiguration $_
        }

        Write-Host "$((Get-Date).ToString()) | Waiting for VM(s) to be created. Checking every 1 minute." -ForegroundColor Yellow
        Wait-SysEngCloneTask
    }

    #[STAGE 4] Configure VM(s)
    if(!$SkipConfigureVM) {

        Write-Host "`n[STAGE 4] Configure VM(s)`n" -ForegroundColor Cyan

        $Servers | ForEach-Object {

            Set-SysEngVM -VM $_
        }

        # Wait 4 minutes for VM(s) to power on
        Write-Host "$((Get-Date).ToString()) | Waiting for VMs to power on (4 minutes)." -ForegroundColor Yellow
        Start-Sleep (60*4)
    }

    #[STAGE 5] Configure Guest(s)
    if(!$SkipConfigureGuest) {

        if($LocalCreds) {

            Write-Host "`n[STAGE 5] Configure Guest(s)`n" -ForegroundColor Cyan

            $Servers | ForEach-Object {

                Set-SysEngGuest -VM $_ -LocalCreds $LocalCreds
            }
            
        } else {

            Throw "You need to provide guest OS credentials in order to configure the guest OS. Use the -LocalCreds parameter."
        }
    }
}
