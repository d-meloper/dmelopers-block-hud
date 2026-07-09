# ImportFromOldVersion helpers - Player skin editor and orchestration

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-ImportFromOldVersionScriptValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $variable -or $null -eq $variable.Value) {
        return ''
    }

    return [string]$variable.Value
}

function Get-ImportFromOldVersionDefaultTargetRoot {
    $targetRoot = Get-ImportFromOldVersionScriptValue -Name 'ImportFromOldVersionDefaultTargetRoot'
    if (-not [string]::IsNullOrWhiteSpace($targetRoot)) {
        return [System.IO.Path]::GetFullPath($targetRoot)
    }

    $entrypointRoot = Get-ImportFromOldVersionScriptValue -Name 'ImportFromOldVersionEntrypointRoot'
    if (-not [string]::IsNullOrWhiteSpace($entrypointRoot)) {
        return [System.IO.Path]::GetFullPath((Join-Path $entrypointRoot '..'))
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Sanitize-FileComponent {
    param([AllowNull()][string]$Value)

    $resolved = ([string]$Value).Trim()
    if ($resolved.Length -eq 0) {
        return ''
    }

    $resolved = $resolved -replace '[<>:"/\\|\?\*]', '_'
    $resolved = $resolved -replace '[\x00-\x1F]', '_'
    return $resolved.Trim()
}

function Normalize-ImportedMinecraftSkinState {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $supportPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Settings\Support.inc'
    if (-not (Test-Path -LiteralPath $supportPath -PathType Leaf)) {
        return
    }

    $supportVariables = Read-VariablesFile -Path $supportPath
    $username = if ($supportVariables.Contains('MinecraftSkinUsername')) { ([string]$supportVariables['MinecraftSkinUsername']).Trim() } else { '' }
    $currentImagePath = if ($supportVariables.Contains('MinecraftSkinImagePath')) { ([string]$supportVariables['MinecraftSkinImagePath']).Trim() } else { '' }
    $currentTexturePath = if ($supportVariables.Contains('MinecraftSkinTexturePath')) { ([string]$supportVariables['MinecraftSkinTexturePath']).Trim() } else { '' }
    $currentImagePathVerified = if ($supportVariables.Contains('MinecraftSkinImagePathVerified')) { ([string]$supportVariables['MinecraftSkinImagePathVerified']).Trim() } else { '' }
    $playerImageDirectory = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Images\Player'
    $normalizedImagePath = ''
    $normalizedTexturePath = ''

    if ($username -ne '') {
        $imageFileName = ''
        if ($currentImagePath -ne '') {
            try {
                $imageFileName = [System.IO.Path]::GetFileName($currentImagePath)
            }
            catch {
                $imageFileName = ''
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($imageFileName)) {
            $fileNameCandidate = Join-Path $playerImageDirectory $imageFileName
            if (Test-PngFileSignature -Path $fileNameCandidate) {
                $normalizedImagePath = [System.IO.Path]::GetFullPath($fileNameCandidate)
            }
        }

        if ($normalizedImagePath -eq '') {
            $sanitizedUsername = Sanitize-FileComponent -Value $username
            if ($sanitizedUsername -ne '') {
                $expectedPath = Join-Path $playerImageDirectory ("MinecraftSkinBody_{0}.png" -f $sanitizedUsername)
                if (Test-PngFileSignature -Path $expectedPath) {
                    $normalizedImagePath = [System.IO.Path]::GetFullPath($expectedPath)
                }
            }
        }

        $textureFileName = ''
        if ($currentTexturePath -ne '') {
            try {
                $textureFileName = [System.IO.Path]::GetFileName($currentTexturePath)
            }
            catch {
                $textureFileName = ''
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($textureFileName)) {
            $textureFileNameCandidate = Join-Path $playerImageDirectory $textureFileName
            if (Test-PngFileSignature -Path $textureFileNameCandidate) {
                $normalizedTexturePath = [System.IO.Path]::GetFullPath($textureFileNameCandidate)
            }
        }

        if ($normalizedTexturePath -eq '') {
            $sanitizedUsername = Sanitize-FileComponent -Value $username
            if ($sanitizedUsername -ne '') {
                $expectedTexturePath = Join-Path $playerImageDirectory ("MinecraftSkinTexture_{0}.png" -f $sanitizedUsername)
                if (Test-PngFileSignature -Path $expectedTexturePath) {
                    $normalizedTexturePath = [System.IO.Path]::GetFullPath($expectedTexturePath)
                }
            }
        }
    }

    $normalizedImagePathVerified = if ($normalizedImagePath -ne '') { '1' } else { '0' }

    if ($currentImagePath -eq $normalizedImagePath -and $currentTexturePath -eq $normalizedTexturePath -and $currentImagePathVerified -eq $normalizedImagePathVerified) {
        return
    }

    Set-MapValue -Map $supportVariables -Key 'MinecraftSkinImagePath' -Value $normalizedImagePath
    Set-MapValue -Map $supportVariables -Key 'MinecraftSkinTexturePath' -Value $normalizedTexturePath
    Set-MapValue -Map $supportVariables -Key 'MinecraftSkinImagePathVerified' -Value $normalizedImagePathVerified
    $content = ConvertTo-VariablesContent -Variables $supportVariables
    $null = Invoke-MigrationAction -Action 'Normalize imported Minecraft skin cache path' -Target $supportPath -ScriptBlock {
        Write-Utf16Text -Path $supportPath -Content $content
    }
}

function Get-ItemFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [string]$Field
    )

    $key = "${Prefix}_${Field}"
    if ($Variables.Contains($key)) {
        return [string]$Variables[$key]
    }

    return ''
}

function Test-ItemSectionEmpty {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $image = (Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Image').Trim()
    $label = (Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Label').Trim()
    $action = (Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Action').Trim()
    $qty = (Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Qty').Trim()
    return ($image -eq '' -and $label -eq '' -and $action -eq '' -and ($qty -eq '' -or $qty -eq '0'))
}

function Test-ReservedHotbarSlot10Section {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $image = (Normalize-ImageAssetForMigration -Value (Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Image')).ToLowerInvariant()
    $action = (Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Action').Trim()
    return ($image -eq 'more.png' -and $action -eq '_OPEN_INVENTORY_')
}

function Set-ItemSectionValues {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [hashtable]$Values,
        [hashtable]$ImageRenameMap
    )

    foreach ($field in @('Image', 'Label', 'Action', 'Qty')) {
        $value = if ($Values.ContainsKey($field)) { [string]$Values[$field] } else { '' }
        if ($field -eq 'Image') {
            $value = Repair-ImportImageValue -Value $value -ImageRenameMap $ImageRenameMap
        }
        Set-MapValue -Map $Variables -Key "${Prefix}_${field}" -Value $value
    }
}

function Get-ItemSectionValues {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    return @{
        Image = Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Image'
        Label = Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Label'
        Action = Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Action'
        Qty = Get-ItemFieldValue -Variables $Variables -Prefix $Prefix -Field 'Qty'
    }
}

function Find-FirstEmptyInventoryPrefix {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$InventoryVariables)

    for ($y = 1; $y -le 4; $y += 1) {
        for ($x = 1; $x -le 9; $x += 1) {
            $prefix = "InventoryItem_SlotX${x}Y${y}"
            if (Test-ItemSectionEmpty -Variables $InventoryVariables -Prefix $prefix) {
                return $prefix
            }
        }
    }

    return $null
}

function Move-HotbarSlot10ToInventoryIfCustom {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$SourceVariables,
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$InventoryVariables,
        [Parameter(Mandatory = $true)]
        [string]$SourcePrefix,
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [hashtable]$ImageRenameMap
    )

    if ((Test-ItemSectionEmpty -Variables $SourceVariables -Prefix $SourcePrefix) -or (Test-ReservedHotbarSlot10Section -Variables $SourceVariables -Prefix $SourcePrefix)) {
        return $false
    }

    $targetPrefix = Find-FirstEmptyInventoryPrefix -InventoryVariables $InventoryVariables
    if (-not $targetPrefix) {
        Write-Log "$Context slot 10 contains custom data but no empty inventory slot was available; keeping v1.1 inventory button in hotbar slot 10." 'WARN'
        return $false
    }

    Set-ItemSectionValues -Variables $InventoryVariables -Prefix $targetPrefix -Values (Get-ItemSectionValues -Variables $SourceVariables -Prefix $SourcePrefix) -ImageRenameMap $ImageRenameMap
    Write-Log "$Context slot 10 custom data moved to $targetPrefix to preserve the v1.1 inventory button."
    return $true
}

function Move-LegacyHotbarSlot10IfCustom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceHotbarPath,
        [Parameter(Mandatory = $true)]
        [string]$TargetInventoryPath,
        [hashtable]$ImageRenameMap
    )

    if (-not (Test-Path -LiteralPath $SourceHotbarPath -PathType Leaf)) {
        return
    }

    $sourceVariables = Read-VariablesFile -Path $SourceHotbarPath
    $inventoryVariables = Read-VariablesFile -Path $TargetInventoryPath
    $changed = Move-HotbarSlot10ToInventoryIfCustom -SourceVariables $sourceVariables -InventoryVariables $inventoryVariables -SourcePrefix 'HotbarItem_Slot10' -Context 'Legacy hotbar' -ImageRenameMap $ImageRenameMap
    if (-not $changed) {
        return
    }

    $content = ConvertTo-VariablesContent -Variables $inventoryVariables
    $null = Invoke-MigrationAction -Action 'Move custom legacy hotbar slot 10 to inventory' -Target $TargetInventoryPath -ScriptBlock {
        Write-Utf16Text -Path $TargetInventoryPath -Content $content
    }
}

function Test-EditorDraftActive {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$DraftVariables)

    $sourceSchema = if ($DraftVariables.Contains('EditorDraftMeta_SchemaVersion')) { $DraftVariables['EditorDraftMeta_SchemaVersion'] } else { '' }
    if ($sourceSchema -ne '3') {
        return $false
    }

    $isDirty = $DraftVariables.Contains('EditorDraftMeta_Dirty') -and $DraftVariables['EditorDraftMeta_Dirty'] -eq '1'
    $isOpen = $DraftVariables.Contains('EditorDraftMeta_EditorOpen') -and $DraftVariables['EditorDraftMeta_EditorOpen'] -eq '1'
    return ($isDirty -or $isOpen)
}

function Commit-EditorDraftIfActive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetHotbarPath,
        [Parameter(Mandatory = $true)]
        [string]$TargetInventoryPath,
        [hashtable]$ImageRenameMap
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return $false
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath
    if (-not (Test-EditorDraftActive -DraftVariables $sourceVariables)) {
        return $false
    }

    $hotbarVariables = Read-VariablesFile -Path $TargetHotbarPath
    $inventoryVariables = Read-VariablesFile -Path $TargetInventoryPath
    $hotbarChanged = $false
    $inventoryChanged = $false
    $draftSlot10 = New-VariablesMap

    foreach ($key in $sourceVariables.Keys) {
        if ($key -notmatch '^EditorDraftItem_(Slot\d\d|SlotX\dY\d)_(Image|Label|Action|Qty)$') {
            continue
        }

        $slot = $matches[1]
        $field = $matches[2]
        $value = [string]$sourceVariables[$key]
        if ($field -eq 'Image') {
            $value = Repair-ImportImageValue -Value $value -ImageRenameMap $ImageRenameMap
        }

        if ($slot -eq 'Slot10') {
            Set-MapValue -Map $draftSlot10 -Key "DraftSlot10_${field}" -Value $value
            continue
        }

        if ($slot -like 'SlotX*') {
            Set-MapValue -Map $inventoryVariables -Key "InventoryItem_${slot}_${field}" -Value $value
            $inventoryChanged = $true
        }
        else {
            Set-MapValue -Map $hotbarVariables -Key "HotbarItem_${slot}_${field}" -Value $value
            $hotbarChanged = $true
        }
    }

    if ($draftSlot10.Count -gt 0) {
        $slot10Values = New-VariablesMap
        foreach ($field in @('Image', 'Label', 'Action', 'Qty')) {
            $sourceKey = "DraftSlot10_${field}"
            $value = if ($draftSlot10.Contains($sourceKey)) { $draftSlot10[$sourceKey] } else { '' }
            Set-MapValue -Map $slot10Values -Key "DraftSlot10_${field}" -Value $value
        }
        $inventoryChanged = (Move-HotbarSlot10ToInventoryIfCustom -SourceVariables $slot10Values -InventoryVariables $inventoryVariables -SourcePrefix 'DraftSlot10' -Context 'Active editor draft' -ImageRenameMap $ImageRenameMap) -or $inventoryChanged
    }

    if ($hotbarChanged) {
        $hotbarContent = ConvertTo-VariablesContent -Variables $hotbarVariables
        $null = Invoke-MigrationAction -Action 'Commit active editor draft to hotbar' -Target $TargetHotbarPath -ScriptBlock {
            Write-Utf16Text -Path $TargetHotbarPath -Content $hotbarContent
        }
    }
    if ($inventoryChanged) {
        $inventoryContent = ConvertTo-VariablesContent -Variables $inventoryVariables
        $null = Invoke-MigrationAction -Action 'Commit active editor draft to inventory' -Target $TargetInventoryPath -ScriptBlock {
            Write-Utf16Text -Path $TargetInventoryPath -Content $inventoryContent
        }
    }

    return $true
}

function Merge-EditorDraftIfActive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [hashtable]$ImageRenameMap
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source editor draft: $SourcePath"
        return
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath
    $sourceSchema = if ($sourceVariables.Contains('EditorDraftMeta_SchemaVersion')) { $sourceVariables['EditorDraftMeta_SchemaVersion'] } else { '' }
    if ($sourceSchema -ne '3') {
        Write-Log "Skipped incompatible source editor draft schema '$sourceSchema'." 'WARN'
        return
    }

    if (-not (Test-EditorDraftActive -DraftVariables $sourceVariables)) {
        Write-Log 'No active legacy editor draft found to migrate.'
        return
    }

    $targetVariables = Read-VariablesFile -Path $TargetPath
    foreach ($key in $sourceVariables.Keys) {
        $value = $sourceVariables[$key]
        if ($key -match '_Image$') {
            $value = Repair-ImportImageValue -Value $value -ImageRenameMap $ImageRenameMap
        }

        Set-MapValue -Map $targetVariables -Key $key -Value $value
    }

    Set-MapValue -Map $targetVariables -Key 'EditorDraftMeta_Dirty' -Value '0'
    Set-MapValue -Map $targetVariables -Key 'EditorDraftMeta_EditorOpen' -Value '0'
    Set-MapValue -Map $targetVariables -Key 'EditorDraftMeta_HeartbeatClockMs' -Value '0'
    Set-MapValue -Map $targetVariables -Key 'EditorDraftMeta_DragActive' -Value '0'

    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Mirror active editor draft as clean closed draft' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Get-RequiredVariableValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if (-not $Variables.Contains($Key)) {
        throw "$Context is missing required variable '$Key'."
    }

    return [string]$Variables[$Key]
}

