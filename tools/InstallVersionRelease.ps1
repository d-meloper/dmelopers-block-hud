[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [string]$PackagePath,
    [string]$PackageUrl,
    [string]$ExpectedVersion,
    [string]$ExpectedReleaseVariant,
    [string]$SelectedTargetRoot,
    [switch]$AllowCompatibilityWarning,
    [switch]$NonInteractive,
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.ReleaseCatalog.ps1')

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:SkinRootForLocalization = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$script:LanguageCode = Read-LanguageCode -SkinRoot $script:SkinRootForLocalization
$script:LocTable = Read-LocaleTable -SkinRoot $script:SkinRootForLocalization -LanguageCode $script:LanguageCode
$script:ResolvedCurrentRoot = ''
$script:ResolvedDestinationRoot = ''
$script:DestinationCreated = $false
$script:DestinationReplacementBackupRoot = ''
$script:ImportStarted = $false
$script:SwitchSucceeded = $false
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
}

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Fallback = ''
    )

    Get-LocalizedText -Table $script:LocTable -Key $Key -Fallback $Fallback
}

function TF {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object[]]$Arguments,
        [string]$Fallback = ''
    )

    $normalizedArguments = @()
    foreach ($argument in @($Arguments)) {
        $normalizedArguments += ,([string]$argument)
    }

    Format-LocalizedText -Table $script:LocTable -Key $Key -Arguments $normalizedArguments -Fallback $Fallback
}

function Get-FriendlyInstallErrorMessage {
    param([AllowNull()][string]$RawMessage)

    $resolved = [string]$RawMessage
    if ($resolved -eq (T 'Helper_VersionManager_Update_InstalledImportHelperMissing' 'The installed root is missing tools\ImportFromOldVersion.ps1.')) {
        return $resolved
    }

    return (T 'Helper_VersionManager_Update_ApplyFailed' 'The update could not be applied. Check the log file for details.')
}

function Set-ResultPairValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
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
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
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
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] {1}' -f $Level, $Message
    $script:LogMessages.Add($line)
    Write-Host $line
}

function Save-Log {
    try {
        $parent = Split-Path -Parent $script:LogPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'InstallVersionRelease' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    }
    catch {
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value ''
        Write-Host ("Log save failed: {0}" -f $_.Exception.Message)
    }
}

function Use-CanonicalHelperLogPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot $PSScriptRoot
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
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

function Join-RootPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    Join-Path $Root $RelativePath
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-TextSmart {
    param([Parameter(Mandatory = $true)][string]$Path)

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Read-VariablesFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $map
    }

    foreach ($rawLine in ((Read-TextSmart -Path $Path) -split "`r?`n")) {
        $line = [string]$rawLine
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.TrimStart().StartsWith('[') -or $line.TrimStart().StartsWith(';')) {
            continue
        }
        $parts = $line -split '=', 2
        if ($parts.Length -ne 2) {
            continue
        }
        $map[$parts[0].Trim()] = [string]$parts[1]
    }

    return $map
}

function Get-GeneralSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\General.inc'
}

function Get-SupportSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\Support.inc'
}

