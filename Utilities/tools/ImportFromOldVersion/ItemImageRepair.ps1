# ImportFromOldVersion helpers - deterministic item-image compatibility plans.

function Get-ItemImageRepairEntryId {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Key
    )

    return ('{0}:{1}{2}' -f $Context.Length, $Context, $Key)
}

function Test-AllowedReservedItemImageReference {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Key
    )

    return ($Context -eq 'source HotbarItems.inc' -and
        $Key -eq 'HotbarItem_Slot10_Image' -and
        (Test-ReservedHotbarSlot10Section -Variables $Variables -Prefix 'HotbarItem_Slot10'))
}

function Test-ItemImageRepairKeyForContext {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($Context -eq 'source HotbarItems.inc') {
        return ($Key -match '^HotbarItem_Slot(0?[1-9]|10)_Image$')
    }
    if ($Context -eq 'source InventoryItems.inc') {
        return ($Key -match '^InventoryItem_SlotX[1-9]Y[1-4]_Image$')
    }
    if ($Context -eq 'active source EditorDraft.inc') {
        return ($Key -match '^EditorDraftItem_(Slot(0?[1-9]|10)|SlotX[1-9]Y[1-4])_Image$')
    }
    return $false
}

function Get-ItemImageRepairEntriesFromPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][hashtable]$SourceAssets,
        [Parameter(Mandatory = $true)][hashtable]$TargetAssets,
        [switch]$ActiveEditorDraftOnly
    )

    $entries = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $entries.ToArray()
    }

    $variables = Read-VariablesFile -Path $Path
    if ($ActiveEditorDraftOnly -and -not (Test-EditorDraftActive -DraftVariables $variables)) {
        return $entries.ToArray()
    }

    foreach ($key in $variables.Keys) {
        if (-not (Test-ItemImageRepairKeyForContext -Context $Context -Key ([string]$key))) {
            continue
        }

        $rawValue = [string]$variables[$key]
        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            continue
        }

        $asset = Normalize-ImageAssetForMigration -Value $rawValue
        if ([string]::IsNullOrWhiteSpace($asset)) {
            $entries.Add([pscustomobject][ordered]@{
                Context = $Context
                Key = [string]$key
                Value = $rawValue
                Asset = ''
                Reason = 'invalid_asset_name'
            })
            continue
        }

        if ($asset.Equals('more.png', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (Test-AllowedReservedItemImageReference -Variables $variables -Context $Context -Key ([string]$key)) {
                continue
            }
            $entries.Add([pscustomobject][ordered]@{
                Context = $Context
                Key = [string]$key
                Value = $rawValue
                Asset = $asset
                Reason = 'reserved_runtime_asset_misuse'
            })
            continue
        }

        if (-not $SourceAssets.ContainsKey($asset) -and -not $TargetAssets.ContainsKey($asset)) {
            $entries.Add([pscustomobject][ordered]@{
                Context = $Context
                Key = [string]$key
                Value = $rawValue
                Asset = $asset
                Reason = 'asset_unavailable'
            })
        }
    }

    return $entries.ToArray()
}

function Get-ItemImageRepairIdentityPart {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'missing'
    }
    return (Get-Sha256HashString -Path $Path)
}

function Get-ItemImageDirectoryIdentityPart {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return 'missing'
    }

    $identityParts = New-Object System.Collections.Generic.List[string]
    $profiles = @(Get-BlockHudValidItemGifAtlasProfiles -ItemImageDirectory $Directory)
    foreach ($asset in @(Get-DirectoryItemImageAssets -Directory $Directory | Sort-Object)) {
        $assetPath = Resolve-BlockHudItemImageBackingPath -ItemImageDirectory $Directory -AssetName $asset -ValidAtlasProfiles $profiles
        if ([string]::IsNullOrWhiteSpace($assetPath)) { continue }
        $identityParts.Add(('{0}:{1}' -f $asset, (Get-Sha256HashString -Path $assetPath)))
    }
    return ($identityParts.ToArray() -join '|')
}

