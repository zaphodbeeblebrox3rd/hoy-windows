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

# SIG # Begin signature block
# MIIlKgYJKoZIhvcNAQcCoIIlGzCCJRcCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUw5Nmm5ycZcTGpeWPJzXUVLvp
# mTCggh8SMIIFgTCCBGmgAwIBAgIQOXJEOvkit1HX02wQ3TE1lTANBgkqhkiG9w0B
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
# CslUXdS5anSevUiumDCCBwcwggTvoAMCAQICEQCMd6AAj/TRsMY9nzpIg41rMA0G
# CSqGSIb3DQEBDAUAMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVyIE1h
# bmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28gTGlt
# aXRlZDElMCMGA1UEAxMcU2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBDQTAeFw0y
# MDEwMjMwMDAwMDBaFw0zMjAxMjIyMzU5NTlaMIGEMQswCQYDVQQGEwJHQjEbMBkG
# A1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMMI1NlY3RpZ28gUlNBIFRpbWUg
# U3RhbXBpbmcgU2lnbmVyICMyMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAkYdLLIvB8R6gntMHxgHKUrC+eXldCWYGLS81fbvA+yfaQmpZGyVM6u9A1pp+
# MshqgX20XD5WEIE1OiI2jPv4ICmHrHTQG2K8P2SHAl/vxYDvBhzcXk6Th7ia3kwH
# ToXMcMUNe+zD2eOX6csZ21ZFbO5LIGzJPmz98JvxKPiRmar8WsGagiA6t+/n1rgl
# ScI5G4eBOcvDtzrNn1AEHxqZpIACTR0FqFXTbVKAg+ZuSKVfwYlYYIrv8azNh2MY
# jnTLhIdBaWOBvPYfqnzXwUHOrat2iyCA1C2VB43H9QsXHprl1plpUcdOpp0pb+d5
# kw0yY1OuzMYpiiDBYMbyAizE+cgi3/kngqGDUcK8yYIaIYSyl7zUr0QcloIilSqF
# VK7x/T5JdHT8jq4/pXL0w1oBqlCli3aVG2br79rflC7ZGutMJ31MBff4I13EV8gm
# BXr8gSNfVAk4KmLVqsrf7c9Tqx/2RJzVmVnFVmRb945SD2b8mD9EBhNkbunhFWBQ
# pbHsz7joyQu+xYT33Qqd2rwpbD1W7b94Z7ZbyF4UHLmvhC13ovc5lTdvTn8cxjwE
# 1jHFfu896FF+ca0kdBss3Pl8qu/CdkloYtWL9QPfvn2ODzZ1RluTdsSD7oK+LK43
# EvG8VsPkrUPDt2aWXpQy+qD2q4lQ+s6g8wiBGtFEp8z3uDECAwEAAaOCAXgwggF0
# MB8GA1UdIwQYMBaAFBqh+GEZIA/DQXdFKI7RNV8GEgRVMB0GA1UdDgQWBBRpdTd7
# u501Qk6/V9Oa258B0a7e0DAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDBABgNVHSAEOTA3MDUGDCsGAQQBsjEBAgED
# CDAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzBEBgNVHR8E
# PTA7MDmgN6A1hjNodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29SU0FUaW1l
# U3RhbXBpbmdDQS5jcmwwdAYIKwYBBQUHAQEEaDBmMD8GCCsGAQUFBzAChjNodHRw
# Oi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29SU0FUaW1lU3RhbXBpbmdDQS5jcnQw
# IwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEB
# DAUAA4ICAQBKA3iQQjPsexqDCTYzmFW7nUAGMGtFavGUDhlQ/1slXjvhOcRbuumV
# kDc3vd/7ZOzlgreVzFdVcEtO9KiH3SKFple7uCEn1KAqMZSKByGeir2nGvUCFctE
# UJmM7D66A3emggKQwi6Tqb4hNHVjueAtD88BN8uNovq4WpquoXqeE5MZVY8JkC7f
# 6ogXFutp1uElvUUIl4DXVCAoT8p7s7Ol0gCwYDRlxOPFw6XkuoWqemnbdaQ+eWia
# NotDrjbUYXI8DoViDaBecNtkLwHHwaHHJJSjsjxusl6i0Pqo0bglHBbmwNV/aBrE
# ZSk1Ki2IvOqudNaC58CIuOFPePBcysBAXMKf1TIcLNo8rDb3BlKao0AwF7ApFpnJ
# qreISffoCyUztT9tr59fClbfErHD7s6Rd+ggE+lcJMfqRAtK5hOEHE3rDbW4hqAw
# p4uhn7QszMAWI8mR5UIDS4DO5E3mKgE+wF6FoCShF0DV29vnmBCk8eoZG4BU+keJ
# 6JiBqXXADt/QaJR5oaCejra3QmbL2dlrL03Y3j4yHiDk7JxNQo2dxzOZgjdE1CYp
# JkCOeC+57vov8fGP/lC4eN0Ult4cDnCwKoVqsWxo6SrkECtuIf3TfJ035CoG1sPx
# 12jjTwd5gQgT/rJkXumxPObQeCOyCSziJmK/O6mXUczHRDKBsq/P3zGCBYIwggV+
# AgEBMIGQMHwxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJNSTESMBAGA1UEBxMJQW5u
# IEFyYm9yMRIwEAYDVQQKEwlJbnRlcm5ldDIxETAPBgNVBAsTCEluQ29tbW9uMSUw
# IwYDVQQDExxJbkNvbW1vbiBSU0EgQ29kZSBTaWduaW5nIENBAhBm9BIuaT1Tppc1
# x4P8tqNVMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkG
# CSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
# AYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRSquXifNyxfHqyqh8FTbsA/3JyYDANBgkq
# hkiG9w0BAQEFAASCAQCh24sA1vTuHWy+dsCnvz16GsVym1kPHrfz9njyTDpjvpXD
# HxgJEWDL0h4PYtSZpLokH3Tz06ayytmMC/XOkEwUb5ZL77AH9DopMGXAqs9fapVZ
# xFE3fwrWUGrn0dcsWU90WGsagR/6QbAJIpl8bGgGItQT5Snntsdrh2BVFbEJ9xvj
# vwTwvvRFX+VrH5kbnXvU1vPRhKPQZP1Fx9hx7Zkbt1/j0OJsE4qxSayjGUPpRA+y
# OJ9HQOaXx9jmPj4fvxArUBID/v6k3+F5AP5XS17kqeG6qrRlN7Dvgoz/O49OUW2W
# dq4qQq2XX0PU7r4sy4224oXf7jQ/XnjIOVW1NdYOoYIDTDCCA0gGCSqGSIb3DQEJ
# BjGCAzkwggM1AgEBMIGSMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVy
# IE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28g
# TGltaXRlZDElMCMGA1UEAxMcU2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBDQQIR
# AIx3oACP9NGwxj2fOkiDjWswDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMjA0MjAxODM4MTBaMD8GCSqG
# SIb3DQEJBDEyBDACWxpVIH8jPcVMPwUOqjvOw61xAn8fhHhOsyus7LeQq0qMHz4Q
# h7CO6GOEU85YMU8wDQYJKoZIhvcNAQEBBQAEggIAY+dTwLJ9KptH0cRq91mm+sua
# EZE8kJsBmMu9pX4CxMj7OI3X4vfhvNyKkV3aIdUn3erxQEmugj2fcIWd3i8z2OGx
# Brgqzfg+ztw1tFpqhydiAXi097RiTe1dGANtIJXcIPN+ve+6r/Yi14bR2SQUhV3V
# BYxrzeOLnSQ0H+cJ0iooQIid7oiyd988Wk5846NdEVHBiMPgHpSrEn2cIK4sENpV
# oIABS5ocSd1kLisMwkhAFbGwgAtmN5ZyLnphnQQd/5r+j/rPQIuVCaNCkyJQAESh
# GY1i/eYQHqqe1iXEVwKIwPQ9pIV7UVE+bWfKcDgZ3GX7Z/vYiTYb37cXqKQNBXYM
# AK2IaDe1Du1D542AabfGW8q1wCDWU3H5V1XNJCl6IVBYc47fU+XQjbabKbh6zMVb
# hwblkXtEXSLOTzp5GftH8rtIKEpnbO96YR3xQyTQ3hGcWQ7BAc52AC5oXymCZneF
# kLs2JOsSikT+ppOZEu+bmjv9fPtyIfd1YMLUvw6aN7AHqfNdLra6IX4MEHe5HJyn
# vqsL8lKed+AQaazNFubzE8Yr48wLaiy3Akvtq1gnYmuxkgVMw+O6GH6XQrKU5+Df
# Ik7iQ/X+MMwQ5zi4F2hs88+d0FstquxFUVwdDOkZtaBgyBDHDmA7f15/3vkeOcXd
# cY/xA54tjd/UOsRD5Xg=
# SIG # End signature block
