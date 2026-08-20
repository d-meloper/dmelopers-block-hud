[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SkinRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{32}$')][string]$Token,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{32}$')][string]$LaunchAttemptId,
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$LauncherProcessId,
    [Parameter(Mandatory = $true)][ValidateRange(1, 9223372036854775807)][int64]$LauncherStartTimeUtcTicks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

. (Join-Path $PSScriptRoot 'VersionManager.OperationLock.ps1')

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Read-PendingState {
    param([Parameter(Mandatory = $true)][string]$Path)
    $value = [System.IO.File]::ReadAllText($Path, $utf8NoBom) | ConvertFrom-Json
    if ([int]$value.SchemaVersion -ne 1 -or
        -not [string]::Equals([string]$value.Token, $Token, [System.StringComparison]::Ordinal)) {
        throw 'Mouse plugin pending state token is invalid.'
    }
    return $value
}

function Get-CurrentPowerShellIdentity {
    $process = Get-Process -Id $PID -ErrorAction Stop
    return [PSCustomObject]@{
        ProcessId = [int]$process.Id
        StartTimeUtcTicks = [int64]$process.StartTime.ToUniversalTime().Ticks
        ExecutablePath = [System.IO.Path]::GetFullPath([string]$process.Path)
    }
}

function Wait-VersionMutationBoundary {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $deadline = [DateTime]::UtcNow.AddSeconds(75)
    $waitLogged = $false
    do {
        $candidate = Enter-VersionManagerOperationMutex -TargetRoot $TargetRoot
        if ([bool]$candidate.Acquired) {
            if ([bool]$candidate.Abandoned) {
                Write-MouseUpdateTrace -Stage 'VERSION_MUTATION_LOCK_RECOVERED' -Message ([string]$candidate.Name) -Level 'WARN'
            }
            return $candidate
        }
        Exit-VersionManagerOperationMutex -Lock $candidate
        if (-not $waitLogged) {
            Write-MouseUpdateTrace -Stage 'VERSION_MUTATION_LOCK_WAIT' -Message 'Waiting for the installing version operation to commit or roll back.'
            $waitLogged = $true
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    Write-MouseUpdateTrace -Stage 'VERSION_MUTATION_LOCK_TIMEOUT' -Message 'The installing version operation did not release its mutation lock within 75 seconds; Mouse.dll was not touched.' -Level 'ERROR'
    return $null
}

function Write-RestartReadyState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet(0, 1)][int]$Ready
    )
    $content = "[Variables]`r`nToken=$Token`r`nReady=$Ready`r`n"
    $temporaryPath = $Path + '.' + $PID + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, $content, [System.Text.Encoding]::Unicode)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-RestartReadyValue {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return -1 }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::Unicode)
    $tokenMatch = [regex]::Match($text, '(?m)^Token=(?<Value>[a-f0-9]{32})\s*$')
    $readyMatch = [regex]::Match($text, '(?m)^Ready=(?<Value>[01])\s*$')
    if (-not $tokenMatch.Success -or -not $readyMatch.Success -or
        -not [string]::Equals($tokenMatch.Groups['Value'].Value, $Token, [System.StringComparison]::Ordinal)) {
        throw 'Mouse plugin restart-ready state identity is invalid.'
    }
    return [int]$readyMatch.Groups['Value'].Value
}

function Write-PendingState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$State
    )
    $temporaryPath = $Path + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, ($State | ConvertTo-Json -Depth 5), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Set-PendingStateProperty {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Value
    )

    Add-Member -InputObject $State -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Assert-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Context
    )
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escapes its authorized root: $resolvedPath"
    }
    return $resolvedPath
}

function Get-ExactRainmeterProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$ProcessId = 0,
        [int64]$StartTimeUtcTicks = 0
    )
    $matches = @(Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue | Where-Object {
        try {
            [string]::Equals([System.IO.Path]::GetFullPath([string]$_.Path), [System.IO.Path]::GetFullPath($Path), [System.StringComparison]::OrdinalIgnoreCase)
        }
        catch { $false }
    })
    if ($ProcessId -gt 0) {
        $matches = @($matches | Where-Object {
            $_.Id -eq $ProcessId -and ($StartTimeUtcTicks -le 0 -or $_.StartTime.ToUniversalTime().Ticks -eq $StartTimeUtcTicks)
        })
    }
    if ($matches.Count -gt 1) {
        throw "More than one matching Rainmeter process is running. path=$Path"
    }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Invoke-RainmeterBang {
    param(
        [Parameter(Mandatory = $true)][string]$RainmeterPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $RainmeterPath @Arguments | Out-Null
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Rainmeter bang failed with exit code $LASTEXITCODE."
    }
}

function Wait-RainmeterExit {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    if (-not $Process.WaitForExit(30000)) {
        throw 'Rainmeter did not exit within 30 seconds.'
    }
}

