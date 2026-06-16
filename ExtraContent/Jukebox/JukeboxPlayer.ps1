param(
    [ValidateSet('Play', 'Pause', 'Stop', 'PollEvent', 'Serve', 'SetLoop', 'SetVolume')]
    [string]$Command = 'Play',

    [string]$AudioPath,
    [string]$RequestPath,
    [string]$StateRoot,
    [string]$InstanceKey = 'default',
    [int]$Volume = 100,
    [switch]$Loop
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:ResultPairs = [ordered]@{
    DMEL_STATUS  = ''
    DMEL_CODE    = ''
    DMEL_MESSAGE = ''
    DMEL_LOGPATH = ''
    DMEL_EVENT   = '0'
    DMEL_AUDIOFILE = ''
}
$script:ServerLaunchContractVersion = 'hidden-window-v2'
$script:LastHeartbeatUnixSeconds = 0

try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

function Set-ResultPairValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($Key + '=' + [string]$Value)
    }
    finally {
        $writer.Dispose()
    }
}

function Emit-ResultPairs {
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value (Get-CanonicalLogPath)
    foreach ($key in @('DMEL_STATUS', 'DMEL_CODE', 'DMEL_MESSAGE', 'DMEL_LOGPATH', 'DMEL_EVENT', 'DMEL_AUDIOFILE')) {
        Write-OutputPair -Key $key -Value $script:ResultPairs[$key]
    }
}

function Get-SkinRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Get-CanonicalLogPath {
    return [System.IO.Path]::Combine((Get-SkinRoot), 'Logs', "DMeloper's Block HUD Log.log")
}

function Write-CanonicalLogBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [AllowNull()][object[]]$Lines
    )

    $path = Get-CanonicalLogPath
    $parent = [System.IO.Path]::GetDirectoryName($path)
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not [System.IO.Directory]::Exists($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine(('<{0}>' -f $Type))
    foreach ($line in @($Lines)) {
        [void]$builder.AppendLine([string]$line)
    }
    [void]$builder.AppendLine(('</{0}>' -f $Type))
    [System.IO.File]::AppendAllText($path, $builder.ToString(), $script:Utf8NoBom)
    return $path
}

function Complete-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Event = '0',
        [string]$AudioFile = ''
    )

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value $Status
    Set-ResultPairValue -Key 'DMEL_CODE' -Value $Code
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $Message
    Set-ResultPairValue -Key 'DMEL_EVENT' -Value $Event
    Set-ResultPairValue -Key 'DMEL_AUDIOFILE' -Value $AudioFile
}

function Get-SafeInstanceKey {
    $safe = ([string]$InstanceKey) -replace '[^A-Za-z0-9_.-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'default'
    }
    return $safe
}

function Get-StateRootPath {
    $root = [string]$StateRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($local)) {
            $local = [System.IO.Path]::GetTempPath()
        }
        $root = [System.IO.Path]::Combine($local, 'DMeloperBlockHUD', 'Jukebox')
    }
    elseif ($root.IndexOf([char]0xfffd) -ge 0) {
        throw 'Jukebox helper StateRoot contains Unicode replacement characters. The caller must omit StateRoot or pass a Unicode-safe path.'
    }
    foreach ($invalidChar in [System.IO.Path]::GetInvalidPathChars()) {
        if ($root.IndexOf($invalidChar) -ge 0) {
            throw 'Jukebox helper StateRoot contains invalid path characters. The caller must omit StateRoot or pass a Unicode-safe path.'
        }
    }
    return [System.IO.Path]::GetFullPath($root)
}

function Get-InstanceRoot {
    return [System.IO.Path]::Combine((Get-StateRootPath), (Get-SafeInstanceKey))
}

function Get-CommandsRoot {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'commands')
}

function Get-EventsRoot {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'events')
}

function Get-EventQueuePath {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'events.queue')
}

function Get-EventQueueCursorPath {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'events.cursor')
}

function Ensure-InstanceDirectories {
    foreach ($path in @((Get-InstanceRoot), (Get-CommandsRoot), (Get-EventsRoot))) {
        if (-not [System.IO.Directory]::Exists($path)) {
            [System.IO.Directory]::CreateDirectory($path) | Out-Null
        }
    }
}

