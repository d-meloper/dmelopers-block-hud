[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OldRoot,
    [Parameter(Mandatory = $true)][string]$SkinsRoot,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [int]$CleanupTimeoutSeconds = 20
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

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
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

function Test-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Path)
    $rootFull = (Resolve-FullPath -Path $Root).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $Path -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Write-Result {
    param([Parameter(Mandatory = $true)][string]$Status, [Parameter(Mandatory = $true)][string]$Message)
    $parent = Split-Path -Parent $ResultPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $payload = [PSCustomObject]@{
        Status = $Status
        Message = $Message
        OldRoot = $OldRoot
        CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    }
    [System.IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 3), $utf8NoBom)
}

try {
    $resolvedOldRoot = Resolve-FullPath -Path $OldRoot -AllowMissing
    $resolvedSkinsRoot = Resolve-FullPath -Path $SkinsRoot
    if (-not (Test-PathWithinRoot -Root $resolvedSkinsRoot -Path $resolvedOldRoot) -or
        [string]::Equals($resolvedOldRoot, $resolvedSkinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a path outside the Rainmeter skins root: $resolvedOldRoot"
    }

    # Do not wait on the helper parent here: Version Manager waits for this helper's
    # result, so waiting on that UI process makes successful cleanup impossible.
    # The detached runner owns deletion from TEMP and reports a bounded result instead.
    Set-Location ([System.IO.Path]::GetTempPath())
    $deadline = [DateTime]::UtcNow.AddSeconds($CleanupTimeoutSeconds)
    $lastError = $null
    do {
        try {
            if (Test-Path -LiteralPath $resolvedOldRoot) {
                Remove-Item -LiteralPath $resolvedOldRoot -Force -Recurse
            }
            Write-Result -Status 'OK' -Message 'Old root deleted.'
            exit 0
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 250
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)

    Write-Result -Status 'TIMEOUT' -Message ("Old-root cleanup did not finish within {0} seconds. Last error: {1}" -f $CleanupTimeoutSeconds, $lastError)
}
catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
}
