[VISUAL STUDIO ALM RANGERS](http://aka.ms/vsaraboutus)
 ---

| [README](./README.md) | [Setting the context for PowerShell DSC](./Setting the context for PowerShell DSC.md) | [**Interesting Questions and Answers**](./Interesting Questions and Answers.md) | [Walkthrough - File Server & Share Custom Resource](./Building and sharing a custom resource walkthrough.md) | [Walkthrough - Deploy TFS 2013 using DSC](./Deploy TFS 2013 using DSC.md) |

| Appendix [PowerShell 101](./Getting started with PowerShell.md) | [Scenario - Deploy a website using MSDeploy](Scenario - Deploy a website using MSDeploy.md) | [Scenario - Deploying a database using DacPac](./Scenario - Deploying a database using DacPac.md) | [Scenario - TFS 2013 on a single ATDT server](./Scenario - TFS 2013 on a single ATDT server.md) |

# Interesting Questions and Answers
## How does a third party review their schema?
The best way to ensure you are developing your PowerShell DSC Resource properly is to use the [DSC Resource Designer Tool](http://blogs.msdn.com/b/powershell/archive/2013/11/19/resource-designer-tool-a-walkthrough-writing-a-dsc-resource.aspx). This module includes tools such as

- New-DscResource: generates the code skeleton and MOF for a new DSC Resource
- Test-DscResource: which checks the resource against the MOF, and the basic rules for DSC

Watch for updates to this module in the DSC Resource kit, as the plan is for new tools will be added to this module.

## How is it possible to externalize common configurations?
***Context***: Scenario, you are automating several kind of "roles" (over 10 different types) and each role will have several nodes. Most of the roles, have configurations that are common to them (e.g.: Basic IIS capabilities, NLB, and so on). You want to externalize all these configurations into an external file to avoid repetition among other things. How?*

The best way to create support for common configurations is to use Composite Resources. Composite Resources are actually DSC Configurations built to be called from another Configuration. See [Reusing Existing Configuration Scripts in PowerShell Desired State Configuration](http://blogs.msdn.com/b/powershell/archive/2014/02/25/reusing-existing-configuration-scripts-in-powershell-desired-state-configuration.aspx).

Not part of this topic, but related: When there are multiple organizations that have ownership over the configuration of a single system, creating a single DSC Configuration can be difficult. The classic example is when the storage, networking, and database teams must collaborate to build out a SQL Server instance. To solve this, the [Windows Management Framework (WMF) 5.0 September Preview](http://blogs.msdn.com/b/powershell/archive/2014/09/04/windows-management-framework-5-0-preview-september-2014-is-now-available.aspx) has added support for Partial Configurations. This allows the Configuration to be managed as multiple components, drawn from a single Pull Server. There is good information in the Release Notes for the WMF 5.0 September Preview on how to take advantage of this. Also see Composite Resources, in [The DSC Book](http://aka.ms/dscPsoBook).

## How to deal with a process pinned in memory?
***Context***: This problem would manifest if you cannot debug into a module and old code you just deleted seems to be running.*
If you encounter issues with resources that are cached in memory, you have two options of resetting your environment:
- Kill the WMI provider host that is hosting your PowerShell or PowerShell ISE window, rather than unloading and re-loading it.

Or
- Create and run a script to unload cached modules


## Check that the required PowerShell module is loaded if it is remove it as it might be an older version
```powershell
if ((get-module -name AlmRangers.Tfs.Utilities) -ne $null)
{
    remove-module AlmRangers.Tfs.Utilities
}
import-module .\AlmRangers.Tfs.Utilities.psm1 -verbose
```

## How to decide the scope of a module?
When deciding the scope of a module consider if the actions you wish to perform on a system can be expressed as verbs on a noun in sentence e.g. Enable sharing on server X. If you can express your intent in this manner then you probably have the correct scope of the DSC module. If not you probably need to consider different scope.

## How to know when configuration has actually completed?
The [Windows Management Framework 5.0 Preview](http://blogs.msdn.com/b/powershell/archive/2014/09/04/windows-management-framework-5-0-preview-september-2014-is-now-available.aspx) has added a new cmdlet called `Get-DSCConfigurationStatus`. This will allow a user to check the status of current or recently executed DSC Configurations. You can get
information about the cmdlet from the Release Notes document for WMF 5.0 September.

## Sometimes I have to reboot in order for a change to my resource script to take effect. Which process or service do I need to cycle to avoid a full reboot?
Have this command (cmd) file on your desktop:

    robocopy <your source>\Modules\ "%ProgramFiles%\WindowsPowerShell\Modules" /MIR
    net stop winmgmt 
    net start winmgmt

## What to do with helper functions shared between modules?
See example in the [DSC Resource Kit](http://gallery.technet.microsoft.com/scriptcenter/DSC-Resource-Kit-All-c449312d), for example, xDatabase for good examples.

## When you start a DSC config you get log messages on the console. If the machine reboots during configuration, where can you see those log messages after a reboot?
For messages other than debug and verbose, you should use the Event Viewer and refer to Microsoft-Windows-Desired State Configuration/Operational. Also consider using the
[DebugView](http://technet.microsoft.com/en-us/sysinternals/bb896647) tool from
[sysinternals](http://technet.microsoft.com/en-US/sysinternals).