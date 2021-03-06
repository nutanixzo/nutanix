<#
.SYNOPSIS
  This script connects to Prism Central and for each managed cluster, returns
  the CPU oversubscription ratio.
.DESCRIPTION
  This script connects to Prism Central and for each managed cluster, returns
  the CPU oversubscription ratio (total number of allocated vCPUs / number of 
  logical cores).
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER prismcentral
  Nutanix Prism Central fully qualified domain name or IP address.
.PARAMETER username
  Username used to connect to the Nutanix cluster.
.PARAMETER password
  Password used to connect to the Nutanix cluster.
.PARAMETER prismCreds
  Specifies a custom credentials file name (will look for %USERPROFILE\Documents\WindowsPowerShell\CustomCredentials\$prismCreds.txt on Windows or in $home/$prismCreds.txt on Mac and Linux).
.PARAMETER ignorePoweredOff
  Ignores VMs which are powered off.
.EXAMPLE
.\get-AhvCpuRatio.ps1 -cluster ntnxc1.local -username admin -password admin
Connect to a Nutanix Prism Central VM of your choice and compute the CPU 
oversubscription ratio for each managed AHV cluster.
.LINK
  http://github.com/sbourdeaud/nutanix
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: September 23rd 2019
#>

#region parameters
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $true)] [string]$prismcentral,
    [parameter(mandatory = $false)] [string]$username,
    [parameter(mandatory = $false)] [string]$password,
    [parameter(mandatory = $false)] $prismCreds,
    [parameter(mandatory = $false)] [switch]$ignorePoweredOff
)
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

#region prepwork

$HistoryText = @'
Maintenance Log
Date       By   Updates (newest updates at the top)
---------- ---- ---------------------------------------------------------------
09/23/2019 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\get-AhvCpuRatio.ps1"

if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}

#check PoSH version
if ($PSVersionTable.PSVersion.Major -lt 5) {throw "$(get-date) [ERROR] Please upgrade to Powershell v5 or above (https://www.microsoft.com/en-us/download/details.aspx?id=50395)"}

# ignore SSL warnings
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

#region variables
$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew()
#prepare our overall results variable
[System.Collections.ArrayList]$myvarVmResults = New-Object System.Collections.ArrayList($null)
[System.Collections.ArrayList]$myvarHostResults = New-Object System.Collections.ArrayList($null)
[System.Collections.ArrayList]$myvarClusterResults = New-Object System.Collections.ArrayList($null)
[System.Collections.ArrayList]$myvarReport = New-Object System.Collections.ArrayList($null)
$length=100 #this specifies how many entities we want in the results of each API query
#endregion

#region parameters validation
if (!$prismCreds) 
{#we are not using custom credentials, so let's ask for a username and password if they have not already been specified
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
else 
{ #we are using custom credentials, so let's grab the username and password from that
    try 
    {
        $prismCredentials = Get-CustomCredentials -credname $prismCreds -ErrorAction Stop
        $username = $prismCredentials.UserName
        $PrismSecurePassword = $prismCredentials.Password
    }
    catch 
    {
        $credname = Read-Host "Enter the credentials name"
        Set-CustomCredentials -credname $credname
        $prismCredentials = Get-CustomCredentials -credname $prismCreds -ErrorAction Stop
        $username = $prismCredentials.UserName
        $PrismSecurePassword = $prismCredentials.Password
    }
}
#endregion

#region prepare api call (get vms)
$api_server_port = "9440"
$api_server_endpoint = "/api/nutanix/v3/vms/list"
$url = "https://{0}:{1}{2}" -f $prismcentral,$api_server_port, $api_server_endpoint
$method = "POST"

$headers = @{
    "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword))) ));
    "Content-Type"="application/json";
    "Accept"="application/json"
}

# this is used to capture the content of the payload
$content = @{
    kind="vm";
    offset=0;
    length=$length
}
$payload = (ConvertTo-Json $content -Depth 4)
#endregion

#region make api call and process results (get vms)
Do {
    Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
    try {
        #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -SkipCertificateCheck -SslProtocol Tls12 -ErrorAction Stop
        } else {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -ErrorAction Stop
        }
        Write-Host "$(get-date) [SUCCESS] Call $method to $url succeeded." -ForegroundColor Cyan 
        Write-Host "$(Get-Date) [INFO] Processing results from $($resp.metadata.offset) to $($resp.metadata.offset + $resp.metadata.length) out of $($resp.metadata.total_matches)" -ForegroundColor Green
        if ($debugme) {Write-Host "$(Get-Date) [DEBUG] Response Metadata: $($resp.metadata | ConvertTo-Json)" -ForegroundColor White}

        #grab the information we need in each entity
        ForEach ($entity in $resp.entities) {
            if ($entity.spec.resources.num_sockets) {
                $myvarVmInfo = [ordered]@{
                    "num_sockets" = $entity.spec.resources.num_sockets;
                    "power_state" = $entity.spec.resources.power_state;
                    "cluster" = $entity.spec.cluster_reference.name;
                    "hypervisor" = $entity.status.resources.hypervisor_type;
                    "cluster_uuid" = $entity.status.cluster_reference.uuid;
                }
                #store the results for this entity in our overall result variable
                $myvarVmResults.Add((New-Object PSObject -Property $myvarVmInfo)) | Out-Null
            }
        }

        #prepare the json payload for the next batch of entities/response
        $content = @{
            kind="vm";
            offset=($resp.metadata.length + $resp.metadata.offset);
            length=$length
        }
        $payload = (ConvertTo-Json $content -Depth 4)
    }
    catch {
        $saved_error = $_.Exception.Message
        # Write-Host "$(Get-Date) [INFO] Headers: $($headers | ConvertTo-Json)"
        Write-Host "$(Get-Date) [INFO] Payload: $payload" -ForegroundColor Green
        Throw "$(get-date) [ERROR] $saved_error"
    }
    finally {
        #add any last words here; this gets processed no matter what
    }
}
While ($resp.metadata.length -eq $length)

