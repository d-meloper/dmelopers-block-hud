# ImportFromOldVersion helpers - Result logging and root discovery

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Fallback = ''
    )

    Get-LocalizedText -Table $script:LocTable -Key $Key -Fallback $Fallback
}

function Expand-UnicodeEscapes {
    param([Parameter(Mandatory = $true)][string]$Value)

    return [regex]::Unescape($Value)
}

function Set-ResultPairValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowNull()]
        [string]$Value
    )

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Add-ResultPairMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $current = [string]$script:ResultPairs['DMEL_MESSAGE']
    if ([string]::IsNullOrWhiteSpace($current)) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $Message
        return
    }

    if ($current.IndexOf($Message, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return
    }

    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ($current.TrimEnd() + ' | ' + $Message)
}

function Convert-ResultPairValueToSingleLine {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $singleLine = [string]$Value
    $singleLine = $singleLine.Replace("`r", ' ').Replace("`n", ' ')
    while ($singleLine.Contains('  ')) {
        $singleLine = $singleLine.Replace('  ', ' ')
    }

    return $singleLine.Trim()
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowNull()]
        [string]$Value
    )

    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($Key + '=' + (Convert-ResultPairValueToSingleLine -Value $Value))
    }
    finally {
        $writer.Dispose()
    }
}

function Emit-ResultPairs {
    if (-not $EmitResultPairs) {
        return
    }

    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    foreach ($key in @(
        'DMEL_STATUS',
        'DMEL_SOURCEPATH',
        'DMEL_BACKUPPATH',
        'DMEL_LOGPATH',
        'DMEL_MESSAGE',
        'DMEL_COMPATIBILITY',
        'DMEL_REPAIRCOUNT',
        'DMEL_REPAIRSUMMARY',
        'DMEL_REPAIRPLANID'
    )) {
        Write-OutputPair -Key $key -Value $script:ResultPairs[$key]
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] {1}' -f $Level, $Message
    $script:LogMessages.Add($line)
    Write-Host $line
}

function Get-ManagedSnapshotScopeRelativePaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @(
        '@Resources\Customs\Settings',
        '@Resources\Customs\Data',
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Images\Player',
        ((Get-BlockHudSettingsRelativePath -Root $Root) + '\State.inc')
    )
}

function Get-TemporaryRollbackScopeRelativePaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @(
        '@Resources\Customs',
        ((Get-BlockHudSettingsRelativePath -Root $Root) + '\State.inc'),
        '@Resources\CustomsDataMinecraftSkinHistory.txt'
    )
}

function Save-Log {
    try {
        $parent = Split-Path -Parent $script:LogPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'ImportFromOldVersion' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
        Write-Host ("Log: {0}" -f $script:LogPath)
    }
    catch {
        $message = "Helper log could not be saved: $($_.Exception.Message)"
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value ''
        Add-ResultPairMessage -Message $message
        try {
            Write-Host ("Log save failed: {0}" -f $_.Exception.Message)
        }
        catch {
        }
    }
}

function Get-CanonicalHelperLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    return (Get-BlockHudCanonicalLogPath -Root $TargetRoot -ScriptRoot $PSScriptRoot)
}

function Use-CanonicalTargetLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $script:LogPath = Get-CanonicalHelperLogPath -TargetRoot $TargetRoot -Prefix $Prefix
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AllowMissing
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([string]::IsNullOrWhiteSpace($expanded)) {
        throw 'Path is empty.'
    }

    if ([System.IO.Path]::IsPathRooted($expanded)) {
        $full = [System.IO.Path]::GetFullPath($expanded)
    }
    else {
        $full = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $expanded))
    }

    $full = $full.TrimEnd('\', '/')
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Path does not exist: $full"
    }

    return $full
}

function Get-ReparseTargetText {
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

function Test-CloudPlaceholderReparsePoint {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)

    # Windows cloud placeholders are non-redirecting reparse points.  The
    # RecallOnOpen / RecallOnDataAccess flags distinguish those placeholders
    # from an unknown redirecting tag whose target PowerShell cannot resolve.
    $recallOnOpen = [System.IO.FileAttributes]0x00040000
    $recallOnDataAccess = [System.IO.FileAttributes]0x00400000
    return (($Item.Attributes -band $recallOnOpen) -ne 0 -or
        ($Item.Attributes -band $recallOnDataAccess) -ne 0)
}

