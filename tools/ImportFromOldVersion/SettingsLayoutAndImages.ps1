# ImportFromOldVersion helpers - Settings layout and image catalogs

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-SettingsBackfill {
    param([Parameter(Mandatory = $true)][string]$FileName)

    switch ($FileName) {
        'General.inc' {
            $values = @{
                EnableRainmeterStartup = '0'
                ItemCountTextFontSize = '18'
                LanguageCode = 'ko-KR'
                EnableJukeboxSkin = '1'
                EnableJukebox2DMode = '0'
                DisableJukeboxNoteAnimation = '0'
                AllowJukeboxDrag = '1'
                AllowJukeboxSnapEdges = '0'
                JukeboxPlaybackSourceMode = 'local'
                EnableHerobrineSkin = '0'
            }
            foreach ($entry in Get-LowSpecSettingsPolicy) {
                $values[[string]$entry.VariableName] = [string]$entry.DefaultValue
            }
            return (New-BackfillMap -Values $values)
        }
        'Indicators.inc' {
            return (New-BackfillMap -Values @{
                ExpLevelTextGap = '0'
                IndicatorBarScalePercent = '100'
                ArmorBarDiskTarget = 'C:'
                FoodBarDiskTarget = 'C:'
                AirBarDiskTarget = 'C:'
            })
        }
        'Clock.inc' {
            return (New-BackfillMap -Values @{
                ClockDisplayMode = 'default'
                EnableClockTextSkin = '1'
                EnableClockSpriteSkin = '1'
                ClockSpriteSize = '128'
                ClockTextColor = '255,255,255,255'
            })
        }
        'Support.inc' {
            return (New-BackfillMap -Values @{
                HideSteve = '0'
                MinecraftSkinUsername = ''
                MinecraftSkinModel = 'wide'
                MinecraftSkinImagePath = ''
                MinecraftSkinTexturePath = ''
                MinecraftSkinImagePathVerified = '0'
            })
        }
        default {
            return $null
        }
    }
}

function Test-LegacyUpdaterZPosBootstrapSource {
    param([Parameter(Mandatory = $true)][version]$SourceVersion)

    return ($SourceVersion -ge [version]'1.2.0' -and $SourceVersion -lt [version]'1.3.1')
}

function Set-LegacyUpdaterZPosBootstrapPending {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,
        [Parameter(Mandatory = $true)]
        [version]$SourceVersion
    )

    if (-not (Test-LegacyUpdaterZPosBootstrapSource -SourceVersion $SourceVersion)) {
        return
    }

    $bootstrapPath = Join-RootPath -Root $TargetRoot -RelativePath 'Bootstrap\ZPosBootstrap.ini'
    if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
        Write-Log 'Legacy updater z-position bootstrap marker was not armed because Bootstrap\ZPosBootstrap.ini is missing from the target.' 'WARN'
        return
    }

    $statePath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\LegacyUpdaterBootstrapState.inc'
    $stateVariables = New-VariablesMap
    Set-MapValue -Map $stateVariables -Key 'BlockHudLegacyUpdaterZPosBootstrapPending' -Value '1'
    Write-Utf16Text -Path $statePath -Content (ConvertTo-VariablesContent -Variables $stateVariables)
    Write-Log 'Legacy updater z-position bootstrap marker armed for pre-v1.3.1 source update.'
}

function Replace-DirectorySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$TargetDirectory
    )

    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        Write-Log "Skipped missing source directory snapshot: $SourceDirectory"
        return
    }
    if (Test-SkippedSourcePath -Path $SourceDirectory) {
        Write-Log "Skipped source directory snapshot marked unreadable during preflight: $SourceDirectory" 'WARN'
        return
    }

    Clear-TargetPath -Path $TargetDirectory
    Copy-PathSnapshot -SourcePath $SourceDirectory -TargetPath $TargetDirectory
}

