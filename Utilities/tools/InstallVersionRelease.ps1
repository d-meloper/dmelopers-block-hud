[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [string]$PackagePath,
    [string]$PackageUrl,
    [string]$ExpectedPackageSha256 = '',
    [string]$ExpectedVersion,
    [string]$ExpectedReleaseVariant,
    [string]$SelectedTargetRoot,
    [ValidateRange(5, 3600)][int]$PackageDownloadTimeoutSeconds = 1800,
    [ValidateRange(0, 5)][int]$PackageDownloadRetryCount = 2,
    [switch]$AllowCompatibilityWarning,
    [string]$ExpectedRepairPlanId = '',
    [string]$LatestUpdateLaunchToken = '',
    [string]$ProgressOwnerRoot = '',
    [string]$ProgressToken = '',
    [switch]$NonInteractive,
    [switch]$EmitResultPairs,
    [switch]$PassThruResultObject
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
    $OutputEncoding = $script:Utf8NoBom
}
catch {
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.ReleaseIdentity.ps1')
. (Join-Path $PSScriptRoot 'LatestUpdate.Common.ps1')

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
$script:ExtractRoot = ''
$script:CancellationObserved = $false
$script:CancellationRollbackFailed = $false
$script:CancellationRollbackMessage = ''
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
    DMEL_COMPATIBILITY = ''
    DMEL_REPAIRCOUNT = '0'
    DMEL_REPAIRSUMMARY = ''
    DMEL_REPAIRPLANID = ''
}

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Fallback = ''
    )

    Get-LocalizedText -Table $script:LocTable -Key $Key -Fallback $Fallback
}

function Test-LatestUpdateInstallCancellationRequested {
    if ([string]::IsNullOrWhiteSpace($LatestUpdateLaunchToken) -or
        [string]::IsNullOrWhiteSpace($ProgressOwnerRoot)) {
        return $false
    }
    return [string]::Equals(
        (Read-LatestUpdateCancellation -Root $ProgressOwnerRoot -LaunchToken $LatestUpdateLaunchToken),
        'cancel',
        [System.StringComparison]::Ordinal)
}

function Assert-LatestUpdateInstallNotCancelled {
    if (-not (Test-LatestUpdateInstallCancellationRequested)) { return }
    $script:CancellationObserved = $true
    throw (New-Object System.OperationCanceledException 'Latest update was canceled by the user.')
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
    if ($resolved -eq (T 'Helper_VersionManager_Update_InstalledImportHelperMissing' 'The installed root is missing Utilities\tools\ImportFromOldVersion.ps1.')) {
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

    $settingsPath = Get-BlockHudSettingsIniPath -Root $Root
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

    return (Test-BlockHudSkinRoot -Root $Root)
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

    $transportPath = Join-Path $PSScriptRoot 'InstallVersionRelease.PackageTransport.ps1'
    if (-not (Test-Path -LiteralPath $transportPath -PathType Leaf)) {
        throw "PackageUrl transport module was not found: $transportPath"
    }
    . $transportPath
    return (Resolve-DownloadedInstallReleasePackagePath `
        -CurrentRoot $CurrentRoot `
        -Url $PackageUrl `
        -TimeoutSeconds $PackageDownloadTimeoutSeconds `
        -RetryCount $PackageDownloadRetryCount `
        -LogStamp $script:LogStamp)
}

function Get-ReleasePackageIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = New-Object byte[] (1024 * 1024)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            Assert-LatestUpdateInstallNotCancelled
            [void]$sha256.TransformBlock($buffer, 0, $read, $buffer, 0)
        }
        [void]$sha256.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return (($sha256.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Invoke-CancelablePowerShellCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Parameters,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Assert-LatestUpdateInstallNotCancelled
    $pipeline = [PowerShell]::Create()
    $asyncResult = $null
    try {
        [void]$pipeline.AddCommand($Command)
        foreach ($entry in $Parameters.GetEnumerator()) {
            if ($entry.Value -is [bool] -and [bool]$entry.Value) {
                [void]$pipeline.AddParameter([string]$entry.Key)
            }
            else {
                [void]$pipeline.AddParameter([string]$entry.Key, $entry.Value)
            }
        }
        $asyncResult = $pipeline.BeginInvoke()
        while (-not $asyncResult.IsCompleted) {
            Assert-LatestUpdateInstallNotCancelled
            Start-Sleep -Milliseconds 100
        }
        [void]$pipeline.EndInvoke($asyncResult)
        if ($pipeline.HadErrors) {
            $detail = @($pipeline.Streams.Error | ForEach-Object { [string]$_ }) -join ' | '
            throw ("{0} failed: {1}" -f $Operation, $detail)
        }
    }
    finally {
        if ($null -ne $asyncResult -and -not $asyncResult.IsCompleted) {
            try { $pipeline.Stop() } catch { }
        }
        $pipeline.Dispose()
    }
}

function Resolve-ExpectedPackageSha256 {
    $required = -not [string]::IsNullOrWhiteSpace($PackageUrl) -or
        -not [string]::IsNullOrWhiteSpace($LatestUpdateLaunchToken)
    if ([string]::IsNullOrWhiteSpace($ExpectedPackageSha256)) {
        if ($required) {
            throw 'ExpectedPackageSha256 is required for a downloaded or latest-update release package.'
        }
        return ''
    }

    $normalized = $ExpectedPackageSha256.Trim().ToUpperInvariant()
    if ($normalized -notmatch '^[0-9A-F]{64}$') {
        throw 'ExpectedPackageSha256 must be a 64-character hexadecimal SHA-256 value.'
    }
    return $normalized
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
    Invoke-CancelablePowerShellCommand `
        -Command 'Copy-Item' `
        -Parameters ([ordered]@{
            LiteralPath = $PackageRoot
            Destination = $DestinationRoot
            Recurse = $true
            Force = $true
            ErrorAction = 'Stop'
        }) `
        -Operation 'release package copy'
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

function Remove-RootStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return
    }
    Write-Log ("Removing destination root after {0}: {1}" -f $Reason, $Root) 'WARN'
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $Root) {
        throw "Destination rollback did not remove the root: $Root"
    }
}