function Get-PidFilePath {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'server.pid')
}

function Get-ServerLaunchContractPath {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'server.launch')
}

function Get-ServerHeartbeatPath {
    return [System.IO.Path]::Combine((Get-InstanceRoot), 'server.heartbeat')
}

function Resolve-FullPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
}

function Get-AudioDisplayName {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return 'selected audio file'
    }

    try {
        $name = [System.IO.Path]::GetFileName([string]$Path)
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name
        }
    }
    catch {
    }

    return [string]$Path
}

function Resolve-AudioFile {
    $resolved = Resolve-FullPath -Path $AudioPath
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not [System.IO.File]::Exists($resolved)) {
        throw ([System.IO.FileNotFoundException]::new('The Jukebox audio file is missing.', $resolved))
    }
    return $resolved
}

function Import-RequestFile {
    param([AllowNull()][string]$Path)

    $values = @{}
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $values
    }

    $resolved = Resolve-FullPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not [System.IO.File]::Exists($resolved)) {
        throw "The Jukebox request file is missing."
    }

    foreach ($line in [System.IO.File]::ReadAllLines($resolved, $script:Utf8NoBom)) {
        $separator = ([string]$line).IndexOf('=')
        if ($separator -lt 1) {
            continue
        }
        $key = ([string]$line).Substring(0, $separator).Trim()
        $value = ([string]$line).Substring($separator + 1)
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $values[$key] = $value
        }
    }

    try {
        Remove-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
    }
    catch {
    }

    return $values
}

function Apply-RequestFile {
    $request = Import-RequestFile -Path $RequestPath
    if ($request.Count -le 0) {
        return
    }

    if ($request.ContainsKey('COMMAND')) {
        $script:Command = [string]$request['COMMAND']
    }
    if ($request.ContainsKey('AUDIOPATH')) {
        $script:AudioPath = [string]$request['AUDIOPATH']
    }
    if ($request.ContainsKey('LOOP')) {
        $script:Loop = [string]$request['LOOP'] -eq '1'
    }
    if ($request.ContainsKey('VOLUME')) {
        $script:Volume = Get-ClampedVolumePercent -Value $request['VOLUME']
    }

    if (@('Play', 'Pause', 'Stop', 'PollEvent', 'Serve', 'SetLoop', 'SetVolume') -notcontains $script:Command) {
        throw "The Jukebox request file contained an invalid command."
    }
}

function Get-ClampedVolumePercent {
    param([AllowNull()][object]$Value)

    $parsed = 100
    if ($null -ne $Value) {
        $text = ([string]$Value).Trim()
        if (-not [int]::TryParse($text, [ref]$parsed)) {
            $parsed = 100
        }
    }
    if ($parsed -lt 0) {
        return 0
    }
    if ($parsed -gt 100) {
        return 100
    }
    return $parsed
}

function ConvertTo-PlayerVolume {
    param([int]$VolumePercent)

    $clamped = Get-ClampedVolumePercent -Value $VolumePercent
    return [double]($clamped / 100.0)
}

function Get-JsonPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Fallback
    )

    if ($null -eq $Object -or $null -eq $Object.PSObject) {
        return $Fallback
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Fallback
    }
    return $property.Value
}

function Get-CommandVolumePercent {
    param(
        [AllowNull()][object]$CommandData,
        [int]$Fallback
    )

    return Get-ClampedVolumePercent -Value (Get-JsonPropertyValue -Object $CommandData -Name 'Volume' -Fallback $Fallback)
}

function Clear-CurrentMediaState {
    param([switch]$ClosePlayer)

    try {
        if ($ClosePlayer -and $script:Player) {
            $script:Player.Stop()
            $script:Player.Close()
        }
    }
    catch {
    }

    $script:CurrentAudioPath = ''
    $script:HasMedia = $false
    $script:IsPlaying = $false
}

function Test-CurrentAudioAvailable {
    if (-not $script:HasMedia -or [string]::IsNullOrWhiteSpace([string]$script:CurrentAudioPath)) {
        return $true
    }
    if ([System.IO.File]::Exists([string]$script:CurrentAudioPath)) {
        return $true
    }

    $missingAudio = Get-AudioDisplayName -Path $script:CurrentAudioPath
    Clear-CurrentMediaState -ClosePlayer
    Write-PlayerEvent -Status 'ERROR' -Code 'AUDIO_MISSING' -Message 'The Jukebox audio file is missing.' -Detail '' -AudioFile $missingAudio
    return $false
}

