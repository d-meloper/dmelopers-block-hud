[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [Parameter(Mandatory = $true)][string]$LaunchToken,
    [string]$DownloadedPackagePath = '',
    [string]$ExpectedVersion = '',
    [string]$ReleaseVariant = '',
    [string]$AssetName = '',
    [string]$ExpectedPackageSha256 = '',
    [long]$StartedAtUnixSeconds = 0,
    [ValidateSet('', 'continue', 'cancel')][string]$Decision = '',
    [switch]$ProbeState,
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $script:Utf8NoBom; $OutputEncoding = $script:Utf8NoBom } catch { }

. (Join-Path $PSScriptRoot 'LatestUpdate.Common.ps1')

$script:ResolvedRoot = ''
$script:StagingPath = ''
$script:Intent = $null
$script:ChildStarted = $false
$script:ChildOwnershipConfirmed = $false
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
    DMEL_PROBESTATUS = ''
}

function ConvertTo-LatestUpdateSingleLine {
    param([AllowNull()][string]$Value)
    return ([string]$Value).Replace("`r", ' ').Replace("`n", ' ').Trim()
}

function Set-LatestUpdateResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [AllowNull()][string]$Message = '',
        [AllowNull()][string]$SourcePath = '',
        [AllowNull()][string]$ProbeStatus = ''
    )
    $script:ResultPairs['DMEL_STATUS'] = $Status
    $script:ResultPairs['DMEL_SOURCEPATH'] = [string]$SourcePath
    $script:ResultPairs['DMEL_BACKUPPATH'] = ''
    $script:ResultPairs['DMEL_LOGPATH'] = if ([string]::IsNullOrWhiteSpace($script:ResolvedRoot)) { '' } else { Get-LatestUpdateLogPath -Root $script:ResolvedRoot }
    $script:ResultPairs['DMEL_MESSAGE'] = ConvertTo-LatestUpdateSingleLine -Value $Message
    $script:ResultPairs['DMEL_PROBESTATUS'] = ConvertTo-LatestUpdateSingleLine -Value $ProbeStatus
}

function Emit-LatestUpdateResult {
    if (-not $EmitResultPairs) { return }
    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        foreach ($key in @('DMEL_STATUS', 'DMEL_SOURCEPATH', 'DMEL_BACKUPPATH', 'DMEL_LOGPATH', 'DMEL_MESSAGE', 'DMEL_PROBESTATUS')) {
            $writer.WriteLine($key + '=' + (ConvertTo-LatestUpdateSingleLine -Value ([string]$script:ResultPairs[$key])))
        }
    }
    finally { $writer.Dispose() }
}

function Get-LatestUpdatePowerShellPath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [System.IO.Path]::GetFullPath($candidate) }
    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) { return [System.IO.Path]::GetFullPath($command.Source) }
    throw 'powershell.exe could not be located.'
}

function ConvertTo-LatestUpdateCommandLineArgument {
    param([AllowNull()][string]$Value)
    $text = [string]$Value
    if ($text.Length -eq 0) { return '""' }
    if ($text.IndexOfAny([char[]]@(' ', "`t", "`r", "`n", '"')) -lt 0) { return $text }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $text.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($slashes * 2) + 1))); [void]$builder.Append('"'); $slashes = 0; continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Start-LatestUpdateIndependentSession {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Token
    )
    $sessionPath = Join-Path $PSScriptRoot 'LatestUpdateSession.ps1'
    if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { throw "Latest update session helper was not found: $sessionPath" }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sessionPath, '-TargetRoot', $Root, '-LaunchToken', $Token)
    $quoted = @($arguments | ForEach-Object { ConvertTo-LatestUpdateCommandLineArgument -Value ([string]$_) })
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-LatestUpdatePowerShellPath
    $startInfo.Arguments = $quoted -join ' '
    $startInfo.UseShellExecute = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw 'Latest update session process could not be started.' }
    return $process
}

