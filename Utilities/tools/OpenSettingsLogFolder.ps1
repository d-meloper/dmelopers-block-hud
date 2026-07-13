[CmdletBinding()]
param(
    [string]$TargetRoot,
    [switch]$EmitResultPairs,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'SkinLayout.Common.ps1')

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:ResolvedTargetRoot = ''
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
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
    if (-not $EmitResultPairs) {
        return
    }

    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    foreach ($key in @('DMEL_STATUS', 'DMEL_SOURCEPATH', 'DMEL_BACKUPPATH', 'DMEL_LOGPATH', 'DMEL_MESSAGE')) {
        Write-OutputPair -Key $key -Value $script:ResultPairs[$key]
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] {1}' -f $Level, $Message
    $script:LogMessages.Add($line)
    Write-Host $line
}

function Save-Log {
    $parent = Split-Path -Parent $script:LogPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'OpenSettingsLogFolder' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    Write-Host ("Log: {0}" -f $script:LogPath)
}

function Format-DiagnosticValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return '<null>'
    }

    $text = [string]$Value
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $text.ToCharArray()) {
        $code = [int][char]$character
        if ($code -lt 32) {
            [void]$builder.Append(('<U+{0:X4}>' -f $code))
        }
        else {
            [void]$builder.Append($character)
        }
    }

    $result = $builder.ToString()
    if ($result.Length -gt 180) {
        return $result.Substring(0, 180) + '...'
    }
    return $result
}

function Normalize-PathArgument {
    param([AllowNull()][string]$Path)

    if ($null -eq $Path) {
        return ''
    }

    $normalized = ([string]$Path).Replace([string][char]0, '').Trim()
    do {
        $previous = $normalized
        if ($normalized.Length -ge 2) {
            $first = $normalized[0]
            $last = $normalized[$normalized.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $normalized = $normalized.Substring(1, $normalized.Length - 2).Trim()
            }
        }
    } while ($normalized -ne $previous)

    return $normalized
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    $normalizedPath = Normalize-PathArgument -Path $Path
    $expanded = Normalize-PathArgument -Path ([Environment]::ExpandEnvironmentVariables($normalizedPath))
    if ([string]::IsNullOrWhiteSpace($expanded)) {
        throw 'Path is empty.'
    }

    if ([System.IO.Path]::IsPathRooted($expanded)) {
        $full = [System.IO.Path]::GetFullPath($expanded)
    }
    else {
        $full = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $expanded))
    }

    $full = $full.TrimEnd('\', '/')
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Path does not exist: $full"
    }

    return $full
}

function Join-RootPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    return (Join-Path $Root $RelativePath)
}

function Test-SkinRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Test-BlockHudSkinRoot -Root $Root)
}

function Resolve-PreferredLogDirectory {
    param([AllowNull()][string]$RequestedTargetRoot)

    if ([string]::IsNullOrWhiteSpace($RequestedTargetRoot)) {
        return (Split-Path -Parent (Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot))
    }

    try {
        $normalizedRequestedTargetRoot = Normalize-PathArgument -Path $RequestedTargetRoot
        if ($normalizedRequestedTargetRoot -ne [string]$RequestedTargetRoot) {
            Write-Log ("Normalized TargetRoot argument for log folder open: raw={0}; normalized={1}" -f (Format-DiagnosticValue -Value $RequestedTargetRoot), (Format-DiagnosticValue -Value $normalizedRequestedTargetRoot))
        }

        $resolvedTargetRoot = Resolve-FullPath -Path $normalizedRequestedTargetRoot
        $script:ResolvedTargetRoot = $resolvedTargetRoot
        if (-not (Test-SkinRoot -Root $resolvedTargetRoot)) {
            Write-Log "TargetRoot is not a valid skin root; falling back to script-root logs: $resolvedTargetRoot" 'WARN'
            return (Split-Path -Parent (Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot))
        }

        return (Join-RootPath -Root $resolvedTargetRoot -RelativePath 'Logs')
    }
    catch {
        Write-Log "Could not resolve TargetRoot for log folder open; falling back to script-root logs: $($_.Exception.Message)" 'WARN'
        return (Split-Path -Parent (Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot))
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Start-DetachedExplorer {
    param([Parameter(Mandatory = $true)][string]$Target)

    $windowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($windowsRoot)) {
        $windowsRoot = [Environment]::ExpandEnvironmentVariables('%SystemRoot%')
    }
    $explorerPath = [System.IO.Path]::Combine($windowsRoot, 'explorer.exe')
    if (-not [System.IO.File]::Exists($explorerPath)) {
        throw 'File Explorer is unavailable.'
    }

    $quotedTarget = '"' + $Target.Replace('"', '') + '"'
    Start-Process -FilePath $explorerPath -ArgumentList $quotedTarget -WindowStyle Normal | Out-Null
}

function Invoke-OpenLogFolder {
    $targetLogDirectory = Resolve-PreferredLogDirectory -RequestedTargetRoot $TargetRoot
    try {
        Ensure-Directory -Path $targetLogDirectory
    }
    catch {
        Write-Log "Preferred log directory could not be prepared; falling back to script-root logs: $($_.Exception.Message)" 'WARN'
        $targetLogDirectory = Split-Path -Parent (Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot)
        Ensure-Directory -Path $targetLogDirectory
    }

    $script:LogPath = Join-Path $targetLogDirectory (Get-BlockHudCanonicalLogFileName)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath

    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedTargetRoot)) {
        Write-Log "TargetRoot: $script:ResolvedTargetRoot"
    }
    Write-Log "LogFolder: $targetLogDirectory"

    if (-not $NoOpen) {
        Start-DetachedExplorer -Target $targetLogDirectory
    }
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Opened settings helper log folder.'
}

try {
    Invoke-OpenLogFolder
}
catch {
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.InvocationInfo) {
        Write-Log ("at {0}, {1}: line {2}" -f $_.InvocationInfo.MyCommand, $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber) 'ERROR'
    }
}
finally {
    Save-Log
    Emit-ResultPairs
}