function Test-ProcessAlive {
    param([int]$ProcessId)

    if ($ProcessId -le 0) {
        return $false
    }
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return -not $process.HasExited
    }
    catch {
        return $false
    }
}

function Get-ServerProcessId {
    $pidFile = Get-PidFilePath
    if (-not [System.IO.File]::Exists($pidFile)) {
        return 0
    }
    $raw = ([System.IO.File]::ReadAllText($pidFile, $script:Utf8NoBom)).Trim()
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed) -and (Test-ProcessAlive -ProcessId $parsed)) {
        return $parsed
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    return 0
}

function Get-ServerLaunchContract {
    $path = Get-ServerLaunchContractPath
    if (-not [System.IO.File]::Exists($path)) {
        return ''
    }
    try {
        return ([System.IO.File]::ReadAllText($path, $script:Utf8NoBom)).Trim()
    }
    catch {
        return ''
    }
}

function Write-ServerLaunchContract {
    Ensure-InstanceDirectories
    [System.IO.File]::WriteAllText((Get-ServerLaunchContractPath), $script:ServerLaunchContractVersion, $script:Utf8NoBom)
}

function Clear-ServerLaunchContract {
    Remove-Item -LiteralPath (Get-ServerLaunchContractPath) -Force -ErrorAction SilentlyContinue
}

function Write-ServerHeartbeat {
    param([switch]$Force)

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $Force -and $script:LastHeartbeatUnixSeconds -eq $now) {
        return
    }
    Ensure-InstanceDirectories
    [System.IO.File]::WriteAllText((Get-ServerHeartbeatPath), [string]$now, $script:Utf8NoBom)
    $script:LastHeartbeatUnixSeconds = $now
}

function Clear-ServerHeartbeat {
    Remove-Item -LiteralPath (Get-ServerHeartbeatPath) -Force -ErrorAction SilentlyContinue
}

function Test-ServerLaunchContractCurrent {
    return [string]::Equals((Get-ServerLaunchContract), $script:ServerLaunchContractVersion, [System.StringComparison]::Ordinal)
}

function Reset-LegacyServerIfNeeded {
    $serverPid = Get-ServerProcessId
    if ($serverPid -le 0 -or (Test-ServerLaunchContractCurrent)) {
        return
    }

    Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
        '[WARN] Restarting Jukebox player server because its launch contract predates hidden-window startup.',
        ('PID=' + [string]$serverPid)
    ) | Out-Null
    Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Get-PidFilePath) -Force -ErrorAction SilentlyContinue
    Clear-ServerLaunchContract
    Clear-ServerHeartbeat
}

function Quote-NativeArgument {
    param([AllowNull()][string]$Argument)

    $value = if ($null -eq $Argument) { '' } else { [string]$Argument }
    if ($value.Length -gt 0 -and $value -notmatch '[\s"]') {
        return $value
    }
    return '"' + ($value -replace '"', '\"') + '"'
}

