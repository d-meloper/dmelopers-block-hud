# ImportFromOldVersion helpers - Settings layout and image catalogs

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-SettingsBackfill {
    param([Parameter(Mandatory = $true)][string]$FileName)

    switch ($FileName) {
        'General.inc' {
            $values = @{
                BaseFont = 'Galmuri9 Regular'
                UseClickSound = '1'
                ShowMissingHintText = '1'
                EnableRainmeterStartup = '0'
                EnableRainmeterFastStartup = '0'
                ItemCountTextFontSize = '18'
                LanguageCode = 'ko-KR'
                EnableHudMirrorMode = '0'
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
                ClockTextWeight = '0'
                ClockTextBorderSize = '0'
                ClockTextBorderColor = '0,0,0'
                ClockTextShadowYOffset = '0'
                ClockTextShadowColor = '0,0,0'
                ClockTextShadowBlur = '0'
                ClockTextShadowOpacity = '50'
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
                MinecraftSkinAtlasPath = ''
                MinecraftSkinAtlasPathVerified = '0'
                MinecraftSkinAtlasManaged = '0'
            })
        }
        'HudMirror.inc' {
            $values = @{
                HudMirrorSchemaVersion = '1'
                AllowHudMirrorReplicaDrag = '0'
                AllowHudMirrorReplicaSnapEdges = '0'
            }
            $targetIds = @('Hotbar', 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp', 'Clock', 'ClockSprite')
            for ($slot = 1; $slot -le 31; $slot++) {
                $slotId = '{0:D2}' -f $slot
                $values["HudMirrorSlot${slotId}Fingerprint"] = ''
                $values["HudMirrorSlot${slotId}Selection"] = '0'
                foreach ($targetId in $targetIds) {
                    $values["HudMirrorSlot${slotId}${targetId}Position"] = ''
                }
            }
            return (New-BackfillMap -Values $values)
        }
        default {
            return $null
        }
    }
}

# DMEL_COMPAT:import.hud-mirror-settings-v1
function Assert-HudMirrorImportSettings {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if (-not $Variables.Contains('HudMirrorSchemaVersion') -or [string]$Variables['HudMirrorSchemaVersion'] -ne '1') {
        throw "Unsupported HUD mirror settings schema in $Context"
    }
    foreach ($key in @('AllowHudMirrorReplicaDrag', 'AllowHudMirrorReplicaSnapEdges')) {
        if (-not $Variables.Contains($key) -or [string]$Variables[$key] -notmatch '^[01]$') {
            throw "Invalid HUD mirror boolean '$key' in $Context"
        }
    }

    $fingerprintPattern = '^-?\d+,-?\d+,\d+,\d+\|-?\d+,-?\d+,\d+,\d+$'
    $number = '[+-]?(?:\d+(?:\.\d*)?|\.\d+)'
    $positionPattern = "^${number},${number}$"
    $targetIds = @('Hotbar', 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp', 'Clock', 'ClockSprite')
    $seenFingerprints = New-CaseInsensitiveHashtable

    for ($slot = 1; $slot -le 31; $slot++) {
        $slotId = '{0:D2}' -f $slot
        $fingerprintKey = "HudMirrorSlot${slotId}Fingerprint"
        $selectionKey = "HudMirrorSlot${slotId}Selection"
        $fingerprint = if ($Variables.Contains($fingerprintKey)) { ([string]$Variables[$fingerprintKey]).Trim() } else { '' }
        if ($fingerprint -ne '' -and $fingerprint -notmatch $fingerprintPattern) {
            throw "Invalid HUD mirror fingerprint for slot $slotId in $Context"
        }
        if ($fingerprint -ne '') {
            if ($seenFingerprints.ContainsKey($fingerprint)) {
                throw "Duplicate HUD mirror fingerprint in $Context"
            }
            $seenFingerprints[$fingerprint] = $true
        }

        $selectionLiteral = if ($Variables.Contains($selectionKey)) { ([string]$Variables[$selectionKey]).Trim() } else { '0' }
        $selection = 0
        if (-not [int]::TryParse($selectionLiteral, [ref]$selection) -or $selection -lt 0 -or $selection -gt 511) {
            throw "Invalid HUD mirror selection for slot $slotId in $Context"
        }
        if ($fingerprint -eq '' -and $selection -ne 0) {
            throw "HUD mirror slot $slotId selects content without a monitor fingerprint in $Context"
        }

        foreach ($targetId in $targetIds) {
            $positionKey = "HudMirrorSlot${slotId}${targetId}Position"
            $position = if ($Variables.Contains($positionKey)) { ([string]$Variables[$positionKey]).Trim() } else { '' }
            if ($position -ne '' -and $position -notmatch $positionPattern) {
                throw "Invalid HUD mirror position for slot $slotId target $targetId in $Context"
            }
            if ($fingerprint -eq '' -and $position -ne '') {
                throw "HUD mirror slot $slotId stores a position without a monitor fingerprint in $Context"
            }
        }
    }
}

function Assert-HudMirrorImportSourcePreflight {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Settings\HudMirror.inc'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Write-Log "Source HUD mirror settings are absent: $sourcePath; current target defaults will be preserved."
        return
    }

    Test-ReadableSourceFile -Path $sourcePath
    Assert-HudMirrorImportSettings -Variables (Read-VariablesFile -Path $sourcePath) -Context $sourcePath
}

