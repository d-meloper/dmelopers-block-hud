[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TargetRoot,
    [string]$SourceRoot,
    [switch]$NonInteractive,
    [switch]$ResetPositions,
    [switch]$ConfirmDetectedSource,
    [switch]$ValidateOnly,
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Cmdlet = $PSCmdlet
$script:Utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}
$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = ''
$script:ResolvedTargetRoot = ''
$script:ResolvedSourceRoot = ''
$script:TouchedRainmeterFiles = New-Object System.Collections.Generic.List[string]
$script:SkippedSourceFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$script:SkippedSourceDirectories = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$script:ImportTargetMutationStarted = $false
$script:EphemeralRollbackRoot = ''
$script:AutoRollbackAttempted = $false
$script:AutoRollbackSucceeded = $false
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'LowSpecSettings.Policy.ps1')
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:SkinRootForLocalization = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$script:LanguageCode = Read-LanguageCode -SkinRoot $script:SkinRootForLocalization
$script:LocTable = Read-LocaleTable -SkinRoot $script:SkinRootForLocalization -LanguageCode $script:LanguageCode

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
    foreach ($key in @('DMEL_STATUS', 'DMEL_SOURCEPATH', 'DMEL_BACKUPPATH', 'DMEL_LOGPATH', 'DMEL_MESSAGE')) {
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
    return @(
        '@Resources\Customs\Settings',
        '@Resources\Customs\Data',
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Images\Player',
        'Settings\State.inc'
    )
}