function Start-ServerProcess {
    param([Parameter(Mandatory = $true)][string]$ResolvedAudioPath)

    Reset-LegacyServerIfNeeded
    if ((Get-ServerProcessId) -gt 0) {
        return
    }

    $powerShellPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $arguments = @(
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Command', 'Serve',
        '-AudioPath', $ResolvedAudioPath,
        '-Volume', (Get-ClampedVolumePercent -Value $Volume),
        '-StateRoot', (Get-StateRootPath),
        '-InstanceKey', (Get-SafeInstanceKey)
    )
    if ($Loop) {
        $arguments += '-Loop'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $powerShellPath
    $psi.Arguments = (($arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) {
        throw 'The Jukebox player process could not be started.'
    }

    Start-Sleep -Milliseconds 350
    if ($process.HasExited) {
        throw ("The Jukebox player process exited during startup with code {0}." -f $process.ExitCode)
    }
}

function Write-JsonFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $json = $Value | ConvertTo-Json -Compress -Depth 5
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, $script:Utf8NoBom)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-EventQueueMutex {
    $name = 'DMeloperBlockHudJukeboxEvents_' + ((Get-SafeInstanceKey) -replace '[^A-Za-z0-9_]', '_')
    return New-Object System.Threading.Mutex($false, $name)
}

function Invoke-WithEventQueueMutex {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    $mutex = Get-EventQueueMutex
    $hasLock = $false
    try {
        $hasLock = $mutex.WaitOne(5000)
        if (-not $hasLock) {
            return $false
        }
        & $Action
        return $true
    }
    finally {
        if ($hasLock) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function ConvertTo-ResultPairLineValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value) -replace "[`r`n]+", ' '
}

function New-PlayerEventResultBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()][string]$AudioFile
    )

    $queueId = [guid]::NewGuid().ToString('N')
    $lines = @(
        'DMEL_QUEUE_ID=' + $queueId,
        'DMEL_STATUS=' + (ConvertTo-ResultPairLineValue $Status),
        'DMEL_CODE=' + (ConvertTo-ResultPairLineValue $Code),
        'DMEL_MESSAGE=' + (ConvertTo-ResultPairLineValue $Message),
        'DMEL_LOGPATH=' + (ConvertTo-ResultPairLineValue (Get-CanonicalLogPath)),
        'DMEL_EVENT=1',
        'DMEL_AUDIOFILE=' + (ConvertTo-ResultPairLineValue $AudioFile),
        'DMEL_END=1'
    )
    return (($lines -join "`n") + "`n")
}

function Add-PlayerEventResultBlock {
    param([Parameter(Mandatory = $true)][string]$Block)

    Ensure-InstanceDirectories
    $queuePath = Get-EventQueuePath
    $ok = Invoke-WithEventQueueMutex {
        [System.IO.File]::AppendAllText($queuePath, $Block, $script:Utf8NoBom)
    }
    if (-not $ok) {
        Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
            '[ERROR] Failed to queue Jukebox player event.',
            'The Jukebox player event queue was busy.'
        ) | Out-Null
    }
}

