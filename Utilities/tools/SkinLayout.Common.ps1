Set-StrictMode -Version 2.0

function Resolve-BlockHudFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-BlockHudSkinRoot {
    param([Parameter(Mandatory = $true)][string]$StartPath)

    $candidate = Resolve-BlockHudFullPath -Path $StartPath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidate = Split-Path -Parent $candidate
    }

    for ($depth = 0; $depth -lt 10; $depth++) {
        $resources = Join-Path $candidate '@Resources'
        if (Test-Path -LiteralPath $resources -PathType Container) {
            return $candidate
        }

        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $candidate = $parent
    }

    throw "Could not resolve the Block HUD skin root from: $StartPath"
}

function Get-BlockHudLayoutContractPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-Path (Resolve-BlockHudFullPath -Path $Root) '@Resources\Defaults\Runtime\SkinLayoutContract.json'
}

function Get-BlockHudLayoutContract {
    param([Parameter(Mandatory = $true)][string]$Root)

    $path = Get-BlockHudLayoutContractPath -Root $Root
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    try {
        $raw = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false, $true)))
        $contract = $raw | ConvertFrom-Json
    }
    catch {
        throw "Skin layout contract is invalid: $path. $($_.Exception.Message)"
    }

    $version = 0
    if ($null -ne $contract.layoutContractVersion) {
        [void][int]::TryParse([string]$contract.layoutContractVersion, [ref]$version)
    }
    if ($version -lt 2) {
        throw "Skin layout contract version must be 2 or newer: $path"
    }

    return $contract
}

