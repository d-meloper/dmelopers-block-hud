# Same-version data reset helpers.
# Dot-sourced by UpdateToLatestVersion.ps1. The installed skin root and its
# program files are never replaced by this workflow.

function Get-CurrentVersionResetPayloadSpecs {
    @(
        [PSCustomObject]@{ RelativePath = '@Resources\Customs'; PathType = 'Container' }
        [PSCustomObject]@{ RelativePath = 'HUD\Settings\Cache.inc'; PathType = 'Leaf' }
        [PSCustomObject]@{ RelativePath = 'HUD\Settings\State.inc'; PathType = 'Leaf' }
    )
}

function Get-CurrentVersionResetClearOnlyPaths {
    param([Parameter(Mandatory = $true)][string]$CurrentRoot)

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in @(
        'Logs',
        'MigrationBackup',
        'VersionManagerExports',
        '@Resources\CustomsDataMinecraftSkinHistory.txt',
        'HUD\Settings\Cache.inc.bak'
    )) {
        $paths.Add($relativePath)
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath $CurrentRoot -Directory -Force -ErrorAction Stop)) {
        if ($directory.Name.StartsWith('MigrationBackup_', [System.StringComparison]::OrdinalIgnoreCase)) {
            $paths.Add([string]$directory.Name)
        }
    }
    return @($paths)
}

function Get-CurrentVersionResetRequiredDefaults {
    @(
        '@Resources\Customs\Audios',
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Data\EditorDraft.inc',
        '@Resources\Customs\Data\HerobrineState.inc',
        '@Resources\Customs\Data\HerobrineStats.inc',
        '@Resources\Customs\Data\HotbarItems.inc',
        '@Resources\Customs\Data\ImageAdjustments.inc',
        '@Resources\Customs\Data\InventoryItems.inc',
        '@Resources\Customs\Data\ItemImages.inc',
        '@Resources\Customs\Data\JukeboxPlaybackState.inc',
        '@Resources\Customs\Data\LegacyUpdaterBootstrapState.inc',
        '@Resources\Customs\Data\ResponsiveLayoutDefaults.inc',
        '@Resources\Customs\Data\ResponsiveLayoutState.inc',
        '@Resources\Customs\Localization\Active.inc',
        '@Resources\Customs\Localization\HelperCache.json',
        '@Resources\Customs\Settings\Clock.inc',
        '@Resources\Customs\Settings\Entry.inc',
        '@Resources\Customs\Settings\Entry.Stable.inc',
        '@Resources\Customs\Settings\General.inc',
        '@Resources\Customs\Settings\Hotbar.inc',
        '@Resources\Customs\Settings\Indicators.inc',
        '@Resources\Customs\Settings\Inventory.inc',
        '@Resources\Customs\Settings\Support.inc',
        'HUD\Settings\Cache.inc',
        'HUD\Settings\State.inc'
    )
}

function Assert-CurrentVersionResetPayload {
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    foreach ($spec in @(Get-CurrentVersionResetPayloadSpecs)) {
        $path = Join-RootPath -Root $PackageRoot -RelativePath ([string]$spec.RelativePath)
        if (-not (Test-Path -LiteralPath $path -PathType ([string]$spec.PathType))) {
            throw ("Same-version reset package is missing required default data: {0}" -f [string]$spec.RelativePath)
        }
    }
    foreach ($relativePath in @(Get-CurrentVersionResetRequiredDefaults)) {
        $path = Join-RootPath -Root $PackageRoot -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw ("Same-version reset package is missing required concrete default data: {0}" -f $relativePath)
        }
    }
}

function Get-CurrentVersionResetFileSystemInfoPropertyText {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Item.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }

    $values = @($property.Value | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($values.Count -eq 0) {
        return ''
    }

    return (($values | ForEach-Object { [string]$_ }) -join '; ').Trim()
}

function Test-CurrentVersionResetCloudPlaceholderFileAttributes {
    param([Parameter(Mandatory = $true)][System.IO.FileAttributes]$Attributes)

    return (Test-BlockHudCloudRecallAttributes -Attributes $Attributes)
}

function Test-CurrentVersionResetCloudPlaceholderReparsePoint {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item,
        [AllowNull()][Nullable[uint32]]$ReparseTag
    )

    $resolvedTag = if ($PSBoundParameters.ContainsKey('ReparseTag')) {
        $ReparseTag
    }
    else {
        Get-BlockHudReparseTagValue -Item $Item
    }
    return (Test-BlockHudCloudPlaceholderMetadata -Attributes $Item.Attributes -ReparseTag $resolvedTag)
}