function Get-TemporaryRollbackScopeRelativePaths {
    return @(
        '@Resources\Customs',
        'Settings\State.inc',
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

function Ensure-FinalPathApi {
    if ('DMeloperMigrationFinalPath' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class DMeloperMigrationFinalPath {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern uint GetFinalPathNameByHandle(
        SafeFileHandle hFile,
        StringBuilder lpszFilePath,
        uint cchFilePath,
        uint dwFlags);
}
"@
}

function Get-FinalExistingPathInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-FullPath -Path $Path
    $item = Get-Item -LiteralPath $resolved

    try {
        Ensure-FinalPathApi
        $fileFlagBackupSemantics = 0x02000000
        $openExisting = 3
        $shareReadWriteDelete = 7
        $handle = [DMeloperMigrationFinalPath]::CreateFile($item.FullName, 0, $shareReadWriteDelete, [IntPtr]::Zero, $openExisting, $fileFlagBackupSemantics, [IntPtr]::Zero)
        if ($handle.IsInvalid) {
            $handle.Dispose()
            throw "CreateFile failed for $($item.FullName)"
        }

        try {
            $builder = New-Object System.Text.StringBuilder 1024
            $length = [DMeloperMigrationFinalPath]::GetFinalPathNameByHandle($handle, $builder, [uint32]$builder.Capacity, 0)
            if ($length -le 0) {
                throw "GetFinalPathNameByHandle failed for $($item.FullName)"
            }
            if ($length -gt $builder.Capacity) {
                $builder = New-Object System.Text.StringBuilder ([int]$length + 1)
                $length = [DMeloperMigrationFinalPath]::GetFinalPathNameByHandle($handle, $builder, [uint32]$builder.Capacity, 0)
            }

            $finalPath = $builder.ToString()
            if ($finalPath.StartsWith('\\?\UNC\')) {
                $finalPath = '\' + $finalPath.Substring(7)
            }
            elseif ($finalPath.StartsWith('\\?\')) {
                $finalPath = $finalPath.Substring(4)
            }
            return [pscustomobject]@{
                Success = $true
                Path = $finalPath.TrimEnd('\', '/').ToLowerInvariant()
                Error = ''
            }
        }
        finally {
            $handle.Dispose()
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

    foreach ($relativePath in @('@Resources\Customs', 'Settings', 'Inventory', 'Hotbar')) {
        if (-not (Test-Path -LiteralPath (Join-RootPath -Root $Root -RelativePath $relativePath) -PathType Container)) {
            return $false
        }
    }

    return $true
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

    $settingsPath = Join-RootPath -Root $Root -RelativePath 'Settings\Settings.ini'
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
        'Settings\State.inc',
        'Settings\Settings.ini'
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

    $resolvedLanguageCode = Normalize-LanguageCode -Value $ImportedLanguageCode -Fallback 'ko-KR'
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
        'Settings\Settings.ini'
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

function Select-SourceRootWithDialog {
    param([Parameter(Mandatory = $true)][string]$InitialPath)

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = T 'Helper_Import_FolderPrompt' "Select the older (v1.1.0+) DMeloper's Block HUD folder."
    $dialog.ShowNewFolderButton = $false
    if (Test-Path -LiteralPath $InitialPath -PathType Container) {
        $dialog.SelectedPath = $InitialPath
    }

    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        throw (New-Object System.OperationCanceledException (T 'Helper_Import_SelectCanceled' 'The user canceled old-data import.'))
    }

    $selectedDirectory = $dialog.SelectedPath
    if ($null -eq $selectedDirectory) {
        $selectedDirectory = ''
    }
    $selectedDirectory = $selectedDirectory.Trim()
    $selected = Resolve-SourceRootCandidate -Candidate $selectedDirectory
    if (-not $selected) {
        $message = T 'Helper_Import_InvalidFolder' 'The selected folder is not a valid v1.1.0+ skin folder:'
        throw ($message + ' ' + $selectedDirectory)
    }

    return $selected
}

function Confirm-DetectedSourceSelection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DetectedSource,
        [Parameter(Mandatory = $true)]
        [string]$BrowseRoot
    )

    Add-Type -AssemblyName System.Windows.Forms
    $messageLines = @(
        (T 'Helper_Import_ConfirmFound' 'An older (v1.1.0+) skin folder to import was found.'),
        '',
        $DetectedSource,
        '',
        (T 'Helper_Import_ConfirmYes' 'Yes: use this folder'),
        (T 'Helper_Import_ConfirmNo' 'No: choose a different folder'),
        (T 'Helper_Import_ConfirmCancel' 'Cancel: exit without changes')
    )
    $message = [string]::Join([Environment]::NewLine, $messageLines)
    $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        (T 'Helper_Import_ConfirmTitle' 'Old-data import'),
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1
    )

    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "Auto-detected source confirmed: $DetectedSource"
            return [pscustomobject]@{
                Path = $DetectedSource
                Detection = 'auto'
            }
        }
        ([System.Windows.Forms.DialogResult]::No) {
            $selectedSource = Select-SourceRootWithDialog -InitialPath $BrowseRoot
            Write-Log "Source selected after declining auto-detected source: $selectedSource"
            return [pscustomobject]@{
                Path = $selectedSource
                Detection = 'manual'
            }
        }
        default {
            Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $DetectedSource
            throw (New-Object System.OperationCanceledException (T 'Helper_Import_SelectCanceled' 'The user canceled old-data import.'))
        }
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

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-TextSmart {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-SkippedSourcePath -Path $Path) {
        return ''
    }

    [byte[]]$bytes = Read-AllBytesShared -Path $Path
    if ($null -eq $bytes) {
        $bytes = [byte[]]@()
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return $script:Utf16LeBom.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    try {
        return $script:StrictUtf8.GetString($bytes)
    }
    catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Write-Utf16Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
)

    Assert-SafeTargetPath -Path $Path
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf16LeBom)
    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension.Equals('.ini', [System.StringComparison]::OrdinalIgnoreCase) -or $extension.Equals('.inc', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:TouchedRainmeterFiles.Add($Path)
    }
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
)

    Assert-SafeTargetPath -Path $Path
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function Test-PathStartsWith {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Prefix)) {
        return $false
    }

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $normalizedPrefix = [System.IO.Path]::GetFullPath($Prefix).TrimEnd('\', '/')
    return (
        $normalizedPath.Equals($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedPrefix + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedPrefix + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-SystemPSModulePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $systemPrefixes = New-Object System.Collections.Generic.List[string]
    foreach ($prefix in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($prefix)) {
            $systemPrefixes.Add($prefix)
        }
    }

    foreach ($prefix in $systemPrefixes) {
        if (Test-PathStartsWith -Path $Path -Prefix $prefix) {
            return $true
        }
    }

    return $false
}

function Get-UserPSModulePathCandidates {
    $candidates = New-Object System.Collections.Generic.List[object]
    $entries = @([string]$env:PSModulePath -split [regex]::Escape([System.IO.Path]::PathSeparator))

    $index = 0
    foreach ($entry in $entries) {
        $trimmed = ([string]$entry).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $index++
            continue
        }

        try {
            $full = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($trimmed)).TrimEnd('\', '/')
        }
        catch {
            $index++
            continue
        }

        if (Test-SystemPSModulePath -Path $full) {
            $index++
            continue
        }

        $candidates.Add([pscustomobject]@{
            Path = $full
            Index = $index
        })
        $index++
    }

    return @($candidates | Sort-Object -Property Index | ForEach-Object { [string]$_.Path })
}

function Test-SourceInstallerNeedsRootConfigNameCompat {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    $installerPath = Join-RootPath -Root $SourceRoot -RelativePath 'tools\InstallVersionRelease.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        return $false
    }

    $content = Read-TextSmart -Path $installerPath
    $usesRootConfigName = ($content -match '\bGet-RootConfigName\b')
    $definesRootConfigName = ($content -match '(?m)^\s*function\s+Get-RootConfigName\b')
    return ($usesRootConfigName -and -not $definesRootConfigName)
}

