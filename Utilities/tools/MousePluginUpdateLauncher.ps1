[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SkinRoot,
    [switch]$InspectExisting,
    [ValidatePattern('^[a-f0-9]{32}$')][string]$RetryToken = '',
    [ValidatePattern('^[a-f0-9]{32}$')][string]$RetryAttemptId = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

function Quote-WindowsArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Resolve-ChildPowerShell {
    $preferred = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $preferred -PathType Leaf) { return $preferred }
    $command = Get-Command 'powershell.exe' -CommandType Application -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$command.Source) -or
        -not [string]::Equals([System.IO.Path]::GetFileName([string]$command.Source), 'powershell.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'A validated Windows PowerShell executable was not found.'
    }
    return [string]$command.Source
}

function Read-PendingState {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([System.IO.File]::ReadAllText($Path, $utf8NoBom) | ConvertFrom-Json)
}

function Write-PendingState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$State
    )
    $temporaryPath = $Path + '.' + $PID + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, ($State | ConvertTo-Json -Depth 6), $utf8NoBom)
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

function Get-PowerShellProcessIdentity {
    param([int]$ProcessId = $PID)
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    return [PSCustomObject]@{
        ProcessId = [int]$process.Id
        StartTimeUtcTicks = [int64]$process.StartTime.ToUniversalTime().Ticks
        ExecutablePath = [System.IO.Path]::GetFullPath([string]$process.Path)
    }
}

