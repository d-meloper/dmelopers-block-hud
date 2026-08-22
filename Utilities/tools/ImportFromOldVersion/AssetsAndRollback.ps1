# ImportFromOldVersion helpers - Asset copy and rollback

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Split-AssetList {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value -split '\|' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-CaseInsensitiveHashtable {
    New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
}

function Normalize-ImageAssetForMigration {
    param([AllowNull()][string]$Value)

    return (ConvertTo-BlockHudItemImageAssetName -Value $Value -AppendDefaultExtension -AllowReservedRuntimeAsset)
}

function Get-ImageAdjustmentKeyForMigration {
    param([AllowNull()][string]$Value)

    $asset = Normalize-ImageAssetForMigration -Value $Value
    if ($asset.Length -gt 0) {
        return [System.IO.Path]::GetFileNameWithoutExtension($asset)
    }

    $candidate = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate -eq '.' -or $candidate -eq '..') {
        return ''
    }
    if ([System.IO.Path]::IsPathRooted($candidate) -or $candidate.IndexOfAny([char[]]@('/', '\')) -ge 0) {
        return ''
    }

    # Image adjustment keys intentionally omit the final image extension. Appending
    # a known-safe extension validates the complete basename without interpreting a
    # suffix such as ".part" as an unsupported image extension.
    $validatedAsset = ConvertTo-BlockHudItemImageAssetName -Value ($candidate + '.png') -AllowReservedRuntimeAsset
    if ([string]::IsNullOrWhiteSpace($validatedAsset)) {
        return ''
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($validatedAsset)
}

function Add-ImageRenameMapEntry {
    param(
        [hashtable]$RenameMap,
        [Parameter(Mandatory = $true)]
        [string]$OriginalValue,
        [Parameter(Mandatory = $true)]
        [string]$RenamedValue
    )

    if (-not $RenameMap) {
        return
    }

    $originalAsset = Normalize-ImageAssetForMigration -Value $OriginalValue
    $renamedAsset = Normalize-ImageAssetForMigration -Value $RenamedValue
    $originalAdjustmentKey = Get-ImageAdjustmentKeyForMigration -Value $OriginalValue
    $renamedAdjustmentKey = Get-ImageAdjustmentKeyForMigration -Value $RenamedValue

    foreach ($entry in @(
        @{ Key = $OriginalValue; Value = $RenamedValue },
        @{ Key = $originalAsset; Value = $renamedAsset },
        @{ Key = $originalAdjustmentKey; Value = $renamedAdjustmentKey }
    )) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Key) -and -not $RenameMap.ContainsKey($entry.Key)) {
            $RenameMap[$entry.Key] = $entry.Value
        }
    }
}

function Rename-ImageValue {
    param(
        [AllowNull()]
        [string]$Value,
        [hashtable]$RenameMap
    )

    if (-not $RenameMap -or [string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    foreach ($candidate in @(
        $Value,
        (Normalize-ImageAssetForMigration -Value $Value),
        (Get-ImageAdjustmentKeyForMigration -Value $Value)
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $RenameMap.ContainsKey($candidate)) {
            return $RenameMap[$candidate]
        }
    }

    return $Value
}

function Repair-ImportImageValue {
    param(
        [AllowNull()]
        [string]$Value,
        [hashtable]$ImageRenameMap,
        [string]$RepairContext = '',
        [string]$RepairKey = ''
    )

    $approvedByKey = ($script:ApprovedItemImageRepairKeys -and
        -not [string]::IsNullOrWhiteSpace($RepairContext) -and
        -not [string]::IsNullOrWhiteSpace($RepairKey) -and
        $script:ApprovedItemImageRepairKeys.ContainsKey((Get-ItemImageRepairEntryId -Context $RepairContext -Key $RepairKey)))
    if ($approvedByKey) {
        if (-not $script:AppliedItemImageRepairKeys) {
            $script:AppliedItemImageRepairKeys = New-CaseInsensitiveHashtable
        }
        $repairEntryId = Get-ItemImageRepairEntryId -Context $RepairContext -Key $RepairKey
        $script:AppliedItemImageRepairKeys[$repairEntryId] = $true
        return ''
    }

    return (Rename-ImageValue -Value $Value -RenameMap $ImageRenameMap)
}

function Merge-UniqueLines {
    param(
        [string[][]]$LineSets,
        [switch]$CaseInsensitive
    )

    $seen = @{}
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($lines in $LineSets) {
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed.Length -eq 0) {
                continue
            }
            $key = if ($CaseInsensitive) { $trimmed.ToLowerInvariant() } else { $trimmed }
            if ($seen.ContainsKey($key)) {
                continue
            }
            $seen[$key] = $true
            $result.Add($trimmed)
        }
    }

    return $result.ToArray()
}