function Get-LatestUpdateChildOwnedState {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    try {
        $state = Read-LatestUpdateJson -Path (Get-LatestUpdateStatePath -Root $script:ResolvedRoot)
        if ($null -eq $state) { return $null }
        $token = [string](Get-LatestUpdateObjectProperty -Object $state -Name 'LaunchToken' -DefaultValue '')
        $status = [string](Get-LatestUpdateObjectProperty -Object $state -Name 'Status' -DefaultValue '')
        $sessionPid = [int](Get-LatestUpdateObjectProperty -Object $state -Name 'SessionPid' -DefaultValue 0)
        if ([string]::Equals($token, $LaunchToken, [System.StringComparison]::Ordinal) -and
            $sessionPid -eq [int]$Process.Id -and
            $status -in @('installing', 'warning', 'switching', 'success', 'canceled', 'error')) {
            return $state
        }
    }
    catch { }
    return $null
}

function Wait-LatestUpdateIndependentSessionOwnership {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    while ($true) {
        $Process.Refresh()
        if ($Process.HasExited) {
            $terminalState = Get-LatestUpdateChildOwnedState -Process $Process
            $terminalStatus = if ($null -eq $terminalState) { '' } else { [string]$terminalState.Status }
            if ($terminalStatus -in @('success', 'canceled', 'error')) { return $terminalState }
            throw ("Independent latest-update session exited before taking ownership of state. exitCode={0}" -f $Process.ExitCode)
        }
        $ownedState = Get-LatestUpdateChildOwnedState -Process $Process
        if ($null -ne $ownedState) { return $ownedState }
        # No deadline: cold PowerShell / AMSI startup is expected to remain visible.
        Start-Sleep -Milliseconds 100
    }
}