# DMEL_COMPAT:import.pre-v131-zpos-bootstrap
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

    $bootstrapRelativePath = Get-BlockHudBootstrapRelativePath -Root $TargetRoot
    $bootstrapPath = Join-RootPath -Root $TargetRoot -RelativePath (Join-Path $bootstrapRelativePath 'ZPosBootstrap.ini')
    if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
        Write-Log 'Legacy updater z-position bootstrap marker was not armed because Utilities\Bootstrap\ZPosBootstrap.ini is missing from the target.' 'WARN'
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

function Get-TargetFallbackItemImageAssets {
    param(
        [Parameter(Mandatory = $true)][string]$SourceHotbarPath,
        [Parameter(Mandatory = $true)][string]$SourceInventoryPath,
        [string]$SourceEditorDraftPath = '',
        [Parameter(Mandatory = $true)][string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory
    )

    $referencedAssets = New-Object System.Collections.Generic.List[string]
    $seenReferenced = New-CaseInsensitiveHashtable
    $referenceFindings = New-Object System.Collections.Generic.List[object]
    $referenceFindings.Add((Get-ImageReferenceFindingsFromPath -Path $SourceHotbarPath -Context 'source HotbarItems.inc'))
    $referenceFindings.Add((Get-ImageReferenceFindingsFromPath -Path $SourceInventoryPath -Context 'source InventoryItems.inc'))
    if (-not [string]::IsNullOrWhiteSpace($SourceEditorDraftPath)) {
        $referenceFindings.Add((Get-ImageReferenceFindingsFromPath -Path $SourceEditorDraftPath -Context 'active source EditorDraft.inc' -ActiveEditorDraftOnly))
    }

    foreach ($findings in $referenceFindings) {
        foreach ($asset in @($findings.Assets)) {
            if (-not $seenReferenced.ContainsKey($asset)) {
                $seenReferenced[$asset] = $true
                $referencedAssets.Add($asset)
            }
        }
    }

    if ($referencedAssets.Count -eq 0) {
        return @()
    }

    $sourceAssets = New-CaseInsensitiveHashtable
    if (Test-Path -LiteralPath $SourceImageDirectory -PathType Container) {
        foreach ($asset in @(Get-DirectoryItemImageAssets -Directory $SourceImageDirectory)) { $sourceAssets[$asset] = $true }
    }
    $targetAssets = New-CaseInsensitiveHashtable
    if (Test-Path -LiteralPath $TargetImageDirectory -PathType Container) {
        foreach ($asset in @(Get-DirectoryItemImageAssets -Directory $TargetImageDirectory)) { $targetAssets[$asset] = $true }
    }
    $fallbackAssets = New-Object System.Collections.Generic.List[string]
    foreach ($asset in $referencedAssets) {
        if ($sourceAssets.ContainsKey($asset)) {
            continue
        }
        if ($targetAssets.ContainsKey($asset)) {
            $fallbackAssets.Add($asset)
        }
    }

    return $fallbackAssets.ToArray()
}

# DMEL_COMPAT:import.item-gif-atlas-cache-v1
function New-ItemGifAtlasImportPlan {
    param(
        [Parameter(Mandatory = $true)][string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory
    )

    $validSource = New-Object System.Collections.Generic.List[object]
    $validTarget = New-Object System.Collections.Generic.List[object]
    $invalidations = New-Object System.Collections.Generic.List[string]
    foreach ($side in @(
        @{ Name = 'source'; Directory = $SourceImageDirectory; Output = $validSource },
        @{ Name = 'target'; Directory = $TargetImageDirectory; Output = $validTarget }
    )) {
        $directory = [string]$side.Directory
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        $customsRoot = Split-Path -Parent (Split-Path -Parent $directory)
        $manifestPath = Join-Path $customsRoot 'Data\ItemImages.inc'
        $parsed = ConvertFrom-BlockHudItemGifAtlasProfiles -Value (Get-BlockHudItemGifAtlasProfilesValue -ManifestPath $manifestPath)
        foreach ($invalidRecord in @($parsed.InvalidRecords)) {
            $invalidations.Add(('{0}:invalid-profile:{1}' -f $side.Name, [string]$invalidRecord))
        }
        $preservedAtlasNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in @($parsed.Entries)) {
            if (Test-BlockHudItemGifAtlasProfileFiles -Entry $entry -ItemImageDirectory $directory) {
                $side.Output.Add($entry)
                [void]$preservedAtlasNames.Add([string]$entry.AtlasName)
            }
            else {
                $invalidations.Add(('{0}:invalid-authoritative-atlas:{1}' -f $side.Name, [string]$entry.SourceName))
            }
        }
        $atlasDirectory = Join-Path $directory 'atlas'
        if (Test-Path -LiteralPath $atlasDirectory -PathType Container) {
            foreach ($atlasFile in @(Get-SourceDirectoryFilesLoopSafe -SourceDirectory $atlasDirectory)) {
                $atlasName = [System.IO.Path]::GetFileName($atlasFile)
                if (-not $preservedAtlasNames.Contains($atlasName)) {
                    $invalidations.Add(('{0}:orphan-managed-atlas:{1}' -f $side.Name, $atlasName))
                }
            }
        }
    }

    return [PSCustomObject]@{
        SourceEntries = $validSource.ToArray()
        TargetEntries = $validTarget.ToArray()
        Invalidations = $invalidations.ToArray()
    }
}

function Replace-ItemImageDirectoryForImport {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$TargetDirectory,
        [Parameter(Mandatory = $true)][string]$SourceHotbarPath,
        [Parameter(Mandatory = $true)][string]$SourceInventoryPath,
        [string]$SourceEditorDraftPath = '',
        [Parameter(Mandatory = $true)][object]$ItemGifAtlasPlan
    )

    $fallbackAssets = @(Get-TargetFallbackItemImageAssets -SourceHotbarPath $SourceHotbarPath -SourceInventoryPath $SourceInventoryPath -SourceEditorDraftPath $SourceEditorDraftPath -SourceImageDirectory $SourceDirectory -TargetImageDirectory $TargetDirectory)
    $fallbackRoot = ''
    try {
        if ($fallbackAssets.Count -gt 0) {
            $fallbackRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('BlockHudImportImageFallback_' + [guid]::NewGuid().ToString('N'))
            Ensure-Directory -Path $fallbackRoot
            foreach ($asset in $fallbackAssets) {
                $sourceFallback = Join-RootPath -Root $TargetDirectory -RelativePath $asset
                $tempFallback = Join-RootPath -Root $fallbackRoot -RelativePath $asset
                if (Test-Path -LiteralPath $sourceFallback -PathType Leaf) {
                    Ensure-Directory -Path (Split-Path -Parent $tempFallback)
                    Copy-Item -LiteralPath $sourceFallback -Destination $tempFallback -Force
                }
            }
            foreach ($entry in @($ItemGifAtlasPlan.TargetEntries)) {
                if ($fallbackAssets -notcontains [string]$entry.SourceName) { continue }
                $sourceAtlas = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $TargetDirectory -AtlasName ([string]$entry.AtlasName)
                $tempAtlas = Join-Path (Join-Path $fallbackRoot 'atlas') ([string]$entry.AtlasName)
                Ensure-Directory -Path (Split-Path -Parent $tempAtlas)
                Copy-Item -LiteralPath $sourceAtlas -Destination $tempAtlas -Force
            }
        }

        Replace-DirectorySnapshot -SourceDirectory $SourceDirectory -TargetDirectory $TargetDirectory
        $targetAtlasDirectory = Join-Path $TargetDirectory 'atlas'
        Clear-TargetPath -Path $targetAtlasDirectory
        Ensure-Directory -Path $targetAtlasDirectory
        $installedProfiles = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($ItemGifAtlasPlan.SourceEntries)) {
            $sourceAtlas = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $SourceDirectory -AtlasName ([string]$entry.AtlasName)
            $targetAtlas = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $TargetDirectory -AtlasName ([string]$entry.AtlasName)
            Copy-Item -LiteralPath $sourceAtlas -Destination $targetAtlas -Force
            $installedProfiles.Add($entry)
        }

        foreach ($asset in $fallbackAssets) {
            $tempFallback = Join-RootPath -Root $fallbackRoot -RelativePath $asset
            if (Test-Path -LiteralPath $tempFallback -PathType Leaf) {
                $targetFallback = Join-RootPath -Root $TargetDirectory -RelativePath $asset
                Assert-SafeTargetPath -Path $targetFallback
                if (-not (Test-Path -LiteralPath $targetFallback -PathType Leaf)) {
                    $null = Invoke-MigrationAction -Action 'Restore target-only fallback item image' -Target $targetFallback -ScriptBlock {
                        Ensure-Directory -Path (Split-Path -Parent $targetFallback)
                        Copy-Item -LiteralPath $tempFallback -Destination $targetFallback -Force
                    }
                }
            }
            foreach ($entry in @($ItemGifAtlasPlan.TargetEntries)) {
                if (-not [string]::Equals([string]$entry.SourceName, [string]$asset, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $tempAtlas = Join-Path (Join-Path $fallbackRoot 'atlas') ([string]$entry.AtlasName)
                $targetAtlas = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $TargetDirectory -AtlasName ([string]$entry.AtlasName)
                if (Test-Path -LiteralPath $tempAtlas -PathType Leaf) {
                    Copy-Item -LiteralPath $tempAtlas -Destination $targetAtlas -Force
                    $installedProfiles.Add($entry)
                }
            }
        }
        foreach ($entry in @($installedProfiles.ToArray())) {
            $authoritativeSourcePath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $TargetDirectory -AssetName ([string]$entry.SourceName)
            if (Test-Path -LiteralPath $authoritativeSourcePath -PathType Leaf) {
                Clear-TargetPath -Path $authoritativeSourcePath
            }
        }
        $script:ImportedItemGifAtlasProfiles = ConvertTo-BlockHudItemGifAtlasProfiles -Entries @($installedProfiles.ToArray())
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($fallbackRoot) -and (Test-Path -LiteralPath $fallbackRoot)) {
            $resolvedFallbackRoot = [System.IO.Path]::GetFullPath($fallbackRoot)
            $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
            if ($resolvedFallbackRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
                (Split-Path -Leaf $resolvedFallbackRoot).StartsWith('BlockHudImportImageFallback_', [System.StringComparison]::Ordinal)) {
                Remove-Item -LiteralPath $resolvedFallbackRoot -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
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
        'Support.inc',
        'HudMirror.inc'
    )

    foreach ($fileName in $targetFiles) {
        $targetPath = Join-RootPath -Root $targetSettings -RelativePath $fileName
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Write-Log "Skipped settings file not present in the current target: $fileName"
            continue
        }

        $sourcePath = Join-RootPath -Root $sourceSettings -RelativePath $fileName
        $backfill = Get-SettingsBackfill -FileName $fileName
        if ($fileName -eq 'HudMirror.inc' -and (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Assert-HudMirrorImportSettings -Variables (Read-VariablesFile -Path $sourcePath) -Context $sourcePath
        }
        $excludeKeyPatterns = @()
        if ($fileName -eq 'General.inc') {
            $excludeKeyPatterns = @('^EnableHudMirrorMode$')
        }
        elseif ($fileName -eq 'HudMirror.inc') {
            $excludeKeyPatterns = @('^HudMirrorSchemaVersion$')
        }
        elseif ($fileName -eq 'Support.inc') {
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

# DMEL_COMPAT:import.low-spec-single-toggle
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
        [string]$Fallback = 'en-US',
        [string]$SkinRoot = ''
    )

    $registry = Read-LanguageRegistry -SkinRoot $SkinRoot
    $resolved = Resolve-RegisteredLanguageCode -Registry $registry -Value $Value -Fallback $Fallback
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        return $resolved
    }

    'en-US'
}

function Resolve-TargetLanguageFallback {
    param([AllowNull()][string]$TargetRoot)

    if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        return 'en-US'
    }

    foreach ($settingsRoot in @('@Resources\Customs\Settings', '@Resources\Defaults\Settings')) {
        $path = Join-RootPath -Root $TargetRoot -RelativePath (Join-Path $settingsRoot 'General.inc')
        $variables = Read-VariablesFile -Path $path
        if ($variables.Contains('LanguageCode') -and -not [string]::IsNullOrWhiteSpace([string]$variables['LanguageCode'])) {
            return (Normalize-LanguageCode -Value $variables['LanguageCode'] -Fallback 'en-US' -SkinRoot $TargetRoot)
        }
    }

    'en-US'
}

function Resolve-ImportedLanguageCode {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [AllowNull()][string]$TargetRoot = ''
    )

    $fallbackLanguageCode = Resolve-TargetLanguageFallback -TargetRoot $TargetRoot
    $registryRoot = if ([string]::IsNullOrWhiteSpace($TargetRoot)) { $SourceRoot } else { $TargetRoot }
    $sourceGeneralPath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Settings\General.inc'
    $sourceVariables = Read-VariablesFile -Path $sourceGeneralPath
    if ($sourceVariables.Contains('LanguageCode')) {
        return (Normalize-LanguageCode -Value $sourceVariables['LanguageCode'] -Fallback $fallbackLanguageCode -SkinRoot $registryRoot)
    }

    return $fallbackLanguageCode
}

