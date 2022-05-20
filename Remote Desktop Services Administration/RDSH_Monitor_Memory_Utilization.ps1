#Connect to all Windows RDS Servers and Monitor Memory Utilization
#Enforce a user-based memory quota
#Author: Eric Hoy, University of Chicago, SSCS
#Date: 2022-02-23
#Modified: 2022-05-12


#Variables that are ok to change (in some environments the script will need to be re-signed after a change)
$variables_file = "\\harbor.uchicago.edu\sscs-server\Scripts\variables\sscs.xml"
$line_separator='****************************************************************************'


#$rd_connection_broker='' #FQDN is required
#$rds_environment_name=''

#$computer_domain=''
#$user_domain=''
#$administrator_email_address=''
#$help_desk_email=''
#$support_team_name=''
#$help_resources=''
#$smtp_relay=''


##############################################################################################
#Content in this section can be edited if you choose not to have a separate xml file for vars

#Read in variables from the xml file
[xml]$sscs = Get-Content $variables_file

$rds_environment_name = $sscs.sscs.rds_environment.name

$target_servers = $sscs.sscs.rdsh_mem_quota.host

$rd_connection_broker = $sscs.sscs.rds_environment.rdcb.fqdn

$computer_domain = $sscs.sscs.rds_environment.computer_domain

$user_domain = $sscs.sscs.rds_environment.user_domain

$administrator_email_address = $sscs.sscs.rds_environment.admin_email

$help_desk_email = $sscs.sscs.rds_environment.helpdesk_email

$support_team_name = $sscs.sscs.rds_environment.support_team_name

$help_resources = $sscs.sscs.rds_environment.help_resources

$smtp_relay = $sscs.sscs.rds_environment.smtp_relay




##############################################################################################
#Content below should not need any modification



#Get a list of active users in the RDS environment
$rds_active_users=$(Get-RDUserSession -ConnectionBroker $rd_connection_broker | Select-Object -ExpandProperty Username)
Write-Host "RDS Active Users: $rds_active_users"

#Clear out old and create new Remote PowerShell Sessions
Get-PSSession | Remove-PSSession
$sessions=New-PSSession -ComputerName $target_servers.name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue

