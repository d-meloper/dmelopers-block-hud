[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$ExpectedReleaseVariant,
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
$script:ResolvedCurrentRoot = ''
$script:ResolvedLatestRoot = ''
$script:ResolvedStageRoot = ''
$script:ReplacementRollbackRoot = ''
$script:FailedLatestRoot = ''
$script:LatestRootCreated = $false
$script:StageRootCreated = $false
$script:FixedRootReplacementStarted = $false
$script:FixedRootInstalled = $false
$script:ImportStarted = $false
$script:SwitchSucceeded = $false
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
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

        [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'UpdateToLatestVersion' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
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

    throw 'Rainmeter.exe could not be located for post-update refresh.'
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
        throw 'Package identity resolved to an empty folder name.'
    }

    return $trimmed
}

function Get-PackageIdentityName {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)]$PackageMetadata,
        [Parameter(Mandatory = $true)][string]$ExtractRoot
    )

    $identity = [System.IO.Path]::GetFileName($PackageRoot.TrimEnd('\', '/'))
    if ([string]::Equals((Resolve-FullPath -Path $PackageRoot), (Resolve-FullPath -Path $ExtractRoot), [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageMetadata.Name)) {
        $identity = [string]$PackageMetadata.Name
    }

    $identity = $identity -replace '\s+(?i:settings)$', ''
    $identity = $identity -replace '\s+[vV]?\d+(\.\d+){1,3}.*$', ''
    return (Convert-ToSafeFolderName -Name $identity)
}

function Resolve-LatestDestinationRoot {
    param(
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [Parameter(Mandatory = $true)][string]$IdentityName
    )

    $folderName = Convert-ToSafeFolderName -Name $IdentityName
    return (Resolve-FullPath -Path (Join-Path $SkinsRoot $folderName) -AllowMissing)
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

function New-StagedLatestRoot {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$IdentityName
    )

    $stageParent = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestStage_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    $stageRoot = Join-Path $stageParent (Convert-ToSafeFolderName -Name $IdentityName)
    Ensure-Directory -Path $stageParent
    Copy-Item -LiteralPath $PackageRoot -Destination $stageRoot -Recurse -Force
    $script:ResolvedStageRoot = (Resolve-FullPath -Path $stageRoot)
    $script:StageRootCreated = $true
    Write-Log ("StagedLatestRoot: {0}" -f $script:ResolvedStageRoot)
    return $script:ResolvedStageRoot
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
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    try {
        Remove-Item -LiteralPath $Root -Force -Recurse
        Write-Log ("Cleaned root after {0}: {1}" -f $Reason, $Root)
    }
    catch {
        Write-Log ("Failed to clean root after {0}: {1} ({2})" -f $Reason, $Root, $_.Exception.Message) 'WARN'
    }
}

function Remove-RootWithResult {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return [PSCustomObject]@{
            Status = 'OK'
            Message = 'Root was already absent.'
        }
    }

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    try {
        Remove-Item -LiteralPath $Root -Force -Recurse
        Write-Log ("Cleaned root after {0}: {1}" -f $Reason, $Root)
        return [PSCustomObject]@{
            Status = 'OK'
            Message = 'Cleanup completed.'
        }
    }
    catch {
        $message = "Failed to clean root after ${Reason}: $Root ($($_.Exception.Message))"
        Write-Log $message 'WARN'
        return [PSCustomObject]@{
            Status = 'WARN'
            Message = $message
        }
    }
}

function Test-ConfigFileExists {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $folderPath = Join-RootPath -Root $Root -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        return $false
    }

    return (Test-Path -LiteralPath (Join-Path $folderPath $FileName) -PathType Leaf)
}

function Restore-FixedRootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$FinalRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot
    )

    if (-not (Test-Path -LiteralPath $RollbackRoot -PathType Container)) {
        throw "Rollback root is missing; manual recovery may be required: $RollbackRoot"
    }

    if (Test-Path -LiteralPath $FinalRoot) {
        throw "Final root already exists; refusing to overwrite it during rollback: $FinalRoot"
    }

    Move-Item -LiteralPath $RollbackRoot -Destination $FinalRoot
    Write-Log ("Restored fixed root from rollback root: {0}" -f $RollbackRoot)
}

