#Connect to all Windows RDS Servers and Monitor Memory Utilization
#Enforce a user-based memory quota
#Author: Eric Hoy, University of Chicago, SSCS
#Date: 2022-02-23
#Modified: 2022-05-12


#Variables that are ok to change (in some environments the script will need to be re-signed after a change)
$variables_file = "\\server.domain.comu\myteam\Scripts\variables\sscs.xml"
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
