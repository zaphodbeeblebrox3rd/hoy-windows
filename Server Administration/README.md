# hoy-windows
Windows (mostly PowerShell) scripts for sharing publicly.  This is under GPL licensing, which basically means you are free to use, 
modify, and share this however you want but you must publish the source code of any derivative work.

### Requirements
- Windows Servers
- Active Directory
- Administrator access to all specified servers 
- One management server or computer with WinRM access to all servers in the RDS deployment

### Usage
- If you are enforcing a PowerShell Execution Policy of AllSigned you will need to edit the variables and then code-sign the script.
- The script does not accept args.  You will need to edit the vars at the top of the script.
- If you run into issues with the Execution Policy or running as a Scheduled Task, run PowerShell with these options:
```
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NonInteractive -NoProfile -ExecutionPolicy bypass -file "<path_to_the script>\All_Server_Folder_Size_report.ps1"
```

## All_Server_Folder_Size_report
The Server Manager GUI provides a good overview of disk utilization of your servers.  This script gives you the ability to dive deeper to find out what is actually taking up all that space!

To avoid the fatigue of entering all server hostnames into a list var, this will accept a specified OU in Active Directory.  A popup window will allow you to highlight the servers you want to include in the current run.  Use the usual combination of shift or ctrl keys with the mouse to highlight multiple servers.

Enumerating the folder sizes can take a long time despite which tool you use.  This will run in parallel on selected servers to give you the results as fast as possible.


## All_Server_Baseline_Config_Export
For auditing and reference, I like to run a baseline report of my Windows servers on at least a quarterly basis.  This script will generate a report including GPOs, RSOPs, installed software, check on running security services, Windows Updates, BPA results, Performance Monitor results, local users, and group membership.  Basically all the stuff you would want but would never get around to doing without an automatic process.

Note that I commented out the local firewall stuff.  Feel free to remove the commenting and use that if needed.  I think firewall config should be done in GPO to prevent unexpected "firewall drift" but I have heard others disagree with that opinion.

### Requirements
- Windows Servers
- Active Directory
- Administrator access to all specified servers 
- One management server or computer with WinRM access to all servers in the RDS deployment
- A network share to put all the exports
- Basic organization of your AD and a meaningful naming convention for your servers and GPOs.

### Variables of Note
- $target_computers are enumerated by hand.  I could swap this out with a search by AD OU but I'm not sure what will be preferable to users.
- $gpo_name_search_string is a common string in all GPO names you want included.  Hopefully, you are organized and are using some sort of naming convention to take advantage of this.
- $computer_name is used in the blocks for RD Gateway and RD Connection Broker roles.  If you have servers in this role, you will either have to put "RDGW" / "RDCB" in their hostname or you will need to edit the code to accomodate the appropriate string for hostname matching.