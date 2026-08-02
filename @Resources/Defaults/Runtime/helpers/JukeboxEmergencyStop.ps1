param(
    [string]$StateRoot,
    [string]$InstanceKey = 'default'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    [Console]::OutputEncoding = $script:Utf8NoBom
    $OutputEncoding = $script:Utf8NoBom
}
catch {
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    [Console]::WriteLine($Key + '=' + [string]$Value)
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
        throw 'Jukebox emergency stop StateRoot contains Unicode replacement characters.'
    }

    foreach ($invalidChar in [System.IO.Path]::GetInvalidPathChars()) {
        if ($root.IndexOf($invalidChar) -ge 0) {
            throw 'Jukebox emergency stop StateRoot contains invalid path characters.'
        }
    }

    return [System.IO.Path]::GetFullPath($root)
}

function Get-SafeInstanceKey {
    $safe = ([string]$InstanceKey) -replace '[^A-Za-z0-9_.-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'default'
    }
    return $safe
}

function Get-InstanceRoot {
    return [System.IO.Path]::Combine((Get-StateRootPath), (Get-SafeInstanceKey))
}

function Remove-HelperStateFiles {
    param([Parameter(Mandatory = $true)][string]$InstanceRoot)

    foreach ($name in @('server.pid', 'server.launch', 'server.heartbeat')) {
        Remove-Item -LiteralPath ([System.IO.Path]::Combine($InstanceRoot, $name)) -Force -ErrorAction SilentlyContinue
    }

    $commandsRoot = [System.IO.Path]::Combine($InstanceRoot, 'commands')
    if ([System.IO.Directory]::Exists($commandsRoot)) {
        Get-ChildItem -LiteralPath $commandsRoot -File -Filter '*.command.json*' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProcessStartTimeUtcText {
    param([int]$ProcessId)

    if ($ProcessId -le 0) {
        return ''
    }
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return $process.StartTime.ToUniversalTime().ToString('o')
    }
    catch {
        return ''
    }
}

function Get-ServerLaunchContract {
    param([Parameter(Mandatory = $true)][string]$InstanceRoot)

    $path = [System.IO.Path]::Combine($InstanceRoot, 'server.launch')
    if (-not [System.IO.File]::Exists($path)) {
        return $null
    }

    try {
        $raw = ([System.IO.File]::ReadAllText($path, $script:Utf8NoBom)).Trim()
        if ([string]::IsNullOrWhiteSpace($raw) -or -not $raw.StartsWith('{', [System.StringComparison]::Ordinal)) {
            return $null
        }
        return $raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-JukeboxPlayerProcess {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$InstanceRoot
    )

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        if ($process.ProcessName -ne 'powershell') {
            return $false
        }

        $contract = Get-ServerLaunchContract -InstanceRoot $InstanceRoot
        if ($null -eq $contract) {
            return $false
        }
        if (-not [string]::Equals([string]$contract.Version, 'repeat-reopen-v4', [System.StringComparison]::Ordinal)) {
            return $false
        }
        if ([int]$contract.ProcessId -ne $ProcessId) {
            return $false
        }
        if ([string]::IsNullOrWhiteSpace([string]$contract.Token)) {
            return $false
        }

        $expectedStartTimeUtc = [string]$contract.ProcessStartTimeUtc
        if ([string]::IsNullOrWhiteSpace($expectedStartTimeUtc)) {
            return $false
        }

        $actualStartTimeUtc = Get-ProcessStartTimeUtcText -ProcessId $ProcessId
        return [string]::Equals($actualStartTimeUtc, $expectedStartTimeUtc, [System.StringComparison]::Ordinal)
    }
    catch {
        return $false
    }
}

try {
    $instanceRoot = Get-InstanceRoot
    $pidPath = [System.IO.Path]::Combine($instanceRoot, 'server.pid')
    $stopped = 0

    if ([System.IO.File]::Exists($pidPath)) {
        $raw = ([System.IO.File]::ReadAllText($pidPath, $script:Utf8NoBom)).Trim()
        $targetProcessId = 0
        if ([int]::TryParse($raw, [ref]$targetProcessId) -and $targetProcessId -gt 0) {
            if (Test-JukeboxPlayerProcess -ProcessId $targetProcessId -InstanceRoot $instanceRoot) {
                Stop-Process -Id $targetProcessId -Force -ErrorAction SilentlyContinue
                $stopped = 1
            }
        }
    }

    Remove-HelperStateFiles -InstanceRoot $instanceRoot
    Write-OutputPair -Key 'DMEL_STATUS' -Value 'OK'
    Write-OutputPair -Key 'DMEL_CODE' -Value 'EMERGENCY_STOP'
    Write-OutputPair -Key 'DMEL_MESSAGE' -Value 'Jukebox emergency stop was requested.'
    Write-OutputPair -Key 'DMEL_STOPPED_PROCESS' -Value ([string]$stopped)
}
catch {
    Write-OutputPair -Key 'DMEL_STATUS' -Value 'ERROR'
    Write-OutputPair -Key 'DMEL_CODE' -Value 'EMERGENCY_STOP_FAILED'
    Write-OutputPair -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
}