function Get-ReservedInventoryItemLabel {
    param(
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [string]$TargetRoot = ''
    )

    $registry = Read-LanguageRegistry -SkinRoot $TargetRoot
    $resolvedLanguageCode = Normalize-LanguageCode -Value $LanguageCode -Fallback $registry.DefaultFallbackLanguageCode -SkinRoot $TargetRoot
    foreach ($entry in @($registry.Entries)) {
        if ([string]::Equals([string]$entry.Code, $resolvedLanguageCode, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$entry.InventoryLabel)) {
            return [string]$entry.InventoryLabel
        }
    }

    return 'Inventory'
}

function New-HotbarSlot10ReservedBackfill {
    param(
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [string]$TargetRoot = ''
    )

    return (New-BackfillMap -Values @{
        HotbarItem_Slot10_Image = 'more.png'
        HotbarItem_Slot10_Label = Get-ReservedInventoryItemLabel -LanguageCode $LanguageCode -TargetRoot $TargetRoot
        HotbarItem_Slot10_Action = '_OPEN_INVENTORY_'
        HotbarItem_Slot10_Qty = '0'
    })
}

function Normalize-HotbarSlot10ReservedLabel {
    param(
        [Parameter(Mandatory = $true)][string]$TargetHotbarPath,
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [string]$TargetRoot = ''
    )

    $hotbarVariables = Read-VariablesFile -Path $TargetHotbarPath
    if (-not (Test-ReservedHotbarSlot10Section -Variables $hotbarVariables -Prefix 'HotbarItem_Slot10')) {
        return
    }

    $label = Get-ReservedInventoryItemLabel -LanguageCode $LanguageCode -TargetRoot $TargetRoot
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

    $resolvedLanguageCode = Normalize-LanguageCode -Value $LanguageCode -Fallback 'en-US' -SkinRoot $TargetRoot
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

    $helperCacheScript = Get-BlockHudRuntimeToolPath -Root $TargetRoot -RelativeToolPath 'UpdateHelperLocalizationCache.ps1'
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
    Set-MapValue -Map $targetVariables -Key 'ItemImageAtlasProfiles' -Value ([string]$script:ImportedItemGifAtlasProfiles)

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
        [hashtable]$ImageRenameMap,
        [Parameter(Mandatory = $true)]
        [string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)]
        [string]$TargetImageDirectory
    )

    $targetVariables = Read-VariablesFile -Path $TargetPath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source image adjustments: $SourcePath"
        return
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath
    $sourceAdjustmentKeys = New-CaseInsensitiveHashtable
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $SourceImageDirectory)) {
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value $asset
        if (-not [string]::IsNullOrWhiteSpace($adjustKey)) {
            $sourceAdjustmentKeys[$adjustKey] = $true
        }
    }
    $targetAdjustmentKeys = New-CaseInsensitiveHashtable
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $TargetImageDirectory)) {
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value $asset
        if (-not [string]::IsNullOrWhiteSpace($adjustKey)) {
            $targetAdjustmentKeys[$adjustKey] = $true
        }
    }
    $pendingTargetProfiles = ConvertFrom-BlockHudItemGifAtlasProfiles -Value ([string]$script:ImportedItemGifAtlasProfiles)
    foreach ($entry in @($pendingTargetProfiles.Entries)) {
        if (-not (Test-BlockHudItemGifAtlasProfileFiles -Entry $entry -ItemImageDirectory $TargetImageDirectory)) { continue }
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value ([string]$entry.SourceName)
        if (-not [string]::IsNullOrWhiteSpace($adjustKey)) { $targetAdjustmentKeys[$adjustKey] = $true }
    }

    foreach ($key in $sourceVariables.Keys) {
        if ($key -eq 'ImageAdjustKeys') {
            continue
        }

        if ($key -notmatch '^ImageAdjust_(.+)_(OffsetX|OffsetY|SizeOffset)$') {
            continue
        }

        $sourceAdjustKey = $matches[1]
        $suffix = $matches[2]
        if (-not $sourceAdjustmentKeys.ContainsKey($sourceAdjustKey)) {
            continue
        }
        $renamedAdjustKey = Get-ImageAdjustmentKeyForMigration -Value (Rename-ImageValue -Value $sourceAdjustKey -RenameMap $ImageRenameMap)
        if ($renamedAdjustKey.Length -eq 0 -or -not $targetAdjustmentKeys.ContainsKey($renamedAdjustKey)) {
            continue
        }

        Set-MapValue -Map $targetVariables -Key "ImageAdjust_${renamedAdjustKey}_${suffix}" -Value $sourceVariables[$key]
    }

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge image adjustments' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Assert-ImportedImageAdjustmentIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory,
        [hashtable]$ImageRenameMap
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return
    }

    $sourceAssets = New-CaseInsensitiveHashtable
    $sourceProfiles = @(Get-BlockHudValidItemGifAtlasProfiles -ItemImageDirectory $SourceImageDirectory)
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $SourceImageDirectory)) {
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value $asset
        if (-not [string]::IsNullOrWhiteSpace($adjustKey)) {
            $sourceAssets[$adjustKey] = Resolve-BlockHudItemImageBackingPath -ItemImageDirectory $SourceImageDirectory -AssetName $asset -ValidAtlasProfiles $sourceProfiles
        }
    }
    $targetAssets = New-CaseInsensitiveHashtable
    $targetProfiles = @(Get-BlockHudValidItemGifAtlasProfiles -ItemImageDirectory $TargetImageDirectory)
    foreach ($asset in (Get-DirectoryItemImageAssets -Directory $TargetImageDirectory)) {
        $adjustKey = Get-ImageAdjustmentKeyForMigration -Value $asset
        if (-not [string]::IsNullOrWhiteSpace($adjustKey)) {
            $targetAssets[$adjustKey] = Resolve-BlockHudItemImageBackingPath -ItemImageDirectory $TargetImageDirectory -AssetName $asset -ValidAtlasProfiles $targetProfiles
        }
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath
    $targetVariables = Read-VariablesFile -Path $TargetPath
    foreach ($key in $sourceVariables.Keys) {
        if ($key -notmatch '^ImageAdjust_(.+)_(OffsetX|OffsetY|SizeOffset)$') {
            continue
        }

        $sourceAdjustKey = $matches[1]
        $suffix = $matches[2]
        if (-not $sourceAssets.ContainsKey($sourceAdjustKey)) {
            continue
        }
        $targetAdjustKey = Get-ImageAdjustmentKeyForMigration -Value (Rename-ImageValue -Value $sourceAdjustKey -RenameMap $ImageRenameMap)
        if ([string]::IsNullOrWhiteSpace($targetAdjustKey) -or -not $targetAssets.ContainsKey($targetAdjustKey)) {
            continue
        }

        $targetKey = "ImageAdjust_${targetAdjustKey}_${suffix}"
        if (-not $targetVariables.Contains($targetKey) -or [string]$targetVariables[$targetKey] -cne [string]$sourceVariables[$key]) {
            throw "Imported image adjustment integrity validation failed for $targetKey."
        }
        if ((Get-Sha256HashString -Path ([string]$sourceAssets[$sourceAdjustKey])) -ne
            (Get-Sha256HashString -Path ([string]$targetAssets[$targetAdjustKey]))) {
            throw "Imported image adjustment asset hash validation failed for $targetAdjustKey."
        }
    }

    Write-Log 'Imported image adjustment values passed post-import integrity validation.'
}