function Resolve-ReparseAwareExistingPath {
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

            $target = Get-ReparseTargetText -Item $item
            if ([string]::IsNullOrWhiteSpace($target)) {
                $linkTypeProperty = $item.PSObject.Properties['LinkType']
                $linkType = if ($null -eq $linkTypeProperty) { '' } else { [string]$linkTypeProperty.Value }
                if (-not [string]::IsNullOrWhiteSpace($linkType)) {
                    throw "Reparse target is unavailable for '$($item.FullName)' (LinkType=$linkType)."
                }
                if (Test-CloudPlaceholderReparsePoint -Item $item) {
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
                [System.IO.Path]::GetFullPath((Join-Path $target $remaining))
            }
            $redirected = $true
            break
        }

        if (-not $redirected) {
            return $candidate.TrimEnd('\', '/').ToLowerInvariant()
        }
    }

    throw "Reparse-point resolution exceeded the supported depth for '$Path'."
}

function Get-FinalExistingPathInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-FullPath -Path $Path
    $item = Get-Item -LiteralPath $resolved

    try {
        return [pscustomobject]@{
            Success = $true
            Path = Resolve-ReparseAwareExistingPath -Path $item.FullName
            Error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Path = ''
            Error = $_.Exception.Message
        }
    }
}

function Get-CanonicalExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-FullPath -Path $Path
    $item = Get-Item -LiteralPath $resolved
    $finalPathInfo = Get-FinalExistingPathInfo -Path $item.FullName
    if ($finalPathInfo.Success) {
        return $finalPathInfo.Path
    }

    Write-Log "Falling back to normalized path identity for '$($item.FullName)': $($finalPathInfo.Error)" 'WARN'
    return $item.FullName.TrimEnd('\', '/').ToLowerInvariant()
}

function Join-RootPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    Join-Path $Root $RelativePath
}

function Normalize-PathIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Resolve-FullPath -Path $Path -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
}

function Open-SharedReadStream {
    param([Parameter(Mandatory = $true)][string]$Path)

    $shareMode = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    return [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $shareMode)
}

function Read-AllBytesShared {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = Open-SharedReadStream -Path $Path
    try {
        $memory = New-Object System.IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return ,($memory.ToArray())
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Add-SkippedSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Directory
    )

    $normalized = Normalize-PathIdentity -Path $Path
    if ($Directory) {
        [void]$script:SkippedSourceDirectories.Add($normalized)
    }
    else {
        [void]$script:SkippedSourceFiles.Add($normalized)
    }
}

function Test-SkippedSourcePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($script:ResolvedSourceRoot)) {
        return $false
    }

    $normalized = Normalize-PathIdentity -Path $Path
    if ($script:SkippedSourceFiles.Contains($normalized) -or $script:SkippedSourceDirectories.Contains($normalized)) {
        return $true
    }

    foreach ($directory in $script:SkippedSourceDirectories) {
        if ($normalized.StartsWith($directory + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-SkinRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Test-BlockHudSkinRoot -Root $Root)
}

function Assert-SkinRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-SkinRoot -Root $Root)) {
        throw "$Name is not a valid DMeloper's Block HUD skin root: $Root"
    }
}

function Test-VariablesFileHasKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $variables = Read-VariablesFile -Path $Path
    return $variables.Contains($Key)
}

function Get-SkinMetadataVersion {
    param([Parameter(Mandatory = $true)][string]$Root)

    $settingsPath = Get-BlockHudSettingsIniPath -Root $Root
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        return ''
    }

    $content = Read-TextSmart -Path $settingsPath
    $inMetadata = $false
    foreach ($line in ($content -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inMetadata = ($matches[1] -ieq 'Metadata')
            continue
        }

        if (-not $inMetadata) {
            continue
        }

        if ($trimmed -match '^Version\s*=\s*(.+?)\s*$') {
            return $matches[1].Trim()
        }
    }

    return ''
}

function ConvertTo-SkinVersion {
    param(
        [AllowNull()]
        [string]$VersionText,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        throw "$Context metadata version is missing."
    }

    try {
        $normalized = $VersionText.Trim()
        if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(1)
        }
        return [version]$normalized
    }
    catch {
        throw "$Context metadata version is invalid: '$VersionText'."
    }
}