function Read-FirstQueuedPlayerEventBlock {
    $queuePath = Get-EventQueuePath
    if (-not [System.IO.File]::Exists($queuePath)) {
        return ''
    }

    $script:QueuedPlayerEventBlock = ''
    [void](Invoke-WithEventQueueMutex {
        if (-not [System.IO.File]::Exists($queuePath)) {
            return
        }
        $raw = [System.IO.File]::ReadAllText($queuePath, $script:Utf8NoBom)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return
        }

        $cursorPath = Get-EventQueueCursorPath
        $cursorId = ''
        if ([System.IO.File]::Exists($cursorPath)) {
            $cursorId = ([System.IO.File]::ReadAllText($cursorPath, $script:Utf8NoBom)).Trim()
        }

        $blocks = New-Object 'System.Collections.Generic.List[string]'
        $matches = [regex]::Matches([string]$raw, 'DMEL_QUEUE_ID=.*?DMEL_END=1', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($match in $matches) {
            $block = ([string]$match.Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($block)) {
                [void]$blocks.Add($block)
            }
        }
        if ($blocks.Count -le 0) {
            return
        }

        $returnNext = [string]::IsNullOrWhiteSpace($cursorId)
        $selectedBlock = ''
        $selectedId = ''
        foreach ($block in $blocks) {
            $blockId = Get-ResultPairValueFromBlock -Block $block -Name 'DMEL_QUEUE_ID'
            if ([string]::IsNullOrWhiteSpace($blockId)) {
                continue
            }
            if ($returnNext) {
                $selectedBlock = $block
                $selectedId = $blockId
                break
            }
            if ([string]::Equals($blockId, $cursorId, [System.StringComparison]::Ordinal)) {
                $returnNext = $true
            }
        }

        if ([string]::IsNullOrWhiteSpace($selectedBlock) -and -not [string]::IsNullOrWhiteSpace($cursorId) -and -not $returnNext) {
            for ($index = $blocks.Count - 1; $index -ge 0; $index--) {
                $blockId = Get-ResultPairValueFromBlock -Block $blocks[$index] -Name 'DMEL_QUEUE_ID'
                if (-not [string]::IsNullOrWhiteSpace($blockId)) {
                    [System.IO.File]::WriteAllText($cursorPath, ($blockId.Trim() + "`n"), $script:Utf8NoBom)
                    return
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($selectedBlock)) {
            return
        }

        $script:QueuedPlayerEventBlock = $selectedBlock
        if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
            [System.IO.File]::WriteAllText($cursorPath, ($selectedId + "`n"), $script:Utf8NoBom)
        }
    })

    return $script:QueuedPlayerEventBlock
}

function Get-ResultPairsFromBlock {
    param([AllowNull()][string]$Block)

    $pairs = @{}
    $text = [string]$Block
    $matches = [regex]::Matches($text, '([A-Z][A-Z0-9_]+)=')
    for ($index = 0; $index -lt $matches.Count; $index++) {
        $match = $matches[$index]
        $key = [string]$match.Groups[1].Value
        $valueStart = $match.Index + $match.Length
        $valueEnd = $text.Length
        if ($index + 1 -lt $matches.Count) {
            $valueEnd = $matches[$index + 1].Index
        }
        if ($valueEnd -lt $valueStart) {
            $valueEnd = $valueStart
        }
        $pairs[$key] = $text.Substring($valueStart, $valueEnd - $valueStart).Trim()
    }
    return $pairs
}

function Get-ResultPairValueFromBlock {
    param(
        [AllowNull()][string]$Block,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $pairs = Get-ResultPairsFromBlock -Block $Block
    if ($pairs.ContainsKey($Name)) {
        return [string]$pairs[$Name]
    }
    return ''
}

function Set-ResultPairsFromBlock {
    param([AllowNull()][string]$Block)

    $pairs = Get-ResultPairsFromBlock -Block $Block
    foreach ($key in @($pairs.Keys)) {
        if ($script:ResultPairs.Contains($key)) {
            Set-ResultPairValue -Key $key -Value $pairs[$key]
        }
    }
}

function Poll-QueuedPlayerEvent {
    $block = Read-FirstQueuedPlayerEventBlock
    if ([string]::IsNullOrWhiteSpace($block)) {
        return $false
    }
    Set-ResultPairsFromBlock -Block $block
    return $true
}

function Queue-PlayerCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][string]$ResolvedAudioPath,
        [int]$VolumePercent = 100
    )

    Ensure-InstanceDirectories
    $id = [guid]::NewGuid().ToString('N')
    $path = [System.IO.Path]::Combine((Get-CommandsRoot), ($id + '.command.json'))
    Write-JsonFileAtomic -Path $path -Value ([ordered]@{
        Id        = $id
        Command   = $Name
        AudioPath = [string]$ResolvedAudioPath
        Loop      = [bool]$Loop
        Volume    = Get-ClampedVolumePercent -Value $VolumePercent
        CreatedAt = [DateTime]::UtcNow.ToString('o')
    })
}

function Get-OldestFile {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (-not [System.IO.Directory]::Exists($Directory)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $Directory -File -Filter '*.json' |
        Sort-Object LastWriteTimeUtc, Name |
        Select-Object -First 1
}

function Poll-PlayerEvent {
    Ensure-InstanceDirectories
    if (Poll-QueuedPlayerEvent) {
        return
    }

    $file = Get-OldestFile -Directory (Get-EventsRoot)
    if ($null -eq $file) {
        Complete-Result -Status 'OK' -Code 'NO_EVENT' -Message 'No Jukebox player event is pending.' -Event '0'
        return
    }

    try {
        $event = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        $status = if ([string]::IsNullOrWhiteSpace([string]$event.Status)) { 'ERROR' } else { [string]$event.Status }
        $code = if ([string]::IsNullOrWhiteSpace([string]$event.Code)) { 'PLAYBACK_FAILED' } else { [string]$event.Code }
        $message = if ([string]::IsNullOrWhiteSpace([string]$event.Message)) { 'The Jukebox audio could not be played.' } else { [string]$event.Message }
        $audioFile = if ([string]::IsNullOrWhiteSpace([string]$event.AudioFile)) { '' } else { [string]$event.AudioFile }
        Complete-Result -Status $status -Code $code -Message $message -Event '1' -AudioFile $audioFile
    }
    catch {
        Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
            '[ERROR] Failed to read Jukebox player event.',
            $_.Exception.Message
        ) | Out-Null
        Complete-Result -Status 'ERROR' -Code 'EVENT_POLL_FAILED' -Message 'The Jukebox player status could not be checked.' -Event '1'
    }
}

