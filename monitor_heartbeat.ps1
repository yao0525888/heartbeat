$ErrorActionPreference = 'Stop'

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $scriptDir = (Get-Location).Path
}
$defaultLogPath = Join-Path $env:APPDATA 'Pi Network\logs\main.log'
$logPath = $defaultLogPath
$searchPattern = 'run: heartbeat: OK'
$statusLogPath = Join-Path $scriptDir 'heartbeat_status.log'
$lastOkFilePath = Join-Path $scriptDir 'last_heartbeat_ok.txt'
$lastAlertFilePath = Join-Path $scriptDir 'last_alert_time.txt'
$lastRecoveryFilePath = Join-Path $scriptDir 'last_recovery_time.txt'
$offlineCountFilePath = Join-Path $scriptDir 'offline_count.txt'
$lastPiRestartFilePath = Join-Path $scriptDir 'last_pi_restart_time.txt'
$lastSystemRebootFilePath = Join-Path $scriptDir 'last_system_reboot_time.txt'
$maxAge = New-TimeSpan -Minutes 6

function Get-MatchedLogLines {
    param(
        [string]$LogFilePath,
        [string]$Pattern,
        [int]$TailLines = 100
    )

    try {
        $matchedLines = Get-Content -Path $LogFilePath -Tail $TailLines -ErrorAction Stop |
            Select-String -SimpleMatch $Pattern
        return $matchedLines
    } catch {
        Write-Status "Failed to read log file: $($_.Exception.Message)"
        throw
    }
}

function Write-Status {
    param(
        [string]$Message
    )

    $line = '{0:o} - {1}' -f (Get-Date), $Message
    Set-Content -Path $statusLogPath -Value $line
    Write-Host $line
}

if (-not (Test-Path $logPath)) {
    try {
        $usersRoot = 'C:\Users'
        $candidateLogs = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $candidate = Join-Path $_.FullName 'AppData\Roaming\Pi Network\logs\main.log'
            if (Test-Path $candidate) {
                Get-Item $candidate
            }
        }

        if ($candidateLogs) {
            $logPath = ($candidateLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        }
    } catch {
    }
}

$matchedLines = $null
try {
    $matchedLines = Get-MatchedLogLines -LogFilePath $logPath -Pattern $searchPattern -TailLines 50
} catch {
}

Write-Host '=== Heartbeat monitor start ==='

if (-not (Test-Path $logPath)) {
    Write-Status "Log file not found: $logPath"
    exit 1
}

$now = Get-Date

$lastMatchLine = $null
if ($matchedLines) {
    $lastMatchLine = ($matchedLines | Select-Object -Last 1).Line.Trim()
    Write-Status "Found heartbeat OK entry in last 100 lines."
} else {
    Write-Status "No heartbeat OK entry found in last 100 lines."
}

$storedTime = $null
$storedLogLine = $null

if (Test-Path $lastOkFilePath) {
    $raw = Get-Content $lastOkFilePath -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($raw) {
        $sepIndex = $raw.IndexOf('|')
        $timeStr = $null

        if ($sepIndex -ge 0) {
            $storedLogLine = $raw.Substring(0, $sepIndex).Trim()
            if ($sepIndex + 1 -lt $raw.Length) {
                $timeStr = $raw.Substring($sepIndex + 1)
            }
        } else {
            $timeStr = $raw
        }

        if ($timeStr) {
            try {
                $storedTime = [datetime]::Parse($timeStr)
            } catch {
                Write-Status ("Warning: cannot parse stored heartbeat time '{0}'. It will be ignored." -f $timeStr)
            }
        }
    }
}

$lastOkTime = $storedTime
$wasOffline = $false

if ($storedTime) {
    $storedAge = $now - $storedTime
    if ($storedAge -gt $maxAge) {
        $wasOffline = $true
    }
}