function Assert-MigrationTargetRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    Assert-SkinRoot -Root $Root -Name 'TargetRoot'

    $metadataVersion = Get-SkinMetadataVersion -Root $Root
    $targetVersion = ConvertTo-SkinVersion -VersionText $metadataVersion -Context 'TargetRoot'
    if ($targetVersion -lt [version]'1.1.0') {
        throw "TargetRoot metadata version must be v1.1.0 or newer, but was '$metadataVersion'."
    }

    foreach ($relativePath in @(
        '@Resources\Customs\Settings',
        '@Resources\Customs\Data',
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Images\Player',
        ((Get-BlockHudSettingsRelativePath -Root $Root) + '\State.inc'),
        ((Get-BlockHudSettingsRelativePath -Root $Root) + '\Settings.ini')
    )) {
        $path = Join-RootPath -Root $Root -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "TargetRoot is missing required legacy import target input: $relativePath"
        }
    }
}

function Assert-MigrationTargetImportState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ImportedLanguageCode
    )

    foreach ($relativePath in @(
        '@Resources\Customs\Data\HotbarItems.inc',
        '@Resources\Customs\Data\InventoryItems.inc',
        '@Resources\Customs\Data\ItemImages.inc',
        '@Resources\Customs\Data\ResponsiveLayoutState.inc',
        '@Resources\Customs\Data\HerobrineStats.inc',
        '@Resources\Customs\Data\HerobrineState.inc',
        '@Resources\Customs\Settings\General.inc',
        '@Resources\Customs\Settings\Hotbar.inc',
        '@Resources\Customs\Settings\Inventory.inc',
        '@Resources\Customs\Settings\Clock.inc',
        '@Resources\Customs\Settings\Indicators.inc',
        '@Resources\Customs\Settings\Support.inc'
    )) {
        $path = Join-RootPath -Root $Root -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "TargetRoot is missing required legacy import target file: $relativePath"
        }

        Test-ReadableSourceFile -Path $path
    }

    $resolvedLanguageCode = Normalize-LanguageCode -Value $ImportedLanguageCode -Fallback 'en-US' -SkinRoot $Root
    $localeRelativePath = "@Resources\Localization\Languages\{0}.inc" -f $resolvedLanguageCode
    $localePath = Join-RootPath -Root $Root -RelativePath $localeRelativePath
    if (-not (Test-Path -LiteralPath $localePath -PathType Leaf)) {
        throw "TargetRoot is missing canonical localization catalog for imported language '$resolvedLanguageCode'."
    }

    Test-ReadableSourceFile -Path $localePath
}

function Assert-MigrationSourceRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [version]$TargetVersion
    )

    Assert-SkinRoot -Root $Root -Name 'SourceRoot'

    $metadataVersion = Get-SkinMetadataVersion -Root $Root
    $sourceVersion = ConvertTo-SkinVersion -VersionText $metadataVersion -Context 'SourceRoot'
    if ($sourceVersion -lt [version]'1.1.0') {
        throw "SourceRoot metadata version must be v1.1.0 or newer, but was '$metadataVersion'."
    }
    if ($sourceVersion -gt $TargetVersion) {
        throw "SourceRoot metadata version must be less than or equal to the current target version $TargetVersion, but was '$metadataVersion'."
    }

    foreach ($relativePath in @(
        '@Resources\Customs\Settings',
        '@Resources\Customs\Data',
        ((Get-BlockHudSettingsRelativePath -Root $Root) + '\Settings.ini')
    )) {
        $path = Join-RootPath -Root $Root -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "SourceRoot is missing required legacy import input: $relativePath"
        }
    }
}

function Resolve-SourceRootCandidate {
    param([Parameter(Mandatory = $true)][string]$Candidate)

    $resolved = Resolve-FullPath -Path $Candidate -AllowMissing
    if (Test-SkinRoot -Root $resolved) {
        return $resolved
    }

    $child = Join-RootPath -Root $resolved -RelativePath "DMeloper's Block HUD"
    if ((Test-Path -LiteralPath $child -PathType Container) -and (Test-SkinRoot -Root $child)) {
        return (Resolve-FullPath -Path $child)
    }

    return $null
}

function Assert-DifferentRoots {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $sourceIdentity = Get-CanonicalExistingPath -Path $SourceRoot
    $targetIdentity = Get-CanonicalExistingPath -Path $TargetRoot
    if ($sourceIdentity -eq $targetIdentity) {
        throw 'SourceRoot and TargetRoot resolve to the same filesystem root. Migration aborted.'
    }
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootFull = (Resolve-FullPath -Path $Root).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $Path -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Assert-RootContainmentPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    if (Test-PathWithinRoot -Root $SourceRoot -Path $TargetRoot) {
        throw 'TargetRoot cannot be inside SourceRoot because legacy import would mutate the source tree.'
    }

    if (Test-PathWithinRoot -Root $TargetRoot -Path $SourceRoot) {
        throw 'SourceRoot cannot be inside TargetRoot because legacy import must use a separate installed skin root.'
    }
}

