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
```

PowerCLI version:
```
PS> Get-PowerCLIVersion
```

Modules:
```
PS> Get-Module ActiveDirectory -ListAvailable
```

The repo needs to be cloned/downloaded to:
```
$home\Documents\WindowsPowershell\Modules
```
**NOTE:** If downloading the repo, ensure that you rename the folder to "SysEng".

### Installation
Once the module has been cloned/downloaded and all requirements above have been met, simply start PowerShell and import the module:
```
PS> Import-Module SysEng
```

## Examples
Get familiar with the commands:
```
PS> Get-Help Connect-SysEngToVCenters
```

Connect to the vCenters:
```
PS> Connect-SysEngToVCenters -VCenters $VCenters_Object
```
