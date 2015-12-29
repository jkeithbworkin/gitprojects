#
# cTfsApplicationTier: DSC resource to install Team Foundation Server.
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
        [string] $Name
    )

    $product = Get-TfsProduct

    if ($product -ne $null)
    {
        $ensureConfiguration = "Absent"
		$components = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\TeamFoundationServer\12.0\InstalledComponents -ErrorAction SilentlyContinue | where { (Get-ItemProperty -Path $_.PSPath -Name IsConfigured -ErrorAction SilentlyContinue).IsConfigured -eq 1} | foreach { Split-Path -Path $_.PSPath -Leaf }
        if ($components -ne $null)
        {
		    if ($components.Contains("ApplicationTier"))
			{
                $ensureConfiguration = "Present"
		    }
        }

        $returnValue = @{
            Name = $env:COMPUTERNAME
            EnsureBinaries = "Present"
            EnsureConfiguration = $ensureConfiguration
        }
    }
    else
    {
        $returnValue = @{
            Name = $env:COMPUTERNAME
            EnsureBinaries = "Absent"
            EnsureConfiguration = "Absent"
        }
    }

    if ($returnValue.EnsureBinaries -eq "Present" -and $returnValue.EnsureConfiguration -eq "Present")
    {
        Write-Verbose "TFS is installed and configured"
    }
    elseif ($returnValue.EnsureBinaries -eq "Present"
    )
    {
        Write-Verbose "TFS is installed but not configured"
    }
    else
    {
        Write-Verbose "TFS is not installed"
    }
	$returnValue
}


#
# The Set-TargetResource cmdlet.
#
function Set-TargetResource
{
    param
    (	
        [parameter(Mandatory)] 
        [string] $Name,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [ValidateNotNull()]
        [PSCredential] $TfsAdminCredential,

        [System.String]
        $TfsServiceAccount = "NT AUTHORITY\Network Service",

        [System.String]
        $SqlServerInstance = "(localhost)",

        [ValidateNotNullOrEmpty()]
        [System.String]
        $FileCacheDirectory,

        [ValidateNotNullOrEmpty()]
        [System.String]
        $TeamProjectCollectionName = "DefaultCollection",
        
        [string] $LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    if ($Ensure -ne "Present")
    {
        $product = Get-TfsProduct
        if ($product -ne $null)
        {
            Write-Verbose "Uninstalling TFS"
            $product.Uninstall()
        }
    }
    else
    {
    	if ([string]::IsNullOrEmpty($LogPath))
    	{
            $LogPath = Join-Path $env:SystemDrive -ChildPath "Logs"
    	}
    
        if (!(Test-Path $LogPath))
        {
            New-Item $LogPath -ItemType Directory
        }
    
        $info = Get-TargetResource -Name $Name

        if ($info.EnsureBinaries -eq "Absent")
        {
            Install-TfsBinaries $LogPath $SourcePath $SourcePathCredential
        }

        if ($info.EnsureConfiguration -eq "Absent")
        {
            Configure-Tfs $LogPath $TfsAdminCredential $TfsServiceAccount $SqlServerInstance $FileCacheDirectory $TeamProjectCollectionName
        }
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
        [string] $Name,
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [ValidateNotNull()]
        [PSCredential] $TfsAdminCredential,

        [System.String]
        $TfsServiceAccount = "NT AUTHORITY\Network Service",

        [System.String]
        $SqlServerInstance = "(localhost)",

        [ValidateNotNullOrEmpty()]
        [System.String]
        $FileCacheDirectory,

        [ValidateNotNullOrEmpty()]
        [System.String]
        $TeamProjectCollectionName = "DefaultCollection",
        
        [string] $LogPath,

        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    $info = Get-TargetResource -Name $Name
    
    return ($info.Name -eq $Name -and $info.EnsureBinaries -eq $Ensure -and $info.EnsureConfiguration -eq $Ensure)
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

function Get-TfsProduct
{
    $product = Get-WmiObject Win32_Product -Filter "Name LIKE 'Microsoft Team Foundation Server 201%'"
    return $product
}

function Install-TfsBinaries
{
    param
    (
        [string] $LogPath,
        [string] $SourcePath,
        [PSCredential] $SourcePathCredential
    )

    $logFile = Join-Path $LogPath -ChildPath "tfsApplicationTierInstall-log.txt"

    $cmd = Join-Path $SourcePath -ChildPath "tfs_server.exe"

    $cmd += " /install /quiet "
    $cmd += " > $logFile 2>&1 "

    NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Present"
    try
    {
        Write-Debug "Installing TFS with the following command: $cmd"
        Invoke-Expression $cmd
        do
        {
            Write-Debug "Checking process still running"
            $process = Get-Process -Name tfs_server -ErrorAction:SilentlyContinue
            Start-Sleep -Seconds 5
        }
        until ($process -eq $null)
        $setupResult = Get-TargetResource -Name $Name
        if ($setupResult.EnsureBinaries -ne "Present")
        {
            throw "TFS installation failed with result code: $setupResult"
        }
    }
    finally
    {
        NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Absent"
    }
}

function Configure-Tfs
{
    param
    (
        [string] $LogPath,
        [PSCredential] $TfsAdminCredential,
        [string] $TfsServiceAccount,
        [string] $SqlServerInstance,
        [string] $FileCacheDirectory,
        [string] $TeamProjectCollectionName
    )

    $logOutFile = Join-Path $LogPath -ChildPath "tfsApplicationTierConfigure-log.txt"
    $logErrFile = Join-Path $LogPath -ChildPath "tfsApplicationTierConfigureError-log.txt"

    $cmd = Join-Path (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\TeamFoundationServer\12.0 -Name InstallPath).InstallPath -ChildPath "\tools\tfsconfig.exe"

    $inputs = "SendFeedback=False"
    $inputs += ";SqlInstance=$SqlServerInstance"
    $inputs += ";ServiceAccountName=$TfsServiceAccount"
    $inputs += ";AuthenticationMethod=NTLM"
    $inputs += ";FileCacheFolder=$FileCacheDirectory"
    $inputs += ";CreateInitialCollection=True"
    $inputs += ";CollectionName=$TeamProjectCollectionName"

    $arguments = "unattend", "/configure", "/type:basic", """/inputs:$inputs""", "/continue"

    Write-Debug "Configuring TFS with the following command: $cmd $arguments"

    Remove-Item $logErrFile -ErrorAction:SilentlyContinue
    Remove-Item $logOutFile -ErrorAction:SilentlyContinue

    Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $TfsAdminCredential -ScriptBlock { param ($cmd, $arguments, $logOutFile, $logErrFile) Start-Process $cmd -ArgumentList $arguments -Wait -NoNewWindow -RedirectStandardOutput $logOutFile -RedirectStandardError $logErrFile} -ArgumentList $cmd, $arguments, $logOutFile, $logErrFile

    if ((Test-Path $logErrFile))
    {
        $errorText = (Get-Content $logErrFile) -join ""
        if (![string]::IsNullOrEmpty($errorText))
        {
            if ($errorText.Contains("[Error]"))
            {
                throw "Configuration failed: $errorText"
            }
        }
    }
}

Export-ModuleMember -Function *-TargetResource
