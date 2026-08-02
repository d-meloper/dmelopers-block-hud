[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TempRoot,
    [Parameter(Mandatory = $true)][string]$Reason,
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
    param([Parameter(Mandatory = $true)][string]$ParentRoot, [Parameter(Mandatory = $true)][string]$ChildPath)
    $rootFull = (Resolve-FullPath -Path $ParentRoot).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $ChildPath -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
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
        Root = $Root
        Reason = $Reason
        CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    }
    [System.IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 3), $utf8NoBom)
}

try {
    $resolvedRoot = Resolve-FullPath -Path $Root -AllowMissing
    $resolvedTempRoot = Resolve-FullPath -Path $TempRoot
    if (-not (Test-PathWithinRoot -ParentRoot $resolvedTempRoot -ChildPath $resolvedRoot) -or
        [string]::Equals($resolvedRoot, $resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a path outside TEMP: $resolvedRoot"
    }

    Set-Location ([System.IO.Path]::GetTempPath())
    $deadline = [DateTime]::UtcNow.AddSeconds($CleanupTimeoutSeconds)
    $lastError = $null
    do {
        try {
            if (Test-Path -LiteralPath $resolvedRoot) {
                Remove-Item -LiteralPath $resolvedRoot -Force -Recurse
            }
            Write-Result -Status 'OK' -Message 'Temporary old root deleted.'
            exit 0
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 250
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)

    Write-Result -Status 'TIMEOUT' -Message ("Temporary old-root cleanup did not finish within {0} seconds. Last error: {1}" -f $CleanupTimeoutSeconds, $lastError)
}
catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
}