function Get-CurrentVersionResetReparseTargetText {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)

    $property = $Item.PSObject.Properties['Target']
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }

    foreach ($candidate in @($property.Value)) {
        if ($null -ne $candidate -and -not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            return [string]$candidate
        }
    }
    return ''
}

function Resolve-CurrentVersionResetReparseAwareExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = Resolve-FullPath -Path $Path
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    for ($pass = 0; $pass -lt 32; $pass++) {
        if (-not $visited.Add($candidate)) {
            throw "Reparse-point resolution loop detected at '$candidate'."
        }

        $leaf = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        $chain = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]
        $cursor = $leaf
        while ($null -ne $cursor) {
            $chain.Insert(0, $cursor)
            $parentPath = [System.IO.Path]::GetDirectoryName($cursor.FullName.TrimEnd('\', '/'))
            if ([string]::IsNullOrWhiteSpace($parentPath) -or
                [string]::Equals($parentPath, $cursor.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
                break
            }
            try {
                $cursor = Get-Item -LiteralPath $parentPath -Force -ErrorAction Stop
            }
            catch {
                break
            }
        }

        $redirected = $false
        foreach ($item in $chain) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                continue
            }

            $target = Get-CurrentVersionResetReparseTargetText -Item $item
            if ([string]::IsNullOrWhiteSpace($target)) {
                $linkType = Get-CurrentVersionResetFileSystemInfoPropertyText -Item $item -Name 'LinkType'
                if (-not [string]::IsNullOrWhiteSpace($linkType)) {
                    throw "Reparse target is unavailable for '$($item.FullName)' (LinkType=$linkType)."
                }
                if (Test-CurrentVersionResetCloudPlaceholderReparsePoint -Item $item) {
                    continue
                }
                throw "Unsupported targetless reparse point cannot be resolved safely: '$($item.FullName)'."
            }

            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $target = Join-Path ([System.IO.Path]::GetDirectoryName($item.FullName)) $target
            }
            $target = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
            if (-not (Test-Path -LiteralPath $target)) {
                throw "Reparse target does not exist: '$target'."
            }

            $remaining = $candidate.Substring($item.FullName.TrimEnd('\', '/').Length).TrimStart('\', '/')
            $candidate = if ([string]::IsNullOrWhiteSpace($remaining)) {
                $target
            }
            else {
                Join-Path $target $remaining
            }
            $candidate = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
            $redirected = $true
            break
        }

        if (-not $redirected) {
            return $candidate.ToLowerInvariant()
        }
    }

    throw "Reparse-point resolution exceeded the supported depth for '$Path'."
}

function Test-CurrentVersionResetNonRedirectingReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)]
        [ref]$Reason
    )

    $linkType = Get-CurrentVersionResetFileSystemInfoPropertyText -Item $Item -Name 'LinkType'
    if (-not [string]::IsNullOrWhiteSpace($linkType)) {
        $Reason.Value = "LinkType=$linkType"
        return $false
    }

    $target = Get-CurrentVersionResetFileSystemInfoPropertyText -Item $Item -Name 'Target'
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        $Reason.Value = "Target=$target"
        return $false
    }

    if (-not (Test-CurrentVersionResetCloudPlaceholderReparsePoint -Item $Item)) {
        $Reason.Value = 'unsupported targetless reparse tag'
        return $false
    }

    $itemIdentity = (Resolve-FullPath -Path $Item.FullName).TrimEnd('\', '/').ToLowerInvariant()
    try {
        $finalPath = Resolve-CurrentVersionResetReparseAwareExistingPath -Path $Item.FullName
    }
    catch {
        $Reason.Value = "final path could not be resolved: $($_.Exception.Message)"
        return $false
    }
    if ($finalPath -ne $itemIdentity) {
        $Reason.Value = "final path resolves outside itself: $finalPath"
        return $false
    }

    $Reason.Value = 'non-redirecting cloud/sync placeholder'
    return $true
}

function Assert-CurrentVersionResetTreeItemSafe {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        return
    }

    $reason = ''
    if (Test-CurrentVersionResetNonRedirectingReparsePoint -Item $Item -Reason ([ref]$reason)) {
        Write-Log ("Allowed {0} reparse point as {1}: {2}" -f $Context, $reason, $Item.FullName)
        return
    }

    throw ("{0} contains an unsupported reparse point ({1}): {2}" -f $Context, $reason, $Item.FullName)
}

function Get-CurrentVersionResetTreeManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $resolvedPath = Resolve-FullPath -Path $Path
    $rootItem = Get-Item -LiteralPath $resolvedPath -Force -ErrorAction Stop
    Assert-CurrentVersionResetTreeItemSafe -Item $rootItem -Context "$Context root"
    if (-not $rootItem.PSIsContainer) {
        return [PSCustomObject]@{
            PathType = 'Leaf'
            Directories = @()
            Files = @('')
        }
    }

    $directories = New-Object System.Collections.Generic.List[string]
    $files = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($resolvedPath)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            Assert-CurrentVersionResetTreeItemSafe -Item $child -Context $Context
            $relativePath = $child.FullName.Substring($resolvedPath.Length).TrimStart('\', '/')
            if ($child.PSIsContainer) {
                $directories.Add($relativePath)
                $pending.Push([string]$child.FullName)
            }
            else {
                $files.Add($relativePath)
            }
        }
    }
    return [PSCustomObject]@{
        PathType = 'Container'
        Directories = @($directories | Sort-Object)
        Files = @($files | Sort-Object)
    }
}

function Get-CurrentVersionResetFileMap {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = Resolve-FullPath -Path $Root
    $manifest = Get-CurrentVersionResetTreeManifest -Path $resolvedRoot -Context 'Reset data verification'
    $map = @{}
    foreach ($relativePath in @($manifest.Files)) {
        $filePath = if ([string]::IsNullOrWhiteSpace([string]$relativePath)) {
            $resolvedRoot
        }
        else {
            Join-RootPath -Root $resolvedRoot -RelativePath ([string]$relativePath)
        }
        $map[[string]$relativePath] = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    }
    return $map
}