function Get-ControllerMutex {
    $name = 'DMeloperBlockHudJukebox_' + ((Get-SafeInstanceKey) -replace '[^A-Za-z0-9_]', '_')
    return New-Object System.Threading.Mutex($false, $name)
}

function Invoke-WithControllerMutex {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    $mutex = Get-ControllerMutex
    $hasLock = $false
    try {
        $hasLock = $mutex.WaitOne(5000)
        if (-not $hasLock) {
            Complete-Result -Status 'WARN' -Code 'HELPER_BUSY' -Message 'Playback command ignored because the helper is busy.'
            return
        }
        & $Action
    }
    finally {
        if ($hasLock) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Write-PlayerEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()][string]$Detail,
        [AllowNull()][string]$AudioFile
    )

    $block = New-PlayerEventResultBlock -Status $Status -Code $Code -Message $Message -AudioFile $AudioFile
    Add-PlayerEventResultBlock -Block $block

    Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
        ('[{0}] {1}: {2}' -f $Status, $Code, $Message),
        ([string]$Detail)
    ) | Out-Null
}

function Start-PlayerServer {
    Ensure-InstanceDirectories
    $pidFile = Get-PidFilePath
    [System.IO.File]::WriteAllText($pidFile, [string]$PID, $script:Utf8NoBom)
    Write-ServerLaunchContract
    Write-ServerHeartbeat -Force

    $script:Player = $null
    $script:CurrentAudioPath = ''
    $script:HasMedia = $false
    $script:IsPlaying = $false
    $script:LoopPlayback = [bool]$Loop
    $script:PlaybackVolume = Get-ClampedVolumePercent -Value $Volume
    $script:Dispatcher = $null

    try {
        Add-Type -AssemblyName WindowsBase
        Add-Type -AssemblyName PresentationCore

        $script:Dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $script:Player = New-Object System.Windows.Media.MediaPlayer
        $script:Player.Volume = ConvertTo-PlayerVolume -VolumePercent $script:PlaybackVolume
        $script:Player.add_MediaEnded({
            try {
                if ($script:LoopPlayback) {
                    if (-not (Test-CurrentAudioAvailable)) {
                        return
                    }
                    $script:Player.Position = [TimeSpan]::Zero
                    $script:Player.Play()
                    $script:IsPlaying = $true
                }
                else {
                    $script:IsPlaying = $false
                    Write-PlayerEvent -Status 'OK' -Code 'TRACK_ENDED' -Message 'The Jukebox track ended.' -Detail '' -AudioFile (Get-AudioDisplayName -Path $script:CurrentAudioPath)
                }
            }
            catch {
                $audioFile = Get-AudioDisplayName -Path $script:CurrentAudioPath
                Clear-CurrentMediaState -ClosePlayer
                Write-PlayerEvent -Status 'ERROR' -Code 'PLAYBACK_FAILED' -Message 'The Jukebox audio could not be played.' -Detail $_.Exception.Message -AudioFile $audioFile
            }
        })
        $script:Player.add_MediaFailed({
            param($Sender, $Args)
            $detail = 'Unknown media failure.'
            $audioFile = Get-AudioDisplayName -Path $script:CurrentAudioPath
            try {
                if ($Args -and $Args.ErrorException) {
                    $detail = $Args.ErrorException.Message
                }
            }
            catch {
            }
            Clear-CurrentMediaState -ClosePlayer
            Write-PlayerEvent -Status 'ERROR' -Code 'PLAYBACK_FAILED' -Message 'The Jukebox audio could not be played.' -Detail $detail -AudioFile $audioFile
        })

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $timer.add_Tick({
            try {
                Write-ServerHeartbeat
                [void](Test-CurrentAudioAvailable)
                $files = @(Get-ChildItem -LiteralPath (Get-CommandsRoot) -File -Filter '*.command.json' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc, Name)
                foreach ($file in $files) {
                    try {
                        $commandData = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                        $name = [string]$commandData.Command
                        if ([string]::Equals($name, 'Stop', [System.StringComparison]::OrdinalIgnoreCase)) {
                            if ($script:Player) {
                                $script:Player.Stop()
                                $script:Player.Close()
                            }
                            $script:IsPlaying = $false
                            $script:HasMedia = $false
                            $script:Dispatcher.BeginInvokeShutdown([System.Windows.Threading.DispatcherPriority]::Normal)
                            return
                        }

                        if ([string]::Equals($name, 'Pause', [System.StringComparison]::OrdinalIgnoreCase)) {
                            if ($script:Player -and $script:HasMedia -and $script:IsPlaying) {
                                $script:Player.Pause()
                            }
                            $script:IsPlaying = $false
                            continue
                        }

                        if ([string]::Equals($name, 'SetLoop', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $script:LoopPlayback = [bool]$commandData.Loop
                            continue
                        }

                        if ([string]::Equals($name, 'SetVolume', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $script:PlaybackVolume = Get-CommandVolumePercent -CommandData $commandData -Fallback $script:PlaybackVolume
                            if ($script:Player) {
                                $script:Player.Volume = ConvertTo-PlayerVolume -VolumePercent $script:PlaybackVolume
                            }
                            continue
                        }

                        if ([string]::Equals($name, 'Play', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $script:LoopPlayback = [bool]$commandData.Loop
                            $script:PlaybackVolume = Get-CommandVolumePercent -CommandData $commandData -Fallback $script:PlaybackVolume
                            if ($script:Player) {
                                $script:Player.Volume = ConvertTo-PlayerVolume -VolumePercent $script:PlaybackVolume
                            }
                            $incomingAudio = Resolve-FullPath -Path ([string]$commandData.AudioPath)
                            if ([string]::IsNullOrWhiteSpace($incomingAudio) -or -not [System.IO.File]::Exists($incomingAudio)) {
                                if (-not [string]::IsNullOrWhiteSpace($incomingAudio) -and [string]::Equals($script:CurrentAudioPath, $incomingAudio, [System.StringComparison]::OrdinalIgnoreCase)) {
                                    Clear-CurrentMediaState -ClosePlayer
                                }
                                Write-PlayerEvent -Status 'ERROR' -Code 'AUDIO_MISSING' -Message 'The Jukebox audio file is missing.' -Detail $incomingAudio -AudioFile (Get-AudioDisplayName -Path $incomingAudio)
                                continue
                            }

                            if (-not $script:HasMedia -or -not [string]::Equals($script:CurrentAudioPath, $incomingAudio, [System.StringComparison]::OrdinalIgnoreCase)) {
                                try {
                                    $script:Player.Open([Uri]$incomingAudio)
                                }
                                catch {
                                    Clear-CurrentMediaState -ClosePlayer
                                    Write-PlayerEvent -Status 'ERROR' -Code 'PLAYBACK_FAILED' -Message 'The Jukebox audio could not be played.' -Detail $_.Exception.Message -AudioFile (Get-AudioDisplayName -Path $incomingAudio)
                                    continue
                                }
                                $script:CurrentAudioPath = $incomingAudio
                                $script:HasMedia = $true
                                $script:IsPlaying = $false
                            }

                            if (-not $script:IsPlaying) {
                                $script:Player.Play()
                                $script:IsPlaying = $true
                            }
                            continue
                        }

                        Write-PlayerEvent -Status 'ERROR' -Code 'COMMAND_FAILED' -Message 'The Jukebox command could not be completed.' -Detail ('Unsupported command: ' + $name)
                    }
                    catch {
                        try {
                            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                        }
                        catch {
                        }
                        Write-PlayerEvent -Status 'ERROR' -Code 'COMMAND_FAILED' -Message 'The Jukebox command could not be completed.' -Detail $_.Exception.Message
                    }
                }
            }
            catch {
                Write-PlayerEvent -Status 'ERROR' -Code 'COMMAND_FAILED' -Message 'The Jukebox command could not be completed.' -Detail $_.Exception.Message
            }
        })
        $timer.Start()
        [System.Windows.Threading.Dispatcher]::Run()
    }
    finally {
        try {
            if ($script:Player) {
                $script:Player.Close()
            }
        }
        catch {
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        Clear-ServerLaunchContract
        Clear-ServerHeartbeat
    }
}

try {
    Apply-RequestFile
    Ensure-InstanceDirectories

    if ([string]::Equals($Command, 'Serve', [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
            Start-PlayerServer
        }
        catch {
            Write-PlayerEvent -Status 'ERROR' -Code 'HELPER_START_FAILED' -Message 'The Jukebox player could not be started.' -Detail $_.Exception.Message
            Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
                '[ERROR] Jukebox player server failed.',
                $_.Exception.Message
            ) | Out-Null
            exit 1
        }
        exit 0
    }

    Invoke-WithControllerMutex {
        if ([string]::Equals($Command, 'PollEvent', [System.StringComparison]::OrdinalIgnoreCase)) {
            Poll-PlayerEvent
            return
        }

        if ([string]::Equals($Command, 'Stop', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ((Get-ServerProcessId) -gt 0) {
                Queue-PlayerCommand -Name 'Stop' -ResolvedAudioPath '' -VolumePercent $Volume
            }
            Complete-Result -Status 'OK' -Code 'STOP_QUEUED' -Message 'Jukebox playback was stopped.'
            return
        }

        if ([string]::Equals($Command, 'Pause', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ((Get-ServerProcessId) -gt 0) {
                Queue-PlayerCommand -Name 'Pause' -ResolvedAudioPath '' -VolumePercent $Volume
                Complete-Result -Status 'OK' -Code 'PAUSE_QUEUED' -Message 'Jukebox playback pause command was queued.'
            }
            else {
                Complete-Result -Status 'OK' -Code 'PAUSE_NOOP' -Message 'Jukebox playback was already stopped.'
            }
            return
        }

        if ([string]::Equals($Command, 'SetLoop', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ((Get-ServerProcessId) -gt 0) {
                Queue-PlayerCommand -Name 'SetLoop' -ResolvedAudioPath '' -VolumePercent $Volume
                Complete-Result -Status 'OK' -Code 'SET_LOOP_QUEUED' -Message 'Jukebox playback loop mode was queued.'
            }
            else {
                Complete-Result -Status 'OK' -Code 'SET_LOOP_NOOP' -Message 'Jukebox playback loop mode was already inactive.'
            }
            return
        }

        if ([string]::Equals($Command, 'SetVolume', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ((Get-ServerProcessId) -gt 0) {
                Queue-PlayerCommand -Name 'SetVolume' -ResolvedAudioPath '' -VolumePercent $Volume
                Complete-Result -Status 'OK' -Code 'SET_VOLUME_QUEUED' -Message 'Jukebox playback volume command was queued.'
            }
            else {
                Complete-Result -Status 'OK' -Code 'SET_VOLUME_NOOP' -Message 'Jukebox playback volume was saved for the next track.'
            }
            return
        }

        $resolvedAudio = Resolve-AudioFile
        try {
            Start-ServerProcess -ResolvedAudioPath $resolvedAudio
        }
        catch {
            Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
                '[ERROR] Jukebox player process could not be started.',
                $_.Exception.Message
            ) | Out-Null
            Complete-Result -Status 'ERROR' -Code 'HELPER_START_FAILED' -Message 'The Jukebox player could not be started.'
            return
        }

        Queue-PlayerCommand -Name 'Play' -ResolvedAudioPath $resolvedAudio -VolumePercent $Volume
        Complete-Result -Status 'OK' -Code 'PLAY_QUEUED' -Message 'Jukebox playback command was queued.'
    }
}
catch [System.IO.FileNotFoundException] {
    $missingAudioName = Get-AudioDisplayName -Path $_.Exception.FileName
    Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
        '[ERROR] Jukebox audio file is missing.',
        $_.Exception.FileName
    ) | Out-Null
    Complete-Result -Status 'ERROR' -Code 'AUDIO_MISSING' -Message 'The Jukebox audio file is missing.' -AudioFile $missingAudioName
}
catch {
    Write-CanonicalLogBlock -Type 'JukeboxPlayer' -Lines @(
        '[ERROR] Jukebox command failed.',
        $_.Exception.Message
    ) | Out-Null
    Complete-Result -Status 'ERROR' -Code 'COMMAND_FAILED' -Message 'The Jukebox command could not be completed.'
}
finally {
    if (-not [string]::Equals($Command, 'Serve', [System.StringComparison]::OrdinalIgnoreCase)) {
        Emit-ResultPairs
    }
}