function Restore-InstalledFixedRootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$FinalRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $failedParent = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestFailed_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $failedParent
    $failedRoot = Join-Path $failedParent ([System.IO.Path]::GetFileName($FinalRoot))

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    $script:FixedRootInstalled = $false
    if (Test-Path -LiteralPath $FinalRoot) {
        Move-Item -LiteralPath $FinalRoot -Destination $failedRoot
        $script:FailedLatestRoot = $failedRoot
        Write-Log ("Moved failed fixed-root install aside after {0}: {1}" -f $Reason, $failedRoot) 'WARN'
    }

    Restore-FixedRootBestEffort -FinalRoot $FinalRoot -RollbackRoot $RollbackRoot
    $script:FixedRootReplacementStarted = $false
    return $failedRoot
}

function Get-RootConfigName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $leaf = Split-Path -Path $Root -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Could not derive a root config name from [$Root]."
    }

    return $leaf
}

function Get-ConfigName {
    param(
        [Parameter(Mandatory = $true)][string]$RootConfigName,
        [Parameter(Mandatory = $true)][string]$RelativeConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($RelativeConfigPath)) {
        return $RootConfigName
    }

    return ($RootConfigName + '\' + $RelativeConfigPath.Trim('\'))
}

function Get-ZPosBootstrapSpec {
    [PSCustomObject]@{ RelativePath = 'Bootstrap'; FileName = 'ZPosBootstrap.ini' }
}

function Get-RetiredCurrentRootConfigSpecs {
    @(
        [PSCustomObject]@{ RelativePath = 'ExtraContent\Jukebox\Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'Activities\Jukebox\Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'Contents\Jukebox\Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'JukeboxMinimized' }
    )
}

function Get-RainmeterActiveConfigSet {
    $activeConfigs = @{}
    $configPath = Get-RainmeterConfigPath
    if ([string]::IsNullOrWhiteSpace($configPath) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-Log 'Rainmeter.ini was not available for retired active-config cleanup; skipping active-only cleanup.' 'WARN'
        return $activeConfigs
    }

    $currentSection = ''
    foreach ($rawLine in ((Read-TextSmart -Path $configPath) -split "`r?`n")) {
        $line = [string]$rawLine
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            continue
        }

        if ($currentSection -eq '' -or $trimmed.StartsWith(';')) {
            continue
        }

        if ($trimmed -match '^Active\s*=\s*1\s*$') {
            $activeConfigs[$currentSection] = $true
        }
    }

    return $activeConfigs
}

function Invoke-RetiredCurrentRootConfigCleanup {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootConfigName = Get-RootConfigName -Root $Root
    $activeConfigs = Get-RainmeterActiveConfigSet
    foreach ($spec in @(Get-RetiredCurrentRootConfigSpecs)) {
        $configName = Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath)
        if (-not $activeConfigs.ContainsKey($configName)) {
            Write-Log ("Retired config cleanup skipped inactive [{0}]" -f $configName)
            continue
        }

        try {
            Write-Log ("Deactivating retired config [{0}]" -f $configName)
            Invoke-RainmeterBang -Bang '!DeactivateConfig' -Arguments @($configName)
        }
        catch {
            Write-Log ("Retired config cleanup failed for [{0}]: {1}" -f $configName, $_.Exception.Message) 'WARN'
        }
    }
}

function Invoke-ActivateZPosBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $spec = Get-ZPosBootstrapSpec
    $rootConfigName = Get-RootConfigName -Root $Root
    if (-not (Test-ConfigFileExists -Root $Root -RelativePath ([string]$spec.RelativePath) -FileName ([string]$spec.FileName))) {
        throw ("Fixed-root update is missing the z-position bootstrap skin: {0}\{1}" -f $Root, [string]$spec.RelativePath)
    }

    $configName = Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath)
    Write-Log ("Activating z-position bootstrap [{0}] ({1})" -f $configName, [string]$spec.FileName)
    Invoke-RainmeterBang -Bang '!ActivateConfig' -Arguments @($configName, [string]$spec.FileName)
}