function Read-NonEmptyLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-SkippedSourcePath -Path $Path) {
        return @()
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $text = Read-TextSmart -Path $Path
    return @($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-Sha256HashString {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = Open-SharedReadStream -Path $Path
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($stream)
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Test-ReadableSourceFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = Open-SharedReadStream -Path $Path
    try {
        if ($stream.Length -gt 0) {
            [void]$stream.ReadByte()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-SourceDirectoryFilesLoopSafe {
    param([Parameter(Mandatory = $true)][string]$SourceDirectory)

    $files = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        return @()
    }
    if (Test-SkippedSourcePath -Path $SourceDirectory) {
        return @()
    }

    $pending = New-Object System.Collections.Generic.Queue[string]
    $visited = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $pending.Enqueue((Resolve-FullPath -Path $SourceDirectory))

    while ($pending.Count -gt 0) {
        $currentDirectory = $pending.Dequeue()
        if (Test-SkippedSourcePath -Path $currentDirectory) {
            continue
        }

        try {
            $currentItem = Get-Item -LiteralPath $currentDirectory -Force -ErrorAction Stop
        }
        catch {
            Add-SkippedSourcePath -Path $currentDirectory -Directory
            Write-Log "Skipped unreadable source directory: $currentDirectory ($($_.Exception.Message))" 'WARN'
            continue
        }
        Assert-NonRedirectingExistingImportPath -Path $currentItem.FullName -Context 'source user-data directory'
        $canonical = Normalize-PathIdentity -Path $currentItem.FullName

        if (-not $visited.Add($canonical)) {
            Write-Log "Skipped already-visited source directory during loop-safe traversal: $currentDirectory" 'WARN'
            continue
        }

        try {
            $children = @(Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop)
        }
        catch {
            Add-SkippedSourcePath -Path $currentDirectory -Directory
            Write-Log "Skipped unreadable source directory: $currentDirectory ($($_.Exception.Message))" 'WARN'
            continue
        }

        foreach ($child in $children) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reason = ''
                if (-not (Test-NonRedirectingReparsePoint -Item $child -Reason ([ref]$reason))) {
                    throw "Refusing migration because source user data contains an unsafe reparse point ($reason): $($child.FullName)"
                }
                Write-Log "Allowed source user-data reparse point as $reason`: $($child.FullName)"
            }
            if ($child.PSIsContainer) {
                $pending.Enqueue($child.FullName)
            }
            elseif (-not (Test-SkippedSourcePath -Path $child.FullName)) {
                $files.Add($child.FullName)
            }
        }
    }

    return $files.ToArray()
}

function Invoke-OptionalSourceProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Probe
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Source $Description is absent: $Path; current target data will be preserved when present."
        return
    }

    Assert-NonRedirectingExistingImportPath -Path $Path -Context "source $Description"

    try {
        [void](& $Probe)
    }
    catch {
        Add-SkippedSourcePath -Path $Path
        Write-Log "Source $Description could not be read and will be skipped: $Path ($($_.Exception.Message))" 'WARN'
    }
}

function Invoke-OptionalSourceDirectoryProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Log "Source $Description directory is absent: $Path; current target data will be preserved when present."
        return
    }

    foreach ($file in (Get-SourceDirectoryFilesLoopSafe -SourceDirectory $Path)) {
        try {
            Test-ReadableSourceFile -Path $file
        }
        catch {
            Add-SkippedSourcePath -Path $file
            Write-Log "Source $Description file could not be read and will be skipped: $file ($($_.Exception.Message))" 'WARN'
        }
    }
}