function Merge-SettingsFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $sourceSettings = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Settings'
    $targetSettings = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Settings'
    if (-not (Test-Path -LiteralPath $sourceSettings -PathType Container)) {
        Write-Log "Source settings directory is missing; applying target backfills only: $sourceSettings" 'WARN'
    }

    $targetFiles = @(
        'General.inc',
        'Hotbar.inc',
        'Inventory.inc',
        'Clock.inc',
        'Indicators.inc',
        'Support.inc'
    )

    foreach ($fileName in $targetFiles) {
        $targetPath = Join-RootPath -Root $targetSettings -RelativePath $fileName
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Write-Log "Skipped settings file not present in the current target: $fileName"
            continue
        }

        $sourcePath = Join-RootPath -Root $sourceSettings -RelativePath $fileName
        $backfill = Get-SettingsBackfill -FileName $fileName
        $excludeKeyPatterns = @()
        if ($fileName -eq 'Support.inc') {
            $excludeKeyPatterns = @(
                '^UpdateProvider$',
                '^UpdateGithubOwner$',
                '^UpdateGithubRepo$',
                '^UpdateReleaseVariant$',
                '^UpdateReleaseAssetPattern$',
                '^UpdateReleaseAssetPatternKorea$',
                '^UpdateReleaseAssetPatternGlobal$',
                '^EnableWorkProgress$',
                '^WorkProgressImageName$'
            )
        }

        Merge-VariablesFile -SourcePath $sourcePath -TargetPath $targetPath -SameKeysOnly -ExcludeKeyPatterns $excludeKeyPatterns -Backfill $backfill
    }
}

function Test-EnabledSettingValue {
    param([AllowNull()][string]$Value)

    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    return ($normalized -in @('1', 'true', 'yes', 'on'))
}

function Normalize-SettingBoolValue {
    param([AllowNull()][string]$Value)

    if (Test-EnabledSettingValue -Value $Value) {
        return '1'
    }

    return '0'
}

function Apply-LowSpecSettingsCompatibility {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $sourceGeneralPath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Settings\General.inc'
    $targetGeneralPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Settings\General.inc'
    $sourceVariables = Read-VariablesFile -Path $sourceGeneralPath
    $targetVariables = Read-VariablesFile -Path $targetGeneralPath

    $lowSpecPolicy = @(Get-LowSpecSettingsPolicy)
    $sourceHasSplitLowSpec = $false
    $changed = $false

    foreach ($entry in $lowSpecPolicy) {
        $key = [string]$entry.VariableName
        if ($sourceVariables.Contains($key)) {
            $sourceHasSplitLowSpec = $true
        }
        if ($targetVariables.Contains($key)) {
            $normalizedValue = Normalize-SettingBoolValue -Value $targetVariables[$key]
            if ([string]$targetVariables[$key] -ne $normalizedValue) {
                Set-MapValue -Map $targetVariables -Key $key -Value $normalizedValue
                $changed = $true
            }
        }
        else {
            Set-MapValue -Map $targetVariables -Key $key -Value ([string]$entry.DefaultValue)
            $changed = $true
        }
    }

    if ($sourceHasSplitLowSpec) {
        Write-Log 'Source already contains split low-spec settings; legacy low-spec compatibility backfill skipped.'
        if ($changed) {
            $content = ConvertTo-VariablesContent -Variables $targetVariables
            $null = Invoke-MigrationAction -Action 'Normalize split low-spec settings' -Target $targetGeneralPath -ScriptBlock {
                Write-Utf16Text -Path $targetGeneralPath -Content $content
            }
        }
        return
    }

    if (-not $sourceVariables.Contains('EnableLowSpecMode') -or -not (Test-EnabledSettingValue -Value $sourceVariables['EnableLowSpecMode'])) {
        if ($changed) {
            $content = ConvertTo-VariablesContent -Variables $targetVariables
            $null = Invoke-MigrationAction -Action 'Normalize split low-spec settings' -Target $targetGeneralPath -ScriptBlock {
                Write-Utf16Text -Path $targetGeneralPath -Content $content
            }
        }
        return
    }

    foreach ($entry in $lowSpecPolicy) {
        if (-not $entry.ExpandFromLegacySingleToggle) {
            continue
        }
        $key = [string]$entry.VariableName
        $value = Normalize-SettingBoolValue -Value ([string]$entry.LegacyEnabledValue)
        if (-not $targetVariables.Contains($key) -or [string]$targetVariables[$key] -ne $value) {
            Set-MapValue -Map $targetVariables -Key $key -Value $value
            $changed = $true
        }
    }

    if (-not $changed) {
        return
    }

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Apply legacy low-spec settings compatibility' -Target $targetGeneralPath -ScriptBlock {
        Write-Utf16Text -Path $targetGeneralPath -Content $content
    }
}

function Normalize-LanguageCode {
    param(
        [AllowNull()][string]$Value,
        [string]$Fallback = 'ko-KR'
    )

    $resolved = ([string]$Value).Trim().ToLowerInvariant()
    if ($resolved -in @('en', 'en-us')) {
        return 'en-US'
    }
    if ($resolved -in @('ko', 'ko-kr')) {
        return 'ko-KR'
    }

    $fallbackResolved = ([string]$Fallback).Trim().ToLowerInvariant()
    if ($fallbackResolved -eq 'en-us') {
        return 'en-US'
    }
    return 'ko-KR'
}

