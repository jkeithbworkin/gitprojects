#
# cSQLServerManagementStudio: DSC resource to install Sql Server Management Studio.
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
        [ValidateSet("SSMS")]
        [parameter(Mandatory)] 
        [string] $Name = "SSMS"
    )

    $products = Get-ManagementStudioProducts

    if ($products -ne $null)
    {
        Write-Verbose "SSMS is installed"
        $returnValue = @{
            Name = $Name
            Ensure = "Present"
        }
    }
    else
    {
        Write-Verbose "SSMS is not installed"
        $returnValue = @{
            Name = $Name
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
        [ValidateSet("SSMS")]
        [parameter(Mandatory)] 
        [string] $Name = "SSMS",

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $InstanceDirectory = "",

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Advanced = "Present",
        
        [string] $LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    if ($Ensure -ne "Present")
    {
        $products = Get-ManagementStudioProducts
        if ($products.GetType().IsArray)
        {
            foreach($product in $products)
            {
                $msg = "Uninstalling {0}" -f $product.Name
                Write-Verbose $msg
                $product.Uninstall()
            }
        }
        else
        {
            $msg = "Uninstalling {0}" -f $products.Name
            Write-Debug $msg
            $products.Uninstall()
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
    
        $logFile = Join-Path $LogPath -ChildPath "sqlManagementStudioInstall-log.txt"
    
        $features = "SSMS"

        if ($Advanced -eq "Present")
        {
            $features += ",ADV_SSMS"
        }
    
        $cmd = Join-Path $SourcePath -ChildPath "Setup.exe"
    
        $cmd += " /Q /ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /ENU /UpdateEnabled=false /IndicateProgress "
    	if (![string]::IsNullOrEmpty($InstanceDirectory))
	    {
	        $cmd += " /INSTANCEDIR='$InstanceDirectory' "
	    }
        $cmd += " /FEATURES=$features "
        $cmd += " > $logFile 2>&1 "
    
        NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Present"
        try
        {
            Write-Debug "Installing SQL Server Management Studio with the following command: $cmd"
            Invoke-Expression $cmd
            $setupResult = Test-InstallResult
            if ($setupResult -ne "0x00000000")
            {
                throw "SQL Server Management Studio installation failed with result code: $setupResult"
            }
        }
        finally
        {
            NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Absent"
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
        [ValidateSet("SSMS")]
        [parameter(Mandatory)] 
        [string] $Name = "SSMS",

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $InstanceDirectory = "",

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Advanced = "Present",
        
        [string] $LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SourcePathCredential
    )

    [Hashtable]$info = Get-TargetResource -Name $Name
    
    return ($info.Name -eq $Name -and $info.Ensure -eq $Ensure)
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

function Get-ManagementStudioProducts
{
    # This query may return more than one product, and not because of the LIKE, for SQL Server 2012 it lists two products.
    $product = Get-WmiObject Win32_Product -Filter "Name LIKE 'SQL Server % Management Studio'"
    return $product
}

function Test-InstallResult
{
    $statusLine = Get-Content $env:TEMP\sqlsetup.log -Encoding Unicode | Where-Object { $_.Contains("Setup closed with exit code:") }
    $parts = $statusLine.Split(" ")
    $returnCodeString = $parts[$parts.Length - 1]
    return $returnCodeString
}

Export-ModuleMember -Function *-TargetResource