#The search will run in parallel across all RDS servers.
Invoke-Command -Session (Get-PSSession) {
    param ($target_servers,$rds_active_users,$administrator_email_address,$smtp_relay,$line_separator,$help_desk_email,$help_resources,$computer_domain,$user_domain,$support_team_name,$rds_environment_name)
    $today = (Get-Date)
    $computer_name=$env:COMPUTERNAME
    [decimal]$alert_quota_gb= $target_servers | Where-Object -Property name -Like $computer_name | Select-Object -ExpandProperty alert_quota  #Exceeding this quota in GB will generate an email alert
    [decimal]$mem_quota_gb= $target_servers | Where-Object -Property name -Like $computer_name | Select-Object -ExpandProperty mem_quota #Exceeding this quota in GB will result in termination of the RDS User Session
    [int64]$alert_quota=($alert_quota_gb * 1024 * 1024 * 1024) #precise comparison with the output of get-process
    [int64]$mem_quota=($mem_quota_gb * 1024 * 1024 * 1024) 

    
    #Loop through user sessions and sum up mem usage of each users' processes
        foreach ($user_session in $rds_active_users) {
        $user_email_address=($user_session+'@'+$computer_domain)
        $email_from_name=($computer_name+'@'+$computer_domain)
        $mem_process=$(Get-Process -IncludeUserName | Select-Object -Property PM, UserName | Where-Object -Property UserName -Like "$user_domain\$user_session" | Select-Object -ExpandProperty PM)
        $total_user_mem_usage=1 #Start with 1 byte to avoid math issues later on
        foreach ($process_item in $mem_process) { 
            $total_user_mem_usage+=$process_item
            } #adds up the physical memory usage of all processes belonging to the user
        $total_user_mem_usage_gb=[math]::Round($total_user_mem_usage / 1024 / 1024 / 1024,2) #Human-readable value for the body of the email alert.

        #Generate an email alert if needed
        if ( ($total_user_mem_usage -gt $alert_quota) -and ($total_user_mem_usage -lt $mem_quota) ) { 
            Write-Host "$user_session has exceeded the alert quota and an email will be sent to $user_email_address and $administrator_email_address"
            $message_subject="Username: $user_session - Memory usage approaching quota in the $rds_environment_name Remote Desktop Services environment"
            $message_body="$line_separator `n`n
Memory usage by $user_session in $rds_environment_name is: $total_user_mem_usage_gb GB, which exceeds the $alert_quota_gb GB threshold for an email alert. `n
When the memory usage reaches $mem_quota_gb GB, all processes for $user_session will exit and the session will be logged off.`n
Save all work.  Close out any processes using excessive memory to prevent automatic logoff of $user_session from $computer_name.  `n`n
$line_separator `n`n
The $support_team_name team wants you to be able to work successfully!`n`n
Please use these resources if you have more questions about running large-memory processes: `n
  - Check our FAQ pages: $help_resources `n
  - Email us for additional support: $help_desk_email"

            Send-MailMessage -From $email_from_name -To $administrator_email_address -Subject $message_subject -Body "$message_body" -Priority Normal -SmtpServer $smtp_relay
            Send-MailMessage -From $email_from_name -To $user_email_address -Subject $message_subject -Body "$message_body" -Priority High -SmtpServer $smtp_relay
            }

        #End the user's RDS session if needed.  
        if ($total_user_mem_usage -gt $mem_quota) { 
            Write-Host "$user_session has exceeded the memory quota and the session will be terminated"
            $message_subject="Username: $user_session - Memory usage exceeded quota in $rds_environment_name Remote Desktop Services environment"
            $message_body="$line_separator `n`n
Memory usage by $user_session in $rds_environment_name has reached: $total_user_mem_usage_gb GB, which exceeds the $mem_quota_gb GB limit. `n
In order to prevent issues that will affect other users, all processes for $user_session will end and the session will be logged off.`n`n
$line_separator `n`n"

            Send-MailMessage -From $email_from_name -To $administrator_email_address -Subject $message_subject -Body "$message_body" -Priority Normal -SmtpServer $smtp_relay
            Send-MailMessage -From $email_from_name -To $user_email_address -Subject $message_subject -Body "$message_body" -Priority High -SmtpServer $smtp_relay

            #identify the session number on the target server (different from the UnifiedSessionId reported by Get-RDUserSession)
            $problem_session_text= quser $user_session 2>$null

            #create a PSCustomObject to deal with the string output of the native quser Windows command
            ForEach ($line in $problem_session_text){
                If ($line -notmatch "LOGON TIME") {
                    $problem_session = [PSCustomObject]@{
                        Username        = $line.SubString(1, 20).Trim()
                        ID             = $line.SubString(42, 2).Trim()
                        }
                    }
                }
            
            Write-Host ("The problem session ID is: "+$problem_session.ID)
            logoff $problem_session.ID #End the user's session
        }
    }
} -ArgumentList ($target_servers,$rds_active_users,$administrator_email_address,$smtp_relay,$line_separator,$help_desk_email,$help_resources,$computer_domain,$user_domain,$support_team_name,$rds_environment_name)
# SIG # Begin signature block
# MIIlKgYJKoZIhvcNAQcCoIIlGzCCJRcCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUA4NF57I0606tUNYbEvkFEWWD
# eTuggh8SMIIFgTCCBGmgAwIBAgIQOXJEOvkit1HX02wQ3TE1lTANBgkqhkiG9w0B
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
# AYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQszUP2f3lwjwCCok+V5Oo9M0F/aDANBgkq
# hkiG9w0BAQEFAASCAQAeAGHFCE8dg2ssya8gpruzfIofVmdQVwALKszvId4QAafM
# sOqhAh3f0W1dOPyE43CQh6PioO3gNqCqTM0Otx8ClABNQNpdxSof2v9n+ZwqSEEE
# mWHUiG3bjfpTHkvAerSfr36Knqn9cy/C6FGdqTeZsfvBDWsLaTioZiIVMyvgjP6Q
# 5IHC6mqd1hPeEskzjuI+sYyD8cp3r14B8gYr8dpj3Bb7p+JkeVsxtSjY/8q5m1T2
# 11dsUg/wdE2Og4kBJABxKQdHbZIEullB38vAmNoj+ZWx7DnRYFK6Mc3HH8c0L7ck
# 9E3uaL7Q1K9f6Pgu4512flyeihGWU0AhRDzjM4VcoYIDTDCCA0gGCSqGSIb3DQEJ
# BjGCAzkwggM1AgEBMIGSMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVy
# IE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28g
# TGltaXRlZDElMCMGA1UEAxMcU2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBDQQIR
# AIx3oACP9NGwxj2fOkiDjWswDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMjA1MTMyMTIzNTFaMD8GCSqG
# SIb3DQEJBDEyBDAuUGtz8MwQe4NpWYUh7VU2KqkkLIbh9lyjNyYUS2iUrL1Q+pBX
# ad9ouxrYscx3DsQwDQYJKoZIhvcNAQEBBQAEggIAc4D1a6yOIhCtAski8LcYv7kY
# AMQaEADdaXmcoVsANE0s6Vpa57bhr2fPx26zqL4yQ9Nmlcj0BuhIl3VFlOPreatq
# LUsfCcZ6OwOFSt2AssfADSGkWYy++4TNQP7csq2K3KkOVAaCFLLBgHguHUHxZj22
# /V6GH4cIpqVvAM1KujFLyUnd15pif6eXebont3BfT8ABSK0v0KdF6ha2eJeRraX/
# xm630rxiPe17Up3hR+W98Qr3ww0p5qufmFIl72xkul+yBE57tR7Xj5MvKWJ8Q21j
# eBClTa9dWwtFXMeWhN5MZWV6U7clf9NmTDwv0h+Qmlt78fjm4FBAkoEybKsbNU+8
# ybdGbsSrwqXR5kHrapj2xei7qj5pxNWebluY8RTeepYky1MDkxpPEuV/hPZnuIua
# AsTNQo66g737tDsXOjnEU8Cno6vf6aSRwKGavRARf2xAP7X3mPJlpurqZkmVV3DB
# h4dL9pofQInE4vM/eyxtYqkz7gCeFwnnPYUxf4MBb2jKXkKpIenUE9xBe/iz8mdT
# 3e+kAPX5PYoACNrx1Uw7uOKtQFqfShYiFDg/rwv6ZL6dmMP81T0Id1Kxk/S7besf
# KdAnAGPGge+mkmP3F8BGUbiEE58cUHDhRp8LX2kE8GobNZWV6smZJyURVKlWvtuR
# 3bC5PT15vJDCf+9VDX4=
# SIG # End signature block