function Resolve-ImportedLanguageCode {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    $sourceGeneralPath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Settings\General.inc'
    $sourceVariables = Read-VariablesFile -Path $sourceGeneralPath
    if ($sourceVariables.Contains('LanguageCode')) {
        return (Normalize-LanguageCode -Value $sourceVariables['LanguageCode'] -Fallback 'ko-KR')
    }

    return 'ko-KR'
}

function Get-ReservedInventoryItemLabel {
    param([Parameter(Mandatory = $true)][string]$LanguageCode)

    $resolvedLanguageCode = Normalize-LanguageCode -Value $LanguageCode -Fallback 'ko-KR'
    if ($resolvedLanguageCode -eq 'en-US') {
        return 'Inventory'
    }

    return (Expand-UnicodeEscapes -Value '\uC778\uBCA4\uD1A0\uB9AC')
}

function New-HotbarSlot10ReservedBackfill {
    param([Parameter(Mandatory = $true)][string]$LanguageCode)

    return (New-BackfillMap -Values @{
        HotbarItem_Slot10_Image = 'more.png'
        HotbarItem_Slot10_Label = Get-ReservedInventoryItemLabel -LanguageCode $LanguageCode
        HotbarItem_Slot10_Action = '_OPEN_INVENTORY_'
        HotbarItem_Slot10_Qty = '0'
    })
}

function Normalize-HotbarSlot10ReservedLabel {
    param(
        [Parameter(Mandatory = $true)][string]$TargetHotbarPath,
        [Parameter(Mandatory = $true)][string]$LanguageCode
    )

    $hotbarVariables = Read-VariablesFile -Path $TargetHotbarPath
    if (-not (Test-ReservedHotbarSlot10Section -Variables $hotbarVariables -Prefix 'HotbarItem_Slot10')) {
        return
    }

    $label = Get-ReservedInventoryItemLabel -LanguageCode $LanguageCode
    $currentLabel = Get-ItemFieldValue -Variables $hotbarVariables -Prefix 'HotbarItem_Slot10' -Field 'Label'
    if ($currentLabel -eq $label) {
        return
    }

    Set-MapValue -Map $hotbarVariables -Key 'HotbarItem_Slot10_Label' -Value $label
    $content = ConvertTo-VariablesContent -Variables $hotbarVariables
    $null = Invoke-MigrationAction -Action 'Normalize reserved hotbar slot 10 label' -Target $TargetHotbarPath -ScriptBlock {
        Write-Utf16Text -Path $TargetHotbarPath -Content $content
    }
}

function Test-PngFileSignature {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($stream.Length -lt 8) {
                return $false
            }

            $buffer = New-Object byte[] 8
            $read = $stream.Read($buffer, 0, 8)
            if ($read -ne 8) {
                return $false
            }

            [byte[]]$expected = 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
            for ($index = 0; $index -lt $expected.Length; $index++) {
                if ($buffer[$index] -ne $expected[$index]) {
                    return $false
                }
            }

            return $true
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $false
    }
}

function Sync-ActiveLocalizationCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$LanguageCode
    )

    $resolvedLanguageCode = Normalize-LanguageCode -Value $LanguageCode -Fallback 'ko-KR'
    $generalPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Settings\General.inc'
    $generalVariables = Read-VariablesFile -Path $generalPath
    Set-MapValue -Map $generalVariables -Key 'LanguageCode' -Value $resolvedLanguageCode
    $generalContent = ConvertTo-VariablesContent -Variables $generalVariables
    $null = Invoke-MigrationAction -Action 'Normalize imported language code' -Target $generalPath -ScriptBlock {
        Write-Utf16Text -Path $generalPath -Content $generalContent
    }

    $localeSourcePath = Join-RootPath -Root $TargetRoot -RelativePath ("@Resources\Localization\Languages\{0}.inc" -f $resolvedLanguageCode)
    if (-not (Test-Path -LiteralPath $localeSourcePath -PathType Leaf)) {
        throw "TargetRoot is missing canonical localization catalog for imported language '$resolvedLanguageCode'."
    }

    $localeContent = Read-TextSmart -Path $localeSourcePath
    $activeLocalePath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Localization\Active.inc'
    $null = Invoke-MigrationAction -Action 'Regenerate active localization catalog' -Target $activeLocalePath -ScriptBlock {
        Write-Utf16Text -Path $activeLocalePath -Content $localeContent
    }

    $helperCacheScript = Join-RootPath -Root $TargetRoot -RelativePath 'tools\UpdateHelperLocalizationCache.ps1'
    if (Test-Path -LiteralPath $helperCacheScript -PathType Leaf) {
        & $helperCacheScript -SkinRoot $TargetRoot -LanguageCode $resolvedLanguageCode | Out-Null
    }
}

