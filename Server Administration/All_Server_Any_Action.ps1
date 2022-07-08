#Perform any action on multiple designated servers.
#Author: Eric Hoy
#Date: 2021-04-26
#Last Modified: 2021-06-02


#Variables that can be edited
###########################################################

#Make sure to set this one unless you are using an alternative method below
$variables_file = "\\server.domain.com\myteam\Scripts\variables\sscs.xml"

#comment out this line if you decide to use one of the alternatives instead of an external data file
$target_computers = $null

###XML Alternative 1. Insert server names into the following variable
#$target_computers='RDSH-0','RDSH-1','RDSH-2','RDSH-3','RDSH-4','RDSH-5','RDSH-6','RDSH-7','RDSH-8','RDSL-0','RDGW-0','RDCB-0','FM','EM2019'

###XML Alternative 2.  Pull the server list from LDAP or Active Directory and select the ones to include graphically
#$ldap_search_base='OU=Servers,OU=Computers,OU=Division,DC=ad,DC=domain,DC=edu'
###Enumerate the list of Windows Servers
#$all_sscs_server_ad_objects=$(Get-ADComputer -Filter 'operatingsystem -like "*Windows Server*" -and enabled -eq "true"' -SearchBase $ldap_search_base -Properties Name, Operatingsystem, IPv4Address | Select-Object -Property Name, Operatingsystem, IPv4Address)
#$server_selection=($all_sscs_server_ad_objects | Out-GridView -Title "Select Servers to Clean Up" -PassThru) #graphical list to choose from
#$target_computers=@();
#foreach ($s in $server_selection) {
#    if (Test-Connection -Protocol WSMan -ComputerName $s.Name) {
#            $target_computers+=$s
#        }
#    else {
#        Write-Host "$s is not detected"
#        Write-Host "Skipping $s"
#        }
#    }




#These are fine to leave at the default values
###########################################################

$line_separator="**************************************************************************************"

###########################################################


$now=Get-Date -Format "yyyyMMddHHmm"

#import vars from xml file if it exists
if (Test-Path -Path $variables_file) {
   [xml]$sscs = Get-Content $variables_file
   $all_computers = $sscs.sscs.virtual_servers.name
   $requisite_files = $sscs.sscs.virtual_servers.requisite_files
   $requisite_directories = $null #$sscs.sscs.virtual_servers.requisite_directories
   $log_path = $sscs.sscs.virtual_servers.log_path
   }


#Select which servers to include in this run
$selected_servers=($all_computers | Out-GridView -PassThru)
$target_computers=@();
foreach ($computer in $selected_servers) {
    Write-Host "$computer is being added to the target list"
    if ($computer -ne $null) {
        $target_computers+=$computer
        }
    else {
        Write-Host "No computer was selected.  Exiting script."
        exit
        }
    }

#These are the items that will show on the pop-up selection list
$action_list='Show-ScheduledTasks','Show-Processes','Show-LocalAdmins','Sync-GroupPolicy','Show-FirewallBlockedConnections','Show-Systeminfo','Show-DiskFreeSpace','Start-GarbageCleanup','Start-ZeroFreeSpace','Start-CustomActions'


#Get list of actions that you want to perform
$selected_actions=($action_list | Out-GridView -PassThru)
$actions=@();
foreach ($a in $selected_actions) {
    Write-Host "$a is being added to the to-do list"
    if ($a -ne $null) {
        $actions+=$a
        }
    else {
        Write-Host "No action was selected.  Exiting script."
        exit
        }
    }

#Wipe out old remote PS sessions and establish new ones
Get-PSSession | Remove-PSSession
$Sessions=New-PSSession -ComputerName $target_computers -ErrorAction Continue -WarningAction Continue


#Creating requisite directories, if they don't exist already, and clear out previous AnyAction.log file
if (!($requisite_directories -eq $null)) { 
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        param($requisite_directories)
        $computer_name=$env:COMPUTERNAME
        if (Test-Path "C:\logs\AnyAction.log") { Write-Output $computer_name $now | Out-File "C:\logs\AnyAction.log" }
        foreach ($d in $requisite_directories.path) {
            if (!(Test-Path "$d")) {
                write-host "$d folder does not exist on $computer_name.  Creating it now"
                New-Item -ItemType Directory -Path $d
                }
            }
        Start-Sleep(1)
        } -ArgumentList($requisite_directories)
    }
    