function New-CleanEditorDraftVariables {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DraftPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$HotbarVariables,
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$InventoryVariables
    )

    $draftSource = Read-VariablesFile -Path $DraftPath
    $schemaVersion = if ($draftSource.Contains('EditorDraftMeta_SchemaVersion')) {
        [string]$draftSource['EditorDraftMeta_SchemaVersion']
    }
    else {
        '3'
    }

    $draft = New-VariablesMap
    foreach ($entry in @(
        @{ Key = 'EditorDraftMeta_SchemaVersion'; Value = $schemaVersion },
        @{ Key = 'EditorDraftMeta_Dirty'; Value = '0' },
        @{ Key = 'EditorDraftMeta_EditorOpen'; Value = '0' },
        @{ Key = 'EditorDraftMeta_HeartbeatClockMs'; Value = '0' },
        @{ Key = 'EditorDraftMeta_SelectedSource'; Value = 'hotbar' },
        @{ Key = 'EditorDraftMeta_SelectedX'; Value = '1' },
        @{ Key = 'EditorDraftMeta_SelectedY'; Value = '1' },
        @{ Key = 'EditorDraftMeta_SelectedSection'; Value = 'Slot01' },
        @{ Key = 'EditorDraftMeta_DragSource'; Value = '' },
        @{ Key = 'EditorDraftMeta_DragX'; Value = '0' },
        @{ Key = 'EditorDraftMeta_DragY'; Value = '0' },
        @{ Key = 'EditorDraftMeta_DragActive'; Value = '0' }
    )) {
        Set-MapValue -Map $draft -Key $entry.Key -Value $entry.Value
    }

    for ($index = 1; $index -le 10; $index++) {
        $section = 'Slot{0:D2}' -f $index
        foreach ($field in @('Image', 'Label', 'Action', 'Qty')) {
            $sourceKey = "HotbarItem_${section}_$field"
            $draftKey = "EditorDraftItem_${section}_$field"
            Set-MapValue -Map $draft -Key $draftKey -Value (Get-RequiredVariableValue -Variables $HotbarVariables -Key $sourceKey -Context 'imported HotbarItems.inc')
        }
    }

    for ($row = 1; $row -le 4; $row++) {
        for ($column = 1; $column -le 9; $column++) {
            $section = "SlotX${column}Y${row}"
            foreach ($field in @('Image', 'Label', 'Action', 'Qty')) {
                $sourceKey = "InventoryItem_${section}_$field"
                $draftKey = "EditorDraftItem_${section}_$field"
                Set-MapValue -Map $draft -Key $draftKey -Value (Get-RequiredVariableValue -Variables $InventoryVariables -Key $sourceKey -Context 'imported InventoryItems.inc')
            }
        }
    }

    Set-MapValue -Map $draft -Key 'EditorDraftMeta_PageIndex' -Value '1'
    Set-MapValue -Map $draft -Key 'EditorDraftMeta_PickerModalOpen' -Value '0'
    return $draft
}

