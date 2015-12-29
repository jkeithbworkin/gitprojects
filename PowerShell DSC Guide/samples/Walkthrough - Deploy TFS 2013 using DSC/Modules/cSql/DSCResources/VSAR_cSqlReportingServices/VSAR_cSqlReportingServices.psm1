#
# cSQLReportingServices: DSC resource to install Sql Server Enterprise version.
# Based on the following TechNet article: http://technet.microsoft.com/en-us/library/ms144259(v=sql.110).aspx#Role
# Reference for SSRS configuration is: http://technet.microsoft.com/en-us/library/ms154648(v=sql.110).aspx, additional material here: http://social.technet.microsoft.com/Forums/en-US/b227af28-d8af-4bde-87c1-8110c5c82485/how-to-automate-ssrs-install-and-configuration?forum=sqlreportingservices
#


#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
    [OutputType([Hashtable])]
    param
    (	
        [parameter(Mandatory)] 
        [string] $InstanceName = "MSSQLSERVER",

        [parameter(Mandatory)]
        [string] $ServiceAccountName
    )

    $list = Get-Service -Name ReportServer -ErrorAction:SilentlyContinue # TODO: check for non-default instance name
    $retInstanceName = $null

    if ($list -ne $null)
    {
        $retInstanceName = $InstanceName
    }

    if ($retInstanceName -ne $null)
    {
        $rsConfig = Get-ReportingServicesConfigObject $InstanceName

        if ($rsConfig.DatabaseServerName -ne "")
		{
		    $SqlServerInstance = $rsConfig.DatabaseServerName
			if (!$SqlServerInstance.Contains("\"))
			{
			    $SqlServerInstance += "\DEFAULT"
			}

	        Write-Debug "Checking existence of $($returnValue.InstanceName) is $($returnValue.Ensure) and has service account $($returnValue.ServiceAccountName)"
		    if (!(Test-Database $SqlServerInstance "ReportServer"))
			{
                $returnValue = @{
                    InstanceName = $retInstanceName
                    Ensure = "DBMissing"
					ServiceAccountName = $rsConfig.WindowsServiceIdentityActual
                }
			}
			else
			{
                $returnValue = @{
                    InstanceName = $retInstanceName
                    Ensure = "Present"
					ServiceAccountName = $rsConfig.WindowsServiceIdentityActual
                }
			}
		}
		else
		{
            $returnValue = @{
                InstanceName = $retInstanceName
                Ensure = "Installed" # ie installed but not configured
 				ServiceAccountName = $rsConfig.WindowsServiceIdentityActual
           }
		}
    }
    else
    {
        $returnValue = @{
            InstanceName = $retInstanceName
            Ensure = "Absent"
			ServiceAccountName = ""
        }
    }

	Write-Debug "Reporting Services instance $($returnValue.InstanceName) is $($returnValue.Ensure) and has service account $($returnValue.ServiceAccountName)"

    return $returnValue
}


#
# The Set-TargetResource cmdlet.
#
function Set-TargetResource
{
    param
    (	
        [parameter(Mandatory)] 
        [string] $InstanceName = "MSSQLSERVER",

        [parameter(Mandatory)]
        [string] $ServiceAccountName,
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

		[PSCredential] $InstallerCredential,

        [System.String]
        $InstanceDirectory = "",

        [ValidateNotNull()]
        [PSCredential]
        $ServiceAccountPassword,
        
        [ValidateSet("SharePoint", "Native")]
        [System.String]
        $Mode = "Native",

		[ValidateNotNullOrEmpty()]
        [string] $SqlServerInstance,
        
        [string] $LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    if ($Ensure -ne "Present")
    {
        throw "Uninstall not supported"
    }

	if ((Test-IsDomainAccount $ServiceAccountPassword) -and $InstallerCredential -eq $null)
	{
	    throw "Installer credential must be supplied if the service account is a domain account"
	}

	if ([string]::IsNullOrEmpty($LogPath))
	{
        $LogPath = Join-Path $env:SystemDrive -ChildPath "Logs"
	}

    if (!(Test-Path $LogPath))
    {
        New-Item $LogPath -ItemType Directory
    }

    $info = Get-TargetResource -InstanceName $InstanceName -ServiceAccountName $serviceAccountName

	if ($info.Ensure -eq "Absent")
	{
	    Install-ReportingServices $InstallerCredential $InstanceName $InstanceDirectory $ServiceAccountPassword $Mode $LogPath $SourcePath $SourcePathCredential
	}
	elseif ($info.ServiceAccountName -ne $ServiceAccountName)
	{
	    Set-ReportingServicesServiceAccount $InstallerCredential $InstanceName $ServiceAccountPassword
	}
	elseif ($info.Ensure -ne "Present")
	{
	    Configure-ReportingServices $InstanceName $SqlServerInstance $ServiceAccountPassword
	}
}

#
# The Test-TargetResource cmdlet.
#
function Test-TargetResource
{
    [OutputType([Boolean])]
    param
    (	
        [parameter(Mandatory)] 
        [string] $InstanceName = "MSSQLSERVER",

        [parameter(Mandatory)]
        [string] $ServiceAccountName,
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

		[PSCredential] $InstallerCredential,

        [System.String]
        $InstanceDirectory = "",
        
        [ValidateNotNull()]
        [PSCredential]
        $ServiceAccountPassword,
        
        [ValidateSet("SharePoint", "Native")]
        [System.String]
        $Mode = "Native",

		[ValidateNotNullOrEmpty()]
        [string] $SqlServerInstance,
        
        [string] $LogPath,

        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    $info = Get-TargetResource -InstanceName $InstanceName -ServiceAccountName $ServiceAccountName
    
    return ($info.InstanceName -eq $InstanceName -and $info.Ensure -eq $Ensure -and $info.ServiceAccountName -eq $ServiceAccountName)
}

function Get-ReportingServicesConfigObject([string] $InstanceName)
{
    $wmiName = (Get-WmiObject –namespace root\Microsoft\SqlServer\ReportServer  –class __Namespace).Name
    $rsConfig = Get-WmiObject –namespace "root\Microsoft\SqlServer\ReportServer\$wmiName\v11\Admin" -class MSReportServer_ConfigurationSetting  -filter "InstanceName='$InstanceName'"
	return $rsConfig
}

function Install-ReportingServices
{
    param
    (
	    [PSCredential] $InstallerCredential,
        [string] $InstanceName,
        [string]  $InstanceDirectory,
        [PSCredential] $ServiceAccount,
        [string] $Mode,
        [string] $LogPath,
        [string] $SourcePath,
        [PSCredential] $SourcePathCredential
    )

	Write-Debug "Installing Reporting Services"
    $logOutFile = Join-Path $LogPath -ChildPath "sqlReportingServicesInstall-log.txt"
    $logErrFile = Join-Path $LogPath -ChildPath "sqlReportingServicesInstallError-log.txt"

    $features = "RS"

    $cmd = Join-Path $SourcePath -ChildPath "Setup.exe"

    $arguments = @()
	$arguments += "/Q"
	$arguments += "/ACTION=Install"
	$arguments += "/IACCEPTSQLSERVERLICENSETERMS"
	$arguments += "/ENU"
	$arguments += "/UpdateEnabled=false"
	$arguments += "/IndicateProgress"
	if (![string]::IsNullOrEmpty($InstanceDirectory))
	{
	    $arguments += "/INSTANCEDIR='$InstanceDirectory'"
	}
    $arguments += "/FEATURES=$features"
    $arguments += "/INSTANCENAME=$InstanceName"
    if ($Mode -eq "SharePoint")
    {
        $arguments += "/RSINSTALLMODE=SharePointFilesOnlyMode"
    }
    else
    {
        $arguments += "/RSINSTALLMODE=DefaultNativeMode"
    }

	if (Test-IsDomainAccount $ServiceAccount)
	{
	    $arguments += "/RSSVCACCOUNT=`"NT AUTHORITY\Network Service`"" # this is changed later
	}
	else
	{
        $arguments += "/RSSVCACCOUNT=`"$($ServiceAccount.UserName)`""
        $arguments += "/RSSVCPASSWORD=$($ServiceAccount.GetNetworkCredential().Password)"
	}

    NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Present"
    try
    {
        Write-Debug "Installing SQL Server Reporting Services with the following command: $cmd $arguments"
        Start-Process $cmd -ArgumentList $arguments -Wait -NoNewWindow -RedirectStandardOutput $logOutFile -RedirectStandardError $logErrFile

        $setupResult = Test-InstallResult
        if ($setupResult -eq "0x00000000")
        {
            $global:DSCMachineStatus = 1;
        }
        else
        {
            throw "SQL Server Reporting Services installation failed with result code: $setupResult"
        }
    }
    finally
    {
        NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Absent"
    }
}

function Set-ReportingServicesServiceAccount
{
    param
    (
	    [PSCredential] $InstallerCredential,
        [string] $InstanceName,
        [PSCredential] $ServiceAccount
    )

	Write-Debug "Setting Reporting Services Service Account"
    Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $InstallerCredential -ScriptBlock `
	{
	    param ($instanceName, $ServiceAccount) 
        $wmiName = (Get-WmiObject –namespace root\Microsoft\SqlServer\ReportServer  –class __Namespace).Name
        $rsConfig = Get-WmiObject –namespace "root\Microsoft\SqlServer\ReportServer\$wmiName\v11\Admin" -class MSReportServer_ConfigurationSetting  -filter "InstanceName='$InstanceName'"
	    $rsConfig.SetWindowsServiceIdentity($false, $ServiceAccount.UserName, $ServiceAccount.GetNetworkCredential().Password)
	} -ArgumentList $instanceName, $ServiceAccount

	Write-Debug "Finished setting Reporting Services Service Account"
    $global:DSCMachineStatus = 1;
}

function Configure-ReportingServices([string] $instanceName, [string] $SqlServerInstance, [PSCredential] $ServiceAccount)
{
    # TODO: Only tested for native mode, needs to be made to work in SharePoint mode.
	Write-Debug "Configuring Reporting Services"

    $rsConfig = Get-ReportingServicesConfigObject $instanceName

    # Create the database. Can't use SQLPS here as it has a .NET 2.0 dependency in Invoke-SqlCmd
	$scriptPath = "$env:TEMP\ReportServer.sql"
	$rsConfig.GenerateDatabaseCreationScript("ReportServer", 1033, $false).Script | Out-File $scriptPath # TODO: only does native mode script here
	& sqlcmd.exe -E -i "$scriptPath"
	Remove-Item $scriptPath

	$scriptPath = "$env:TEMP\ReportServerRights.sql"
	$rsConfig.GenerateDatabaseRightsScript($ServiceAccount.UserName, "ReportServer", $false, $true).Script | Out-File $scriptPath
	& sqlcmd.exe -E -i "$scriptPath"
	Remove-Item $scriptPath

	if ($rsConfig.VirtualDirectoryReportServer -eq "")
	{
        Check-HResult $rsConfig.SetVirtualDirectory("ReportServerWebService","ReportServer",0)
	}

	if ($rsConfig.VirtualDirectoryReportManager -eq "")
	{
        Check-HResult $rsConfig.SetVirtualDirectory("ReportManager","Reports",0)
	}

	if (!$rsConfig.ListReservedUrls().Application.Contains("ReportServerWebService"))
	{
	    Check-HResult $rsConfig.ReserveURL("ReportServerWebService", "http://+:80", 0)
	}

	if (!$rsConfig.ListReservedUrls().Application.Contains("ReportManager"))
	{
	    Check-HResult $rsConfig.ReserveURL("ReportManager", "http://+:80", 0)
	}

	if ($rsConfig.DatabaseServerName -eq "")
	{
        Check-HResult $rsConfig.SetDatabaseConnection($SqlServerInstance, "ReportServer", 2, $ServiceAccount.UserName, $ServiceAccount.GetNetworkCredential().Password)
	}

    # force refresh
    Check-HResult $rsConfig.SetServiceState($false,$false,$false)
    Restart-Service $rsConfig.ServiceName
    Check-HResult $rsConfig.SetServiceState($true,$true,$true)
}

function Check-HResult ($result)
{
    if ($result -ne $null)
	{
        if ($result.HResult -ne 0)
	    {
	        throw "Failed to configure SQL Server Reporting Services, reason: $($result.Error)"
		}
	}
}

function NetUse
{
    param
    (	   
        [parameter(Mandatory)] 
        [string] $SharePath,
        
        [PSCredential]$SharePathCredential,
        
        [string] $Ensure = "Present"
    )

    if ($null -eq $SharePathCredential)
    {
        return;
    }

	$smbPath = $SharePath.Split("\")[0..3] -join "\"
    if ($Ensure -eq "Absent")
    {
        Write-Debug -Message "Disconnecting from share $smbPath ..."
        Remove-SmbMapping -RemotePath $smbPath
    }
    else 
    {
        Write-Debug -Message "Connecting to share $smbPath ..."
        $cred = $SharePathCredential.GetNetworkCredential()
        $pwd = $cred.Password 
        $user = $cred.Domain + "\" + $cred.UserName
		New-SmbMapping -RemotePath $smbPath -UserName $user -Password $pwd
    }
}

function Test-Database([string]$instanceName, [string]$DatabaseName)
{
    $exists = $false
    try 
    {
        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
   
        $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instanceName)
   
        $exists = $server.Databases[$DatabaseName] -ne $null
    }
   catch 
   {
       Write-Error "Failed to connect to $sqlServer"
   }

   Write-Debug -Message "Existence on $instanceName of $DatabaseName is $exists"
   return $exists
}

function Test-InstallResult
{
    $statusLine = Get-Content $env:TEMP\sqlsetup.log -Encoding Unicode | Where-Object { $_.Contains("Setup closed with exit code:") }
    $parts = $statusLine.Split(" ")
    $returnCodeString = $parts[$parts.Length - 1]
    return $returnCodeString
}

function Test-IsDomainAccount([PSCredential] $account)
{
    $Account.GetNetworkCredential().Domain -ne "NT AUTHORITY"
}

Export-ModuleMember -Function *-TargetResource