function Invoke-LatestUpdateDecisionWrite {
    $state = Read-LatestUpdateJson -Path (Get-LatestUpdateStatePath -Root $script:ResolvedRoot)
    if ($null -eq $state) { throw 'Latest update state was not found.' }
    $stateToken = [string](Get-LatestUpdateObjectProperty -Object $state -Name 'LaunchToken' -DefaultValue '')
    $stateStatus = [string](Get-LatestUpdateObjectProperty -Object $state -Name 'Status' -DefaultValue '')
    if (-not [string]::Equals($stateToken, $LaunchToken, [System.StringComparison]::Ordinal) -or $stateStatus -ne 'warning') {
        throw 'Latest update decision is stale or the update is not waiting for a decision.'
    }
    $sessionPid = [int](Get-LatestUpdateObjectProperty -Object $state -Name 'SessionPid' -DefaultValue 0)
    if (-not (Test-LatestUpdateProcessLive -ProcessId $sessionPid)) { throw 'Latest update session is no longer running.' }
    $payload = [ordered]@{
        SchemaVersion = 1
        LaunchToken = $LaunchToken
        Decision = $Decision.ToLowerInvariant()
        CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-LatestUpdateJson -Path (Get-LatestUpdateDecisionPath -Root $script:ResolvedRoot) -Value $payload
    Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage ('decision:' + $payload.Decision) -Message $LaunchToken
    Set-LatestUpdateResult -Status 'OK' -Message 'Latest update decision was recorded.'
}

function Get-LatestUpdateProbeSnapshot {
    $state = Read-LatestUpdateJson -Path (Get-LatestUpdateStatePath -Root $script:ResolvedRoot)
    if ($null -eq $state) {
        return [PSCustomObject]@{ Kind = 'stale'; Status = ''; SessionPid = 0; SessionStartedAtUtcTicks = 0L; Signature = 'missing' }
    }

    $stateSchema = [int](Get-LatestUpdateObjectProperty -Object $state -Name 'SchemaVersion' -DefaultValue 0)
    $stateToken = [string](Get-LatestUpdateObjectProperty -Object $state -Name 'LaunchToken' -DefaultValue '')
    $stateStatus = ([string](Get-LatestUpdateObjectProperty -Object $state -Name 'Status' -DefaultValue '')).ToLowerInvariant()
    $sessionPid = [int](Get-LatestUpdateObjectProperty -Object $state -Name 'SessionPid' -DefaultValue 0)
    $sessionStartedAtUtcTicks = [long](Get-LatestUpdateObjectProperty -Object $state -Name 'SessionStartedAtUtcTicks' -DefaultValue 0)
    $signature = '{0}|{1}|{2}|{3}|{4}' -f $stateSchema, $stateToken, $stateStatus, $sessionPid, $sessionStartedAtUtcTicks
    $kind = if ($stateSchema -ne 2 -or -not [string]::Equals($stateToken, $LaunchToken, [System.StringComparison]::Ordinal)) {
        'stale'
    }
    elseif ($stateStatus -in @('success', 'canceled', 'error')) {
        'terminal'
    }
    elseif ($stateStatus -in @('staging', 'installing', 'warning', 'switching')) {
        'candidate'
    }
    else {
        'stale'
    }

    return [PSCustomObject]@{
        Kind = $kind
        Status = $stateStatus
        SessionPid = $sessionPid
        SessionStartedAtUtcTicks = $sessionStartedAtUtcTicks
        Signature = $signature
    }
}

function Invoke-LatestUpdateStateProbe {
    . (Join-Path $PSScriptRoot 'VersionManager.OperationLock.ps1')
    $snapshot = Get-LatestUpdateProbeSnapshot
    $probeStatus = 'stale'
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if ($snapshot.Kind -eq 'terminal') {
            $probeStatus = 'terminal'
            break
        }
        if ($snapshot.Kind -eq 'candidate') {
            $sessionProcessLive = Test-LatestUpdateProcessIdentity -ProcessId $snapshot.SessionPid -StartedAtUtcTicks $snapshot.SessionStartedAtUtcTicks
            $operationProbe = Enter-VersionManagerOperationMutex -TargetRoot $script:ResolvedRoot
            try {
                $probeStatus = if ($snapshot.Status -eq 'staging' -and $sessionProcessLive) {
                    'active'
                }
                elseif ($sessionProcessLive -and -not [bool]$operationProbe.Acquired) {
                    'active'
                }
                elseif (-not [bool]$operationProbe.Acquired) {
                    'conflict'
                }
                else {
                    'stale'
                }
            }
            finally {
                Exit-VersionManagerOperationMutex -Lock $operationProbe
            }
        }
        else {
            $probeStatus = 'stale'
        }

        if ($probeStatus -eq 'active' -or $attempt -ge 2) {
            break
        }

        # State may become terminal or change owner while liveness and mutex
        # are inspected. Re-read once before returning stale/conflict.
        $refreshedSnapshot = Get-LatestUpdateProbeSnapshot
        if ($refreshedSnapshot.Kind -eq 'terminal') {
            $snapshot = $refreshedSnapshot
            $probeStatus = 'terminal'
            break
        }
        if (-not [string]::Equals($refreshedSnapshot.Signature, $snapshot.Signature, [System.StringComparison]::Ordinal)) {
            $snapshot = $refreshedSnapshot
            continue
        }
        break
    }
    Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage ('probe:' + $probeStatus) -Message ("token={0}; state={1}; pid={2}; startTicks={3}" -f $LaunchToken, $snapshot.Status, $snapshot.SessionPid, $snapshot.SessionStartedAtUtcTicks)
    Set-LatestUpdateResult -Status 'OK' -ProbeStatus $probeStatus
}