function Get-FileSystemInfoPropertyText {
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

function Test-NonRedirectingReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)]
        [ref]$Reason
    )

    $linkType = Get-FileSystemInfoPropertyText -Item $Item -Name 'LinkType'
    if (-not [string]::IsNullOrWhiteSpace($linkType)) {
        $Reason.Value = "LinkType=$linkType"
        return $false
    }

    $target = Get-FileSystemInfoPropertyText -Item $Item -Name 'Target'
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        $Reason.Value = "Target=$target"
        return $false
    }

    if (-not (Test-CloudPlaceholderReparsePoint -Item $Item)) {
        $Reason.Value = 'unsupported targetless reparse tag'
        return $false
    }

    $itemIdentity = Normalize-PathIdentity -Path $Item.FullName
    $finalPathInfo = Get-FinalExistingPathInfo -Path $Item.FullName
    if (-not $finalPathInfo.Success) {
        $Reason.Value = "final path could not be resolved: $($finalPathInfo.Error)"
        return $false
    }

    if ($finalPathInfo.Path -ne $itemIdentity) {
        $Reason.Value = "final path resolves outside itself: $($finalPathInfo.Path)"
        return $false
    }

    $Reason.Value = 'non-redirecting cloud/sync placeholder'
    return $true
}

function Assert-NoUnsafeTargetReparsePoints {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Roots,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
        $items = @($rootItem) + @(Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction Stop)
        $reparseItems = @($items | Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        })
        foreach ($item in $reparseItems) {
            $reason = ''
            if (Test-NonRedirectingReparsePoint -Item $item -Reason ([ref]$reason)) {
                Write-Log "Allowed $Context reparse point as $reason`: $($item.FullName)"
                continue
            }

            throw "Refusing migration because $Context contains an unsafe reparse point ($reason): $($item.FullName)"
        }
    }
}

function Assert-SafeTargetPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($script:ResolvedTargetRoot)) {
        return
    }

    if (-not (Test-PathWithinRoot -Root $script:ResolvedTargetRoot -Path $Path)) {
        throw "Refusing to write outside TargetRoot: $Path"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedSourceRoot) -and (Test-PathWithinRoot -Root $script:ResolvedSourceRoot -Path $Path)) {
        throw "Refusing to write inside SourceRoot: $Path"
    }
}

function Ensure-ImportFromOldVersionInteractiveSourceSelection {
    if ($null -ne (Get-Command -Name 'Select-SourceRootWithDialog' -CommandType Function -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command -Name 'Confirm-DetectedSourceSelection' -CommandType Function -ErrorAction SilentlyContinue)) {
        return
    }

    $interactivePath = Join-Path $script:ModuleRoot 'InteractiveSourceSelection.ps1'
    if (-not (Test-Path -LiteralPath $interactivePath -PathType Leaf)) {
        throw "Interactive source-selection module was not found: $interactivePath"
    }

    . $interactivePath
    foreach ($functionName in @('Select-SourceRootWithDialog', 'Confirm-DetectedSourceSelection')) {
        $loadedFunction = Get-Item -LiteralPath ('Function:\' + $functionName) -ErrorAction Stop
        Set-Item -LiteralPath ('Function:\script:' + $functionName) -Value $loadedFunction.ScriptBlock
    }
}

function Get-RainmeterConfigPath {
    $candidates = @(
        (Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'),
        (Join-Path $env:LOCALAPPDATA 'Rainmeter\Rainmeter.ini')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-FullPath -Path $candidate)
        }
    }

    return ''
}

function Get-RainmeterSkinsRoot {
    $configPath = Get-RainmeterConfigPath
    if (-not [string]::IsNullOrWhiteSpace($configPath)) {
        $content = Read-TextSmart -Path $configPath
        $inRainmeterSection = $false
        foreach ($line in ($content -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[(.+)\]$') {
                $inRainmeterSection = ($matches[1] -ieq 'Rainmeter')
                continue
            }

            if (-not $inRainmeterSection) {
                continue
            }

            if ($trimmed -match '^SkinPath\s*=\s*(.+?)\s*$') {
                $skinPath = $matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($skinPath)) {
                    return (Resolve-FullPath -Path $skinPath -AllowMissing)
                }
            }
        }
    }

    $targetParent = Split-Path -Parent $script:ResolvedTargetRoot
    if (-not [string]::IsNullOrWhiteSpace($targetParent)) {
        return (Resolve-FullPath -Path $targetParent -AllowMissing)
    }

    throw (Expand-UnicodeEscapes 'Rainmeter SkinPath\uB97C \uD655\uC778\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.')
}