function Rebuild-EditorDraftFromImportedItems {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $targetData = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data'
    $targetDraftPath = Join-RootPath -Root $targetData -RelativePath 'EditorDraft.inc'
    $hotbarVariables = Read-VariablesFile -Path (Join-RootPath -Root $targetData -RelativePath 'HotbarItems.inc')
    $inventoryVariables = Read-VariablesFile -Path (Join-RootPath -Root $targetData -RelativePath 'InventoryItems.inc')
    $draftVariables = New-CleanEditorDraftVariables -DraftPath $targetDraftPath -HotbarVariables $hotbarVariables -InventoryVariables $inventoryVariables
    $content = ConvertTo-VariablesContent -Variables $draftVariables

    $null = Invoke-MigrationAction -Action 'Rebuild editor draft from imported item data' -Target $targetDraftPath -ScriptBlock {
        Write-Utf16Text -Path $targetDraftPath -Content $content
    }
}

function Ensure-CacheFormat2 {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $cachePath = Join-RootPath -Root $TargetRoot -RelativePath 'Settings\Cache.inc'
    $cacheVariables = Read-VariablesFile -Path $cachePath
    $requiredCache = New-BackfillMap -Values @{
        SettingsPersistentCacheFormatVersion = '2'
        SettingsPersistentCacheFontsLoaded = '0'
        SettingsPersistentCacheFontFamilies = ''
        SettingsPersistentCacheDrivesLoaded = '0'
        SettingsPersistentCacheDriveTargets = ''
        SettingsPersistentCacheStartupAutoRunInitialized = '0'
        SettingsPersistentCacheStartupAutoRunValue = '0'
    }

    $currentFormat = if ($cacheVariables.Contains('SettingsPersistentCacheFormatVersion')) { [string]$cacheVariables['SettingsPersistentCacheFormatVersion'] } else { '' }
    if ($currentFormat -ne '' -and $currentFormat -ne '1' -and $currentFormat -ne '2') {
        throw "Unsupported Settings cache format '$currentFormat'. Aborting instead of rewriting unknown future cache data."
    }

    $changed = $false
    foreach ($key in $requiredCache.Keys) {
        if (-not $cacheVariables.Contains($key)) {
            Set-MapValue -Map $cacheVariables -Key $key -Value $requiredCache[$key]
            $changed = $true
        }
    }
    if (-not $cacheVariables.Contains('SettingsPersistentCacheFormatVersion') -or $cacheVariables['SettingsPersistentCacheFormatVersion'] -ne '2') {
        Set-MapValue -Map $cacheVariables -Key 'SettingsPersistentCacheFormatVersion' -Value '2'
        $changed = $true
    }

    if ($currentFormat -eq '2') {
        if (-not $changed) {
            Write-Log 'Settings cache already uses complete format 2; keeping current cache.'
            return
        }

        $backfilledContent = ConvertTo-VariablesContent -Variables $cacheVariables
        $null = Invoke-MigrationAction -Action 'Backfill Settings cache format 2 fields' -Target $cachePath -ScriptBlock {
            Write-Utf16Text -Path $cachePath -Content $backfilledContent
        }
        return
    }

    $content = ConvertTo-VariablesContent -Variables $cacheVariables
    $null = Invoke-MigrationAction -Action 'Upgrade Settings cache to format 2' -Target $cachePath -ScriptBlock {
        Write-Utf16Text -Path $cachePath -Content $content
    }
}