function Get-BlockHudContractString {
    param(
        [AllowNull()]$Contract,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [Parameter(Mandatory = $true)][string]$Fallback
    )

    if ($null -ne $Contract) {
        $property = $Contract.PSObject.Properties[$PropertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return ([string]$property.Value).Trim('\', '/')
        }
    }
    return $Fallback.Trim('\', '/')
}

function Resolve-BlockHudLayoutRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ContractProperty,
        [Parameter(Mandatory = $true)][string]$CanonicalRelativePath,
        [Parameter(Mandatory = $true)][string]$LegacyRelativePath,
        [ValidateSet('Any', 'Leaf', 'Container')][string]$PathType = 'Any',
        [switch]$AllowMissing
    )

    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    $contract = Get-BlockHudLayoutContract -Root $resolvedRoot
    $canonical = Get-BlockHudContractString -Contract $contract -PropertyName $ContractProperty -Fallback $CanonicalRelativePath
    $candidates = @($canonical, $LegacyRelativePath.Trim('\', '/')) | Select-Object -Unique

    foreach ($relative in $candidates) {
        $path = Join-Path $resolvedRoot $relative
        $exists = switch ($PathType) {
            'Leaf' { Test-Path -LiteralPath $path -PathType Leaf }
            'Container' { Test-Path -LiteralPath $path -PathType Container }
            default { Test-Path -LiteralPath $path }
        }
        if ($exists) {
            return $relative
        }
    }

    if ($AllowMissing -or $null -ne $contract) {
        return $canonical
    }
    return $LegacyRelativePath.Trim('\', '/')
}

function Get-BlockHudSettingsRelativePath {
    param([Parameter(Mandatory = $true)][string]$Root, [switch]$AllowMissing)

    Resolve-BlockHudLayoutRelativePath -Root $Root -ContractProperty 'settingsRelativePath' -CanonicalRelativePath 'HUD\Settings' -LegacyRelativePath 'Settings' -PathType Container -AllowMissing:$AllowMissing
}

function Get-BlockHudSettingsIniPath {
    param([Parameter(Mandatory = $true)][string]$Root, [switch]$AllowMissing)

    $relative = Get-BlockHudSettingsRelativePath -Root $Root -AllowMissing:$AllowMissing
    Join-Path (Resolve-BlockHudFullPath -Path $Root) (Join-Path $relative 'Settings.ini')
}

function Get-BlockHudRuntimeToolsRelativePath {
    param([Parameter(Mandatory = $true)][string]$Root, [switch]$AllowMissing)

    Resolve-BlockHudLayoutRelativePath -Root $Root -ContractProperty 'runtimeToolsRelativePath' -CanonicalRelativePath 'Utilities\tools' -LegacyRelativePath 'tools' -PathType Container -AllowMissing:$AllowMissing
}

function Get-BlockHudRuntimeToolPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativeToolPath,
        [switch]$AllowMissing
    )

    $tools = Get-BlockHudRuntimeToolsRelativePath -Root $Root -AllowMissing:$AllowMissing
    Join-Path (Resolve-BlockHudFullPath -Path $Root) (Join-Path $tools $RelativeToolPath)
}

function Get-BlockHudBootstrapRelativePath {
    param([Parameter(Mandatory = $true)][string]$Root, [switch]$AllowMissing)

    Resolve-BlockHudLayoutRelativePath -Root $Root -ContractProperty 'bootstrapRelativePath' -CanonicalRelativePath 'Utilities\Bootstrap' -LegacyRelativePath 'Bootstrap' -PathType Container -AllowMissing:$AllowMissing
}

function Get-BlockHudConfigRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$CanonicalRelativePath,
        [Parameter(Mandatory = $true)][string]$LegacyRelativePath,
        [switch]$AllowMissing
    )

    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    $contract = Get-BlockHudLayoutContract -Root $resolvedRoot
    $canonical = $CanonicalRelativePath
    if ($null -ne $contract -and $null -ne $contract.configs) {
        $property = $contract.configs.PSObject.Properties[$Id]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $canonical = [string]$property.Value
        }
    }

    foreach ($relative in @($canonical, $LegacyRelativePath) | Select-Object -Unique) {
        if (Test-Path -LiteralPath (Join-Path $resolvedRoot $relative) -PathType Container) {
            return $relative.Trim('\', '/')
        }
    }
    if ($AllowMissing -or $null -ne $contract) {
        return $canonical.Trim('\', '/')
    }
    return $LegacyRelativePath.Trim('\', '/')
}

function ConvertTo-BlockHudConfigRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowNull()][string]$LegacyRelativePath,
        [switch]$AllowMissing
    )

    $relative = ([string]$LegacyRelativePath).Trim('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative)) {
        return $relative
    }

    $parts = $relative -split '[\\/]', 2
    $top = $parts[0]
    $tail = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    $hudIds = @('Clock', 'ClockSprite', 'Editor', 'Hotbar', 'Indicators', 'Inventory', 'InventoryBG', 'Settings')
    $utilityIds = @('Bootstrap', 'Diagnostics', 'Modal')

    if ($hudIds -contains $top) {
        $canonicalTop = Get-BlockHudConfigRelativePath -Root $Root -Id $top -CanonicalRelativePath (Join-Path 'HUD' $top) -LegacyRelativePath $top -AllowMissing:$AllowMissing
    }
    elseif ($utilityIds -contains $top) {
        $canonicalTop = Get-BlockHudConfigRelativePath -Root $Root -Id $top -CanonicalRelativePath (Join-Path 'Utilities' $top) -LegacyRelativePath $top -AllowMissing:$AllowMissing
    }
    else {
        return $relative
    }

    if ([string]::IsNullOrWhiteSpace($tail)) {
        return $canonicalTop
    }
    return (Join-Path $canonicalTop $tail)
}

