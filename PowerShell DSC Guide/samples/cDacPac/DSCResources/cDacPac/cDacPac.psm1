function CheckIfDbExists([string]$ConnectionString, [string]$DatabaseName)
{
    Write-Verbose "CheckIfDbExists"

    $connectionStringToUse = "$ConnectionString;database=$DatabaseName;"

    $connection = New-Object system.Data.SqlClient.SqlConnection
    $connection.connectionstring = $connectionStringToUse

    $result = $true
    try
    {
        $connection.Open()
    }
    catch
    {  
        $result = $false
    }

    Write-Verbose "`t$result"

    $connection.Close()

    return $result
}

function DeleteDb([string]$ConnectionString, [string] $DatabaseName)
{
    Write-Verbose "DeleteDb"

    $sqlConnection = new-object system.data.SqlClient.SQLConnection($ConnectionString);

    $query = "If EXISTS(SELECT * FROM sys.databases WHERE name='$DatabaseName')
               BEGIN
                EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$DatabaseName'
                ALTER DATABASE [$DatabaseName] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
                USE [master]
                DROP DATABASE [$DatabaseName]
               END"

    Write-Verbose "`t$query"

    $result = SqlExecuteNonQuery -SqlConnection $sqlConnection -Query $query

    $sqlConnection.Close()
}

function GetDacPacVersion([string]$ConnectionString, [string] $DatabaseName)
{
    Write-Verbose "GetDacPacVersion"

    $sqlConnection = new-object system.data.SqlClient.SQLConnection($ConnectionString)

    $query = "SELECT type_version FROM [msdb].[dbo].[sysdac_instances]
              WHERE instance_name = '$DatabaseName'"

    Write-Verbose "`t$query"

    $result = SqlExecuteScalar -SqlConnection $sqlConnection -Query $query

    Write-Verbose "`t$result"

    $sqlConnection.Close()

    return $result
}

function SqlExecuteNonQuery([system.data.SqlClient.SQLConnection]$SqlConnection, [string]$Query)
{
    Write-Verbose "SqlExecuteNonQuery"

    $sqlCommand = new-object system.data.sqlclient.sqlcommand($Query, $SqlConnection)

    $SqlConnection.Open()
    $queryResult = $sqlCommand.ExecuteNonQuery()
    $SqlConnection.Close()

    if ($queryResult  -ne -1)
    {
        return $true
    }

    return $false
}

function SqlExecuteScalar([system.data.SqlClient.SQLConnection]$SqlConnection, [string]$Query)
{
    Write-Verbose "SqlExecuteScalar"

    $sqlCommand = new-object system.data.sqlclient.sqlcommand($Query, $SqlConnection)

    $SqlConnection.Open()
    $queryResult = $sqlCommand.ExecuteScalar()
    $SqlConnection.Close()

    Write-Verbose "`t$queryResult"

    return $queryResult
}

function Construct-ConnectionString([string]$SqlServer, [System.Management.Automation.PSCredential]$Credentials)
{
    Write-Verbose "Construct-ConnectionString"

    $server = "Server=$sqlServer;"

    if($Credentials -ne $null)
    {
        $uid = $credentials.UserName
        $pwd = $credentials.GetNetworkCredential().Password
        $userName = "uid=$uid;pwd=$pwd;"
        $integratedSecurity = "Integrated Security=False;"
    }
    else
    {
        $integratedSecurity = "Integrated Security=SSPI;"
    }

    $connectionString = "$server$userName$integratedSecurity"

    Write-Verbose "`t$connectionString"

    return $connectionString
}

function Get-SqlServerMajorVersion([string]$SqlServerVersion)
{
    Write-Verbose "Get-SqlServerMajorVersion"

    switch($SqlserverVersion)
    {
        "2008-R2"
        {
            $majorVersion = 100
        }
        "2012"
        {
            $majorVersion = 110
        }
        "2014"
        {
            $majorVersion = 120
        }
    }

    Write-Verbose "`t$majorVersion"

    return $majorVersion
}