function Invoke-PostUpdateRefresh {
    param([Parameter(Mandatory = $true)][string]$Root)

    Write-Log 'Refreshing Rainmeter app and running z-position bootstrap after fixed-root update.'
    Invoke-RainmeterBang -Bang '!RefreshApp'
    Invoke-RainmeterBang -Bang '!RefreshGroup' -Arguments @('DMeloper')
    Invoke-ActivateZPosBootstrap -Root $Root
}

function Invoke-FixedRootReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$StagedRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot
    )

    $resolvedCurrentRoot = Resolve-FullPath -Path $CurrentRoot
    $resolvedStagedRoot = Resolve-FullPath -Path $StagedRoot
    $resolvedSkinsRoot = Resolve-FullPath -Path $SkinsRoot
    if (-not (Test-PathWithinRoot -Root $resolvedSkinsRoot -Path $resolvedCurrentRoot) -or
        [string]::Equals($resolvedCurrentRoot, $resolvedSkinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace a path outside the Rainmeter skins root: $resolvedCurrentRoot"
    }

    if ((Test-PathWithinRoot -Root $resolvedCurrentRoot -Path $resolvedStagedRoot) -or
        (Test-PathWithinRoot -Root $resolvedStagedRoot -Path $resolvedCurrentRoot)) {
        throw 'Fixed-root replacement requires separate current and staged roots.'
    }

    $rollbackParent = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestRollback_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $rollbackParent
    $rollbackRoot = Join-Path $rollbackParent ([System.IO.Path]::GetFileName($resolvedCurrentRoot))
    $script:ReplacementRollbackRoot = $rollbackRoot
    Write-Log ("ReplacementRollbackRoot: {0}" -f $rollbackRoot)

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    $script:FixedRootReplacementStarted = $true
    try {
        Move-Item -LiteralPath $resolvedCurrentRoot -Destination $rollbackRoot
        Write-Log ("Moved current fixed root to rollback root: {0}" -f $rollbackRoot)

        $stagedMovedToFinal = $false
        try {
            Move-Item -LiteralPath $resolvedStagedRoot -Destination $resolvedCurrentRoot
            $script:StageRootCreated = $false
            $stagedMovedToFinal = $true
            if (-not (Test-SkinRoot -Root $resolvedCurrentRoot)) {
                throw "Replacement root failed post-move skin-root validation: $resolvedCurrentRoot"
            }
            $script:FixedRootInstalled = $true
            Write-Log ("Installed staged latest root at fixed path: {0}" -f $resolvedCurrentRoot)
        }
        catch {
            $replaceFailure = $_.Exception.Message
            Write-Log ("Fixed-root replacement failed after rollback root was created: {0}" -f $replaceFailure) 'ERROR'
            try {
                if ($stagedMovedToFinal -and (Test-Path -LiteralPath $resolvedCurrentRoot)) {
                    Restore-InstalledFixedRootBestEffort -FinalRoot $resolvedCurrentRoot -RollbackRoot $rollbackRoot -Reason 'fixed-root replacement failure' | Out-Null
                }
                else {
                    Restore-FixedRootBestEffort -FinalRoot $resolvedCurrentRoot -RollbackRoot $rollbackRoot
                    $script:FixedRootReplacementStarted = $false
                }
            }
            catch {
                throw ("Fixed-root replacement failed and automatic restore also failed. replacement_error={0}; restore_error={1}" -f $replaceFailure, $_.Exception.Message)
            }

            throw ("Fixed-root replacement failed; restored the previous fixed root. {0}" -f $replaceFailure)
        }
    }
    catch {
        throw
    }

    return $rollbackRoot
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

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs')
    if (Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ValidateOnly') {
        $arguments += '-ValidateOnly'
    }
    else {
        throw 'ImportFromOldVersion.ps1 does not expose the required -ValidateOnly validation contract.'
    }

    $result = Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import validation'
    Assert-HelperOk -Result $result -Operation 'Legacy import validation'
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

function Invoke-VersionSwitch {
    param(
        [Parameter(Mandatory = $true)][string]$SwitchScript,
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SelectedRoot
    )

    $arguments = @('-CurrentTargetRoot', $CurrentRoot, '-SelectedTargetRoot', $SelectedRoot, '-EmitResultPairs')
    $result = Invoke-HelperScript -ScriptPath $SwitchScript -Arguments $arguments -Operation 'active version switch'
    Assert-HelperOk -Result $result -Operation 'Active version switch'
    $script:SwitchSucceeded = $true
}

function Resolve-SwitchScript {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SelectedRoot
    )

    $currentScript = Join-RootPath -Root $CurrentRoot -RelativePath 'tools\SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $currentScript -PathType Leaf) {
        return $currentScript
    }

    $selectedScript = Join-RootPath -Root $SelectedRoot -RelativePath 'tools\SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $selectedScript -PathType Leaf) {
        return $selectedScript
    }

    throw 'SwitchActiveSkinVersion.ps1 was not found in the selected or current root.'
}