function Test-BlockHudSkinRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot '@Resources\Customs') -PathType Container)) {
        return $false
    }

    $settings = Get-BlockHudSettingsIniPath -Root $resolvedRoot
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        return $false
    }

    foreach ($spec in @(
        @{ Id = 'Hotbar'; Canonical = 'HUD\Hotbar'; Legacy = 'Hotbar'; File = 'Hotbar.ini' },
        @{ Id = 'Inventory'; Canonical = 'HUD\Inventory'; Legacy = 'Inventory'; File = 'Inventory.ini' }
    )) {
        $relative = Get-BlockHudConfigRelativePath -Root $resolvedRoot -Id $spec.Id -CanonicalRelativePath $spec.Canonical -LegacyRelativePath $spec.Legacy
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot (Join-Path $relative $spec.File)) -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Get-BlockHudFixedRootRequiredRelativePaths {
    @(
        '@Resources\Defaults\Runtime\SkinLayoutContract.json'
        '@Resources\Defaults\Runtime\images\clockSpriteSheet.png'
        '@Resources\Defaults\Runtime\images\playerLookAtlas.png'
        '@Resources\Defaults\Runtime\images\playerSteveStatic.png'
        '@Resources\Defaults\Runtime\images\hotbar.png'
        '@Resources\Defaults\Runtime\images\inv.png'
        'HUD\Settings\Settings.ini'
        'HUD\Hotbar\Hotbar.ini'
        'HUD\Inventory\Inventory.ini'
        'Utilities\Bootstrap\ZPosBootstrap.ini'
        'Utilities\Bootstrap\ZPosBootstrap.lua'
        'Utilities\Diagnostics\Diagnostics.ini'
        'Utilities\Diagnostics\Diagnostics.lua'
        'Utilities\LatestUpdate\LatestUpdate.ini'
        'Utilities\LatestUpdate\LatestUpdate.lua'
        'Utilities\MousePluginUpdate\MousePluginUpdate.ini'
        'Utilities\MousePluginUpdate\MousePluginUpdate.lua'
        'Utilities\Modal\Modal.ini'
        'Utilities\Modal\Modal.lua'
        'Utilities\tools\DefaultItemLocalization.Common.ps1'
        'Utilities\tools\GetVersionReleaseCatalog.ps1'
        'Utilities\tools\ImportFromOldVersion.ps1'
        'Utilities\tools\ImportFromOldVersion\AssetsAndRollback.ps1'
        'Utilities\tools\ImportFromOldVersion\CoreDiscovery.ps1'
        'Utilities\tools\ImportFromOldVersion\InteractiveSourceSelection.ps1'
        'Utilities\tools\ImportFromOldVersion\ItemImageRepair.ps1'
        'Utilities\tools\ImportFromOldVersion\JukeboxAndProgress.ps1'
        'Utilities\tools\ImportFromOldVersion\MousePluginUpdate.ps1'
        'Utilities\tools\ImportFromOldVersion\PlayerEditorAndRun.ps1'
        'Utilities\tools\ImportFromOldVersion\SettingsLayoutAndImages.ps1'
        'Utilities\tools\ImportFromOldVersion\VariablesAndCompatibility.ps1'
        'Utilities\tools\InstallVersionRelease.PackageTransport.ps1'
        'Utilities\tools\InstallVersionRelease.ps1'
        'Utilities\tools\ItemImageAsset.Policy.ps1'
        'Utilities\tools\LatestUpdate.Common.ps1'
        'Utilities\tools\LatestUpdateSession.ps1'
        'Utilities\tools\Localization.Common.ps1'
        'Utilities\tools\LowSpecSettings.Policy.ps1'
        'Utilities\tools\OpenSettingsLogFolder.ps1'
        'Utilities\tools\OpenVersionManager.ps1'
        'Utilities\tools\OpenVersionManager\ConfigurationAndInstallations.ps1'
        'Utilities\tools\OpenVersionManager\CoreProcessAndPaths.ps1'
        'Utilities\tools\OpenVersionManager\DialogsActionsAndHelpers.ps1'
        'Utilities\tools\OpenVersionManager\InteractiveModuleLoader.ps1'
        'Utilities\tools\OpenVersionManager\MainForm.ps1'
        'Utilities\tools\OpenVersionManager\SessionLaunch.ps1'
        'Utilities\tools\Remove-LegacyLayoutTransportAdapter.ps1'
        'Utilities\tools\MousePluginUpdateLauncher.ps1'
        'Utilities\tools\MousePluginUpdateSession.ps1'
        'Utilities\tools\SkinLayout.Common.ps1'
        'Utilities\tools\StartLatestUpdate.ps1'
        'Utilities\tools\SwitchActiveSkinVersion.ps1'
        'Utilities\tools\Update-DefaultItemLabels.ps1'
        'Utilities\tools\UpdateHelperLocalizationCache.ps1'
        'Utilities\tools\UpdateToLatestVersion.ps1'
        'Utilities\tools\UpdateToLatestVersion\CleanupOldRoot.ps1'
        'Utilities\tools\UpdateToLatestVersion\CleanupTempRoot.ps1'
        'Utilities\tools\UpdateToLatestVersion\CorePathsAndPackage.ps1'
        'Utilities\tools\UpdateToLatestVersion\ReplacementAndSwitch.ps1'
        'Utilities\tools\UpdateToLatestVersion\CurrentVersionDataReset.ps1'
        'Utilities\tools\UpdateToLatestVersion\ResetRecovery.ps1'
        'Utilities\tools\UpdateToLatestVersion\ResetRecoveryGuard.ps1'
        'Utilities\tools\VersionManager.OperationLock.ps1'
        'Utilities\tools\VersionManager.ReleaseCatalog.ps1'
        'Utilities\tools\VersionManager.ReleaseIdentity.ps1'
        'Utilities\tools\VersionManager.UiState.ps1'
        'Utilities\tools\VersionManager.UpdateCache.ps1'
    )
}

function Get-BlockHudFixedRootHandoffPaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    $dataRoot = Join-Path (Resolve-BlockHudFullPath -Path $Root) '@Resources\Customs\Data'
    return [PSCustomObject]@{
        DataRoot = $dataRoot
        RequestPath = Join-Path $dataRoot 'FixedRootActivationRequest.json'
        AckPath = Join-Path $dataRoot 'FixedRootActivationAck.json'
    }
}

function Get-BlockHudSha256Hex {
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

function Assert-BlockHudFixedRootRuntimeContract {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$RequireTransportAdapter,
        [switch]$RequireTransportAdapterAbsent,
        [switch]$AllowMissingManagerLocalResetHelper
    )

    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    foreach ($relativeDirectory in @('@Resources', 'HUD', 'Utilities', 'ExtraContent')) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot $relativeDirectory) -PathType Container)) {
            throw "$Context is missing the required directory: $relativeDirectory"
        }
    }
    foreach ($relativePath in @(Get-BlockHudFixedRootRequiredRelativePaths)) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot $relativePath) -PathType Leaf)) {
            if ($AllowMissingManagerLocalResetHelper -and
                [string]::Equals(
                    $relativePath,
                    'Utilities\tools\UpdateToLatestVersion\CurrentVersionDataReset.ps1',
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            throw "$Context is missing the required runtime file: $relativePath"
        }
    }

    $contract = Get-BlockHudLayoutContract -Root $resolvedRoot
    if ($null -eq $contract -or $null -eq $contract.legacyTransportAdapter) {
        throw "$Context does not define the legacy transport adapter contract."
    }
    $manifestRelativePath = [string]$contract.legacyTransportAdapter.manifestRelativePath
    if ([string]::IsNullOrWhiteSpace($manifestRelativePath)) {
        throw "$Context has an empty legacy transport adapter manifest path."
    }
    $manifestPath = Join-Path $resolvedRoot $manifestRelativePath
    if ($RequireTransportAdapter -and -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "$Context is missing the signed legacy transport adapter manifest: $manifestRelativePath"
    }
    if ($RequireTransportAdapter) {
        try {
            $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        }
        catch {
            throw "$Context has an invalid legacy transport adapter manifest: $($_.Exception.Message)"
        }
        $adapter = $contract.legacyTransportAdapter
        if ([int]$manifest.adapterContractVersion -ne 1 -or
            -not [string]::Equals([string]$manifest.marker, [string]$adapter.marker, [System.StringComparison]::Ordinal)) {
            throw "$Context has a legacy transport adapter manifest with the wrong identity."
        }
        $listed = @{}
        foreach ($entry in @($manifest.files)) {
            $relativePath = ([string]$entry.relativePath).Trim('\', '/')
            if ([string]::IsNullOrWhiteSpace($relativePath) -or $listed.ContainsKey($relativePath)) {
                throw "$Context has a duplicate or empty legacy transport adapter manifest entry."
            }
            $listed[$relativePath] = $entry
        }
        $expectedFiles = @($adapter.files)
        if ($listed.Count -ne $expectedFiles.Count) {
            throw "$Context does not contain the exact legacy transport adapter file set."
        }
        foreach ($spec in $expectedFiles) {
            $relativePath = ([string]$spec.relativePath).Trim('\', '/')
            if (-not $listed.ContainsKey($relativePath) -or
                -not [string]::Equals([string]$listed[$relativePath].kind, [string]$spec.kind, [System.StringComparison]::Ordinal)) {
                throw "$Context has an unexpected legacy transport adapter entry: $relativePath"
            }
            $path = Join-Path $resolvedRoot $relativePath
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "$Context is missing a signed legacy transport adapter file: $relativePath"
            }
            if (-not [string]::Equals((Get-BlockHudSha256Hex -Path $path), [string]$listed[$relativePath].sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "$Context has a modified legacy transport adapter file: $relativePath"
            }
        }
    }
    if ($RequireTransportAdapterAbsent -and (Test-Path -LiteralPath $manifestPath)) {
        throw "$Context still contains the legacy transport adapter manifest after Bootstrap cleanup: $manifestRelativePath"
    }
    if ($RequireTransportAdapterAbsent) {
        foreach ($spec in @($contract.legacyTransportAdapter.files)) {
            $relativePath = ([string]$spec.relativePath).Trim('\', '/')
            if (Test-Path -LiteralPath (Join-Path $resolvedRoot $relativePath)) {
                throw "$Context still contains a legacy transport adapter file after Bootstrap cleanup: $relativePath"
            }
        }
    }
}

function New-BlockHudFixedRootImmutableSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    Assert-BlockHudFixedRootRuntimeContract -Root $resolvedRoot -Context $Context
    $relativePaths = New-Object System.Collections.Generic.List[string]
    $utilitiesRoot = Join-Path $resolvedRoot 'Utilities'
    foreach ($file in @(Get-ChildItem -LiteralPath $utilitiesRoot -File -Recurse -Force | Sort-Object FullName)) {
        [void]$relativePaths.Add($file.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/'))
    }
    foreach ($relativePath in @(Get-BlockHudFixedRootRequiredRelativePaths)) {
        if (-not $relativePath.StartsWith('Utilities\', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $relativePaths.Contains($relativePath)) {
            [void]$relativePaths.Add($relativePath)
        }
    }

    $files = @()
    foreach ($relativePath in @($relativePaths | Sort-Object -Unique)) {
        $path = Join-Path $resolvedRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "$Context changed while its immutable file snapshot was being captured: $relativePath"
        }
        $files += [PSCustomObject]@{
            RelativePath = $relativePath
            Sha256 = Get-BlockHudSha256Hex -Path $path
        }
    }
    return [PSCustomObject]@{
        Files = @($files)
        UtilitiesFileCount = @($files | Where-Object { $_.RelativePath.StartsWith('Utilities\', [System.StringComparison]::OrdinalIgnoreCase) }).Count
    }
}

function Assert-BlockHudFixedRootImmutableSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $resolvedRoot = Resolve-BlockHudFullPath -Path $Root
    $expected = @{}
    foreach ($entry in @($Snapshot.Files)) {
        $relativePath = [string]$entry.RelativePath
        $expected[$relativePath] = [string]$entry.Sha256
        $path = Join-Path $resolvedRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "$Context lost an immutable runtime file: $relativePath"
        }
        $actualHash = Get-BlockHudSha256Hex -Path $path
        if (-not [string]::Equals($actualHash, [string]$entry.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "$Context changed an immutable runtime file: $relativePath"
        }
    }

    $actualUtilities = @(Get-ChildItem -LiteralPath (Join-Path $resolvedRoot 'Utilities') -File -Recurse -Force |
        ForEach-Object { $_.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/') })
    if ($actualUtilities.Count -ne [int]$Snapshot.UtilitiesFileCount) {
        throw ("{0} changed the canonical Utilities file set. expected={1} actual={2}" -f $Context, [int]$Snapshot.UtilitiesFileCount, $actualUtilities.Count)
    }
    foreach ($relativePath in $actualUtilities) {
        if (-not $expected.ContainsKey([string]$relativePath)) {
            throw "$Context added an unexpected canonical Utilities file: $relativePath"
        }
    }
}