function Preflight-SourceState {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    Write-Log 'Building read-only source preflight model.'

    $sourceSettingsIni = Join-RootPath -Root $SourceRoot -RelativePath ((Get-BlockHudSettingsRelativePath -Root $SourceRoot) + '\Settings.ini')
    Assert-NonRedirectingExistingImportPath -Path $sourceSettingsIni -Context 'source Settings.ini'
    Test-ReadableSourceFile -Path $sourceSettingsIni

    foreach ($relativePath in @(
        '@Resources\Customs\Data\HotbarItems.inc',
        '@Resources\Customs\Data\InventoryItems.inc',
        '@Resources\Customs\Data\ItemImages.inc',
        '@Resources\Customs\Data\ResponsiveLayoutState.inc',
        '@Resources\Customs\Settings\Hotbar.inc',
        '@Resources\Customs\Settings\Inventory.inc',
        '@Resources\Customs\Settings\Clock.inc',
        '@Resources\Customs\Settings\Indicators.inc',
        '@Resources\Customs\Settings\Support.inc'
    )) {
        $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "SourceRoot is missing required legacy import file: $relativePath"
        }

        Assert-NonRedirectingExistingImportPath -Path $sourcePath -Context "required legacy import file $relativePath"
        Test-ReadableSourceFile -Path $sourcePath
    }

    $editorDraftPath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\EditorDraft.inc'
    if (Test-Path -LiteralPath $editorDraftPath -PathType Leaf) {
        Assert-NonRedirectingExistingImportPath -Path $editorDraftPath -Context 'source EditorDraft.inc'
        Test-ReadableSourceFile -Path $editorDraftPath
    }

    foreach ($optionalFile in @(
        '@Resources\Customs\Settings\General.inc',
        '@Resources\Customs\Data\ImageAdjustments.inc',
        '@Resources\Customs\Data\HerobrineStats.inc',
        '@Resources\Customs\Data\HerobrineState.inc',
        '@Resources\Customs\Data\EditorFavoritesCatalog.txt',
        '@Resources\Customs\Data\JukeboxDiscSlots.json',
        '@Resources\Customs\Data\JukeboxPlaybackState.inc',
        '@Resources\Customs\Data\ProgramActionLabels.txt',
        '@Resources\Customs\Data\MinecraftSkinHistory.txt',
        '@Resources\CustomsDataMinecraftSkinHistory.txt'
    )) {
        $probePath = Join-RootPath -Root $SourceRoot -RelativePath $optionalFile
        Invoke-OptionalSourceProbe -Path $probePath -Description $optionalFile -Probe {
            Test-ReadableSourceFile -Path $probePath
        }
    }

    $hudMirrorPath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Settings\HudMirror.inc'
    if (Test-Path -LiteralPath $hudMirrorPath -PathType Leaf) {
        Assert-NonRedirectingExistingImportPath -Path $hudMirrorPath -Context 'source HUD mirror settings'
    }
    Assert-HudMirrorImportSourcePreflight -SourceRoot $SourceRoot

    foreach ($optionalDirectory in @(
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Images\Player',
        '@Resources\Customs\Audios\Jukebox Disc'
    )) {
        Invoke-OptionalSourceDirectoryProbe -Path (Join-RootPath -Root $SourceRoot -RelativePath $optionalDirectory) -Description $optionalDirectory
    }

    Write-Log 'Source preflight completed.'
}

function Clear-TargetPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-SafeTargetPath -Path $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $null = Invoke-MigrationAction -Action 'Clear target snapshot path' -Target $Path -ScriptBlock {
        Remove-Item -LiteralPath $Path -Force -Recurse
    }
}

function Copy-PathSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    Assert-SafeTargetPath -Path $TargetPath
    $parent = Split-Path -Parent $TargetPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    $null = Invoke-MigrationAction -Action 'Copy snapshot path' -Target $TargetPath -ScriptBlock {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force -Recurse
    }
}

function Copy-FilteredSourceDirectorySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$TargetDirectory
    )

    Assert-SafeTargetPath -Path $TargetDirectory
    $sourceBase = [System.IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\', '/') + '\'
    $sourceFiles = @(Get-SourceDirectoryFilesLoopSafe -SourceDirectory $SourceDirectory)
    $null = Invoke-MigrationAction -Action 'Copy filtered source directory snapshot' -Target $TargetDirectory -ScriptBlock {
        Ensure-Directory -Path $TargetDirectory
        foreach ($sourceFile in $sourceFiles) {
            if (Test-SkippedSourcePath -Path $sourceFile) {
                continue
            }

            $relativePath = [System.IO.Path]::GetFullPath($sourceFile).Substring($sourceBase.Length)
            $targetFile = Join-RootPath -Root $TargetDirectory -RelativePath $relativePath
            Assert-SafeTargetPath -Path $targetFile
            Ensure-Directory -Path (Split-Path -Parent $targetFile)
            Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        }
    }
}