function New-RootConfigNameCompatModuleContent {
    return @'
function Get-RootConfigName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $leaf = Split-Path -Path $Root -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Could not derive a root config name from [$Root]."
    }

    return $leaf
}

Export-ModuleMember -Function Get-RootConfigName
'@
}

function New-RootConfigNameCompatManifestContent {
    return @'
@{
    RootModule = 'DMeloperBlockHudCompat.psm1'
    ModuleVersion = '1.3.3'
    GUID = '7e2698fc-2f2e-4cda-b6e8-b0df5cbf8931'
    Author = 'DMeloper'
    CompanyName = 'DMeloper'
    Copyright = '(c) DMeloper. All rights reserved.'
    Description = 'Compatibility shim for DMeloper Block HUD v1.2.0 skin-manager updates.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-RootConfigName')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
'@
}

function Install-RootConfigNameCompatModule {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    if (-not (Test-SourceInstallerNeedsRootConfigNameCompat -SourceRoot $SourceRoot)) {
        return
    }

    $moduleName = 'DMeloperBlockHudCompat'
    $moduleContent = New-RootConfigNameCompatModuleContent
    $manifestContent = New-RootConfigNameCompatManifestContent
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($basePath in Get-UserPSModulePathCandidates) {
        $moduleDirectory = Join-Path $basePath $moduleName
        $probePath = Join-Path $moduleDirectory '.write-test'
        $modulePath = Join-Path $moduleDirectory ($moduleName + '.psm1')
        $manifestPath = Join-Path $moduleDirectory ($moduleName + '.psd1')

        try {
            if (-not $script:Cmdlet.ShouldProcess($moduleDirectory, 'Install v1.2.0 updater Get-RootConfigName compatibility module')) {
                $errors.Add(("{0}: module install was skipped by ShouldProcess" -f $moduleDirectory))
                continue
            }

            if (-not (Test-Path -LiteralPath $moduleDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
            }

            [System.IO.File]::WriteAllText($probePath, 'ok', $script:Utf8NoBom)
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            [System.IO.File]::WriteAllText($modulePath, $moduleContent, $script:Utf8NoBom)
            [System.IO.File]::WriteAllText($manifestPath, $manifestContent, $script:Utf8NoBom)
            Write-Log ("Installed v1.2.0 updater compatibility module for Get-RootConfigName: {0}" -f $moduleDirectory)
            return
        }
        catch {
            $errors.Add(("{0}: {1}" -f $moduleDirectory, $_.Exception.Message))
        }
        finally {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }

    $detail = if ($errors.Count -gt 0) { $errors -join ' | ' } else { 'No writable user PSModulePath entry was available.' }
    throw "Could not install the v1.2.0 updater compatibility module required for Get-RootConfigName autoload. $detail"
}

function Test-Utf16LeBomStrict {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 2 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xFE) {
        return $false
    }
    if (($bytes.Length % 2) -ne 0) {
        return $false
    }
    if ($bytes.Length -ge 4 -and $bytes[2] -eq 0xFF -and $bytes[3] -eq 0xFE) {
        return $false
    }

    try {
        [void]$script:Utf16LeBom.GetString($bytes)
        return $true
    }
    catch {
        return $false
    }
}

function Validate-TouchedRainmeterFiles {
    $seen = @{}
    foreach ($path in $script:TouchedRainmeterFiles) {
        if ($seen.ContainsKey($path)) {
            continue
        }
        $seen[$path] = $true
        if (-not (Test-Utf16LeBomStrict -Path $path)) {
            throw "Touched Rainmeter file is not valid UTF-16 LE BOM: $path"
        }
    }
}

function New-VariablesMap {
    New-Object System.Collections.Specialized.OrderedDictionary
}

function Set-MapValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowNull()]
        [string]$Value
    )

    if ($Map.Contains($Key)) {
        $Map[$Key] = $Value
    }
    else {
        $Map.Add($Key, $Value)
    }
}