#Make sure the sysinternals tools are located on the C: drive
foreach ($t in $target_computers) {
    $real_destination_path = ("\\"+$t+"\"+$requisite_files.destination_path)
    if (!(Test-Path -Path $real_destination_path)) {
        Write-Host "Copying item for $t at the path: $requisite_files.destination_path"
        Copy-Item -Recurse $requisite_files.source_path "$real_destination_path" -Verbose
        }
    }


#Enumerate scheduled tasks.  Filter out disabled tasks and include only the ones at the \ path
if ($actions.Contains("Show-ScheduledTasks")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        param($actions)
        $computer_name=$env:computername

        try {
            Write-Output "Gathering Scheduled Tasks on $computer_name"  | Out-File -Append -FilePath C:\logs\AnyAction.log
            Write-Output "Only enabled Tasks at the root directory will be displayed"  | Out-File -Append -FilePath C:\logs\AnyAction.log
            Get-ScheduledTask | Where-object -property State -NE 'Disabled' | Where-Object -Property TaskPath -EQ '\' | Select-Object -Property Author, State, TaskName, Description | Sort-object -Property Author | Out-File -Append -FilePath C:\logs\AnyAction.log
            }    
        catch {
            Write-Host "An error occurred with Scheduled Task Enumeration"
            Write-Host $_
            Write-Host $_.ScriptStackTrace
            }
        Start-Sleep(1)
        }
    }


#Show processes
if ($actions.Contains("Show-Processes")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        $processes = try {
            Write-Output "Gathering process info on $computer_name"  | Out-File -Append -FilePath C:\logs\AnyAction.log
            Get-Process -IncludeUserName | Sort-object -Descending -Property CPU | Out-File -Append -FilePath C:\logs\AnyAction.log
            }
        catch {
            Write-Host "An error occurred with Process Enumeration"
            Write-Host $_
            Write-Host $_.ScriptStackTrace
            }
        Start-Sleep(1)
        }
    }


#Get local Administrators
if ($actions.Contains("Show-LocalAdmins")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        $computer_name = $env:COMPUTERNAME

        try {
            $local_group="Administrators"
            foreach ($l in $local_group) {
                Write-Output "$l on $computer_name"  | Out-File -Append -FilePath C:\logs\AnyAction.log
                Get-LocalGroupMember -Group $l | Out-File -Append -FilePath C:\logs\AnyAction.log
                }
            }
        catch {"An error occurred gathering local Administrators"}
        Start-Sleep(1)
        }
    }


#Refresh Group Policy
if ($actions.Contains("Sync-GroupPolicy")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        $computer_name = $env:COMPUTERNAME

        Write-Output "Updating Group policy on $computer_name" | Out-File -Append -FilePath C:\logs\AnyAction.log
        gpupdate
        Start-Sleep(1)
        }
    } 


#Show recent blocked connections from the firewall log
if ($actions.Contains("Show-FirewallBlockedConnections")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        Write-Output "Sorting firewall log on $computer_name" | Tee-Object -Append -FilePath C:\logs\AnyAction.log
        Get-Content C:\Windows\System32\LogFiles\Firewall\pfirewall.log -Tail 500 | select-string -Pattern "DROP" | select-string -Pattern "224.0" -NotMatch | out-file -Append -FilePath C:\logs\AnyAction.log
        }
    } 


#Show systeminfo
if ($actions.Contains("Show-SystemInfo")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        param($actions)
        $computer_name = $env:COMPUTERNAME

        Write-Output "Pulling system info, including boot time, for $computer_name"  | Tee-Object -Append -FilePath C:\logs\AnyAction.log
        systeminfo | out-file -Append -FilePath C:\logs\AnyAction.log
        }
    Start-Sleep(1)
    }


#show disk free space
if ($actions.Contains("Show-DiskFreeSpace")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        $disks = $(Get-WmiObject Win32_LogicalDisk | Select-Object -ExpandProperty DeviceID)
        $computer_name = $env:COMPUTERNAME

        foreach ($disk in $disks) {
            $disk_info = $(Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$disk'" | Select-Object -Property *)
            $size = $disk_info.Size / 1GB
            $free = $disk_info.FreeSpace / 1GB
            Write-Output "$computer_name $disk Total:$size Free:$free" | Tee-Object -Append -FilePath C:\logs\AnyAction.log
            }
        }
        Start-Sleep(1) 
    }