function Remove-TemporaryRollbackRootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$RollbackRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($RollbackRoot) -or -not (Test-Path -LiteralPath $RollbackRoot)) {
        return
    }

    try {
        Remove-Item -LiteralPath $RollbackRoot -Force -Recurse
        Write-Log ("Removed temporary rollback workspace after {0}: {1}" -f $Reason, $RollbackRoot)
    }
    catch {
        Write-Log ("Failed to remove temporary rollback workspace after {0}: {1} ({2})" -f $Reason, $RollbackRoot, $_.Exception.Message) 'WARN'
    }
}

function Backup-TargetStateToTemporaryRollback {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $rollbackRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLegacyImportRollback_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    try {
        Ensure-Directory -Path $rollbackRoot
        $script:EphemeralRollbackRoot = Resolve-FullPath -Path $rollbackRoot

        Copy-TargetStateToTemporaryRollbackWithProgress -TargetRoot $TargetRoot -RollbackRoot $script:EphemeralRollbackRoot

        Write-Log ("Prepared temporary rollback workspace: {0}" -f $script:EphemeralRollbackRoot)
    }
    catch {
        $failure = $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($script:EphemeralRollbackRoot)) {
            Remove-TemporaryRollbackRootBestEffort -RollbackRoot $script:EphemeralRollbackRoot -Reason 'rollback preparation failure'
            $script:EphemeralRollbackRoot = ''
        }
        throw ("Temporary rollback workspace could not be prepared before target mutation: {0}" -f $failure)
    }
}

function Restore-TargetStateFromTemporaryRollback {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot
    )

    if (-not (Test-Path -LiteralPath $RollbackRoot -PathType Container)) {
        throw "Temporary rollback workspace is missing: $RollbackRoot"
    }

    Write-Log ("Automatic rollback started from temporary workspace: {0}" -f $RollbackRoot) 'WARN'
    foreach ($relativePath in (Get-TemporaryRollbackScopeRelativePaths -Root $TargetRoot)) {
        $targetPath = Join-RootPath -Root $TargetRoot -RelativePath $relativePath
        $rollbackPath = Join-Path $RollbackRoot $relativePath

        Clear-TargetPath -Path $targetPath
        if (Test-Path -LiteralPath $rollbackPath) {
            Copy-PathSnapshot -SourcePath $rollbackPath -TargetPath $targetPath
        }
    }

    Write-Log 'Automatic rollback completed from temporary workspace.' 'WARN'
}

function Import-SnapshotState {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    foreach ($relativePath in @(
        '@Resources\Customs\Settings',
        '@Resources\Customs\Data',
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Images\Player'
    )) {
        $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath $relativePath
        $targetPath = Join-RootPath -Root $TargetRoot -RelativePath $relativePath

        Clear-TargetPath -Path $targetPath
        Copy-PathSnapshot -SourcePath $sourcePath -TargetPath $targetPath

        if ($relativePath.StartsWith('@Resources\Customs\', [System.StringComparison]::OrdinalIgnoreCase)) {
            foreach ($rainmeterFile in Get-ChildItem -LiteralPath $targetPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -in @('.ini', '.inc')
            }) {
                [void]$script:TouchedRainmeterFiles.Add($rainmeterFile.FullName)
            }
        }
    }

    $sourceStateRelativePath = (Get-BlockHudSettingsRelativePath -Root $SourceRoot) + '\State.inc'
    $targetStateRelativePath = (Get-BlockHudSettingsRelativePath -Root $TargetRoot) + '\State.inc'
    $sourceStatePath = Join-RootPath -Root $SourceRoot -RelativePath $sourceStateRelativePath
    $targetStatePath = Join-RootPath -Root $TargetRoot -RelativePath $targetStateRelativePath
    Clear-TargetPath -Path $targetStatePath
    Copy-PathSnapshot -SourcePath $sourceStatePath -TargetPath $targetStatePath
    [void]$script:TouchedRainmeterFiles.Add($targetStatePath)
}
function Merge-LineFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source text file: $SourcePath"
        return
    }

    $lines = @(Merge-UniqueLines -LineSets @(
        (Read-NonEmptyLines -Path $TargetPath),
        (Read-NonEmptyLines -Path $SourcePath)
    ))

    $content = ''
    if ($lines.Count -gt 0) {
        $content = ($lines -join "`r`n") + "`r`n"
    }

    $null = Invoke-MigrationAction -Action 'Merge text lines' -Target $TargetPath -ScriptBlock {
        Write-Utf8Text -Path $TargetPath -Content $content
    }
}