function Normalize-JukeboxPlaybackSourceMode {
    param([AllowNull()][string]$Value)

    $mode = ([string]$Value).Trim().ToLowerInvariant()
    if ($mode -eq 'external') {
        return 'external'
    }

    return 'local'
}

function Normalize-MinecraftSkinModel {
    param([AllowNull()][string]$Value)

    $model = ([string]$Value).Trim().ToLowerInvariant()
    if ($model -eq 'slim' -or $model -eq 'alex') {
        return 'slim'
    }

    return 'wide'
}

function Normalize-ImportedVariableValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowNull()]
        [string]$Value
    )

    if ($Key -eq 'JukeboxPlaybackSourceMode') {
        return (Normalize-JukeboxPlaybackSourceMode -Value $Value)
    }
    if ($Key -eq 'MinecraftSkinModel') {
        return (Normalize-MinecraftSkinModel -Value $Value)
    }

    return $Value
}

function Normalize-ImportedVariablesInPlace {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables
    )

    if ($Variables.Contains('JukeboxPlaybackSourceMode')) {
        Set-MapValue -Map $Variables -Key 'JukeboxPlaybackSourceMode' -Value (Normalize-JukeboxPlaybackSourceMode -Value $Variables['JukeboxPlaybackSourceMode'])
    }
    if ($Variables.Contains('MinecraftSkinModel')) {
        Set-MapValue -Map $Variables -Key 'MinecraftSkinModel' -Value (Normalize-MinecraftSkinModel -Value $Variables['MinecraftSkinModel'])
    }
}

function Read-VariablesFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $variables = New-VariablesMap
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $variables
    }
    if (Test-SkippedSourcePath -Path $Path) {
        return $variables
    }

    $content = Read-TextSmart -Path $Path
    $inVariables = $false
    foreach ($line in ($content -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inVariables = ($matches[1] -ieq 'Variables')
            continue
        }

        if (-not $inVariables -or $trimmed.Length -eq 0 -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1)
        if ($key.Length -gt 0) {
            Set-MapValue -Map $variables -Key $key -Value $value
        }
    }

    return $variables
}

