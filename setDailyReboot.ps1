#Minimum Powershell Version: 7
#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
#winrm quickconfig

#Params
# -computername (for remote PC's, omit this parameter for local PCs)
# -username (supply the username to run the task as, default is Administrator)
# -showPassword (password will be visibly shown on screen if switch is supplied, default is to hide the password)
# -deleteTask (supply this parameter to prompt for deleting an existing task)

#.\setDailyReboots.ps1 -computername "U151AY38cD7DgKd" -showPassword
#.\setDailyReboots.ps1 -computername "U151AY38cD7DgKd" -showPassword -deleteTask

#v0.1 - Draft (Corey Jackson)
#v0.2 - added ability to delete task (CJ)

param(
    [ValidateNotNullOrEmpty()]
    [string]$computername,
    [string]$username = "Admin",
    [switch]$showPassword = $false,
    [switch]$deleteTask = $false
)

$scriptver = "0.2"
Write-Host("setDailyReboots v:$scriptver")

if ([string]::IsNullOrEmpty($computername)) {
    $computername = [Environment]::MachineName
}
Write-Host("Computer name: " + $computername)

if ([string]::IsNullOrEmpty($username)) {
    $username = "Admin"
}
Write-Host("Username: " + $username)

try
{
    if ($computername -ne [Environment]::MachineName)
    {
        $remoteDevice = $true
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $computername -Force
    }
    else
    {
        $remoteDevice = $false
    }
    Write-Host("Remote Device: $remoteDevice")
    
    function scheduleTask()
    {
        param(
            [string]$user,
            [bool]$remote,
            [bool]$deleteTask
        )

        $scriptBlock = {
            $taskname = "Daily Reboot"
            #check for existing task
            try
            {
                $objTask = Get-ScheduledTask -TaskName $taskname -ErrorAction Stop
                
                if ($objTask)
                {
                    $objTaskInfo = Get-ScheduledTaskInfo -TaskName $taskname -ErrorAction Stop
                    Write-Host("Task already exists:" + $objTask.TaskName)
                    Write-Host("Last Run Time:" + $objTaskInfo.LastRunTime)
                    Write-Host("Task State:" + $objTask.State)

                    if ($deleteTask)
                    {
                        $deleteTsk = Read-Host -Prompt "Do you wish to delete the existing task named: $taskname ? (input: DELETE, default is NO)"
                        if ($deleteTsk -ceq "DELETE")
                        {
                            Write-Host("Attempting to delete task")
                            Unregister-ScheduledTask -TaskName $taskname -Confirm:$false -ErrorAction Stop
                            
                            $tskDeleted = Get-ScheduledTask -TaskName $taskname -ErrorAction SilentlyContinue
                            if (-not $tskDeleted)
                            {
                                Write-Host("Task deleted successfully")
                            }
                        }
                    }
                    exit
                }
            }
            catch
            {
                #task does not exist so continue
                Write-Host("No existing task found")
            }
            
            $action = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /f /t 1"
            $trigger = New-ScheduledTaskTrigger -Daily -At 5:15am
            
            $credentials = Get-Credential -Credential $user #-WarningAction SilentlyContinue
            
            $username = $credentials.GetNetworkCredential().UserName
            $password = $credentials.GetNetworkCredential().Password
            if ($showPassword -eq $true)
            {
                Write-Host("Pwd:" + $password)
            }
            
            #$principal = New-ScheduledTaskPrincipal -UserId ("U151MT06R6T2W9X\Admin") -LogonType Password -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -Priority 4
            $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Description "Daily Reboot for MTRs"

            Register-ScheduledTask -TaskName $taskname -Action $action -Trigger $trigger -Settings $settings  -User $username -Password $password -RunLevel Highest -ErrorAction Stop
            
            #Get newly created task if no error
            $tskDailyReboot = Get-ScheduledTask -TaskName $taskname -ErrorAction Stop
            if ($tskDailyReboot)
            {
                $startTsk = Read-Host -Prompt "Do you wish to test and run the scheduled task now? (input: YES, default is NO)"
                if ($startTsk -eq "YES")
                {
                    Start-ScheduledTask -TaskName $taskname
                }
            }
        }

        if ($remote)
        {
            Write-Host "Executing remotely..."
            $retval = Test-Connection $computername -Count 1 -TimeoutSeconds 1 -Quiet
            if ($retval -eq "true")
            {
                Invoke-Command -ComputerName $computername -ScriptBlock $scriptBlock
            }
            else
            {
                Write-Host("Device is inaccessible or offline")
            }
        }
        else
        {
            Write-Host "Executing locally..."
            & $scriptBlock
        }
    }

    scheduleTask -user $username -remote $remoteDevice -deleteTask $deleteTask
} catch {
    # Handle errors
    Write-Host "Level1 Catch Error : $($_.Exception.Message)" -ForegroundColor Red
}