function Merge-ItemImagesCatalog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [hashtable]$ImageRenameMap
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source item image catalog: $SourcePath"
    }

    $targetVariables = Read-VariablesFile -Path $TargetPath
    $customsRoot = Split-Path -Parent (Split-Path -Parent $TargetPath)
    $targetImageDirectory = Join-Path $customsRoot 'Images\Items'
    $assets = @(Get-DirectoryItemImageAssets -Directory $targetImageDirectory)
    $assetList = ($assets -join '|')
    Set-MapValue -Map $targetVariables -Key 'ItemImageAssets' -Value $assetList
    Set-MapValue -Map $targetVariables -Key 'ItemImageKeys' -Value $assetList

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge item image catalog' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Rebuild-ImageAdjustmentsCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ImageDirectory
    )

    $targetVariables = Read-VariablesFile -Path $TargetPath
    $allowedAdjustKeys = New-CaseInsensitiveHashtable
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $ImageDirectory)) {
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value $asset
        if ($adjustKey.Length -gt 0 -and -not $allowedAdjustKeys.ContainsKey($adjustKey)) {
            $allowedAdjustKeys[$adjustKey] = $true
        }
    }

    foreach ($variableKey in @($targetVariables.Keys)) {
        if ($variableKey -notmatch '^ImageAdjust_(.+)_(OffsetX|OffsetY|SizeOffset)$') {
            continue
        }

        $adjustKey = $matches[1]
        if (-not $allowedAdjustKeys.ContainsKey($adjustKey)) {
            $targetVariables.Remove($variableKey)
        }
    }

    $orderedKeys = New-Object System.Collections.Generic.List[string]
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $ImageDirectory)) {
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value $asset
        if ($adjustKey.Length -eq 0) {
            continue
        }
        if (-not $allowedAdjustKeys.ContainsKey($adjustKey)) {
            continue
        }

        $hasAdjustment = $false
        foreach ($suffix in @('OffsetX', 'OffsetY', 'SizeOffset')) {
            if ($targetVariables.Contains("ImageAdjust_${adjustKey}_${suffix}")) {
                $hasAdjustment = $true
                break
            }
        }

        if ($hasAdjustment -and -not $orderedKeys.Contains($adjustKey)) {
            $orderedKeys.Add($adjustKey)
        }
    }

    Set-MapValue -Map $targetVariables -Key 'ImageAdjustKeys' -Value ($orderedKeys.ToArray() -join '|')
    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Rebuild image adjustment catalog' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Merge-ImageAdjustmentsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [hashtable]$ImageRenameMap
    )

    $targetVariables = Read-VariablesFile -Path $TargetPath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source image adjustments: $SourcePath"
        return
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath
    foreach ($key in $sourceVariables.Keys) {
        if ($key -eq 'ImageAdjustKeys') {
            continue
        }

        if ($key -notmatch '^ImageAdjust_(.+)_(OffsetX|OffsetY|SizeOffset)$') {
            continue
        }

        $sourceAdjustKey = $matches[1]
        $suffix = $matches[2]
        $renamedAdjustKey = Get-ImageAdjustmentKeyForMigration -Value (Rename-ImageValue -Value $sourceAdjustKey -RenameMap $ImageRenameMap)
        if ($renamedAdjustKey.Length -eq 0) {
            continue
        }

        Set-MapValue -Map $targetVariables -Key "ImageAdjust_${renamedAdjustKey}_${suffix}" -Value $sourceVariables[$key]
    }

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge image adjustments' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Get-ReferencedImageAssetsFromVariables {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables)

    $assets = New-Object System.Collections.Generic.List[string]
    $seen = New-CaseInsensitiveHashtable
    foreach ($key in $Variables.Keys) {
        if ($key -notmatch '_(Image)$') {
            continue
        }

        $asset = Normalize-ImageAssetForMigration -Value $Variables[$key]
        if ([string]::IsNullOrWhiteSpace($asset)) {
            continue
        }
        if ($asset.Equals('more.png', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (-not $seen.ContainsKey($asset)) {
            $seen[$asset] = $true
            $assets.Add($asset)
        }
    }

    return $assets.ToArray()
}

function Get-DirectoryItemImageAssetMap {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $map = New-CaseInsensitiveHashtable
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $Directory)) {
        if (-not $map.ContainsKey($asset)) {
            $map[$asset] = $true
        }
    }
    return $map
}

