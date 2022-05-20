# PowerShell Miscellaneous Scripts

## This is where most of the PowerShell scripts reside, unless they fit neatly into another category.

### XML vars file
Moving forward, I will mostly be writing scripts to make use of an external files for variables.  This removes the need to constantly code-sign scripts every time I need to make the slightest change in the environment, like adding a VM or adjusting parameters.

Check [sample.xml](https://github.com/uchicago-ssd-sscs/windows/blob/main/sample.xml) for a template for putting your vars into xml format.

### RDSH_Monitor_Memory_Utilization
This is the first script to adopt the usage of an external file for vars.  See the XML vars file section above.  This script can be run as a scheduled task from a single "management" server that has WinRM access to all the machines in your RDS environment.  

I created this script to prepare for a wave of new users and the addition of a memory-intensive computational application to my RDSH servers.  There is a lower threshold which will generate an email warning, followed by an upper threshold where that user's processes are terminated (including their RDP session) and an additional email notification.

You will need to edit the path and filename of your xml vars file before you run it.  If code-signing is required in your environment, you will then have to re-sign the script.
