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



# SIG # Begin signature block
# MIIlGQYJKoZIhvcNAQcCoIIlCjCCJQYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUmMIT09bqQq5ClfljjgeboTmi
# Lhuggh8BMIIFgTCCBGmgAwIBAgIQOXJEOvkit1HX02wQ3TE1lTANBgkqhkiG9w0B
# AQwFADB7MQswCQYDVQQGEwJHQjEbMBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVy
# MRAwDgYDVQQHDAdTYWxmb3JkMRowGAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEh
# MB8GA1UEAwwYQUFBIENlcnRpZmljYXRlIFNlcnZpY2VzMB4XDTE5MDMxMjAwMDAw
# MFoXDTI4MTIzMTIzNTk1OVowgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpOZXcg
# SmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVTRVJU
# UlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRpZmljYXRp
# b24gQXV0aG9yaXR5MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAgBJl
# FzYOw9sIs9CsVw127c0n00ytUINh4qogTQktZAnczomfzD2p7PbPwdzx07HWezco
# EStH2jnGvDoZtF+mvX2do2NCtnbyqTsrkfjib9DsFiCQCT7i6HTJGLSR1GJk23+j
# BvGIGGqQIjy8/hPwhxR79uQfjtTkUcYRZ0YIUcuGFFQ/vDP+fmyc/xadGL1RjjWm
# p2bIcmfbIWax1Jt4A8BQOujM8Ny8nkz+rwWWNR9XWrf/zvk9tyy29lTdyOcSOk2u
# TIq3XJq0tyA9yn8iNK5+O2hmAUTnAU5GU5szYPeUvlM3kHND8zLDU+/bqv50TmnH
# a4xgk97Exwzf4TKuzJM7UXiVZ4vuPVb+DNBpDxsP8yUmazNt925H+nND5X4OpWax
# KXwyhGNVicQNwZNUMBkTrNN9N6frXTpsNVzbQdcS2qlJC9/YgIoJk2KOtWbPJYjN
# hLixP6Q5D9kCnusSTJV882sFqV4Wg8y4Z+LoE53MW4LTTLPtW//e5XOsIzstAL81
# VXQJSdhJWBp/kjbmUZIO8yZ9HE0XvMnsQybQv0FfQKlERPSZ51eHnlAfV1SoPv10
# Yy+xUGUJ5lhCLkMaTLTwJUdZ+gQek9QmRkpQgbLevni3/GcV4clXhB4PY9bpYrrW
# X1Uu6lzGKAgEJTm4Diup8kyXHAc/DVL17e8vgg8CAwEAAaOB8jCB7zAfBgNVHSME
# GDAWgBSgEQojPpbxB+zirynvgqV/0DCktDAdBgNVHQ4EFgQUU3m/WqorSs9UgOHY
# m8Cd8rIDZsswDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEQYDVR0g
# BAowCDAGBgRVHSAAMEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwuY29tb2Rv
# Y2EuY29tL0FBQUNlcnRpZmljYXRlU2VydmljZXMuY3JsMDQGCCsGAQUFBwEBBCgw
# JjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuY29tb2RvY2EuY29tMA0GCSqGSIb3
# DQEBDAUAA4IBAQAYh1HcdCE9nIrgJ7cz0C7M7PDmy14R3iJvm3WOnnL+5Nb+qh+c
# li3vA0p+rvSNb3I8QzvAP+u431yqqcau8vzY7qN7Q/aGNnwU4M309z/+3ri0ivCR
# lv79Q2R+/czSAaF9ffgZGclCKxO/WIu6pKJmBHaIkU4MiRTOok3JMrO66BQavHHx
# W/BBC5gACiIDEOUMsfnNkjcZ7Tvx5Dq2+UUTJnWvu6rvP3t3O9LEApE9GQDTF1w5
# 2z97GA1FzZOFli9d31kWTz9RvdVFGD/tSo7oBmF0Ixa1DVBzJ0RHfxBdiSprhTEU
# xOipakyAvGp4z7h/jnZymQyd/teRCBaho1+VMIIFnzCCBIegAwIBAgIQZvQSLmk9
# U6aXNceD/LajVTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzELMAkGA1UE
# CBMCTUkxEjAQBgNVBAcTCUFubiBBcmJvcjESMBAGA1UEChMJSW50ZXJuZXQyMREw
# DwYDVQQLEwhJbkNvbW1vbjElMCMGA1UEAxMcSW5Db21tb24gUlNBIENvZGUgU2ln
# bmluZyBDQTAeFw0yMTAyMDIwMDAwMDBaFw0yNDAyMDIyMzU5NTlaMIHPMQswCQYD
# VQQGEwJVUzEOMAwGA1UEEQwFNjA2MzcxETAPBgNVBAgMCElsbGlub2lzMRAwDgYD
# VQQHDAdDaGljYWdvMSAwHgYDVQQJDBc1ODAxIFNvdXRoIEVsbGlzIEF2ZW51ZTEi
# MCAGA1UECgwZVGhlIFVuaXZlcnNpdHkgb2YgQ2hpY2FnbzEhMB8GA1UECwwYU29j
# aWFsIFNjaWVuY2VzIERpdmlzaW9uMSIwIAYDVQQDDBlUaGUgVW5pdmVyc2l0eSBv
# ZiBDaGljYWdvMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1ZmalmZ8
# 1iMojw0yY5BzVFNVEPIrMABO0rwtL57+D+VYoFG7snb8K135sBXsMFgJTXFaIODe
# UMDvoXOLABChsOaFtmwOQu5Qdc2hkdOjNzdDT/GcW/3HnFzIB/HZYxoOSnDDJdoV
# 0DAlJe+DPaNq/UuYLXp4AnHkjeOdLUmnMB8ONJoFpediLVIMXIlV8RxscsHEfwKM
# LNAWExHXhDSNLuIcfZgzjFK5I1OjRI1xcErKCVYVo2G2s/aZaSZZzKdYeRvslxOq
# oDnnX6ysfxMTZVQiFsuhDhiHc44YyAaPkdUylvCcOLhncFrFa2c4ozKV6gEXDu8/
# HNulvpszxuRxdwIDAQABo4IBxzCCAcMwHwYDVR0jBBgwFoAUrjUjF///Bj2cUOCM
# JGUzHnAQiKIwHQYDVR0OBBYEFExR2TFGFX0Ps1ni0BRNtH6LvHe3MA4GA1UdDwEB
# /wQEAwIHgDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMBEGCWCG
# SAGG+EIBAQQEAwIEEDBwBgNVHSAEaTBnMFsGDCsGAQQBriMBBAMCATBLMEkGCCsG
# AQUFBwIBFj1odHRwczovL3d3dy5pbmNvbW1vbi5vcmcvY2VydC9yZXBvc2l0b3J5
# L2Nwc19jb2RlX3NpZ25pbmcucGRmMAgGBmeBDAEEATBJBgNVHR8EQjBAMD6gPKA6
# hjhodHRwOi8vY3JsLmluY29tbW9uLXJzYS5vcmcvSW5Db21tb25SU0FDb2RlU2ln
# bmluZ0NBLmNybDB+BggrBgEFBQcBAQRyMHAwRAYIKwYBBQUHMAKGOGh0dHA6Ly9j
# cnQuaW5jb21tb24tcnNhLm9yZy9JbkNvbW1vblJTQUNvZGVTaWduaW5nQ0EuY3J0
# MCgGCCsGAQUFBzABhhxodHRwOi8vb2NzcC5pbmNvbW1vbi1yc2Eub3JnMA0GCSqG
# SIb3DQEBCwUAA4IBAQC5stOq/hJrRME8+sLYXWX9Zvqr9VC/Nqs8NzHLFKGtcbNO
# 1/pSE7AWZqpTotOCcESqxmkV+Clgt60gWaKN4aaO7txW4BtjyQPiajDXFPYx4r3r
# wLWHd+dvzIGSWEZ2nOCwyAEHN2a38pd+F40MT/8Q/Ip13PQq0xT8l7PX6YhP7jZm
# eGMWdLxJPy1qdUKR5Jy7UhNhh3RtvZLxhZpMPef9HZx+gH5ne1qI54qM+q7hFRAc
# qL9s3qbtHPZimcKgf+JriUyr10qFuzMTezpb2BXHg9P4UUUgrPc0sk0JJ1tJsoBL
# 7tFmcPoBLCAJYStSlBMbkZ/z6PNb0Me6GNg4PpDAMIIF6zCCA9OgAwIBAgIQZeHi
# 49XeUEWF8yYkgAXi1DANBgkqhkiG9w0BAQ0FADCBiDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQK
# ExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBSU0Eg
# Q2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTQwOTE5MDAwMDAwWhcNMjQwOTE4
# MjM1OTU5WjB8MQswCQYDVQQGEwJVUzELMAkGA1UECBMCTUkxEjAQBgNVBAcTCUFu
# biBBcmJvcjESMBAGA1UEChMJSW50ZXJuZXQyMREwDwYDVQQLEwhJbkNvbW1vbjEl
# MCMGA1UEAxMcSW5Db21tb24gUlNBIENvZGUgU2lnbmluZyBDQTCCASIwDQYJKoZI
# hvcNAQEBBQADggEPADCCAQoCggEBAMCgL4seertqdaz4PtyjujkiyvOjduS/fTAn
# 5rrTmDJWI1wGhpcNgOjtooE16wv2Xn6pPmhz/Z3UZ3nOqupotxnbHHY6WYddXpnH
# obK4qYRzDMyrh0YcasfvOSW+p93aLDVwNh0iLiA73eMcDj80n+V9/lWAWwZ8gleE
# VfM4+/IMNqm5XrLFgUcjfRKBoMABKD4D+TiXo60C8gJo/dUBq/XVUU1Q0xciRuVz
# GOA65Dd3UciefVKKT4DcJrnATMr8UfoQCRF6VypzxOAhKmzCVL0cPoP4W6ks8frb
# eM/ZiZpto/8Npz9+TFYj1gm+4aUdiwfFv+PfWKrvpK+CywX4CgkCAwEAAaOCAVow
# ggFWMB8GA1UdIwQYMBaAFFN5v1qqK0rPVIDh2JvAnfKyA2bLMB0GA1UdDgQWBBSu
# NSMX//8GPZxQ4IwkZTMecBCIojAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgw
# BgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzARBgNVHSAECjAIMAYGBFUdIAAw
# UAYDVR0fBEkwRzBFoEOgQYY/aHR0cDovL2NybC51c2VydHJ1c3QuY29tL1VTRVJU
# cnVzdFJTQUNlcnRpZmljYXRpb25BdXRob3JpdHkuY3JsMHYGCCsGAQUFBwEBBGow
# aDA/BggrBgEFBQcwAoYzaHR0cDovL2NydC51c2VydHJ1c3QuY29tL1VTRVJUcnVz
# dFJTQUFkZFRydXN0Q0EuY3J0MCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2Vy
# dHJ1c3QuY29tMA0GCSqGSIb3DQEBDQUAA4ICAQBGLLZ/ak4lZr2caqaq0J69D65O
# NfzwOCfBx50EyYI024bhE/fBlo0wRBPSNe1591dck6YSV22reZfBJmTfyVzLwzai
# bZMjoduqMAJr6rjAhdaSokFsrgw5ZcUfTBAqesReMJx9THLOFnizq0D8vguZFhOY
# IP+yunPRtVTcC5Jf6aPTkT5Y8SinhYT4Pfk4tycxyMVuy3cpY333HForjRUedfwS
# RwGSKlA8Ny7K3WFs4IOMdOrYDLzhH9JyE3paRU8albzLSYZzn2W6XV2UOaNU7KcX
# 0xFTkALKdOR1DQl8oc55VS69CWjZDO3nYJOfc5nU20hnTKvGbbrulcq4rzpTEj1p
# msuTI78E87jaK28Ab9Ay/u3MmQaezWGaLvg6BndZRWTdI1OSLECoJt/tNKZ5yeu3
# K3RcH8//G6tzIU4ijlhG9OBU9zmVafo872goR1i0PIGwjkYApWmatR92qiOyXkZF
# hBBKek7+FgFbK/4uy6F1O9oDm/AgMzxasCOBMXHa8adCODl2xAh5Q6lOLEyJ6sJT
# MKH5sXjuLveNfeqiKiUJfvEspJdOlZLajLsfOCMN2UCx9PCfC2iflg1MnHODo2Ot
# SOxRsQg5G0kH956V3kRZtCAZ/Bolvk0Q5OidlyRS1hLVWZoW6BZQS6FJah1AirtE
# DoVP/gBDqp2PfI9s0TCCBuwwggTUoAMCAQICEDAPb6zdZph0fKlGNqd4LbkwDQYJ
# KoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpOZXcgSmVyc2V5
# MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVTRVJUUlVTVCBO
# ZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRpZmljYXRpb24gQXV0
# aG9yaXR5MB4XDTE5MDUwMjAwMDAwMFoXDTM4MDExODIzNTk1OVowfTELMAkGA1UE
# BhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2Fs
# Zm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSUwIwYDVQQDExxTZWN0aWdv
# IFJTQSBUaW1lIFN0YW1waW5nIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAyBsBr9ksfoiZfQGYPyCQvZyAIVSTuc+gPlPvs1rAdtYaBKXOR4O168TM
# STTL80VlufmnZBYmCfvVMlJ5LsljwhObtoY/AQWSZm8hq9VxEHmH9EYqzcRaydvX
# XUlNclYP3MnjU5g6Kh78zlhJ07/zObu5pCNCrNAVw3+eolzXOPEWsnDTo8Tfs8Vy
# rC4Kd/wNlFK3/B+VcyQ9ASi8Dw1Ps5EBjm6dJ3VV0Rc7NCF7lwGUr3+Az9ERCleE
# yX9W4L1GnIK+lJ2/tCCwYH64TfUNP9vQ6oWMilZx0S2UTMiMPNMUopy9Jv/TUyDH
# YGmbWApU9AXn/TGs+ciFF8e4KRmkKS9G493bkV+fPzY+DjBnK0a3Na+WvtpMYMyo
# u58NFNQYxDCYdIIhz2JWtSFzEh79qsoIWId3pBXrGVX/0DlULSbuRRo6b83XhPDX
# 8CjFT2SDAtT74t7xvAIo9G3aJ4oG0paH3uhrDvBbfel2aZMgHEqXLHcZK5OVmJyX
# nuuOwXhWxkQl3wYSmgYtnwNe/YOiU2fKsfqNoWTJiJJZy6hGwMnypv99V9sSdvqK
# QSTUG/xypRSi1K1DHKRJi0E5FAMeKfobpSKupcNNgtCN2mu32/cYQFdz8HGj+0p9
# RTbB942C+rnJDVOAffq2OVgy728YUInXT50zvRq1naHelUF6p4MCAwEAAaOCAVow
# ggFWMB8GA1UdIwQYMBaAFFN5v1qqK0rPVIDh2JvAnfKyA2bLMB0GA1UdDgQWBBQa
# ofhhGSAPw0F3RSiO0TVfBhIEVTAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgw
# BgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDCDARBgNVHSAECjAIMAYGBFUdIAAw
# UAYDVR0fBEkwRzBFoEOgQYY/aHR0cDovL2NybC51c2VydHJ1c3QuY29tL1VTRVJU
# cnVzdFJTQUNlcnRpZmljYXRpb25BdXRob3JpdHkuY3JsMHYGCCsGAQUFBwEBBGow
# aDA/BggrBgEFBQcwAoYzaHR0cDovL2NydC51c2VydHJ1c3QuY29tL1VTRVJUcnVz
# dFJTQUFkZFRydXN0Q0EuY3J0MCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2Vy
# dHJ1c3QuY29tMA0GCSqGSIb3DQEBDAUAA4ICAQBtVIGlM10W4bVTgZF13wN6Mgst
# JYQRsrDbKn0qBfW8Oyf0WqC5SVmQKWxhy7VQ2+J9+Z8A70DDrdPi5Fb5WEHP8ULl
# EH3/sHQfj8ZcCfkzXuqgHCZYXPO0EQ/V1cPivNVYeL9IduFEZ22PsEMQD43k+Thi
# vxMBxYWjTMXMslMwlaTW9JZWCLjNXH8Blr5yUmo7Qjd8Fng5k5OUm7Hcsm1BbWfN
# yW+QPX9FcsEbI9bCVYRm5LPFZgb289ZLXq2jK0KKIZL+qG9aJXBigXNjXqC72NzX
# StM9r4MGOBIdJIct5PwC1j53BLwENrXnd8ucLo0jGLmjwkcd8F3WoXNXBWiap8k3
# ZR2+6rzYQoNDBaWLpgn/0aGUpk6qPQn1BWy30mRa2Coiwkud8TleTN5IPZs0lpoJ
# X47997FSkc4/ifYcobWpdR9xv1tDXWU9UIFuq/DQ0/yysx+2mZYm9Dx5i1xkzM3u
# J5rloMAMcofBbk1a0x7q8ETmMm8c6xdOlMN4ZSA7D0GqH+mhQZ3+sbigZSo04N6o
# +TzmwTC7wKBjLPxcFgCo0MR/6hGdHgbGpm0yXbQ4CStJB6r97DDa8acvz7f9+tCj
# hNknnvsBZne5VhDhIG7GrrH5trrINV0zdo7xfCAMKneutaIChrop7rRaALGMq+P5
# CslUXdS5anSevUiumDCCBvYwggTeoAMCAQICEQCQOX+a0ko6E/K9kV8IOKlDMA0G
# CSqGSIb3DQEBDAUAMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVyIE1h
# bmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28gTGlt
# aXRlZDElMCMGA1UEAxMcU2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBDQTAeFw0y
# MjA1MTEwMDAwMDBaFw0zMzA4MTAyMzU5NTlaMGoxCzAJBgNVBAYTAkdCMRMwEQYD
# VQQIEwpNYW5jaGVzdGVyMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNV
# BAMMI1NlY3RpZ28gUlNBIFRpbWUgU3RhbXBpbmcgU2lnbmVyICMzMIICIjANBgkq
# hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAkLJxP3nh1LmKF8zDl8KQlHLtWjpvAUN/
# c1oonyR8oDVABvqUrwqhg7YT5EsVBl5qiiA0cXu7Ja0/WwqkHy9sfS5hUdCMWTc+
# pl3xHl2AttgfYOPNEmqIH8b+GMuTQ1Z6x84D1gBkKFYisUsZ0vCWyUQfOV2csJbt
# WkmNfnLkQ2t/yaA/bEqt1QBPvQq4g8W9mCwHdgFwRd7D8EJp6v8mzANEHxYo4Wp0
# tpxF+rY6zpTRH72MZar9/MM86A2cOGbV/H0em1mMkVpCV1VQFg1LdHLuoCox/CYC
# NPlkG1n94zrU6LhBKXQBPw3gE3crETz7Pc3Q5+GXW1X3KgNt1c1i2s6cHvzqcH3m
# fUtozlopYdOgXCWzpSdoo1j99S1ryl9kx2soDNqseEHeku8Pxeyr3y1vGlRRbDOz
# jVlg59/oFyKjeUFiz/x785LaruA8Tw9azG7fH7wir7c4EJo0pwv//h1epPPuFjgr
# P6x2lEGdZB36gP0A4f74OtTDXrtpTXKZ5fEyLVH6Ya1N6iaObfypSJg+8kYNabG3
# bvQF20EFxhjAUOT4rf6sY2FHkbxGtUZTbMX04YYnk4Q5bHXgHQx6WYsuy/RkLEJH
# 9FRYhTflx2mn0iWLlr/GreC9sTf3H99Ce6rrHOnrPVrd+NKQ1UmaOh2DGld/HAHC
# zhx9zPuWFcUCAwEAAaOCAYIwggF+MB8GA1UdIwQYMBaAFBqh+GEZIA/DQXdFKI7R
# NV8GEgRVMB0GA1UdDgQWBBQlLmg8a5orJBSpH6LfJjrPFKbx4DAOBgNVHQ8BAf8E
# BAMCBsAwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDBKBgNV
# HSAEQzBBMDUGDCsGAQQBsjEBAgEDCDAlMCMGCCsGAQUFBwIBFhdodHRwczovL3Nl
# Y3RpZ28uY29tL0NQUzAIBgZngQwBBAIwRAYDVR0fBD0wOzA5oDegNYYzaHR0cDov
# L2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUlNBVGltZVN0YW1waW5nQ0EuY3JsMHQG
# CCsGAQUFBwEBBGgwZjA/BggrBgEFBQcwAoYzaHR0cDovL2NydC5zZWN0aWdvLmNv
# bS9TZWN0aWdvUlNBVGltZVN0YW1waW5nQ0EuY3J0MCMGCCsGAQUFBzABhhdodHRw
# Oi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEAc9rtaHLLwrlA
# oTG7tAOjLRR7JOe0WxV9qOn9rdGSDXw9NqBp2fOaMNqsadZ0VyQ/fg882fXDeSVs
# JuiNaJPO8XeJOX+oBAXaNMMU6p8IVKv/xH6WbCvTlOu0bOBFTSyy9zs7WrXB+9eJ
# dW2YcnL29wco89Oy0OsZvhUseO/NRaAA5PgEdrtXxZC+d1SQdJ4LT03EqhOPl68B
# NSvLmxF46fL5iQQ8TuOCEmLrtEQMdUHCDzS4iJ3IIvETatsYL254rcQFtOiECJMH
# +X2D/miYNOR35bHOjJRs2wNtKAVHfpsu8GT726QDMRB8Gvs8GYDRC3C5VV9Hvjlk
# zrfaI1Qy40ayMtjSKYbJFV2Ala8C+7TRLp04fDXgDxztG0dInCJqVYLZ8roIZQPl
# 8SnzSIoJAUymefKithqZlOuXKOG+fRuhfO1WgKb0IjOQ5IRT/Cr6wKeXqOq1jXrO
# 5OBLoTOrC3ag1WkWt45mv1/6H8Sof6ehSBSRDYL8vU2Z7cnmbDb+d0OZuGktfGEv
# 7aOwSf5bvmkkkf+T/FdpkkvZBT9thnLTotDAZNI6QsEaA/vQ7ZohuD+vprJRVNVM
# xcofEo1XxjntXP/snyZ2rWRmZ+iqMODSrbd9sWpBJ24DiqN04IoJgm6/4/a3vJ4L
# KRhogaGcP24WWUsUCQma5q6/YBXdhvUxggWCMIIFfgIBATCBkDB8MQswCQYDVQQG
# EwJVUzELMAkGA1UECBMCTUkxEjAQBgNVBAcTCUFubiBBcmJvcjESMBAGA1UEChMJ
# SW50ZXJuZXQyMREwDwYDVQQLEwhJbkNvbW1vbjElMCMGA1UEAxMcSW5Db21tb24g
# UlNBIENvZGUgU2lnbmluZyBDQQIQZvQSLmk9U6aXNceD/LajVTAJBgUrDgMCGgUA
# oHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYB
# BAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0B
# CQQxFgQUNKy4PgFt6c1HAAdu+PK7ku5l+E8wDQYJKoZIhvcNAQEBBQAEggEA1S5T
# pIpkQK+hiw7GXza0h/ns7Lv+uf7Ch/Gaxo4uo7mIJOucHfBQCpWyr1maDuh48qC3
# 0HHh/GGjKaGNUwfm55GviaMMVfk1Czkc9w+jIygNIq7qRLLuzxWAc9QOQfOQHORB
# w0mp6Mrda8jnW0QHxmnwJJ9sgxrxMiz5X0Ii9vBzG+IjO1/rM0PyxAaeuvqVcEqK
# qY9nblgo+7R45m43hc0Z1utdCZA4AJN1L5cBmTEqMISlKjQmouGQ0aNejQciPYhY
# pWGJBkHDo5FhZPr+yXJ7rEZOXu+Ugv1THIkBRz/npUrlEpj6v6q7TCS0NeYQWwxj
# siQD33BvDOKbL/66KqGCA0wwggNIBgkqhkiG9w0BCQYxggM5MIIDNQIBATCBkjB9
# MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYD
# VQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxJTAjBgNVBAMT
# HFNlY3RpZ28gUlNBIFRpbWUgU3RhbXBpbmcgQ0ECEQCQOX+a0ko6E/K9kV8IOKlD
# MA0GCWCGSAFlAwQCAgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkq
# hkiG9w0BCQUxDxcNMjIwNzA4MTgzMzI1WjA/BgkqhkiG9w0BCQQxMgQw+Y+plG+f
# GRxCRHO1iripzvk+x8R0XQtqU/skrIrW0BNgZcjaNHacCl7/Vs4MBJkUMA0GCSqG
# SIb3DQEBAQUABIICAIYtn2r+iSUZBlVgXGFy3tYYIa77DnbYVPHCACJcJyXCrEDl
# +ec1oM3p/omy92Na0a7K76ACXr+dEdqwM8rBU0eV8IhoSa7ZgAgCZ631oOMvvxWE
# MZBVdt4YugDuiT3C7YDTqpJxQmhaLYFHkaCXplpnj4vR1CT3qiOZTM6H4BQS6JTi
# 2gCbC1p1G0s68UNYDF8VmLEVua0Ejdk0/APr4tXorShzL6vGFx0/WDB6NgJYwh3m
# m/k7fMaIg4HKbOVwEgaJJSO0OSsTVLmBCmwKXL9i9QLQdpzqheZpGjzFOZUZeSto
# uN+Sd0SwcHezA1RPq+/iV+GYT579JJdQNpukWMFiB/oIL1z3/JxT1fIynctAPE+8
# 9aQRCLMjq5eH7aWmwQeJ0jtw4mRXhGWjKs9sBlLuMRzEING4gNxh1DRvFrBNAHbc
# 2PkWASc2w9xtK1uo7VexEMFkHmPgToWpW9nb1/wPMEv2PbonYV9zFWNxdvRGgPCA
# hChjzdivHebrtembDZWKYCRJnta5mOjey4bmi8lNWu6yCSKzUG/HUIlC0EZxf0kN
# jT6Im9L+sxgrWmuZv/4fahqPpu6C2S30BeAVjWJovBT9N3jdQtEYZoD4KNhwfSu2
# lhi9yBi77mS1xfu+LUXavvKL1QLy6n6yX+dn2dFSpmnYAbIJfAlWjCiSNGmX
# SIG # End signature block
