<#
.SYNOPSIS
  This script retrieves the list of unprotected (not in any protection domain) virtual machines from a given Nutanix cluster.
.DESCRIPTION
  The script uses v2 REST API in Prism to GET the list of unprotected VMs from /protection_domains/unprotected_vms/.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER cluster
  Nutanix cluster fully qualified domain name or IP address.
.PARAMETER username
  Username used to connect to the Nutanix cluster.
.PARAMETER password
  Password used to connect to the Nutanix cluster.
.PARAMETER prismCreds
  Specifies a custom credentials file name (will look for %USERPROFILE\Documents\WindowsPowerShell\CustomCredentials\$prismCreds.txt). These credentials can be created using the Powershell command 'Set-CustomCredentials -credname <credentials name>'. See https://blog.kloud.com.au/2016/04/21/using-saved-credentials-securely-in-powershell-scripts/ for more details.
.PARAMETER email
  Specifies that you want to email the output. This requires that you set up variables inside the script for smtp gateway and recipients.

.EXAMPLE
.\get-UnprotectedVms.ps1 -cluster ntnxc1.local -username admin -password admin
Retrieve the list of unprotected VMs from cluster ntnxc1.local

.LINK
  http://www.nutanix.com/services
.LINK
  https://github.com/sbourdeaud/nutanix
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: Feb 19th 2017
#>

#region parameters
######################################
##   parameters and initial setup   ##
######################################
#let's start with some command line parsing
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $true)] [string]$cluster,
    [parameter(mandatory = $false)] [string]$username,
    [parameter(mandatory = $false)] [string]$password,
    [parameter(mandatory = $false)] $prismCreds,
    [parameter(mandatory = $false)] [switch]$email
)
#endregion

#region functions
########################
##   main functions   ##
########################

#endregion

#region prepwork
# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}
#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 02/19/2018 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\get-UnprotectedVms.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}


    if ($PSVersionTable.PSVersion.Major -lt 5) 
    {#check PoSH version
        throw "$(get-date) [ERROR] Please upgrade to Powershell v5 or above (https://www.microsoft.com/en-us/download/details.aspx?id=50395)"
    }
    
    Write-Host "$(get-date) [INFO] Checking for required Powershell modules..." -ForegroundColor Green

    #region - module BetterTls
        if (!(Get-Module -Name BetterTls)) {
            Write-Host "$(get-date) [INFO] Importing module 'BetterTls'..." -ForegroundColor Green
            try
            {
                Import-Module -Name BetterTls -ErrorAction Stop
                Write-Host "$(get-date) [SUCCESS] Imported module 'BetterTls'!" -ForegroundColor Cyan
            }#end try
            catch #we couldn't import the module, so let's install it
            {
                Write-Host "$(get-date) [INFO] Installing module 'BetterTls' from the Powershell Gallery..." -ForegroundColor Green
                try {Install-Module -Name BetterTls -Scope CurrentUser -ErrorAction Stop}
                catch {throw "$(get-date) [ERROR] Could not install module 'BetterTls': $($_.Exception.Message)"}

                try
                {
                    Import-Module -Name BetterTls -ErrorAction Stop
                    Write-Host "$(get-date) [SUCCESS] Imported module 'BetterTls'!" -ForegroundColor Cyan
                }#end try
                catch #we couldn't import the module
                {
                    Write-Host "$(get-date) [ERROR] Unable to import the module BetterTls : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "$(get-date) [WARNING] Please download and install from https://www.powershellgallery.com/packages/BetterTls/0.1.0.0" -ForegroundColor Yellow
                    Exit
                }#end catch
            }#end catch
        }
        Write-Host "$(get-date) [INFO] Disabling Tls..." -ForegroundColor Green
        try {Disable-Tls -Tls -Confirm:$false -ErrorAction Stop} catch {throw "$(get-date) [ERROR] Could not disable Tls : $($_.Exception.Message)"}
        Write-Host "$(get-date) [INFO] Enabling Tls 1.2..." -ForegroundColor Green
        try {Enable-Tls -Tls12 -Confirm:$false -ErrorAction Stop} catch {throw "$(get-date) [ERROR] Could not enable Tls 1.2 : $($_.Exception.Message)"}
    #endregion

    #region - module sbourdeaud is used for facilitating Prism REST calls
        if (!(Get-Module -Name sbourdeaud)) 
        {#module sbourdeaud is not loaded...
            Write-Host "$(get-date) [INFO] Importing module 'sbourdeaud'..." -ForegroundColor Green
            try
            {#importing module sbourdeaud
                Import-Module -Name sbourdeaud -ErrorAction Stop
                Write-Host "$(get-date) [SUCCESS] Imported module 'sbourdeaud'!" -ForegroundColor Cyan
            }#end try
            catch 
            {#we couldn't import the module, so let's install it
                Write-Host "$(get-date) [INFO] Installing module 'sbourdeaud' from the Powershell Gallery..." -ForegroundColor Green
                try 
                {#installing module sbourdeaud for the current user
                    Install-Module -Name sbourdeaud -Scope CurrentUser -ErrorAction Stop
                }
                catch 
                {#couldn't install module sbourdeaud
                    throw "$(get-date) [ERROR] Could not install module 'sbourdeaud': $($_.Exception.Message)"
                }

                try
                {#trying again to import module sbourdeaud
                    Import-Module -Name sbourdeaud -ErrorAction Stop
                    Write-Host "$(get-date) [SUCCESS] Imported module 'sbourdeaud'!" -ForegroundColor Cyan
                }#end try
                catch 
                {#we couldn't import the module
                    Write-Host "$(get-date) [ERROR] Unable to import the module sbourdeaud.psm1 : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "$(get-date) [WARNING] Please download and install from https://www.powershellgallery.com/packages/sbourdeaud" -ForegroundColor Yellow
                    Exit
                }#end catch
            }#end catch
        }#endif module sbourdeaud
        if (((Get-Module -Name sbourdeaud).Version.Major -le 1) -and ((Get-Module -Name sbourdeaud).Version.Minor -le 1)) 
        {#check the version of module sbourdeaud
            Write-Host "$(get-date) [INFO] Updating module 'sbourdeaud'..." -ForegroundColor Green
            try 
            {#updating module sbourdeaud
                Update-Module -Name sbourdeaud -Scope CurrentUser -ErrorAction Stop
            }
            catch 
            {#we couldn't update module sbourdeaud
                throw "$(get-date) [ERROR] Could not update module 'sbourdeaud': $($_.Exception.Message)"
            }
        }
    #endregion


    #let's get ready to use the Nutanix REST API
    #Accept self signed certs