function Copy-CurrentVersionResetPath {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$AllowedDestinationRoot,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $resolvedSource = Resolve-FullPath -Path $SourcePath
    $resolvedDestination = Resolve-FullPath -Path $DestinationPath -AllowMissing
    $resolvedAllowedRoot = Resolve-FullPath -Path $AllowedDestinationRoot
    if (-not (Test-PathWithinRoot -Root $resolvedAllowedRoot -Path $resolvedDestination) -or
        [string]::Equals($resolvedAllowedRoot, $resolvedDestination, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("{0} refused a destination outside its allowed root: {1}" -f $Context, $resolvedDestination)
    }

    $manifest = Get-CurrentVersionResetTreeManifest -Path $resolvedSource -Context $Context
    if ([string]$manifest.PathType -eq 'Leaf') {
        Ensure-Directory -Path (Split-Path -Parent $resolvedDestination)
        [System.IO.File]::Copy($resolvedSource, $resolvedDestination, $true)
        return
    }

    Ensure-Directory -Path $resolvedDestination
    foreach ($relativePath in @($manifest.Directories)) {
        Ensure-Directory -Path (Join-RootPath -Root $resolvedDestination -RelativePath ([string]$relativePath))
    }
    foreach ($relativePath in @($manifest.Files)) {
        $sourceFile = Join-RootPath -Root $resolvedSource -RelativePath ([string]$relativePath)
        $destinationFile = Join-RootPath -Root $resolvedDestination -RelativePath ([string]$relativePath)
        Ensure-Directory -Path (Split-Path -Parent $destinationFile)
        [System.IO.File]::Copy($sourceFile, $destinationFile, $true)
    }
}

function Clear-CurrentVersionResetPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $resolvedPath = Resolve-FullPath -Path $Path
    $resolvedAllowedRoot = Resolve-FullPath -Path $AllowedRoot
    if (-not (Test-PathWithinRoot -Root $resolvedAllowedRoot -Path $resolvedPath) -or
        [string]::Equals($resolvedAllowedRoot, $resolvedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("{0} refused to clear a path outside its allowed root: {1}" -f $Context, $resolvedPath)
    }

    $manifest = Get-CurrentVersionResetTreeManifest -Path $resolvedPath -Context $Context
    if ([string]$manifest.PathType -eq 'Leaf') {
        [System.IO.File]::SetAttributes($resolvedPath, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($resolvedPath)
        return
    }

    foreach ($relativePath in @($manifest.Files)) {
        $filePath = Join-RootPath -Root $resolvedPath -RelativePath ([string]$relativePath)
        [System.IO.File]::SetAttributes($filePath, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($filePath)
    }
    foreach ($relativePath in @($manifest.Directories | Sort-Object -Property Length -Descending)) {
        $directoryPath = Join-RootPath -Root $resolvedPath -RelativePath ([string]$relativePath)
        [System.IO.Directory]::Delete($directoryPath, $false)
    }
    [System.IO.Directory]::Delete($resolvedPath, $false)
}

function Assert-CurrentVersionResetPathEquivalent {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedPath,
        [Parameter(Mandatory = $true)][string]$ActualPath,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if (Test-Path -LiteralPath $ExpectedPath -PathType Leaf) {
        if (-not (Test-Path -LiteralPath $ActualPath -PathType Leaf)) {
            throw "$Context is missing its applied file."
        }
        $expectedHash = (Get-FileHash -LiteralPath $ExpectedPath -Algorithm SHA256).Hash
        $actualHash = (Get-FileHash -LiteralPath $ActualPath -Algorithm SHA256).Hash
        if (-not [string]::Equals($expectedHash, $actualHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "$Context did not preserve the package file bytes."
        }
        return
    }

    if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Container) -or
        -not (Test-Path -LiteralPath $ActualPath -PathType Container)) {
        throw "$Context is missing its expected directory."
    }
    $expectedManifest = Get-CurrentVersionResetTreeManifest -Path $ExpectedPath -Context "$Context expected data"
    $actualManifest = Get-CurrentVersionResetTreeManifest -Path $ActualPath -Context "$Context actual data"
    $expectedDirectories = @($expectedManifest.Directories)
    $actualDirectories = @($actualManifest.Directories)
    if ($expectedDirectories.Count -ne $actualDirectories.Count) {
        throw ("{0} directory count differs from the package. expected={1} actual={2}" -f $Context, $expectedDirectories.Count, $actualDirectories.Count)
    }
    for ($index = 0; $index -lt $expectedDirectories.Count; $index++) {
        if (-not [string]::Equals([string]$expectedDirectories[$index], [string]$actualDirectories[$index], [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("{0} directory layout differs from the package at {1}" -f $Context, [string]$expectedDirectories[$index])
        }
    }

    $expectedMap = Get-CurrentVersionResetFileMap -Root $ExpectedPath
    $actualMap = Get-CurrentVersionResetFileMap -Root $ActualPath
    if ($expectedMap.Count -ne $actualMap.Count) {
        throw ("{0} file count differs from the package. expected={1} actual={2}" -f $Context, $expectedMap.Count, $actualMap.Count)
    }
    foreach ($relativePath in @($expectedMap.Keys)) {
        if (-not $actualMap.ContainsKey($relativePath) -or
            -not [string]::Equals([string]$expectedMap[$relativePath], [string]$actualMap[$relativePath], [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("{0} differs from the package at {1}" -f $Context, $relativePath)
        }
    }
}

function Get-CurrentVersionResetActiveConfigRecords {
    param([Parameter(Mandatory = $true)][string]$Root)

    $configPath = Get-RainmeterConfigPath
    if ([string]::IsNullOrWhiteSpace($configPath) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw 'Rainmeter.ini is unavailable; current-version data reset cannot preserve active configs.'
    }

    $rootConfigName = Get-RootConfigName -Root $Root
    $prefix = $rootConfigName + '\'
    $records = New-Object System.Collections.Generic.List[object]
    $currentSection = ''
    $sectionOrder = -1
    foreach ($rawLine in ((Read-TextSmart -Path $configPath) -split "`r?`n")) {
        $trimmed = ([string]$rawLine).Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = [string]$matches[1]
            $sectionOrder++
            continue
        }
        if ($currentSection -eq '' -or $trimmed.StartsWith(';') -or
            $trimmed -notmatch '^Active\s*=\s*([1-9][0-9]*)\s*$') {
            continue
        }
        if (-not ([string]::Equals($currentSection, $rootConfigName, [System.StringComparison]::OrdinalIgnoreCase) -or
            $currentSection.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }

        $activeIndex = [int]$matches[1]
        $relativeConfigPath = if ([string]::Equals($currentSection, $rootConfigName, [System.StringComparison]::OrdinalIgnoreCase)) {
            ''
        }
        else {
            $currentSection.Substring($prefix.Length)
        }
        $configFolder = if ([string]::IsNullOrWhiteSpace($relativeConfigPath)) {
            $Root
        }
        else {
            Join-RootPath -Root $Root -RelativePath $relativeConfigPath
        }
        $iniFiles = @(Get-ChildItem -LiteralPath $configFolder -File -Filter '*.ini' -Force -ErrorAction Stop | Sort-Object -Property Name)
        if ($activeIndex -gt $iniFiles.Count) {
            throw ("Rainmeter active index cannot be resolved to an INI file. config={0} active={1}" -f $currentSection, $activeIndex)
        }
        $records.Add([PSCustomObject]@{
            ConfigName = $currentSection
            ActiveIndex = $activeIndex
            FileName = [string]$iniFiles[$activeIndex - 1].Name
            SectionOrder = $sectionOrder
        })
    }
    return @($records | Sort-Object -Property SectionOrder)
}

function Get-CurrentVersionResetActiveConfigSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $records = @(Get-CurrentVersionResetActiveConfigRecords -Root $Root)
    Write-Log ("Captured {0} active configs before current-version data reset." -f $records.Count)
    return $records
}

function Invoke-QuiesceCurrentVersionResetConfigs {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Snapshot,
        [ValidateRange(5, 60)][int]$TimeoutSeconds = 20
    )

    foreach ($record in @($Snapshot)) {
        Write-Log ("Quiescing reset config [{0}] ({1})" -f [string]$record.ConfigName, [string]$record.FileName)
        Invoke-RainmeterBang -Bang '!DeactivateConfig' -Arguments @([string]$record.ConfigName)
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $remaining = @(Get-CurrentVersionResetActiveConfigRecords -Root $Root)
        if ($remaining.Count -eq 0) {
            Write-Log 'Current-version data reset quiescence barrier completed.'
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    throw ("Current-version data reset stopped before mutation because configs remained active: {0}" -f ((@($remaining | ForEach-Object { $_.ConfigName })) -join ', '))
}

function Test-CurrentVersionResetActiveConfigSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Snapshot
    )

    $actual = @(Get-CurrentVersionResetActiveConfigRecords -Root $Root)
    if ($actual.Count -ne $Snapshot.Count) {
        return $false
    }
    for ($index = 0; $index -lt $Snapshot.Count; $index++) {
        if (-not [string]::Equals([string]$actual[$index].ConfigName, [string]$Snapshot[$index].ConfigName, [System.StringComparison]::OrdinalIgnoreCase) -or
            [int]$actual[$index].ActiveIndex -ne [int]$Snapshot[$index].ActiveIndex -or
            -not [string]::Equals([string]$actual[$index].FileName, [string]$Snapshot[$index].FileName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Restore-CurrentVersionResetActiveConfigs {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Snapshot,
        [ValidateRange(5, 60)][int]$TimeoutSeconds = 20
    )

    foreach ($record in @($Snapshot)) {
        Write-Log ("Restoring reset config [{0}] ({1})" -f [string]$record.ConfigName, [string]$record.FileName)
        Invoke-RainmeterBang -Bang '!ActivateConfig' -Arguments @([string]$record.ConfigName, [string]$record.FileName)
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-CurrentVersionResetActiveConfigSnapshot -Root $Root -Snapshot $Snapshot) {
            Write-Log 'Restored the exact pre-reset active config and INI set.'
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    throw 'Current-version reset data was applied, but the exact pre-reset active config and INI set was not restored.'
}

function Invoke-CurrentVersionResetFaultIfRequested {
    param([Parameter(Mandatory = $true)][string]$Stage)

    if ([string]::Equals([string]$env:DMEL_TEST_CURRENT_VERSION_RESET_FAIL_STAGE, $Stage, [System.StringComparison]::Ordinal)) {
        throw ("Injected current-version data reset failure at stage: {0}" -f $Stage)
    }
}

function Invoke-CurrentVersionDataReset {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot
    )

    $resolvedCurrentRoot = Resolve-FullPath -Path $CurrentRoot
    $resolvedPackageRoot = Resolve-FullPath -Path $PackageRoot
    $resolvedSkinsRoot = Resolve-FullPath -Path $SkinsRoot
    if (-not (Test-PathWithinRoot -Root $resolvedSkinsRoot -Path $resolvedCurrentRoot) -or
        [string]::Equals($resolvedSkinsRoot, $resolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Current-version data reset requires an exact installed root under Rainmeter SkinPath.'
    }

    Assert-CurrentVersionResetPayload -PackageRoot $resolvedPackageRoot
    $token = [guid]::NewGuid().ToString('N')
    $transactionRoot = Join-RootPath -Root $resolvedCurrentRoot -RelativePath ("@Resources\ResetTransactions\{0}" -f $token)
    $stageRoot = Join-Path $transactionRoot 'Stage'
    $backupRoot = Join-Path $transactionRoot 'Backup'
    $operations = New-Object System.Collections.Generic.List[object]
    $snapshot = @()
    $quiesced = $false
    $mutationStarted = $false

    try {
        Ensure-Directory -Path $stageRoot
        Ensure-Directory -Path $backupRoot
        foreach ($spec in @(Get-CurrentVersionResetPayloadSpecs)) {
            $source = Join-RootPath -Root $resolvedPackageRoot -RelativePath ([string]$spec.RelativePath)
            $staged = Join-RootPath -Root $stageRoot -RelativePath ([string]$spec.RelativePath)
            Copy-CurrentVersionResetPath `
                -SourcePath $source `
                -DestinationPath $staged `
                -AllowedDestinationRoot $transactionRoot `
                -Context ("Staging reset payload {0}" -f [string]$spec.RelativePath)
            Assert-CurrentVersionResetPathEquivalent -ExpectedPath $source -ActualPath $staged -Context ("Staged reset payload {0}" -f [string]$spec.RelativePath)
        }

        $snapshot = @(Get-CurrentVersionResetActiveConfigSnapshot -Root $resolvedCurrentRoot)
        $quiesced = $true
        Invoke-QuiesceCurrentVersionResetConfigs -Root $resolvedCurrentRoot -Snapshot $snapshot

        $managedPaths = @((Get-CurrentVersionResetPayloadSpecs | ForEach-Object { [string]$_.RelativePath })) +
            @(Get-CurrentVersionResetClearOnlyPaths -CurrentRoot $resolvedCurrentRoot)
        foreach ($relativePath in $managedPaths) {
            $target = Join-RootPath -Root $resolvedCurrentRoot -RelativePath $relativePath
            if (-not (Test-PathWithinRoot -Root $resolvedCurrentRoot -Path (Resolve-FullPath -Path $target -AllowMissing))) {
                throw ("Refusing to reset a data path outside CurrentTargetRoot: {0}" -f $relativePath)
            }
            $backup = Join-RootPath -Root $backupRoot -RelativePath $relativePath
            $operation = [PSCustomObject]@{
                RelativePath = $relativePath
                Target = $target
                Backup = $backup
                TargetExisted = (Test-Path -LiteralPath $target)
                BackupReady = $false
            }
            $operations.Add($operation)
            if ([bool]$operation.TargetExisted) {
                Copy-CurrentVersionResetPath `
                    -SourcePath $target `
                    -DestinationPath $backup `
                    -AllowedDestinationRoot $transactionRoot `
                    -Context ("Backing up reset data {0}" -f $relativePath)
                Assert-CurrentVersionResetPathEquivalent -ExpectedPath $target -ActualPath $backup -Context ("Backed up reset data {0}" -f $relativePath)
                $operation.BackupReady = $true
            }
        }

        $mutationStarted = $true
        foreach ($operation in $operations) {
            Clear-CurrentVersionResetPath `
                -Path ([string]$operation.Target) `
                -AllowedRoot $resolvedCurrentRoot `
                -Context ("Clearing reset data {0}" -f [string]$operation.RelativePath)
        }

        foreach ($spec in @(Get-CurrentVersionResetPayloadSpecs)) {
            $relativePath = [string]$spec.RelativePath
            $staged = Join-RootPath -Root $stageRoot -RelativePath $relativePath
            $target = Join-RootPath -Root $resolvedCurrentRoot -RelativePath $relativePath
            Copy-CurrentVersionResetPath `
                -SourcePath $staged `
                -DestinationPath $target `
                -AllowedDestinationRoot $resolvedCurrentRoot `
                -Context ("Applying reset payload {0}" -f $relativePath)
            Assert-CurrentVersionResetPathEquivalent `
                -ExpectedPath (Join-RootPath -Root $resolvedPackageRoot -RelativePath $relativePath) `
                -ActualPath $target `
                -Context ("Applied reset payload {0}" -f $relativePath)
            if ([string]::Equals($relativePath, '@Resources\Customs', [System.StringComparison]::OrdinalIgnoreCase)) {
                Invoke-CurrentVersionResetFaultIfRequested -Stage 'AfterCustomsApply'
            }
        }
        Invoke-CurrentVersionResetFaultIfRequested -Stage 'AfterSettingsApply'
        Invoke-CurrentVersionResetFaultIfRequested -Stage 'BeforeActivation'

        Restore-CurrentVersionResetActiveConfigs -Root $resolvedCurrentRoot -Snapshot $snapshot
        $quiesced = $false
        Invoke-CurrentVersionResetFaultIfRequested -Stage 'BeforeCleanup'

        Clear-CurrentVersionResetPath -Path $transactionRoot -AllowedRoot $resolvedCurrentRoot -Context 'Cleaning the completed reset transaction'
        $transactionParent = Split-Path -Parent $transactionRoot
        if ((Test-Path -LiteralPath $transactionParent -PathType Container) -and
            @(Get-ChildItem -LiteralPath $transactionParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            [System.IO.Directory]::Delete($transactionParent, $false)
        }
        Write-Log 'Applied the same-version package default data without replacing the installed root or program files.'
        return [PSCustomObject]@{
            Status = 'OK'
            Message = 'Applied the same-version package default data at the current skin root and restored the previous active configs.'
        }
    }
    catch {
        $failure = $_.Exception.Message
        $rollbackErrors = New-Object System.Collections.Generic.List[string]
        if ($quiesced -or $mutationStarted) {
            try {
                foreach ($record in @(Get-CurrentVersionResetActiveConfigRecords -Root $resolvedCurrentRoot)) {
                    Invoke-RainmeterBang -Bang '!DeactivateConfig' -Arguments @([string]$record.ConfigName)
                }
            }
            catch {
                $rollbackErrors.Add(("quiesce={0}" -f $_.Exception.Message))
            }
        }
        if ($mutationStarted) {
            foreach ($operation in @($operations | Sort-Object -Property RelativePath -Descending)) {
                try {
                    Clear-CurrentVersionResetPath `
                        -Path ([string]$operation.Target) `
                        -AllowedRoot $resolvedCurrentRoot `
                        -Context ("Rolling back reset data {0}" -f [string]$operation.RelativePath)
                    if ([bool]$operation.TargetExisted -and [bool]$operation.BackupReady) {
                        Copy-CurrentVersionResetPath `
                            -SourcePath ([string]$operation.Backup) `
                            -DestinationPath ([string]$operation.Target) `
                            -AllowedDestinationRoot $resolvedCurrentRoot `
                            -Context ("Restoring reset data {0}" -f [string]$operation.RelativePath)
                        Assert-CurrentVersionResetPathEquivalent `
                            -ExpectedPath ([string]$operation.Backup) `
                            -ActualPath ([string]$operation.Target) `
                            -Context ("Restored reset data {0}" -f [string]$operation.RelativePath)
                    }
                }
                catch {
                    $rollbackErrors.Add(("data:{0}={1}" -f [string]$operation.RelativePath, $_.Exception.Message))
                }
            }
        }
        if ($quiesced -or $mutationStarted) {
            try {
                Restore-CurrentVersionResetActiveConfigs -Root $resolvedCurrentRoot -Snapshot $snapshot
            }
            catch {
                $rollbackErrors.Add(("activation={0}" -f $_.Exception.Message))
            }
        }
        if ($rollbackErrors.Count -eq 0) {
            try {
                if (Test-Path -LiteralPath $transactionRoot) {
                    Clear-CurrentVersionResetPath -Path $transactionRoot -AllowedRoot $resolvedCurrentRoot -Context 'Cleaning the rolled-back reset transaction'
                }
                $transactionParent = Split-Path -Parent $transactionRoot
                if ((Test-Path -LiteralPath $transactionParent -PathType Container) -and
                    @(Get-ChildItem -LiteralPath $transactionParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                    [System.IO.Directory]::Delete($transactionParent, $false)
                }
            }
            catch {
                $rollbackErrors.Add(("transaction_cleanup={0}" -f $_.Exception.Message))
            }
        }
        if ($rollbackErrors.Count -gt 0) {
            throw ("Current-version data reset failed and rollback was incomplete; preserved transaction data at {0}. error={1}; rollback={2}" -f $transactionRoot, $failure, ($rollbackErrors -join '; '))
        }
        throw ("Current-version data reset failed; restored the previous data and active configs. {0}" -f $failure)
    }
}
