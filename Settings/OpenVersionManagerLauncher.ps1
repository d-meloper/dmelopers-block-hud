[CmdletBinding()]
param(
    [string]$TargetRoot = '..',
    [string]$LaunchToken = '',
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}
catch {
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    [Console]::Out.WriteLine($Key + '=' + [string]$Value)
}

function Write-RainmeterLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Notice', 'Warning', 'Error')][string]$Level = 'Notice'
    )

    try {
        $rainmeter = Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
            Select-Object -First 1 -ExpandProperty Path
        if ([string]::IsNullOrWhiteSpace($rainmeter) -or -not (Test-Path -LiteralPath $rainmeter)) {
            return
        }
        & $rainmeter '!Log' ('[DMeloper Block HUD] VersionManagerLauncher ' + [string]$Message) $Level | Out-Null
    }
    catch {
    }
}

function Get-LauncherLogPath {
    try {
        $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $logsRoot = Join-Path $root 'Logs'
        if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
        }
        return (Join-Path $logsRoot "DMeloper's Block HUD Log.log")
    }
    catch {
        return ''
    }
}

function Write-LauncherFileLog {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][string]$Message = ''
    )

    try {
        $path = Get-LauncherLogPath
        if ([string]::IsNullOrWhiteSpace($path)) {
            return
        }
        $lines = @(
            '<VersionManagerLauncher>',
            ('timeUtc={0}' -f ((Get-Date).ToUniversalTime().ToString('o'))),
            ('stage={0}' -f $Stage),
            ('pid={0}' -f $PID),
            ('scriptRoot={0}' -f $PSScriptRoot),
            ('targetRoot={0}' -f [string]$TargetRoot),
            ('launchToken={0}' -f [string]$LaunchToken),
            ('message={0}' -f [string]$Message),
            '</VersionManagerLauncher>',
            ''
        )
        [System.IO.File]::AppendAllText($path, [string]::Join("`r`n", $lines), $utf8NoBom)
    }
    catch {
    }
}

function Emit-LauncherFailure {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-LauncherFileLog -Stage 'error' -Message $Message
    Write-RainmeterLog -Message ('ERROR ' + $Message) -Level 'Error'
    if ($EmitResultPairs) {
        Write-OutputPair -Key 'DMEL_STATUS' -Value 'ERROR'
        Write-OutputPair -Key 'DMEL_MESSAGE' -Value $Message
        Write-OutputPair -Key 'DMEL_LOGPATH' -Value (Get-LauncherLogPath)
    }
}

try {
    Write-LauncherFileLog -Stage 'start' -Message 'Settings launcher wrapper started.'
    Write-RainmeterLog -Message ('start launchToken=' + [string]$LaunchToken) -Level 'Notice'

    $helperPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\tools\OpenVersionManager.ps1'))
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw ("OpenVersionManager helper was not found: {0}" -f $helperPath)
    }

    $arguments = @(
        '-TargetRoot',
        $TargetRoot,
        '-LaunchToken',
        $LaunchToken
    )
    if ($EmitResultPairs) {
        $arguments += '-EmitResultPairs'
    }

    $output = @(& $helperPath @arguments 2>&1)
    $hasStatus = $false
    foreach ($line in @($output)) {
        $text = [string]$line
        if ($text -match '^DMEL_STATUS=') {
            $hasStatus = $true
        }
        [Console]::Out.WriteLine($text)
    }

    if (-not $hasStatus) {
        $preview = (($output | ForEach-Object { [string]$_ }) -join ' | ')
        if ($preview.Length -gt 600) {
            $preview = $preview.Substring(0, 600) + '...'
        }
        if ([string]::IsNullOrWhiteSpace($preview)) {
            $preview = 'OpenVersionManager helper returned no stdout.'
        }
        Emit-LauncherFailure -Message ('OpenVersionManager helper returned no DMEL_STATUS. ' + $preview)
    }
}
catch {
    Emit-LauncherFailure -Message $_.Exception.Message
}
