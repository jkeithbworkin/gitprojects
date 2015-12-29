[VISUAL STUDIO ALM RANGERS](http://aka.ms/vsaraboutus)
 ---

| [README](./README.md) | [Setting the context for PowerShell DSC](./Setting the context for PowerShell DSC.md) | [Interesting Questions and Answers](./Interesting Questions and Answers.md) | [Walkthrough - **File Server & Share Custom Resource**](./Building and sharing a custom resource walkthrough.md) | [Walkthrough - Deploy TFS 2013 using DSC](./Deploy TFS 2013 using DSC.md) | 

| Appendix [PowerShell 101](./Getting started with PowerShell.md) | [Scenario - Deploy a website using MSDeploy](Scenario - Deploy a website using MSDeploy.md) | [Scenario - Deploying a database using DacPac](./Scenario - Deploying a database using DacPac.md) | [Scenario - TFS 2013 on a single ATDT server](./Scenario - TFS 2013 on a single ATDT server.md) |

# Building and sharing a custom resource walk through

This walk through will show you how to create and deploy a PowerShell Desired State Configuration module, which will create a file share and assign permissions for that file share. A practical use for this could be configuring a drop folder for a build server or a shared folder for specific team members. As a practical matter, there is an xSmbFileShare DSC that are part of the core set of modules.

**>> NOTE >>** Please refer to **Quick Reference Cheat sheet / Posters**, for information on a visual cheat sheet poster that guides you through this and other walk throughs.

## Know what your DSC configuration is going to do

Before authoring configuration scripts, it is critical to understand the resources they will affect. The results of this question will lead to wildly different implementations of the configuration.

Important terminology:

-   **Shared Resource** (i.e. a folder is a resource): A resource accessed by multiple users and processes for purposes which may or may not align with the purposes of the specific DSC configuration being created
-   **Private Resource**: A resource required and accessed only for the purpose for which it is being configured
-   **Module**: In DSC terms a module is a package which contains one or more resources
-   **Resource**: A specific script which performs an action that furthers the configuration of a target system
-   **Configuration**: A single file containing end state configuration of a target system which passes values to one or more DSC Resources

The first question to ask is, “*is this a shared resource or a private resource?*” The answer to this question will affect every piece of script. The rule here is that when modifying a **shared** resource, target a **minimum** configuration, and when modifying a private resource target an **exact** configuration.

What does this mean exactly?

**>> SITUATION >>** In this walk through, the desired actions are to create a shared folder and set certain permissions on it. For argument’s sake, John requires Read permission to the file share. When the configuration runs it is determined, that John has Change permissions. Should John be removed from the Change group and re-assigned to the Read group or is the best approach to say, John is in the Change group which means he has read permissions already, leave the resource alone?.

## Decompose your configuration into the smallest logical steps

Trying to do too much in a configuration becomes problematic from a maintenance perspective and potentially the required number of scripts. Consider the current scenario – to create a file share and set permissions. You can do this in single step but it becomes more complex and is not as flexible.

In a single step process, writing extra code is required to see if the file share exists and then set permissions. In addition, if the user wants to just set permissions and not create a file share at all, they will not have any option to do that. The simplest solution is to provide more choice.

In order to get around this scenario you can create a PowerShell DSC Module with multiple resources and then set the configuration such that the processing of a module is dependent on the processing of another module. This allows you to create re-usable packages where people can pick what they want to configure.

For this walkthrough, the decomposition will require a **CreateFileShare** and **SetSharePermissions** resources in the module.

Once the configuration is decomposed, determine how to use existing PowerShell commands to configure the target system. Knowing this is critical when generating the initial outline of the DSC module, because the script must declare the parameters for the resources. This DSC configuration is going to call the **New-Item**, **Grant-SmbShareAccess**, and **Remove-SmbShareAccess** commands.

## Generating the initial outline

This part of the walkthrough will generate the skeleton structure of the module. Microsoft has created the **xDscResourceDesigner** (x stands for experimental so this is subject to change). It is not required but it makes the generation process much faster. In addition, the use of **Test-xDscResource** and **Test-xDscSchema** are not necessarily required because this generates the correct skeleton automatically.

1. **Start Environment**
	- Download and setup supporting resources, for example [DSC Resource Kit](http://gallery.technet.microsoft.com/scriptcenter/DSC-Resource-Kit-All-c449312d).
2. **Create schema script**
	- Create the [Generate_VSAR_cFileShare_Schema.ps1](./samples/Generate_VSAR_cFileShare_Schema.md) script.
		- the naming convention is “Generate\_” + DSC Module name + “\_Schema.ps1”
		- This file should be version controlled in case it needs to be re-generated or schema changes are required in the future
3. **Run schema script**
	- Run the script
	- The Path argument in the New-xDscResource command determines the output location of the resource.
	- The result of this command is that the following folder and file structure is generated:
		- WindowsPowerShell (folder)
			- Modules (folder)
				- cFileShare (folder)
					- DSCResources (folder)
						- VSAR\_cCreateFileShare (folder)
							- VSAR\_cCreateFileShare.psm1 (file)
							- VSAR\_cCreateFileShare.schema.mof (file)
						- VSAR\_cSetSharePermissions (folder)
							- VSAR\_cSetSharePermissions.psm1 (file)
							- VSAR\_cSetSharePermissions.schema.mof (file)
4. **Create manifest file**
	- To generate this, run the following PowerShell command shown below.
	- This will generate the missing file in the correct location.

		```powershell
    	New-ModuleManifest –Path "%ProgramFiles%\WindowsPowerShell\Modules\cFileShare\cFileShare.psd1"
		```

	**>>> WARNING >>>** As of the time of this writing there is a known bug in the xDscResourceDesigner – it should have output one additional file named [**cFileShare.psd1**](./samples/cFileShare.md) in the cFileShare folder. This will be corrected in a future release if the DSC Resource Kit.

## Understanding Ensure Present and Absent

Before writing the actual resources, it helps to understand **ensure present** and **ensure absent**.

Almost anything on a system – an application, file, registry key, permissions, etc. – may need to be confirmed as existing (**Present**), or explicitly not existing (**Absent**). If a resource exposes **Ensure** as a property, you have control over the existence of that object in the final state of the system. In this example, if the configuration should be **Present** it will create the resource and assign permissions. If the configuration should be **Absent**, it will remove the resource.

There are no specific steps to follow here, but keep in mind that the **Set-TargetResource** and **Test-TargetResource** methods will both have an ‘if…then’ statement to handle this condition.

## Configuring the CreateFileShare resource

The generated output is a set of skeleton files that need some modifications.

The **\*.schema.mof** files and the **\*.psd1** files do not need to be edited (the cFileShare.psd1 may be edited to update version numbers and provide more detailed information but the generated output is perfectly acceptable at this point). This means that the \*.psm1 files do need to be edited. Each psm1 file contains three specific methods:

-   Get-TargetResource
-   Set-TargetResource
-   Test-TargetResource

This section describes each methods use and function. This section describes the edits to both the VSAR\_cCreateFileShare.psm1 and the [VSAR_cSetSharePermissions.psm1](./samplesVSAR_cSetSharePermissions.md) files.


### Get-TargetResource

This method checks to determine the state of the system and returns the key and required data in a hash table.

**>> NOTE >>** The **Get-TargetResource** and the other Set-* and Test-* methods should *never throw an exception* as part of the normal process that is not caught and handled. For example, the code below passes the common parameter –ErrorAction SilentlyContinue to the Get-SmbShare. This is because Get-SmbShare will throw an exception if the share does not exist. If this happens, the configuration will not succeed. However, if Get-SmbShare does throw an exception, the variable *\$shareInfo* will be null. Therefore, checking the value of $shareInfo after this call is made will determine whether the given share exists. A try...catch block can also be used but –ErrorAction SilentlyContinue seems to work best in most cases.

In addition, if the process should *stop because of an error*, throwing an exception is a perfectly acceptable way of managing the situation. It writes Exceptions thrown in this manner to the Desired State Configuration Operational log (discussed in the troubleshooting section below).

Always include verbose statements here so the end user can get an exact description of what is happening and that way if the resource throws an exception they can determine exactly where it threw the exception but they can also see the variables in use along the way.

1. **Implement Get-\* method**
	- Open the generated [VSAR_cCreateFileShare.psm1](./samples/VSAR_cCreateFileShare.md) file Implement Get-* method
	- Implement the **Get-TargetResource** method, using the sample **VSAR_cCreateFileShare Get-TargetResource**.

### Test-TargetResource

The **Test-TargetResource** method determines whether the state of the system matches the configuration requested. For example, the CreateFileShare resource needs to create a share.

The **Get-TargetResource** returned a hash table saying that the share does or does not exist simply by looking for the share. The **Test-TargetResource** looks at it in the context of the configuration you requested. If you requested that the file share be present, then the method will return true if it does and false otherwise. It is not simply getting the state of the system it is returning whether the system matches your desired configuration.

1. **Implement Test-\* method**

	- Implement the **Test-TargetResource** method, using the sample **VSAR\_cCreateFileShare Test-TargetResource**.
	- Design the Test-TargetResource to run **quickly**. Each time DSC scans the system for drift, it runs the Test-TargetResource, so design it to execute quickly, and have the least performance impact on the system possible.

### Set-TargetResource

**Set-TargetResource** does the work of getting the system into the desired configuration. Remember to take into account the Present and Absent aspects of the Ensure parameter.

**>>> WARNING >>>** This gets into a very grey area when dealing with a shared resource. In this case, ensuring a file share is absent means that there is only one recourse – removing the file share. This is somewhat in conflict with the statements made earlier regarding a minimum state versus an absolute state. One important thing to note is that when pushing configurations to a target machine, you can only push (or pull) one configuration per server.

In other words, it is not possible for two parties to create different configurations that might overwrite each other – all of the configurations for a single machine must be in a single file – thoroughly review the configuration file and version control it. We cover the configuration file later in this document.

1. **Implement Set-\* method**
	- Implement the **Set-TargetResource** method, using the sample **VSAR\_cCreateFileShare Set-TargetResource**
2. **Save changes**
	- Save the modified the generated VSAR\_cCreateFileShare.psm1 file.

Questions:
- Why is there no error handling around creating the file share?
- What if the file share already exists?
- Why does the code not check to see if the file share exists before trying to create it?

The answer is the **Test-TargetResource** method. Based on the results of the **Test-TargetResource** method, it may not even call the **Set-TargetResource** method. If the configuration calls for the file share to exist and it does, then the configuration skips the **Set-TargetResource** method – the system is already in the desired state. Therefore, the fact that this code is being called, by definition means that the share does not already exist.

## Configuring the SetSharePermission resource

1. **Open resource file**
	- Open the generated [**VSAR_cSetSharePermission.psm1**](./samples/VSAR_cSetSharePermission.md) file
2. **Implement methods**
	- Get-Target method
	- Test-Target method
	- Set-Target method
3. **Save changes**
	- Save the modified generated VSAR\_cCreateFileShare.psm1 file.

At this point, the DSC Module and Resources are complete and ready to deploy.

## Testing the Resources
We are big fans of unit testing, quality and “doing it right the first time.” In line with that, it is appropriate to unit test resources as best as can be done. Scripts that configure system resources require a bit more time and energy to unit test but it is well worth it. The major reason for this is that it is virtually impossible to mock these unit tests. How you perform unit testing is entirely up to you, as long as you do unit testing.

You can find various resources on the web for unit testing PowerShell scripts – they may or may not work with a given resource. This walkthrough shows a manual process for creating the unit tests. Alternatively, the completed unit test files are included in the download.

These files are [VSAR_cCreateFileShare_UnitTests.ps1](./samples/VSAR_cCreateFileShare_UnitTests.md) and [VSAR_cSetSharePermissions_UnitTests.ps1](./samples/VSAR_cSetSharePermissions_UnitTests.md).

This is more an “anatomy” of a unit test than a walkthrough.

```powershell
#Unit tests for VSAR_cCreateFileShare
Import-Module "%ProgramFiles%\WindowsPowerShell\Modules\cFileShare\DSCResources>\VSAR_cCreateFileShare"
#Variable Declarations
$ShareName = "TestShare"
$Path = "C:\Test"
$PassCounter = 0
$FailCounter = 0

##############################
#
# Tests for Get-TargetResource
#
##############################

#####################################################
# Test #1 - If share exists, Ensure returns "Present"
#####################################################

#Setup for Test #1
$SetupResult = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if (!$SetupResult)
{
	New-SmbShare -Path $Path -Name $ShareName
}

$Result = Get-TargetResource -ShareName $ShareName -Path $Path
if ($Result.Ensure -ne "Present")
{
	$FailCounter += 1
	"Test 1 Failed"
}
else
{
	$PassCounter += 1
	"Test 1 Passed"
}
```

### Overview of the unit test sample script

- The first line clearly defines what this file tests – a good rule of thumb is one file per resource
- Import the resource which is to be tested
- Declare any variables which will be used throughout the tests
	- The Pass/Fail counters are used to provide a summary at the end of the test
- Test each section of the resource separately – as noted here this test is part of the Get-TargetResource tests
- Comment the test with a number and what is being tested
	- Note that this can also be done with each test being in a separate method and the method names providing the detail as is done with standard unit tests
- Perform any test setup required and mark that section as the setup section
- Run the test
- Examine the result and increment the appropriate counter and output the result

The output of the test run, using the [VSAR_cCreateFileShare_UnitTests.ps1](./samples/VSAR_cCreateFileShare_UnitTests.md) script, should be as
follows:

```console
	PS C:\windows\system32> C:\Users\DemoUser\Desktop\DSC Walkthrough Final Files\VSAR_cCreateFileShare_UnitTests.ps1
	
	Test 1 Passed
	Test 2 Passed
	Test 3 Passed
	Test 4 Passed
	Test 5 Passed
	Test 6 Passed
	Passed: 6, Failed: 0
	
	PS C:\windows\system32>
```

**>> NOTE >>** These tests should always pass no matter how many times you run them, since they perform their own setup.

**>> NOTE >>** Write the DSC configuration and perform these tests on system as similar as possible to the target systems.

**>> NOTE >>** Run these tests as an Administrator to ensure they will not fail. For example, this test creates a folder in the root of the c drive – this requires administrative permissions and the tests will fail if run as a regular user.

## Creating the configuration

**>> NOTE >>** This section assumes that you have a pull server and a target server already configured. See [Push and Pull Configuration Modes](http://blogs.msdn.com/b/powershell/archive/2013/11/26/push-and-pull-configuration-modes.aspx) and [Building a Desired State Configuration Pull Server](http://powershell.org/wp/2013/10/03/building-a-desired-state-configuration-pull-server/) for more information on push and pull servers.

The configuration tells the target server what configuration it needs to be in and therefore passes values to the previously created PowerShell DSC Resources.

1. **Create config script**
	- Start the PowerShell ISE and enter the following in a new script tab alternatively, use the provided file and make changes according to the highlighted areas below as discussed in the following section):

		```powershell
	    Configuration CreateDropShare
	    {
	        Import-DscResource -ModuleName cFileShare
	        Node appserver
	        {
	            VSAR_cCreateFileShare CreateShare
	            {
	                 ShareName= 'DropShare'
	                 Path = 'C:\DropShare'
	                 Ensure   = 'Present'
	            }
	            VSAR_cSetSharePermissions SetPermissions
	            {
	                 ShareName  = 'DropShare'
	                 DependsOn  = '[cCreateFileShare]CreateShare'
	                 Ensure	= 'Present'
	                 FullAccessUsers= @(‘dx\jeff’)
	                 ChangeAccessUsers  = @(‘dx\steven’)
	                 ReadAccessUsers= @(‘dx\shad’)
	            }
	        }
	    }
	    CreateDropShare
		```

	- A brief tour of some of the information present in the configuration file:
		- **CreateDropShare** is the name given to the configuration – it can be anything you want and just serves as a way to identify it
		- **Import-DscResource** imports the previously created module and all resources
		- The **Node** line specifies the target system that will be configured – in this case the server name is called **appserver**
		- **VSAR\_cCreateFileShare** is the name of the Resource this section will pass configuration information too. You must give the Resource a name, for example **CreateShare,** although the name can actually be anything.

		**>> NOTE >>** With your cursor on the resource name (VSAR\_cCreateFileShare), pressing **Ctrl+SpaceBar** will show the list of parameters for the resource.

		**>> NOTE >>** When entering parameter names in this section, typing in any letter and pressing **Ctrl+SpaceBa**r will bring up the IntelliSense list of parameters to select (for instance, type ‘a’ and **Ctrl+SpaceBar** and you can select ShareName).

	- In the **SetPermissions** section **DependsOn** absolutely ensures that the configuration section that this section relies on will be configured first.
	- The last line, **CreateDropShare** simply instructs the DSC engine to run the configuration in order to create (not perform) a configuration.
2. **Set working directory**
	- Change the working directory to another location (the default is C:\\Windows\\System32, in this example the directory is C:\\users\\[username]\\desktop\\dsc)
3. **Save script**
	- As a best practice, save the above configuration script to a file and version control it since it represents the formatted configuration of the server in question.
4. **Run script**
	- Once the file is saved, run it and verify that the output matches the following:

		```powershell
	    PS C:\Users\[username]\Desktop\DSC> .\CreateDropShare.ps1
	    Directory: C:\Users\[username]\Desktop\DSC\CreateDropShare
	    ModeLastWriteTime Length Name
	    ----------------- ------ ----
	    -a--- 8/14/2014   2:43 PM   2358 appserver.mof
		```

5. **Verify results**
	- Verify that the result is a new folder called **CreateDropShare**, which contains a single file – **appserver.mof**.

		**>> NOTE >>** The output file name will be [server name].mof not appserver.mof unless this is the name of the server.

6. **Connect to remote server**
	- The configuration has been generated, but some additional steps are required.
	- The unique identifier of the target system needs to be determined. While appserver is the name of the server, it is not guaranteed to be unique.
	- Each server is identified by a GUID that is created when you configure the target server as the target of a pull server.
	- Connect to the remote server with RDP or a remote PowerShell session.
7. **Determine server GUID**
	- Once connected to the remote system, open a PowerShell prompt and run **Get-DscLocalConfigurationManager**.
	- The results should look like the following if you configure everything correctly. The import part of this is the ConfigurationID which is needed to finalize the configuration:

		```powershell
	    [dxdemo.cloudapp.net]: PS C:\Users\jeff.DX\Documents> Get-DscLocalConfigurationManager
	    AllowModuleOverwrite: False
	    CertificateID   :
	    ConfigurationID : 1f970101-df17-444f-914d-ac6cb5f246cf
	    ConfigurationMode   : ApplyOnly
	    ConfigurationModeFrequencyMins  : 30
	    Credential  :
	    DownloadManagerCustomData   : {MSFT_KeyValuePair (key = "ServerUrl"), 
	       MSFT_KeyValuePair (key = "AllowUnsecureConnection")}
	    DownloadManagerName : WebDownloadManager
	    RebootNodeIfNeeded  : False
	    RefreshFrequencyMins: 15
	    RefreshMode : Pull
	    PSComputerName
		```

	-**>> NOTE >>** Your GUID will be different. Please use that GUID in place of this one!

8. **Rename schema file**
	- Rename the appserver.mof file 1f970101-df17-444f-914d-ac6cb5f246cf.mof
	- Format is: ([GUID].mof)
9. **Run command**
	- In PowerShell, navigate to the previously created CreateDropShare folder and run the following command:

		```powershell
	    New-DSCCheckSum .\1f970101-df17-444f-914d-ac6cb5f246cf.mof
		```

	- This will generate a second file in the folder with the name 1f970101-df17-444f-914d-ac6cb5f246cf.mof.checksum ([GUID].mof.checksum).

The configuration is complete. It is now ready to deploy and test.

**>> NOTE >>** As you start assigning GUID’s to various servers, it’s helpful to create a central repository of server names and GUID’s to make it easier and faster to look up – especially as you may not have permission to each server.

## Deploying your custom DSC resource and configuration

Deploying the PowerShell DSC resource involves not only deploying the configuration but the resource itself. The resource, when deployed to the pull server is in a zip format and both the resource and you can simply copy the configuration to the pull server.

1. **Navigate to modules folder**
	- Before deploying a custom resource, it needs to be zipped and a checksum created for the zipped file.
  Navigate to modules folder

	**>>> WARNING >>>** Because of a peculiar bug in the current version of DSC, resources can only be zipped in the manner shown in this walkthrough – all other attempts will result in failures.

	- Navigate to the **%ProgramFiles%\\WindowsPowerShell\\Modules** folder
**2. Zip module**
	- Right-click the **cFileShare** folder and select **Send To \> Compressed (zipped) folder**
  Zip module
	- You must run as an admin in order to create this file in this folder.
	- A save location prompt will be displayed and it defaults to the desktop which poses no problem.
3. **Rename zip file**
	- Rename the zip file **cFileShare\_1.0.zip**
	- The DSC engine requires this particular naming convention. The version number at the end of this file must match the module version number in the [**VSAR_cFileShare.psd1**](./samples/VSAR_cFileShare.md) file
4. **Open PowerShell window**
	- Open a PowerShell window and navigate to the location of the zip file
5. **Generate checksum**
	- Enter the command New-DSCChecksum **.\\cFileShare\_1.0.zip**
	- This will result in a new file being created in the same folder named **cFileShare\_1.0.zip.checksum**
	- At this point the module and configuration are ready to be deployed to the pull server.
6. **Remote into pull server**
	- Remote into the pull server and navigate to **%ProgramFiles%\\WindowsPowerShell\\DscService\\Modules** folder
	- Copy the **cFileShare\_1.0.zip** and **cFileShare\_1.0.zip.checksum** to this folder
7. **Copy custom resource to pull server**
	- Copy the **[GUID].mof** and **[GUID].mof.checksum** file to the **%ProgramFiles%\\WindowsPowerShell\\DscService\\Configuration** folder.
	- The configuration has now been deployed to the pull server and by default will be picked up within 30 minutes (this is the ConfigurationModeFreq
	- uencyMin value from above)

## Executing your configuration on the target server 

Frequently when testing, waiting 30 minutes for a configuration to kick off is too long. You can manually kick off the configuration manually for a “quick” test. We recommend that you use *Push* mode to do testing and once you have validated the config, switch to *Pull* mode.

**>> WARNING >>** Do not run Start-DSCConfiguration from the pull server. Doing this will change the state of the target server from pull to push which means it will no longer poll the pull server for updates (if it is configured in this way).

1. **Logon to target server**
	- Log on to the target server.
	- Open a **PowerShell prompt** (this can also be accomplished through a remote PowerShell session)
2. **Invoke CimMethod**
	- Run the following command:

		```powershell
		Invoke-CimMethod -ComputerName appserver -Namespace root/microsoft/windows/desiredstateconfiguration
		                                         -Class MSFT_DscLocalConfigurationManager 
		                                         -MethodName PerformRequiredConfigurationChecks
		                                         -Arguments @{Flags = [Uint32]1} -Verbose  
	 	```

	- This command forces the target server to verify its configuration against the pull server. When it finds a change, it will run the configuration. The resulting message should look like the following:

		```powershell
		PS C:\Users\jeff.DX\Desktop> Invoke-CimMethod -ComputerName appserver 
		                                              -Namespace root/microsoft/windows/desiredstateconfiguration `
		                                              -Class MSFT_DscLocalConfigurationManager -MethodName PerformRequiredConfigurationChecks 
		VERBOSE: Performing the operation "Invoke-CimMethod: PerformRequiredConfigurationChecks" on target "MSFT_DscLocalConfigurationManager.”
		VERBOSE: Perform operation 'Invoke CimMethod' with following parameters, ''methodName' = PerformRequiredConfigurationChecks,
								   'className' = MSFT_DscLocalConfigurationManager,'namespaceName' = root/microsoft/windows/desiredstateconfiguration'.
		VERBOSE: An LCM method call arrived from computer APPSERVER with user sid S-1-5-21-1100927510-3167963274-3869165624-500.
		VERBOSE: [APPSERVER]:                            [] Starting consistency engine.
		VERBOSE: [APPSERVER]:                            [] Consistency check completed.
		                                                 ReturnValue PSComputerName
		                                                 ----------- --------------
		                                                 0           appserver     
		VERBOSE: Operation 'Invoke CimMethod' complete. 
		```
		
3. **Verify**
	- Verify that the **DropShare** folder was created and all permissions assigned correctly

## Troubleshooting

### What to do if you get an error message

Inevitably, errors will occur when deploying to the target server. This is a quick bit of help for what to do.

1. ** Review results**
	- On the target server, when executing the command in step two above you may get a result that looks like the following:

		```powershell
		PS C:\Users\jeff.DX\Desktop> Invoke-CimMethod -ComputerName appserver 
		                                              -Namespace root/microsoft/windows/desiredstateconfiguration
		                                              -Class MSFT_DscLocalConfigurationManager 
		VERBOSE: Performing the operation "Invoke-CimMethod: PerformRequiredConfigurationChecks" on target "MSFT_DscLocalConfigurationManager.”
		VERBOSE: Perform operation 'Invoke CimMethod' with following parameters, ''methodName' = PerformRequiredConfigurationChecks,'className' = MSFT_DscLocalConfigurationManager,
		'namespaceName' = root/microsoft/windows/desiredstateconfiguration'.
		VERBOSE: An LCM method call arrived from computer APPSERVER with user sid S-1-5-21-1100927510-3167963274-3869165624-500.
		Invoke-CimMethod : The SendConfigurationApply function did not succeed.
		At line:1 char:1
		+ Invoke-CimMethod -ComputerName appserver -Namespace root/microsoft/windows/desir ...
		+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
		+ CategoryInfo          : NotSpecified: (root/microsoft/...gurationManager:String) [Invoke-CimMethod], CimException
		+ FullyQualifiedErrorId : MI RESULT 1,Microsoft.Management.Infrastructure.CimCmdlets.InvokeCimMethodCommand
		 PSComputerName        : appserver
		VERBOSE: Operation 'Invoke CimMethod' complete.
		```

	- On its face, it is a particularly unhelpful message as nothing tells you what is wrong.
2. **Open Event Viewer**
	- Expand the **Event Viewer \> Applications and Services Log \> Desired State Configuration**.
	- Select the **Operational** log (at this time it is the only log there)
3. **Review Log**
	- When selecting the Operational log, for each exception that occurred you will see four error entries.
	- The bottom (first) error in the list is the only that concerns troubleshooting a failed configuration deployment.
4. **Review Sample Error**
	- When running this deployment, I purposely entered an invalid username (one that was not in active directory) and the error log showed the following:

		```powershell
		Job {807B3C9E-603E-4B43-AF20-C3F3710BEBE3} : 
		This event indicates that a non-terminating error was thrown when DSCEngine was executing Set-TargetResource on VSAR_cSetSharePermissions provider. 
		FullyQualifiedErrorId is Windows System Error 1332, Grant-SmbShareAccess. ErrorMessage is No mapping between account names and security IDs was done.
		```
		
	- This error is straightforward – there is a problem in the **VSAR\_cSetSharePermissions** resource and the error is with the Grant-SmbShareAccess.
	- It happens to be that “No mapping between account names…” is generated when an invalid ID is provided.
	- However, the error does not tell you which ID was incorrect.
	- To fix it, look at the DropShare folder, which was created, and examine the permissions.
	- The configuration is run in order to it is easy to look down the list of already configured users and figure out which one failed.
	- Once you have identified the correct account and fixed it, fix the configuration file, regenerate it, and re-perform the steps from generating the Configuration section onward.
	- After the configuration is re-invoked everything will be configured correctly.

## Useful Nuggets

|Command|Usage|
|-------|-----|
|xDscResourceDesigner resource|Generate skeleton of module structure|
|Get-DscLocalConfigurationManager|Used to determine server GUID|
|New-DSCChecksum|Generate checksum|
|Invoke-CimMethod|Force a configuration verification|
