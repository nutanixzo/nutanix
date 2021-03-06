<#
.SYNOPSIS
  This script can be used to add or remove an AHV network to a specified AHV vswitch.
.DESCRIPTION
  Given a Nutanix cluster, a network name, a vlan ID, a description and a virtual switch, add or remove the AHV network using Prism Element REST API.
.PARAMETER prism
  IP address or FQDN of Prism Element.
.PARAMETER username
  Prism Central username.
.PARAMETER password
  Prism Central username password.
.PARAMETER prismCreds
  Specifies a custom credentials file name (will look for %USERPROFILE\Documents\WindowsPowerShell\CustomCredentials\$prismCreds.txt). These credentials can be created using the Powershell command 'Set-CustomCredentials -credname <credentials name>'. See https://blog.kloud.com.au/2016/04/21/using-saved-credentials-securely-in-powershell-scripts/ for more details.
.PARAMETER network
  Name of the network to add.
.PARAMETER id
  VLAN id of the network.
.PARAMETER description
  Description of the network.
.PARAMETER vswitch
  Name of the AHV virtual switch where the network should be added (exp: br1).
.PARAMETER uuid
  Uuid of the AHV network you want to remove (use -get to figure that out if needed). This is an alternative way to specify the network you want to remove when the name matches multiple instances.
.PARAMETER add
  Adds the specified network.
.PARAMETER remove
  Removes the specified network.
.PARAMETER get
  Retrieves and displays the specified network. (wip)
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.EXAMPLE
.\add-AhvNetwork.ps1 -prism 10.10.10.1 -prismCreds myuser -network mynetwork -id 100 -description "This is my network" -vswitch br1 -add
Adds the network mynetwork with vlan id 100 to the AHV br1 virtual switch on cluster 10.10.10.1.
.LINK
  http://www.nutanix.com/services
  https://github.com/sbourdeaud/nutanix
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: January 15th 2020
#>

#region Parameters
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $false)] [string]$prism,
    [parameter(mandatory = $false)] [string]$username,
    [parameter(mandatory = $false)] [string]$password,
    [parameter(mandatory = $false)] $prismCreds,
    [parameter(mandatory = $false)] [string]$network,
    [parameter(mandatory = $false)] [Int32]$vlanid,
    [parameter(mandatory = $false)] [string]$description,
    [parameter(mandatory = $false)] [string]$vswitch,
    [parameter(mandatory = $false)] [string]$uuid,
    [parameter(mandatory = $false)] [switch]$get,
    [parameter(mandatory = $false)] [switch]$add,
    [parameter(mandatory = $false)] [switch]$remove
)
#endregion

#region prep-work
#check if we need to display help and/or history
$HistoryText = @'
Maintenance Log
Date       By   Updates (newest updates at the top)
---------- ---- ---------------------------------------------------------------
01/15/2020 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\add-AhvNetwork.ps1"
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}

#let's get ready to use the Nutanix REST API
Write-Host "$(Get-Date) [INFO] Ignoring invalid certificates" -ForegroundColor Green
if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
  $certCallback = @"
  using System;
  using System.Net;
  using System.Net.Security;
  using System.Security.Cryptography.X509Certificates;
  public class ServerCertificateValidationCallback
  {
      public static void Ignore()
      {
          if(ServicePointManager.ServerCertificateValidationCallback ==null)
          {
              ServicePointManager.ServerCertificateValidationCallback += 
                  delegate
                  (
                      Object obj, 
                      X509Certificate certificate, 
                      X509Chain chain, 
                      SslPolicyErrors errors
                  )
                  {
                      return true;
                  };
          }
      }
  }
"@
  Add-Type $certCallback
}
[ServerCertificateValidationCallback]::Ignore()

# add Tls12 support
Write-Host "$(Get-Date) [INFO] Adding Tls12 support" -ForegroundColor Green
[Net.ServicePointManager]::SecurityProtocol = `
  ([Net.ServicePointManager]::SecurityProtocol -bor `
  [Net.SecurityProtocolType]::Tls12)

#endregion