function ConvertTo-VariablesContent {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("[Variables]`r`n")
    foreach ($key in $Variables.Keys) {
        [void]$builder.Append($key)
        [void]$builder.Append('=')
        [void]$builder.Append($Variables[$key])
        [void]$builder.Append("`r`n")
    }

    return $builder.ToString()
}

function Merge-VariablesFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [switch]$SameKeysOnly,
        [string[]]$ExcludeKeyPatterns = @(),
        [System.Collections.Specialized.OrderedDictionary]$Backfill,
        [hashtable]$ImageRenameMap
    )

    $targetVariables = Read-VariablesFile -Path $TargetPath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source variables: $SourcePath"
        if ($Backfill) {
            foreach ($key in $Backfill.Keys) {
                if (-not $targetVariables.Contains($key)) {
                    Set-MapValue -Map $targetVariables -Key $key -Value $Backfill[$key]
                }
            }

            Normalize-ImportedVariablesInPlace -Variables $targetVariables
            $backfillContent = ConvertTo-VariablesContent -Variables $targetVariables
            $null = Invoke-MigrationAction -Action 'Backfill variables' -Target $TargetPath -ScriptBlock {
                Write-Utf16Text -Path $TargetPath -Content $backfillContent
            }
        }
        return
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath

    foreach ($key in $sourceVariables.Keys) {
        $excluded = $false
        foreach ($pattern in $ExcludeKeyPatterns) {
            if ($key -match $pattern) {
                $excluded = $true
                break
            }
        }
        if ($excluded) {
            continue
        }

        if ($SameKeysOnly -and -not $targetVariables.Contains($key)) {
            continue
        }

        $value = $sourceVariables[$key]
        if ($key -match '_Image$') {
            $value = Repair-ImportImageValue -Value $value -ImageRenameMap $ImageRenameMap
        }
        $value = Normalize-ImportedVariableValue -Key $key -Value $value

        Set-MapValue -Map $targetVariables -Key $key -Value $value
    }

    if ($Backfill) {
        foreach ($key in $Backfill.Keys) {
            if (-not $targetVariables.Contains($key)) {
                Set-MapValue -Map $targetVariables -Key $key -Value $Backfill[$key]
            }
        }
    }

    Normalize-ImportedVariablesInPlace -Variables $targetVariables
    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge variables' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Get-HerobrineStatsKeys {
    return @(
        'HerobrineTotalAppearances',
        'HerobrineVisibleSeconds',
        'HerobrineCaptures'
    )
}

function New-HerobrineStatsDefaultVariables {
    $variables = New-VariablesMap
    foreach ($key in Get-HerobrineStatsKeys) {
        Set-MapValue -Map $variables -Key $key -Value '0'
    }

    return $variables
}

function Merge-HerobrineStatsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $mergedVariables = New-HerobrineStatsDefaultVariables
    if (Test-SkippedSourcePath -Path $SourcePath) {
        Write-Log "Reset Herobrine stats to defaults because the source file was marked unreadable during preflight: $SourcePath" 'WARN'
    }
    elseif (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
        Write-Log "Reset Herobrine stats to the current persistent extra-content schema; old source counters were not imported."
    }
    else {
        Write-Log "Initialized missing source Herobrine stats with current defaults: $SourcePath"
    }

    $content = ConvertTo-VariablesContent -Variables $mergedVariables
    $null = Invoke-MigrationAction -Action 'Merge Herobrine stats' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Get-HerobrineStateKeys {
    return @(
        'HerobrineApparitionActive',
        'HerobrineApparitionX',
        'HerobrineApparitionY',
        'HerobrineApparitionW',
        'HerobrineApparitionH',
        'HerobrineApparitionMessageIndex'
    )
}