function Assert-ImportableItemImageReferences {
    param(
        [Parameter(Mandatory = $true)][string]$SourceHotbarPath,
        [Parameter(Mandatory = $true)][string]$SourceInventoryPath,
        [Parameter(Mandatory = $true)][string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory
    )

    $referencedAssets = New-Object System.Collections.Generic.List[string]
    foreach ($asset in (Get-ReferencedImageAssetsFromVariables -Variables (Read-VariablesFile -Path $SourceHotbarPath))) {
        $referencedAssets.Add($asset)
    }
    foreach ($asset in (Get-ReferencedImageAssetsFromVariables -Variables (Read-VariablesFile -Path $SourceInventoryPath))) {
        $referencedAssets.Add($asset)
    }

    if ($referencedAssets.Count -eq 0) {
        return
    }

    $sourceDirectoryExists = Test-Path -LiteralPath $SourceImageDirectory -PathType Container
    $sourceAssets = if ($sourceDirectoryExists) { Get-DirectoryItemImageAssetMap -Directory $SourceImageDirectory } else { New-CaseInsensitiveHashtable }
    $targetAssets = if (Test-Path -LiteralPath $TargetImageDirectory -PathType Container) { Get-DirectoryItemImageAssetMap -Directory $TargetImageDirectory } else { New-CaseInsensitiveHashtable }
    $missingAssets = New-Object System.Collections.Generic.List[string]
    $seenMissing = New-CaseInsensitiveHashtable
    foreach ($asset in $referencedAssets) {
        if ($sourceAssets.ContainsKey($asset) -or $targetAssets.ContainsKey($asset)) {
            continue
        }
        if (-not $seenMissing.ContainsKey($asset)) {
            $seenMissing[$asset] = $true
            $missingAssets.Add($asset)
        }
    }

    $unavailableAssets = New-CaseInsensitiveHashtable
    foreach ($asset in $missingAssets) {
        $unavailableAssets[$asset] = $true
    }

    if ($missingAssets.Count -gt 0) {
        throw ("Legacy import found item image references unavailable in both source and target item image directories: {0}" -f ($missingAssets.ToArray() -join ', '))
    }

    return $unavailableAssets
}

function Test-TruthyLegacySetting {
    param([AllowNull()][string]$Value)

    return (([string]$Value).Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on'))
}

function Apply-LegacyPositionLocks {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$SourceVariables
    )

    $lockSpecs = @(
        @{
            RelativePath = '@Resources\Customs\Settings\Hotbar.inc'
            Key = 'LockHotbarPosition'
            Targets = @('Hotbar')
        },
        @{
            RelativePath = '@Resources\Customs\Settings\Inventory.inc'
            Key = 'LockInventoryPosition'
            Targets = @('Inventory', 'InventoryBG')
        },
        @{
            RelativePath = '@Resources\Customs\Settings\Clock.inc'
            Key = 'LockClockPosition'
            Targets = @('Clock')
        },
        @{
            RelativePath = '@Resources\Customs\Settings\Indicators.inc'
            Key = 'LockIndicatorsPosition'
            Targets = @('IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp')
        }
    )

    foreach ($spec in $lockSpecs) {
        $settingsPath = Join-RootPath -Root $SourceRoot -RelativePath $spec.RelativePath
        $settingsVariables = Read-VariablesFile -Path $settingsPath
        if (-not $settingsVariables.Contains($spec.Key) -or -not (Test-TruthyLegacySetting -Value $settingsVariables[$spec.Key])) {
            continue
        }

        foreach ($targetName in $spec.Targets) {
            $prefix = "ResponsiveLayout_${targetName}_"
            Set-MapValue -Map $Variables -Key "${prefix}PositionMode" -Value 'fixed'
            foreach ($axis in @('X', 'Y')) {
                $liveKey = "${prefix}LiveWindow${axis}"
                $fixedKey = "${prefix}Fixed${axis}"
                if ($SourceVariables.Contains($liveKey) -and -not [string]::IsNullOrWhiteSpace($SourceVariables[$liveKey])) {
                    Set-MapValue -Map $Variables -Key $fixedKey -Value $SourceVariables[$liveKey]
                }
            }
        }
    }
}

function Clear-ResponsiveLiveState {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables)

    foreach ($key in @($Variables.Keys)) {
        if ($key -match '^ResponsiveLayout_.+_Live') {
            $Variables[$key] = '0'
        }
    }
}