if (!$IsLinux) {
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol =  [System.Security.Authentication.SslProtocols] "tls, tls11, tls12"
}#endif not Linux

#endregion

#region variables

    #! Constants (for -email)
    $smtp_gateway = "" #add your smtp gateway address here
    $smtp_port = 25 #customize the smtp port here if necessary
    $recipients = "" #add a comma separated value of valid email addresses here
    $from = "" #add the from email address here
    $subject = "WARNING: Unprotected VMs in Nutanix cluster $cluster" #customize the subject here
    $body = "Please open the attached csv file and make sure the VMs listed are in protection domains on cluster $cluster"

    #initialize variables
	$ElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp

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
        $prismCredentials = Get-CustomCredentials -credname $prismCreds
        $username = $prismCredentials.UserName
        $PrismSecurePassword = $prismCredentials.Password
    }

#endregion

#region parameters validation
	############################################################################
	# command line arguments initialization
	############################################################################

    
#endregion

#region processing	
	################################
	##  Main execution here       ##
	################################
   
    #retrieving all AHV vm information
    Write-Host "$(get-date) [INFO] Retrieving list of unprotected VMs..." -ForegroundColor Green
    $url = "https://$($cluster):9440/api/nutanix/v2.0/protection_domains/unprotected_vms/"
    $method = "GET"
    $vmList = Get-PrismRESTCall -method $method -url $url -username $username -password ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))
    Write-Host "$(get-date) [SUCCESS] Successfully retrieved unprotected VMs list from $cluster!" -ForegroundColor Cyan

    
    Foreach ($vm in $vmList.entities) {
        Write-Host $vm.vm_name
    }#end foreach vm

    $vmList.entities | select -Property vm_name | export-csv -NoTypeInformation unprotected-vms.csv
    Write-Host "$(get-date) [SUCCESS] Exported list to unprotected-vms.csv" -ForegroundColor Cyan

    if ($email -and ($vmList.metadata.count -ge 1))
    {#user wants to send email and we have results
        Write-Host "$(get-date) [INFO] Emailing unprotected-vms.csv..." -ForegroundColor Green
        if ((!$smtp_gateway) -and (!$recipients) -and (!$from))
        {#user hasn't customized the script to enable email
            Write-Host "$(get-date) [ERROR] You must configure the smtp_gateway, recipients and from constants in the script (search for Constants in the script source code)!" -ForegroundColor Red
            Exit
        }
        else 
        {
            $attachment = ".\unprotected-vms.csv"
            Send-MailMessage -From $from -to $recipients -Subject $subject -Body $body -SmtpServer $smtp_gateway -port $smtp_port -Attachments $attachment 
        }
    }


#endregion

#region cleanup
#########################
##       cleanup       ##
#########################

	#let's figure out how much time this all took
    Write-Host "$(get-date) [SUM] total processing time: $($ElapsedTime.Elapsed.ToString())" -ForegroundColor Magenta
	
#endregion