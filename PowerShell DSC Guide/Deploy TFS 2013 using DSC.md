[VISUAL STUDIO ALM RANGERS](http://aka.ms/vsaraboutus)
 ---

| [README](./README.md) | [Setting the context for PowerShell DSC](./Setting the context for PowerShell DSC.md) | [Interesting Questions and Answers](./Interesting Questions and Answers.md) | [Walkthrough - File Server & Share Custom Resource](./Building and sharing a custom resource walkthrough.md) | [Walkthrough - **Deploy TFS 2013 using DSC**](./Deploy TFS 2013 using DSC.md)

| Appendix [PowerShell 101](./Getting started with PowerShell.md) | [Scenario - Deploy a website using MSDeploy](Scenario - Deploy a website using MSDeploy.md) | [Scenario - Deploying a database using DacPac](./Scenario - Deploying a database using DacPac.md) | [Scenario - TFS 2013 on a single ATDT server](./Scenario - TFS 2013 on a single ATDT server.md) |

# Walkthrough - Deploy TFS 2013 using DSC

## Introduction

In this walkthrough, we look at the process of deploying Microsoft Team Foundation Server 2013 on a base installation of Windows Server 2012 R2. The premise is that we need to get a single-server TFS deployment up and running quickly. This could be for demonstration purposes, or for supporting multiple isolated virtualized development environments. To keep the deployment simple, the scope is limited to a single-server deployment, with an application tier and build; we have excluded reporting and SharePoint integration for the time being.

**>> NOTE >>** Please refer to **Quick Reference Cheat sheet / Posters**, for information on a visual cheat sheet poster that guides you through this and other walk throughs.

In order to build this, the main components you must deploy are:

1.  The SQL Server Database Engine
2.  SQL Server Analysis Services
3.  Team Foundation Server Application Tier
4.  Team Foundation Server Build

Consequently, we mapped each of these to a PowerShell DSC resource. The sections below discuss the resources that we built to support these components.

**>> NOTE >>** You must be a local administrator on the server where you run the configuration.
 
You will also need:
- We will use TFS Administrator as the credentials for the account. We use this account to run the TFS Configuration Wizard and the account requires local administration rights on the server.
- [Optional] The credentials of an account used to access the share where the install media are located

### SQL Server Resources

The Resource Kit already has a resource for **SQL Server**. However, we found number of deficiencies, which made it simpler to rewrite the resource. The problems identified with the Resource Kit resource for SQL Server (xSqlServerInstall) were as follows:

1. It provided a parameter that allows the configuration of the set of features to be installed. However, it does not provide a way to supply the other parameters that might be required by other features, meaning that installation could never succeed. It is also not particularly intentional design just to give access to the raw  list of features.
2. It always reboots the machine, no matter what feature was installed, and without checking to see whether the installation succeeded. This would result in an infinite reboot cycle if the installation fails.
3. It imposes SQL Server authentication, and provides no option for integrated security, which is usually preferred.
4. It imposes specific service accounts and imposes the local System account as the sysadmin server role.
5. It does not support removal of SQL Server.

#### Design of the Resources

##### Reveal the Intention

Rather than provide the list of features as a parameter, we defined a number of separate intention-revealing resources instead. Therefore, there is one resource for the SQL Server Engine, another resource for SQL Analysis Services, and another one for SQL Server Management Studio. When the time comes to add Reporting Services, we can define an additional resource.

This design means we do not need the features parameter any more. In some cases, we control sub features through additional parameters. For example, the SQL Database Engine has a Full Text option, which we install as a feature. The Full Text option is required when deploying TFS. Therefore, the Resource has a FullText parameter, indicating whether we need Full Text. Inside the Resource, we modify the list of features to install according to the value of the Full Text parameter. Similarly, there is a basic and full install of SQL Management Studio, and that is a feature controlled by an intention-revealing parameter on the Resource.

It should be clear that the principal that we have applied is to make the Resource parameters intentional, rather than just providing a technical list of features. Having a technical list of features requires the person authoring the configuration to know about how the Resource works, what the internal names of the features are etc.

##### Error Handling

The new SQL Server resources actually check whether the install succeeded or not. Most importantly, they do not set the reboot flag if the install failed. This will prevent an infinite reboot cycle, something that the Resource Kit resource is prone to do.

This raises the question of how to report errors. The answer is to throw an exception. This will tell the Local Configuration Manager that something went wrong; otherwise, it will just blindly carry on with the other configuration items we have given it, and assume your resource is
in its desired state.

##### Give Important Choices

The Resource Kit resource imposes one, arguably less desirable, authentication mode, and forces us to use certain accounts as the service accounts and for the sysadmin server role. The new resources allow you to parameterize all these aspects to, so that the person defining the configuration is in control of these important aspects of the server.

We have defined other important parameters, allowing the locations of the database directories to be controlled. Most organizations have standards for where things are placed that must be respected, and so it is important to allow these aspects to be controlled.

##### Consider Supporting Ensure=Absent

This is arguably less useful. It would seem unlikely that anyone would use a SQL Server resource to ensure that you don not install SQL Server. However, it could be that an organization wants to move certain SQL Server components to other servers as their implementation grows.

### Team Foundation Server Resources

There were no pre-existing Resources for Team Foundation Server, so we designed these from scratch. They assume a single server deployment.

#### Design of the Resources

##### Granularity

A Resource has been defined for the Application Tier and for Build, as these are the components that an Administrator would think in terms of. We also wanted a Team Project Collection Resource as well, but the only
way to do this is through the TFS Object Model (see [*TFS2010: Create a new Team Project Collection from Powershell and C#*](http://blogs.msdn.com/b/granth/archive/2010/02/27/tfs2010-create-a-new-team-project-collection-from-powershell.aspx) and there was not enough time to do this. This could be added later. It should be noted, though, that the Object Model does not appear to allow for the deletion of a Team Project Collection (which is probably a good thing!) which may make it difficult to create a fully-fledged PowerShell DSC Resource for Team Project Collections.

There was discussion within the team about whether there should be a Resource to represent just the Team Foundation Server binaries being installed on the machine. This is because you must install these binaries first since both the Application Tier and Build require them. However, we decided not to do this because it hides intention. It is not the intention to install the binaries; it is the intention to install an Application Tier. Furthermore, it is unlikely anyone would want to install the binaries and then do nothing with them, so installing an Application Tier (or Build) would always need two steps, and you would have to remember the dependency, there is more to get wrong. Consequently, we defined the Resources as much as possible in functional terms, rather than technical terms.

**>> NOTE >>** Instead of the above approach, you should really consider to design principle of decomposing to smallest components. Use a composite resource to bundle the deployment with the configuration, see [The DSC Book](http://aka.ms/dscPsoBook) for details.

This has a small impact on the Get-TargetResource function. It needs to detect if we have installed the binaries and if we have done the configuration. This is important for idempotency, as installation of a Resource could be interrupted for any reason. The hash table returned by Get-TargetResource returns the status of both items, so that Test-TargetResource can check if everything has been done, and Set-TargetResource knows which bits still need to be done.

##### Identity

One problem we encountered creating the TFS Resources was that the TFS Administrator must run the tfsconfig.exe program. We normally run Resource scripts in the context of the Local System account, which cannot be the TFS Administrator.

To run the tfsconfig.exe program under the identity of another account requires the use of PowerShell remote sessions. Specifically, the -ComputerName and -Credential options of the Invoke-Command cmdlet have been used to do this.

We need further steps if the tfsconfig.exe program needs access to other systems in the domain. In that case, we also need the –Authentication CredSSP option, and we need to enable CredSSP. To enable CredSSP, enter the following commands on the server where we will use CredSSP:

```console
winrm set winrm/config/client/auth @{CredSSP="true"}
winrm set winrm/config/service/auth @{CredSSP="true"}
```

It is also necessary to edit the Group Policy LocalComputerPolicy, ComputerConfiguration, Administrative Templates, System, Credentials Delegation, Allow delegating fresh credentials. Enable this policy, and in the list of servers enter “WSMAN/\<server FQDN\>”.

You can find more information about CredSSP here: [Multi-Hop Support in WinRM](http://msdn.microsoft.com/en-us/library/ee309365(v=vs.85).aspx)

**Limitations** 
- The Resources described here are not fully “make it so.” Once we have installed and configured the component we deem that successful. If the configuration is changed, the state will not be changed if the configuration is run again.
- In some cases, the component makes it impossible to check the configuration. For example, there is no way to find out what Team Project Collections there are, and we cannot rename the Team Project Collection if the configuration says it should be called something else.
- Similarly, changes to the SQL Server configuration, although possible, could be quite hard to do. For example, if the directory locations are changed, there could be quite a lot of work to move databases.
- We have not tested the Resources in a multiple server configuration, where, for example, SQL Server is on a different computer to TFS. Furthermore, we have not tested them in a domain with domain accounts; it is likely that some of the resource parameters will have to be changed to support this.

## Building the Resources

In this section, we cover how we built the resources. The example used here is the resource used to install the SQL Server Engine.

1. **Copy an existing resource**
	- Rather than re-invent the wheel, the easiest thing to do is to make a copy of an existing resource and then change it into the module and resource you are designing. For the resources we are building here, we used the xSqlPs resource from the resource kit. 
	- We used the following steps:
		- Install the Resource Kit.
		- In %ProgramFiles%\\WindowsPowerShell\\Module, copy the xSqlPs directory and create a new cSql directory.
		- Inside the %ProgramFiles%\\WindowsPowerShell\\Module\\cSql directory rename the .psd1 file to cSql.psd1.
		- Edit the cSql.psd1 file; replace the GUID with a new GUID (use the Guidgen program, which is part of Visual Studio, to do this). Also, amend the Author, CompanyName, Copyright and Description settings as appropriate.
		- Inside the %ProgramFiles%\\WindowsPowerShell\\Module\\cSql\\DSCResources directory, delete all but one of the directories. Rename the directory you leave behind to match your resource name (in this case VSAR\_cSqlServerEngine).
		- Rename the mof file to VSAR\_cSqlServerEngine.schema.mof.
		- Rename the psm1 file to VSAR\_cSqlServerEngine.psm1.
2. **Update and test schema**
	- The next step is to define the schema. We can do this with PowerShell cmdlets that generate properties. However, in this case we edit the MOF file directly.
	- Open the MOF file in a text editor (notepad or Visual Studio will do).
	- Change the FriendlyName to cSqlServerEngine and the class name to VSAR\_cSqlServerEngine, as shown below:
		```powershell
		[ClassVersion("1.0.0.0"), FriendlyName("cSqlServerEngine")]
		class VSAR_cSqlServerEngine : OMI_BaseResource
		```
	- Edit the properties to match the requirements of your resource. Try to use ValueMap and Values attributes for properties that take one of a set of fixed values. Use EmbeddedInstance(“MSFT\_Credential”) where a credential is required. The parameters for cSqlServerEngine were defined as follows:
		```powershell
		[Key, Description("The name of sql instance")] string InstanceName;
		[Write, ValueMap{"Present", "Absent"}, Values{"Present", "Absent"}] string Ensure;
		[Write, Description("The service account under which the SQL Agent runs")] string AgentServiceAccount;
		[Write, Description("The service account under which the SQL Server service runs")] string SqlServiceAccount;
		[Write, Description("The account which is in the sysadmin role for SQL Server")] string SysAdminAccount;
		[Write, Description("The location of the TempDB data files")] string TempDBDataDirectory;
		[Write, Description("The location of the TempDB log files")] string TempDBLogDirectory;
		[Write, Description("The location of the user database data files")] string UserDBDataDirectory;
		[Write, Description("The location of the user database log files")] string UserDBLogDirectory;
		[Write, ValueMap{"Present", "Absent"}, Values{"Present", "Absent"}] string FullText;
		[Write, Description("The path to the directory where log files are to be placed")] string LogPath;
		[Write, Description("The share path of sql server software")] string SourcePath;
		[Write, EmbeddedInstance("MSFT_Credential"), 
		Description("The credential to be used to access net share of sql server software")]string SourcePathCredential;
		```
	- Verify that the schema is valid using the following command:
		```console
		Test-xDscSchema -Path \$env:ProgramFiles\\WindowsPowerShell\\Modules\\cSql\\DSCResources\\VSAR\_cSqlServerEngine\\VSAR\_cSqlServerEngine.schema.mof
		```

	- Fix any issues reported. The cmdlet will return “true” if the schema is valid. Note that you have to be running an elevated PowerShell environment to run this cmdlet.
3. **Edit parameters to TargetResource functions**
	- In this step you set up the Get/Test/Set\_TargetResource functions with the parameters that match the schema MOF you edited in the previous step, as follows:
		- Open the .psm1 file.
		- Edit the parameters of Get\_TargetResource to match the Key properties in the MOF file.
		- Edit the parameters of Test\_TargetResource and Set\_TargetResource file to match the full set of properties in the MOF file.
		- Verify that the resource is valid using the following command:\
		- Test-xDscResource cSqlServerEngine
		- Fix any issues reported.
		- Be sure that the parameter attributes in the PowerShell functions match the properties in the MOF file. In particular:
			- Use PSCredential for EmbeddedInstance (“MSFT\_Credential”) properties.
			- “Key” properties must be declared: [parameter(**Mandatory**)]
			- Non-Key parameters that are nonetheless mandatory should be declared [ValidateNotNullOrEmpty ()] or [ValidateNotNull ()].
4. **Implement the resource**
	- Add the code to the Get, Test and Set functions for the Resource as appropriate. These functions must operate idempotently, which means that it should be possible to run them more than once and have the same result without getting any errors.
5. **Add a new resource**
	-  If further resources are required in the module, repeat the steps above, using the new resource that we have just created as the starting point. Only create an entirely new module if the next resource to be authored, is not related to other resources in the same module.

---
NOTE: In this walkthrough, we only covered cSql. The same steps apply to the cTfs resource referenced in this walkthrough.
 ---

## Steps to Configure TFS on a Single Server

This section describes the steps to take to build TFS on a single server, from scratch, using the PowerShell DSC resources that we previously described. The result is an installation of Team Foundation Server 2013 and a Build Service, along with the SQL Server software, all on a single server running Windows Server 2012 R2.

The pre-requisite is a server running Windows Server 2012 R2.

1. **Gather the installation media**
	- Place the installers for the following products on a share that is accessible from the server where TFS is going to be installed:
		- Windows Server 2012 R2
		- SQL Server 2012
		- Team Foundation Server 2013
2. **Install the DSC resource**
	- Copy the cSql and the cTfs resources to the following directory on the target server:
		```powershell
		%ProgramFiles%\WindowsPowerShell\Module
		```

	- Make sure that the scripts are not blocked by running the following command:
		 ```powershell
		$resourcePath = [System.IO.Path]::Combine((Get-Item env:ProgramFiles).Value, "WindowsPowershell\\Modules\\")
		Get-ChildItem -Path \$resourcePath -Recurse -include ("\*.psd1", "\*.psm1") | Unblock-File
		```

3. **Configure the server for DSC**
	- To be able to run DSC and the PowerShell scripts, on the server, carry out the following steps:
	  Configure the server for DSC
	- Run the following command from a command prompt (do not use a PowerShell shell as this may stop responding):
		```console
		winrm quickconfig
		```
	- Enable processing of unsigned scripts using the following PowerShell command, from a shell that is running with elevated permissions:
		```console
		Set-ExecutionPolicy remotesigned 
		```

	- If the server is part of a domain and domain accounts are going to be used then enable CredSSP using the following command:
		```console
		winrm set winrm/config/client/auth @{CredSSP="true"}
		```
4. **Set up the configuration**
	- Place the PowerShell configuration into a .ps1 file on the server:
		```powershell
		Configuration Tfs
		{
		   …
		}
		```

	- See [DSC configuration script sample](./samples/ConfigurationScript.md) for the complete script.
	- At the top of the file just created above, add the configuration data, which must be set up along the following lines, replacing the marked tokens:
		```powershell
		$ConfigData=
		@{
		 …
		}
		```

	- At the end of the file just created above, add the following script, which actually invokes the DSC resources.
5. **Run the configuration**
	- Run the script that we created in the previous step. This script will update Windows, install SQL Server, and install TFS. The machine will reboot a couple of times.
	- Check the log file location if you want to check on progress.

## Sample Code

- [Configuration Script Sample](./samples/ConfigurationScript.md)
- See **Walkthrough - Deploy TFS 2013 using DSC** in samples folder.