function LoadDependencies([string]$SqlServerVersion)
{
    $sqlVersion = Get-SqlServerMajorVersion -SqlServerVersion $SqlServerVersion
    $SmoServerLocation = "${env:ProgramFiles(x86)}\Microsoft SQL Server\$sqlVersion\SDK\Assemblies\Microsoft.SqlServer.Smo.dll"
    [System.Reflection.Assembly]::LoadFrom($SmoServerLocation) | Out-Null
    $SmoLocation = "${env:ProgramFiles(x86)}\Microsoft SQL Server\$sqlVersion\DAC\bin\Microsoft.SqlServer.Dac.dll"
    [System.Reflection.Assembly]::LoadFrom($SmoLocation) | Out-Null
}

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SqlServer,

		[parameter(Mandatory = $true)]
		[System.String]
		$DatabaseName,

		[parameter(Mandatory = $true)]
		[System.String]
		$DacPacPath,

		[parameter(Mandatory = $true)]
		[ValidateSet("2008-R2","2012","2014")]
		[System.String]
		$SqlServerVersion,

		[System.Management.Automation.PSCredential]
		$SqlConnectionCredential
	)

    $connectionString = Construct-ConnectionString -SqlServer $sqlServer -Credentials $SqlConnectionCredential 
    $dbExists = CheckIfDbExists -connectionString $connectionString -databaseName $databaseName
    $dacPacVersion = GetDacPacVersion -ConnectionString $ConnectionString -DatabaseName $DatabaseName

    $ensure = $false
    if($dbExists -eq $true)
    {
        $ensure = $true
    }

    $returnValue = @{
		SqlServer = $SqlServer
		DatabaseName = $DatabaseName
		DacPacPath = $DacPacPath
		SqlServerVersion = $SqlServerVersion
		DacPacVersion = $dacPacVersion
		SqlConnectionCredential = $SqlConnectionCredential
		Ensure = $ensure
    }

    $returnValue
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SqlServer,

		[parameter(Mandatory = $true)]
		[System.String]
		$DatabaseName,

		[parameter(Mandatory = $true)]
		[System.String]
		$DacPacPath,

		[parameter(Mandatory = $true)]
		[ValidateSet("2008-R2","2012","2014")]
		[System.String]
		$SqlServerVersion,

		[System.String]
		$DacPacVersion,

		[System.Management.Automation.PSCredential]
		$SqlConnectionCredential,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure
	)

    Write-Verbose "Set-TargetResource"

    LoadDependencies -SqlServerVersion $SqlServerVersion

    $connectionString = Construct-ConnectionString -SqlServer $sqlServer -Credentials $credentials
    $dacServicesObject = new-object Microsoft.SqlServer.Dac.DacServices($connectionString)
    $dacPacInstance = [Microsoft.SqlServer.Dac.DacPackage]::Load($DacPacPath)

    # If version is specified use that instead of the version in the dacpac
    if($DacPacVersion -ne "")
    {
        $versionToUse = New-Object System.Version($DacPacVersion)
    }
    else
    {
        $versionToUse = $dacPacInstance.Version
    }
    
    Write-Verbose "`tUsing version $versionToUse"

    if($Ensure -eq "Present")
    {
        $dacServicesObject.Deploy($dacPacInstance, $databaseName, $true) 
        $dacServicesObject.Register($databaseName, $dacPacInstance.Name, $versionToUse, $dacPacInstance.Description)
    }
    else
    {
        DeleteDb -connectionString $connectionString -databaseName $databaseName
        $dacServicesObject.Unregister($databaseName)
    }
}

function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SqlServer,

		[parameter(Mandatory = $true)]
		[System.String]
		$DatabaseName,

		[parameter(Mandatory = $true)]
		[System.String]
		$DacPacPath,

		[parameter(Mandatory = $true)]
		[ValidateSet("2008-R2","2012","2014")]
		[System.String]
		$SqlServerVersion,

		[System.String]
		$DacPacVersion,

		[System.Management.Automation.PSCredential]
		$SqlConnectionCredential,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure
	)

    Write-Verbose "Test-TargetResource"

    $result = $false
    $versionToUse = "not-set"

    LoadDependencies -SqlServerVersion $SqlServerVersion

    $connectionString = Construct-ConnectionString -SqlServer $sqlServer -Credentials $SqlConnectionCredential
    $dacServicesObject = new-object Microsoft.SqlServer.Dac.DacServices($connectionString)
    $dacPacInstance = [Microsoft.SqlServer.Dac.DacPackage]::Load($DacPacPath)

    # If version is specified use that instead of the version in the dacpac
    if($DacPacVersion -ne "")
    {
        $versionToUse = $DacPacVersion
    }
    else
    {
        $versionToUse = $dacPacInstance.Version
    }

    $dbExists = CheckIfDbExists -ConnectionString $ConnectionString -DatabaseName $DatabaseName
    $dacPacVersion = GetDacPacVersion -ConnectionString $ConnectionString -DatabaseName $DatabaseName -Version $versionToUse

    if($Ensure -eq "Present")
    {
        if($dbExists -eq $true)
        {
            if($dacPacVersion -eq $versionToUse)
            {
                $result = $true
            }
        }
    }
    else
    {
        if($dbExists -eq $false)
        {
            $result = $true
        }
        else
        {
            if($dacPacVersion -ne $versionToUse)
            {
                $result = $true
            }
        }
    }

	$result
}

Export-ModuleMember -Function *-TargetResource