#clean up superseded Windows Components and Service Packs.  Clean temp files.
if ($actions.Contains("Start-GarbageCleanup")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{
        
        #Begin cleanup of superseded Windows Components
        Write-Output "Cleaning up superseded Windows Components" | Tee-Object -Append "$logpath\systeminfo.txt"
        dism /online /Cleanup-Image /StartComponentCleanup /ResetBase | Tee-Object -Append "$logpath\systeminfo.txt"
        Write-Output $lineseparator | Tee-Object -Append "$logpath\systeminfo.txt"

        #Begin cleanup of superseded service packs
        Write-Output "Cleaning up superseded service packs" | Tee-Object -Append "$logpath\systeminfo.txt"
        dism /online /Cleanup-Image /SPSuperseded | Tee-Object -Append "$logpath\systeminfo.txt"
        Write-Output $lineseparator | Tee-Object -Append "$logpath\systeminfo.txt"

        #Use the built-in Windows Disk Cleanup Utility to re-check and to also delete temp files
        Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\*' | % {
                New-ItemProperty -Path $_.PSPath -Name StateFlags0001 -Value 2 -PropertyType DWord -Force
                }
        Start-Process -FilePath CleanMgr.exe -ArgumentList '/sagerun:1' -WindowStyle Hidden   
        }
        Start-Sleep(1)
    }


#zero out free space
if ($actions.Contains("Start-ZeroFreeSpace")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{     
        Write-Output "Free space in a VM is not able to be thinned on the VM host until this space is zeroed out."
        Write-Output "This process can take a VERY long time, possibly an entire day or longer."
        C:\InstallationFiles\Sysinternals\sdelete64.exe -z C: -accepteula
        Start-Sleep(1)
        }
    }


 #Run all custom script inside this block
if ($actions.Contains("Start-CustomActions")) {
    Invoke-Command -Session (Get-PSSession) -ScriptBlock{

        Write-Output "Running all custom script"
        
        #add Nexpose account to local Administrators
        #Add-LocalGroupMember -Group Administrators -Member "_sa-scan00"
    

        #Add the SID of the Network Service account to the Channel Access permissions on the Security Event Log
        #wevtutil sl security "/ca:O:BAG:SYD:(A;;0xf0005;;;SY)(A;;0x5;;;BA)(A;;0x1;;;S-1-5-32-573)(A;;0x1;;;S-1-5-20)"
       
        #Check for a specific hotfix
        #Get-Hotfix | Where-Object -Property HotFixID -like KB5004335

        #Install a .msu Microsoft Update package
        #wusa.exe has been deprecated.  Extract the cab file from the .msu and then install it with dism
        #cd c:
        #mkdir C:\InstallationFiles\flashremoval
        #expand -F:* "C:\installationfiles\windows10.0-kb4577586-x64_d0f434327db9e3308b86591c248c825c03687632.msu" "C:\installationfiles\flashremoval"
        #dism.exe /online /add-package /packagepath:"C:\installationfiles\flashremoval\Windows10.0-KB4577586-x64.cab" /quiet /norestart /logpath:"C:\logs\FlashRemoval_MicrosoftUpdate.log"
        #Check the installation of the update
        #$log=(Get-Content "C:\logs\FlashRemoval_MicrosoftUpdate.log")
        #Write-Host $log

        #another way to try to remove flash
        #Write-Host "Checking $Computername for Adobe Flash"
        #Get-Childitem -Path 'C:\Windows\SysWOW64\macromed'' | Remove-Item -Recurse -Force
        

        #work with services
        #Get-WmiObject win32_service | select-object -ExpandProperty startname
        #get-service | where-object -property Name -Like "*Spooler*"
        #Get-Service | Where-Object -Property Name -Like "Log Forwarder*" | stop-service
        #Get-Service | Where-Object -Property Name -Like "Log Forwarder*" | set-service -StartupType Disabled
    
        #Add EM2019 as an authorized computer to pull event logs
        #net localgroup "Event Log Readers" "AD\EM2019$" /ADD
        
        #get-process -IncludeUserName | Where-Object Name -Like "*Access*"

        #Write-Host "Checking $Computername for session logs"
        #Get-childitem C:\SessionLogs

        }           
    }

#Finally, pull content from the logs to display
Invoke-Command -Session (Get-PSSession) -ScriptBlock{
    param($actions,$line_separator)
    Get-Content C:\logs\AnyAction.log -Raw
    Write-Host $line_separator
    } -ArgumentList($actions,$line_separator)


