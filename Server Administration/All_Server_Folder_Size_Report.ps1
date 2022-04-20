#Provide graphical representation of folder size on all Windows servers (no application install needed)
#Requirements: 
#  AD environment
#  Windows Server 2016+ to run script - it needs remote powershell access to all targets
#  Time and patience - this may take an hour or longer to run depending on disk speed
#Author: Eric Hoy
#Date: 2022-04-13


###############################################################################

#These are the only variables you should edit

#This MUST be edited to reflect the OU you want to include in your search.
$ldap_search_base='OU=Servers,OU=Department,OU=Division,DC=ad,DC=yourdomain,DC=edu'

#These can typically be left alone
$target_folder='C:\Users'
$depth=0
$simultaneous_connections='16'

#############################################################

#Do not edit below

$now=Get-Date -Format "yyyyMMddHHmm"

#Enumerate the list of Windows Servers
$all_sscs_server_ad_objects=$(Get-ADComputer -Filter 'operatingsystem -like "*Windows Server*" -and enabled -eq "true"' -SearchBase $ldap_search_base -Properties Name, Operatingsystem, IPv4Address | Select-Object -Property Name, Operatingsystem, IPv4Address)

$server_selection=($all_sscs_server_ad_objects | Out-GridView -Title "Select Servers to Clean Up" -PassThru) #graphical list to choose from
$servers=@();
foreach ($s in $server_selection) {
    if (Test-Connection -Protocol WSMan -ComputerName $s.Name) { #only include servers that are reachable on the network
    #if (Test-Connection -ComputerName $s.Name) { #only include servers that are reachable on the network
        $servers+=$s
        }
    else {
        Write-Host "$s is not detected"
        Write-Host "Skipping $s"
        }
    }

$server_names=$($servers | Select-Object -ExpandProperty Name)

#clear out old PSSessions and establish new ones
Get-PSSession | Remove-PSSession
$sessions=(New-PSSession -ComputerName $server_names -ErrorAction SilentlyContinue)

#Reach out to all machines in parallel, creating a custom PSObject on each machine
#The custom PSObjects will be fed into an array on the machine, and then fed into an array of arrays
$data_aggregate=@()
$data_aggregate+=Invoke-Command -Session (Get-PSSession) -ThrottleLimit $simultaneous_connections -ScriptBlock{
    param($depth,$target_folder)
    Write-Host "Depth equals $depth"
    $computer_name=$env:computername
    $data_coll=@()
    gci -force -depth $depth $target_folder -ErrorAction SilentlyContinue | Where-Object -Property LinkType -NotContains * | ? { $_ -is [io.directoryinfo] } | % {
        $len = 0
        $len=(gci -recurse -force $_.FullName -ErrorAction SilentlyContinue | Measure-Object -Property Length -sum)
        $len_sum=$len.Sum
        $folder_name = $_.fullname
        $folder_size_string= '{0:N2}' -f ($len_sum / 1Gb)
        $folder_size=[Decimal]$folder_size_string
        $data_object = New-Object PSObject
        Add-Member -inputObject $data_object -memberType NoteProperty -name “foldername” -value $folder_name -Force
        Add-Member -inputObject $data_object -memberType NoteProperty -name “foldersizeGB” -value $folder_size -Force
        Add-Member -inputObject $data_object -memberType NoteProperty -name “computername” -value $computer_name -Force
        $data_coll+=$data_object
        }
    return $data_coll
    } -ArgumentList ($depth,$target_folder)


$data_aggregate | Out-GridView -Title “Size of subdirectories”



# SIG # Begin signature block
# MIIlKgYJKoZIhvcNAQcCoIIlGzCCJRcCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUVE1VEGQynalonZU8eqLWA6Nm
# 5feggh8SMIIFgTCCBGmgAwIBAgIQOXJEOvkit1HX02wQ3TE1lTANBgkqhkiG9w0B
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
# AYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQOyn97N6vm2lP4FQHKp+AKW3LMxTANBgkq
# hkiG9w0BAQEFAASCAQAmQLlQ8x1PXr4ghTtl6kG4wQkda/x5cGBVogeHPBNH8x3S
# cWWyoiCmkiIFrXeR1qcxvEXQ1ve4uWLe2UtQbvoLlOg26LVY6YXG3sSM5KUgsXBw
# Fp9AhG9DXAyjA9hdEWdGPFqsJaJFxMY8IBnDj+HTxEQQG9vdAOjgohC20mpOa1PN
# y6UQv1Aa+9FP2CFKrGlXZb5+g86R1N9PX9oG8g0d+13PrZQi+pAcgbX9fT/J0H1U
# htbJyJQjmgUKx4lVLc1Swsu+LrdQ0BboJEPW0zZ5ivXODtfe1glci4OU4IDfnV9M
# Qq82A+DuRcq+oi3Gfcb2gxXdK7PetvwyYzpvpNeXoYIDTDCCA0gGCSqGSIb3DQEJ
# BjGCAzkwggM1AgEBMIGSMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVy
# IE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28g
# TGltaXRlZDElMCMGA1UEAxMcU2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBDQQIR
# AIx3oACP9NGwxj2fOkiDjWswDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMjA0MjAxNTA0MThaMD8GCSqG
# SIb3DQEJBDEyBDDsolhlcdOrYsZRCq99rfe/SvTljEDacKT8vXC/BDfSIFlKJ7c6
# P5C0LLZq2n+FpR8wDQYJKoZIhvcNAQEBBQAEggIALUTfpSFrSJuSY+pDy51q2tu7
# 3ts3EsgL6VN0bpzGr5WXCeHog7Ild3fUy3TAk1zcOZZGmQqQgo/Pry6XaoSLS4Z+
# SsAk83eemYnx4VdjTJuG8rx7r4aUeeQSHMaDTfWs8/FTYcKHYBwSpy7UahdhErBO
# nZ2ahzBtri8VIjQHlQbFt3VHelHZ4RBYmr9D4zOaDEtgEpAPbja4YFxD4AYSLpyG
# zuqGGZ+kzIO9yRWJKO+Vep0KeCja4Hj7skF3uFcoYCLZCWwhV1wge2XuZ5rh68qh
# degLianRdyL4D97n0CRB9xOQ2K9vBNeiuERRie2iVzLcruUS9wpK3sbapRo+U6Ly
# atGdkfxP6CWPPGOUA9Pfluq1L2tmWJNZ41c+A9BhkS/sdeA1GIeolg1N4GqUMbiO
# G8gYj24dF2YxT5ePGzDWXwp+zRGATqcPu9BuqPjxOVyhAVBN8tvFFkteLuBDqZz6
# GdaUpVbW6Woew/GYenK4jhNFtayEwNdRJ9GRtUA5Kllp4aETbdS+v9lNyG66VSdI
# r3dsBXpKzbWx33Bvz+9Gmt0v/eyE4A4csx4pbKqg5oHTbS/CScA9FWitMC2yGQfh
# apqKUUQ2EXm8TTDfmFt/r6qO50GpoA41dXurXEBoZZgJuqDM8/ZjI7Sxwv741OK1
# AUSH2SteTtrgWttR5iU=
# SIG # End signature block
