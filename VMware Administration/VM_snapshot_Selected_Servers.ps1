# Connect to a single vCenter Server
# Clear out old VM snapshots for multiple VMs and create fresh snapshots based on pattern match of server hostname
# Author: Eric Hoy
# Date: 2020-10-08
# Date Modified: 2022-07-07


# These variables can be edited
#####################################

# Make sure to set this one unless you are using an alternative method below
$variables_file = "\\server.domain.comu\myteam\Scripts\variables\sample.xml"

# comment out this line if you decide to use one of the alternatives instead of an external data file
$target_computers = $null

### XML Alternative 1. Insert server names into the following variable
# $target_computers='RDSH-0','RDSH-1','RDSH-2','RDSH-3','RDSH-4','RDSH-5','RDSH-6','RDSH-7','RDSH-8','RDSL-0','RDGW-0','RDCB-0','FM','EM2019'

### XML Alternative 2.  Pull the server list from LDAP or Active Directory and select the ones to include graphically
# $ldap_search_base='OU=Servers,OU=Computers,OU=Division,DC=ad,DC=domain,DC=edu'
### Enumerate the list of Windows Servers
# $all_sscs_server_ad_objects=$(Get-ADComputer -Filter 'operatingsystem -like "*Windows Server*" -and enabled -eq "true"' -SearchBase $ldap_search_base -Properties Name, Operatingsystem, IPv4Address | Select-Object -Property Name, Operatingsystem, IPv4Address)
# $server_selection=($all_sscs_server_ad_objects | Out-GridView -Title "Select Servers to Clean Up" -PassThru) #graphical list to choose from
# $target_computers=@();
# foreach ($s in $server_selection) {
#    if (Test-Connection -Protocol WSMan -ComputerName $s.Name) {
#            $target_computers+=$s
#        }
#    else {
#        Write-Host "$s is not detected"
#        Write-Host "Skipping $s"
#        }
#    }

# local directory for report outputs, and other variables
# These will be pulled from the external xml file if you're using one.  
# If not, remove the commenting from these vars
# $LogPath='C:\logs'
# $log_entries_per_vm=50
# $default_snapshot_description='Fresh Snapshots for Domain Connectivity'
# $report_header=$default_snapshot_description
# $vcenter='1.2.3.4'

# These are fine to leave at the default values
###########################################################

$line_separator="**************************************************************************************"

###########################################################

#Don't edit below
####################################

$now=Get-Date -Format "yyyyMMddHHmm"

#Import-Module VMWare.vimautomation.core

#import vars from xml file if it exists
if (Test-Path -Path $variables_file) {
   [xml]$sscs = Get-Content $variables_file
   $all_computers = $sscs.sscs.virtual_servers.name
   $log_path = $sscs.sscs.virtual_servers.log_path
   $log_entries_per_vm = $sscs.sscs.virtual_servers.log_entries_per_vm
   $vcenter = $sscs.sscs.vcenter.primary_name
   $default_snapshot_description = 'Fresh Snapshots for Domain Connectivity'
   $vcenter_username = $sscs.sscs.vcenter.username
   }


if (($snapshot_description = Read-Host "Press enter to accept default snapshot description: $default_snapshot_description") -eq '') {$default_snapshot_description} else {$snapshot_description}

#Override any certificate issues
Set-PowerCLIConfiguration -InvalidCertificateAction Warn -Confirm:$false

#Get connected to vCenter Server
$credential = Get-Credential $vcenter_username
Connect-VIServer -Server $vcenter -Credential $credential


#Get VMs, but only the ones selected by the user
$server_selection=($all_computers | Out-GridView -PassThru)
$virtual_machines=@();
foreach ($s in $server_selection) {
    Write-Host $s
    if ($s -ne $null) {
        $vm = Get-VM | Where {$_.Name -like $s}
        $virtual_machines+=$vm
        }
    else {
        Write-Host "$s is not detected in this VM space"
        Write-Host "Skipping $s"
        }
    }

$snapshots = $virtual_machines | Get-Snapshot
 
$date = Get-Date

#Generate the data for the PreCleanupSnapshotReport
$precleanupreport = $snapshots `
| Select-Object VM, Name, Uid, Created, @{Name="Age"; Expression = {New-TimeSpan -Start $_.Created -End $date}}, Description `
| Sort-Object -Property "VM"

#Write the data into a readable HTML file 
$pre_cleanup_snapshot_report_html = $precleanupreport | ConvertTo-Html -Head $report_header -PreContent "Pre-Cleanup Report Date: $date" 
Remove-Item $log_path\PreCleanupSnapshot.html
New-item $log_path\PreCleanupSnapshot.html
Set-Content $log_path\PreCleanupSnapshot.html $pre_cleanup_snapshot_report_html

$old_snapshot_cleanup=$(Read-Host "Do you want to clean up previous snapshots on these VMs? y or n")
If ($old_snapshot_cleanup -Like "y") {
    Remove-Snapshot $snapshots
    }