function Invoke-LatestUpdateLaunch {
    if ([string]::IsNullOrWhiteSpace($DownloadedPackagePath)) { throw 'DownloadedPackagePath is required.' }
    $existingState = Read-LatestUpdateJson -Path (Get-LatestUpdateStatePath -Root $script:ResolvedRoot)
    if ($null -ne $existingState) {
        $existingToken = [string](Get-LatestUpdateObjectProperty -Object $existingState -Name 'LaunchToken' -DefaultValue '')
        $existingStatus = [string](Get-LatestUpdateObjectProperty -Object $existingState -Name 'Status' -DefaultValue '')
        $existingPid = [int](Get-LatestUpdateObjectProperty -Object $existingState -Name 'SessionPid' -DefaultValue 0)
        $existingStartedAtUtcTicks = [long](Get-LatestUpdateObjectProperty -Object $existingState -Name 'SessionStartedAtUtcTicks' -DefaultValue 0)
        if ($existingStatus -in @('staging', 'installing', 'warning', 'switching') -and
            (Test-LatestUpdateProcessIdentity -ProcessId $existingPid -StartedAtUtcTicks $existingStartedAtUtcTicks)) {
            if ([string]::Equals($existingToken, $LaunchToken, [System.StringComparison]::Ordinal)) {
                $script:StagingPath = Get-LatestUpdateStagingPath -Root $script:ResolvedRoot -LaunchToken $LaunchToken
                Set-LatestUpdateResult -Status 'OK' -Message 'The same latest update session is already running.' -SourcePath $script:StagingPath
                return
            }
            throw 'Another latest update session is already running.'
        }
    }

    $script:Intent = New-LatestUpdateIntent -LaunchToken $LaunchToken -ExpectedVersion $ExpectedVersion -ReleaseVariant $ReleaseVariant -AssetName $AssetName -ExpectedPackageSha256 $ExpectedPackageSha256 -StartedAtUnixSeconds $StartedAtUnixSeconds
    Write-LatestUpdateJson -Path (Get-LatestUpdateIntentPath -Root $script:ResolvedRoot) -Value $script:Intent
    # No live operation remains at this boundary, so an unscoped decision JSON
    # can only belong to a completed older token and must not linger forever.
    Remove-LatestUpdateDecisionFile -Root $script:ResolvedRoot
    Remove-LatestUpdateNativeDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
    [void](Save-LatestUpdateState -Root $script:ResolvedRoot -Intent $script:Intent -Status 'staging' -SessionPid $PID -Message 'Preparing the downloaded update package.' -LogPath (Get-LatestUpdateLogPath -Root $script:ResolvedRoot))
    $script:StagingPath = Copy-LatestUpdatePackageToStaging -Root $script:ResolvedRoot -LaunchToken $LaunchToken -SourcePath $DownloadedPackagePath -ExpectedPackageSha256 $script:Intent.ExpectedPackageSha256
    Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage 'staged' -Message $script:StagingPath
    $process = Start-LatestUpdateIndependentSession -Root $script:ResolvedRoot -Token $LaunchToken
    try {
        $script:ChildStarted = $true
        # Republish staging with the detached child's exact identity before
        # waiting for its first script-owned state. Rainmeter may unload the
        # RunCommand parent while the child is still cold-starting in AMSI.
        [void](Save-LatestUpdateState -Root $script:ResolvedRoot -Intent $script:Intent -Status 'staging' -SessionPid $process.Id -Message 'Waiting for the independent update session to initialize.' -LogPath (Get-LatestUpdateLogPath -Root $script:ResolvedRoot))
        [void](Wait-LatestUpdateIndependentSessionOwnership -Process $process)
        $script:ChildOwnershipConfirmed = $true
        # The detached session is the sole state writer after ownership. The
        # launcher waits without a deadline so a cold AMSI scan cannot leave a
        # dead parent PID in permanent staging state.
        Set-LatestUpdateResult -Status 'OK' -Message 'Latest update session started.' -SourcePath $script:StagingPath
    }
    finally { $process.Dispose() }
}

try {
    $script:ResolvedRoot = Resolve-LatestUpdateTargetRoot -Path $TargetRoot
    [void](Assert-LatestUpdateToken -LaunchToken $LaunchToken)
    if ($ProbeState -and -not [string]::IsNullOrWhiteSpace($Decision)) {
        throw 'ProbeState and Decision cannot be used together.'
    }
    if ($ProbeState) { Invoke-LatestUpdateStateProbe }
    elseif (-not [string]::IsNullOrWhiteSpace($Decision)) { Invoke-LatestUpdateDecisionWrite }
    else { Invoke-LatestUpdateLaunch }
}
catch {
    $message = [string]$_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedRoot)) {
        Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage 'launcher-error' -Message $message
    }
    if ([string]::IsNullOrWhiteSpace($Decision) -and $null -ne $script:Intent -and -not $script:ChildOwnershipConfirmed) {
        try { [void](Save-LatestUpdateState -Root $script:ResolvedRoot -Intent $script:Intent -Status 'error' -SessionPid $PID -Message $message -LogPath (Get-LatestUpdateLogPath -Root $script:ResolvedRoot) -ErrorCode 'startup-failed') } catch { }
        if (-not [string]::IsNullOrWhiteSpace($script:ResolvedRoot)) { Remove-LatestUpdateStagingPackage -Root $script:ResolvedRoot -LaunchToken $LaunchToken }
    }
    Set-LatestUpdateResult -Status 'ERROR' -Message $message
}
finally { Emit-LatestUpdateResult }