function Get-ItemImageRepairPlanId {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Identity)

    $canonical = $Identity | ConvertTo-Json -Depth 8 -Compress
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($canonical)
        return (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

# DMEL_COMPAT:import.item-schema-backfill
function New-ItemImageCompatibilityPlan {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceHotbarPath,
        [Parameter(Mandatory = $true)][string]$SourceInventoryPath,
        [string]$SourceEditorDraftPath = '',
        [Parameter(Mandatory = $true)][string]$SourceImageDirectory,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory
    )

    $sourceAssets = if (Test-Path -LiteralPath $SourceImageDirectory -PathType Container) { Get-DirectoryItemImageAssetMap -Directory $SourceImageDirectory } else { New-CaseInsensitiveHashtable }
    $targetAssets = if (Test-Path -LiteralPath $TargetImageDirectory -PathType Container) { Get-DirectoryItemImageAssetMap -Directory $TargetImageDirectory } else { New-CaseInsensitiveHashtable }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-ItemImageRepairEntriesFromPath -Path $SourceHotbarPath -Context 'source HotbarItems.inc' -SourceAssets $sourceAssets -TargetAssets $targetAssets)) {
        $entries.Add($entry)
    }
    foreach ($entry in @(Get-ItemImageRepairEntriesFromPath -Path $SourceInventoryPath -Context 'source InventoryItems.inc' -SourceAssets $sourceAssets -TargetAssets $targetAssets)) {
        $entries.Add($entry)
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceEditorDraftPath)) {
        foreach ($entry in @(Get-ItemImageRepairEntriesFromPath -Path $SourceEditorDraftPath -Context 'active source EditorDraft.inc' -SourceAssets $sourceAssets -TargetAssets $targetAssets -ActiveEditorDraftOnly)) {
            $entries.Add($entry)
        }
    }

    $orderedEntries = @($entries.ToArray() | Sort-Object Context, Key, Value, Reason)
    $summaryParts = @($orderedEntries | ForEach-Object { '{0}:{1}={2} [{3}]' -f $_.Context, $_.Key, $_.Value, $_.Reason })
    $identityEntries = @($orderedEntries | ForEach-Object {
        [ordered]@{ Context = $_.Context; Key = $_.Key; Value = $_.Value; Asset = $_.Asset; Reason = $_.Reason }
    })
    $identity = [ordered]@{
        SchemaVersion = 1
        SourceVersion = [string](Get-SkinMetadataVersion -Root $SourceRoot)
        TargetVersion = [string](Get-SkinMetadataVersion -Root $TargetRoot)
        PackageIdentity = ([string]$PackageIdentity).Trim().ToLowerInvariant()
        SourceHotbarHash = Get-ItemImageRepairIdentityPart -Path $SourceHotbarPath
        SourceInventoryHash = Get-ItemImageRepairIdentityPart -Path $SourceInventoryPath
        SourceEditorDraftHash = if ([string]::IsNullOrWhiteSpace($SourceEditorDraftPath)) { 'missing' } else { Get-ItemImageRepairIdentityPart -Path $SourceEditorDraftPath }
        TargetHotbarHash = Get-ItemImageRepairIdentityPart -Path (Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\HotbarItems.inc')
        TargetInventoryHash = Get-ItemImageRepairIdentityPart -Path (Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\InventoryItems.inc')
        SourceAssets = Get-ItemImageDirectoryIdentityPart -Directory $SourceImageDirectory
        TargetAssets = Get-ItemImageDirectoryIdentityPart -Directory $TargetImageDirectory
        Repairs = $identityEntries
    }

    return [pscustomobject]@{
        Compatibility = if ($orderedEntries.Count -gt 0) { 'REPAIRABLE' } else { 'OK' }
        Entries = $orderedEntries
        Count = $orderedEntries.Count
        Summary = ($summaryParts -join ' | ')
        PlanId = if ($orderedEntries.Count -gt 0) { Get-ItemImageRepairPlanId -Identity $identity } else { '' }
    }
}

function Set-ItemImageCompatibilityResult {
    param([Parameter(Mandatory = $true)]$Plan)

    Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value ([string]$Plan.Compatibility)
    Set-ResultPairValue -Key 'DMEL_REPAIRCOUNT' -Value ([string]$Plan.Count)
    Set-ResultPairValue -Key 'DMEL_REPAIRSUMMARY' -Value ([string]$Plan.Summary)
    Set-ResultPairValue -Key 'DMEL_REPAIRPLANID' -Value ([string]$Plan.PlanId)
}

function Enable-ApprovedItemImageRepairPlan {
    param([Parameter(Mandatory = $true)]$Plan)

    if ([string]::IsNullOrWhiteSpace($ExpectedRepairPlanId)) {
        throw 'ExpectedRepairPlanId is required when applying item image compatibility repairs.'
    }
    if (-not [string]::Equals([string]$Plan.PlanId, $ExpectedRepairPlanId.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The approved item image repair plan no longer matches the current source and target data. Run compatibility preflight again.'
    }

    $keys = New-CaseInsensitiveHashtable
    foreach ($entry in @($Plan.Entries)) {
        $entryId = Get-ItemImageRepairEntryId -Context ([string]$entry.Context) -Key ([string]$entry.Key)
        if (-not $keys.ContainsKey($entryId)) {
            $keys[$entryId] = $true
        }
    }
    $script:ApprovedItemImageRepairKeys = $keys
    $script:AppliedItemImageRepairKeys = New-CaseInsensitiveHashtable
    Write-Log ("Approved item image repair plan {0} will clear {1} unusable Image field(s)." -f $Plan.PlanId, $Plan.Count) 'WARN'
}

function Assert-ImportedItemImageIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$TargetHotbarPath,
        [Parameter(Mandatory = $true)][string]$TargetInventoryPath,
        [Parameter(Mandatory = $true)][string]$TargetImageDirectory
    )

    $postPlan = New-ItemImageCompatibilityPlan -SourceRoot $TargetRoot -TargetRoot $TargetRoot -SourceHotbarPath $TargetHotbarPath -SourceInventoryPath $TargetInventoryPath -SourceImageDirectory $TargetImageDirectory -TargetImageDirectory $TargetImageDirectory
    if ($postPlan.Count -gt 0) {
        throw ("Imported item image integrity validation failed: {0}" -f $postPlan.Summary)
    }

    if ($script:ItemImageCompatibilityPlan -and $script:ItemImageCompatibilityPlan.Compatibility -eq 'REPAIRABLE') {
        $expectedKeys = New-CaseInsensitiveHashtable
        foreach ($entry in @($script:ItemImageCompatibilityPlan.Entries)) {
            $entryId = Get-ItemImageRepairEntryId -Context ([string]$entry.Context) -Key ([string]$entry.Key)
            $expectedKeys[$entryId] = $true
        }
        $appliedKeys = if ($script:AppliedItemImageRepairKeys) { $script:AppliedItemImageRepairKeys } else { New-CaseInsensitiveHashtable }
        $missingKeys = @($expectedKeys.Keys | Where-Object { -not $appliedKeys.ContainsKey([string]$_) } | Sort-Object)
        $unexpectedKeys = @($appliedKeys.Keys | Where-Object { -not $expectedKeys.ContainsKey([string]$_) } | Sort-Object)
        if ($missingKeys.Count -gt 0 -or $unexpectedKeys.Count -gt 0) {
            throw ("Approved item-image repair application did not match its plan. missing={0}; unexpected={1}" -f ($missingKeys -join ','), ($unexpectedKeys -join ','))
        }
    }

    Write-Log 'Imported item image references and assets passed post-import integrity validation.'
}