function Start-ExactRainmeter {
    param([Parameter(Mandatory = $true)][string]$Path)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Path
    $startInfo.WorkingDirectory = Split-Path -Parent $Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw 'Rainmeter could not be restarted.' }
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 100
        $running = Get-ExactRainmeterProcess -Path $Path -ProcessId $process.Id
        if ($null -ne $running) { return $running }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Restarted Rainmeter did not become ready within 30 seconds.'
}

function Invoke-AdapterCleanup {
    param([Parameter(Mandatory = $true)][object]$State)
    $helper = Join-Path $resolvedRoot 'Utilities\tools\Remove-LegacyLayoutTransportAdapter.ps1'
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
        throw 'Legacy adapter cleanup helper is missing after Mouse.dll replacement.'
    }
    $output = @(& $helper `
        -SkinRoot $resolvedRoot -RootConfig ([string]$State.RootConfig) -SettingsPath ([string]$State.SettingsPath) `
        -ErrorAction Stop 2>&1)
    if ($output.Count -gt 0) {
        Write-MouseUpdateTrace -Stage 'ADAPTER_CLEANUP_OUTPUT' -Message (($output | ForEach-Object { [string]$_ }) -join ' | ')
    }
}

function Invoke-PreviousRootRecovery {
    param([Parameter(Mandatory = $true)][object]$State)
    $previousRoot = [System.IO.Path]::GetFullPath([string]$State.PreviousRoot)
    if (-not (Test-Path -LiteralPath $previousRoot -PathType Container)) { return $false }
    $switchHelper = Join-Path $resolvedRoot 'Utilities\tools\SwitchActiveSkinVersion.ps1'
    if (-not (Test-Path -LiteralPath $switchHelper -PathType Leaf)) { return $false }
    $results = @(& $switchHelper `
        -CurrentTargetRoot $resolvedRoot -SelectedTargetRoot $previousRoot -PassThruResultObject `
        -ErrorAction Stop 2>&1)
    $result = @($results | Where-Object { $null -ne $_.PSObject.Properties['DMEL_STATUS'] } | Select-Object -Last 1)
    if ($result.Count -ne 1 -or
        [string]$result[0].DMEL_STATUS -notin @('OK', 'NOOP')) {
        $detail = if ($result.Count -eq 1) { [string]$result[0].DMEL_MESSAGE } else { ($results | ForEach-Object { [string]$_ }) -join ' | ' }
        throw "Previous-root recovery failed: $detail"
    }
    return $true
}

function Invoke-TargetRootActivation {
    param([Parameter(Mandatory = $true)][object]$State)
    $previousRoot = [System.IO.Path]::GetFullPath([string]$State.PreviousRoot)
    $switchHelper = Join-Path $resolvedRoot 'Utilities\tools\SwitchActiveSkinVersion.ps1'
    if (-not (Test-Path -LiteralPath $previousRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $switchHelper -PathType Leaf)) {
        throw 'The previous-root recovery context required to finish Mouse.dll retry is unavailable.'
    }
    $results = @(& $switchHelper `
        -CurrentTargetRoot $previousRoot -SelectedTargetRoot $resolvedRoot -PassThruResultObject `
        -ErrorAction Stop 2>&1)
    $result = @($results | Where-Object { $null -ne $_.PSObject.Properties['DMEL_STATUS'] } | Select-Object -Last 1)
    if ($result.Count -ne 1 -or [string]$result[0].DMEL_STATUS -notin @('OK', 'NOOP')) {
        $detail = if ($result.Count -eq 1) { [string]$result[0].DMEL_MESSAGE } else { ($results | ForEach-Object { [string]$_ }) -join ' | ' }
        throw "Target-root activation after Mouse.dll retry failed: $detail"
    }
}

function Get-RetryModalToken {
    param([Parameter(Mandatory = $true)][object]$State)
    $attemptId = if ($State.PSObject.Properties.Name -contains 'RetryOfLaunchAttemptId') { [string]$State.RetryOfLaunchAttemptId } else { '' }
    if ($attemptId -notmatch '^[a-f0-9]{32}$') { return '' }
    return 'mouse-plugin-update-retry-' + [string]$State.Token + '-' + $attemptId
}

function Close-UpdateNotices {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$RainmeterPath
    )
    $modalConfig = [string]$State.RootConfig + '\Utilities\Modal'
    Invoke-RainmeterBang -RainmeterPath $RainmeterPath -Arguments @('!CommandMeasure', 'MeasureModal', "CloseIfToken('mouse-plugin-update')", $modalConfig)
    $retryModalToken = Get-RetryModalToken -State $State
    if (-not [string]::IsNullOrWhiteSpace($retryModalToken)) {
        Invoke-RainmeterBang -RainmeterPath $RainmeterPath -Arguments @('!CommandMeasure', 'MeasureModal', ("CloseIfToken('{0}')" -f $retryModalToken), $modalConfig)
    }
}

function Show-RetrySurface {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$RainmeterPath
    )
    $rootConfig = [string]$State.RootConfig
    Invoke-RainmeterBang -RainmeterPath $RainmeterPath -Arguments @('!ActivateConfig', ($rootConfig + '\Utilities\Modal'), 'Modal.ini')
    Invoke-RainmeterBang -RainmeterPath $RainmeterPath -Arguments @('!ActivateConfig', ($rootConfig + '\Utilities\MousePluginUpdate'), 'MousePluginUpdate.ini')
}