if ($lastMatchLine) {
    $currentLogLine = $lastMatchLine.Trim()
    $needsUpdate = $true
    
    if ($storedLogLine -and $currentLogLine -eq $storedLogLine) {
        $needsUpdate = $false
        Write-Status "Last heartbeat log line unchanged. Skipping file update."
    }
    
    if ($needsUpdate) {
        $lastOkTime = $now
        $data = '{0}|{1:o}' -f $currentLogLine, $lastOkTime
        Set-Content -Path $lastOkFilePath -Value $data
        Write-Status "Updated last heartbeat OK time to $lastOkTime."
    } else {
        $lastOkTime = $storedTime
    }
    
    if ($wasOffline) {
        if (Test-Path $offlineCountFilePath) {
            Remove-Item $offlineCountFilePath -ErrorAction SilentlyContinue
            Write-Status "Heartbeat recovered. Reset offline count."
        }
        
        $lastRecoveryTime = $null
        if (Test-Path $lastRecoveryFilePath) {
            $recoveryRaw = Get-Content $lastRecoveryFilePath -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($recoveryRaw) {
                [datetime]$tmpRecovery = $null
                if ([datetime]::TryParse($recoveryRaw, [ref]$tmpRecovery)) {
                    $lastRecoveryTime = $tmpRecovery
                }
            }
        }

        if ($lastRecoveryTime -and $lastRecoveryTime -gt $storedTime) {
            Write-Status ("Heartbeat recovered but recovery notification already sent at {0:o}." -f $lastRecoveryTime)
        } else {
            Write-Status "Heartbeat recovered from offline state. Sending recovery notification."
            $sendEmailBat = Join-Path $scriptDir 'runsend_email.bat'
            
            if (Test-Path $sendEmailBat) {
                try {
                    $cmd = 'cmd.exe'
                    $escapedPath = '"' + $sendEmailBat + '"'
                    $arguments = "/c echo.|$escapedPath on"
                    
                    $process = Start-Process -FilePath $cmd -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
                    $exitCode = $process.ExitCode
                    Write-Status ("runsend_email.bat finished with exit code {0}." -f $exitCode)
                    
                    if ($exitCode -eq 0) {
                        $recoveryTime = Get-Date
                        Set-Content -Path $lastRecoveryFilePath -Value ($recoveryTime.ToString('o'))
                        Write-Status ("Recovery notification sent successfully at {0:o}. Recorded as last recovery time." -f $recoveryTime)
                    }
                } catch {
                    Write-Status ("Failed to start runsend_email.bat: {0}" -f $_.Exception.Message)
                }
            } else {
                Write-Status "runsend_email.bat not found at $sendEmailBat. Skipping recovery notification."
            }
        }
    }
} else {
    if (-not $lastOkTime) {
        $lastOkTime = $now
        $data = '|{0:o}' -f $lastOkTime
        Set-Content -Path $lastOkFilePath -Value $data
        Write-Status "No heartbeat OK seen; initializing last OK time to $lastOkTime."
    } else {
        Write-Status "Using stored last heartbeat OK time: $lastOkTime."
    }
}

$age = $now - $lastOkTime
Write-Status ("Current heartbeat age: {0:c}" -f $age)

$needAlert = $false
$needSystemReboot = $false
$offlineCount = 0

