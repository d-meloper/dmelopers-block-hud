[CmdletBinding()]
param(
    [string]$SkinRoot,
    [string]$RootConfig,
    [string]$SettingsPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

. (Join-Path $PSScriptRoot 'SkinLayout.Common.ps1')

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Read-TextFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return ([System.Text.Encoding]::Unicode.GetString($bytes)).TrimStart([char]0xFEFF)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return ([System.Text.UTF8Encoding]::new($false, $true)).GetString($bytes, 3, $bytes.Length - 3)
    }
    try {
        return ([System.Text.UTF8Encoding]::new($false, $true)).GetString($bytes)
    }
    catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Complete-FixedRootActivationHandoffIfRequested {
    param([Parameter(Mandatory = $true)][string]$Root)

    $paths = Get-BlockHudFixedRootHandoffPaths -Root $Root
    if (-not (Test-Path -LiteralPath $paths.RequestPath -PathType Leaf)) {
        return
    }

    $request = [System.IO.File]::ReadAllText($paths.RequestPath, $utf8NoBom) | ConvertFrom-Json
    $token = [string]$request.Token
    $requestedRoot = [string]$request.CurrentRoot
    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    if ([int]$request.SchemaVersion -ne 1 -or $token -notmatch '^[a-f0-9]{32}$') {
        throw 'Fixed-root activation handoff request identity is invalid.'
    }
    if (-not [string]::Equals($requestedRoot, $resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixed-root activation handoff request targeted a different installed root.'
    }

    Assert-BlockHudFixedRootRuntimeContract `
        -Root $resolvedRoot `
        -Context 'Bootstrap-completed fixed root' `
        -RequireTransportAdapterAbsent
    $ack = [ordered]@{
        SchemaVersion = 1
        Token = $token
        CurrentRoot = $resolvedRoot
        Status = 'OK'
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    if (-not (Test-Path -LiteralPath $paths.DataRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $paths.DataRoot -Force | Out-Null
    }
    $temporaryPath = [string]$paths.AckPath + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, ($ack | ConvertTo-Json -Depth 3), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $paths.AckPath -Force
}

function Remove-FixedRootCompatibilityAssetsWhenSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Specs,
        [switch]$WaitForHandoffRequestRemoval,
        [ValidateRange(1, 120)][int]$TimeoutSeconds = 30
    )

    $existing = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @($Specs)) {
        if (-not [string]::Equals([string]$spec.kind, 'fixedRootCompatibilityAsset', [System.StringComparison]::Ordinal)) {
            throw "Unknown fixed-root compatibility asset kind: $([string]$spec.kind)"
        }
        $relativePath = ([string]$spec.relativePath).Trim('\', '/')
        $path = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        if (-not [string]::Equals((Get-Sha256Hex -Path $path), [string]$spec.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove modified or unsigned fixed-root compatibility asset: $relativePath"
        }
        [void]$existing.Add([PSCustomObject]@{
            RelativePath = $relativePath
            Path = $path
            Sha256 = [string]$spec.sha256
        })
    }
    if ($existing.Count -eq 0) {
        return
    }

    if ($WaitForHandoffRequestRemoval) {
        $paths = Get-BlockHudFixedRootHandoffPaths -Root $Root
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ((Test-Path -LiteralPath $paths.RequestPath -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
        if (Test-Path -LiteralPath $paths.RequestPath -PathType Leaf) {
            Write-Warning 'Fixed-root compatibility asset cleanup was deferred because the updater handoff request is still active.'
            return
        }
    }

    foreach ($asset in $existing) {
        if (-not (Test-Path -LiteralPath $asset.Path -PathType Leaf)) {
            continue
        }
        if (-not [string]::Equals((Get-Sha256Hex -Path $asset.Path), $asset.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove fixed-root compatibility asset changed during handoff: $($asset.RelativePath)"
        }
        Remove-Item -LiteralPath $asset.Path -Force
    }
}

function Resolve-RainmeterSettingsIniPath {
    param([AllowNull()][string]$Path)

    $candidate = ([string]$Path).Trim()
    if ($candidate -ne '' -and $candidate.IndexOf('#', [System.StringComparison]::Ordinal) -lt 0) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return Join-Path $candidate 'Rainmeter.ini'
        }
        return $candidate
    }

    $appData = [Environment]::GetFolderPath('ApplicationData')
    if (-not [string]::IsNullOrWhiteSpace($appData)) {
        return Join-Path $appData 'Rainmeter\Rainmeter.ini'
    }

    return ''
}

function Get-ActiveRainmeterConfigs {
    param([Parameter(Mandatory = $true)][string]$RainmeterIniPath)

    $active = @{}
    if ([string]::IsNullOrWhiteSpace($RainmeterIniPath) -or -not (Test-Path -LiteralPath $RainmeterIniPath -PathType Leaf)) {
        return $active
    }

    $section = ''
    foreach ($line in ((Read-TextFile -Path $RainmeterIniPath) -split "`r?`n")) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $section = $matches[1]
            continue
        }
        if ($section -ne '' -and $trimmed -match '^Active\s*=\s*([1-9][0-9]*)\s*$') {
            $active[$section] = $true
        }
    }
    return $active
}

function Find-RainmeterExe {
    $command = Get-Command 'Rainmeter.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return [string]$command.Source
    }

    foreach ($registryPath in @(
        'HKCU:\Software\Rainmeter',
        'HKLM:\Software\Rainmeter',
        'HKLM:\Software\WOW6432Node\Rainmeter'
    )) {
        try {
            $installPath = [string](Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop).InstallPath
            if (-not [string]::IsNullOrWhiteSpace($installPath)) {
                $candidate = Join-Path $installPath 'Rainmeter.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
        catch {
        }
    }

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($base)) {
            continue
        }
        $candidate = Join-Path $base 'Rainmeter\Rainmeter.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return ''
}

function Invoke-ActiveLegacyAdapterDeactivate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][hashtable]$ExpectedFiles,
        [AllowNull()][AllowEmptyString()][string]$ConfiguredRootName,
        [AllowNull()][string]$RainmeterIniPath
    )

    $rootName = ([string]$ConfiguredRootName).Trim('\', '/')
    if ([string]::IsNullOrWhiteSpace($rootName)) {
        $rootName = Split-Path -Leaf $Root
    }
    if ([string]::IsNullOrWhiteSpace($rootName)) {
        return
    }

    $rainmeterIni = Resolve-RainmeterSettingsIniPath -Path $RainmeterIniPath
    $activeConfigs = Get-ActiveRainmeterConfigs -RainmeterIniPath $rainmeterIni
    if ($activeConfigs.Count -eq 0) {
        return
    }

    $rainmeterExe = Find-RainmeterExe
    if ([string]::IsNullOrWhiteSpace($rainmeterExe)) {
        return
    }

    $relativeConfigs = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($relativePath in $ExpectedFiles.Keys) {
        if (-not ([string]$relativePath).EndsWith('.ini', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $relativeConfig = (Split-Path -Parent ([string]$relativePath)).Trim('\', '/')
        if ($relativeConfig -ne '') {
            [void]$relativeConfigs.Add($relativeConfig.Replace('/', '\'))
        }
    }

    $deactivated = 0
    foreach ($relativeConfig in $relativeConfigs) {
        $configName = $rootName + '\' + $relativeConfig
        if (-not $activeConfigs.ContainsKey($configName)) {
            continue
        }
        try {
            & $rainmeterExe '!DeactivateConfig' $configName | Out-Null
            $deactivated++
        }
        catch {
            Write-Warning "Could not deactivate active legacy adapter config '$configName': $($_.Exception.Message)"
        }
    }

    if ($deactivated -gt 0) {
        Write-Output "Legacy layout transport adapter active configs deactivated: $deactivated"
    }
}

$root = if ([string]::IsNullOrWhiteSpace($SkinRoot)) {
    Resolve-BlockHudSkinRoot -StartPath $PSScriptRoot
}
else {
    Resolve-BlockHudFullPath -Path $SkinRoot
}
$contract = Get-BlockHudLayoutContract -Root $root
if ($null -eq $contract -or $null -eq $contract.legacyTransportAdapter) {
    throw 'The installed layout contract does not define legacyTransportAdapter.'
}

$adapter = $contract.legacyTransportAdapter
$fixedRootCompatibilityAssets = @()
if ($adapter.PSObject.Properties.Name -contains 'fixedRootCompatibilityAssets') {
    $fixedRootCompatibilityAssets = @($adapter.fixedRootCompatibilityAssets)
}
$manifestPath = Join-Path $root ([string]$adapter.manifestRelativePath)
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $handoffPaths = Get-BlockHudFixedRootHandoffPaths -Root $root
    $handoffWasRequested = Test-Path -LiteralPath $handoffPaths.RequestPath -PathType Leaf
    Complete-FixedRootActivationHandoffIfRequested -Root $root
    Remove-FixedRootCompatibilityAssetsWhenSafe `
        -Root $root `
        -Specs $fixedRootCompatibilityAssets `
        -WaitForHandoffRequestRemoval:$handoffWasRequested
    Write-Output 'Legacy layout transport adapter is already absent.'
    exit 0
}

$manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
if ([int]$manifest.adapterContractVersion -ne 1 -or [string]$manifest.marker -ne [string]$adapter.marker) {
    throw 'Legacy layout transport adapter manifest identity did not match the installed contract.'
}

$expected = @{}
foreach ($spec in @($adapter.files)) {
    $expected[([string]$spec.relativePath).Trim('\', '/')] = [string]$spec.kind
}
$listed = @{}
foreach ($entry in @($manifest.files)) {
    $relativePath = ([string]$entry.relativePath).Trim('\', '/')
    if (-not $expected.ContainsKey($relativePath) -or $expected[$relativePath] -ne [string]$entry.kind) {
        throw "Unexpected adapter manifest entry: $relativePath"
    }
    $listed[$relativePath] = $entry
}
if ($listed.Count -ne $expected.Count) {
    throw 'Legacy layout transport adapter manifest does not contain the exact contracted file set.'
}

$unsafe = New-Object System.Collections.Generic.List[string]
foreach ($relativePath in $expected.Keys) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $entry = $listed[$relativePath]
    $actualHash = Get-Sha256Hex -Path $path
    if (-not [string]::Equals($actualHash, [string]$entry.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$unsafe.Add($relativePath)
        continue
    }
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.IndexOf([string]$adapter.marker, [System.StringComparison]::Ordinal) -lt 0) {
        [void]$unsafe.Add($relativePath)
    }
}
if ($unsafe.Count -gt 0) {
    throw ('Refusing to remove modified or unsigned legacy adapter files: ' + ($unsafe -join ', '))
}

Invoke-ActiveLegacyAdapterDeactivate -Root $root -ExpectedFiles $expected -ConfiguredRootName $RootConfig -RainmeterIniPath $SettingsPath

foreach ($relativePath in $expected.Keys) {
    $path = Join-Path $root $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force
    }
}
Remove-Item -LiteralPath $manifestPath -Force

$directories = @($expected.Keys | ForEach-Object { Split-Path -Parent (Join-Path $root $_) } | Sort-Object Length -Descending -Unique)
foreach ($directory in $directories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        continue
    }
    if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
        Remove-Item -LiteralPath $directory -Force
    }
    else {
        Write-Warning "Legacy adapter directory retained because it contains unexpected files: $directory"
    }
}

$handoffPaths = Get-BlockHudFixedRootHandoffPaths -Root $root
$handoffWasRequested = Test-Path -LiteralPath $handoffPaths.RequestPath -PathType Leaf
Complete-FixedRootActivationHandoffIfRequested -Root $root
Remove-FixedRootCompatibilityAssetsWhenSafe `
    -Root $root `
    -Specs $fixedRootCompatibilityAssets `
    -WaitForHandoffRequestRemoval:$handoffWasRequested
Write-Output 'Legacy layout transport adapter cleanup completed.'