function Invoke-Migration {
    if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        $TargetRoot = Get-ImportFromOldVersionDefaultTargetRoot
    }

    $resolvedTargetRoot = Resolve-FullPath -Path $TargetRoot
    $script:ResolvedTargetRoot = $resolvedTargetRoot
    Assert-MigrationTargetRoot -Root $resolvedTargetRoot
    $targetVersion = ConvertTo-SkinVersion -VersionText (Get-SkinMetadataVersion -Root $resolvedTargetRoot) -Context 'TargetRoot'

    $sourceSelection = Find-SourceRoot -ResolvedTargetRoot $resolvedTargetRoot -TargetVersion $targetVersion
    $resolvedSourceRoot = $sourceSelection.Path
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedSourceRoot
    Assert-MigrationSourceRoot -Root $resolvedSourceRoot -TargetVersion $targetVersion
    Assert-DifferentRoots -SourceRoot $resolvedSourceRoot -TargetRoot $resolvedTargetRoot
    Assert-RootContainmentPolicy -SourceRoot $resolvedSourceRoot -TargetRoot $resolvedTargetRoot

    if ($resolvedSourceRoot.ToLowerInvariant() -eq $resolvedTargetRoot.ToLowerInvariant()) {
        throw 'SourceRoot and TargetRoot resolve to the same folder. Legacy import aborted.'
    }

    $script:ResolvedSourceRoot = $resolvedSourceRoot
    Assert-NoUnsafeTargetReparsePoints -Context 'target operational state' -Roots @(
        (Join-RootPath -Root $resolvedTargetRoot -RelativePath '@Resources\Customs'),
        (Join-RootPath -Root $resolvedTargetRoot -RelativePath 'Settings')
    )

    $sourceVersionText = Get-SkinMetadataVersion -Root $resolvedSourceRoot
    $targetVersionText = Get-SkinMetadataVersion -Root $resolvedTargetRoot
    $sourceVersion = ConvertTo-SkinVersion -VersionText $sourceVersionText -Context 'SourceRoot'
    Write-Log "TargetRoot: $resolvedTargetRoot"
    Write-Log "TargetVersion: $targetVersionText"
    Write-Log "SourceRoot: $resolvedSourceRoot"
    Write-Log "SourceVersion: $sourceVersionText"

    $sourceData = Join-RootPath -Root $resolvedSourceRoot -RelativePath '@Resources\Customs\Data'
    $targetData = Join-RootPath -Root $resolvedTargetRoot -RelativePath '@Resources\Customs\Data'
    $imageRenameMap = New-CaseInsensitiveHashtable

    $sourceHotbarPath = Join-RootPath -Root $sourceData -RelativePath 'HotbarItems.inc'
    $sourceInventoryPath = Join-RootPath -Root $sourceData -RelativePath 'InventoryItems.inc'
    $targetHotbarPath = Join-RootPath -Root $targetData -RelativePath 'HotbarItems.inc'
    $targetInventoryPath = Join-RootPath -Root $targetData -RelativePath 'InventoryItems.inc'
    $sourceItemImageDirectory = Join-RootPath -Root $resolvedSourceRoot -RelativePath '@Resources\Customs\Images\Items'
    $targetItemImageDirectory = Join-RootPath -Root $resolvedTargetRoot -RelativePath '@Resources\Customs\Images\Items'
    $importedLanguageCode = $null

    if ($ValidateOnly) {
        Preflight-SourceState -SourceRoot $resolvedSourceRoot
        $importedLanguageCode = Resolve-ImportedLanguageCode -SourceRoot $resolvedSourceRoot
        Assert-MigrationTargetImportState -Root $resolvedTargetRoot -ImportedLanguageCode $importedLanguageCode
        Assert-ImportableItemImageReferences -SourceHotbarPath $sourceHotbarPath -SourceInventoryPath $sourceInventoryPath -SourceImageDirectory $sourceItemImageDirectory -TargetImageDirectory $targetItemImageDirectory

        Write-Log 'Legacy import validation passed.'
        return
    }

    Use-CanonicalTargetLogPath -TargetRoot $resolvedTargetRoot -Prefix 'ImportFromOldVersion'
    Preflight-SourceState -SourceRoot $resolvedSourceRoot
    $importedLanguageCode = Resolve-ImportedLanguageCode -SourceRoot $resolvedSourceRoot
    Assert-MigrationTargetImportState -Root $resolvedTargetRoot -ImportedLanguageCode $importedLanguageCode

    Assert-ImportableItemImageReferences -SourceHotbarPath $sourceHotbarPath -SourceInventoryPath $sourceInventoryPath -SourceImageDirectory $sourceItemImageDirectory -TargetImageDirectory $targetItemImageDirectory

    Backup-TargetStateToTemporaryRollback -TargetRoot $resolvedTargetRoot
    $script:ImportTargetMutationStarted = $true
    Replace-DirectorySnapshot -SourceDirectory $sourceItemImageDirectory -TargetDirectory $targetItemImageDirectory
    $hotbarBackfill = New-HotbarSlot10ReservedBackfill -LanguageCode $importedLanguageCode -TargetRoot $resolvedTargetRoot
    Merge-VariablesFile -SourcePath $sourceHotbarPath -TargetPath $targetHotbarPath -SameKeysOnly -ExcludeKeyPatterns @('^HotbarItem_Slot10_') -Backfill $hotbarBackfill -ImageRenameMap $imageRenameMap
    Normalize-HotbarSlot10ReservedLabel -TargetHotbarPath $targetHotbarPath -LanguageCode $importedLanguageCode -TargetRoot $resolvedTargetRoot
    Merge-VariablesFile -SourcePath $sourceInventoryPath -TargetPath $targetInventoryPath -SameKeysOnly -ImageRenameMap $imageRenameMap
    Merge-ImageAdjustmentsFile -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'ImageAdjustments.inc') -TargetPath (Join-RootPath -Root $targetData -RelativePath 'ImageAdjustments.inc') -ImageRenameMap $imageRenameMap
    Merge-ItemImagesCatalog -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'ItemImages.inc') -TargetPath (Join-RootPath -Root $targetData -RelativePath 'ItemImages.inc') -ImageRenameMap $imageRenameMap
    Rebuild-ImageAdjustmentsCatalog -TargetPath (Join-RootPath -Root $targetData -RelativePath 'ImageAdjustments.inc') -ImageDirectory $targetItemImageDirectory
    Move-LegacyHotbarSlot10IfCustom -SourceHotbarPath $sourceHotbarPath -TargetInventoryPath $targetInventoryPath -ImageRenameMap $imageRenameMap
    Commit-EditorDraftIfActive -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'EditorDraft.inc') -TargetHotbarPath $targetHotbarPath -TargetInventoryPath $targetInventoryPath -ImageRenameMap $imageRenameMap | Out-Null
    Rebuild-EditorDraftFromImportedItems -TargetRoot $resolvedTargetRoot
    Merge-ResponsiveLayoutState -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'ResponsiveLayoutState.inc') -TargetPath (Join-RootPath -Root $targetData -RelativePath 'ResponsiveLayoutState.inc') -SourceRoot $resolvedSourceRoot
    Merge-HerobrineStatsFile -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'HerobrineStats.inc') -TargetPath (Join-RootPath -Root $targetData -RelativePath 'HerobrineStats.inc')
    Merge-HerobrineStateFile -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'HerobrineState.inc') -TargetPath (Join-RootPath -Root $targetData -RelativePath 'HerobrineState.inc')
    Merge-LineFile -SourcePath (Join-RootPath -Root $sourceData -RelativePath 'EditorFavoritesCatalog.txt') -TargetPath (Join-RootPath -Root $targetData -RelativePath 'EditorFavoritesCatalog.txt')

    Copy-PlayerSkinCacheFiles -SourceDirectory (Join-RootPath -Root $resolvedSourceRoot -RelativePath '@Resources\Customs\Images\Player') -TargetDirectory (Join-RootPath -Root $resolvedTargetRoot -RelativePath '@Resources\Customs\Images\Player')

    Merge-SettingsFiles -SourceRoot $resolvedSourceRoot -TargetRoot $resolvedTargetRoot
    Apply-LowSpecSettingsCompatibility -SourceRoot $resolvedSourceRoot -TargetRoot $resolvedTargetRoot
    Normalize-ImportedMinecraftSkinState -TargetRoot $resolvedTargetRoot
    Sync-ActiveLocalizationCatalog -TargetRoot $resolvedTargetRoot -LanguageCode $importedLanguageCode
    Set-LegacyUpdaterZPosBootstrapPending -TargetRoot $resolvedTargetRoot -SourceVersion $sourceVersion
    Validate-TouchedRainmeterFiles
    if (-not [string]::IsNullOrWhiteSpace($script:EphemeralRollbackRoot)) {
        Remove-TemporaryRollbackRootBestEffort -RollbackRoot $script:EphemeralRollbackRoot -Reason 'successful legacy import'
        $script:EphemeralRollbackRoot = ''
    }

    Install-RootConfigNameCompatModule -SourceRoot $resolvedSourceRoot
    Write-Log 'Legacy import completed.'
}
