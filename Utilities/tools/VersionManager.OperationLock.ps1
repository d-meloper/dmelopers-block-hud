Set-StrictMode -Version 2.0

function Get-VersionManagerOperationSkinsRoot {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $resolvedTargetRoot = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd('\', '/')
    foreach ($candidate in @(
        (Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'),
        (Join-Path $env:LOCALAPPDATA 'Rainmeter\Rainmeter.ini')
    )) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            [byte[]]$bytes = [System.IO.File]::ReadAllBytes($candidate)
            $text = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
            }
            else { [System.Text.Encoding]::UTF8.GetString($bytes) }
            $inRainmeter = $false
            foreach ($line in ($text -split "`r?`n")) {
                $trimmed = ([string]$line).Trim()
                if ($trimmed -match '^\[(.+)\]$') { $inRainmeter = [string]::Equals($matches[1], 'Rainmeter', [System.StringComparison]::OrdinalIgnoreCase); continue }
                if ($inRainmeter -and $trimmed -match '^SkinPath=(.*)$') {
                    $path = [Environment]::ExpandEnvironmentVariables($matches[1].Trim())
                    if (Test-Path -LiteralPath $path -PathType Container) { return [System.IO.Path]::GetFullPath($path).TrimEnd('\', '/') }
                }
            }
        }
        catch { }
    }
    return [System.IO.Path]::GetFullPath((Split-Path -Parent $resolvedTargetRoot)).TrimEnd('\', '/')
}

function Get-VersionManagerOperationMutexName {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)
    $skinsRoot = (Get-VersionManagerOperationSkinsRoot -TargetRoot $TargetRoot).ToUpperInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash((New-Object System.Text.UTF8Encoding($false)).GetBytes($skinsRoot)) }
    finally { $sha.Dispose() }
    $hex = ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 32)
    return ('Local\DMeloperBlockHud.VersionMutation.' + $hex)
}

function Enter-VersionManagerOperationMutex {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)
    $name = Get-VersionManagerOperationMutexName -TargetRoot $TargetRoot
    $mutex = New-Object System.Threading.Mutex($false, $name)
    $acquired = $false
    $abandoned = $false
    try {
        try { $acquired = $mutex.WaitOne(0, $false) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true; $abandoned = $true }
        return [PSCustomObject]@{ Name = $name; Mutex = $mutex; Acquired = [bool]$acquired; Abandoned = [bool]$abandoned }
    }
    catch { $mutex.Dispose(); throw }
}

function Exit-VersionManagerOperationMutex {
    param([AllowNull()]$Lock)
    if ($null -eq $Lock) { return }
    try { if ([bool]$Lock.Acquired) { $Lock.Mutex.ReleaseMutex() } }
    catch { }
    finally { try { $Lock.Mutex.Dispose() } catch { } }
}