function Reset-ResponsiveLayoutPositionsFromDefaults {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $targetDataRoot = Split-Path -Parent $TargetPath
    $defaultsPath = Join-Path $targetDataRoot 'ResponsiveLayoutDefaults.inc'
    if (-not (Test-Path -LiteralPath $defaultsPath -PathType Leaf)) {
        throw "ResetPositions requires target responsive layout defaults: $defaultsPath"
    }

    $defaultVariables = Read-VariablesFile -Path $defaultsPath
    foreach ($key in @($Variables.Keys)) {
        if ($key -notmatch '^ResponsiveLayout_(.+)_(PositionMode|FixedX|FixedY)$') {
            continue
        }

        $targetId = $matches[1]
        $field = $matches[2]
        $defaultKey = "ResponsiveLayoutDefault_${targetId}_${field}"
        if (-not $defaultVariables.Contains($defaultKey)) {
            throw "ResetPositions target defaults are missing required key '$defaultKey' in $defaultsPath"
        }

        Set-MapValue -Map $Variables -Key $key -Value $defaultVariables[$defaultKey]
    }
}

function Merge-ResponsiveLayoutState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source layout state: $SourcePath"
        return
    }

    $targetVariables = Read-VariablesFile -Path $TargetPath
    $sourceVariables = Read-VariablesFile -Path $SourcePath
    foreach ($key in $sourceVariables.Keys) {
        if ($key -match '_Live') {
            continue
        }
        if (-not $targetVariables.Contains($key)) {
            continue
        }
        Set-MapValue -Map $targetVariables -Key $key -Value $sourceVariables[$key]
    }

    Apply-LegacyPositionLocks -Variables $targetVariables -SourceRoot $SourceRoot -SourceVariables $sourceVariables

    if ($ResetPositions) {
        Reset-ResponsiveLayoutPositionsFromDefaults -Variables $targetVariables -TargetPath $TargetPath
        Write-Log 'ResetPositions enabled: layout PositionMode/FixedX/FixedY values were restored from target responsive defaults.'
    }

    Clear-ResponsiveLiveState -Variables $targetVariables

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge responsive layout state' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Copy-PlayerSkinCacheFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$TargetDirectory
    )

    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        Write-Log "Skipped missing source player skin cache directory: $SourceDirectory"
        return
    }
    if (Test-SkippedSourcePath -Path $SourceDirectory) {
        Write-Log "Skipped source player skin cache directory marked unreadable during preflight: $SourceDirectory" 'WARN'
        return
    }

    $sourceBase = [System.IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\', '/') + '\'
    foreach ($file in (Get-SourceDirectoryFilesLoopSafe -SourceDirectory $SourceDirectory)) {
        if (Test-SkippedSourcePath -Path $file) {
            continue
        }

        $leafName = [System.IO.Path]::GetFileName($file)
        if ($leafName -notlike 'MinecraftSkinBody_*.png' -and $leafName -notlike 'MinecraftSkinTexture_*.png') {
            continue
        }

        $relative = $file.Substring($sourceBase.Length)
        $targetFile = Join-RootPath -Root $TargetDirectory -RelativePath $relative
        Assert-SafeTargetPath -Path $targetFile

        if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
            $sourceHash = Get-Sha256HashString -Path $file
            $targetHash = Get-Sha256HashString -Path $targetFile
            if ($sourceHash -eq $targetHash) {
                Write-Log "Skipped existing identical player skin cache file: $targetFile"
                continue
            }

            $null = Invoke-MigrationAction -Action 'Overwrite player skin cache file' -Target $targetFile -ScriptBlock {
                Ensure-Directory -Path (Split-Path -Parent $targetFile)
                Copy-Item -LiteralPath $file -Destination $targetFile -Force
            }
            continue
        }

        $null = Invoke-MigrationAction -Action 'Copy player skin cache file' -Target $targetFile -ScriptBlock {
            Ensure-Directory -Path (Split-Path -Parent $targetFile)
            Copy-Item -LiteralPath $file -Destination $targetFile -Force
        }
    }
}