function Get-ImageReferenceFindingsFromVariables {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $assets = New-Object System.Collections.Generic.List[string]
    $invalidReferences = New-Object System.Collections.Generic.List[string]
    $seen = New-CaseInsensitiveHashtable
    foreach ($key in $Variables.Keys) {
        if ($key -notmatch '_(Image)$') {
            continue
        }

        $rawValue = [string]$Variables[$key]
        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            continue
        }

        $asset = Normalize-ImageAssetForMigration -Value $rawValue
        if ([string]::IsNullOrWhiteSpace($asset)) {
            $invalidReferences.Add(("{0}:{1}={2}" -f $Context, $key, $rawValue))
            continue
        }
        if ($asset.Equals('more.png', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (Test-AllowedReservedItemImageReference -Variables $Variables -Context $Context -Key ([string]$key)) {
                continue
            }
            $invalidReferences.Add(("{0}:{1}={2}" -f $Context, $key, $rawValue))
            continue
        }
        if (-not $seen.ContainsKey($asset)) {
            $seen[$asset] = $true
            $assets.Add($asset)
        }
    }

    return [pscustomobject]@{
        Assets = $assets.ToArray()
        InvalidReferences = $invalidReferences.ToArray()
    }
}

function Get-ImageReferenceFindingsFromPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$ActiveEditorDraftOnly
    )

    $empty = [pscustomobject]@{
        Assets = @()
        InvalidReferences = @()
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $empty
    }

    $variables = Read-VariablesFile -Path $Path
    if ($ActiveEditorDraftOnly -and -not (Test-EditorDraftActive -DraftVariables $variables)) {
        return $empty
    }

    return (Get-ImageReferenceFindingsFromVariables -Variables $variables -Context $Context)
}