sleep -Seconds 10

$virtual_machines | ForEach-Object {New-Snapshot -Name $snapshot_description -Description $snapshot_description -VM $_.Name}

$new_snapshots = $virtual_machines | Get-Snapshot

#Generate data for PostCleanupSnapshotReport
$postcleanupreport = $new_snapshots `
| Select-Object VM, Name, Uid, Created, @{Name="Age"; Expression = {New-TimeSpan -Start $_.Created -End $date}}, Description `
| Sort-Object -Property "VM"

#Write data into a readable HTML file
$post_cleanup_snapshot_report_html = $postcleanupreport | ConvertTo-Html -Head $snapshot_description -PreContent "Post-Cleanup Report Date: $date" 
Remove-Item $log_path\PostCleanupSnapshot.html
New-item $log_path\PostCleanupSnapshot.html
Set-Content $log_path\PostCleanupSnapshot.html $post_cleanup_snapshot_report_html



# SIG # Begin signature block
# MIIlGQYJKoZIhvcNAQcCoIIlCjCCJQYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZF20fIpyXdyC1oWnXnq+BvgL
# h3Kggh8BMIIFgTCCBGmgAwIBAgIQOXJEOvkit1HX02wQ3TE1lTANBgkqhkiG9w0B
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
# CQQxFgQU5JpXpvK+YKz55KiB6BImm1l5sWcwDQYJKoZIhvcNAQEBBQAEggEAw0qR
# +AP0y14uJ6FbcLZlA88IfjHJ9CaJ8ldlpNeGo3zX0CwTXqyxUPrwlhfGtkSHtDEJ
# x7xJOFL4jwkiqTDzsiirO+eewP5FqTt2RWou+m4VNettw/bq3IyGdObd5LL/sUe2
# oO0v07SFqTw3CGlhS9v4fAm2oFo6xCBpS6U6Yq30woA7DxHOI+XZWd17deYIyO3+
# VkF94JYxctgeQTI0NJprqX1mNuqNSOg2PtrrzpeID4jTomfdzuH6fOICH9jNibOo
# Mdi4RfduGmx7HpcKqHG2hO0rGbylEPwh61Tf5sdw3dAmxvT6OhdvzlFYdyRhgBOd
# LN9WXSHYWYljpdSxt6GCA0wwggNIBgkqhkiG9w0BCQYxggM5MIIDNQIBATCBkjB9
# MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYD
# VQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxJTAjBgNVBAMT
# HFNlY3RpZ28gUlNBIFRpbWUgU3RhbXBpbmcgQ0ECEQCQOX+a0ko6E/K9kV8IOKlD
# MA0GCWCGSAFlAwQCAgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkq
# hkiG9w0BCQUxDxcNMjIwNzA4MTgzNDI0WjA/BgkqhkiG9w0BCQQxMgQwilYxT+Ub
# 8fS5f45dPQouE0Qt1zU21OwZPA1RBSeISsr04HjLIme3e8rbzoyS1+B5MA0GCSqG
# SIb3DQEBAQUABIICAEJ8TXp65oIokFkda6GB9Di6/JKt4fkn677vyv6J6GwoEDJB
# D+UhXH2Pr1vb2rNA2Lx/LHvEjqTtc+4/PY9xC7Sb6/rZRSa5lys/esbRxzRILCgr
# JFQlh9KXe2l8BVZ+WeLLHZpunHtCJCh+tDItlfxHiWVNYud9iwmZHPE9OQ2RWOaj
# fAeH6DV+ssbjL3VsYrV6JubPjkSTvdQlmzRbEGdpTec9z7An9SltxhN4R0ktRiBb
# O4ei7XePy8h6vK+TP2NwrShsDax4aIJBbRqeE2A0tY7+R68LqFqkC/7eZhqa1hfe
# CUXxte4kZHH0kyr4tYg8eFgscvvKxILWGvIrWF5tI6takwMhK8fg4eKnq7YgvXDH
# PK7hAxZvftfa6L3VgjDedo7HbBpCiM725UabkUrCLXnvzd5qKnMOPdEvdKBdtt+V
# GYlEfC5hOtm1DFampKiV+MLyMfXDOXeDggnh0INxVYub+ZCf9lFVP2hTX12gFr0w
# ZDKscUab2VXH7AQ1wCYVwqLVl0SRnpNtAeXVawWi+6fWPIpk/BXYYP5elMuKTuPp
# JWGr1O/Nrl+BDkBUYz88pftKZHl5pjf1oL/YNDBQ+vsE90fM6wlTk3xPOYrYRE9q
# DIE6Mj0HJ1xrgSn8qDOubeUNdWgOx+VF9Z6Vxp1mpZjlSkaiUch+bJNwTLpS
# SIG # End signature block
