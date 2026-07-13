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
