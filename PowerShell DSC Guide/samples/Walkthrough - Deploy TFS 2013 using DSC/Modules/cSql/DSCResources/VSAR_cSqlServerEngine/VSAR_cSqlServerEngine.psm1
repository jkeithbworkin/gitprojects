#
# cSQLServerEngine: DSC resource to install Sql Server Enterprise version.
# Based on the following TechNet article: http://technet.microsoft.com/en-us/library/ms144259(v=sql.110).aspx#Role
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
        [string] $InstanceName = "MSSQLSERVER"
    )

    $list = Get-Service -Name MSSQL*
    $retInstanceName = $null

    if ($InstanceName -eq "MSSQLSERVER")
    {
        if ($list.Name -contains "MSSQLSERVER")
        {
            $retInstanceName = $InstanceName
        }
    }
    elseif ($list.Name -contains $("MSSQL$" + $InstanceName))
    {
        $retInstanceName = $InstanceName
    }

    if ($retInstanceName -ne $null)
    {
        $returnValue = @{
            InstanceName = $retInstanceName
            Ensure = "Present"
        }
    }
    else
    {
        $returnValue = @{
            InstanceName = $retInstanceName
            Ensure = "Absent"
        }
    }
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

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $InstanceDirectory = "",
        
        [System.String]
        $AgentServiceAccount = "NT AUTHORITY\Network Service",

        [ValidateSet("Automatic", "Disabled", "Manual")]
        [System.String]
        $AgentServiceStartupType = "Manual",
        
        [System.String]
        $SqlServiceAccount = "NT AUTHORITY\Network Service",
        
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SysAdminAccount,
        
        [System.String]
        $TempDBDataDirectory,
        
        [System.String]
        $TempDBLogDirectory,
        
        [System.String]
        $UserDBDataDirectory,
        
        [System.String]
        $UserDBLogDirectory,
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $FullText = "Present",
        
        [string] $LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    if ($Ensure -ne "Present")
    {
        throw "Uninstall not supported"
    }

	if ([string]::IsNullOrEmpty($LogPath))
	{
        $LogPath = Join-Path $env:SystemDrive -ChildPath "Logs"
	}

    if (!(Test-Path $LogPath))
    {
        New-Item $LogPath -ItemType Directory
    }

    $logFile = Join-Path $LogPath -ChildPath "sqlEngineInstall-log.txt"

    $features = "SQLEngine"
    if ($FullText -eq "Present")
    {
        $features += ",FullText"
    }

    $cmd = Join-Path $SourcePath -ChildPath "Setup.exe"

    $cmd += " /Q /ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /ENU /UpdateEnabled=false /IndicateProgress "
	if (![string]::IsNullOrEmpty($InstanceDirectory))
	{
	    $cmd += " /INSTANCEDIR='$InstanceDirectory' "
	}
    $cmd += " /FEATURES=$features "
    $cmd += " /INSTANCENAME=$InstanceName "
    $cmd += " /AGTSVCACCOUNT='$AgentServiceAccount'  "
	$cmd += " /AGTSVCSTARTUPTYPE=$AgentServiceStartupType "
    $cmd += " /SQLSVCACCOUNT='$SqlServiceAccount' "
    $cmd += " /SQLSYSADMINACCOUNTS='$SysAdminAccount' "
    if (![string]::IsNullOrEmpty($TempDBDataDirectory))
    {
        $cmd += " /SQLTEMPDBDIR='$TempDBDataDirectory' "
    }
    if (![string]::IsNullOrEmpty($TempDBLogDirectory))
    {
        $cmd += " /SQLTEMPDBLOGDIR='$TempDBLogDirectory' "
    }
    if (![string]::IsNullOrEmpty($UserDBDataDirectory))
    {
        $cmd += " /SQLUSERDBDIR='$UserDBDataDirectory' "
    }
    if (![string]::IsNullOrEmpty($UserDBLogDirectory))
    {
        $cmd += " /SQLUSERDBLOGDIR='$UserDBLogDirectory' "
    }
    $cmd += " > $logFile 2>&1 "

    NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Present"
    try
    {
        Write-Debug "Installing SQL Server Engine with the following command: $cmd"
        Invoke-Expression $cmd
        $setupResult = Test-InstallResult
        if ($setupResult -eq "0x00000000")
        {
            $global:DSCMachineStatus = 1;
        }
        else
        {
            throw "SQL Server Engine installation failed with result code: $setupResult"
        }
    }
    finally
    {
        NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Absent"
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
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $InstanceDirectory = "",

        [System.String]
        $AgentServiceAccount = "NT AUTHORITY\Network Service",

        [ValidateSet("Automatic", "Disabled", "Manual")]
        [System.String]
        $AgentServiceStartupType = "Manual",
        
        [System.String]
        $SqlServiceAccount = "NT AUTHORITY\Network Service",
        
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SysAdminAccount,
        
        [System.String]
        $TempDBDataDirectory,
        
        [System.String]
        $TempDBLogDirectory,
        
        [System.String]
        $UserDBDataDirectory,
        
        [System.String]
        $UserDBLogDirectory,
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $FullText = "Present",
        
        [string] $LogPath,

        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    $info = Get-TargetResource -InstanceName $InstanceName
    
    return ($info.InstanceName -eq $InstanceName -and $info.Ensure -eq $Ensure)
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
        Write-Verbose -Message "Disconnecting from share $smbPath ..."
        Remove-SmbMapping -RemotePath $smbPath
    }
    else 
    {
        Write-Verbose -Message "Connecting to share $smbPath ..."
        $cred = $SharePathCredential.GetNetworkCredential()
        $pwd = $cred.Password 
        $user = $cred.Domain + "\" + $cred.UserName
		New-SmbMapping -RemotePath $smbPath -UserName $user -Password $pwd
    }
}

function Test-InstallResult
{
    $statusLine = Get-Content $env:TEMP\sqlsetup.log -Encoding Unicode | Where-Object { $_.Contains("Setup closed with exit code:") }
    $parts = $statusLine.Split(" ")
    $returnCodeString = $parts[$parts.Length - 1]
    return $returnCodeString
}

Export-ModuleMember -Function *-TargetResource
