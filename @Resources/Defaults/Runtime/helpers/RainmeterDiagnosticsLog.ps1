[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('EnsureLogging', 'Tail')]
    [string]$Mode,

    [string]$RainmeterIniPath = '',
    [string]$RainmeterLogPath = '',
    [string]$ConfigName = '',
    [long]$Offset = 0,
    [ValidateRange(4096, 1048576)]
    [int]$MaxTailBytes = 262144,
    [ValidateRange(1, 1000)]
    [int]$MaxEntries = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PendingKey = 'BlockHudDiagnosticsLoggingRefreshPending'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $Utf8NoBom

function Write-DmelPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Value
    )

    $text = [string]$Value
    $text = $text -replace '[\r\n\t]+', ' '
    [Console]::WriteLine(('{0}={1}' -f $Key, $text))
}

function Get-TextEncodingKind {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return 'UTF16LE'
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return 'UTF16BE'
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return 'UTF8'
    }

    $sampleLength = [Math]::Min($Bytes.Length, 512)
    $nulOdd = 0
    for ($index = 1; $index -lt $sampleLength; $index += 2) {
        if ($Bytes[$index] -eq 0) {
            $nulOdd++
        }
    }
    if ($nulOdd -gt 8) {
        return 'UTF16LE'
    }

    return 'Default'
}

function Get-FileTextEncodingKind {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    $sampleLength = [int][Math]::Min($Stream.Length, 512)
    if ($sampleLength -le 0) {
        return 'Default'
    }

    $sample = [byte[]]::new($sampleLength)
    $originalPosition = $Stream.Position
    try {
        $Stream.Position = 0
        $read = $Stream.Read($sample, 0, $sample.Length)
        if ($read -lt $sample.Length) {
            $trimmed = [byte[]]::new($read)
            if ($read -gt 0) {
                [Array]::Copy($sample, 0, $trimmed, 0, $read)
            }
            $sample = $trimmed
        }
        return Get-TextEncodingKind -Bytes $sample
    }
    finally {
        $Stream.Position = $originalPosition
    }
}

function Convert-BytesToText {
    param(
        [byte[]]$Bytes,
        [string]$Kind
    )

    if ($Bytes.Length -eq 0) {
        return ''
    }

    switch ($Kind) {
        'UTF16LE' { return [System.Text.Encoding]::Unicode.GetString($Bytes) }
        'UTF16BE' { return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes) }
        'UTF8' { return [System.Text.Encoding]::UTF8.GetString($Bytes) }
        default { return [System.Text.Encoding]::Default.GetString($Bytes) }
    }
}

function Read-TextFileBestEffort {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return ''
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $kind = Get-TextEncodingKind -Bytes $bytes
    return (Convert-BytesToText -Bytes $bytes -Kind $kind).TrimStart([char]0xFEFF)
}

function Get-IniValue {
    param(
        [string]$Content,
        [string]$Section,
        [string]$Key
    )

    $targetSection = $Section.Trim()
    $targetKey = $Key.Trim()
    if ([string]::IsNullOrWhiteSpace($targetSection) -or [string]::IsNullOrWhiteSpace($targetKey)) {
        return $null
    }

    $inSection = $false
    foreach ($line in ([string]$Content -split '\r?\n')) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $inSection = [string]::Equals($matches[1].Trim(), $targetSection, [System.StringComparison]::OrdinalIgnoreCase)
            continue
        }
        if ($inSection -and $line -match '^\s*([^=;\s][^=]*)\s*=\s*(.*?)\s*$') {
            if ([string]::Equals($matches[1].Trim(), $targetKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $matches[2].Trim()
            }
        }
    }
    return $null
}

function Set-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $content = Read-TextFileBestEffort -Path $Path
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($content.Length -gt 0) {
        foreach ($line in ($content -split '\r?\n')) {
            $lines.Add([string]$line)
        }
    }

    $sectionIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[([^\]]+)\]\s*$' -and
            [string]::Equals($matches[1].Trim(), $Section, [System.StringComparison]::OrdinalIgnoreCase)) {
            $sectionIndex = $index
            break
        }
    }

    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    }
    else {
        $insertIndex = $lines.Count
        $updated = $false
        for ($index = $sectionIndex + 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^\s*\[[^\]]+\]\s*$') {
                $insertIndex = $index
                break
            }
            if ($lines[$index] -match '^\s*([^=;\s][^=]*)\s*=') {
                if ([string]::Equals($matches[1].Trim(), $Key, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $lines[$index] = "$Key=$Value"
                    $updated = $true
                    break
                }
            }
        }
        if (-not $updated) {
            $lines.Insert($insertIndex, "$Key=$Value")
        }
    }

    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    [System.IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Unicode)
}

function Get-FileLength {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) {
        return 0
    }
    return ([System.IO.FileInfo]::new($Path)).Length
}