function Write-MousePluginUpdateCancellationMarker {
    param([Parameter(Mandatory = $true)][string]$DestinationRoot)

    $dataRoot = Join-Path $DestinationRoot '@Resources\Customs\Data'
    $pendingPath = Join-Path $dataRoot 'MousePluginUpdatePending.json'
    if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
        return
    }
    $markerPath = Join-Path $dataRoot 'MousePluginUpdateCancelled.inc'
    $temporaryPath = $markerPath + '.' + $PID + '.tmp'
    try {
        [System.IO.File]::WriteAllText($temporaryPath, "[Variables]`r`nCancelled=1`r`n", [System.Text.Encoding]::Unicode)
        Move-Item -LiteralPath $temporaryPath -Destination $markerPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    $markerBytes = [System.IO.File]::ReadAllBytes($markerPath)
    if ($markerBytes.Length -lt 2 -or $markerBytes[0] -ne 0xFF -or $markerBytes[1] -ne 0xFE -or
        -not ([System.Text.Encoding]::Unicode.GetString($markerBytes, 2, $markerBytes.Length - 2) -match '(?m)^Cancelled=1\s*$')) {
        throw 'Mouse plugin cancellation marker was not committed with the expected UTF-16 state.'
    }
    Write-Log ("Mouse plugin handoff canceled before reverse switch: {0}" -f $markerPath) 'WARN'
}

function Remove-ExtractRootBestEffort {
    if ([string]::IsNullOrWhiteSpace($script:ExtractRoot)) {
        return
    }

    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $resolvedExtractRoot = [System.IO.Path]::GetFullPath($script:ExtractRoot).TrimEnd('\', '/')
    $leaf = Split-Path -Leaf $resolvedExtractRoot
    if (-not $resolvedExtractRoot.StartsWith($resolvedTempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $leaf.StartsWith('DMeloperReleaseExtract_', [System.StringComparison]::Ordinal)) {
        Write-Log ("Refusing unexpected extraction cleanup path: {0}" -f $resolvedExtractRoot) 'WARN'
        return
    }

    if (Test-Path -LiteralPath $resolvedExtractRoot -PathType Container) {
        try {
            Remove-Item -LiteralPath $resolvedExtractRoot -Recurse -Force -ErrorAction Stop
            Write-Log ("Removed temporary release extraction root: {0}" -f $resolvedExtractRoot)
        }
        catch {
            Write-Log ("Best-effort extraction cleanup failed for {0}: {1}" -f $resolvedExtractRoot, $_.Exception.Message) 'WARN'
        }
    }
    $script:ExtractRoot = ''
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
        Remove-RootStrict -Root $DestinationRoot -Reason $Reason
    }
    Move-Item -LiteralPath $script:DestinationReplacementBackupRoot -Destination $DestinationRoot -Force -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container) -or
        (Test-Path -LiteralPath $script:DestinationReplacementBackupRoot)) {
        throw "Previous destination rollback could not be verified: $DestinationRoot"
    }
    $script:DestinationReplacementBackupRoot = ''
    $script:DestinationCreated = $false
}

