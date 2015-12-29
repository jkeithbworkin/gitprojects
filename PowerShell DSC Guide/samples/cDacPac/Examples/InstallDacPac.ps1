$ConfigData = @{
    AllNodes = @(
        @{
            NodeName = "[servername]" 
            SqlServer = "[sqlserver name]" 
            DatabaseName = "[database name]"
            DacPacPath = "[path to dacpac package]"
        }
    )
}

Configuration InstallDacPac
{
    Import-DscResource -ModuleName cDacPac

    node $AllNodes.NodeName
    {
        cDacPac DeployDacPac
        {
            SqlServer = $Node.SqlServer
            DatabaseName = $Node.DatabaseName
            DacPacPath = $Node.DacPacPath
            SqlServerVersion = '2014'
            Ensure = 'Present'
        }
    }
}

InstallDacPac -ConfigurationData $ConfigData 

Start-DscConfiguration -Path .\InstallDacPac -Wait -Force -Verbose
