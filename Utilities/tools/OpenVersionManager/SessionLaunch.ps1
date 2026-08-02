# OpenVersionManager helpers - process/session launch boundary

# Dot-sourced by the public entrypoint before the on-demand interaction modules.

function Get-VersionManagerSessionProcesses {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    try {
        $state = Read-JsonFile -Path (Get-VersionManagerLaunchStatePath -Root $ResolvedTargetRoot)
        if ($null -eq $state) {
            return @()
        }

        $status = [string](Get-ObjectPropertyValue -Object $state -Name 'Status' -DefaultValue '')
        if ($status -notin @('launching', 'initializing', 'shown')) {
            return @()
        }

        $processId = [int](Get-ObjectPropertyValue -Object $state -Name 'ProcessId' -DefaultValue 0)
        if ($processId -le 0 -or $processId -eq $PID) {
            return @()
        }

        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return @()
        }

        if ($process.ProcessName -ne 'powershell') {
            Write-Log ("Skipping existing version manager session cleanup because launch-state PID {0} is now '{1}'." -f $processId, $process.ProcessName) 'WARN'
            return @()
        }

        return @($process)
    }
    catch {
        Write-Log ("Skipping existing version manager session cleanup after launch-state check failed: {0}" -f $_.Exception.Message) 'WARN'
    }
    return @()
}

function Stop-VersionManagerSessions {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    foreach ($process in @(Get-VersionManagerSessionProcesses -ResolvedTargetRoot $ResolvedTargetRoot)) {
        try {
            $processId = [int]$process.Id
            if ($processId -le 0) {
                continue
            }
            Write-Log ("Stopping existing version manager session PID {0}" -f $processId)
            Stop-Process -Id $processId -Force -ErrorAction Stop
            try {
                Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
            }
            catch {
            }
        }
        catch {
            Write-Log ("Failed to stop existing version manager session: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Start-VersionManagerLauncherForRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedTargetRoot
    )

    if (-not (Test-SkinRoot -Root $ResolvedTargetRoot)) {
        throw 'TargetRoot is not a valid Block HUD skin root.'
    }

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $ResolvedTargetRoot -ScriptRoot (Get-VersionManagerToolsRoot)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath

    Write-VersionManagerLaunchDiagnostic -Root $ResolvedTargetRoot -Stage 'launcher-before-session-cleanup' -LaunchTokenValue $LaunchToken -Details @(
        ('script={0}' -f (Get-VersionManagerEntrypointPath))
    )
    Stop-VersionManagerSessions -ResolvedTargetRoot $ResolvedTargetRoot
    Write-VersionManagerLaunchDiagnostic -Root $ResolvedTargetRoot -Stage 'launcher-after-session-cleanup' -LaunchTokenValue $LaunchToken
    Save-VersionManagerLaunchState -Root $ResolvedTargetRoot -Status 'launching' -LaunchTokenValue $LaunchToken

    $powershellExe = Get-PowerShellExecutablePath
    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-STA'
        '-File'
        (Get-VersionManagerEntrypointPath)
        '-TargetRoot'
        $ResolvedTargetRoot
        '-WindowSession'
    )
    if (-not [string]::IsNullOrWhiteSpace($LaunchToken)) {
        $argumentList += @('-LaunchToken', $LaunchToken)
    }
    if (-not [string]::IsNullOrWhiteSpace($InitialAction)) {
        $argumentList += @('-InitialAction', $InitialAction)
    }

    $startInfo = New-VersionManagerHostProcessStartInfo -Arguments $argumentList
    $startedProcess = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $startedProcess) {
        throw 'The Skin manager window session process could not be started.'
    }
    Write-Log ("Started version manager window session PID {0}" -f $startedProcess.Id)
    Write-VersionManagerLaunchDiagnostic -Root $ResolvedTargetRoot -Stage 'launcher-child-started' -LaunchTokenValue $LaunchToken -Details @(
        ('childPid={0}' -f $startedProcess.Id),
        ('powershell={0}' -f $powershellExe)
    )
    return $startedProcess
}

function Start-VersionManagerLauncher {
    $root = Get-TargetRoot
    $process = Start-VersionManagerLauncherForRoot -ResolvedTargetRoot $root
    $launchResult = Wait-VersionManagerLaunchShown -Root $root -ExpectedLaunchToken $LaunchToken -Process $process
    Write-VersionManagerLaunchDiagnostic -Root $root -Stage ('launcher-wait-' + [string]$launchResult.Status) -LaunchTokenValue $LaunchToken -Message ([string]$launchResult.Message) -Details @(
        ('observedStatus={0}' -f [string]$launchResult.ObservedStatus),
        ('observedToken={0}' -f [string]$launchResult.ObservedToken)
    )
    return $launchResult
}