if ($age -gt $maxAge) {
    if (Test-Path $offlineCountFilePath) {
        $countRaw = Get-Content $offlineCountFilePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($countRaw) {
            if ([int]::TryParse($countRaw, [ref]$offlineCount)) {
                $offlineCount = [int]$countRaw
            }
        }
    }
    
    $offlineCount = $offlineCount + 1
    Set-Content -Path $offlineCountFilePath -Value $offlineCount.ToString()
    Write-Status ("Heartbeat age > {0}. Offline count: {1}" -f $maxAge, $offlineCount)
    
    if ($offlineCount -eq 1) {
        Write-Status "First offline detection (count=1). Restarting Pi Network application."
        
        try {
            $piProcesses = Get-Process -Name "Pi Network" -ErrorAction SilentlyContinue
            if ($piProcesses) {
                $piProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Status "Stopped existing Pi Network processes."
                Start-Sleep -Seconds 3
            }
            
            $usersRoot = 'C:\Users'
            $piNetworkExe = $null
            $candidateExes = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $candidate = Join-Path $_.FullName 'AppData\Local\Programs\pi-network-desktop\Pi Network.exe'
                if (Test-Path $candidate) {
                    Get-Item $candidate
                }
            }
            
            if ($candidateExes) {
                $piNetworkExe = ($candidateExes | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                Write-Status "Found Pi Network.exe at: $piNetworkExe"
                
                $workingDir = Split-Path -Parent $piNetworkExe
                Write-Status "Working directory: $workingDir"
                
                try {
                    $explorerProcesses = Get-Process -Name explorer -ErrorAction SilentlyContinue
                    if (-not $explorerProcesses) {
                        throw "No active user session found (no explorer.exe)"
                    }
                    
                    $loggedOnUsers = @()
                    try {
                        $explorerProcesses | ForEach-Object {
                            try {
                                $owner = $_.GetOwner()
                                if ($owner -and $owner.User) {
                                    if ($loggedOnUsers -notcontains $owner.User) {
                                        $loggedOnUsers += $owner.User
                                    }
                                }
                            } catch {
                            }
                        }
                    } catch {
                    }
                    
                    if ($loggedOnUsers.Count -eq 0) {
                        try {
                            $explorerOwner = (Get-WmiObject Win32_Process -Filter "name='explorer.exe'" | Select-Object -First 1).GetOwner()
                            if ($explorerOwner -and $explorerOwner.User) {
                                $loggedOnUsers += $explorerOwner.User
                            }
                        } catch {
                        }
                    }
                    
                    if ($loggedOnUsers.Count -eq 0) {
                        $loggedOnUsers = @($env:USERNAME)
                    }
                    
                    $targetUser = $loggedOnUsers[0]
                    Write-Status "Target user for GUI launch: $targetUser"
                    
                    $tempTaskName = "StartPiNetwork_$(Get-Date -Format 'yyyyMMddHHmmss')"
                    $batContent = "@echo off`r`ncd /d `"$workingDir`"`r`nstart `"`" `"$piNetworkExe`""
                    $tempBat = Join-Path $env:TEMP "$tempTaskName.bat"
                    Set-Content -Path $tempBat -Value $batContent -Encoding ASCII
                    
                    $taskCommand = "schtasks /create /tn `"$tempTaskName`" /tr `"$tempBat`" /sc once /st 23:59 /ru `"$targetUser`" /rl HIGHEST /f"
                    Write-Status "Creating temporary task to start Pi Network as user: $targetUser"
                    
                    $result = cmd.exe /c $taskCommand 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        schtasks /run /tn $tempTaskName | Out-Null
                        Start-Sleep -Seconds 5
                        
                        schtasks /delete /tn $tempTaskName /f | Out-Null
                        Start-Sleep -Seconds 1
                        Remove-Item $tempBat -ErrorAction SilentlyContinue
                        
                        $checkProcess = Get-Process -Name "Pi Network" -ErrorAction SilentlyContinue
                        if ($checkProcess) {
                            Write-Status "Pi Network application started successfully via scheduled task (PID: $($checkProcess.Id))."
                            $piRestartTime = Get-Date
                            Set-Content -Path $lastPiRestartFilePath -Value ($piRestartTime.ToString('o'))
                            Write-Status "Recorded Pi Network restart time: $($piRestartTime.ToString('o'))"
                        } else {
                            Write-Status "Scheduled task executed but Pi Network process not found. Please check manually."
                        }
                    } else {
                        Write-Status "Failed to create scheduled task: $result"
                        Remove-Item $tempBat -ErrorAction SilentlyContinue
                        throw "Could not create scheduled task"
                    }
                } catch {
                    Write-Status "Failed to start Pi Network via scheduled task: $($_.Exception.Message)"
                    
                    try {
                        $vbsContent = @"
Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

piExePath = "$piNetworkExe"
workingDir = "$workingDir"

If objFSO.FileExists(piExePath) Then
    objShell.CurrentDirectory = workingDir
    objShell.Run """" & piExePath & """", 1, False
End If
"@
                        $tempVbs = Join-Path $env:TEMP "start_pi_$(Get-Date -Format 'yyyyMMddHHmmss').vbs"
                        Set-Content -Path $tempVbs -Value $vbsContent -Encoding ASCII
                        
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = 'wscript.exe'
                        $psi.Arguments = "`"$tempVbs`""
                        $psi.UseShellExecute = $true
                        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                        [System.Diagnostics.Process]::Start($psi) | Out-Null
                        Start-Sleep -Seconds 4
                        
                        Remove-Item $tempVbs -ErrorAction SilentlyContinue
                        
                        $checkProcess2 = Get-Process -Name "Pi Network" -ErrorAction SilentlyContinue
                        if ($checkProcess2) {
                            Write-Status "Pi Network application started via VBScript fallback (PID: $($checkProcess2.Id))."
                            $piRestartTime = Get-Date
                            Set-Content -Path $lastPiRestartFilePath -Value ($piRestartTime.ToString('o'))
                            Write-Status "Recorded Pi Network restart time: $($piRestartTime.ToString('o'))"
                        } else {
                            Write-Status "VBScript fallback executed but Pi Network process not found."
                        }
                    } catch {
                        Write-Status "VBScript fallback also failed: $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Status "Pi Network.exe not found in any user directory. Searched: $usersRoot"
            }
        } catch {
            Write-Status ("Failed to restart Pi Network: {0}" -f $_.Exception.Message)
            Write-Status ("Exception: {0}" -f $_.Exception.ToString())
        }
    } elseif ($offlineCount -eq 4) {
        Write-Status "Pi Network restart didn't help (count=4). Will restart system."
        $needSystemReboot = $true
    } elseif ($offlineCount -ge 7) {
        Write-Status "System reboot didn't help (count=$offlineCount). Will send alert email."
        
        $lastAlertTime = $null
        if (Test-Path $lastAlertFilePath) {
            $alertRaw = Get-Content $lastAlertFilePath -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($alertRaw) {
                [datetime]$tmpAlert = $null
                if ([datetime]::TryParse($alertRaw, [ref]$tmpAlert)) {
                    $lastAlertTime = $tmpAlert
                }
            }
        }

        if ($lastAlertTime -and $lastAlertTime -gt $lastOkTime) {
            $needAlert = $false
            Write-Status ("Heartbeat age is > {0} but alert already sent at {1:o}." -f $maxAge, $lastAlertTime)
        } else {
            $needAlert = $true
            Write-Status ("Heartbeat offline after Pi restart and system reboot. Sending alert email." -f $maxAge, $offlineCount)
        }
    } else {
        Write-Status ("Heartbeat still offline (count: {0}). Waiting for escalation thresholds (4=reboot system, 7=send email)." -f $offlineCount)
    }
} else {
    Write-Status ("Heartbeat age <= {0}. No alert needed." -f $maxAge)
    if (Test-Path $offlineCountFilePath) {
        Remove-Item $offlineCountFilePath -ErrorAction SilentlyContinue
    }
}

if ($needSystemReboot) {
    try {
        $rebootTime = Get-Date
        Set-Content -Path $lastSystemRebootFilePath -Value ($rebootTime.ToString('o'))
        Write-Status ("Recorded system reboot request time: {0:o}" -f $rebootTime)
        
        $shutdownArgs = '/r /t 60 /c "Pi Network heartbeat still offline after Pi restart. System will reboot in 60 seconds."'
        Start-Process -FilePath 'shutdown.exe' -ArgumentList $shutdownArgs -WindowStyle Hidden
        Write-Status 'Scheduled system reboot in 60 seconds due to persistent offline status.'
    } catch {
        Write-Status ("Failed to schedule system reboot: {0}" -f $_.Exception.Message)
    }
}

if ($needAlert) {
    $sendEmailBat = Join-Path $scriptDir 'runsend_email.bat'

    if (-not (Test-Path $sendEmailBat)) {
        Write-Status "runsend_email.bat not found at $sendEmailBat. Skipping email alert."
    } else {
        try {
            $cmd = 'cmd.exe'
            $escapedPath = '"' + $sendEmailBat + '"'
            $arguments = "/c echo.|$escapedPath"

            $process = Start-Process -FilePath $cmd -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            $exitCode = $process.ExitCode
            Write-Status ("runsend_email.bat finished with exit code {0}." -f $exitCode)

            if ($exitCode -eq 0) {
                $alertTime = Get-Date
                Set-Content -Path $lastAlertFilePath -Value ($alertTime.ToString('o'))
                Write-Status ("Offline alert sent successfully at {0:o}. Recorded as last alert time." -f $alertTime)
            } else {
                Write-Status "Email script reported failure. Alert time not updated so it can be retried."
            }
        } catch {
            Write-Status ("Failed to start runsend_email.bat: {0}" -f $_.Exception.Message)
        }
    }
}

if (-not $needAlert -and -not $needSystemReboot) {
    Write-Status 'No alert or reboot action taken this run.'
}
Write-Host '=== Heartbeat monitor end ==='
exit 0
