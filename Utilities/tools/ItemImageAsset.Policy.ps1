# Shared Block HUD item-image asset-name policy.
# Dot-source this file from runtime helpers that create or consume item image names.

function Get-BlockHudSupportedItemImageExtensions {
    return @('.png', '.jpg', '.jpeg', '.jpe', '.bmp', '.gif', '.tif', '.tiff', '.ico', '.jxr', '.wdp', '.dds')
}

function ConvertTo-BlockHudItemImageAssetName {
    param(
        [AllowNull()][string]$Value,
        [switch]$AppendDefaultExtension,
        [switch]$AllowReservedRuntimeAsset
    )

    $asset = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($asset)) {
        return ''
    }

    $deviceStem = ($asset -split '[.]', 2)[0]
    if ($asset -eq '.' -or $asset -eq '..' -or
        $asset.IndexOfAny([char[]]@('/', '\')) -ge 0 -or
        $asset.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $asset -match '[#\[\]";|:<>?*]' -or
        $deviceStem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$' -or
        [System.IO.Path]::IsPathRooted($asset) -or
        $asset.EndsWith('.', [System.StringComparison]::Ordinal) -or
        $asset.EndsWith(' ', [System.StringComparison]::Ordinal) -or
        -not [string]::Equals([System.IO.Path]::GetFileName($asset), $asset, [System.StringComparison]::Ordinal)) {
        return ''
    }

    $extension = [System.IO.Path]::GetExtension($asset)
    if ([string]::IsNullOrWhiteSpace($extension) -and $AppendDefaultExtension) {
        $asset += '.png'
        $extension = '.png'
    }

    if ([string]::IsNullOrWhiteSpace($extension) -or
        (Get-BlockHudSupportedItemImageExtensions) -notcontains $extension.ToLowerInvariant()) {
        return ''
    }

    if (-not $AllowReservedRuntimeAsset -and
        [string]::Equals($asset, 'more.png', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    return $asset
}

function Test-BlockHudItemImageAssetName {
    param(
        [AllowNull()][string]$Value,
        [switch]$AppendDefaultExtension,
        [switch]$AllowReservedRuntimeAsset
    )

    return -not [string]::IsNullOrWhiteSpace((ConvertTo-BlockHudItemImageAssetName -Value $Value -AppendDefaultExtension:$AppendDefaultExtension -AllowReservedRuntimeAsset:$AllowReservedRuntimeAsset))
}

function Resolve-BlockHudItemImageAssetPath {
    param(
        [Parameter(Mandatory = $true)][string]$ItemImageDirectory,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [switch]$AllowReservedRuntimeAsset
    )

    $safeAsset = ConvertTo-BlockHudItemImageAssetName -Value $AssetName -AllowReservedRuntimeAsset:$AllowReservedRuntimeAsset
    if ([string]::IsNullOrWhiteSpace($safeAsset)) {
        throw "Invalid Block HUD item image asset name: $AssetName"
    }

    $directoryFullPath = [System.IO.Path]::GetFullPath($ItemImageDirectory).TrimEnd([char[]]@('\', '/'))
    $assetFullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($directoryFullPath, $safeAsset))
    $assetParent = [System.IO.Path]::GetDirectoryName($assetFullPath).TrimEnd([char[]]@('\', '/'))
    if (-not [string]::Equals($assetParent, $directoryFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Block HUD item image asset escaped its owning directory: $AssetName"
    }

    return $assetFullPath
}
