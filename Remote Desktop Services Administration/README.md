# PowerShell Remote Desktop Services Administration Scripts

## These scripts are intended for managing a Microsoft Windows Remote Desktop Services environment.

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

### RDSH_Monitor_Memory_Utilization
This is the first script to adopt the usage of an external file for vars.  See the XML vars file section above.  This script can be run as a scheduled task from a single "management" server that has WinRM access to all the machines in your RDS environment.  

I created this script to prepare for a wave of new users and the addition of a memory-intensive computational application to my RDSH servers.  There is a lower threshold which will generate an email warning, followed by an upper threshold where that user's processes are terminated (including their RDP session) and an additional email notification.

