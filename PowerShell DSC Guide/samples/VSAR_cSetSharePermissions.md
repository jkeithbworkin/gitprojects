
```powershell
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $ShareName
    )

    #Write-Verbose "Use this cmdlet to deliver information about command processing."

    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."

    #For this situation, this method will always return Ensure = false because we aren't
    #going to check the permissions every time in this method.

    $returnValue = @{
        ShareName = $ShareName
        Ensure = "Absent"
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
        $ShareName,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [System.String[]]
        $FullAccessUsers,

        [System.String[]]
        $ChangeAccessUsers,

        [System.String[]]
        $ReadAccessUsers
    )

    Write-Verbose -Message "Retrieving share permissions"

    #Get the members who have access to the share
    $results = Get-SmbShareAccess -Name $ShareName

    if($Ensure -eq 'Present')
    {
        if ($FullAccessUsers -ne $null)
        {
            #Loop through the list of full access users to be added
            for($i = 0; $i -lt $FullAccessUsers.Count; $i++)
            {

                #Search the list of returned users where the account name has been provided  and the current access right is full
                $found = $results | Where-Object { ($_.AccountName -eq $FullAccessUsers[$i]) -and ($_.AccessRight -eq "Full") }
                #If any user in this loop is not found add the user to the group
                if ($found -eq $null)
                {
                    Write-Verbose -Message "Adding user $FullAccessUsers[$i] to the Full access group"
                    Grant-SmbShareAccess -Name $ShareName -AccountName $FullAccessUsers[$i] -AccessRight Full -Force
                }
            }
        }

        if ($ChangeAccessUsers -ne $null)
        {
            for($i = 0; $i -lt $ChangeAccessUsers.Count; $i++)
            {
                $found = $results | Where-Object { ($_.AccountName -eq $ChangeAccessUsers[$i]) -and ($_.AccessRight -eq "Change") }
                if ($found -eq $null)
                {
                    Write-Verbose -Message "Adding user $ChangeAccessUsers[$i] to the Change access group"
                    Grant-SmbShareAccess -Name $ShareName -AccountName $ChangeAccessUsers[$i] -AccessRight Change -Force
                }
            }
        }

        if ($ReadAccessUsers -ne $null)
        {
            for($i = 0; $i -lt $ReadAccessUsers.Count; $i++)
            {
                $found = $results | Where-Object { ($_.AccountName -eq $ReadAccessUsers[$i]) -and ($_.AccessRight -eq "Read") }
                if ($found -eq $null)
                {
                    Write-Verbose -Message "Adding user $ReadAccessUsers[$i] to the Read access group"
                    Grant-SmbShareAccess -Name $ShareName -AccountName $ReadAccessUsers[$i] -AccessRight Read -Force
                }
            }
        }
    }
    else
    {
        if ($FullAccessUsers -ne $null)
        {
            #Loop through the list of full access users to be added
            for($i = 0; $i -lt $FullAccessUsers.Count; $i++)
            {

                #Search the list of returned users where the account name has been provided  and the current access right is full
                $found = $results | Where-Object { ($_.AccountName -eq $FullAccessUsers[$i]) -and ($_.AccessRight -eq "Full") }
                #If any user in this loop is not found add the user to the group
                if ($found -eq $null)
                {
                    Write-Verbose -Message "Removing user $FullAccessUsers[$i] from the Full access group"
                    Remove-SmbShareAccess -Name $ShareName -AccountName $FullAccessUsers[$i] -AccessRight Full -Force
                }
            }
        }

        if ($ChangeAccessUsers -ne $null)
        {
            for($i = 0; $i -lt $ChangeAccessUsers.Count; $i++)
            {
                $found = $results | Where-Object { ($_.AccountName -eq $ChangeAccessUsers[$i]) -and ($_.AccessRight -eq "Change") }
                if ($found -eq $null)
                {
                    Write-Verbose -Message "Removing user $ChangeAccessUsers[$i] from the Change access group"
                    Remove-SmbShareAccess -Name $ShareName -AccountName $ChangeAccessUsers[$i] -AccessRight Change -Force
                }
            }
        }

        if ($ReadAccessUsers -ne $null)
        {
            for($i = 0; $i -lt $ReadAccessUsers.Count; $i++)
            {
                $found = $results | Where-Object { ($_.AccountName -eq $ReadAccessUsers[$i]) -and ($_.AccessRight -eq "Read") }
                if ($found -eq $null)
                {
                    Write-Verbose -Message "Removing user $ReadAccessUsers[$i] from the Read access group"
                    Remove-SmbShareAccess -Name $ShareName -AccountName $ReadAccessUsers[$i] -AccessRight Read -Force
                }
            }
        }
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
        $ShareName,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [System.String[]]
        $FullAccessUsers,

        [System.String[]]
        $ChangeAccessUsers,

        [System.String[]]
        $ReadAccessUsers
    )

    <#
        If the users have the minimum permissions required by this resource, then return true.
        Read access users can be in Read, Change or full groups
        Change access users can be in Change or full groups
        Full access users must be in the Full group
    #>

    Write-Verbose -Message "Retrieving share permissions"

    #Get the members who have access to the share
    $results = Get-SmbShareAccess -Name $ShareName

    if ($Ensure -eq "Present")
    {
        Write-Verbose -Message "Checking for users to add"

        #before starting these checks, check to see if the user is attempting to add any users to the share at all,
        #if not this is not a required check
        if ($FullAccessUsers -ne $null)
        {
            Write-Verbose -Message "Checking full access users"

            #Loop through the list of full access users to be added
            for($i = 0; $i -lt $FullAccessUsers.Count; $i++)
            {
                #Search the list of returned users where the account name has been provided  and the current access right is full
                $found = $results | Where-Object { ($_.AccountName -eq $FullAccessUsers[$i]) -and ($_.AccessRight -eq "Full")}
                #If any user in this loop is not found return false to indicate that the state is not as desired
                if ($found -eq $null)
                {
                    Write-Verbose -Message "At least one user was not found in the full access group"
                    return $false
                }
            }
        }

        if ($ChangeAccessUsers -ne $null)
        {
            Write-Verbose -Message "Checking change access users"

            for($i = 0; $i -lt $ChangeAccessUsers.Count; $i++)
            {
                #For the change access user, check the change and full rights
                $found = $results | Where-Object { ($_.AccountName -eq $ChangeAccessUsers[$i]) -and (($_.AccessRight -eq "Full") -or ($_.AccessRight -eq "Change"))}
                if ($found -eq $null)
                {
                    Write-Verbose -Message "At least one user was not found in the change access group"
                    return $false
                }
            }
        }

        if ($ReadAccessUsers -ne $null)
        {
            Write-Verbose -Message "Checking read access users"

            for($i = 0; $i -lt $ReadAccessUsers.Count; $i++)
            {
                #For the Read access users check the Full, Change and Read rights
                $found = $results | Where-Object { ($_.AccountName -eq $ReadAccessUsers[$i]) -and (($_.AccessRight -eq "Full") -or ($_.AccessRight -eq "Change") -or ($_.AccessRight -eq "Read"))}
                if ($found -eq $null)
                {
                    Write-Verbose -Message "At least one user was not found in the read access group"
                    return $false
                }
            }
        }
    }
    else
    {
        #The resource is to remove the users from the specified groups if they exist.
        #The removal is an exact remove whereas the add is a minimum set
        #before starting these checks, check to see if the user is attempting to add any users to the share at all,
        #if not this is not a required check

        Write-Verbose -Message "Checking for users to remove"

        if ($FullAccessUsers -ne $null)
        {
            Write-Verbose -Message "Checking full access users"

            #Loop through the list of full access users to be added
            for($i = 0; $i -lt $FullAccessUsers.Count; $i++)
            {
                #Search the list of returned users where the account name has been provided  and the current access right is full
                $found = $results | Where-Object { ($_.AccountName -eq $FullAccessUsers[$i]) -and ($_.AccessRight -eq "Full") }
                #If any user in this loop is found return false to indicate that the state is not as desired
                if ($found -ne $null)
                {
                    Write-Verbose -Message "At least one user was found in the full access group"
                    return $false
                }
            }
        }

        if ($ChangeAccessUsers -ne $null)
        {
            Write-Verbose -Message "Checking change access users"

            for($i = 0; $i -lt $ChangeAccessUsers.Count; $i++)
            {
                $found = $results | Where-Object { ($_.AccountName -eq $ChangeAccessUsers[$i]) -and ($_.AccessRight -eq "Change") }
                if ($found -ne $null)
                {
                    Write-Verbose -Message "At least one user was found in the change access group"
                    return $false
                }
            }
        }

        if ($ReadAccessUsers -ne $null)
        {
            Write-Verbose -Message "Checking read access users"

            for($i = 0; $i -lt $ReadAccessUsers.Count; $i++)
            {
                $found = $results | Where-Object { ($_.AccountName -eq $ReadAccessUsers[$i]) -and ($_.AccessRight -eq "Read") }
                if ($found -ne $null)
                {
                    Write-Verbose -Message "At least one user was found in the read access group"
                    return $false
                }
            }
        }
    }

    #If this is called, then all users are in an acceptable group (or not as the case may be)
    return $true
} 


Export-ModuleMember -Function *-TargetResource
```
