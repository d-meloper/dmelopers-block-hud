# Shared Block HUD item-image asset-name policy.
# Dot-source this file from runtime helpers that create or consume item image names.

function Get-BlockHudSupportedItemImageExtensions {
    return @('.png', '.jpg', '.jpeg', '.jpe', '.bmp', '.gif', '.tif', '.tiff', '.ico', '.jxr', '.wdp', '.dds')
}

function Test-BlockHudManagedItemGifAtlasName {
    param([AllowNull()][string]$Value)

    return ([string]$Value) -match '^(?i:ItemGifAtlas_v1_[0-9a-f]{16}_[0-9a-f]{16}\.png)$'
}

function Resolve-BlockHudItemGifAtlasPath {
    param(
        [Parameter(Mandatory = $true)][string]$ItemImageDirectory,
        [Parameter(Mandatory = $true)][string]$AtlasName
    )

    if (-not (Test-BlockHudManagedItemGifAtlasName -Value $AtlasName)) {
        throw "Invalid Block HUD item GIF atlas name: $AtlasName"
    }

    $root = [System.IO.Path]::GetFullPath($ItemImageDirectory).TrimEnd([char[]]@('\', '/'))
    $atlasDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, 'atlas'))
    $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($atlasDirectory, [string]$AtlasName))
    if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($path), $atlasDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Block HUD item GIF atlas escaped its owning directory: $AtlasName"
    }
    return $path
}

function Get-BlockHudItemGifAtlasProfilesValue {
    param([string]$ManifestPath)

    if ([string]::IsNullOrWhiteSpace($ManifestPath) -or -not [System.IO.File]::Exists($ManifestPath)) {
        return ''
    }

    $text = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::Unicode)
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^ItemImageAtlasProfiles=(.*)$') {
            return [string]$Matches[1]
        }
    }
    return ''
}

function ConvertFrom-BlockHudItemGifAtlasProfiles {
    param([AllowNull()][string]$Value)

    $entries = New-Object System.Collections.Generic.List[object]
    $invalid = New-Object System.Collections.Generic.List[string]
    $owners = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $atlasNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @(([string]$Value) -split '\|')) {
        if ([string]::IsNullOrWhiteSpace($record)) {
            continue
        }

        $fields = @($record -split '>', -1)
        $sourceName = ''
        $valid = $fields.Count -eq 11
        if ($valid) {
            $sourceName = ConvertTo-BlockHudItemImageAssetName -Value $fields[1]
            $sourceExtension = [System.IO.Path]::GetExtension($sourceName)
            $valid = $fields[0] -ceq 'v1' -and
                -not [string]::IsNullOrWhiteSpace($sourceName) -and
                $sourceExtension -ieq '.gif' -and
                (Test-BlockHudManagedItemGifAtlasName -Value $fields[2]) -and
                $fields[3] -match '^[0-9a-fA-F]{64}$' -and
                $fields[4] -match '^[0-9a-fA-F]{64}$' -and
                $fields[5] -match '^[1-9][0-9]*$' -and
                $fields[6] -match '^[1-9][0-9]*$' -and
                $fields[7] -match '^[1-9][0-9]*$' -and
                $fields[8] -match '^[1-9][0-9]*$' -and
                $fields[9] -match '^[1-9][0-9]*$' -and
                $fields[10] -ceq '50'
        }

        if ($valid) {
            $sourceFrames = [int]$fields[5]
            $expandedCells = [int]$fields[6]
            $columns = [int]$fields[7]
            $cellWidth = [int]$fields[8]
            $cellHeight = [int]$fields[9]
            $rows = [int][Math]::Ceiling($expandedCells / [double]$columns)
            $valid = $sourceFrames -ge 1 -and $sourceFrames -le 240 -and
                $expandedCells -ge $sourceFrames -and $expandedCells -le 512 -and
                $columns -le $expandedCells -and
                $cellWidth -le 64 -and $cellHeight -le 64 -and
                ($columns * $cellWidth) -le 2048 -and ($rows * $cellHeight) -le 2048 -and
                $owners.Add($sourceName) -and $atlasNames.Add([string]$fields[2])
        }

        if (-not $valid) {
            if ($fields.Count -eq 11 -and -not [string]::IsNullOrWhiteSpace($sourceName) -and
                (Test-BlockHudManagedItemGifAtlasName -Value $fields[2])) {
                for ($entryIndex = $entries.Count - 1; $entryIndex -ge 0; $entryIndex -= 1) {
                    if ([string]::Equals([string]$entries[$entryIndex].SourceName, $sourceName, [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals([string]$entries[$entryIndex].AtlasName, [string]$fields[2], [System.StringComparison]::OrdinalIgnoreCase)) {
                        $entries.RemoveAt($entryIndex)
                    }
                }
            }
            $invalid.Add([string]$record)
            continue
        }

        $entries.Add([PSCustomObject]@{
            Version = 'v1'
            SourceName = $sourceName
            AtlasName = [string]$fields[2]
            SourceSha256 = ([string]$fields[3]).ToLowerInvariant()
            AtlasSha256 = ([string]$fields[4]).ToLowerInvariant()
            SourceFrameCount = [int]$fields[5]
            ExpandedCellCount = [int]$fields[6]
            Columns = [int]$fields[7]
            CellWidth = [int]$fields[8]
            CellHeight = [int]$fields[9]
            TickMs = 50
        })
    }

    return [PSCustomObject]@{
        Entries = $entries.ToArray()
        InvalidRecords = $invalid.ToArray()
    }
}

function ConvertTo-BlockHudItemGifAtlasProfiles {
    param([AllowNull()][object[]]$Entries)

    $records = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($Entries | Sort-Object SourceName)) {
        if ($null -eq $entry) { continue }
        $records.Add(('v1>{0}>{1}>{2}>{3}>{4}>{5}>{6}>{7}>{8}>50' -f
            [string]$entry.SourceName,
            [string]$entry.AtlasName,
            ([string]$entry.SourceSha256).ToLowerInvariant(),
            ([string]$entry.AtlasSha256).ToLowerInvariant(),
            [int]$entry.SourceFrameCount,
            [int]$entry.ExpandedCellCount,
            [int]$entry.Columns,
            [int]$entry.CellWidth,
            [int]$entry.CellHeight))
    }
    return ($records.ToArray() -join '|')
}