function Get-CompatibleSourceCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SkinsRoot,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedTargetRoot,
        [Parameter(Mandatory = $true)]
        [version]$TargetVersion
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $SkinsRoot -PathType Container)) {
        return @()
    }

    $seen = @{}
    foreach ($directory in Get-ChildItem -LiteralPath $SkinsRoot -Directory -Force) {
        $resolvedSource = Resolve-SourceRootCandidate -Candidate $directory.FullName
        if (-not $resolvedSource) {
            continue
        }

        $key = $resolvedSource.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true

        if ($resolvedSource.Equals($ResolvedTargetRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Log "Source candidate skipped because it is the target root: $resolvedSource" 'WARN'
            continue
        }

        try {
            Assert-MigrationSourceRoot -Root $resolvedSource -TargetVersion $TargetVersion
            $versionText = Get-SkinMetadataVersion -Root $resolvedSource
            $version = ConvertTo-SkinVersion -VersionText $versionText -Context 'SourceRoot'
            $results.Add([pscustomobject]@{
                Path = $resolvedSource
                Version = $version
                VersionText = $versionText
            })
        }
        catch {
            Write-Log "Source candidate skipped because it is not a compatible v1.1.0+ legacy-import source: $resolvedSource ($($_.Exception.Message))" 'WARN'
        }
    }

    return ,@($results | Sort-Object -Property Version -Descending)
}

function Find-SourceRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedTargetRoot,
        [Parameter(Mandatory = $true)]
        [version]$TargetVersion
    )

    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $resolvedSource = Resolve-SourceRootCandidate -Candidate $SourceRoot
        if (-not $resolvedSource) {
            throw "SourceRoot is not a valid v1.1.0+ DMeloper's Block HUD skin root: $SourceRoot"
        }

        Assert-MigrationSourceRoot -Root $resolvedSource -TargetVersion $TargetVersion

        return [pscustomobject]@{
            Path = $resolvedSource
            Detection = 'explicit'
        }
    }

    $skinsRoot = Get-RainmeterSkinsRoot
    $candidates = Get-CompatibleSourceCandidates -SkinsRoot $skinsRoot -ResolvedTargetRoot $ResolvedTargetRoot -TargetVersion $TargetVersion
    if (@($candidates).Count -gt 0) {
        $resolvedSource = $candidates[0].Path
        if ($ConfirmDetectedSource) {
            if ($NonInteractive) {
                throw (Expand-UnicodeEscapes '\uC790\uB3D9 \uAC10\uC9C0\uB41C \uACBD\uB85C\uB294 NonInteractive \uBAA8\uB4DC\uC5D0\uC11C \uD655\uC778\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4. -SourceRoot\uB97C \uC9C1\uC811 \uC9C0\uC815\uD558\uAC70\uB098 -ConfirmDetectedSource\uB97C \uC81C\uAC70\uD558\uC138\uC694.')
            }

            Write-Log "Auto-detected source candidate: $resolvedSource"
            Ensure-ImportFromOldVersionInteractiveSourceSelection
            return (Confirm-DetectedSourceSelection -DetectedSource $resolvedSource -BrowseRoot $skinsRoot)
        }

        Write-Log "Auto-detected source: $resolvedSource"
        return [pscustomobject]@{
            Path = $resolvedSource
            Detection = 'auto'
        }
    }

    if ($NonInteractive -or $WhatIfPreference) {
        throw (T 'Helper_Import_AutoDetectNeedsManual' 'Without opening the folder picker, a compatible v1.1.0+ skin folder cannot be auto-detected. Specify -SourceRoot directly.')
    }

    Ensure-ImportFromOldVersionInteractiveSourceSelection
    return [pscustomobject]@{
        Path = (Select-SourceRootWithDialog -InitialPath $skinsRoot)
        Detection = 'manual'
    }
}

function Invoke-MigrationAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    if ($script:Cmdlet.ShouldProcess($Target, $Action)) {
        & $ScriptBlock
        return $true
    }
    else {
        Write-Log "WhatIf: $Action -> $Target"
        return $false
    }
}
