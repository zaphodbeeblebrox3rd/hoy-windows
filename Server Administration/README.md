# hoy-windows
Windows (mostly PowerShell) scripts for sharing publicly.  This is under GPL licensing, which basically means you are free to use, 
modify, and share this however you want but you must publish the source code of any derivative work.

## All_Server_Folder_Size_report
The Server Manager GUI provides a good overview of disk utilization of your servers.  This script gives you the ability to dive deeper to find out what is actually taking up all that space!

To avoid the fatigue of entering all server hostnames into a list var, this will accept a specified OU in Active Directory.  A popup window will allow you to highlight the servers you want to include in the current run.  Use the usual combination of shift or ctrl keys with the mouse to highlight multiple servers.

Enumerating the folder sizes can take a long time despite which tool you use.  This will run in parallel on selected servers to give you the results as fast as possible.

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