function Invoke-EnsureLogging {
    if ([string]::IsNullOrWhiteSpace($RainmeterIniPath) -or [string]::IsNullOrWhiteSpace($ConfigName)) {
        throw 'Rainmeter settings path or config name is empty.'
    }

    $iniPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RainmeterIniPath))
    $content = Read-TextFileBestEffort -Path $iniPath
    $loggingEnabled = [string]::Equals((Get-IniValue -Content $content -Section 'Rainmeter' -Key 'Logging'), '1', [System.StringComparison]::Ordinal)
    $refreshPending = [string]::Equals((Get-IniValue -Content $content -Section $ConfigName -Key $PendingKey), '1', [System.StringComparison]::Ordinal)

    if ($loggingEnabled) {
        if ($refreshPending) {
            Set-IniValue -Path $iniPath -Section $ConfigName -Key $PendingKey -Value '0'
        }
        Write-DmelPair 'DMEL_STATUS' 'OK'
        Write-DmelPair 'DMEL_LOGGING_ENABLED' '1'
        Write-DmelPair 'DMEL_REFRESH_REQUIRED' '0'
        Write-DmelPair 'DMEL_LOG_SIZE' (Get-FileLength -Path $RainmeterLogPath)
        return
    }

    if ($refreshPending) {
        Write-DmelPair 'DMEL_STATUS' 'OK'
        Write-DmelPair 'DMEL_LOGGING_ENABLED' '0'
        Write-DmelPair 'DMEL_REFRESH_REQUIRED' '0'
        Write-DmelPair 'DMEL_LOG_SIZE' '0'
        return
    }

    Set-IniValue -Path $iniPath -Section 'Rainmeter' -Key 'Logging' -Value '1'
    Set-IniValue -Path $iniPath -Section $ConfigName -Key $PendingKey -Value '1'
    Write-DmelPair 'DMEL_STATUS' 'OK'
    Write-DmelPair 'DMEL_LOGGING_ENABLED' '0'
    Write-DmelPair 'DMEL_REFRESH_REQUIRED' '1'
    Write-DmelPair 'DMEL_LOG_SIZE' '0'
}

function Invoke-TailLog {
    if ([string]::IsNullOrWhiteSpace($RainmeterLogPath)) {
        throw 'Rainmeter log path is empty.'
    }

    $logPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RainmeterLogPath))
    if (-not [System.IO.File]::Exists($logPath)) {
        Write-DmelPair 'DMEL_STATUS' 'OK'
        Write-DmelPair 'DMEL_OFFSET' '0'
        Write-DmelPair 'DMEL_ENTRY_COUNT' '0'
        return
    }

    $stream = [System.IO.File]::Open(
        $logPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $size = [long]$stream.Length
        $requestedStart = if ($Offset -gt $size) { 0L } else { [Math]::Max(0L, [long]$Offset) }
        if ($requestedStart -eq $size) {
            Write-DmelPair 'DMEL_STATUS' 'OK'
            Write-DmelPair 'DMEL_OFFSET' $size
            Write-DmelPair 'DMEL_ENTRY_COUNT' '0'
            return
        }

        $kind = Get-FileTextEncodingKind -Stream $stream
        $available = $size - $requestedStart
        $start = $requestedStart
        $truncated = $false
        if ($available -gt $MaxTailBytes) {
            $start = $size - $MaxTailBytes
            $truncated = $true
        }
        if (($kind -eq 'UTF16LE' -or $kind -eq 'UTF16BE') -and (($start % 2) -ne 0)) {
            $start--
        }

        $length = [int]($size - $start)
        $chunk = [byte[]]::new($length)
        $stream.Position = $start
        $totalRead = 0
        while ($totalRead -lt $chunk.Length) {
            $read = $stream.Read($chunk, $totalRead, $chunk.Length - $totalRead)
            if ($read -le 0) {
                break
            }
            $totalRead += $read
        }
        if ($totalRead -lt $chunk.Length) {
            $trimmed = [byte[]]::new($totalRead)
            if ($totalRead -gt 0) {
                [Array]::Copy($chunk, 0, $trimmed, 0, $totalRead)
            }
            $chunk = $trimmed
            $size = $start + $totalRead
        }
        $text = (Convert-BytesToText -Bytes $chunk -Kind $kind).TrimStart([char]0xFEFF)
        if ($truncated) {
            $firstNewLine = $text.IndexOf("`n", [System.StringComparison]::Ordinal)
            if ($firstNewLine -ge 0) {
                $text = $text.Substring($firstNewLine + 1)
            }
        }
    }
    finally {
        $stream.Dispose()
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '^([A-Z]+)\s+\((.*?)\)\s*(.*?):\s*(.*)$' -and $matches[1] -eq 'ERRO') {
            $entries.Add([PSCustomObject]@{
                Level = $matches[1]
                Time = $matches[2]
                Source = $matches[3]
                Message = $matches[4]
            })
            if ($entries.Count -gt $MaxEntries) {
                $entries.RemoveAt(0)
            }
        }
    }

    Write-DmelPair 'DMEL_STATUS' 'OK'
    Write-DmelPair 'DMEL_OFFSET' $size
    Write-DmelPair 'DMEL_TAIL_TRUNCATED' $(if ($truncated) { '1' } else { '0' })
    Write-DmelPair 'DMEL_ENTRY_COUNT' $entries.Count
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $number = $index + 1
        Write-DmelPair "DMEL_ENTRY_${number}_LEVEL" $entries[$index].Level
        Write-DmelPair "DMEL_ENTRY_${number}_TIME" $entries[$index].Time
        Write-DmelPair "DMEL_ENTRY_${number}_SOURCE" $entries[$index].Source
        Write-DmelPair "DMEL_ENTRY_${number}_MESSAGE" $entries[$index].Message
    }
}

try {
    if ($Mode -eq 'EnsureLogging') {
        Invoke-EnsureLogging
    }
    else {
        Invoke-TailLog
    }
}
catch {
    Write-DmelPair 'DMEL_STATUS' 'ERROR'
    Write-DmelPair 'DMEL_MESSAGE' $_.Exception.Message
}