function Get-MinecraftSkinHistoryCandidates {
    param([Parameter(Mandatory = $true)][string]$Root)

    $values = New-Object System.Collections.Generic.List[string]
    $supportSettings = Read-VariablesFile -Path (Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\Support.inc')
    if ($supportSettings.Contains('MinecraftSkinUsername') -and -not [string]::IsNullOrWhiteSpace($supportSettings['MinecraftSkinUsername'])) {
        $values.Add(([string]$supportSettings['MinecraftSkinUsername']).Trim())
    }

    $playerImageDirectory = Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Images\Player'
    if (Test-Path -LiteralPath $playerImageDirectory -PathType Container) {
        if (Test-SkippedSourcePath -Path $playerImageDirectory) {
            return $values.ToArray()
        }
        foreach ($file in Get-ChildItem -LiteralPath $playerImageDirectory -File -Filter 'MinecraftSkinBody_*.png') {
            if (Test-SkippedSourcePath -Path $file.FullName) {
                continue
            }
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ($name.StartsWith('MinecraftSkinBody_', [System.StringComparison]::OrdinalIgnoreCase)) {
                $skinName = $name.Substring('MinecraftSkinBody_'.Length).Trim()
                if ($skinName.Length -gt 0) {
                    $values.Add($skinName)
                }
            }
        }
    }

    return $values.ToArray()
}

function Get-DirectoryItemImageAssets {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }

    $assets = New-Object System.Collections.Generic.List[string]
    $seen = New-CaseInsensitiveHashtable
    $atlasPrefix = [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($Directory).TrimEnd([char[]]@('\', '/')), 'atlas') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($file in (Get-SourceDirectoryFilesLoopSafe -SourceDirectory $Directory | Sort-Object { [System.IO.Path]::GetFileName($_) })) {
        if (Test-SkippedSourcePath -Path $file) {
            continue
        }
        if ([System.IO.Path]::GetFullPath($file).StartsWith($atlasPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $asset = Normalize-ImageAssetForMigration -Value ([System.IO.Path]::GetFileName($file))
        if ([string]::IsNullOrWhiteSpace($asset)) {
            continue
        }

        if ($asset.Equals('more.png', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-BlockHudManagedItemGifAtlasName -Value $asset) {
            continue
        }

        if ($seen.ContainsKey($asset)) {
            continue
        }
        $seen[$asset] = $true
        $assets.Add($asset)
    }

    foreach ($entry in @(Get-BlockHudValidItemGifAtlasProfiles -ItemImageDirectory $Directory | Sort-Object SourceName)) {
        $asset = [string]$entry.SourceName
        if (-not $seen.ContainsKey($asset)) {
            $seen[$asset] = $true
            $assets.Add($asset)
        }
    }

    return @($assets.ToArray() | Sort-Object)
}

function Merge-MinecraftSkinHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $targetHistory = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\MinecraftSkinHistory.txt'
    $sourceHistory = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\MinecraftSkinHistory.txt'
    $targetStray = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\CustomsDataMinecraftSkinHistory.txt'
    $sourceStray = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\CustomsDataMinecraftSkinHistory.txt'

    $lines = @(Merge-UniqueLines -CaseInsensitive -LineSets @(
        (Read-NonEmptyLines -Path $targetHistory),
        (Read-NonEmptyLines -Path $sourceHistory),
        (Read-NonEmptyLines -Path $targetStray),
        (Read-NonEmptyLines -Path $sourceStray),
        (Get-MinecraftSkinHistoryCandidates -Root $TargetRoot),
        (Get-MinecraftSkinHistoryCandidates -Root $SourceRoot)
    ))

    if ($lines.Count -eq 0) {
        Write-Log 'No Minecraft skin history values found to merge.'
        return
    }

    $content = ($lines -join "`r`n") + "`r`n"
    $merged = Invoke-MigrationAction -Action 'Merge Minecraft skin history' -Target $targetHistory -ScriptBlock {
        Write-Utf8Text -Path $targetHistory -Content $content
    }

    if (($merged -or $WhatIfPreference) -and (Test-Path -LiteralPath $targetStray -PathType Leaf)) {
        $null = Invoke-MigrationAction -Action 'Remove merged stray Minecraft skin history' -Target $targetStray -ScriptBlock {
            Assert-SafeTargetPath -Path $targetStray
            Remove-Item -LiteralPath $targetStray -Force
        }
    }
}

function Copy-DirectoryMissingFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,
        [Parameter(Mandatory = $true)]
        [string]$TargetDirectory,
        [hashtable]$RenameMap,
        [switch]$RenameConflicts
    )

    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        Write-Log "Skipped missing source directory: $SourceDirectory"
        return
    }
    if (Test-SkippedSourcePath -Path $SourceDirectory) {
        Write-Log "Skipped source directory marked unreadable during preflight: $SourceDirectory" 'WARN'
        return
    }

    $sourceBase = [System.IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\', '/') + '\'
    $files = Get-SourceDirectoryFilesLoopSafe -SourceDirectory $SourceDirectory
    foreach ($file in $files) {
        if (Test-SkippedSourcePath -Path $file) {
            continue
        }

        $relative = $file.Substring($sourceBase.Length)
        $targetFile = Join-RootPath -Root $TargetDirectory -RelativePath $relative
        Assert-SafeTargetPath -Path $targetFile
        if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
            $sourceHash = Get-Sha256HashString -Path $file
            $targetHash = Get-Sha256HashString -Path $targetFile
            if ($sourceHash -eq $targetHash) {
                Write-Log "Skipped existing identical file: $targetFile"
                continue
            }

            if (-not $RenameConflicts) {
                Write-Log "Skipped conflicting existing file: $targetFile" 'WARN'
                continue
            }

            $targetDirectoryForFile = Split-Path -Parent $targetFile
            $leaf = [System.IO.Path]::GetFileNameWithoutExtension($targetFile)
            $extension = [System.IO.Path]::GetExtension($targetFile)
            $renamedLeaf = '{0}_migrated{1}' -f $leaf, $extension
            $renamedTarget = Join-Path $targetDirectoryForFile $renamedLeaf
            $counter = 2
            $reuseExistingMigrated = $false
            while (Test-Path -LiteralPath $renamedTarget) {
                $renamedHash = Get-Sha256HashString -Path $renamedTarget
                if ($renamedHash -eq $sourceHash) {
                    Add-ImageRenameMapEntry -RenameMap $RenameMap -OriginalValue $relative -RenamedValue $renamedLeaf
                    Write-Log "Reusing existing migrated conflict file: $relative -> $renamedLeaf" 'WARN'
                    $reuseExistingMigrated = $true
                    break
                }

                $renamedLeaf = '{0}_migrated_{1}{2}' -f $leaf, $counter, $extension
                $renamedTarget = Join-Path $targetDirectoryForFile $renamedLeaf
                $counter += 1
            }
            if ($reuseExistingMigrated) {
                continue
            }

            Write-Log "Conflicting file will be migrated as: $relative -> $renamedLeaf" 'WARN'
            Assert-SafeTargetPath -Path $renamedTarget
            $copied = Invoke-MigrationAction -Action 'Copy conflicting file with migrated name' -Target $renamedTarget -ScriptBlock {
                Ensure-Directory -Path (Split-Path -Parent $renamedTarget)
                Copy-Item -LiteralPath $file -Destination $renamedTarget
            }
            if (($copied -or $WhatIfPreference) -and $RenameMap -and -not $RenameMap.ContainsKey($relative)) {
                Add-ImageRenameMapEntry -RenameMap $RenameMap -OriginalValue $relative -RenamedValue $renamedLeaf
            }
            continue
        }

        $null = Invoke-MigrationAction -Action 'Copy missing file' -Target $targetFile -ScriptBlock {
            Ensure-Directory -Path (Split-Path -Parent $targetFile)
            Copy-Item -LiteralPath $file -Destination $targetFile
        }
    }
}

function New-BackfillMap {
    param([hashtable]$Values)

    $map = New-VariablesMap
    foreach ($key in $Values.Keys) {
        Set-MapValue -Map $map -Key $key -Value $Values[$key]
    }
    return $map
}