function Test-BlockHudItemGifAtlasProfileFiles {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$ItemImageDirectory
    )

    try {
        $sourcePath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $ItemImageDirectory -AssetName ([string]$Entry.SourceName)
        $atlasPath = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $ItemImageDirectory -AtlasName ([string]$Entry.AtlasName)
        if (-not [System.IO.File]::Exists($atlasPath)) { return $false }
        if ([System.IO.File]::Exists($sourcePath) -and
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine [string]$Entry.SourceSha256) { return $false }
        if ((Get-FileHash -LiteralPath $atlasPath -Algorithm SHA256).Hash -ine [string]$Entry.AtlasSha256) { return $false }

        Add-Type -AssemblyName System.Drawing
        $image = $null
        try {
            $image = [System.Drawing.Image]::FromFile($atlasPath)
            $rows = [int][Math]::Ceiling(([int]$Entry.ExpandedCellCount) / [double]([int]$Entry.Columns))
            return $image.RawFormat.Guid -eq [System.Drawing.Imaging.ImageFormat]::Png.Guid -and
                $image.Width -eq ([int]$Entry.Columns * [int]$Entry.CellWidth) -and
                $image.Height -eq ($rows * [int]$Entry.CellHeight)
        }
        finally {
            if ($null -ne $image) { $image.Dispose() }
        }
    }
    catch {
        return $false
    }
}

function Get-BlockHudValidItemGifAtlasProfiles {
    param([Parameter(Mandatory = $true)][string]$ItemImageDirectory)

    $customsRoot = Split-Path -Parent (Split-Path -Parent ([System.IO.Path]::GetFullPath($ItemImageDirectory)))
    $manifestPath = Join-Path $customsRoot 'Data\ItemImages.inc'
    $parsed = ConvertFrom-BlockHudItemGifAtlasProfiles -Value (Get-BlockHudItemGifAtlasProfilesValue -ManifestPath $manifestPath)
    return @($parsed.Entries | Where-Object {
        Test-BlockHudItemGifAtlasProfileFiles -Entry $_ -ItemImageDirectory $ItemImageDirectory
    })
}

function Resolve-BlockHudItemImageBackingPath {
    param(
        [Parameter(Mandatory = $true)][string]$ItemImageDirectory,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [AllowNull()][object[]]$ValidAtlasProfiles
    )

    $normalized = ConvertTo-BlockHudItemImageAssetName -Value $AssetName
    if ([string]::IsNullOrWhiteSpace($normalized)) { return '' }

    $profiles = if ($PSBoundParameters.ContainsKey('ValidAtlasProfiles')) {
        @($ValidAtlasProfiles)
    }
    else {
        @(Get-BlockHudValidItemGifAtlasProfiles -ItemImageDirectory $ItemImageDirectory)
    }
    $matches = @($profiles | Where-Object {
        [string]::Equals([string]$_.SourceName, $normalized, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -eq 1) {
        return Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $ItemImageDirectory -AtlasName ([string]$matches[0].AtlasName)
    }

    $physicalPath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $ItemImageDirectory -AssetName $normalized
    if ([System.IO.File]::Exists($physicalPath)) { return $physicalPath }
    return ''
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
        ([string]::Equals($asset, 'more.png', [System.StringComparison]::OrdinalIgnoreCase) -or
        (Test-BlockHudManagedItemGifAtlasName -Value $asset))) {
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
