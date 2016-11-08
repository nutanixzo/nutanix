<#
.SYNOPSIS
  This script configures DNS and NTP for all hosts in a given cluster.
.DESCRIPTION
  This script configures the DNS domain name, primary DNS server, secondary DNS server and NTP servers for all hosts in a given vSphere cluster.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER vcenter
  VMware vCenter server hostname. You can specify several hostnames by separating entries with commas and using double quotes. If none is specified, the script will prompt you.
.PARAMETER cluster
  vSphere cluster name. If none is specified, the script will prompt you.
.PARAMETER domain
  Domain name (exp: acme.local). If none is specified, the script will prompt you.
.PARAMETER dns
  IP address(es) of the DNS server(s). Separate multiple entries with commas and use double quotes. You can specify up to two DNS servers. If none is specified, the script will prompt you.
.PARAMETER ntp
  IP address(es) of the NTP server(s).  Separate multiple entries with commas and use double quotes. You can specify up to two NTP servers. If none is specified, the script will prompt you.
.PARAMETER clearntp
  If specified, this will clear the existing ntp server configuration instead of appending to it.
.EXAMPLE
  Configure all hosts in clusterA:
  PS> .\set-hostconfig.ps1 -vcenter myvcenter.mydomain.local -cluster clusterA -domain mydomain.local -dns "10.10.10.1,10.10.10.2" -ntp "10.10.10.1,10.10.10.2"
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: October 1st 2015
#>

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
    [parameter(mandatory = $false)] [string]$vcenter,
    [parameter(mandatory = $false)] [string]$cluster,
    [parameter(mandatory = $false)] [string]$domain,
    [parameter(mandatory = $false)] [string]$dns,
    [parameter(mandatory = $false)] [string]$ntp,
	[parameter(mandatory = $false)] [boolean]$clearntp
)

# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}

########################
##   main functions   ##
########################

#this function is used to output log data
Function OutputLogData 
{
	#input: log category, log message
	#output: text to standard output
<#
.SYNOPSIS
  Outputs messages to the screen and/or log file.
.DESCRIPTION
  This function is used to produce screen and log output which is categorized, time stamped and color coded.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER myCategory
  This the category of message being outputed. If you want color coding, use either "INFO", "WARNING", "ERROR" or "SUM".
.PARAMETER myMessage
  This is the actual message you want to display.
.EXAMPLE
  PS> OutputLogData -mycategory "ERROR" -mymessage "You must specify a cluster name!"
#>
	param
	(
		[string] $category,
		[string] $message
	)

    begin
    {
	    $myvarDate = get-date
	    $myvarFgColor = "Gray"
	    switch ($category)
	    {
		    "INFO" {$myvarFgColor = "Green"}
		    "WARNING" {$myvarFgColor = "Yellow"}
		    "ERROR" {$myvarFgColor = "Red"}
		    "SUM" {$myvarFgColor = "Magenta"}
	    }
    }

    process
    {
	    Write-Host -ForegroundColor $myvarFgColor "$myvarDate [$category] $message"
	    if ($log) {Write-Output "$myvarDate [$category] $message" >>$myvarOutputLogFile}
    }

    end
    {
        Remove-variable category
        Remove-variable message
        Remove-variable myvarDate
        Remove-variable myvarFgColor
    }
}#end function OutputLogData

#########################
##   main processing   ##
#########################

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 10/01/2015 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\set-hostconfig.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}



