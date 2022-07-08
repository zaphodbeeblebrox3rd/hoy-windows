#Windows Back up ESXi configuration from all hosts - SSCS Server Team
#Author: Eric Hoy
#Created: 2022-06-29
#Modified:


#Make sure to set this one, or comment it out if you are not going to use an xml data file
$variables_file = "\\harbor.uchicago.edu\sscs-server\Scripts\variables\sscs.xml"

#These are fine to leave at the default values
$line_separator="**************************************************************************************"

#Use these only if you have opted out of using the xml file for vars
#$hosts='10.10.1.3','10.10.1.4','10.10.1.5','10.10.1.6''
#$vcenter_ip='10.10.1.10'
$vcenter_user='username'


#############################################################################################


#import vars from xml file if it exists
if (Test-Path -Path $variables_file) {
   [xml]$sscs = Get-Content $variables_file
   $all_computers = $sscs.sscs.virtual_servers.name
   $requisite_files = $sscs.sscs.virtual_servers.requisite_files
   $requisite_directories = $null #$sscs.sscs.virtual_servers.requisite_directories
   $log_path = $sscs.sscs.virtual_servers.log_path
   }

#You must have this module, minimum version 12.1.0.16009493, on this computer to proceed. 
Install-Module VMWare.PowerCLI -MinimumVersion 12.1.0.17009493 -AllowClobber

$credential = Get-Credential $vcenter_user

Connect-VIServer -Server $vcenter_ip -Credential $credential

Get-VMHost | sort Name | select Name,@{Name="Current VMHost Time";Expression={(Get-View $_.ExtensionData.ConfigManager.DateTimeSystem).QueryDateTime()}}

