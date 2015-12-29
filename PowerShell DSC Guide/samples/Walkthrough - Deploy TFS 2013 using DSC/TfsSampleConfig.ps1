$ConfigData=
@{
    AllNodes = @(
        @{
            NodeName="*"
            PSDscAllowPlainTextPassword=$true
         }

       @{
            NodeName = "<name of TFS server>" 

        }
    )
 }
 

Configuration Tfs
{
    param
    (
        [Parameter(Mandatory)]
        [string] $WindowsMediaPath,
        [Parameter(Mandatory)]
        [string] $SqlServerMediaPath,
        [Parameter(Mandatory)]
        [string] $TfsMediaPath,
        [Parameter(Mandatory)]
        [string] $LogPath,
        [Parameter(Mandatory=$true)] 
        [ValidateNotNullorEmpty()] 
        [PSCredential] $TfsAdministratorCredential
    )

    Import-DscResource -Module cSql
    Import-DscResource -Module cTfs

    Node <name of TFS server>
    {
        WindowsFeature InstallDotNet35
        {            
            Ensure = "Present"
            Name = "Net-Framework-Core"
            Source = (Join-Path $WindowsMediaPath -ChildPath "\Sources\SxS")
        }
    
        WindowsFeature InstallDotNet40
        {            
            Ensure = "Present"
            Name = "AS-NET-Framework"
        }
    
        cSqlServerEngine InstallSqlServer2012Engine
        {
            InstanceName = "MSSQLSERVER"
            Ensure = "Present"
            AgentServiceAccount = "NT Authority\Network Service"
            SqlServiceAccount =  "NT Authority\Network Service"
            SysAdminAccount = $TfsAdministratorCredential.UserName
            TempDBDataDirectory = "C:\SQL\Databases\TempDB\"
            TempDBLogDirectory = "C:\SQL\Databases\TempDB\"
            UserDBDataDirectory = "C:\SQL\Databases\UserDBs\"
            UserDBLogDirectory = "C:\SQL\Databases\UserDBs\"
            FullText = "Present"
            LogPath = $LogPath
            SourcePath = $SqlServerMediaPath
            DependsOn = "[WindowsFeature]InstallDotNet35","[WindowsFeature]InstallDotNet40"
        }
    
        cSqlServerAnalysisServices InstallSqlServer2012AnalysisServices
        {
            InstanceName = "MSSQLSERVER"
            Ensure = "Present"
            ServiceAccount = "NT Authority\Network Service"
            SysAdminAccount = $TfsAdministratorCredential.UserName
            TempDataDirectory = "C:\SQL\AnalysisServices\Temp\"
            LogPath = $LogPath
            SourcePath = $SqlServerMediaPath
            DependsOn = "[WindowsFeature]InstallDotNet35","[WindowsFeature]InstallDotNet40"
        }
    
        cSqlServerManagementStudio InstallSqlServer2012ManagementStudio
        {
            Name = "SSMS"
            Ensure = "Present"
            InstanceDirectory = ""
            Advanced = "Present"
            LogPath = $LogPath
            SourcePath = $SqlServerMediaPath
            DependsOn = "[cSqlServerEngine]InstallSqlServer2012Engine", "[cSqlServerAnalysisServices]InstallSqlServer2012AnalysisServices"
        }
    
        cTfsApplicationTier InstallTfs2013
        {
            Name = $Node.NodeName
            Ensure = "Present"
            TfsAdminCredential = $TfsAdministratorCredential
            TfsServiceAccount = "NT AUTHORITY\Local Service"
            SqlServerInstance = $Node.NodeName
            FileCacheDirectory = "C:\TFS\FileCache"
            TeamProjectCollectionName = "DefaultCollection"
            LogPath = $LogPath
            SourcePath = $TfsMediaPath
            DependsOn = "[cSqlServerEngine]InstallSqlServer2012Engine", "[cSqlServerAnalysisServices]InstallSqlServer2012AnalysisServices"
        }
    
        cTfsBuildServer InstallTfs2013BuildServer
        {
            Name = $Node.NodeName
            Ensure = "Present"
            ConfigurationCredential = $TfsAdministratorCredential
            BuildServiceCredential = $TfsAdministratorCredential
            Port = 9191
            AgentCount = 2
            TeamProjectCollectionUri = "http://localhost:8080/tfs/DefaultCollection/"
            LogPath = $LogPath
            SourcePath = $TfsMediaPath
            DependsOn = "[cTfsApplicationTier]InstallTfs2013"
        }
    
        LocalConfigurationManager 
        { 
            RebootNodeIfNeeded = $true
        } 
    }
} 

$MofPath = ".\Mof" 
$LogPath = "c:\DSCLogsTFS" 
$WindowsMediaPath = "D:\"
$SqlServerMediaPath = "E:\"
$TfsMediaPath = "F:\"
$domainName = "<domain/workgroup>"
$domainAdminAccount = New-Object System.Management.Automation.PSCredential("$domainName\Administrator", (ConvertTo-SecureString "<password>" -AsPlainText -Force))

if (!(Test-Path $MofPath))
{
    New-Item $MofPath -ItemType Directory
}

if (!(Test-Path $LogPath))
{
    New-Item $LogPath -ItemType Directory
}

Tfs -ConfigurationData $ConfigData -OutputPath .\Mof -WindowsMediaPath $WindowsMediaPath -SqlServerMediaPath $SqlServerMediaPath -TfsMediaPath $TfsMediaPath -LogPath $LogPath -TfsAdministratorCredential $domainAdminAccount

Set-DscLocalConfigurationManager .\Mof

Start-DscConfiguration -Path .\Mof -ComputerName $env:COMPUTERNAME -Wait -Debug