if ($debugme) {
    Write-Host "$(Get-Date) [DEBUG] Showing results:" -ForegroundColor White
    $myvarVmResults
}
#endregion

#region prepare api call (get hosts)
$api_server_port = "9440"
$api_server_endpoint = "/api/nutanix/v3/hosts/list"
$url = "https://{0}:{1}{2}" -f $prismcentral,$api_server_port, $api_server_endpoint
$method = "POST"

$headers = @{
    "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword))) ));
    "Content-Type"="application/json";
    "Accept"="application/json"
}

# this is used to capture the content of the payload
$content = @{
    kind="host";
    offset=0;
    length=$length
}
$payload = (ConvertTo-Json $content -Depth 4)
#endregion

#region make api call and process results (get hosts)
Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
Do {
    try {
        #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -SkipCertificateCheck -SslProtocol Tls12 -ErrorAction Stop
        } else {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -ErrorAction Stop
        }
        
        Write-Host "$(get-date) [SUCCESS] Call $method to $url succeeded." -ForegroundColor Cyan 
        Write-Host "$(Get-Date) [INFO] Processing results from $($resp.metadata.offset) to $($resp.metadata.offset + $resp.metadata.length) out of $($resp.metadata.total_matches)" -ForegroundColor Green
        if ($debugme) {Write-Host "$(Get-Date) [DEBUG] Response Metadata: $($resp.metadata | ConvertTo-Json)" -ForegroundColor White}

        #grab the information we need in each entity
        ForEach ($entity in $resp.entities) {
            if ($entity.status.resources.num_cpu_sockets) {
                $myvarHostInfo = [ordered]@{
                    "num_cpu_sockets" = $entity.status.resources.num_cpu_sockets;
                    "num_cpu_cores" = $entity.status.resources.num_cpu_cores;
                    #"num_cpu_total_cores" = ($entity.status.resources.num_cpu_sockets * $entity.status.resources.num_cpu_cores);
                    "cluster_uuid" = $entity.status.cluster_reference.uuid;
                }
                #store the results for this entity in our overall result variable
                $myvarHostResults.Add((New-Object PSObject -Property $myvarHostInfo)) | Out-Null
            }
        }

        #prepare the json payload for the next batch of entities/response
        $content = @{
            kind="host";
            offset=($resp.metadata.length + $resp.metadata.offset);
            length=$length
        }
        $payload = (ConvertTo-Json $content -Depth 4)
    }
    catch {
        $saved_error = $_.Exception.Message
        # Write-Host "$(Get-Date) [INFO] Headers: $($headers | ConvertTo-Json)"
        Write-Host "$(Get-Date) [INFO] Payload: $payload" -ForegroundColor Green
        Throw "$(get-date) [ERROR] $saved_error"
    }
    finally {
        #add any last words here; this gets processed no matter what
    }
}
While ($resp.metadata.length -eq $length)

if ($debugme) {
    Write-Host "$(Get-Date) [DEBUG] Showing results:" -ForegroundColor White
    $myvarHostResults
}
#endregion

#region prepare api call (get clusters)
$api_server_port = "9440"
$api_server_endpoint = "/api/nutanix/v3/clusters/list"
$url = "https://{0}:{1}{2}" -f $prismcentral,$api_server_port, $api_server_endpoint
$method = "POST"

$headers = @{
    "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword))) ));
    "Content-Type"="application/json";
    "Accept"="application/json"
}

# this is used to capture the content of the payload
$content = @{
    kind="cluster";
    offset=0;
    length=$length
}
$payload = (ConvertTo-Json $content -Depth 4)
#endregion

