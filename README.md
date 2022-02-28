# hoy-windows
Windows (mostly PowerShell) scripts for sharing publicly.  This is under GPL licensing, which basically means you are free to use, 
modify, and share this however you want but you must publish the source code of any derivative work.

## RDSH_Monitor_Memory_Utilization
Windows has excellent "Fair Share" enforcement of CPU, network, and disk I/O resources but NOTHING buit in for memory usage.
There are third party solutions, but nothing that meets my needs.

I created this script initially to prepare an RDS environment to move beyond lightweight applications and to accommodate 
resource-intensive computational jobs in R, Python, and Matlab.  Without any preventive measures, a single user can take
all physical memory on an RD Session Host, causing excessive paging and making the machine unusable for other users.

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
- There are no command-line options.  Just edit the vars at the top of the script.