#let's make sure the VIToolkit is being used
if ((Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null)#is it already there?
{
	Add-PSSnapin VMware.VimAutomation.Core #no? let's add it
	if (!$?) #have we been able to add it successfully?
	{
		OutputLogData -category "ERROR" -message "Unable to load the PowerCLI snapin.  Please make sure PowerCLI is installed on this server."
		return
	}
} 
#Initialize-VIToolkitEnvironment.ps1 | Out-Null

#let's load the Nutanix cmdlets
#if ((Get-PSSnapin -Name NutanixCmdletsPSSnapin -ErrorAction SilentlyContinue) -eq $null)#is it already there?
#{
#	Add-PSSnapin NutanixCmdletsPSSnapin #no? let's add it
#	if (!$?) #have we been able to add it successfully?
#	{
#		OutputLogData -category "ERROR" -message "Unable to load the Nutanix snapin.  Please make sure the Nutanix Cmdlets are installed on this server."
#		return
#	}
#}

#initialize variables
	#misc variables
	$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
	$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
	$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
	$myvarOutputLogFile += "OutputLog.log"
	
	############################################################################
	# command line arguments initialization
	############################################################################	
	#let's initialize parameters if they haven't been specified
	if (!$vcenter) {$vcenter = read-host "Enter vCenter server name or IP address"}#prompt for vcenter server name
	$myvarvCenterServers = $vcenter.Split(",") #make sure we parse the argument in case it contains several entries
    if (!$cluster) {$cluster = read-host "Enter the vSphere cluster name"}
    if (!$domain) {$domain = read-host "Enter DNS domain name"}
    if (!$dns) {$dns = read-host "Enter primary and secondary DNS servers separated by a comma and WITHOUT double quotes"}
    $myvarDns = $dns.Split(",") #make sure we parse the argument in case it contains several entries
    if (!$ntp) {$ntp = read-host "Enter primary and secondary NTP servers separated by a comma and WITHOUT double quotes"}
    $myvarNtp = $ntp.Split(",") #make sure we parse the argument in case it contains several entries
	
	
	################################
	##  foreach vCenter loop      ##
	################################
	foreach ($myvarvCenter in $myvarvCenterServers)	
	{
		OutputLogData -category "INFO" -message "Connecting to vCenter server $myvarvCenter..."
		if (!($myvarvCenterObject = Connect-VIServer $myvarvCenter))#make sure we connect to the vcenter server OK...
		{#make sure we can connect to the vCenter server
			$myvarerror = $error[0].Exception.Message
			OutputLogData -category "ERROR" -message "$myvarerror"
			return
		}
		else #...otherwise show the error message
		{
			OutputLogData -category "INFO" -message "Connected to vCenter server $myvarvCenter."
		}#endelse
		
		if ($myvarvCenterObject)
		{
		
			######################
			#main processing here#
			######################
            
            #let's gather hosts in the cluster
            OutputLogData -category "INFO" -message "Figuring out which hosts are in cluster $cluster..."
            $myvarHosts = get-cluster -name $cluster | Get-VMHost

            foreach ($myvarHost in $myvarHosts)
            {
                OutputLogData -category "INFO" -message "Configuring DNS domain name and servers for $myvarHost..."
                Get-VMHostNetwork -VMHost $myvarHost | Set-VMHostNetwork -DomainName $domain -DnsAddress $myvarDns[0], $myvarDns[1] -Confirm:$false | out-null

                if ($clearntp)
				{
					OutputLogData -category "INFO" -message "Clearing NTP servers for $myvarHost..."
					$myvarExistingNTParray = $myvarHost | Get-VMHostNTPServer
					Remove-VMHostNTPServer -NtpServer $myvarExistingNTParray -Confirm:$false | out-null 
                }#endif
				
				OutputLogData -category "INFO" -message "Configuring NTP servers for $myvarHost..."
				Add-VMHostNtpServer -NtpServer $myvarNtp[0], $myvarNtp[1] -VMHost $myvarHost | out-null

                OutputLogData -category "INFO" -message "Configuring NTP client policy for $myvarHost..."
                Get-VMHostService -VMHost $myvarHost | where {$_.Key -eq "ntpd"} | Set-VMHostService -policy "on" -Confirm:$false | out-null

                OutputLogData -category "INFO" -message "Restarting NTP client on $myvarHost..."
                Get-VMHostService -VMHost $myvarHost | where {$_.Key -eq "ntpd"} | Restart-VMHostService -Confirm:$false | out-null
            }#end foreach host loop
		
		}#endif
        OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
		Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	}#end foreach vCenter
	
#########################
##       cleanup       ##
#########################

	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"
	
	#cleanup after ourselves and delete all custom variables
	Remove-Variable myvar*
	Remove-Variable ErrorActionPreference
	Remove-Variable help
    Remove-Variable history
	Remove-Variable log
	Remove-Variable vcenter
    Remove-Variable debug
    Remove-Variable cluster
    Remove-Variable domain
    Remove-Variable dns
    Remove-Variable ntp