function Get-SkinRootReleaseVariant {
    param([Parameter(Mandatory = $true)][string]$Root)

    $general = Read-VariablesFile -Path (Get-GeneralSettingsPath -Root $Root)
    $support = Read-VariablesFile -Path (Get-SupportSettingsPath -Root $Root)
    $languageCode = if ([string]::IsNullOrWhiteSpace([string]$general['LanguageCode'])) { 'en-US' } else { [string]$general['LanguageCode'] }
    $assetPattern = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateReleaseAssetPattern'])) { '' } else { [string]$support['UpdateReleaseAssetPattern'] }

    return (Normalize-BlockHudReleaseVariant `
        -ConfiguredReleaseVariant ([string]$support['UpdateReleaseVariant']) `
        -LanguageCode $languageCode `
        -AssetPattern $assetPattern)
}

function Assert-ExpectedReleaseVariant {
    param(
        [Parameter(Mandatory = $true)][string]$ActualReleaseVariant,
        [AllowNull()][string]$ExpectedReleaseVariant,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        return
    }

    if (-not [string]::Equals($ExpectedReleaseVariant, 'Korea', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($ExpectedReleaseVariant, 'Global', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("ExpectedReleaseVariant must be Korea or Global. value={0}" -f [string]$ExpectedReleaseVariant)
    }
    $expected = Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ExpectedReleaseVariant -LanguageCode '' -AssetPattern ''
    if (-not [string]::Equals($ActualReleaseVariant, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("{0} release variant did not match ExpectedReleaseVariant. expected={1} actual={2}" -f $Context, $expected, $ActualReleaseVariant)
    }
}

function Read-IniMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    $inMetadata = $false
    foreach ($line in ((Read-TextSmart -Path $Path) -split "`r?`n")) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inMetadata = ($matches[1] -ieq 'Metadata')
            continue
        }

        if (-not $inMetadata -or [string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) {
            continue
        }

        $parts = $trimmed -split '=', 2
        if ($parts.Length -eq 2) {
            $values[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    return $values
}

function Get-SkinMetadata {
    param([Parameter(Mandatory = $true)][string]$Root)

    $settingsPath = Join-RootPath -Root $Root -RelativePath 'Settings\Settings.ini'
    $metadata = Read-IniMetadata -Path $settingsPath
    $name = if ($metadata.ContainsKey('Name')) { [string]$metadata['Name'] } else { '' }
    $metadataVersion = if ($metadata.ContainsKey('Version')) { [string]$metadata['Version'] } else { '' }
    $appVersion = ''

    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        foreach ($line in ((Read-TextSmart -Path $settingsPath) -split "`r?`n")) {
            $trimmed = ([string]$line).Trim()
            if ($trimmed -match '^AppVersion\s*=\s*(.+?)\s*$') {
                $appVersion = $matches[1].Trim()
                break
            }
        }
    }

    $version = if (-not [string]::IsNullOrWhiteSpace($appVersion)) { $appVersion } else { $metadataVersion }

    return [PSCustomObject]@{
        Name = $name
        Version = $version
        MetadataVersion = $metadataVersion
        AppVersion = $appVersion
    }
}

function ConvertTo-SkinVersion {
    param(
        [AllowNull()][string]$VersionText,
        [Parameter(Mandatory = $true)][string]$Context
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

function Test-SkinRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    foreach ($relativePath in @('@Resources\Customs', 'Settings', 'Inventory', 'Hotbar')) {
        if (-not (Test-Path -LiteralPath (Join-RootPath -Root $Root -RelativePath $relativePath) -PathType Container)) {
            return $false
        }
    }

    return $true
}

function Resolve-SkinRootCandidate {
    param([Parameter(Mandatory = $true)][string]$Candidate)

    $resolved = Resolve-FullPath -Path $Candidate -AllowMissing
    if ((Test-Path -LiteralPath $resolved -PathType Container) -and (Test-SkinRoot -Root $resolved)) {
        return $resolved
    }

    $child = Join-RootPath -Root $resolved -RelativePath "DMeloper's Block HUD"
    if ((Test-Path -LiteralPath $child -PathType Container) -and (Test-SkinRoot -Root $child)) {
        return (Resolve-FullPath -Path $child)
    }

    return $null
}

function Resolve-PackageRoot {
    param([Parameter(Mandatory = $true)][string]$ExtractRoot)

    if (Test-SkinRoot -Root $ExtractRoot) {
        return $ExtractRoot
    }

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($directory in Get-ChildItem -LiteralPath $ExtractRoot -Directory -Force -ErrorAction SilentlyContinue) {
        if (Test-SkinRoot -Root $directory.FullName) {
            $matches.Add((Resolve-FullPath -Path $directory.FullName))
        }
    }

    if ($matches.Count -eq 1) {
        return $matches[0]
    }
    if ($matches.Count -gt 1) {
        throw 'Extracted package contains more than one valid Block HUD skin root.'
    }

    throw 'Extracted package did not contain a valid Block HUD skin root.'
}

function Get-RainmeterConfigPath {
    foreach ($candidate in @(
        (Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'),
        (Join-Path $env:LOCALAPPDATA 'Rainmeter\Rainmeter.ini')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-FullPath -Path $candidate)
        }
    }

    return ''
}

function Get-RootConfigName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $leaf = Split-Path -Path $Root -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Could not derive a root config name from [$Root]."
    }

    return $leaf
}

function Get-RainmeterExecutablePath {
    $runningPath = Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
        Select-Object -First 1 -ExpandProperty Path
    if ($runningPath -and (Test-Path -LiteralPath $runningPath)) {
        return [System.IO.Path]::GetFullPath($runningPath)
    }

    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Rainmeter\Rainmeter.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Rainmeter.exe could not be located for installed root refresh.'
}

function Invoke-RainmeterBang {
    param(
        [Parameter(Mandatory = $true)][string]$Bang,
        [string[]]$Arguments = @()
    )

    $rainmeterExe = Get-RainmeterExecutablePath
    $argList = @($Bang) + @($Arguments)
    & $rainmeterExe @argList | Out-Null
    $exitCode = $LASTEXITCODE
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        throw ("Rainmeter bang failed with exit code {0}: {1}" -f $exitCode, ($argList -join ' '))
    }
}

function Invoke-InstalledRootRefresh {
    param([Parameter(Mandatory = $true)][string]$Root)

    Write-Log 'Refreshing Rainmeter app list before active version switch.'
    Invoke-RainmeterBang -Bang '!RefreshApp'
}

function Get-RainmeterSkinsRoot {
    param([Parameter(Mandatory = $true)][string]$CurrentRoot)

    $configPath = Get-RainmeterConfigPath
    if (-not [string]::IsNullOrWhiteSpace($configPath)) {
        $content = Read-TextSmart -Path $configPath
        $inRainmeter = $false
        foreach ($rawLine in ($content -split "`r?`n")) {
            $trimmed = ([string]$rawLine).Trim()
            if ($trimmed -match '^\[(.+)\]$') {
                $inRainmeter = ($matches[1] -ieq 'Rainmeter')
                continue
            }
            if (-not $inRainmeter) {
                continue
            }
            if ($trimmed -match '^SkinPath=(.*)$') {
                return (Resolve-FullPath -Path $matches[1].Trim())
            }
        }
    }

    $fallbackRoot = Split-Path -Parent $CurrentRoot
    if ([string]::IsNullOrWhiteSpace($fallbackRoot)) {
        throw 'Rainmeter SkinPath could not be resolved.'
    }

    Write-Log ("Rainmeter SkinPath could not be read; falling back to current root parent: {0}" -f $fallbackRoot) 'WARN'
    return (Resolve-FullPath -Path $fallbackRoot)
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = (Resolve-FullPath -Path $Root).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $Path -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Assert-InstalledSkinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-SkinRoot -Root $Root)) {
        throw "$Name is not a valid Block HUD root."
    }
    if (-not (Test-PathWithinRoot -Root $SkinsRoot -Path $Root) -or
        [string]::Equals((Resolve-FullPath -Path $Root), (Resolve-FullPath -Path $SkinsRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Name must be under Rainmeter SkinPath. root=$Root skinPath=$SkinsRoot"
    }
}

function Convert-ToSafeFolderName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $trimmed = $Name.Trim()
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $trimmed = $trimmed.Replace([string]$character, '_')
    }

    while ($trimmed.Contains('  ')) {
        $trimmed = $trimmed.Replace('  ', ' ')
    }

    $trimmed = $trimmed.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'Folder name resolved to an empty value.'
    }

    return $trimmed
}

function Convert-ToVersionFolderSuffix {
    param([Parameter(Mandatory = $true)][string]$VersionText)

    $normalized = $VersionText.Trim()
    if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }

    return (Convert-ToSafeFolderName -Name $normalized)
}

function Resolve-VersionDestinationRoot {
    param(
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [Parameter(Mandatory = $true)][string]$VersionText,
        [Parameter(Mandatory = $true)][string]$ReleaseVariant
    )

    $versionSuffix = Convert-ToVersionFolderSuffix -VersionText $VersionText
    $variantSuffix = Convert-ToSafeFolderName -Name (Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ReleaseVariant -LanguageCode '' -AssetPattern '')
    $folderName = "DMeloper's Block HUD $variantSuffix v$versionSuffix"
    return (Resolve-FullPath -Path (Join-Path $SkinsRoot $folderName) -AllowMissing)
}

function Get-UrlFileName {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $uri = [System.Uri]$Url
        $fileName = [System.IO.Path]::GetFileName($uri.LocalPath)
    }
    catch {
        $fileName = ''
    }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'release.zip'
    }

    $extension = [System.IO.Path]::GetExtension($fileName)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $fileName += '.zip'
    }
    elseif (-not [string]::Equals($extension, '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'PackageUrl must resolve to a ZIP release package.'
    }

    return (Convert-ToSafeFolderName -Name $fileName)
}

function Resolve-ReleasePackagePath {
    param([Parameter(Mandatory = $true)][string]$CurrentRoot)

    $hasPath = -not [string]::IsNullOrWhiteSpace($PackagePath)
    $hasUrl = -not [string]::IsNullOrWhiteSpace($PackageUrl)
    if ($hasPath -and $hasUrl) {
        throw 'Use either PackagePath or PackageUrl, not both.'
    }
    if (-not $hasPath -and -not $hasUrl) {
        throw 'PackagePath, PackageUrl, or SelectedTargetRoot is required.'
    }

    if ($hasPath) {
        $resolvedPath = Resolve-FullPath -Path $PackagePath
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw 'PackagePath was not found.'
        }
        if (-not [string]::Equals([System.IO.Path]::GetExtension($resolvedPath), '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'PackagePath must be a ZIP release package.'
        }
        return $resolvedPath
    }

    $downloadRoot = Join-RootPath -Root $CurrentRoot -RelativePath '@Resources\Customs\Data\VersionManagerDownloads'
    Ensure-Directory -Path $downloadRoot
    $fileName = Get-UrlFileName -Url $PackageUrl
    $downloadPath = Join-Path $downloadRoot $fileName
    if (Test-Path -LiteralPath $downloadPath -PathType Leaf) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $downloadPath = Join-Path $downloadRoot ("{0}_{1}.zip" -f $baseName, $script:LogStamp)
    }

    Write-Log ("Downloading PackageUrl to: {0}" -f $downloadPath)
    Invoke-WebRequest -Uri $PackageUrl -OutFile $downloadPath -UseBasicParsing
    if (-not [string]::Equals([System.IO.Path]::GetExtension($downloadPath), '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Downloaded package path must be a ZIP release package.'
    }

    return (Resolve-FullPath -Path $downloadPath)
}

function Copy-PackageToDestination {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (Test-Path -LiteralPath $DestinationRoot) {
        throw "Destination install root already exists: $DestinationRoot"
    }

    $parent = Split-Path -Parent $DestinationRoot
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "Could not resolve destination parent for: $DestinationRoot"
    }

    Ensure-Directory -Path $parent
    Copy-Item -LiteralPath $PackageRoot -Destination $DestinationRoot -Recurse -Force
}

function Move-ExistingDestinationForReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$CurrentRoot
    )

    if (-not (Test-Path -LiteralPath $DestinationRoot)) {
        return
    }

    $resolvedDestinationRoot = Resolve-FullPath -Path $DestinationRoot
    $resolvedCurrentRoot = Resolve-FullPath -Path $CurrentRoot
    if ([string]::Equals($resolvedDestinationRoot, $resolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination install root resolves to the current active root and cannot be overwritten: $DestinationRoot"
    }

    $backupRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperInstallReplace_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Write-Log ("DestinationRoot already exists; staging it for overwrite rollback: {0}" -f $DestinationRoot) 'WARN'
    Move-Item -LiteralPath $DestinationRoot -Destination $backupRoot -Force -ErrorAction Stop
    $script:DestinationReplacementBackupRoot = $backupRoot
    Write-Log ("Existing destination backup: {0}" -f $backupRoot)
}

function Remove-RootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return
    }

    try {
        Write-Log ("Removing destination root after {0}: {1}" -f $Reason, $Root) 'WARN'
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Log ("Best-effort cleanup failed for {0}: {1}" -f $Root, $_.Exception.Message) 'WARN'
    }
}

function Complete-DestinationReplacement {
    param([Parameter(Mandatory = $true)][string]$DestinationRoot)

    if ([string]::IsNullOrWhiteSpace($script:DestinationReplacementBackupRoot)) {
        return
    }

    Remove-RootBestEffort -Root $script:DestinationReplacementBackupRoot -Reason 'successful destination overwrite'
    $script:DestinationReplacementBackupRoot = ''
    Write-Log ("Destination overwrite completed: {0}" -f $DestinationRoot)
}

function Restore-DestinationReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($script:DestinationReplacementBackupRoot)) {
        return
    }

    Write-Log ("Restoring previous destination after {0}: {1}" -f $Reason, $DestinationRoot) 'WARN'
    if (Test-Path -LiteralPath $DestinationRoot) {
        Remove-Item -LiteralPath $DestinationRoot -Recurse -Force -ErrorAction Stop
    }
    Move-Item -LiteralPath $script:DestinationReplacementBackupRoot -Destination $DestinationRoot -Force -ErrorAction Stop
    $script:DestinationReplacementBackupRoot = ''
    $script:DestinationCreated = $false
}

function Undo-DestinationInstallAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if (-not [string]::IsNullOrWhiteSpace($script:DestinationReplacementBackupRoot)) {
        Restore-DestinationReplacement -DestinationRoot $DestinationRoot -Reason $Reason
        return
    }

    if ($script:DestinationCreated -and -not $script:SwitchSucceeded) {
        Remove-RootBestEffort -Root $DestinationRoot -Reason $Reason
    }
}

function Test-ScriptSupportsParameter {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    $content = Read-TextSmart -Path $ScriptPath
    return ($content -match ('(?i)\$' + [regex]::Escape($ParameterName) + '\b'))
}

function Convert-OutputToResultPairs {
    param([object[]]$Output)

    $pairs = @{}
    foreach ($line in $Output) {
        $textLine = [string]$line
        if ($textLine -match '^(DMEL_[A-Z]+)=(.*)$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }

    return $pairs
}

function Invoke-HelperScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Write-Log ("Starting {0}: {1}" -f $Operation, $ScriptPath)
    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $pairs = Convert-OutputToResultPairs -Output $output
    $status = [string]($pairs['DMEL_STATUS'])
    $message = [string]($pairs['DMEL_MESSAGE'])
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'ERROR'
        $detail = Convert-ResultPairValueToSingleLine -Value ($output | Out-String)
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = if ([string]::IsNullOrWhiteSpace($detail)) {
                ("{0} helper did not emit DMEL_STATUS." -f $Operation)
            }
            else {
                ("{0} helper did not emit DMEL_STATUS. output={1}" -f $Operation, $detail)
            }
        }
    }
    $status = $status.ToUpperInvariant()

    Write-Log ("{0} completed with status={1} exitCode={2}" -f $Operation, $status, $exitCode)
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        Write-Log ("{0} message: {1}" -f $Operation, $message)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]($pairs['DMEL_LOGPATH']))) {
        Write-Log ("{0} log: {1}" -f $Operation, [string]($pairs['DMEL_LOGPATH']))
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = [string]($pairs['DMEL_SOURCEPATH'])
        LogPath = [string]($pairs['DMEL_LOGPATH'])
        Output = ($output | Out-String)
    }
}

function Assert-HelperOk {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if ($Result.ExitCode -ne 0 -or -not [string]::Equals([string]$Result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
        $detail = if ([string]::IsNullOrWhiteSpace([string]$Result.Message)) { [string]$Result.Output } else { [string]$Result.Message }
        throw ("{0} failed: {1}" -f $Operation, (Convert-ResultPairValueToSingleLine -Value $detail))
    }
}

function Invoke-ImportValidation {
    param(
        [Parameter(Mandatory = $true)][string]$ImportScript,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    if (-not (Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ValidateOnly')) {
        throw 'ImportFromOldVersion.ps1 does not expose the required -ValidateOnly validation contract.'
    }

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs', '-ValidateOnly')
    return (Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import validation')
}

function Invoke-RealImport {
    param(
        [Parameter(Mandatory = $true)][string]$ImportScript,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs')
    $script:ImportStarted = $true
    $result = Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import'
    Assert-HelperOk -Result $result -Operation 'Legacy import'
}

function Resolve-SwitchScript {
    param(
        [Parameter(Mandatory = $true)][string]$PreferredRoot,
        [Parameter(Mandatory = $true)][string]$CurrentRoot
    )

    $managerLocalScript = Join-Path $PSScriptRoot 'SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $managerLocalScript -PathType Leaf) {
        return $managerLocalScript
    }

    $currentScript = Join-RootPath -Root $CurrentRoot -RelativePath 'tools\SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $currentScript -PathType Leaf) {
        return $currentScript
    }

    $preferredScript = Join-RootPath -Root $PreferredRoot -RelativePath 'tools\SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $preferredScript -PathType Leaf) {
        return $preferredScript
    }

    throw 'SwitchActiveSkinVersion.ps1 was not found in the selected or current root.'
}

function Invoke-VersionSwitch {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedRoot,
        [Parameter(Mandatory = $true)][string]$CurrentRoot
    )

    $switchScript = Resolve-SwitchScript -PreferredRoot $SelectedRoot -CurrentRoot $CurrentRoot
    $arguments = @('-CurrentTargetRoot', $CurrentRoot, '-SelectedTargetRoot', $SelectedRoot, '-EmitResultPairs')
    $result = Invoke-HelperScript -ScriptPath $switchScript -Arguments $arguments -Operation 'active version switch'
    Assert-HelperOk -Result $result -Operation 'Active version switch'
    $script:SwitchSucceeded = $true
    return $result
}

function Assert-SwitchResultForSelectedRoot {
    param([Parameter(Mandatory = $true)]$Result)

    if ($Result.ExitCode -ne 0) {
        $detail = if ([string]::IsNullOrWhiteSpace([string]$Result.Message)) { [string]$Result.Output } else { [string]$Result.Message }
        throw ("Active version switch failed: {0}" -f (Convert-ResultPairValueToSingleLine -Value $detail))
    }

    if (-not [string]::Equals([string]$Result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals([string]$Result.Status, 'NOOP', [System.StringComparison]::OrdinalIgnoreCase)) {
        $detail = if ([string]::IsNullOrWhiteSpace([string]$Result.Message)) { [string]$Result.Output } else { [string]$Result.Message }
        throw ("Active version switch failed: {0}" -f (Convert-ResultPairValueToSingleLine -Value $detail))
    }

    $script:SwitchSucceeded = $true
}

function Invoke-SelectedRootSwitch {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedCurrentRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($PackagePath) -or -not [string]::IsNullOrWhiteSpace($PackageUrl)) {
        throw 'SelectedTargetRoot cannot be combined with PackagePath or PackageUrl.'
    }

    $resolvedSelectedRoot = Resolve-SkinRootCandidate -Candidate $SelectedTargetRoot
    if (-not $resolvedSelectedRoot) {
        throw 'SelectedTargetRoot is not a valid Block HUD root.'
    }
    Assert-InstalledSkinRoot -Root $resolvedSelectedRoot -SkinsRoot $SkinsRoot -Name 'SelectedTargetRoot'
    $selectedReleaseVariant = Get-SkinRootReleaseVariant -Root $resolvedSelectedRoot
    Assert-ExpectedReleaseVariant -ActualReleaseVariant $selectedReleaseVariant -ExpectedReleaseVariant $ExpectedReleaseVariant -Context 'SelectedTargetRoot'
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedSelectedRoot

    Write-Log ("CurrentTargetRoot: {0}" -f $ResolvedCurrentRoot)
    Write-Log ("SelectedTargetRoot: {0}" -f $resolvedSelectedRoot)
    Write-Log ("SelectedReleaseVariant: {0}" -f $selectedReleaseVariant)
    $switchResult = Invoke-HelperScript `
        -ScriptPath (Resolve-SwitchScript -PreferredRoot $resolvedSelectedRoot -CurrentRoot $ResolvedCurrentRoot) `
        -Arguments @('-CurrentTargetRoot', $ResolvedCurrentRoot, '-SelectedTargetRoot', $resolvedSelectedRoot, '-EmitResultPairs') `
        -Operation 'active version switch'
    Assert-SwitchResultForSelectedRoot -Result $switchResult

    $switchSourcePath = [string]$switchResult.SourcePath
    if ([string]::IsNullOrWhiteSpace($switchSourcePath)) {
        $switchSourcePath = $resolvedSelectedRoot
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$switchResult.Status)
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $switchSourcePath
    Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ([string]$switchResult.Message)
}

function Invoke-PackageInstall {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedCurrentRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot
    )

    $resolvedPackagePath = Resolve-ReleasePackagePath -CurrentRoot $ResolvedCurrentRoot
    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperReleaseExtract_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $extractRoot
    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $extractRoot -Force
    $packageRoot = Resolve-PackageRoot -ExtractRoot $extractRoot

    $packageMetadata = Get-SkinMetadata -Root $packageRoot
    $packageVersion = ConvertTo-SkinVersion -VersionText ([string]$packageMetadata.Version) -Context 'Package'
    $packageReleaseVariant = Get-SkinRootReleaseVariant -Root $packageRoot
    Assert-ExpectedReleaseVariant -ActualReleaseVariant $packageReleaseVariant -ExpectedReleaseVariant $ExpectedReleaseVariant -Context 'Package'
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        $expectedVersionValue = ConvertTo-SkinVersion -VersionText $ExpectedVersion -Context 'ExpectedVersion'
        if ($packageVersion -ne $expectedVersionValue) {
            throw "Package version did not match ExpectedVersion. expected=$ExpectedVersion package=$($packageMetadata.Version)"
        }
    }

    $destinationRoot = Resolve-VersionDestinationRoot -SkinsRoot $SkinsRoot -VersionText ([string]$packageMetadata.Version) -ReleaseVariant $packageReleaseVariant
    $script:ResolvedDestinationRoot = $destinationRoot
    if (-not (Test-PathWithinRoot -Root $SkinsRoot -Path $destinationRoot)) {
        throw "Destination root is outside the Rainmeter skins root: $destinationRoot"
    }
    if ([string]::Equals((Resolve-FullPath -Path $destinationRoot -AllowMissing), (Resolve-FullPath -Path $ResolvedCurrentRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination install root resolves to the current active root and cannot be overwritten: $destinationRoot"
    }

    Write-Log ("CurrentTargetRoot: {0}" -f $ResolvedCurrentRoot)
    Write-Log ("PackagePath: {0}" -f $resolvedPackagePath)
    Write-Log ("PackageRoot: {0}" -f $packageRoot)
    Write-Log ("PackageVersion: {0}" -f [string]$packageMetadata.Version)
    Write-Log ("PackageReleaseVariant: {0}" -f $packageReleaseVariant)
    Write-Log ("DestinationRoot: {0}" -f $destinationRoot)
    Write-Log 'DestinationRoot policy: side-by-side variant/version-specific root; current fixed root is never overwritten.'

    $packageImportScript = Join-RootPath -Root $packageRoot -RelativePath 'tools\ImportFromOldVersion.ps1'
    if (-not (Test-Path -LiteralPath $packageImportScript -PathType Leaf)) {
        throw 'Package is missing tools\ImportFromOldVersion.ps1.'
    }

    $validationResult = Invoke-ImportValidation -ImportScript $packageImportScript -TargetRoot $packageRoot -SourceRoot $ResolvedCurrentRoot
    $validationOk = ($validationResult.ExitCode -eq 0 -and [string]::Equals([string]$validationResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase))
    if (-not $validationOk -and -not $AllowCompatibilityWarning) {
        $validationDetail = Convert-ResultPairValueToSingleLine -Value ([string]$validationResult.Message)
        if ([string]::IsNullOrWhiteSpace($validationDetail)) {
            $validationDetail = T 'Helper_VersionManager_Update_HelperLogHint' 'See the helper log for details.'
        }
        elseif ($validationDetail.Length -gt 240) {
            $validationDetail = $validationDetail.Substring(0, 240).Trim() + '...'
        }
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $ResolvedCurrentRoot
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (TF 'Helper_VersionManager_Update_CompatibilityValidationFailed' @($validationDetail) 'Release compatibility validation failed; install was not started. %1')
        Write-Log ("Validation warning detail: {0}" -f (Convert-ResultPairValueToSingleLine -Value ([string]$validationResult.Message))) 'WARN'
        return
    }
    elseif (-not $validationOk) {
        Write-Log ("Compatibility warning allowed: {0}" -f (Convert-ResultPairValueToSingleLine -Value ([string]$validationResult.Message))) 'WARN'
    }

    try {
        Move-ExistingDestinationForReplacement -DestinationRoot $destinationRoot -CurrentRoot $ResolvedCurrentRoot
        Copy-PackageToDestination -PackageRoot $packageRoot -DestinationRoot $destinationRoot
        $script:DestinationCreated = $true
        Use-CanonicalHelperLogPath -Root $destinationRoot -Prefix 'InstallVersionRelease'

        if ($validationOk) {
            $installedImportScript = Join-RootPath -Root $destinationRoot -RelativePath 'tools\ImportFromOldVersion.ps1'
            if (-not (Test-Path -LiteralPath $installedImportScript -PathType Leaf)) {
                throw (T 'Helper_VersionManager_Update_InstalledImportHelperMissing' 'The installed root is missing tools\ImportFromOldVersion.ps1.')
            }
            Invoke-RealImport -ImportScript $installedImportScript -TargetRoot $destinationRoot -SourceRoot $ResolvedCurrentRoot
        }
        else {
            Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        }

        Invoke-InstalledRootRefresh -Root $destinationRoot
        Invoke-VersionSwitch -SelectedRoot $destinationRoot -CurrentRoot $ResolvedCurrentRoot | Out-Null
        Complete-DestinationReplacement -DestinationRoot $destinationRoot
    }
    catch {
        $failureMessage = $_.Exception.Message
        Undo-DestinationInstallAttempt -DestinationRoot $destinationRoot -Reason 'failed release install'
        throw $failureMessage
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $destinationRoot
    if (-not $validationOk) {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Update_InstalledWithoutImport' 'Installed the selected release without importing current data, then switched active configs.')
    }
    else {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Update_InstalledWithImport' 'Installed the selected release, imported current data, and switched active configs.')
    }
}

function Invoke-InstallVersionRelease {
    $resolvedCurrentRoot = Resolve-SkinRootCandidate -Candidate $CurrentTargetRoot
    if (-not $resolvedCurrentRoot) {
        throw 'CurrentTargetRoot is not a valid Block HUD install root.'
    }
    $script:ResolvedCurrentRoot = $resolvedCurrentRoot
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedCurrentRoot
    Use-CanonicalHelperLogPath -Root $resolvedCurrentRoot -Prefix 'InstallVersionRelease'

    $skinsRoot = Get-RainmeterSkinsRoot -CurrentRoot $resolvedCurrentRoot
    if (-not (Test-Path -LiteralPath $skinsRoot -PathType Container)) {
        throw "Rainmeter skins root does not exist: $skinsRoot"
    }
    Assert-InstalledSkinRoot -Root $resolvedCurrentRoot -SkinsRoot $skinsRoot -Name 'CurrentTargetRoot'

    if (-not [string]::IsNullOrWhiteSpace($SelectedTargetRoot)) {
        Invoke-SelectedRootSwitch -ResolvedCurrentRoot $resolvedCurrentRoot -SkinsRoot $skinsRoot
        return
    }

    Invoke-PackageInstall -ResolvedCurrentRoot $resolvedCurrentRoot -SkinsRoot $skinsRoot
}

try {
    Invoke-InstallVersionRelease
}
catch {
    $friendlyMessage = Get-FriendlyInstallErrorMessage -RawMessage ([string]$_.Exception.Message)
    if (($script:DestinationCreated -or -not [string]::IsNullOrWhiteSpace($script:DestinationReplacementBackupRoot)) -and -not [string]::IsNullOrWhiteSpace($script:ResolvedDestinationRoot)) {
        Undo-DestinationInstallAttempt -DestinationRoot $script:ResolvedDestinationRoot -Reason 'error rollback'
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot)) {
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $script:ResolvedCurrentRoot
        if (-not $script:SwitchSucceeded) {
            Use-CanonicalHelperLogPath -Root $script:ResolvedCurrentRoot -Prefix 'InstallVersionRelease'
        }
    }
    if (-not $script:ImportStarted) {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    }
    else {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    }
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $friendlyMessage
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
}
finally {
    Save-Log
    Emit-ResultPairs
}