function ConvertTo-EncodedCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
}

function Escape-SingleQuotedString {
    param([AllowNull()][string]$Value)

    return ([string]$Value).Replace("'", "''")
}

function Invoke-DetachedOldRootCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$OldRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [int]$CleanupTimeoutSeconds = 20,
        [int]$ResultTimeoutSeconds = 30
    )

    $cleanupRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestCleanup_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $cleanupRoot
    $runnerPath = Join-Path $cleanupRoot 'CleanupOldRoot.ps1'
    $resultPath = Join-Path $cleanupRoot 'CleanupResult.json'

    $runner = @'
param(
    [Parameter(Mandatory = $true)][string]$OldRoot,
    [Parameter(Mandatory = $true)][string]$SkinsRoot,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [int]$CleanupTimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
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

function Test-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Path)
    $rootFull = (Resolve-FullPath -Path $Root).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $Path -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Write-Result {
    param([Parameter(Mandatory = $true)][string]$Status, [Parameter(Mandatory = $true)][string]$Message)
    $parent = Split-Path -Parent $ResultPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $payload = [PSCustomObject]@{
        Status = $Status
        Message = $Message
        OldRoot = $OldRoot
        CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    }
    [System.IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 3), $utf8NoBom)
}

try {
    $resolvedOldRoot = Resolve-FullPath -Path $OldRoot -AllowMissing
    $resolvedSkinsRoot = Resolve-FullPath -Path $SkinsRoot
    if (-not (Test-PathWithinRoot -Root $resolvedSkinsRoot -Path $resolvedOldRoot) -or
        [string]::Equals($resolvedOldRoot, $resolvedSkinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a path outside the Rainmeter skins root: $resolvedOldRoot"
    }

    # Do not wait on the helper parent here: Version Manager waits for this helper's
    # result, so waiting on that UI process makes successful cleanup impossible.
    # The detached runner owns deletion from TEMP and reports a bounded result instead.
    Set-Location ([System.IO.Path]::GetTempPath())
    $deadline = [DateTime]::UtcNow.AddSeconds($CleanupTimeoutSeconds)
    $lastError = $null
    do {
        try {
            if (Test-Path -LiteralPath $resolvedOldRoot) {
                Remove-Item -LiteralPath $resolvedOldRoot -Force -Recurse
            }
            Write-Result -Status 'OK' -Message 'Old root deleted.'
            exit 0
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 250
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)

    Write-Result -Status 'TIMEOUT' -Message ("Old-root cleanup did not finish within {0} seconds. Last error: {1}" -f $CleanupTimeoutSeconds, $lastError)
}
catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
}
'@

    [System.IO.File]::WriteAllText($runnerPath, $runner, $script:Utf8NoBom)

    $command = "& '{0}' -OldRoot '{1}' -SkinsRoot '{2}' -ResultPath '{3}' -CleanupTimeoutSeconds {4}" -f `
        (Escape-SingleQuotedString -Value $runnerPath),
        (Escape-SingleQuotedString -Value $OldRoot),
        (Escape-SingleQuotedString -Value $SkinsRoot),
        (Escape-SingleQuotedString -Value $resultPath),
        $CleanupTimeoutSeconds
    $encoded = ConvertTo-EncodedCommand -Command $command
    Start-Process -FilePath powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -WindowStyle Hidden | Out-Null

    $deadline = [DateTime]::UtcNow.AddSeconds($ResultTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            return [PSCustomObject]@{
                Status = [string]$result.Status
                Message = [string]$result.Message
                ResultPath = $resultPath
            }
        }
        Start-Sleep -Milliseconds 250
    }

    return [PSCustomObject]@{
        Status = 'TIMEOUT'
        Message = "Old-root cleanup did not report a result within $ResultTimeoutSeconds seconds."
        ResultPath = $resultPath
    }
}

function Invoke-DetachedTempRootCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason,
        [int]$CleanupTimeoutSeconds = 20,
        [int]$ResultTimeoutSeconds = 30
    )

    $resolvedRoot = Resolve-FullPath -Path $Root
    $tempRoot = Resolve-FullPath -Path ([System.IO.Path]::GetTempPath())
    if (-not (Test-PathWithinRoot -Root $tempRoot -Path $resolvedRoot) -or
        [string]::Equals($resolvedRoot, $tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing detached cleanup outside TEMP for $($Reason): $resolvedRoot"
    }

    $cleanupRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestCleanup_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $cleanupRoot
    $runnerPath = Join-Path $cleanupRoot 'CleanupTempRoot.ps1'
    $resultPath = Join-Path $cleanupRoot 'CleanupResult.json'

    $runner = @'
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TempRoot,
    [Parameter(Mandatory = $true)][string]$Reason,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [int]$CleanupTimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
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

function Test-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$ParentRoot, [Parameter(Mandatory = $true)][string]$ChildPath)
    $rootFull = (Resolve-FullPath -Path $ParentRoot).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $ChildPath -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Write-Result {
    param([Parameter(Mandatory = $true)][string]$Status, [Parameter(Mandatory = $true)][string]$Message)
    $parent = Split-Path -Parent $ResultPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $payload = [PSCustomObject]@{
        Status = $Status
        Message = $Message
        Root = $Root
        Reason = $Reason
        CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    }
    [System.IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 3), $utf8NoBom)
}

try {
    $resolvedRoot = Resolve-FullPath -Path $Root -AllowMissing
    $resolvedTempRoot = Resolve-FullPath -Path $TempRoot
    if (-not (Test-PathWithinRoot -ParentRoot $resolvedTempRoot -ChildPath $resolvedRoot) -or
        [string]::Equals($resolvedRoot, $resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a path outside TEMP: $resolvedRoot"
    }

    Set-Location ([System.IO.Path]::GetTempPath())
    $deadline = [DateTime]::UtcNow.AddSeconds($CleanupTimeoutSeconds)
    $lastError = $null
    do {
        try {
            if (Test-Path -LiteralPath $resolvedRoot) {
                Remove-Item -LiteralPath $resolvedRoot -Force -Recurse
            }
            Write-Result -Status 'OK' -Message 'Temporary old root deleted.'
            exit 0
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 250
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)

    Write-Result -Status 'TIMEOUT' -Message ("Temporary old-root cleanup did not finish within {0} seconds. Last error: {1}" -f $CleanupTimeoutSeconds, $lastError)
}
catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
}
'@

    [System.IO.File]::WriteAllText($runnerPath, $runner, $script:Utf8NoBom)

    $command = "& '{0}' -Root '{1}' -TempRoot '{2}' -Reason '{3}' -ResultPath '{4}' -CleanupTimeoutSeconds {5}" -f `
        (Escape-SingleQuotedString -Value $runnerPath),
        (Escape-SingleQuotedString -Value $resolvedRoot),
        (Escape-SingleQuotedString -Value $tempRoot),
        (Escape-SingleQuotedString -Value $Reason),
        (Escape-SingleQuotedString -Value $resultPath),
        $CleanupTimeoutSeconds
    $encoded = ConvertTo-EncodedCommand -Command $command
    Start-Process -FilePath powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -WindowStyle Hidden | Out-Null

    $deadline = [DateTime]::UtcNow.AddSeconds($ResultTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            return [PSCustomObject]@{
                Status = [string]$result.Status
                Message = [string]$result.Message
                ResultPath = $resultPath
            }
        }
        Start-Sleep -Milliseconds 250
    }

    return [PSCustomObject]@{
        Status = 'TIMEOUT'
        Message = "Temporary old-root cleanup did not report a result within $ResultTimeoutSeconds seconds."
        ResultPath = $resultPath
    }
}

