# PowerShell SysEng Module (In Progress)
This PowerShell module will work in a combination of the following environments:
- VMware
- Microsoft Active Directory

The module automates a few everyday tasks for Systems/DevOps engineers/administrators. The tasks this module can currently help automate are:
- Simultaneously deploying multiple virtual machines to multiple vCenters using a template (Windows and Linux).
- Configuring vCPU, memory, HDD, NIC and guest ID on the newly created virtual machines (Windows and Linux).
- Configuring the network adapter and joining an Active Directory domain.

Please note, this is an amateur new module and it has not been thoroughly tested. Do not use this in your production environment before thoroughly testing the module on your own.

## Getting Started
The below instructions will guide you through what you need to do in order to run this module in your environment.

### Requirements
Powershell Version:
```
PS> $PSVersionTable

Name                           Value
----                           -----
PSVersion                      5.1.17763.771
PSEdition                      Desktop
PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0...}
BuildVersion                   10.0.17763.771
CLRVersion                     4.0.30319.42000
WSManStackVersion              3.0
PSRemotingProtocolVersion      2.3
SerializationVersion           1.1.0.1
```

PowerCLI version:
```
PS> Get-PowerCLIVersion

PowerCLI Version
----------------
   VMware PowerCLI 11.5.0 build 14912921
```

Modules:
```
PS> Get-Module ActiveDirectory -ListAvailable

ModuleType Version    Name
---------- -------    ----
Manifest   1.0.0.0    ActiveDirectory
```

### Installation
Once you confirmed that all requirements above have been met, simply start PowerShell and install the module from the PowerShell gallery:
```
PS> Install-Module SysEng
```
Then you can just import the module:
```
PS> Import-Module SysEng
```

**NOTE:** If downloading the repo directly from GitHub, ensure that you rename the folder to "SysEng".

## Examples
Get familiar with the commands:
```
PS> Get-Help Connect-SysEngToVCenters
```

Connect to the vCenters:
```
PS> Connect-SysEngToVCenters -VCenters $VCenters_Object
```