#region make api call and process results (get clusters)
Write-Host "$(Get-Date) [INFO] Making a $method call to $url" -ForegroundColor Green
Do {
    try {
        #check powershell version as PoSH 6 Invoke-RestMethod can natively skip SSL certificates checks and enforce Tls12
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -SkipCertificateCheck -SslProtocol Tls12 -ErrorAction Stop
        } else {
            $resp = Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $payload -ErrorAction Stop
        }
        
        Write-Host "$(get-date) [SUCCESS] Call $method to $url succeeded." -ForegroundColor Cyan 
        Write-Host "$(Get-Date) [INFO] Processing results from $($resp.metadata.offset) to $($resp.metadata.offset + $resp.metadata.length) out of $($resp.metadata.total_matches)" -ForegroundColor Green
        if ($debugme) {Write-Host "$(Get-Date) [DEBUG] Response Metadata: $($resp.metadata | ConvertTo-Json)" -ForegroundColor White}

        #grab the information we need in each entity
        ForEach ($entity in $resp.entities) {
            if ($entity.status.resources.nodes.hypervisor_server_list) {
                $myvarClusterInfo = [ordered]@{
                    "cluster_name" = $entity.spec.name;
                    "hypervisor" = $entity.status.resources.nodes.hypervisor_server_list[0].type;
                    "cluster_uuid" = $entity.metadata.uuid;
                }
                #store the results for this entity in our overall result variable
                $myvarClusterResults.Add((New-Object PSObject -Property $myvarClusterInfo)) | Out-Null
            }
        }

        #prepare the json payload for the next batch of entities/response
        $content = @{
            kind="host";
            offset=($resp.metadata.length + $resp.metadata.offset);
            length=$length
        }
        $payload = (ConvertTo-Json $content -Depth 4)
    }
    catch {
        $saved_error = $_.Exception.Message
        # Write-Host "$(Get-Date) [INFO] Headers: $($headers | ConvertTo-Json)"
        Write-Host "$(Get-Date) [INFO] Payload: $payload" -ForegroundColor Green
        Throw "$(get-date) [ERROR] $saved_error"
    }
    finally {
        #add any last words here; this gets processed no matter what
    }
}
While ($resp.metadata.length -eq $length)

if ($debugme) {
    Write-Host "$(Get-Date) [DEBUG] Showing results:" -ForegroundColor White
    $myvarClusterResults
}
#endregion

#region process and print overall results
ForEach ($cluster in $myvarClusterResults) {
    if ($ignorePoweredOff) {
        $myvarAllocatedvCpus = ($myvarVmResults | where {$_.cluster_uuid -eq $cluster.cluster_uuid} | where {$_.power_state -eq "ON"} | measure num_sockets -sum).Sum
        $myvarAveragevCpuAllocation = [math]::Round(($myvarVmResults | where {$_.cluster_uuid -eq $cluster.cluster_uuid} | where {$_.power_state -eq "ON"} | measure num_sockets -average).Average)
    }
    else {
        $myvarAllocatedvCpus = ($myvarVmResults | where {$_.cluster_uuid -eq $cluster.cluster_uuid} | measure num_sockets -sum).Sum
        $myvarAveragevCpuAllocation = [math]::Round(($myvarVmResults | where {$_.cluster_uuid -eq $cluster.cluster_uuid} | measure num_sockets -average).Average)
    }
    $myvarTotalCores = ($myvarHostResults | where {$_.cluster_uuid -eq $cluster.cluster_uuid} | measure num_cpu_cores -sum).Sum
    $myvarCpuRatio = [math]::Round($myvarAllocatedvCpus / $myvarTotalCores,2)
    $myvarClusterReport = [ordered]@{
        "cluster_name" = $cluster.cluster_name;
        "hypervisor" = $cluster.hypervisor;
        "cluster_uuid" = $cluster.cluster_uuid;
        "allocated_vcpus" = $myvarAllocatedvCpus;
        "average_vcpu_allocation" = $myvarAveragevCpuAllocation;
        "total_cores" = $myvarTotalCores;
        "cpu_ratio" = $myvarCpuRatio;
    }
    #store the results for this entity in our overall result variable
    $myvarReport.Add((New-Object PSObject -Property $myvarClusterReport)) | Out-Null
}
$myvarClusterReport | ft
#endregion

#region Cleanup	
#let's figure out how much time this all took
Write-Host "$(Get-Date) [SUM] total processing time: $($myvarElapsedTime.Elapsed.ToString())" -ForegroundColor Magenta

#cleanup after ourselves and delete all custom variables
Remove-Variable myvar* -ErrorAction SilentlyContinue
Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
Remove-Variable help -ErrorAction SilentlyContinue
Remove-Variable history -ErrorAction SilentlyContinue
Remove-Variable log -ErrorAction SilentlyContinue
Remove-Variable username -ErrorAction SilentlyContinue
Remove-Variable password -ErrorAction SilentlyContinue
Remove-Variable cluster -ErrorAction SilentlyContinue
Remove-Variable debugme -ErrorAction SilentlyContinue
#endregion
