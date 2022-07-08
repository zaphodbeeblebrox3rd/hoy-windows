# Connect to a single vCenter Server
# Clear out old VM snapshots for multiple VMs and create fresh snapshots based on pattern match of server hostname
# Author: Eric Hoy
# Date: 2020-10-08
# Date Modified: 2022-07-07


# These variables can be edited
#####################################

# Make sure to set this one unless you are using an alternative method below
$variables_file = "\\server.domain.comu\myteam\Scripts\variables\sample.xml"

# comment out this line if you decide to use one of the alternatives instead of an external data file
$target_computers = $null

### XML Alternative 1. Insert server names into the following variable
# $target_computers='RDSH-0','RDSH-1','RDSH-2','RDSH-3','RDSH-4','RDSH-5','RDSH-6','RDSH-7','RDSH-8','RDSL-0','RDGW-0','RDCB-0','FM','EM2019'

### XML Alternative 2.  Pull the server list from LDAP or Active Directory and select the ones to include graphically
# $ldap_search_base='OU=Servers,OU=Computers,OU=Division,DC=ad,DC=domain,DC=edu'
### Enumerate the list of Windows Servers
# $all_sscs_server_ad_objects=$(Get-ADComputer -Filter 'operatingsystem -like "*Windows Server*" -and enabled -eq "true"' -SearchBase $ldap_search_base -Properties Name, Operatingsystem, IPv4Address | Select-Object -Property Name, Operatingsystem, IPv4Address)
# $server_selection=($all_sscs_server_ad_objects | Out-GridView -Title "Select Servers to Clean Up" -PassThru) #graphical list to choose from
# $target_computers=@();
# foreach ($s in $server_selection) {
#    if (Test-Connection -Protocol WSMan -ComputerName $s.Name) {
#            $target_computers+=$s
#        }
#    else {
#        Write-Host "$s is not detected"
#        Write-Host "Skipping $s"
#        }
#    }

# local directory for report outputs, and other variables
# These will be pulled from the external xml file if you're using one.  
# If not, remove the commenting from these vars
# $LogPath='C:\logs'
# $log_entries_per_vm=50
# $default_snapshot_description='Fresh Snapshots for Domain Connectivity'
# $report_header=$default_snapshot_description
# $vcenter='1.2.3.4'

# These are fine to leave at the default values
###########################################################

$line_separator="**************************************************************************************"

###########################################################

#Don't edit below
####################################

$now=Get-Date -Format "yyyyMMddHHmm"

#Import-Module VMWare.vimautomation.core

#import vars from xml file if it exists
if (Test-Path -Path $variables_file) {
   [xml]$sscs = Get-Content $variables_file
   $all_computers = $sscs.sscs.virtual_servers.name
   $log_path = $sscs.sscs.virtual_servers.log_path
   $log_entries_per_vm = $sscs.sscs.virtual_servers.log_entries_per_vm
   $vcenter = $sscs.sscs.vcenter.primary_name
   $default_snapshot_description = 'Fresh Snapshots for Domain Connectivity'
   $vcenter_username = $sscs.sscs.vcenter.username
   }


if (($snapshot_description = Read-Host "Press enter to accept default snapshot description: $default_snapshot_description") -eq '') {$default_snapshot_description} else {$snapshot_description}

#Override any certificate issues
Set-PowerCLIConfiguration -InvalidCertificateAction Warn -Confirm:$false

#Get connected to vCenter Server
$credential = Get-Credential $vcenter_username
Connect-VIServer -Server $vcenter -Credential $credential


#Get VMs, but only the ones selected by the user
$server_selection=($all_computers | Out-GridView -PassThru)
$virtual_machines=@();
foreach ($s in $server_selection) {
    Write-Host $s
    if ($s -ne $null) {
        $vm = Get-VM | Where {$_.Name -like $s}
        $virtual_machines+=$vm
        }
    else {
        Write-Host "$s is not detected in this VM space"
        Write-Host "Skipping $s"
        }
    }

$snapshots = $virtual_machines | Get-Snapshot
 
$date = Get-Date

#Generate the data for the PreCleanupSnapshotReport
$precleanupreport = $snapshots `
| Select-Object VM, Name, Uid, Created, @{Name="Age"; Expression = {New-TimeSpan -Start $_.Created -End $date}}, Description `
| Sort-Object -Property "VM"

#Write the data into a readable HTML file 
$pre_cleanup_snapshot_report_html = $precleanupreport | ConvertTo-Html -Head $report_header -PreContent "Pre-Cleanup Report Date: $date" 
Remove-Item $log_path\PreCleanupSnapshot.html
New-item $log_path\PreCleanupSnapshot.html
Set-Content $log_path\PreCleanupSnapshot.html $pre_cleanup_snapshot_report_html

$old_snapshot_cleanup=$(Read-Host "Do you want to clean up previous snapshots on these VMs? y or n")
If ($old_snapshot_cleanup -Like "y") {
    Remove-Snapshot $snapshots
    }

sleep -Seconds 10

$virtual_machines | ForEach-Object {New-Snapshot -Name $snapshot_description -Description $snapshot_description -VM $_.Name}

$new_snapshots = $virtual_machines | Get-Snapshot

#Generate data for PostCleanupSnapshotReport
$postcleanupreport = $new_snapshots `
| Select-Object VM, Name, Uid, Created, @{Name="Age"; Expression = {New-TimeSpan -Start $_.Created -End $date}}, Description `
| Sort-Object -Property "VM"

#Write data into a readable HTML file
$post_cleanup_snapshot_report_html = $postcleanupreport | ConvertTo-Html -Head $snapshot_description -PreContent "Post-Cleanup Report Date: $date" 
Remove-Item $log_path\PostCleanupSnapshot.html
New-item $log_path\PostCleanupSnapshot.html
Set-Content $log_path\PostCleanupSnapshot.html $post_cleanup_snapshot_report_html