function Invoke-UpdateToLatest {
    $resolvedCurrentRoot = Resolve-SkinRootCandidate -Candidate $CurrentTargetRoot
    if (-not $resolvedCurrentRoot) {
        throw 'CurrentTargetRoot is not a valid Block HUD install root.'
    }
    $script:ResolvedCurrentRoot = $resolvedCurrentRoot
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedCurrentRoot
    Use-CanonicalHelperLogPath -Root $resolvedCurrentRoot -Prefix 'UpdateToLatestVersion'

    $resolvedPackagePath = Resolve-FullPath -Path $PackagePath
    if (-not (Test-Path -LiteralPath $resolvedPackagePath -PathType Leaf)) {
        throw 'PackagePath was not found.'
    }
    $packageExtension = [System.IO.Path]::GetExtension($resolvedPackagePath)
    if (-not [string]::Equals($packageExtension, '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'PackagePath must be a ZIP update package. RMSKIN installers are not supported by the updater.'
    }

    $skinsRoot = Get-RainmeterSkinsRoot -CurrentRoot $resolvedCurrentRoot
    if (-not (Test-Path -LiteralPath $skinsRoot -PathType Container)) {
        throw "Rainmeter skins root does not exist: $skinsRoot"
    }
    if (-not (Test-PathWithinRoot -Root $skinsRoot -Path $resolvedCurrentRoot) -or
        [string]::Equals($resolvedCurrentRoot, $skinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "CurrentTargetRoot must be an installed skin root under Rainmeter SkinPath. current=$resolvedCurrentRoot skinPath=$skinsRoot"
    }

    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestExtract_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $extractRoot
    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $extractRoot -Force
    $packageRoot = Resolve-PackageRoot -ExtractRoot $extractRoot

    $currentMetadata = Get-SkinMetadata -Root $resolvedCurrentRoot
    $packageMetadata = Get-SkinMetadata -Root $packageRoot
    $currentReleaseVariant = Get-SkinRootReleaseVariant -Root $resolvedCurrentRoot
    Assert-ExpectedReleaseVariant -ActualReleaseVariant $currentReleaseVariant -ExpectedReleaseVariant $ExpectedReleaseVariant -Context 'CurrentTargetRoot'
    $effectiveExpectedReleaseVariant = if ([string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        $currentReleaseVariant
    }
    else {
        Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ExpectedReleaseVariant -LanguageCode '' -AssetPattern ''
    }
    $packageReleaseVariant = Get-SkinRootReleaseVariant -Root $packageRoot
    Assert-ExpectedReleaseVariant -ActualReleaseVariant $packageReleaseVariant -ExpectedReleaseVariant $effectiveExpectedReleaseVariant -Context 'Package'
    $currentVersion = ConvertTo-SkinVersion -VersionText ([string]$currentMetadata.Version) -Context 'CurrentTargetRoot'
    $packageVersion = ConvertTo-SkinVersion -VersionText ([string]$packageMetadata.Version) -Context 'Package'
    if ($packageVersion -le $currentVersion) {
        throw "Package version must be newer than current target version. current=$($currentMetadata.Version) package=$($packageMetadata.Version)"
    }

    $identityName = Get-PackageIdentityName -PackageRoot $packageRoot -PackageMetadata $packageMetadata -ExtractRoot $extractRoot
    $fixedRootName = "DMeloper's Block HUD"
    if (-not [string]::Equals($identityName, $fixedRootName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package identity must resolve to the fixed installed root '$fixedRootName', but was '$identityName'."
    }
    $latestRoot = Resolve-LatestDestinationRoot -SkinsRoot $skinsRoot -IdentityName $identityName
    $script:ResolvedLatestRoot = $latestRoot

    Write-Log ("CurrentTargetRoot: {0}" -f $resolvedCurrentRoot)
    Write-Log ("PackagePath: {0}" -f $resolvedPackagePath)
    Write-Log ("PackageRoot: {0}" -f $packageRoot)
    Write-Log ("CurrentVersion: {0}" -f [string]$currentMetadata.Version)
    Write-Log ("LatestVersion: {0}" -f [string]$packageMetadata.Version)
    Write-Log ("CurrentReleaseVariant: {0}" -f $currentReleaseVariant)
    Write-Log ("PackageReleaseVariant: {0}" -f $packageReleaseVariant)
    Write-Log ("ExpectedReleaseVariant: {0}" -f $effectiveExpectedReleaseVariant)
    Write-Log ("PackageIdentity: {0}" -f $identityName)
    Write-Log ("DestinationRoot: {0}" -f $latestRoot)
    Write-Log 'DestinationRoot policy: fixed package identity root; version-suffixed side-by-side update roots are disabled.'

    if (-not (Test-PathWithinRoot -Root $skinsRoot -Path $latestRoot)) {
        throw "Destination root is outside the Rainmeter skins root: $latestRoot"
    }

    if (Test-Path -LiteralPath $latestRoot) {
        if (-not [string]::Equals((Resolve-FullPath -Path $latestRoot), $resolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Destination install root already exists and is not the current root: $latestRoot"
        }
    }

    $packageImportScript = Join-RootPath -Root $packageRoot -RelativePath 'tools\ImportFromOldVersion.ps1'
    if (-not (Test-Path -LiteralPath $packageImportScript -PathType Leaf)) {
        throw 'Package is missing tools\ImportFromOldVersion.ps1.'
    }
    Invoke-ImportValidation -ImportScript $packageImportScript -TargetRoot $packageRoot -SourceRoot $resolvedCurrentRoot

    if (Test-Path -LiteralPath $latestRoot) {
        Write-Log 'Fixed-root update path: destination resolves to the current active root; staging latest package before replacement.'

        $stageRoot = New-StagedLatestRoot -PackageRoot $packageRoot -IdentityName $identityName
        $stageImportScript = Join-RootPath -Root $stageRoot -RelativePath 'tools\ImportFromOldVersion.ps1'
        if (-not (Test-Path -LiteralPath $stageImportScript -PathType Leaf)) {
            throw 'Staged latest root is missing tools\ImportFromOldVersion.ps1.'
        }

        Invoke-RealImport -ImportScript $stageImportScript -TargetRoot $stageRoot -SourceRoot $resolvedCurrentRoot

        Invoke-RetiredCurrentRootConfigCleanup -Root $resolvedCurrentRoot
        $rollbackRoot = Invoke-FixedRootReplacement -CurrentRoot $resolvedCurrentRoot -StagedRoot $stageRoot -SkinsRoot $skinsRoot
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedCurrentRoot
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Use-CanonicalHelperLogPath -Root $resolvedCurrentRoot -Prefix 'UpdateToLatestVersion'

        try {
            Invoke-PostUpdateRefresh -Root $resolvedCurrentRoot
        }
        catch {
            $refreshFailure = $_.Exception.Message
            Write-Log ("Post-update refresh failed after fixed-root replacement: {0}" -f $refreshFailure) 'ERROR'
            try {
                Restore-InstalledFixedRootBestEffort -FinalRoot $resolvedCurrentRoot -RollbackRoot $rollbackRoot -Reason 'post-update refresh failure'
            }
            catch {
                throw ("Post-update refresh failed and automatic fixed-root restore also failed. refresh_error={0}; restore_error={1}" -f $refreshFailure, $_.Exception.Message)
            }

            throw ("Post-update refresh failed; restored the previous fixed root. {0}" -f $refreshFailure)
        }

        $cleanupResult = Invoke-DetachedTempRootCleanup -Root $rollbackRoot -Reason 'successful fixed-root update'
        if ([string]::Equals([string]$cleanupResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Updated to the latest version, imported data, and replaced the fixed install root.'
        }
        else {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ("Updated to the latest version and replaced the fixed install root, but temporary rollback-root cleanup did not complete: {0}" -f [string]$cleanupResult.Message)
        }

        return
    }

    try {
        Copy-PackageToDestination -PackageRoot $packageRoot -DestinationRoot $latestRoot
        $script:LatestRootCreated = $true
        Use-CanonicalHelperLogPath -Root $latestRoot -Prefix 'UpdateToLatestVersion'

        $latestImportScript = Join-RootPath -Root $latestRoot -RelativePath 'tools\ImportFromOldVersion.ps1'
        if (-not (Test-Path -LiteralPath $latestImportScript -PathType Leaf)) {
            throw 'Installed latest root is missing tools\ImportFromOldVersion.ps1.'
        }
        Invoke-RealImport -ImportScript $latestImportScript -TargetRoot $latestRoot -SourceRoot $resolvedCurrentRoot

        $switchScript = Resolve-SwitchScript -CurrentRoot $resolvedCurrentRoot -SelectedRoot $latestRoot
        Invoke-VersionSwitch -SwitchScript $switchScript -CurrentRoot $resolvedCurrentRoot -SelectedRoot $latestRoot
    }
    catch {
        $failureMessage = $_.Exception.Message
        if ($script:LatestRootCreated -and -not $script:SwitchSucceeded) {
            Remove-RootBestEffort -Root $latestRoot -Reason 'failed latest update'
        }
        throw $failureMessage
    }

    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $latestRoot
    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    try {
        $cleanupResult = Invoke-DetachedOldRootCleanup -OldRoot $resolvedCurrentRoot -SkinsRoot $skinsRoot
    }
    catch {
        $cleanupResult = [PSCustomObject]@{
            Status = 'ERROR'
            Message = $_.Exception.Message
            ResultPath = ''
        }
    }
    Write-Log ("Old-root cleanup result: {0} - {1}" -f [string]$cleanupResult.Status, [string]$cleanupResult.Message)
    if ([string]::Equals([string]$cleanupResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Updated to the latest version, imported data, switched active configs, and deleted the old root.'
    }
    else {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ("Updated to the latest version and switched active configs, but old-root cleanup did not complete: {0}" -f [string]$cleanupResult.Message)
    }
}

try {
    Invoke-UpdateToLatest
}
catch {
    if ($script:FixedRootReplacementStarted -and -not $script:FixedRootInstalled -and
        -not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot) -and
        -not [string]::IsNullOrWhiteSpace($script:ReplacementRollbackRoot)) {
        try {
            if (-not (Test-Path -LiteralPath $script:ResolvedCurrentRoot) -and
                (Test-Path -LiteralPath $script:ReplacementRollbackRoot -PathType Container)) {
                Restore-FixedRootBestEffort -FinalRoot $script:ResolvedCurrentRoot -RollbackRoot $script:ReplacementRollbackRoot
            }
        }
        catch {
            Write-Log ("Fixed-root restore attempt failed in outer catch: {0}" -f $_.Exception.Message) 'ERROR'
        }
    }

    if ($script:LatestRootCreated -and -not $script:SwitchSucceeded -and -not [string]::IsNullOrWhiteSpace($script:ResolvedLatestRoot)) {
        Remove-RootBestEffort -Root $script:ResolvedLatestRoot -Reason 'error rollback'
    }
    if ($script:StageRootCreated -and -not $script:ImportStarted -and -not [string]::IsNullOrWhiteSpace($script:ResolvedStageRoot)) {
        Remove-RootBestEffort -Root $script:ResolvedStageRoot -Reason 'error rollback'
    }
    elseif ($script:StageRootCreated -and $script:ImportStarted -and -not [string]::IsNullOrWhiteSpace($script:ResolvedStageRoot)) {
        Remove-RootBestEffort -Root $script:ResolvedStageRoot -Reason 'failed import or replacement'
        if (Test-Path -LiteralPath $script:ResolvedStageRoot -PathType Container) {
            Write-Log ("Preserved staged root after failed cleanup for diagnostics: {0}" -f $script:ResolvedStageRoot) 'WARN'
        }
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot)) {
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $script:ResolvedCurrentRoot
        if (-not $script:SwitchSucceeded) {
            Use-CanonicalHelperLogPath -Root $script:ResolvedCurrentRoot -Prefix 'UpdateToLatestVersion'
        }
    }
    if (-not $script:ImportStarted) {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    }
    else {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    }
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
}
finally {
    Save-Log
    Emit-ResultPairs
}