#region functions
#this function is used to create saved credentials for the current user
function Set-CustomCredentials 
{
#input: path, credname
  #output: saved credentials file
<#
.SYNOPSIS
  Creates a saved credential file using DAPI for the current user on the local machine.
.DESCRIPTION
  This function is used to create a saved credential file using DAPI for the current user on the local machine.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER path
  Specifies the custom path where to save the credential file. By default, this will be %USERPROFILE%\Documents\WindowsPowershell\CustomCredentials.
.PARAMETER credname
  Specifies the credential file name.
.EXAMPLE
.\Set-CustomCredentials -path c:\creds -credname prism-apiuser
Will prompt for user credentials and create a file called prism-apiuser.txt in c:\creds
#>
  param
  (
    [parameter(mandatory = $false)]
        [string] 
        $path,
    
        [parameter(mandatory = $true)]
        [string] 
        $credname
  )

    begin
    {
        if (!$path)
        {
            if ($IsLinux -or $IsMacOS) 
            {
                $path = $home
            }
            else 
            {
                $path = "$Env:USERPROFILE\Documents\WindowsPowerShell\CustomCredentials"
            }
            Write-Host "$(get-date) [INFO] Set path to $path" -ForegroundColor Green
        } 
    }
    process
    {
        #prompt for credentials
        $credentialsFilePath = "$path\$credname.txt"
    $credentials = Get-Credential -Message "Enter the credentials to save in $path\$credname.txt"
    
    #put details in hashed format
    $user = $credentials.UserName
    $securePassword = $credentials.Password
        
        #convert secureString to text
        try 
        {
            $password = $securePassword | ConvertFrom-SecureString -ErrorAction Stop
        }
        catch 
        {
            throw "$(get-date) [ERROR] Could not convert password : $($_.Exception.Message)"
        }

        #create directory to store creds if it does not already exist
        if(!(Test-Path $path))
    {
            try 
            {
                $result = New-Item -type Directory $path -ErrorAction Stop
            } 
            catch 
            {
                throw "$(get-date) [ERROR] Could not create directory $path : $($_.Exception.Message)"
            }
    }

        #save creds to file
        try 
        {
            Set-Content $credentialsFilePath $user -ErrorAction Stop
        } 
        catch 
        {
            throw "$(get-date) [ERROR] Could not write username to $credentialsFilePath : $($_.Exception.Message)"
        }
        try 
        {
            Add-Content $credentialsFilePath $password -ErrorAction Stop
        } 
        catch 
        {
            throw "$(get-date) [ERROR] Could not write password to $credentialsFilePath : $($_.Exception.Message)"
        }

        Write-Host "$(get-date) [SUCCESS] Saved credentials to $credentialsFilePath" -ForegroundColor Cyan                
    }
    end
    {}
}

#this function is used to retrieve saved credentials for the current user
function Get-CustomCredentials 
{
#input: path, credname
  #output: credential object
<#
.SYNOPSIS
  Retrieves saved credential file using DAPI for the current user on the local machine.
.DESCRIPTION
  This function is used to retrieve a saved credential file using DAPI for the current user on the local machine.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER path
  Specifies the custom path where the credential file is. By default, this will be %USERPROFILE%\Documents\WindowsPowershell\CustomCredentials.
.PARAMETER credname
  Specifies the credential file name.
.EXAMPLE
.\Get-CustomCredentials -path c:\creds -credname prism-apiuser
Will retrieve credentials from the file called prism-apiuser.txt in c:\creds
#>
  param
  (
        [parameter(mandatory = $false)]
    [string] 
        $path,
    
        [parameter(mandatory = $true)]
        [string] 
        $credname
  )

    begin
    {
        if (!$path)
        {
            if ($IsLinux -or $IsMacOS) 
            {
                $path = $home
            }
            else 
            {
                $path = "$Env:USERPROFILE\Documents\WindowsPowerShell\CustomCredentials"
            }
            Write-Host "$(get-date) [INFO] Retrieving credentials from $path" -ForegroundColor Green
        } 
    }
    process
    {
        $credentialsFilePath = "$path\$credname.txt"
        if(!(Test-Path $credentialsFilePath))
      {
            throw "$(get-date) [ERROR] Could not access file $credentialsFilePath : $($_.Exception.Message)"
        }

        $credFile = Get-Content $credentialsFilePath
    $user = $credFile[0]
    $securePassword = $credFile[1] | ConvertTo-SecureString

        $customCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $user, $securePassword

        Write-Host "$(get-date) [SUCCESS] Returning credentials from $credentialsFilePath" -ForegroundColor Cyan 
    }
    end
    {
        return $customCredentials
    }
}
#endregion

#region variables
#initialize variables
#misc variables
$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
$myvarOutputLogFile += "OutputLog.log"
  
