#Generate a Comprehensive Windows Server Baseline Report for Auditing and Reference
#Entire detail of relevant GPOs as well as RSOPs
#Software installed
#Windows Updates
#Example of old security services that should not be present
#Search for new security services that should be installed
#Pull BPA scans if present
#Pull Performance Monitors 
#Local Users and Group Membership

#Author: Eric Hoy
#Date: 2021-01-25
#Last Modified: 2022-04-20


##############################################################################
#These variables definitely need to be edited to fit your organization
$target_computers='server1','server2','server3','server4','server5'
$gpo_folder_path="\\myfileserver\server\windows\Baseline Reports\GPO"
$gpo_name_search_string='<portion of GPO name to search for>'
$current_antivirus="Crowdstrike"
$current_antivirus_service_name="CSFalcon"
$old_antivirus="Cylance"
$old_antivirus_service_name="Cylance"
$vulnerability_scanner="Rapid7"
$vulnerability_scanner_service="ir_agent"
$export_path="\\myfileserver\server\windows\Baseline Reports\exports"

#You can leave this at the default if you want
$gpo_list_name='GPOlist.csv'

##############################################################################
#No need to edit below

$Now=Get-Date -Format "yyyyMMddHHmm"

#We need the target directory to be created and named with the timestamp
Write-Host "Generating GPO reports"
New-Item -Path $gpo_folder_path -Name $Now -ItemType "directory"
$GPOName=Get-GPO -All -Domain ad.uchicago.edu | Where-Object {$_.DisplayName -like "$gpo_name_search_string*"} | Select Displayname | Export-Csv ($gpo_folder_path+"\"+$Now+"\"+$gpo_list_name)
#Human Readable Version of GPO report
Import-Csv ($gpo_folder_path+"\"+$Now+"\"+$gpo_list_name) | Select-Object -ExpandProperty DisplayName | ForEach-Object {Get-GPOReport -Domain ad.uchicago.edu -Name $_ -ReportType HTML -Path ($gpo_folder_path+"\"+$Now+"\"+"$_"+".html")} 
#Machine Readable version of GPO report
Import-Csv ($gpo_folder_path+"\"+$Now+"\"+$gpo_list_name) | Select-Object -ExpandProperty DisplayName | ForEach-Object {Get-GPOReport -Domain ad.uchicago.edu -Name $_ -ReportType XML -Path ($gpo_folder_path+"\"+$Now+"\"+"$_"+".xml")} 

Get-PSSession | Remove-PSSession
$Sessions=(New-PSSession -ComputerName $target_computers -ErrorAction SilentlyContinue)

Invoke-Command -Session (Get-PSSession) -ThrottleLimit 16 -ScriptBlock {
    param($now)
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Confirm:$false -Force
    #Install the Necessary Modules  -  comment these out if the modules are already installed
    Install-WindowsFeature -Name gpmc
    Install-Module PackageManagement -MinimumVersion 1.0.0.1
    Install-Module PowershellGet -MinimumVersion 1.0.0.1
    Install-Module PSWindowsUpdate -MinimumVersion 2.2.0.2
    Import-Module PackageManagement
    Import-Module PowershellGet
    Import-Module PSWindowsUpdate

    $computer_name=$env:computername
    $logparent = "C:\logs"
    $uptime=$((get-date) - (gcim Win32_OperatingSystem).LastBootUpTime)
    If(!(test-path $logparent)) {
        New-Item -ItemType Directory -Force -Path $logparent
        }
    $today=Get-Date -Format "yyyyMMdd"
    $logpath = "$logparent\$Now-$computer_name"
    $lineseparator = "*********************************************************"

    If(!(test-path "$logpath")) {
        New-Item -ItemType Directory -Force -Path $logpath
        }


    #Installed Applications and Features
    Write-Output "Installed Applications and Windows Features for $computer_name" | Tee-Object -Append "$logpath\InstalledProgramsWMI.txt"
    Get-WmiObject -Class Win32_Product -ComputerName $computer_name | select @{Name="Computer";Expression={ $computer_name }}, Name, Version | Tee-Object -Append "$logpath\InstalledProgramsWMI.txt"
    Write-Host
    Write-Output "Some applications not included in the above list will show in the Program Files or Program Files (x86) directories" | Tee-Object -Append "$logpath\InstalledProgramsWMI.txt"
    Get-childitem -Recurse -Depth 1 -Path 'C:\Program Files' | Tee-Object -Append "$logpath\InstalledProgramsWMI.txt"
    Get-childitem -Recurse -Depth 1 -Path 'C:\Program Files (x86)' | Tee-Object -Append "$logpath\InstalledProgramsWMI.txt"
    Get-WindowsFeature | Select-Object -Property  @{ Name = 'Computername'; Expression = {$env:COMPUTERNAME}},Name,Installstate | Tee-Object -Append "$logpath\InstalledProgramsWMI.txt"

    #Syslogging
    Write-Output "Looking for SolarWinds Service  on $computer_name" | Tee-Object -Append "$logpath\Security.txt"
    Get-Service | Where-Object -Property Name -Like "Log Forwarder*"  | Tee-Object -Append "$logpath\Security.txt"
    Write-Output "Looking for RSysLog Service  on $computer_name" | Tee-Object -Append "$logpath\Security.txt"
    Get-Service | Where-Object -Property Name -Like "RSysLog*"  | Tee-Object -Append "$logpath\Security.txt"

    #All services, with status
    Write-Output "" | Tee-Object -Append "$logpath\Security.txt"
    Write-Output "Enumerating services on $computer_name" | Tee-Object -Append "$logpath\Security.txt"
    Get-Service | Select-Object -Property *  | Tee-Object -Append "$logpath\Security.txt"

    #Antivirus
    Write-Output "" | Tee-Object -Append "$logpath\Security.txt"
    Write-Output "Looking for $current_antivirus Antivirus on $computer_name" | Tee-Object -Append "$logpath\Security.txt"
    Get-Service | Where-Object -Property Name -Like "$current_antivirus_service_name*" | Tee-Object -Append "$logpath\Security.txt"

    #Vulnerability Scan
    Write-Output "" | Tee-Object -Append "$logpath\Security.txt"
    Write-Output "Looking for $vulnerability_scanner Vulnerability Scan on $computer_name" | Tee-Object -Append "$logpath\Security.txt"
    Get-Service | Where-Object -Property Name -Like "$vulnerability_scanner_service*" | Tee-Object -Append "$logpath\Security.txt"

    #Old Security Software
    Write-Output "" | Tee-Object -Append "$logpath\Security.txt"
    Write-Output "Looking for $old_antivirus - THIS PRODUCT SHOULD NOT BE INSTALLED - on $computer_name" | Tee-Object -Append "$logpath\Security.txt"
    Get-Service | Where-Object -Property Name -Like "$old_antivirus_service_name*" | Tee-Object -Append "$logpath\Security.txt"

    #Windows Firewall Rules
    #Write-Output "Exporting Firewall Rules from $computer_name" | Tee-Object -Append "$logpath\Firewall.txt"
    #Write-Output "PLEASE KEEP IN MIND THAT GPO FIREWALL SETTINGS OVERRIDE LOCAL FIREWALL SETTINGS IN THIS ENVIRONMENT." | Tee-Object -Append "$logpath\Firewall.txt"
    #Write-Output "THIS IS MAINLY FOR REFERENCE." | Tee-Object -Append "$logpath\Firewall.txt"
    #$Rules=Get-NetFirewallRule -All
    #foreach ($Rule in $Rules) {
    #    $Rulename=$($Rule | Select-Object -ExpandProperty DisplayName,Description)
    #    Write-Output $Rulename | Out-File -Append "$logpath\Firewall.txt"
    #   Get-NetFirewallPortFilter -AssociatedNetFirewallRule $Rule | Out-File -Append "$logpath\Firewall.txt"
    #    Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $Rule | Select-Object -Property LocalAddress,RemoteAddress,LocalIP,RemoteIP | Out-File -Append "$logpath\Firewall.txt"
    #    Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $Rule | Select-Object -Property Program | Out-File -Append "$logpath\Firewall.txt"
    #    Write-Output "*****************************************************************************************" | Out-File -Append "$logpath\Firewall.txt"
    #    }
    

    #Group Membership
    Write-Output "Looking for local users on $computer_name" | Tee-Object -Append "$logpath\localusers.txt"
    $localusers=$(Get-LocalUser)
    Write-Output $localusers | Tee-Object -Append "$logpath\localusers.txt"
    Write-Output "Looking for local groups and their members on $computer_name" | Tee-Object -Append "$logpath\localgroups.txt"
    $localgroups=$(Get-LocalGroup)
    foreach ($group in $localgroups) {
        Write-Output $lineseparator | Tee-Object -Append "$logpath\localgroups.txt"
        Write-Output "Enumerating membership of $group" | Tee-Object -Append "$logpath\localgroups.txt"
        Get-LocalGroupMember -Group $group | Tee-Object -Append "$logpath\localgroups.txt"
        }


    #Enumerate Important Folders
    $Cdrive=$(Get-Childitem -Depth 1 C:\)
    $Programfiles=$(Get-Childitem -Depth 1 'C:\Program Files\')
    $Programfilesx86=$(Get-Childitem -Depth 1 'C:\Program Files (x86)\')
    $Ddrive=$(Get-Childitem -Depth 1 D:\)
    $Edrive=$(Get-Childitem -Depth 1 E:\)
    $Fdrive=$(Get-Childitem -Depth 1 F:\)
    Write-Output "Getting file list for the C drive on $computer_name" | Tee-Object -Append "$logpath\Directories.txt"
    Write-Output $Cdrive | Out-File -Append "$logpath\Directories.txt"
    Write-Output "Getting file list for the Program Files directory on $computer_name" | Tee-Object -Append "$logpath\Directories.txt"
    Write-Output $Programfiles | Out-File -Append "$logpath\Directories.txt"
    Write-Output "Getting file list for the Program Files (x86) directory on $computer_name" | Tee-Object -Append "$logpath\Directories.txt"
    Write-Output $Programfilesx86 | Out-File -Append "$logpath\Directories.txt"
    Write-Output "Getting file list for the D drive on $computer_name" | Tee-Object -Append "$logpath\Directories.txt"
    Write-Output $Ddrive | Out-File -Append "$logpath\Directories.txt"
    Write-Output "Getting file list for the E drive on $computer_name" | Tee-Object -Append "$logpath\Directories.txt"
    Write-Output $Edrive | Out-File -Append "$logpath\Directories.txt"
    Write-Output "Getting file list for the F drive on $computer_name" | Tee-Object -Append "$logpath\Directories.txt"
    Write-Output $Fdrive | Out-File -Append "$logpath\Directories.txt"

    #Microsoft Updates and hotfixes
    Write-Output "Gathering Windows Update and Hotfix info on $computer_name" | Tee-Object -Append "$logpath\WindowsUpdates.txt"
    Get-WUInstall -MicrosoftUpdate -AcceptAll -Verbose | Tee-Object -Append "$logpath\WindowsUpdates.txt"
    Get-HotFix | Tee-Object -Append "$logpath\WindowsUpdates.txt"

    #Uptime and General System info
    Write-Output "Gathering Uptime and General System Info on $computer_name" | Tee-Object -Append "$logpath\systeminfo.txt"
    Write-Output $uptime | Tee-Object -Append "$logpath\systeminfo.txt"
    Invoke-Expression -Command ('systeminfo >> "$logpath\systeminfo.txt"')

    #Performance Monitors - if any are already configured in the GUI
    Write-Host "Gathering Performance Monitor files, if available, on $computer_name"
    Copy-Item "C:\PerfLogs\Admin\ServerManager\SNPerfMon-$today*.*" -Destination "$logpath"

    #BPA scan results
    Write-Output "If there are no results detailed below, there are no Best Practice scans available on $computer_name" | Tee-Object -Append "$logpath\BPAresults.txt"
    Get-BpaModel | Get-BpaResult -All -ErrorAction SilentlyContinue | Tee-Object -Append "$logpath\BPAresults.txt"

    #Export GPO
    Write-Host "Gathering GPO and RSOP on $computer_name"
    Get-GPResultantSetofPolicy -ReportType HTML -Path "$logpath\GPO-RSOP.html"

    #Compress the Directory
    Write-Host "Compressing today's logfile directory on $computer_name"
    Compress-Archive -Path "$logpath\*" -DestinationPath "$logpath-BASELINE.zip" -Update -ErrorAction SilentlyContinue

    #Depending on Role, create additional backups
    #RDWeb/Gateway
    If ($computer_name -Like "*RDGW*") {
        Write-Host "This is an RD Web server.  Backing up important files on $computer_name"
        $backup_name=($computer_name+'_IIS_'+$today)
        Backup-WebConfiguration -Name $backup_name -ErrorAction SilentlyContinue
        copy-item "C:\Windows\Web" "C:\Backup" -Recurse -Force 
        copy-item "C:\Windows\System32\Inetsrv" "C:\Backup" -Recurse -Force
        }
    #RDCB (Connection Broker)
    If ($computer_name -Like "*RDCB*") {
        Write-Host "This is an RD Connection Broker.  Backing up registry on $computer_name"
        #If this is a new connection broker you might have to remove the comment from the following line:
        #Install-Module sqlserver
        REG EXPORT "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server" "C:\Backup\RDCB_TS_Reg.reg" /y
    
        #The following line has been substituted for a nightly scheduled task to avoid daytime disruptions
        #Invoke-Sqlcmd -InputFile "C:\Backup\BackupRDCB.sql" | Tee-Object -Append "C:\Backup\BackupRDCB_LOG.txt"
        }

    
    Set-ExecutionPolicy -ExecutionPolicy AllSigned -Confirm:$false -Force

} -ArgumentList $Now -ErrorAction Continue

#Wait a few seconds before continuing
ping -n 10 www.google.com

#Put baseline and log files on the network (assuming that the RDGW and RDCB above are backed up in some other way)
foreach ($Session in $Sessions) {
    Write-Host $Session
    $Now=Get-Date -Format "yyyyMMdd"
    $current_machine=$(Invoke-Command -Session $Session -Scriptblock {Write-Output $env:computername})
    $Logzip=$(Invoke-Command -Session $Session -Scriptblock {Get-Childitem C:\logs | where-object -property Name -Like $Now*.zip | Select-Object -ExpandProperty Name | Write-Output})
    Write-Host $current_machine
    Write-Host $Logzip
    Copy-Item "\\$current_machine\C$\logs\*.zip" "$report_output_directory" -Verbose
    Remove-Item "\\$current_machine\C$\logs\*.zip"
    }


#Clean up the local log files
Invoke-Command -Session $Session -Scriptblock {Remove-Item -Recurse "C:\logs\*"} 
Get-PSSession | Remove-PSSession