function New-HerobrineStateDefaultVariables {
    $variables = New-VariablesMap
    Set-MapValue -Map $variables -Key 'HerobrineApparitionActive' -Value '0'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionX' -Value '0'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionY' -Value '0'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionW' -Value '39'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionH' -Value '57'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionMessageIndex' -Value '0'

    return $variables
}

function Merge-HerobrineStateFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $mergedVariables = New-HerobrineStateDefaultVariables
    if (Test-SkippedSourcePath -Path $SourcePath) {
        Write-Log "Reset Herobrine apparition state to inactive defaults because the source file was marked unreadable during preflight: $SourcePath" 'WARN'
    }
    elseif (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
        Write-Log "Reset Herobrine apparition state to inactive defaults; source active apparition state is not imported."
    }
    else {
        Write-Log "Initialized missing source Herobrine apparition state with inactive defaults: $SourcePath"
    }

    $content = ConvertTo-VariablesContent -Variables $mergedVariables
    $null = Invoke-MigrationAction -Action 'Merge Herobrine state' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

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

    $asset = ([string]$Value).Trim().Replace('/', '\')
    if ($asset.Length -eq 0) {
        return ''
    }

    if ($asset.Contains('..') -or $asset -match '[\\#\[\]";|:<>?*]') {
        return ''
    }

    if ($asset -notmatch '\.[^\.]+$') {
        $asset = "$asset.png"
    }

    $extension = [System.IO.Path]::GetExtension($asset).TrimStart('.').ToLowerInvariant()
    if ($extension.Length -eq 0 -or @('png', 'jpg', 'jpeg', 'jpe', 'bmp', 'gif', 'tif', 'tiff', 'ico', 'jxr', 'wdp', 'dds') -notcontains $extension) {
        return ''
    }

    return $asset
}