############################################################################
# command line arguments initialization
############################################################################	
#let's initialize parameters if they haven't been specified
if ((!$add) -and !($remove) -and !($get)) {throw "You must specify either get, add or remove!"}
if ($add -and $remove) {throw "You must specify either add or remove but not both!"}
if (!$prism) {$prism = read-host "Enter the hostname or IP address of Prism Central"}
if (!$network) {$network = read-host "Enter the network name"}
if ((!$get) -and (!$vlanid)) {$vlanid = read-host "Enter the vlan id"}
if ($add -and (!$description)) {$description = read-host "Enter a description for the network"}
if ((!$get) -and (!$vswitch)) {$vswitch = read-host "Enter the name of the AHV virtual switch (br0, br1, ...)"}
if (!$prismCreds) {#we are not using custom credentials, so let's ask for a username and password if they have not already been specified
    if (!$username) 
    {#if Prism username has not been specified ask for it
        $username = Read-Host "Enter the Prism username"
    } 

    if (!$password) 
    {#if password was not passed as an argument, let's prompt for it
        $PrismSecurePassword = Read-Host "Enter the Prism user $username password" -AsSecureString
    }
    else 
    {#if password was passed as an argument, let's convert the string to a secure string and flush the memory
        $PrismSecurePassword = ConvertTo-SecureString $password –asplaintext –force
        Remove-Variable password
    }
} 
else { #we are using custom credentials, so let's grab the username and password from that
    try 
    {
        $prismCredentials = Get-CustomCredentials -credname $prismCreds -ErrorAction Stop
        $username = $prismCredentials.UserName
        $PrismSecurePassword = $prismCredentials.Password
    }
    catch 
    {
        Set-CustomCredentials -credname $prismCreds
        $prismCredentials = Get-CustomCredentials -credname $prismCreds -ErrorAction Stop
        $username = $prismCredentials.UserName
        $PrismSecurePassword = $prismCredentials.Password
    }
}
#endregion