function Get-ReferencedImageAssetsFromVariables {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables)

    return (Get-ImageReferenceFindingsFromVariables -Variables $Variables -Context 'source item data').Assets
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
        [string]$SourceEditorDraftPath = '',
        [Parameter(Mandatory = $true)][string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory
    )

    $referencedAssets = New-Object System.Collections.Generic.List[string]
    $invalidReferences = New-Object System.Collections.Generic.List[string]
    $referenceFindings = New-Object System.Collections.Generic.List[object]
    $referenceFindings.Add((Get-ImageReferenceFindingsFromPath -Path $SourceHotbarPath -Context 'source HotbarItems.inc'))
    $referenceFindings.Add((Get-ImageReferenceFindingsFromPath -Path $SourceInventoryPath -Context 'source InventoryItems.inc'))
    if (-not [string]::IsNullOrWhiteSpace($SourceEditorDraftPath)) {
        $referenceFindings.Add((Get-ImageReferenceFindingsFromPath -Path $SourceEditorDraftPath -Context 'active source EditorDraft.inc' -ActiveEditorDraftOnly))
    }

    foreach ($findings in $referenceFindings) {
        foreach ($invalidReference in @($findings.InvalidReferences)) {
            $invalidReferences.Add($invalidReference)
        }
        foreach ($asset in @($findings.Assets)) {
            $referencedAssets.Add($asset)
        }
    }

    if ($invalidReferences.Count -gt 0) {
        throw ("Legacy import found invalid item image references in source item data: {0}" -f ($invalidReferences.ToArray() -join ', '))
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

function Test-SourceResponsiveLayoutHasMonitorAffinitySchema {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$SourceVariables)

    foreach ($key in $SourceVariables.Keys) {
        if ([string]$key -match '^ResponsiveLayout_.+_Monitor(Fingerprint|RelativeX|RelativeY)$') {
            return $true
        }
    }

    return $false
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

    if (Test-SourceResponsiveLayoutHasMonitorAffinitySchema -SourceVariables $SourceVariables) {
        return
    }

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
            foreach ($field in @('MonitorFingerprint', 'MonitorRelativeX', 'MonitorRelativeY')) {
                Set-MapValue -Map $Variables -Key "${prefix}${field}" -Value ''
            }
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

    if ($Variables.Contains('ResponsiveLayout_Jukebox_FormResetPending')) {
        $Variables['ResponsiveLayout_Jukebox_FormResetPending'] = '0'
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
        if ($key -notmatch '^ResponsiveLayout_(.+)_(PositionMode|FixedX|FixedY|MonitorFingerprint|MonitorRelativeX|MonitorRelativeY)$') {
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
        if ($key -match '_Live' -or $key -eq 'ResponsiveLayout_Jukebox_FormResetPending') {
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
        Write-Log 'ResetPositions enabled: layout PositionMode/FixedX/FixedY and monitor-affinity values were restored from target responsive defaults.'
    }

    Clear-ResponsiveLiveState -Variables $targetVariables

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge responsive layout state' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

# DMEL_COMPAT:import.player-cache-derived-invalidation
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
    $sourceFiles = @(Get-SourceDirectoryFilesLoopSafe -SourceDirectory $SourceDirectory)
    $sourceBodies = @{}
    $sourceTextures = @{}
    foreach ($file in $sourceFiles) {
        if (Test-SkippedSourcePath -Path $file) {
            continue
        }
        $leafName = [System.IO.Path]::GetFileName($file)
        if ($leafName -match '^MinecraftSkinBody_(.+)\.png$') {
            $sourceBodies[$matches[1]] = $file
        }
        elseif ($leafName -match '^MinecraftSkinTexture_(.+)\.png$') {
            $sourceTextures[$matches[1]] = $file
        }
    }

    foreach ($cacheKey in $sourceTextures.Keys) {
        $targetTexture = Join-Path $TargetDirectory ("MinecraftSkinTexture_{0}.png" -f $cacheKey)
        $textureChanged = -not (Test-Path -LiteralPath $targetTexture -PathType Leaf)
        if (-not $textureChanged) {
            $textureChanged = (Get-Sha256HashString -Path $sourceTextures[$cacheKey]) -ne (Get-Sha256HashString -Path $targetTexture)
        }
        if ($textureChanged) {
            Remove-PlayerSkinDerivedCacheFiles -TargetDirectory $TargetDirectory -CacheKey $cacheKey
        }
    }

    foreach ($cacheKey in $sourceBodies.Keys) {
        if ($sourceTextures.ContainsKey($cacheKey)) {
            continue
        }
        $targetBody = Join-Path $TargetDirectory ("MinecraftSkinBody_{0}.png" -f $cacheKey)
        $bodyChanged = -not (Test-Path -LiteralPath $targetBody -PathType Leaf)
        if (-not $bodyChanged) {
            $bodyChanged = (Get-Sha256HashString -Path $sourceBodies[$cacheKey]) -ne (Get-Sha256HashString -Path $targetBody)
        }
        if ($bodyChanged) {
            Remove-PlayerSkinDerivedCacheFiles -TargetDirectory $TargetDirectory -CacheKey $cacheKey -RemoveTexture
        }
    }

    foreach ($file in $sourceFiles) {
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

    $cacheModulePath = [System.IO.Path]::GetFullPath((Join-Path $TargetDirectory '..\..\..\Defaults\Runtime\helpers\MinecraftSkinLookAtlasCache.Common.ps1'))
    if (-not (Test-Path -LiteralPath $cacheModulePath -PathType Leaf)) {
        Write-Log "Skipped player atlas import because the target cache module is missing: $cacheModulePath" 'WARN'
        return
    }
    . $cacheModulePath
    $sourceAtlasByName = @{}
    foreach ($file in $sourceFiles) {
        $leafName = [System.IO.Path]::GetFileName($file)
        if ($leafName -notmatch '^MinecraftSkinLookAtlas_v([12])_(.+)_(wide|slim)\.png$') {
            continue
        }
        $relativeParent = ([string][System.IO.Path]::GetDirectoryName($file.Substring($sourceBase.Length))).Trim('.', '\', '/')
        if ($relativeParent -ne '' -and $relativeParent -ine 'atlas') {
            continue
        }
        if (-not $sourceAtlasByName.ContainsKey($leafName) -or $relativeParent -ieq 'atlas') {
            $sourceAtlasByName[$leafName] = $file
        }
    }

    foreach ($leafName in $sourceAtlasByName.Keys) {
        $sourceAtlasPath = $sourceAtlasByName[$leafName]
        $match = [System.Text.RegularExpressions.Regex]::Match($leafName, '^MinecraftSkinLookAtlas_v([12])_(.+)_(wide|slim)\.png$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $version = [int]$match.Groups[1].Value
        $cacheKey = $match.Groups[2].Value
        $model = $match.Groups[3].Value.ToLowerInvariant()
        $sourceBodyPath = Join-Path $SourceDirectory ("MinecraftSkinBody_{0}.png" -f $cacheKey)
        $targetBodyPath = Join-Path $TargetDirectory ("MinecraftSkinBody_{0}.png" -f $cacheKey)
        if (-not (Test-Path -LiteralPath $sourceBodyPath -PathType Leaf) -or -not (Test-Path -LiteralPath $targetBodyPath -PathType Leaf) -or
            (Get-Sha256HashString -Path $sourceBodyPath) -ne (Get-Sha256HashString -Path $targetBodyPath) -or
            -not (Test-BlockHudMinecraftSkinLookAtlas -Path $sourceAtlasPath)) {
            continue
        }
        $sourceTexturePath = Join-Path $SourceDirectory ("MinecraftSkinTexture_{0}.png" -f $cacheKey)
        $targetTexturePath = Join-Path $TargetDirectory ("MinecraftSkinTexture_{0}.png" -f $cacheKey)
        $hasTexture = Test-Path -LiteralPath $sourceTexturePath -PathType Leaf
        if ($hasTexture -and (-not (Test-Path -LiteralPath $targetTexturePath -PathType Leaf) -or
            (Get-Sha256HashString -Path $sourceTexturePath) -ne (Get-Sha256HashString -Path $targetTexturePath))) {
            continue
        }

        $sourceSidecarPath = [System.IO.Path]::ChangeExtension($sourceAtlasPath, '.render-v2')
        $sourceSidecarValid = $version -eq 2 -and (Test-BlockHudMinecraftSkinLookAtlasSidecar `
            -Path $sourceSidecarPath -CacheKey $cacheKey -Model $model `
            -TexturePath $(if ($hasTexture) { $sourceTexturePath } else { '' }) `
            -BodyPath $sourceBodyPath -AtlasPath $sourceAtlasPath)
        if ($version -eq 2 -and -not $sourceSidecarValid -and $hasTexture) {
            $sourceMarkerPath = Get-BlockHudMinecraftSkinRenderMarkerPath -OutputDirectory $SourceDirectory -CacheKey $cacheKey
            if (-not (Test-BlockHudMinecraftSkinRenderMarker -Path $sourceMarkerPath -Model $model -TexturePath $sourceTexturePath) -or
                [System.IO.File]::GetLastWriteTimeUtc($sourceAtlasPath) -lt [System.IO.File]::GetLastWriteTimeUtc($sourceTexturePath)) {
                continue
            }
        }

        $targetAtlasDirectory = Join-Path $TargetDirectory 'atlas'
        $targetAtlasPath = Get-BlockHudMinecraftSkinLookAtlasPath -OutputDirectory $TargetDirectory -CacheKey $cacheKey -Model $model
        $targetSidecarPath = [System.IO.Path]::ChangeExtension($targetAtlasPath, '.render-v2')
        if (Test-BlockHudMinecraftSkinLookAtlasSidecar `
            -Path $targetSidecarPath -CacheKey $cacheKey -Model $model `
            -TexturePath $(if ($hasTexture) { $targetTexturePath } else { '' }) `
            -BodyPath $targetBodyPath -AtlasPath $targetAtlasPath) {
            continue
        }
        $null = Invoke-MigrationAction -Action 'Normalize imported player skin atlas cache' -Target $targetAtlasPath -ScriptBlock {
            Ensure-Directory -Path $targetAtlasDirectory
            Copy-Item -LiteralPath $sourceAtlasPath -Destination $targetAtlasPath -Force
            Write-BlockHudMinecraftSkinLookAtlasSidecar `
                -Path $targetSidecarPath -CacheKey $cacheKey -Model $model `
                -TexturePath $(if ($hasTexture) { $targetTexturePath } else { '' }) `
                -BodyPath $targetBodyPath -AtlasPath $targetAtlasPath
        }
    }

    foreach ($warning in @(Move-BlockHudLegacyMinecraftSkinLookAtlases -OutputDirectory $TargetDirectory)) {
        Write-Log ('Player atlas cache cleanup warning: ' + [string]$warning) 'WARN'
    }
}

function Remove-PlayerSkinDerivedCacheFiles {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDirectory,
        [Parameter(Mandatory = $true)][string]$CacheKey,
        [switch]$RemoveTexture
    )

    $leafNames = @(
        ("MinecraftSkinBody_{0}.render-v1" -f $CacheKey),
        ("MinecraftSkinLookAtlas_v1_{0}_wide.png" -f $CacheKey),
        ("MinecraftSkinLookAtlas_v1_{0}_slim.png" -f $CacheKey),
        ("MinecraftSkinLookAtlas_v2_{0}_wide.png" -f $CacheKey),
        ("MinecraftSkinLookAtlas_v2_{0}_slim.png" -f $CacheKey),
        ("MinecraftSkinLookAtlas_v2_{0}_wide.render-v2" -f $CacheKey),
        ("MinecraftSkinLookAtlas_v2_{0}_slim.render-v2" -f $CacheKey)
    )
    if ($RemoveTexture) {
        $leafNames += ("MinecraftSkinTexture_{0}.png" -f $CacheKey)
    }

    foreach ($leafName in $leafNames) {
        foreach ($path in @((Join-Path $TargetDirectory $leafName), (Join-Path (Join-Path $TargetDirectory 'atlas') $leafName))) {
            Assert-SafeTargetPath -Path $path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                continue
            }
            $null = Invoke-MigrationAction -Action 'Invalidate imported player skin derived cache' -Target $path -ScriptBlock {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }
}