function Undo-DestinationInstallAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ($script:SwitchSucceeded) {
        Write-Log ("Preserving destination because it may still be the active root: {0}" -f $DestinationRoot) 'ERROR'
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($script:DestinationReplacementBackupRoot)) {
        Restore-DestinationReplacement -DestinationRoot $DestinationRoot -Reason $Reason
        return
    }

    if ($script:DestinationCreated -and -not $script:SwitchSucceeded) {
        Remove-RootStrict -Root $DestinationRoot -Reason $Reason
        $script:DestinationCreated = $false
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

function Get-InstallRuntimePowerShellPath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($candidate)
    }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [System.IO.Path]::GetFullPath($command.Source)
    }

    throw 'powershell.exe could not be located.'
}

function Invoke-HelperScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation,
        [switch]$DeferCancellation
    )

    if (-not $DeferCancellation) {
        Assert-LatestUpdateInstallNotCancelled
    }
    Write-Log ("Starting {0}: {1}" -f $Operation, $ScriptPath)
    $output = @()
    $exitCode = $null
    $pairs = @{}
    if (Test-ScriptSupportsParameter -ScriptPath $ScriptPath -ParameterName 'PassThruResultObject') {
        $parameterMap = [ordered]@{}
        for ($index = 0; $index -lt $Arguments.Count; $index++) {
            $token = [string]$Arguments[$index]
            if (-not $token.StartsWith('-', [System.StringComparison]::Ordinal) -or $token.Length -lt 2) {
                throw ("Unsupported positional helper argument for {0}: {1}" -f $Operation, $token)
            }
            $name = $token.Substring(1)
            $value = $true
            if (($index + 1) -lt $Arguments.Count -and -not ([string]$Arguments[$index + 1]).StartsWith('-', [System.StringComparison]::Ordinal)) {
                $index += 1
                $value = [string]$Arguments[$index]
            }
            $parameterMap[$name] = $value
        }
        $parameterMap['PassThruResultObject'] = $true

        $pipeline = [PowerShell]::Create()
        $asyncResult = $null
        try {
            [void]$pipeline.AddCommand($ScriptPath)
            foreach ($entry in $parameterMap.GetEnumerator()) {
                if ($entry.Value -is [bool] -and [bool]$entry.Value) {
                    [void]$pipeline.AddParameter([string]$entry.Key)
                }
                else {
                    [void]$pipeline.AddParameter([string]$entry.Key, $entry.Value)
                }
            }
            $asyncResult = $pipeline.BeginInvoke()
            while (-not $asyncResult.IsCompleted) {
                if (-not $DeferCancellation) {
                    Assert-LatestUpdateInstallNotCancelled
                }
                Start-Sleep -Milliseconds 100
            }
            $output = @($pipeline.EndInvoke($asyncResult))
            $resultObject = @($output | Where-Object { $null -ne $_.PSObject.Properties['DMEL_STATUS'] } | Select-Object -Last 1)
            if ($resultObject.Count -gt 0) {
                foreach ($property in $resultObject[0].PSObject.Properties) {
                    if ([string]$property.Name -match '^DMEL_[A-Z]+$') {
                        $pairs[[string]$property.Name] = [string]$property.Value
                    }
                }
            }
            if ($pipeline.HadErrors) {
                $output += @($pipeline.Streams.Error | ForEach-Object { [string]$_ })
            }
            $exitCode = if ($pipeline.HadErrors) { 1 } else { 0 }
        }
        finally {
            if ($null -ne $asyncResult -and -not $asyncResult.IsCompleted) {
                try { $pipeline.Stop() } catch { }
            }
            $pipeline.Dispose()
        }
    }
    else {
        Write-Log ("{0} uses the legacy external-process compatibility path." -f $Operation) 'WARN'
        $output = @(& (Get-InstallRuntimePowerShellPath) -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
        Assert-LatestUpdateInstallNotCancelled
        $exitCode = $LASTEXITCODE
        $pairs = Convert-OutputToResultPairs -Output $output
    }
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
        Compatibility = [string]($pairs['DMEL_COMPATIBILITY'])
        RepairCount = [string]($pairs['DMEL_REPAIRCOUNT'])
        RepairSummary = [string]($pairs['DMEL_REPAIRSUMMARY'])
        RepairPlanId = [string]($pairs['DMEL_REPAIRPLANID'])
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

function Copy-CompatibilityResultPairs {
    param([Parameter(Mandatory = $true)]$Result)

    $repairCount = ([string]$Result.RepairCount).Trim()
    if ([string]::IsNullOrWhiteSpace($repairCount)) {
        $repairCount = '0'
    }
    Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value ([string]$Result.Compatibility).Trim().ToUpperInvariant()
    Set-ResultPairValue -Key 'DMEL_REPAIRCOUNT' -Value $repairCount
    Set-ResultPairValue -Key 'DMEL_REPAIRSUMMARY' -Value ([string]$Result.RepairSummary)
    Set-ResultPairValue -Key 'DMEL_REPAIRPLANID' -Value ([string]$Result.RepairPlanId)
}

function Get-ValidatedCompatibilityStatus {
    param([Parameter(Mandatory = $true)]$Result)

    $compatibility = ([string]$Result.Compatibility).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($compatibility)) {
        if ($Result.ExitCode -eq 0 -and [string]::Equals([string]$Result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'OK'
        }
        return 'FATAL'
    }
    if ($compatibility -notin @('OK', 'REPAIRABLE', 'FATAL')) {
        throw ("Legacy import validation emitted unsupported DMEL_COMPATIBILITY '{0}'." -f $compatibility)
    }
    return $compatibility
}

function Set-CompatibilityPreflightResult {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('WARN', 'ERROR')][string]$Status,
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)]$ValidationResult
    )

    $validationDetail = Convert-ResultPairValueToSingleLine -Value ([string]$ValidationResult.Message)
    if ([string]::IsNullOrWhiteSpace($validationDetail)) {
        $validationDetail = Convert-ResultPairValueToSingleLine -Value ([string]$ValidationResult.RepairSummary)
    }
    if ([string]::IsNullOrWhiteSpace($validationDetail)) {
        $validationDetail = T 'Helper_VersionManager_Update_HelperLogHint' 'See the helper log for details.'
    }
    elseif ($validationDetail.Length -gt 480) {
        $validationDetail = $validationDetail.Substring(0, 480).Trim() + '...'
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value $Status
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $CurrentRoot
    Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    if ([string]::Equals($Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase)) {
        $repairCount = Convert-ResultPairValueToSingleLine -Value ([string]$ValidationResult.RepairCount)
        $repairSummary = Convert-ResultPairValueToSingleLine -Value ([string]$ValidationResult.RepairSummary)
        if ([string]::IsNullOrWhiteSpace($repairSummary)) {
            $repairSummary = $validationDetail
        }
        elseif ($repairSummary.Length -gt 480) {
            $repairSummary = $repairSummary.Substring(0, 480).Trim() + '...'
        }
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (TF 'Helper_VersionManager_Update_CompatibilityRepairWarning' @($repairCount, $repairSummary) 'Some item image references cannot be imported. Only those image fields will be cleared; all other current data will be imported. Repair count: %1. %2')
    }
    else {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (TF 'Helper_VersionManager_Update_CompatibilityFatal' @($validationDetail) 'Current data cannot be imported safely, so installation was not started. %1')
    }
}

