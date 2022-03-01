# hoy-windows
Windows (mostly PowerShell) scripts for sharing publicly.  This is under GPL licensing, which basically means you are free to use, 
modify, and share this however you want but you must publish the source code of any derivative work.

## RDSH_Monitor_Memory_Utilization
Windows has excellent "Fair Share" enforcement of CPU, network, and disk I/O resources but NOTHING buit in for memory usage.
There are third party solutions, but nothing on the market has met my specific needs.

I created this script initially to prepare an RDS environment to move beyond lightweight applications and to accommodate 
resource-intensive computational jobs.  Without any preventive measures, a single user can takeall physical memory on an 
RD Session Host, causing excessive paging and making the machine unresponsive to other users.

I created this simple, short script to warn RDS users when their memory utilization exceeds an alert threshold.
There is also a quota threshold.  When exceeded, a user's session will be logged off and another email alert will be sent.

This will most likely be best utilized as a Scheduled Task.

### Requirements
- Windows RDS Deployment.  Tested on Windows 2019.
- Active Directory
- Administrator access to all servers in the RDS deployment
- One management server or computer with WinRM access to all servers in the RDS deployment
- An open SMTP relay inside your network

### Usage
- If you are enforcing a PowerShell Execution Policy of AllSigned you will need to edit the variables and then code-sign the script.
- The script does not accept args.  You will need to edit the vars at the top of the script.
- If you run into issues with the Execution Policy or running as a Scheduled Task, run with these options:
```
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NonInteractive -NoProfile -ExecutionPolicy bypass -file "<path_to_the script>\RDSH_Monitor_memory_utilization.ps1"
```