#region processing

    #! -add
    #region -add
    if ($add) {
        #region prepare api call
        $api_server = $prism
        $api_server_port = "9440"
        $api_server_endpoint = "/PrismGateway/services/rest/v2.0/networks/"
        $url = "https://{0}:{1}{2}" -f $api_server,$api_server_port, `
            $api_server_endpoint
        $method = "POST"
        $headers = @{
            "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))));
            "Content-Type"="application/json";
            "Accept"="application/json"
        }
        $content = @{
            annotation= $description;
            name= $network;
            vlan_id= $vlanid;
            vswitch_name= $vswitch
        }
        $payload = (ConvertTo-Json $content -Depth 4)
        #endregion

        #region make the api call
        Write-Host "$(Get-Date) [INFO] Adding network $network with vlan id $vlanid to vswitch $vswitch on $prism..." -ForegroundColor Green
        try {
        Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
        #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -SkipCertificateCheck -SslProtocol Tls12 -Body $payload -ErrorAction Stop
        } else {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -ErrorAction Stop
        }
        Write-Host "$(Get-Date) [SUCCESS] Successfully added network $network with vlan id $vlanid to vswitch $vswitch on $prism" -ForegroundColor Cyan
        }
        catch {
        $saved_error = $_.Exception.Message
        throw "$(get-date) [ERROR] $saved_error"
        }
        finally {
        }
        #endregion
    }
    #endregion

    #! -remove
    #region -remove
    if ($remove) {
        #region get network uuid
            #region prepare api call
            $api_server = $prism
            $api_server_port = "9440"
            $api_server_endpoint = "/PrismGateway/services/rest/v2.0/networks/" -f $network_uuid
            $url = "https://{0}:{1}{2}" -f $api_server,$api_server_port, `
                $api_server_endpoint
            $method = "GET"
            $headers = @{
                "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))));
                "Content-Type"="application/json";
                "Accept"="application/json"
            }
            #endregion

            #region make the api call
            Write-Host "$(Get-Date) [INFO] Getting details of network $network with vlan id $vlanid on vswitch $vswitch from $prism..." -ForegroundColor Green
            try {
                Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
                #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
                if ($PSVersionTable.PSVersion.Major -gt 5) {
                    $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -SkipCertificateCheck -SslProtocol Tls12 -ErrorAction Stop
                } else {
                    $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -ErrorAction Stop
                }
                Write-Host "$(Get-Date) [SUCCESS] Successfully retrieved details of network $network with vlan id $vlanid on vswitch $vswitch from $prism" -ForegroundColor Cyan
                if (!$uuid) {
                    $network_uuid = ($resp.entities | Where-Object {$_.name -eq $network} | Where-Object {$_.vswitch_name -eq $vswitch} | Where-Object {$_.vlan_id -eq $vlanid}).uuid
                    if (!$network_uuid) {
                        Write-Host "$(Get-Date) [ERROR] Could not find network $network on vswitch $vswitch on $prism!" -ForegroundColor Red
                        exit
                    }
                    if ($network_uuid -is [array]) {
                        Write-Host "$(Get-Date) [ERROR] There are multiple instances of network $network on vswitch $vswitch on $prism!" -ForegroundColor Red
                        exit
                    }
                } else {$network_uuid = $uuid}
            }
            catch {
                $saved_error = $_.Exception.Message
                throw "$(get-date) [ERROR] $saved_error"
            }
            finally {
            }
            #endregion
        #endregion
        #region delete network
            #region prepare api call
            $api_server = $prism
            $api_server_port = "9440"
            $api_server_endpoint = "/PrismGateway/services/rest/v2.0/networks/{0}" -f $network_uuid
            $url = "https://{0}:{1}{2}" -f $api_server,$api_server_port, `
                $api_server_endpoint
            $method = "DELETE"
            $headers = @{
                "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))));
                "Content-Type"="application/json";
                "Accept"="application/json"
            }
            #endregion

            #region make the api call
            Write-Host "$(Get-Date) [INFO] Deleting network $network with vlan id $vlanid to vswitch $vswitch on $prism..." -ForegroundColor Green
            try {
            Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
            #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
            if ($PSVersionTable.PSVersion.Major -gt 5) {
                $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -SkipCertificateCheck -SslProtocol Tls12 -ErrorAction Stop
            } else {
                $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -ErrorAction Stop
            }
            Write-Host "$(Get-Date) [SUCCESS] Successfully deleted network $network with vlan id $vlanid to vswitch $vswitch on $prism" -ForegroundColor Cyan
            }
            catch {
            $saved_error = $_.Exception.Message
            throw "$(get-date) [ERROR] $saved_error"
            }
            finally {
            }
            #endregion
        #endregion
    }
    #endregion

    #! -get
    #region -get
    if ($get) {
        #region get network details
            #region prepare api call
            $api_server = $prism
            $api_server_port = "9440"
            $api_server_endpoint = "/PrismGateway/services/rest/v2.0/networks/" -f $network_uuid
            $url = "https://{0}:{1}{2}" -f $api_server,$api_server_port, `
                $api_server_endpoint
            $method = "GET"
            $headers = @{
                "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))));
                "Content-Type"="application/json";
                "Accept"="application/json"
            }
            #endregion

            #region make the api call
            Write-Host "$(Get-Date) [INFO] Getting details of network $network with vlan id $vlanid on vswitch $vswitch from $prism..." -ForegroundColor Green
            try {
            Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
            #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
            if ($PSVersionTable.PSVersion.Major -gt 5) {
                $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -SkipCertificateCheck -SslProtocol Tls12 -ErrorAction Stop
            } else {
                $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -ErrorAction Stop
            }
            Write-Host "$(Get-Date) [SUCCESS] Successfully retrieved details of network $network with vlan id $vlanid on vswitch $vswitch from $prism" -ForegroundColor Cyan
            $network_details = $resp.entities | Where-Object {$_.name -eq $network}
            ForEach ($network_entry in $network_details) {
                Write-Host "Network Name: $($network_entry.name)" -ForegroundColor White
                Write-Host "VLAN id: $($network_entry.vlan_id)" -ForegroundColor White
                Write-Host "vSwitch: $($network_entry.vswitch_name)" -ForegroundColor White
                Write-Host "Description: $($network_entry.annotation)" -ForegroundColor White
                Write-Host "Uuid: $($network_entry.uuid)" -ForegroundColor White
                Write-Host
            }
            }
            catch {
            $saved_error = $_.Exception.Message
            throw "$(get-date) [ERROR] $saved_error"
            }
            finally {
            }
            #endregion
        #endregion
    }
    #endregion

#endregion processing

#region cleanup	
#let's figure out how much time this all took
Write-Host "$(get-date) [SUM] total processing time: $($myvarElapsedTime.Elapsed.ToString())" -ForegroundColor Magenta

#cleanup after ourselves and delete all custom variables
Remove-Variable myvar* -ErrorAction SilentlyContinue
Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
Remove-Variable help -ErrorAction SilentlyContinue
Remove-Variable history -ErrorAction SilentlyContinue
Remove-Variable log -ErrorAction SilentlyContinue
Remove-Variable username -ErrorAction SilentlyContinue
Remove-Variable password -ErrorAction SilentlyContinue
Remove-Variable prism -ErrorAction SilentlyContinue
Remove-Variable debugme -ErrorAction SilentlyContinue
Remove-Variable network_uuid -ErrorAction SilentlyContinue
Remove-Variable network -ErrorAction SilentlyContinue
Remove-Variable vswitch -ErrorAction SilentlyContinue
Remove-Variable vlanid -ErrorAction SilentlyContinue
Remove-Variable description -ErrorAction SilentlyContinue
Remove-Variable prismCreds -ErrorAction SilentlyContinue
#endregion