function Invoke-ImportValidation {
    param(
        [Parameter(Mandatory = $true)][string]$ImportScript,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$PackageIdentity
    )

    if (-not (Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ValidateOnly')) {
        throw 'ImportFromOldVersion.ps1 does not expose the required -ValidateOnly validation contract.'
    }

    $supportsRepair = Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'AllowItemImageRepair'
    $supportsPackageIdentity = Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'PackageIdentity'
    if ($supportsRepair -xor $supportsPackageIdentity) {
        throw 'ImportFromOldVersion.ps1 exposes an incomplete compatibility-repair validation contract.'
    }

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs', '-ValidateOnly')
    if ($supportsRepair) {
        $arguments += @('-AllowItemImageRepair', '-PackageIdentity', $PackageIdentity)
    }
    else {
        Write-Log 'Package import helper uses the legacy strict compatibility validation contract.' 'WARN'
    }
    return (Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import validation')
}

function Invoke-RealImport {
    param(
        [Parameter(Mandatory = $true)][string]$ImportScript,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$PackageIdentity,
        [string]$RepairPlanId = '',
        [string]$ImportProgressOwnerRoot = '',
        [string]$ImportProgressToken = ''
    )

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs')
    $supportsPackageIdentity = Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'PackageIdentity'
    if ($supportsPackageIdentity) {
        $arguments += @('-PackageIdentity', $PackageIdentity)
    }
    if (-not [string]::IsNullOrWhiteSpace($RepairPlanId)) {
        if (-not (Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'AllowItemImageRepair') -or
            -not (Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ExpectedRepairPlanId') -or
            -not $supportsPackageIdentity) {
            throw 'ImportFromOldVersion.ps1 does not expose the required item-image repair execution contract.'
        }
        $arguments += @('-AllowItemImageRepair', '-ExpectedRepairPlanId', $RepairPlanId)
    }
    $progressRequested = (-not [string]::IsNullOrWhiteSpace($ImportProgressOwnerRoot) -or
        -not [string]::IsNullOrWhiteSpace($ImportProgressToken))
    if ($progressRequested -and ([string]::IsNullOrWhiteSpace($ImportProgressOwnerRoot) -or
        [string]::IsNullOrWhiteSpace($ImportProgressToken))) {
        throw 'ProgressOwnerRoot and ProgressToken must be supplied together.'
    }
    if ($progressRequested) {
        $supportsProgressOwner = Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ProgressOwnerRoot'
        $supportsProgressToken = Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ProgressToken'
        if ($supportsProgressOwner -and $supportsProgressToken) {
            $arguments += @('-ProgressOwnerRoot', $ImportProgressOwnerRoot, '-ProgressToken', $ImportProgressToken)
        }
        elseif ($supportsProgressOwner -xor $supportsProgressToken) {
            Write-Log 'Installed import helper exposes an incomplete progress contract; using the legacy non-determinate UI.' 'WARN'
        }
        else {
            Write-Log 'Installed import helper does not expose the optional progress contract; using the legacy non-determinate UI.' 'WARN'
        }
    }
    $script:ImportStarted = $true
    $result = Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import'
    Assert-HelperOk -Result $result -Operation 'Legacy import'
    if (-not [string]::IsNullOrWhiteSpace($RepairPlanId)) {
        if (-not [string]::Equals([string]$result.Compatibility, 'REPAIRABLE', [System.StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals(([string]$result.RepairPlanId).Trim(), $RepairPlanId.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Legacy import completed without confirming the approved item-image repair plan.'
        }
    }
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

    $currentScript = Get-BlockHudRuntimeToolPath -Root $CurrentRoot -RelativeToolPath 'SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $currentScript -PathType Leaf) {
        return $currentScript
    }

    $preferredScript = Get-BlockHudRuntimeToolPath -Root $PreferredRoot -RelativeToolPath 'SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $preferredScript -PathType Leaf) {
        return $preferredScript
    }

    throw 'SwitchActiveSkinVersion.ps1 was not found in the selected or current root.'
}

function Restore-PreviousActiveVersionAfterCancellation {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedRoot,
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SwitchScript
    )

    try {
        Write-MousePluginUpdateCancellationMarker -DestinationRoot $SelectedRoot
        $rollbackResult = Invoke-HelperScript `
            -ScriptPath $SwitchScript `
            -Arguments @('-CurrentTargetRoot', $SelectedRoot, '-SelectedTargetRoot', $CurrentRoot, '-EmitResultPairs') `
            -Operation 'canceled active version rollback' `
            -DeferCancellation
        Assert-HelperOk -Result $rollbackResult -Operation 'Canceled active version rollback'
        $script:SwitchSucceeded = $false
    }
    catch {
        $script:CancellationRollbackFailed = $true
        $script:CancellationRollbackMessage = 'Cancellation was requested, but the previous active installation could not be restored: ' + [string]$_.Exception.Message
        Write-Log $script:CancellationRollbackMessage 'ERROR'
        throw $script:CancellationRollbackMessage
    }
}

function Invoke-VersionSwitch {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedRoot,
        [Parameter(Mandatory = $true)][string]$CurrentRoot
    )

    $switchScript = Resolve-SwitchScript -PreferredRoot $SelectedRoot -CurrentRoot $CurrentRoot
    $arguments = @('-CurrentTargetRoot', $CurrentRoot, '-SelectedTargetRoot', $SelectedRoot, '-EmitResultPairs')
    Assert-LatestUpdateInstallNotCancelled
    $result = Invoke-HelperScript -ScriptPath $switchScript -Arguments $arguments -Operation 'active version switch' -DeferCancellation
    Assert-HelperOk -Result $result -Operation 'Active version switch'
    $script:SwitchSucceeded = $true
    if (Test-LatestUpdateInstallCancellationRequested) {
        $script:CancellationObserved = $true
        Write-Log 'Cancellation arrived during active version switch; restoring the previous active root.' 'WARN'
        Restore-PreviousActiveVersionAfterCancellation -SelectedRoot $SelectedRoot -CurrentRoot $CurrentRoot -SwitchScript $switchScript
        throw (New-Object System.OperationCanceledException 'Latest update was canceled during active version switching.')
    }
    return $result
}

function Publish-LatestUpdateSwitchingState {
    param([Parameter(Mandatory = $true)][string]$CurrentRoot)

    if ([string]::IsNullOrWhiteSpace($LatestUpdateLaunchToken)) {
        return
    }
    $commonPath = Join-Path $PSScriptRoot 'LatestUpdate.Common.ps1'
    if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) {
        throw 'LatestUpdate.Common.ps1 is required for the latest-update progress handoff.'
    }
    . $commonPath
    $resolvedRoot = Resolve-LatestUpdateTargetRoot -Path $CurrentRoot
    [void](Assert-LatestUpdateToken -LaunchToken $LatestUpdateLaunchToken)
    $rawIntent = Read-LatestUpdateJson -Path (Get-LatestUpdateIntentPath -Root $resolvedRoot)
    if ($null -eq $rawIntent) {
        throw 'Latest update intent was not found before active version switch.'
    }
    $intent = Assert-LatestUpdateIntent -Intent $rawIntent -ExpectedLaunchToken $LatestUpdateLaunchToken
    [void](Save-LatestUpdateState `
        -Root $resolvedRoot `
        -Intent $intent `
        -Status 'switching' `
        -SessionPid $PID `
        -Message 'Switching to the newly installed version.' `
        -LogPath $script:LogPath)
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
    Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value 'OK'
}

function Invoke-PackageInstall {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedCurrentRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot
    )

    Assert-LatestUpdateInstallNotCancelled
    $expectedPackageIdentity = Resolve-ExpectedPackageSha256
    $resolvedPackagePath = Resolve-ReleasePackagePath -CurrentRoot $ResolvedCurrentRoot
    $packageIdentity = Get-ReleasePackageIdentity -Path $resolvedPackagePath
    if ($packageIdentity -notmatch '^[0-9a-f]{64}$') {
        throw 'Could not compute a valid SHA-256 identity for the release package.'
    }
    $normalizedPackageIdentity = $packageIdentity.ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($expectedPackageIdentity) -and
        -not [string]::Equals($normalizedPackageIdentity, $expectedPackageIdentity, [System.StringComparison]::Ordinal)) {
        Write-Log ("Release package SHA-256 mismatch. expected={0} actual={1}" -f $expectedPackageIdentity, $normalizedPackageIdentity) 'ERROR'
        if (-not [string]::IsNullOrWhiteSpace($PackageUrl) -and (Test-Path -LiteralPath $resolvedPackagePath -PathType Leaf)) {
            Remove-Item -LiteralPath $resolvedPackagePath -Force -ErrorAction SilentlyContinue
        }
        throw 'The release package did not match its published SHA-256 checksum.'
    }
    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperReleaseExtract_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    $script:ExtractRoot = $extractRoot
    Assert-BlockHudZipPackageSafeToExtract -PackagePath $resolvedPackagePath -ExtractRoot $extractRoot
    Ensure-Directory -Path $extractRoot
    Invoke-CancelablePowerShellCommand `
        -Command 'Expand-Archive' `
        -Parameters ([ordered]@{
            LiteralPath = $resolvedPackagePath
            DestinationPath = $extractRoot
            Force = $true
            ErrorAction = 'Stop'
        }) `
        -Operation 'release package extraction'
    Assert-LatestUpdateInstallNotCancelled
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
    Write-Log ("PackageIdentity: {0}" -f $normalizedPackageIdentity)
    if (-not [string]::IsNullOrWhiteSpace($expectedPackageIdentity)) {
        Write-Log ("ExpectedPackageSha256: {0}" -f $expectedPackageIdentity)
    }
    Write-Log ("PackageRoot: {0}" -f $packageRoot)
    Write-Log ("PackageVersion: {0}" -f [string]$packageMetadata.Version)
    Write-Log ("PackageReleaseVariant: {0}" -f $packageReleaseVariant)
    Write-Log ("DestinationRoot: {0}" -f $destinationRoot)
    Write-Log 'DestinationRoot policy: side-by-side variant/version-specific root; current fixed root is never overwritten.'

    $packageImportScript = Get-BlockHudRuntimeToolPath -Root $packageRoot -RelativeToolPath 'ImportFromOldVersion.ps1'
    if (-not (Test-Path -LiteralPath $packageImportScript -PathType Leaf)) {
        throw 'Package is missing Utilities\tools\ImportFromOldVersion.ps1.'
    }

    $validationResult = Invoke-ImportValidation -ImportScript $packageImportScript -TargetRoot $packageRoot -SourceRoot $ResolvedCurrentRoot -PackageIdentity $packageIdentity
    Assert-LatestUpdateInstallNotCancelled
    $compatibility = Get-ValidatedCompatibilityStatus -Result $validationResult
    $validationResult.Compatibility = $compatibility
    Copy-CompatibilityResultPairs -Result $validationResult

    $validationSucceeded = ($validationResult.ExitCode -eq 0 -and [string]::Equals([string]$validationResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase))
    if (-not $validationSucceeded -or [string]::Equals($compatibility, 'FATAL', [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value 'FATAL'
        Set-ResultPairValue -Key 'DMEL_REPAIRCOUNT' -Value '0'
        Set-ResultPairValue -Key 'DMEL_REPAIRSUMMARY' -Value ''
        Set-ResultPairValue -Key 'DMEL_REPAIRPLANID' -Value ''
        Set-CompatibilityPreflightResult -Status 'ERROR' -CurrentRoot $ResolvedCurrentRoot -ValidationResult $validationResult
        Write-Log ("Fatal compatibility validation detail: {0}" -f (Convert-ResultPairValueToSingleLine -Value ([string]$validationResult.Message))) 'ERROR'
        return
    }

    $repairPlanId = ''
    if ([string]::Equals($compatibility, 'REPAIRABLE', [System.StringComparison]::OrdinalIgnoreCase)) {
        $repairPlanId = ([string]$validationResult.RepairPlanId).Trim()
        $repairCountValue = 0
        if ($repairPlanId -notmatch '^[0-9A-Fa-f]{64}$' -or
            -not [int]::TryParse(([string]$validationResult.RepairCount), [ref]$repairCountValue) -or
            $repairCountValue -le 0) {
            Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value 'FATAL'
            Set-ResultPairValue -Key 'DMEL_REPAIRCOUNT' -Value '0'
            Set-ResultPairValue -Key 'DMEL_REPAIRSUMMARY' -Value ''
            Set-ResultPairValue -Key 'DMEL_REPAIRPLANID' -Value ''
            Set-CompatibilityPreflightResult -Status 'ERROR' -CurrentRoot $ResolvedCurrentRoot -ValidationResult $validationResult
            Write-Log 'Repairable compatibility validation did not provide a valid repair count and SHA-256 plan id.' 'ERROR'
            return
        }

        $expectedPlanMatches = (-not [string]::IsNullOrWhiteSpace($ExpectedRepairPlanId) -and
            [string]::Equals($repairPlanId, $ExpectedRepairPlanId.Trim(), [System.StringComparison]::OrdinalIgnoreCase))
        if (-not $AllowCompatibilityWarning -or -not $expectedPlanMatches) {
            Set-CompatibilityPreflightResult -Status 'WARN' -CurrentRoot $ResolvedCurrentRoot -ValidationResult $validationResult
            if ($AllowCompatibilityWarning -and -not $expectedPlanMatches) {
                Write-Log 'Compatibility repair approval was rejected because the expected repair plan did not match the current preflight.' 'WARN'
            }
            else {
                Write-Log ("Repairable compatibility validation requires approval: {0}" -f (Convert-ResultPairValueToSingleLine -Value ([string]$validationResult.RepairSummary))) 'WARN'
            }
            return
        }

        Write-Log ("Approved compatibility repair plan: {0} count={1} summary={2}" -f $repairPlanId, $repairCountValue, (Convert-ResultPairValueToSingleLine -Value ([string]$validationResult.RepairSummary))) 'WARN'
    }
    elseif ($AllowCompatibilityWarning -and -not [string]::IsNullOrWhiteSpace($ExpectedRepairPlanId)) {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $ResolvedCurrentRoot
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value 'FATAL'
        Set-ResultPairValue -Key 'DMEL_REPAIRCOUNT' -Value '0'
        Set-ResultPairValue -Key 'DMEL_REPAIRSUMMARY' -Value ''
        Set-ResultPairValue -Key 'DMEL_REPAIRPLANID' -Value ''
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Update_CompatibilityRepairChanged' 'Current data or package changed after approval. Installation was not started. Review compatibility and approve again.')
        Write-Log 'Compatibility repair approval became stale because the current preflight no longer requires that repair.' 'ERROR'
        return
    }

    try {
        Assert-LatestUpdateInstallNotCancelled
        Move-ExistingDestinationForReplacement -DestinationRoot $destinationRoot -CurrentRoot $ResolvedCurrentRoot
        Copy-PackageToDestination -PackageRoot $packageRoot -DestinationRoot $destinationRoot
        $script:DestinationCreated = $true
        Assert-LatestUpdateInstallNotCancelled
        Use-CanonicalHelperLogPath -Root $destinationRoot -Prefix 'InstallVersionRelease'

        $installedImportScript = Get-BlockHudRuntimeToolPath -Root $destinationRoot -RelativeToolPath 'ImportFromOldVersion.ps1'
        if (-not (Test-Path -LiteralPath $installedImportScript -PathType Leaf)) {
            throw (T 'Helper_VersionManager_Update_InstalledImportHelperMissing' 'The installed root is missing Utilities\tools\ImportFromOldVersion.ps1.')
        }
        Invoke-RealImport -ImportScript $installedImportScript -TargetRoot $destinationRoot -SourceRoot $ResolvedCurrentRoot -PackageIdentity $packageIdentity -RepairPlanId $repairPlanId -ImportProgressOwnerRoot $ProgressOwnerRoot -ImportProgressToken $ProgressToken

        Assert-LatestUpdateInstallNotCancelled
        Publish-LatestUpdateSwitchingState -CurrentRoot $ResolvedCurrentRoot
        Invoke-InstalledRootRefresh -Root $destinationRoot
        Assert-LatestUpdateInstallNotCancelled
        Invoke-VersionSwitch -SelectedRoot $destinationRoot -CurrentRoot $ResolvedCurrentRoot | Out-Null
        Complete-DestinationReplacement -DestinationRoot $destinationRoot
    }
    catch {
        throw
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $destinationRoot
    Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    if ([string]::Equals($compatibility, 'REPAIRABLE', [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (TF 'Helper_VersionManager_Update_InstalledWithRepair' @([string]$validationResult.RepairCount) 'Installed the selected release after clearing only the %1 approved unusable image field(s), imported all other current data, and switched active configs.')
    }
    else {
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

    $progressRequested = (-not [string]::IsNullOrWhiteSpace($ProgressOwnerRoot) -or
        -not [string]::IsNullOrWhiteSpace($ProgressToken))
    if ($progressRequested -and ([string]::IsNullOrWhiteSpace($ProgressOwnerRoot) -or
        [string]::IsNullOrWhiteSpace($ProgressToken))) {
        throw 'ProgressOwnerRoot and ProgressToken must be supplied together.'
    }
    if ($progressRequested) {
        if ($ProgressToken -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
            throw 'ProgressToken contains unsupported characters or exceeds the supported length.'
        }
        $resolvedProgressOwner = Resolve-FullPath -Path $ProgressOwnerRoot
        if (-not [string]::Equals($resolvedProgressOwner, $resolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'ProgressOwnerRoot must resolve exactly to CurrentTargetRoot.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedProgressOwner '@Resources\Customs\Data') -PathType Container)) {
            throw 'ProgressOwnerRoot does not contain the required @Resources\Customs\Data directory.'
        }
        if (-not [string]::IsNullOrWhiteSpace($SelectedTargetRoot)) {
            throw 'ProgressOwnerRoot and ProgressToken are supported only for package installation.'
        }
    }

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
    $failureRecord = $_
    $rawMessage = [string]$_.Exception.Message
    $rollbackFailureMessage = ''
    if (($script:DestinationCreated -or -not [string]::IsNullOrWhiteSpace($script:DestinationReplacementBackupRoot)) -and -not [string]::IsNullOrWhiteSpace($script:ResolvedDestinationRoot)) {
        try {
            Undo-DestinationInstallAttempt `
                -DestinationRoot $script:ResolvedDestinationRoot `
                -Reason $(if ($script:CancellationObserved) { 'canceled release install' } else { 'error rollback' })
        }
        catch {
            $rollbackFailureMessage = [string]$_.Exception.Message
            Write-Log ("Destination rollback failed: {0}" -f $rollbackFailureMessage) 'ERROR'
            if ($script:CancellationObserved) {
                $script:CancellationRollbackFailed = $true
                $script:CancellationRollbackMessage = 'Cancellation was requested, but the destination installation could not be rolled back completely: ' + $rollbackFailureMessage
            }
        }
    }

    $cancellationCompleted = $script:CancellationObserved -and -not $script:CancellationRollbackFailed
    $friendlyMessage = if ($script:CancellationRollbackFailed) {
        if ([string]::IsNullOrWhiteSpace($script:CancellationRollbackMessage)) { $rawMessage } else { $script:CancellationRollbackMessage }
    }
    else {
        $baseMessage = Get-FriendlyInstallErrorMessage -RawMessage $rawMessage
        if ([string]::IsNullOrWhiteSpace($rollbackFailureMessage)) { $baseMessage }
        else { $baseMessage + ' Destination rollback also failed: ' + $rollbackFailureMessage }
    }
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value $(if ($cancellationCompleted) { 'CANCEL' } else { 'ERROR' })
    if (-not $cancellationCompleted -and ([string]::IsNullOrWhiteSpace([string]$script:ResultPairs['DMEL_COMPATIBILITY']) -or
        [string]::Equals([string]$script:ResultPairs['DMEL_COMPATIBILITY'], 'OK', [System.StringComparison]::OrdinalIgnoreCase))) {
        Set-ResultPairValue -Key 'DMEL_COMPATIBILITY' -Value 'FATAL'
    }
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
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $(if ($cancellationCompleted) { 'Latest update was canceled and transactional changes were rolled back.' } else { $friendlyMessage })
    Write-Log $rawMessage $(if ($cancellationCompleted) { 'WARN' } else { 'ERROR' })
    if ($failureRecord.ScriptStackTrace) {
        Write-Log $failureRecord.ScriptStackTrace 'ERROR'
    }
}
finally {
    Remove-ExtractRootBestEffort
    Save-Log
    if ($PassThruResultObject) {
        Write-Output ([PSCustomObject]$script:ResultPairs)
    }
    else {
        Emit-ResultPairs
    }
}