function Remove-UpdateArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$PendingPath,
        [Parameter(Mandatory = $true)][string]$PayloadRoot,
        [AllowEmptyString()][string]$BackupPath,
        [Parameter(Mandatory = $true)][string[]]$MarkerPaths
    )
    if ($BackupPath -ne '' -and (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        Remove-Item -LiteralPath $BackupPath -Force
    }
    if (Test-Path -LiteralPath $PayloadRoot -PathType Container) {
        Remove-Item -LiteralPath $PayloadRoot -Recurse -Force
    }
    $payloadParent = Split-Path -Parent $PayloadRoot
    if ((Test-Path -LiteralPath $payloadParent -PathType Container) -and
        @(Get-ChildItem -LiteralPath $payloadParent -Force).Count -eq 0) {
        Remove-Item -LiteralPath $payloadParent -Force
    }
    if (Test-Path -LiteralPath $PendingPath -PathType Leaf) {
        Remove-Item -LiteralPath $PendingPath -Force
    }
    foreach ($markerPath in $MarkerPaths) {
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            Remove-Item -LiteralPath $markerPath -Force
        }
    }
}

function Read-RainmeterIniText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes, $offset, $bytes.Length - $offset)
}

function Get-RainmeterConfigActiveState {
    param(
        [Parameter(Mandatory = $true)][string]$SettingsPath,
        [Parameter(Mandatory = $true)][string]$ConfigName
    )

    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        throw "Rainmeter settings file is missing while waiting for Bootstrap shutdown: $SettingsPath"
    }
    $text = Read-RainmeterIniText -Path $SettingsPath
    $sectionPattern = '(?ms)^\[' + [regex]::Escape($ConfigName) + '\]\s*\r?\n(?<Body>.*?)(?=^\[|\z)'
    $sectionMatch = [regex]::Match($text, $sectionPattern)
    if (-not $sectionMatch.Success) {
        throw "Rainmeter settings do not contain the Bootstrap config section: $ConfigName"
    }
    $activeMatch = [regex]::Match($sectionMatch.Groups['Body'].Value, '(?m)^Active\s*=\s*(?<Value>[^\r\n]*)')
    if (-not $activeMatch.Success) {
        throw "Rainmeter settings do not contain Bootstrap Active state: $ConfigName"
    }
    $value = $activeMatch.Groups['Value'].Value.Trim()
    if ($value -eq '1') { return $true }
    if ($value -eq '0') { return $false }
    throw "Rainmeter Bootstrap Active state is invalid: config=$ConfigName value=$value"
}

function Wait-BootstrapInactive {
    param(
        [Parameter(Mandatory = $true)][string]$SettingsPath,
        [Parameter(Mandatory = $true)][string]$RootConfig,
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$RainmeterProcess
    )

    $bootstrapConfig = $RootConfig.TrimEnd('\') + '\Utilities\Bootstrap'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $lastState = $null
    Write-MouseUpdateTrace -Stage 'BOOTSTRAP_WAIT_BEGIN' -Message ("config={0}; timeoutSeconds=15" -f $bootstrapConfig)
    do {
        $RainmeterProcess.Refresh()
        if ($RainmeterProcess.HasExited) {
            throw 'Rainmeter exited before the Mouse.dll session observed Bootstrap shutdown.'
        }
        $isActive = Get-RainmeterConfigActiveState -SettingsPath $SettingsPath -ConfigName $bootstrapConfig
        if ($null -eq $lastState -or [bool]$lastState -ne $isActive) {
            Write-MouseUpdateTrace -Stage 'BOOTSTRAP_STATE' -Message ("active={0}" -f ([int]$isActive))
            $lastState = $isActive
        }
        if (-not $isActive) {
            Write-MouseUpdateTrace -Stage 'BOOTSTRAP_CLOSED' -Message 'Bootstrap is inactive; Rainmeter shutdown may begin.'
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Bootstrap remained active for 15 seconds; Mouse.dll replacement was not started.'
}

function Wait-RestartReady {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$RainmeterProcess
    )
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    Write-MouseUpdateTrace -Stage 'RESTART_HANDOFF_WAIT_BEGIN' -Message ("path={0}; rainmeterPid={1}; timeoutSeconds=30" -f $Path, $RainmeterProcess.Id)
    do {
        $RainmeterProcess.Refresh()
        if ($RainmeterProcess.HasExited) {
            throw 'Restarted Rainmeter exited before acknowledging the Mouse.dll handoff.'
        }
        if ((Get-RestartReadyValue -Path $Path) -eq 1) {
            Write-MouseUpdateTrace -Stage 'RESTART_HANDOFF_OBSERVED' -Message ("rainmeterPid={0}; path={1}" -f $RainmeterProcess.Id, $Path)
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Restarted Rainmeter did not acknowledge the Mouse.dll handoff within 30 seconds.'
}

$resolvedRoot = [System.IO.Path]::GetFullPath($SkinRoot)
$pendingPath = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot '@Resources\Customs\Data\MousePluginUpdatePending.json') -Root $resolvedRoot -Context 'Pending state'
$launchRequestPath = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot '@Resources\Customs\Data\MousePluginUpdateLaunchRequested.inc') -Root $resolvedRoot -Context 'Mouse launch request state'
$restartReadyPath = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot '@Resources\Customs\Data\MousePluginUpdateRestartReady.inc') -Root $resolvedRoot -Context 'Mouse restart-ready state'
$cancellationPath = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot '@Resources\Customs\Data\MousePluginUpdateCancelled.inc') -Root $resolvedRoot -Context 'Mouse cancellation state'
$logRoot = Join-Path $resolvedRoot '@Resources\Customs\Logs'
if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
$logPath = Join-Path $logRoot ('MousePluginUpdate_{0}.log' -f $Token)
$canonicalLogPath = Join-Path (Join-Path $resolvedRoot 'Logs') "DMeloper's Block HUD Log.log"