function Get-ExactOwnedSession {
    param([Parameter(Mandatory = $true)][object]$State)
    $sessionProcessId = if ($State.PSObject.Properties.Name -contains 'SessionProcessId') { [int]$State.SessionProcessId } else { 0 }
    $sessionStartTicks = if ($State.PSObject.Properties.Name -contains 'SessionStartTimeUtcTicks') { [int64]$State.SessionStartTimeUtcTicks } else { 0 }
    $sessionPath = if ($State.PSObject.Properties.Name -contains 'SessionExecutablePath') { [string]$State.SessionExecutablePath } else { '' }
    if ($sessionProcessId -le 0 -or $sessionStartTicks -le 0 -or [string]::IsNullOrWhiteSpace($sessionPath)) { return $null }
    try {
        $identity = Get-PowerShellProcessIdentity -ProcessId $sessionProcessId
        if ($identity.StartTimeUtcTicks -ne $sessionStartTicks -or
            -not [string]::Equals($identity.ExecutablePath, [System.IO.Path]::GetFullPath($sessionPath), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
        return $identity
    }
    catch { return $null }
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

function Get-RetryMode {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $expectedHash = ([string]$State.ExpectedSha256).ToUpperInvariant()
    if ($expectedHash -notmatch '^[0-9A-F]{64}$') {
        throw 'Mouse plugin retry state contains an invalid expected hash.'
    }
    $phase = [string]$State.Phase
    if ($phase -in @('LaunchFailed', 'Failed')) {
        $payloadPath = Assert-PathWithinRoot -Path (Join-Path $Root ([string]$State.PayloadRelativePath)) -Root $Root -Context 'Mouse retry payload'
        if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
            throw 'The retained Mouse.dll retry payload is missing.'
        }
        $actualHash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if (-not [string]::Equals($actualHash, $expectedHash, [System.StringComparison]::Ordinal)) {
            throw 'The retained Mouse.dll retry payload failed SHA-256 verification.'
        }
        return 'Install'
    }
    if ($phase -eq 'Finalizing') {
        $pluginPath = [System.IO.Path]::GetFullPath([string]$State.PluginTargetPath)
        if (-not [string]::Equals([System.IO.Path]::GetFileName($pluginPath), 'Mouse.dll', [System.StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals((Split-Path -Leaf (Split-Path -Parent $pluginPath)), 'Plugins', [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
            throw 'The verified Mouse.dll target required for finalization retry is missing.'
        }
        $actualHash = (Get-FileHash -LiteralPath $pluginPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if (-not [string]::Equals($actualHash, $expectedHash, [System.StringComparison]::Ordinal)) {
            throw 'The installed Mouse.dll no longer matches the verified finalization state.'
        }
        return 'Finalize'
    }
    throw "Mouse plugin state phase is not manually retryable: $phase"
}

function ConvertTo-ResultValue {
    param([AllowNull()][object]$Value)
    return ([string]$Value -replace '[\r\n\0]+', ' ').Trim()
}

function Write-ResultPairs {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$SessionProcessId = 0,
        [string]$AttemptId = ''
    )

    Write-Output ('DMEL_STATUS=' + (ConvertTo-ResultValue $Status))
    Write-Output ('DMEL_CODE=' + (ConvertTo-ResultValue $Code))
    Write-Output ('DMEL_MESSAGE=' + (ConvertTo-ResultValue $Message))
    Write-Output ('DMEL_LOGPATH=' + (ConvertTo-ResultValue $script:CanonicalLogPath))
    Write-Output ('DMEL_TRACELOG=' + (ConvertTo-ResultValue $script:TokenLogPath))
    Write-Output ('DMEL_TOKEN=' + (ConvertTo-ResultValue $script:TraceToken))
    Write-Output ('DMEL_SESSIONPID=' + [string]$SessionProcessId)
    Write-Output ('DMEL_ATTEMPTID=' + (ConvertTo-ResultValue $AttemptId))
}

function Write-Trace {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] [LAUNCHER] [token={2}] [pid={3}] {4}: {5}' -f `
        [DateTime]::UtcNow.ToString('o'), $Level, $script:TraceToken, $PID, $Stage, (ConvertTo-ResultValue $Message)
    foreach ($entry in @(
        [PSCustomObject]@{ Path = $script:TokenLogPath; Text = $line + [Environment]::NewLine },
        [PSCustomObject]@{ Path = $script:CanonicalLogPath; Text = '<MousePluginUpdate>' + [Environment]::NewLine + $line + [Environment]::NewLine + [Environment]::NewLine }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Path)) { continue }
        try {
            $parent = Split-Path -Parent ([string]$entry.Path)
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                [void][System.IO.Directory]::CreateDirectory($parent)
            }
            [System.IO.File]::AppendAllText([string]$entry.Path, [string]$entry.Text, $utf8NoBom)
        }
        catch {
            # Result pairs remain available to Rainmeter even when the log destination is not writable.
        }
    }
}

$script:ResolvedRoot = ''
$script:CanonicalLogPath = ''
$script:TokenLogPath = ''
$script:TraceToken = 'unknown'
$script:FailureCode = 'LAUNCH_FAILED'
$launchMutex = $null
$launchMutexHeld = $false
$launchClaimed = $false
$launchAttemptId = ''
$retryRequested = -not [string]::IsNullOrWhiteSpace($RetryToken) -or -not [string]::IsNullOrWhiteSpace($RetryAttemptId)
$retryMode = 'Install'
$retryOfLaunchAttemptId = ''
$retryableFailureRetained = $false

try {
    if ($InspectExisting -and $retryRequested) {
        $script:FailureCode = 'RETRY_REJECTED'
        throw 'InspectExisting cannot be combined with a manual retry request.'
    }
    if ($retryRequested -and ([string]::IsNullOrWhiteSpace($RetryToken) -or [string]::IsNullOrWhiteSpace($RetryAttemptId))) {
        $script:FailureCode = 'RETRY_REJECTED'
        throw 'Manual Mouse.dll retry requires both the exact token and failed attempt id.'
    }
    $script:ResolvedRoot = [System.IO.Path]::GetFullPath($SkinRoot).TrimEnd('\', '/')
    $script:CanonicalLogPath = Join-Path (Join-Path $script:ResolvedRoot 'Logs') "DMeloper's Block HUD Log.log"
    $pendingPath = Join-Path $script:ResolvedRoot '@Resources\Customs\Data\MousePluginUpdatePending.json'
    if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
        Write-Trace -Stage 'NO_PENDING' -Message 'The pending state disappeared before launcher execution.' -Level 'WARN'
        Write-ResultPairs -Status 'OK' -Code 'NO_PENDING' -Message 'Mouse plugin update is no longer pending.'
        exit 0
    }

    $state = Read-PendingState -Path $pendingPath
    $token = [string]$state.Token
    if ([int]$state.SchemaVersion -ne 1 -or $token -notmatch '^[a-f0-9]{32}$') {
        throw 'Mouse plugin pending state identity is invalid.'
    }
    $script:TraceToken = $token
    $script:TokenLogPath = Join-Path (Join-Path $script:ResolvedRoot '@Resources\Customs\Logs') ('MousePluginUpdate_{0}.log' -f $token)
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string]$state.TargetRoot).TrimEnd('\', '/'), $script:ResolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Mouse plugin pending state targets a different skin root.'
    }

    $sessionPath = Join-Path $PSScriptRoot 'MousePluginUpdateSession.ps1'
    if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        throw "Mouse plugin update session helper is missing: $sessionPath"
    }
    $launcherIdentity = Get-PowerShellProcessIdentity
    Write-Trace -Stage 'LAUNCH_BEGIN' -Message ("phase={0}; launcherStartTicks={1}; executable={2}; root={3}" -f [string]$state.Phase, $launcherIdentity.StartTimeUtcTicks, $launcherIdentity.ExecutablePath, $script:ResolvedRoot)

    $launchMutex = New-Object System.Threading.Mutex($false, ('Local\DMeloper.BlockHUD.MousePluginUpdate.' + $token))
    try {
        $launchMutexHeld = $launchMutex.WaitOne(15000)
    }
    catch [System.Threading.AbandonedMutexException] {
        $launchMutexHeld = $true
        Write-Trace -Stage 'ABANDONED_LAUNCH_MUTEX_RECOVERED' -Message 'The previous launcher ended while holding the token mutex.' -Level 'WARN'
    }
    if (-not $launchMutexHeld) {
        $script:FailureCode = 'LAUNCH_BUSY'
        throw 'Another Mouse.dll update launcher still owns this token.'
    }

    $state = Read-PendingState -Path $pendingPath
    if (-not [string]::Equals([string]$state.Token, $token, [System.StringComparison]::Ordinal)) {
        throw 'Mouse plugin pending state changed while acquiring launch ownership.'
    }
    if (-not [string]::Equals([string]$state.Phase, 'Pending', [System.StringComparison]::Ordinal)) {
        $ownedSession = Get-ExactOwnedSession -State $state
        if ($null -ne $ownedSession) {
            Write-Trace -Stage 'DUPLICATE_SESSION_ACTIVE' -Message ("phase={0}; sessionPid={1}; sessionStartTicks={2}" -f [string]$state.Phase, $ownedSession.ProcessId, $ownedSession.StartTimeUtcTicks) -Level 'WARN'
            Write-ResultPairs -Status 'OK' -Code 'SESSION_ACTIVE' -Message 'The token-owned Mouse plugin update session is already active.' -SessionProcessId $ownedSession.ProcessId -AttemptId ([string]$state.LaunchAttemptId)
            exit 0
        }
        $failedAttemptId = if ($state.PSObject.Properties.Name -contains 'LaunchAttemptId') { [string]$state.LaunchAttemptId } else { '' }
        if ($failedAttemptId -notmatch '^[a-f0-9]{32}$') {
            $script:FailureCode = 'RETRY_REJECTED'
            throw 'Mouse plugin failure state does not contain an exact launch attempt id.'
        }
        if ($InspectExisting) {
            $retryMode = Get-RetryMode -State $state -Root $script:ResolvedRoot
            Write-Trace -Stage 'RETRY_AVAILABLE' -Message ("phase={0}; attempt={1}; mode={2}" -f [string]$state.Phase, $failedAttemptId, $retryMode) -Level 'WARN'
            Write-ResultPairs -Status 'OK' -Code 'RETRY_AVAILABLE' -Message 'The failed Mouse.dll update can be retried manually.' -AttemptId $failedAttemptId
            exit 0
        }
        if ($retryRequested) {
            $script:FailureCode = 'RETRY_REJECTED'
            if (-not [string]::Equals($RetryToken, $token, [System.StringComparison]::Ordinal) -or
                -not [string]::Equals($RetryAttemptId, $failedAttemptId, [System.StringComparison]::Ordinal)) {
                throw 'Manual Mouse.dll retry identity no longer matches the retained failure state.'
            }
            $retryMode = Get-RetryMode -State $state -Root $script:ResolvedRoot
            $retryOfLaunchAttemptId = $failedAttemptId
            Write-Trace -Stage 'MANUAL_RETRY_ACCEPTED' -Message ("phase={0}; failedAttempt={1}; mode={2}" -f [string]$state.Phase, $failedAttemptId, $retryMode) -Level 'WARN'
        }
        else {
            $script:FailureCode = 'AUTO_RETRY_BLOCKED'
            Write-Trace -Stage 'AUTO_RETRY_BLOCKED' -Message ("phase={0}; no live token-owned session was found" -f [string]$state.Phase) -Level 'ERROR'
            throw 'The previous Mouse.dll update attempt was interrupted. Automatic retry was blocked; inspect the retained token log.'
        }
    }
    elseif ($InspectExisting -or $retryRequested) {
        $script:FailureCode = 'RETRY_REJECTED'
        throw 'Mouse plugin update is still pending its first launcher attempt.'
    }

    $launchAttemptId = [Guid]::NewGuid().ToString('N')
    $state.Phase = 'Launching'
    Set-PendingStateProperty -State $state -Name 'LaunchAttemptId' -Value $launchAttemptId
    Set-PendingStateProperty -State $state -Name 'RetryMode' -Value $retryMode
    Set-PendingStateProperty -State $state -Name 'RetryOfLaunchAttemptId' -Value $retryOfLaunchAttemptId
    Set-PendingStateProperty -State $state -Name 'LauncherProcessId' -Value $launcherIdentity.ProcessId
    Set-PendingStateProperty -State $state -Name 'LauncherStartTimeUtcTicks' -Value $launcherIdentity.StartTimeUtcTicks
    Set-PendingStateProperty -State $state -Name 'LauncherExecutablePath' -Value $launcherIdentity.ExecutablePath
    Set-PendingStateProperty -State $state -Name 'LaunchRequestedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-PendingStateProperty -State $state -Name 'LastStage' -Value 'Launching'
    Set-PendingStateProperty -State $state -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Write-PendingState -Path $pendingPath -State $state
    $launchClaimed = $true
    Write-Trace -Stage 'LAUNCH_CLAIMED' -Message ("attempt={0}; launcherStartTicks={1}" -f $launchAttemptId, $launcherIdentity.StartTimeUtcTicks)

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $sessionPath,
        '-SkinRoot', $script:ResolvedRoot,
        '-Token', $token,
        '-LaunchAttemptId', $launchAttemptId,
        '-LauncherProcessId', [string]$launcherIdentity.ProcessId,
        '-LauncherStartTimeUtcTicks', [string]$launcherIdentity.StartTimeUtcTicks
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Resolve-ChildPowerShell
    $startInfo.Arguments = (($arguments | ForEach-Object { Quote-WindowsArgument -Value ([string]$_) }) -join ' ')
    $startInfo.WorkingDirectory = $script:ResolvedRoot
    $startInfo.UseShellExecute = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    Write-Trace -Stage 'SESSION_START_REQUESTED' -Message ("attempt={0}; helper={1}; executable={2}" -f $launchAttemptId, $sessionPath, $startInfo.FileName)
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        throw 'Mouse plugin update session could not be started.'
    }
    $processStartTicks = [int64]$process.StartTime.ToUniversalTime().Ticks
    Write-Trace -Stage 'SESSION_PROCESS_CREATED' -Message ("attempt={0}; sessionPid={1}; processStartTicks={2}" -f $launchAttemptId, $process.Id, $processStartTicks)
    $ownershipDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ($true) {
        $process.Refresh()
        if ($process.HasExited) {
            $script:FailureCode = 'SESSION_EXITED_BEFORE_OWNERSHIP'
            Write-Trace -Stage 'SESSION_EXITED_BEFORE_OWNERSHIP' -Message ("attempt={0}; sessionPid={1}; exitCode={2}" -f $launchAttemptId, $process.Id, $process.ExitCode) -Level 'ERROR'
            throw 'The Mouse.dll update session exited before publishing token ownership.'
        }
        $published = Read-PendingState -Path $pendingPath
        $publishedAttempt = if ($published.PSObject.Properties.Name -contains 'LaunchAttemptId') { [string]$published.LaunchAttemptId } else { '' }
        $publishedPid = if ($published.PSObject.Properties.Name -contains 'SessionProcessId') { [int]$published.SessionProcessId } else { 0 }
        $publishedTicks = if ($published.PSObject.Properties.Name -contains 'SessionStartTimeUtcTicks') { [int64]$published.SessionStartTimeUtcTicks } else { 0 }
        if ([string]::Equals($publishedAttempt, $launchAttemptId, [System.StringComparison]::Ordinal) -and
            $publishedPid -eq $process.Id -and $publishedTicks -eq $processStartTicks -and
            [string]$published.Phase -in @('Running', 'Stopping', 'Restarting', 'Finalizing')) {
            break
        }
        if ([DateTime]::UtcNow -ge $ownershipDeadline) {
            $script:FailureCode = 'SESSION_OWNERSHIP_TIMEOUT'
            Write-Trace -Stage 'SESSION_OWNERSHIP_TIMEOUT' -Message ("attempt={0}; sessionPid={1}; timeoutSeconds=20" -f $launchAttemptId, $process.Id) -Level 'ERROR'
            throw 'The Mouse.dll update session did not publish token ownership within 20 seconds.'
        }
        Start-Sleep -Milliseconds 50
    }
    Write-Trace -Stage 'SESSION_OWNERSHIP_CONFIRMED' -Message ("attempt={0}; sessionPid={1}; sessionStartTicks={2}" -f $launchAttemptId, $process.Id, $processStartTicks)
    Write-ResultPairs -Status 'OK' -Code 'SESSION_STARTED' -Message 'Mouse plugin update session published ownership.' -SessionProcessId $process.Id -AttemptId $launchAttemptId
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ($launchClaimed -and -not [string]::IsNullOrWhiteSpace($script:ResolvedRoot)) {
        try {
            $pendingPath = Join-Path $script:ResolvedRoot '@Resources\Customs\Data\MousePluginUpdatePending.json'
            if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
                $failedState = Read-PendingState -Path $pendingPath
                if ([string]::Equals([string]$failedState.Phase, 'Launching', [System.StringComparison]::Ordinal) -and
                    [string]::Equals([string]$failedState.LaunchAttemptId, $launchAttemptId, [System.StringComparison]::Ordinal)) {
                    $failedState.Phase = 'LaunchFailed'
                    Set-PendingStateProperty -State $failedState -Name 'Failure' -Value $message
                    Set-PendingStateProperty -State $failedState -Name 'FailedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
                    Set-PendingStateProperty -State $failedState -Name 'LastStage' -Value 'LaunchFailed'
                    Set-PendingStateProperty -State $failedState -Name 'LastUpdatedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
                    Set-PendingStateProperty -State $failedState -Name 'SessionProcessId' -Value 0
                    Set-PendingStateProperty -State $failedState -Name 'SessionStartTimeUtcTicks' -Value ([int64]0)
                    Set-PendingStateProperty -State $failedState -Name 'SessionExecutablePath' -Value ''
                    Write-PendingState -Path $pendingPath -State $failedState
                    $failedPath = Join-Path (Split-Path -Parent $pendingPath) ('MousePluginUpdateFailed_' + $script:TraceToken + '.json')
                    Copy-Item -LiteralPath $pendingPath -Destination $failedPath -Force
                    $retryableFailureRetained = $true
                    Write-Trace -Stage 'FAILED_STATE_RETAINED' -Message ("path={0}" -f $failedPath) -Level 'WARN'
                }
            }
        }
        catch {
            Write-Trace -Stage 'FAILED_STATE_WRITE_ERROR' -Message $_.Exception.Message -Level 'ERROR'
        }
    }
    Write-Trace -Stage 'LAUNCH_FAILED' -Message $message -Level 'ERROR'
    $resultAttemptId = if ($retryableFailureRetained) { $launchAttemptId } else { '' }
    Write-ResultPairs -Status 'ERROR' -Code $script:FailureCode -Message $message -AttemptId $resultAttemptId
    exit 1
}
finally {
    if ($launchMutexHeld -and $null -ne $launchMutex) {
        try { $launchMutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $launchMutex) { $launchMutex.Dispose() }
}
