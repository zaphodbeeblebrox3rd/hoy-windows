## These scripts are intended for managing a VMware environment with a lot of VMs.

### XML vars file
I will mostly be writing scripts to make use of an external files for variables.  This removes the need to constantly code-sign scripts every time I need to make the slightest change in the environment, like adding a VM or adjusting parameters.

Check [sample.xml](https://github.com/zaphodbeeblebrox3rd/hoy-windows/blob/main/sample.xml) for a template for putting your vars into xml format.

You will need to edit the path and filename of your xml vars file before you run it.  If code-signing is required in your environment, you will then have to re-sign the script.

Every script will have a var referencing the path of the external xml file.  Modify this to point to wherever you save your xml file:
> $variables_file = "\\server.domain.comu\myteam\Scripts\variables\sample.xml"

Inside each script, you will see a block which pulls the xml data into variables.  
** This is how you will know which variables are required to be set in your xml file for each script **
~~~~
if (Test-Path -Path $variables_file) {
   [xml]$sample = Get-Content $variables_file
   $all_computers = $sample.sscs.virtual_servers.name
   $requisite_files = $sample.sscs.virtual_servers.requisite_files
   $requisite_directories = $sample.sscs.virtual_servers.requisite_directories
   $log_path = $sample.sscs.virtual_servers.log_path
   }
~~~~

### VM_snapshot_Selected_Servers.ps1
Use this script for making fresh snapshots of your VMs.  The OS is not important, but this is particularly useful for Windows VMs due to snapshots older than 30 days tending to lose their domain connectivity or to be behind on their Windows updates.

There will be a prompt for your credentials, which will be stored encrypted in a variable for the duration of your PowerShell session.

An additional prompt will ask you whether you want to clean up old snapshots, or if you type 'n' it will leave the old snapshots in place.

### VMware_ESXi_Host_Check_DateTime.ps1
This script will poll all of your ESXi servers for date and time.  You should probably have them all pointed to your organization's NTP server but this is an easy way to see if any of them are drifting to the point where it may become a problem.  

 