function Write-MouseUpdateTrace {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $safeMessage = ([string]$Message -replace '[\r\n\0]+', ' ').Trim()
    $line = '[{0}] [{1}] [SESSION] [token={2}] [pid={3}] {4}: {5}' -f `
        [DateTime]::UtcNow.ToString('o'), $Level, $Token, $PID, $Stage, $safeMessage
    foreach ($entry in @(
        [PSCustomObject]@{ Path = $logPath; Text = $line + [Environment]::NewLine },
        [PSCustomObject]@{ Path = $canonicalLogPath; Text = '<MousePluginUpdate>' + [Environment]::NewLine + $line + [Environment]::NewLine + [Environment]::NewLine }
    )) {
        try {
            $parent = Split-Path -Parent ([string]$entry.Path)
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                [void][System.IO.Directory]::CreateDirectory($parent)
            }
            [System.IO.File]::AppendAllText([string]$entry.Path, [string]$entry.Text, $utf8NoBom)
        }
        catch {
            # The update state machine must still reach rollback if a log path becomes unavailable.
        }
    }
}

$activationCommitted = $false
$rainmeterStoppedBySession = $false
$pluginMutationStarted = $false
$state = $null
$versionOperationLock = $null
$sessionIdentity = Get-CurrentPowerShellIdentity
Write-MouseUpdateTrace -Stage 'SESSION_BEGIN' -Message ("attempt={0}; sessionStartTicks={1}; executable={2}; root={3}" -f $LaunchAttemptId, $sessionIdentity.StartTimeUtcTicks, $sessionIdentity.ExecutablePath, $resolvedRoot)

try {
    $state = Read-PendingState -Path $pendingPath
    Write-MouseUpdateTrace -Stage 'PENDING_READ' -Message ("phase={0}; action={1}; architecture={2}" -f [string]$state.Phase, [string]$state.Action, [string]$state.Architecture)
    if (-not [string]::Equals([string]$state.Phase, 'Launching', [System.StringComparison]::Ordinal) -or
        -not [string]::Equals([string]$state.LaunchAttemptId, $LaunchAttemptId, [System.StringComparison]::Ordinal) -or
        [int]$state.LauncherProcessId -ne $LauncherProcessId -or
        [int64]$state.LauncherStartTimeUtcTicks -ne $LauncherStartTimeUtcTicks) {
        throw 'Mouse plugin session launch ownership does not match the pending state.'
    }
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string]$state.TargetRoot), $resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Mouse plugin pending state targets a different skin root.'
    }
    $state.Phase = 'Running'
    Set-PendingStateProperty -State $state -Name 'SessionProcessId' -Value $sessionIdentity.ProcessId
    Set-PendingStateProperty -State $state -Name 'SessionStartTimeUtcTicks' -Value $sessionIdentity.StartTimeUtcTicks
    Set-PendingStateProperty -State $state -Name 'SessionExecutablePath' -Value $sessionIdentity.ExecutablePath
    Set-PendingStateProperty -State $state -Name 'SessionStartedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'Running'
    Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Write-PendingState -Path $pendingPath -State $state
    Write-MouseUpdateTrace -Stage 'SESSION_OWNERSHIP_PUBLISHED' -Message ("attempt={0}; sessionPid={1}; sessionStartTicks={2}" -f $LaunchAttemptId, $sessionIdentity.ProcessId, $sessionIdentity.StartTimeUtcTicks)

    $versionOperationLock = Wait-VersionMutationBoundary -TargetRoot $resolvedRoot
    if ($null -eq $versionOperationLock) {
        return
    }
    Write-MouseUpdateTrace -Stage 'VERSION_MUTATION_LOCK_ACQUIRED' -Message ([string]$versionOperationLock.Name)
    if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
        Write-MouseUpdateTrace -Stage 'PENDING_REMOVED_BEFORE_MUTATION' -Message 'The installing version operation removed the destination handoff before Mouse.dll mutation.' -Level 'WARN'
        return
    }
    $state = Read-PendingState -Path $pendingPath
    if (-not [string]::Equals([string]$state.Phase, 'Running', [System.StringComparison]::Ordinal) -or
        -not [string]::Equals([string]$state.LaunchAttemptId, $LaunchAttemptId, [System.StringComparison]::Ordinal) -or
        [int]$state.SessionProcessId -ne $sessionIdentity.ProcessId -or
        [int64]$state.SessionStartTimeUtcTicks -ne $sessionIdentity.StartTimeUtcTicks) {
        throw 'Mouse plugin session ownership changed before the version mutation boundary was acquired.'
    }
    if (Test-Path -LiteralPath $cancellationPath -PathType Leaf) {
        $state.Phase = 'Cancelled'
        Set-PendingStateProperty -State $state -Name 'CancelledAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
        Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'CancelledBeforeMutation'
        Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
        Write-PendingState -Path $pendingPath -State $state
        Write-MouseUpdateTrace -Stage 'CANCELLED_BEFORE_MUTATION' -Message 'The parent version install canceled and rolled back; Mouse.dll was not touched.' -Level 'WARN'
        return
    }
    $retryMode = if ($state.PSObject.Properties.Name -contains 'RetryMode') { [string]$state.RetryMode } else { 'Install' }
    $rainmeterPath = [System.IO.Path]::GetFullPath([string]$state.RainmeterPath)
    if (-not (Test-Path -LiteralPath $rainmeterPath -PathType Leaf) -or
        -not [string]::Equals([System.IO.Path]::GetFileName($rainmeterPath), 'Rainmeter.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Pending state contains an invalid Rainmeter executable path.'
    }
    $pluginTarget = [System.IO.Path]::GetFullPath([string]$state.PluginTargetPath)
    if (-not [string]::Equals([System.IO.Path]::GetFileName($pluginTarget), 'Mouse.dll', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals((Split-Path -Leaf (Split-Path -Parent $pluginTarget)), 'Plugins', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Pending state contains an invalid Mouse.dll target path.'
    }
    $expectedHash = ([string]$state.ExpectedSha256).ToUpperInvariant()
    if ($expectedHash -notmatch '^[0-9A-F]{64}$') { throw 'Pending state contains an invalid Mouse.dll hash.' }
    if ([string]::Equals($retryMode, 'Finalize', [System.StringComparison]::Ordinal)) {
        if (-not (Test-Path -LiteralPath $pluginTarget -PathType Leaf) -or
            -not [string]::Equals((Get-Sha256Hex -Path $pluginTarget), $expectedHash, [System.StringComparison]::Ordinal)) {
            throw 'Finalization retry cannot verify the installed Mouse.dll.'
        }
        $running = Get-ExactRainmeterProcess -Path $rainmeterPath
        if ($null -eq $running) { throw 'Rainmeter is not running for Mouse.dll finalization retry.' }
        $state.Phase = 'Finalizing'
        Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'FinalizingRetry'
        Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
        Write-PendingState -Path $pendingPath -State $state
        $activationCommitted = $true
        Write-MouseUpdateTrace -Stage 'FINALIZATION_RETRY_BEGIN' -Message 'The verified Mouse.dll will not be replaced again.' -Level 'WARN'
        Invoke-AdapterCleanup -State $state
        $payloadRoot = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot '@Resources\UpdaterPayload\Mouse') -Root $resolvedRoot -Context 'Mouse payload root'
        $backupPath = $pluginTarget + '.dmeloper-v3201-' + $Token + '.bak'
        Remove-UpdateArtifacts -PendingPath $pendingPath -PayloadRoot $payloadRoot -BackupPath $backupPath -MarkerPaths @($launchRequestPath, $restartReadyPath, $cancellationPath)
        Close-UpdateNotices -State $state -RainmeterPath $rainmeterPath
        Invoke-RainmeterBang -RainmeterPath $rainmeterPath -Arguments @('!DeactivateConfig', ([string]$state.RootConfig + '\Utilities\MousePluginUpdate'))
        Write-MouseUpdateTrace -Stage 'COMPLETE' -Message 'Mouse.dll finalization retry completed without replacing the verified plugin.'
        return
    }
    if (-not [string]::Equals($retryMode, 'Install', [System.StringComparison]::Ordinal)) {
        throw "Pending state contains an invalid Mouse.dll retry mode: $retryMode"
    }
    $payloadPath = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot ([string]$state.PayloadRelativePath)) -Root $resolvedRoot -Context 'Mouse payload'
    $payloadRoot = Assert-PathWithinRoot -Path (Join-Path $resolvedRoot '@Resources\UpdaterPayload\Mouse') -Root $resolvedRoot -Context 'Mouse payload root'
    $backupPath = $pluginTarget + '.dmeloper-v3201-' + $Token + '.bak'
    $newPath = $pluginTarget + '.dmeloper-v3201-' + $Token + '.new'

    $running = Get-ExactRainmeterProcess -Path $rainmeterPath -ProcessId ([int]$state.RainmeterProcessId) -StartTimeUtcTicks ([int64]$state.RainmeterStartTimeUtcTicks)
    if ($null -eq $running) { throw 'The Rainmeter process identity changed before Mouse.dll replacement.' }
    Write-MouseUpdateTrace -Stage 'PROCESS_VERIFIED' -Message ("rainmeterPid={0}; path={1}" -f $running.Id, $rainmeterPath)
    Wait-BootstrapInactive -SettingsPath ([System.IO.Path]::GetFullPath([string]$state.SettingsPath)) -RootConfig ([string]$state.RootConfig) -RainmeterProcess $running
    $state.Phase = 'Stopping'
    Set-PendingStateProperty -State $state -Name 'BackupPath' -Value $backupPath
    Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'Stopping'
    Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Write-PendingState -Path $pendingPath -State $state
    Write-MouseUpdateTrace -Stage 'PHASE_STOPPING' -Message ("backup={0}" -f $backupPath)
    Write-MouseUpdateTrace -Stage 'QUIT_REQUESTED' -Message ("rainmeterPid={0}; path={1}" -f $running.Id, $rainmeterPath)
    Invoke-RainmeterBang -RainmeterPath $rainmeterPath -Arguments @('!Quit')
    Write-MouseUpdateTrace -Stage 'QUIT_SENT' -Message ("rainmeterPid={0}" -f $running.Id)
    Wait-RainmeterExit -Process $running
    $rainmeterStoppedBySession = $true
    Write-MouseUpdateTrace -Stage 'RAINMETER_EXITED' -Message ("rainmeterPid={0}" -f $running.Id)
    Write-RestartReadyState -Path $restartReadyPath -Ready 0
    Write-MouseUpdateTrace -Stage 'RESTART_HANDOFF_INITIALIZED' -Message ("path={0}; ready=0" -f $restartReadyPath)

    $pluginDirectory = Split-Path -Parent $pluginTarget
    if (-not (Test-Path -LiteralPath $pluginDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    }
    Write-MouseUpdateTrace -Stage 'PAYLOAD_STAGE_BEGIN' -Message ("source={0}; destination={1}" -f $payloadPath, $newPath)
    Copy-Item -LiteralPath $payloadPath -Destination $newPath -Force
    Write-MouseUpdateTrace -Stage 'PAYLOAD_STAGED' -Message ("path={0}" -f $newPath)
    if (-not [string]::Equals((Get-Sha256Hex -Path $newPath), $expectedHash, [System.StringComparison]::Ordinal)) {
        throw 'Staged Mouse.dll SHA-256 verification failed.'
    }
    $pluginMutationStarted = $true
    if ([bool]$state.OriginalExists) {
        Write-MouseUpdateTrace -Stage 'ORIGINAL_BACKUP_BEGIN' -Message ("source={0}; destination={1}" -f $pluginTarget, $backupPath)
        Move-Item -LiteralPath $pluginTarget -Destination $backupPath -Force
        Write-MouseUpdateTrace -Stage 'ORIGINAL_BACKED_UP' -Message ("path={0}" -f $backupPath)
    }
    try {
        Write-MouseUpdateTrace -Stage 'PLUGIN_COMMIT_BEGIN' -Message ("source={0}; destination={1}" -f $newPath, $pluginTarget)
        Move-Item -LiteralPath $newPath -Destination $pluginTarget -Force
        if (-not [string]::Equals((Get-Sha256Hex -Path $pluginTarget), $expectedHash, [System.StringComparison]::Ordinal)) {
            throw 'Installed Mouse.dll SHA-256 verification failed.'
        }
        Write-MouseUpdateTrace -Stage 'PLUGIN_VERIFIED' -Message ("path={0}; sha256={1}" -f $pluginTarget, $expectedHash)
    }
    catch {
        if (Test-Path -LiteralPath $newPath -PathType Leaf) { Remove-Item -LiteralPath $newPath -Force }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) { Move-Item -LiteralPath $backupPath -Destination $pluginTarget -Force }
        throw
    }
    $state.Phase = 'Restarting'
    Set-PendingStateProperty -State $state -Name 'ReplacedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'Restarting'
    Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Write-PendingState -Path $pendingPath -State $state
    Write-MouseUpdateTrace -Stage 'PHASE_RESTARTING' -Message 'Plugin replacement committed; starting exact Rainmeter executable.'
    Write-MouseUpdateTrace -Stage 'RAINMETER_START_REQUESTED' -Message ("path={0}" -f $rainmeterPath)
    $restarted = Start-ExactRainmeter -Path $rainmeterPath
    Set-PendingStateProperty -State $state -Name 'RainmeterProcessId' -Value ([int]$restarted.Id)
    Set-PendingStateProperty -State $state -Name 'RainmeterStartTimeUtcTicks' -Value ([int64]$restarted.StartTime.ToUniversalTime().Ticks)
    Write-PendingState -Path $pendingPath -State $state
    Write-MouseUpdateTrace -Stage 'RAINMETER_RESTARTED' -Message ("rainmeterPid={0}; path={1}" -f $restarted.Id, $rainmeterPath)
    Wait-RestartReady -Path $restartReadyPath -RainmeterProcess $restarted

    if (-not (Test-Path -LiteralPath $pluginTarget -PathType Leaf) -or
        -not [string]::Equals((Get-Sha256Hex -Path $pluginTarget), $expectedHash, [System.StringComparison]::Ordinal)) {
        throw 'Restarted Rainmeter did not retain the expected Mouse.dll.'
    }
    Write-MouseUpdateTrace -Stage 'RESTART_VERIFIED' -Message ("path={0}; sha256={1}" -f $pluginTarget, $expectedHash)
    $previousRootRecovered = $state.PSObject.Properties.Name -contains 'PreviousRootRecovered' -and [bool]$state.PreviousRootRecovered
    if ($previousRootRecovered) {
        Write-MouseUpdateTrace -Stage 'TARGET_ROOT_REACTIVATION_BEGIN' -Message ("previousRoot={0}; targetRoot={1}" -f [string]$state.PreviousRoot, $resolvedRoot)
        Invoke-TargetRootActivation -State $state
        Set-PendingStateProperty -State $state -Name 'PreviousRootRecovered' -Value $false
        Write-MouseUpdateTrace -Stage 'TARGET_ROOT_REACTIVATED' -Message ("targetRoot={0}" -f $resolvedRoot)
    }
    $state.Phase = 'Finalizing'
    Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'Finalizing'
    Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Write-PendingState -Path $pendingPath -State $state
    Write-MouseUpdateTrace -Stage 'ADAPTER_CLEANUP_BEGIN' -Message 'Running legacy activation cleanup in the token-owned session process.'
    Invoke-AdapterCleanup -State $state
    Write-MouseUpdateTrace -Stage 'ADAPTER_CLEANUP_COMPLETE' -Message 'Legacy activation handoff cleanup completed.'
    $activationCommitted = $true
    Remove-UpdateArtifacts -PendingPath $pendingPath -PayloadRoot $payloadRoot -BackupPath $backupPath -MarkerPaths @($launchRequestPath, $restartReadyPath, $cancellationPath)
    Write-MouseUpdateTrace -Stage 'ARTIFACTS_REMOVED' -Message 'Pending state, native handoff markers, payload, and transactional backup were removed.'
    Close-UpdateNotices -State $state -RainmeterPath $rainmeterPath
    Invoke-RainmeterBang -RainmeterPath $rainmeterPath -Arguments @('!DeactivateConfig', ([string]$state.RootConfig + '\Utilities\MousePluginUpdate'))
    Write-MouseUpdateTrace -Stage 'COMPLETE' -Message 'Mouse.dll 3.2.0.1 verified; Rainmeter restarted and transactional artifacts removed.'
}
catch {
    $message = $_.Exception.Message
    Write-MouseUpdateTrace -Stage 'FAILED' -Message $message -Level 'ERROR'
    if ($activationCommitted) {
        try {
            if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
                $state = Read-PendingState -Path $pendingPath
                $state.Phase = 'Finalizing'
                Set-PendingStateProperty -State $state -Name 'Failure' -Value $message
                Set-PendingStateProperty -State $state -Name 'FailedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
                Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'FinalizationRetryRequired'
                Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
                Set-PendingStateProperty -State $state -Name 'SessionProcessId' -Value 0
                Set-PendingStateProperty -State $state -Name 'SessionStartTimeUtcTicks' -Value ([int64]0)
                Set-PendingStateProperty -State $state -Name 'SessionExecutablePath' -Value ''
                Write-PendingState -Path $pendingPath -State $state
                $failedPath = Join-Path (Split-Path -Parent $pendingPath) ('MousePluginUpdateFailed_' + $Token + '.json')
                Copy-Item -LiteralPath $pendingPath -Destination $failedPath -Force
                $running = Get-ExactRainmeterProcess -Path ([System.IO.Path]::GetFullPath([string]$state.RainmeterPath))
                if ($null -ne $running) { Show-RetrySurface -State $state -RainmeterPath ([string]$state.RainmeterPath) }
            }
        }
        catch {
            Write-MouseUpdateTrace -Stage 'FINALIZATION_RETRY_STATE_FAILED' -Message $_.Exception.Message -Level 'ERROR'
        }
        Write-MouseUpdateTrace -Stage 'FINALIZATION_RETRY_REQUIRED' -Message 'Activation handoff was already committed; a manual finalization retry will not replace the verified plugin.' -Level 'WARN'
        exit 1
    }
    try {
        if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
            $state = Read-PendingState -Path $pendingPath
        }
        elseif ($null -eq $state) {
            throw 'Mouse plugin pending state disappeared before rollback context was captured.'
        }
        else {
            Write-MouseUpdateTrace -Stage 'ROLLBACK_USING_MEMORY_STATE' -Message 'Pending state disappeared; rollback is using the last validated in-memory state.' -Level 'WARN'
        }
        $rainmeterPath = [System.IO.Path]::GetFullPath([string]$state.RainmeterPath)
        $pluginTarget = [System.IO.Path]::GetFullPath([string]$state.PluginTargetPath)
        $backupPath = $pluginTarget + '.dmeloper-v3201-' + $Token + '.bak'
        $running = Get-ExactRainmeterProcess -Path $rainmeterPath
        if ($pluginMutationStarted) {
            if ($null -ne $running) {
                $rollbackRainmeterPid = $running.Id
                Invoke-RainmeterBang -RainmeterPath $rainmeterPath -Arguments @('!Quit')
                Wait-RainmeterExit -Process $running
                $running = $null
                Write-MouseUpdateTrace -Stage 'ROLLBACK_RAINMETER_STOPPED' -Message ("rainmeterPid={0}" -f $rollbackRainmeterPid) -Level 'WARN'
            }
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                Move-Item -LiteralPath $backupPath -Destination $pluginTarget -Force
                Write-MouseUpdateTrace -Stage 'ROLLBACK_PLUGIN_RESTORED' -Message ("path={0}" -f $pluginTarget) -Level 'WARN'
            }
            elseif (-not [bool]$state.OriginalExists -and (Test-Path -LiteralPath $pluginTarget -PathType Leaf)) {
                Remove-Item -LiteralPath $pluginTarget -Force
                Write-MouseUpdateTrace -Stage 'ROLLBACK_PLUGIN_REMOVED' -Message ("path={0}" -f $pluginTarget) -Level 'WARN'
            }
        }
        else {
            Write-MouseUpdateTrace -Stage 'ROLLBACK_NO_PLUGIN_MUTATION' -Message 'Failure occurred before Mouse.dll mutation; the installed plugin was left untouched.' -Level 'WARN'
        }
        if (($rainmeterStoppedBySession -or $pluginMutationStarted) -and $null -eq $running) {
            $running = Start-ExactRainmeter -Path $rainmeterPath
            Write-MouseUpdateTrace -Stage 'ROLLBACK_RAINMETER_RESTARTED' -Message ("rainmeterPid={0}; path={1}" -f $running.Id, $rainmeterPath) -Level 'WARN'
        }
        elseif ($null -ne $running) {
            Write-MouseUpdateTrace -Stage 'ROLLBACK_RAINMETER_LEFT_RUNNING' -Message ("rainmeterPid={0}; no updater-owned restart was required" -f $running.Id) -Level 'WARN'
        }
        $previousRootRecovered = Invoke-PreviousRootRecovery -State $state
        Write-MouseUpdateTrace -Stage 'ROLLBACK_PREVIOUS_ROOT_REQUESTED' -Message ("previousRoot={0}; recovered={1}" -f [string]$state.PreviousRoot, [int][bool]$previousRootRecovered) -Level 'WARN'
        $failedPath = Join-Path (Split-Path -Parent $pendingPath) ('MousePluginUpdateFailed_' + $Token + '.json')
        $state.Phase = 'Failed'
        Set-PendingStateProperty -State $state -Name 'Failure' -Value $message
        Set-PendingStateProperty -State $state -Name 'FailedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
        Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'Failed'
        Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
        Set-PendingStateProperty -State $state -Name 'PreviousRootRecovered' -Value ([bool]$previousRootRecovered)
        Set-PendingStateProperty -State $state -Name 'SessionProcessId' -Value 0
        Set-PendingStateProperty -State $state -Name 'SessionStartTimeUtcTicks' -Value ([int64]0)
        Set-PendingStateProperty -State $state -Name 'SessionExecutablePath' -Value ''
        if ($null -ne $running) {
            Set-PendingStateProperty -State $state -Name 'RainmeterProcessId' -Value ([int]$running.Id)
            Set-PendingStateProperty -State $state -Name 'RainmeterStartTimeUtcTicks' -Value ([int64]$running.StartTime.ToUniversalTime().Ticks)
        }
        $failedStateRoot = Split-Path -Parent $failedPath
        if (Test-Path -LiteralPath $failedStateRoot -PathType Container) {
            if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
                Write-PendingState -Path $pendingPath -State $state
                Copy-Item -LiteralPath $pendingPath -Destination $failedPath -Force
            }
            else {
                Write-PendingState -Path $failedPath -State $state
            }
            Write-MouseUpdateTrace -Stage 'FAILED_STATE_RETAINED' -Message ("path={0}" -f $failedPath) -Level 'WARN'
        }
        else {
            Write-MouseUpdateTrace -Stage 'FAILED_STATE_ROOT_MISSING' -Message ("path={0}" -f $failedStateRoot) -Level 'ERROR'
        }
        foreach ($markerPath in @($restartReadyPath, $cancellationPath)) {
            if (Test-Path -LiteralPath $markerPath -PathType Leaf) { Remove-Item -LiteralPath $markerPath -Force }
        }
        $running = Get-ExactRainmeterProcess -Path $rainmeterPath
        if ($null -ne $running) {
            Show-RetrySurface -State $state -RainmeterPath $rainmeterPath
        }
    }
    catch {
        Write-MouseUpdateTrace -Stage 'ROLLBACK_FAILED' -Message $_.Exception.Message -Level 'ERROR'
    }
    exit 1
}
finally {
    Exit-VersionManagerOperationMutex -Lock $versionOperationLock
}