function Get-ImageAdjustmentKeyForMigration {
    param([AllowNull()][string]$Value)

    $asset = Normalize-ImageAssetForMigration -Value $Value
    if ($asset.Length -eq 0) {
        return ''
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($asset)
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
        [hashtable]$ImageRenameMap
    )

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
            $canonical = Get-CanonicalExistingPath -Path $currentDirectory
        }
        catch {
            Add-SkippedSourcePath -Path $currentDirectory -Directory
            Write-Log "Skipped unreadable source directory: $currentDirectory ($($_.Exception.Message))" 'WARN'
            continue
        }

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
        Write-Log "Source $Description is absent; keeping current target data: $Path"
        return
    }

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
        Write-Log "Source $Description directory is absent; keeping current target data: $Path"
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

        Test-ReadableSourceFile -Path $sourcePath
    }

    foreach ($optionalFile in @(
        '@Resources\Customs\Settings\General.inc',
        '@Resources\Customs\Data\ImageAdjustments.inc',
        '@Resources\Customs\Data\HerobrineStats.inc',
        '@Resources\Customs\Data\HerobrineState.inc',
        '@Resources\Customs\Data\EditorFavoritesCatalog.txt'
    )) {
        $probePath = Join-RootPath -Root $SourceRoot -RelativePath $optionalFile
        Invoke-OptionalSourceProbe -Path $probePath -Description $optionalFile -Probe {
            Test-ReadableSourceFile -Path $probePath
        }
    }

    foreach ($optionalDirectory in @(
        '@Resources\Customs\Images\Items',
        '@Resources\Customs\Images\Player'
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

        foreach ($relativePath in (Get-TemporaryRollbackScopeRelativePaths)) {
            $sourcePath = Join-RootPath -Root $TargetRoot -RelativePath $relativePath
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                continue
            }

            $destinationPath = Join-Path $script:EphemeralRollbackRoot $relativePath
            $parent = Split-Path -Parent $destinationPath
            if (-not [string]::IsNullOrWhiteSpace($parent)) {
                Ensure-Directory -Path $parent
            }

            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -Recurse
        }

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
    foreach ($relativePath in (Get-TemporaryRollbackScopeRelativePaths)) {
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
        '@Resources\Customs\Images\Player',
        'Settings\State.inc'
    )) {
        $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath $relativePath
        $targetPath = Join-RootPath -Root $TargetRoot -RelativePath $relativePath

        Clear-TargetPath -Path $targetPath
        Copy-PathSnapshot -SourcePath $sourcePath -TargetPath $targetPath

        if ($relativePath.EndsWith('.inc', [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$script:TouchedRainmeterFiles.Add($targetPath)
            continue
        }

        if ($relativePath.StartsWith('@Resources\Customs\', [System.StringComparison]::OrdinalIgnoreCase)) {
            foreach ($rainmeterFile in Get-ChildItem -LiteralPath $targetPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -in @('.ini', '.inc')
            }) {
                [void]$script:TouchedRainmeterFiles.Add($rainmeterFile.FullName)
            }
        }
    }
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
        foreach ($file in Get-ChildItem -LiteralPath $playerImageDirectory -File -Filter 'MinecraftSkinBody_*.png') {
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
    foreach ($file in (Get-SourceDirectoryFilesLoopSafe -SourceDirectory $Directory | Sort-Object { [System.IO.Path]::GetFileName($_) })) {
        if (Test-SkippedSourcePath -Path $file) {
            continue
        }

        $asset = Normalize-ImageAssetForMigration -Value ([System.IO.Path]::GetFileName($file))
        if ([string]::IsNullOrWhiteSpace($asset)) {
            continue
        }

        if ($asset.Equals('more.png', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($seen.ContainsKey($asset)) {
            continue
        }
        $seen[$asset] = $true
        $assets.Add($asset)
    }

    return $assets.ToArray()
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
        $TargetRoot = Split-Path -Parent $PSScriptRoot
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
    $hotbarBackfill = New-HotbarSlot10ReservedBackfill -LanguageCode $importedLanguageCode
    Merge-VariablesFile -SourcePath $sourceHotbarPath -TargetPath $targetHotbarPath -SameKeysOnly -ExcludeKeyPatterns @('^HotbarItem_Slot10_') -Backfill $hotbarBackfill -ImageRenameMap $imageRenameMap
    Normalize-HotbarSlot10ReservedLabel -TargetHotbarPath $targetHotbarPath -LanguageCode $importedLanguageCode
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

try {
    Invoke-Migration
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    if ($ValidateOnly) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Legacy import validation passed.'
    }
    else {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Legacy import completed.'
    }
    Save-Log
    Emit-ResultPairs
    exit 0
}
catch [System.OperationCanceledException] {
    Write-Log $_.Exception.Message 'WARN'
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'CANCEL'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    Save-Log
    Emit-ResultPairs
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    if ($script:ImportTargetMutationStarted -and -not $script:AutoRollbackAttempted -and -not [string]::IsNullOrWhiteSpace($script:EphemeralRollbackRoot)) {
        $script:AutoRollbackAttempted = $true
        try {
            Restore-TargetStateFromTemporaryRollback -TargetRoot $script:ResolvedTargetRoot -RollbackRoot $script:EphemeralRollbackRoot
            $script:AutoRollbackSucceeded = $true
            Add-ResultPairMessage -Message 'Automatic rollback restored the pre-import target state from a temporary helper workspace.'
            Remove-TemporaryRollbackRootBestEffort -RollbackRoot $script:EphemeralRollbackRoot -Reason 'successful automatic rollback'
            $script:EphemeralRollbackRoot = ''
        }
        catch {
            Write-Log ("Automatic rollback failed: {0}" -f $_.Exception.Message) 'ERROR'
            if ($_.ScriptStackTrace) {
                Write-Log $_.ScriptStackTrace 'ERROR'
            }
            Add-ResultPairMessage -Message 'Automatic rollback failed after legacy import mutation. Review the helper log before retrying.'
        }
    }
    Save-Log
    Emit-ResultPairs
    exit 1
}
