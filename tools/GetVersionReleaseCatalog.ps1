[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [switch]$NonInteractive,
    [switch]$OutputJson,
    [switch]$EmitResultPairs,
    [switch]$SyncUpdateCache,
    [switch]$PreferFreshCache,
    [int]$CatalogCacheMaxAgeSeconds = 900
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
. (Join-Path $PSScriptRoot 'VersionManager.UpdateCache.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.ReleaseCatalog.ps1')

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:SkinRootForLocalization = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$script:LanguageCode = Read-LanguageCode -SkinRoot $script:SkinRootForLocalization
$script:LocTable = Read-LocaleTable -SkinRoot $script:SkinRootForLocalization -LanguageCode $script:LanguageCode
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
    DMEL_LATESTVERSION = ''
    DMEL_CACHESTATUS = ''
    DMEL_CACHEERRORCODE = ''
    DMEL_CACHEFAILUREHINT = ''
    DMEL_CACHELASTCHECKEDATUTC = ''
}
$script:ShouldOutputJson = $OutputJson -or (-not $EmitResultPairs)

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Fallback = ''
    )

    Get-LocalizedText -Table $script:LocTable -Key $Key -Fallback $Fallback
}

function Get-FriendlyCatalogErrorMessage {
    param([AllowNull()][string]$RawMessage)

    $resolved = [string]$RawMessage
    if ($resolved -eq (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest stable release could not be found.')) {
        return $resolved
    }

    return (T 'Helper_VersionManager_Common_LoadFailed' 'The requested data could not be loaded.')
}

function Set-ResultPairValue {
    param([string]$Key, [string]$Value)

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Write-OutputPair {
    param([string]$Key, [string]$Value)

    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($Key + '=' + [string]$Value)
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
    foreach ($key in @('DMEL_STATUS', 'DMEL_SOURCEPATH', 'DMEL_BACKUPPATH', 'DMEL_LOGPATH', 'DMEL_MESSAGE', 'DMEL_LATESTVERSION', 'DMEL_CACHESTATUS', 'DMEL_CACHEERRORCODE', 'DMEL_CACHEFAILUREHINT', 'DMEL_CACHELASTCHECKEDATUTC')) {
        Write-OutputPair -Key $key -Value $script:ResultPairs[$key]
    }
}

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')

    $line = '[{0}] {1}' -f $Level, $Message
    [void]$script:LogMessages.Add($line)
}

function Save-Log {
    $parent = Split-Path -Parent $script:LogPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'VersionReleaseCatalog' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
}

function Resolve-FullPath {
    param([string]$Path, [switch]$AllowMissing)

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

function Join-RootPath {
    param([string]$Root, [string]$RelativePath)

    Join-Path $Root $RelativePath
}

function Read-TextSmart {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return ([System.Text.UnicodeEncoding]::new($false, $true)).GetString($bytes, 2, $bytes.Length - 2)
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
        if ($line.TrimStart().StartsWith('[')) {
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

function Test-SkinRoot {
    param([AllowNull()][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }
    foreach ($relativePath in @('@Resources\Customs', 'Settings', 'Inventory', 'Hotbar')) {
        if (-not (Test-Path -LiteralPath (Join-RootPath -Root $Root -RelativePath $relativePath) -PathType Container)) {
            return $false
        }
    }
    return $true
}

function Test-BlockHudRootName {
    param([AllowNull()][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }
    $leafName = [System.IO.Path]::GetFileName($Root.TrimEnd('\', '/'))
    return ($leafName.IndexOf("DMeloper's Block HUD", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
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

function Get-SkinMetadataVersion {
    param([Parameter(Mandatory = $true)][string]$Root)

    $settingsIni = Join-RootPath -Root $Root -RelativePath 'Settings\Settings.ini'
    if (-not (Test-Path -LiteralPath $settingsIni -PathType Leaf)) {
        return ''
    }

    $content = Read-TextSmart -Path $settingsIni
    $inVariables = $false
    foreach ($rawLine in ($content -split "`r?`n")) {
        $trimmed = ([string]$rawLine).Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inVariables = ($matches[1] -ieq 'Variables')
            continue
        }
        if ($inVariables -and $trimmed -match '^AppVersion=(.*)$') {
            return [string]$matches[1].Trim()
        }
        if ($trimmed -match '^Version=(.*)$') {
            return [string]$matches[1].Trim()
        }
    }

    return ''
}

function Convert-ToSemanticVersion {
    param([AllowNull()][string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $normalized = $VersionText.Trim()
    if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }
    if ($normalized -notmatch '^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$') {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($matches[4])) {
        return (New-Object System.Version ([int]$matches[1]), ([int]$matches[2]), ([int]$matches[3]))
    }

    return (New-Object System.Version ([int]$matches[1]), ([int]$matches[2]), ([int]$matches[3]), ([int]$matches[4]))
}

function Get-GeneralSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\General.inc'
}

function Get-SupportSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\Support.inc'
}

function Get-FixedUpdateZipAssetName {
    param([AllowNull()][string]$LanguageCode)

    return (Get-BlockHudFixedUpdateZipAssetName -LanguageCode $LanguageCode)
}

function Get-RootReleaseVariant {
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

function Get-UpdateConfiguration {
    param([Parameter(Mandatory = $true)][string]$Root)

    $general = Read-VariablesFile -Path (Get-GeneralSettingsPath -Root $Root)
    $support = Read-VariablesFile -Path (Get-SupportSettingsPath -Root $Root)
    $languageCode = if ([string]::IsNullOrWhiteSpace([string]$general['LanguageCode'])) { 'en-US' } else { [string]$general['LanguageCode'] }
    $legacyAssetPattern = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateReleaseAssetPattern'])) { '' } else { [string]$support['UpdateReleaseAssetPattern'] }
    $releaseVariant = Normalize-BlockHudReleaseVariant `
        -ConfiguredReleaseVariant ([string]$support['UpdateReleaseVariant']) `
        -LanguageCode $languageCode `
        -AssetPattern $legacyAssetPattern
    $assetName = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant $releaseVariant -LanguageCode $languageCode

    [PSCustomObject]@{
        Provider = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateProvider'])) { 'github' } else { [string]$support['UpdateProvider'] }
        Owner = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubOwner'])) { 'd-meloper' } else { [string]$support['UpdateGithubOwner'] }
        Repo = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubRepo'])) { 'dmelopers-block-hud' } else { [string]$support['UpdateGithubRepo'] }
        LanguageCode = $languageCode
        ReleaseVariant = $releaseVariant
        AssetName = $assetName
    }
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

function Get-RainmeterSkinPaths {
    $configPath = Get-RainmeterConfigPath
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        return @()
    }

    $paths = New-Object System.Collections.Generic.List[string]
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
            $value = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $parts = $value -split ';'
                foreach ($part in $parts) {
                    if (-not [string]::IsNullOrWhiteSpace($part)) {
                        [void]$paths.Add((Resolve-FullPath -Path $part.Trim() -AllowMissing))
                    }
                }
            }
        }
    }

    return $paths.ToArray()
}

function Get-InstalledBlockHudVersions {
    param([Parameter(Mandatory = $true)][string]$CurrentRoot)

    $items = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $addCandidate = {
        param([AllowNull()][string]$Candidate)

        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            return
        }

        $resolvedCandidate = $null
        try {
            $resolvedCandidate = Resolve-SkinRootCandidate -Candidate $Candidate
        }
        catch {
            $resolvedCandidate = $null
        }
        if (-not $resolvedCandidate) {
            return
        }
        if (-not (Test-BlockHudRootName -Root $resolvedCandidate)) {
            return
        }
        if (-not $seen.Add($resolvedCandidate)) {
            return
        }

        $versionText = Get-SkinMetadataVersion -Root $resolvedCandidate
        $semanticVersion = Convert-ToSemanticVersion -VersionText $versionText
        if ($null -eq $semanticVersion) {
            return
        }

        [void]$items.Add([PSCustomObject]@{
            Path = $resolvedCandidate
            VersionText = $versionText
            Version = $semanticVersion
            ReleaseVariant = Get-RootReleaseVariant -Root $resolvedCandidate
            IsCurrent = [string]::Equals($resolvedCandidate, $CurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }

    & $addCandidate -Candidate $CurrentRoot
    foreach ($skinPath in Get-RainmeterSkinPaths) {
        if (-not (Test-Path -LiteralPath $skinPath -PathType Container)) {
            continue
        }
        $skinDirectories = @(Get-ChildItem -LiteralPath $skinPath -Directory -Force -ErrorAction SilentlyContinue)
        foreach ($directory in $skinDirectories) {
            & $addCandidate -Candidate $directory.FullName
        }
    }

    return $items.ToArray()
}

function Get-MatchingInstall {
    param(
        [Parameter(Mandatory = $true)][object[]]$Installations,
        [Parameter(Mandatory = $true)][version]$Version,
        [Parameter(Mandatory = $true)][string]$ReleaseVariant
    )

    $matches = @($Installations | Where-Object {
        $null -ne $_.Version -and
        $_.Version.CompareTo($Version) -eq 0 -and
        [string]::Equals([string]$_.ReleaseVariant, $ReleaseVariant, [System.StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object @{ Expression = { if ($_.IsCurrent) { 0 } else { 1 } } }, Path)
    if ($matches.Count -gt 0) {
        return $matches[0]
    }
    return $null
}

function Find-ReleaseAsset {
    param(
        [AllowNull()]$Release,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    foreach ($asset in @($Release.assets)) {
        if ([string]::Equals([string]$asset.name, $AssetName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $asset
        }
    }
    return $null
}

function ConvertTo-ChangelogSummary {
    param([AllowNull()][string]$Body)

    $summary = ([string]$Body).Trim()
    $summary = [regex]::Replace($summary, '<[^>]+>', ' ')
    $summary = [System.Net.WebUtility]::HtmlDecode($summary)
    $summary = [regex]::Replace($summary, '^[\p{Cf}\p{Cc}\s]+', '')
    $summary = [regex]::Replace($summary, '\s+', ' ')
    $summary = $summary.Trim()
    if ($summary.Length -gt 600) {
        $summary = $summary.Substring(0, 600).Trim() + '...'
    }
    return $summary
}

function Get-CatalogUpdateErrorCode {
    param([AllowNull()][System.Exception]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [System.Net.WebException]) {
            switch ($current.Status) {
                'ConnectFailure' { return 'update-network-offline' }
                'SendFailure' { return 'update-network-offline' }
                'ReceiveFailure' { return 'update-network-offline' }
                'NameResolutionFailure' { return 'update-network-offline' }
                'ProxyNameResolutionFailure' { return 'update-network-offline' }
                'Timeout' { return 'update-network-offline' }
            }
        }
        if ([string]$current.Message -match '(?i)(internet connection|offline|name resolution|timed out|connect)') {
            return 'update-network-offline'
        }
        if ([string]$current.Message -match '(?i)(expected update ZIP|release asset|asset.*not found)') {
            return 'update-asset-match-failed'
        }
        $current = $current.InnerException
    }

    return 'update-check-failed'
}

function Get-CatalogUpdateFailureHint {
    param([string]$ErrorCode)

    if ([string]::Equals($ErrorCode, 'update-network-offline', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'offline'
    }
    return ''
}

function Set-CacheResultPairs {
    param([Parameter(Mandatory = $true)]$Cache)

    Set-ResultPairValue -Key 'DMEL_LATESTVERSION' -Value ([string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'LatestVersion' -DefaultValue ''))
    Set-ResultPairValue -Key 'DMEL_CACHESTATUS' -Value ([string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'Status' -DefaultValue ''))
    Set-ResultPairValue -Key 'DMEL_CACHEERRORCODE' -Value ([string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'ErrorCode' -DefaultValue ''))
    Set-ResultPairValue -Key 'DMEL_CACHEFAILUREHINT' -Value ([string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'FailureHint' -DefaultValue ''))
    Set-ResultPairValue -Key 'DMEL_CACHELASTCHECKEDATUTC' -Value ([string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'LastCheckedAtUtc' -DefaultValue ''))
}

function Save-CatalogUpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Catalog
    )

    $latest = $null
    foreach ($entry in @($Catalog.releases)) {
        if ([bool]$entry.is_latest_stable) {
            $latest = $entry
            break
        }
    }
    if ($null -eq $latest) {
        throw (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.')
    }
    if ([string]::IsNullOrWhiteSpace([string]$latest.asset_url)) {
        throw ("The expected update ZIP `"{0}`" was not found in the latest release." -f [string]$latest.asset_name)
    }

    $cache = [PSCustomObject]@{
        LastCheckedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        LatestVersion = [string]$latest.tag
        ReleaseName = [string]$latest.release_name
        ReleaseUrl = if ([string]::IsNullOrWhiteSpace([string]$latest.tag)) { '' } else { 'https://github.com/{0}/{1}/releases/tag/{2}' -f [string]$Catalog.owner, [string]$Catalog.repo, [System.Uri]::EscapeDataString([string]$latest.tag) }
        AssetName = [string]$latest.asset_name
        AssetUrl = [string]$latest.asset_url
        AssetSize = [long]$latest.asset_size
        PublishedAtUtc = [string]$latest.published_at
        ChangelogSummary = [string]$latest.changelog_summary
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = 'ready'
        Error = ''
        ErrorCode = ''
        FailureHint = ''
        ReleaseVariant = [string]$Catalog.release_variant
        ActiveAssetPattern = [string]$Catalog.asset_name
    }

    $saved = Save-VersionManagerUpdateCache -Root $Root -Cache $cache
    Set-CacheResultPairs -Cache $saved
    return $saved
}

function Save-CatalogUpdateFailureCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowNull()][string]$Message,
        [Parameter(Mandatory = $true)][string]$ErrorCode
    )

    $cache = Update-VersionManagerUpdateCache -Root $Root -Patch ([PSCustomObject]@{
        LastCheckedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        LatestVersion = ''
        ReleaseName = ''
        ReleaseUrl = ''
        AssetName = ''
        AssetUrl = ''
        AssetSize = 0
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = 'error'
        Error = [string]$Message
        ErrorCode = $ErrorCode
        FailureHint = Get-CatalogUpdateFailureHint -ErrorCode $ErrorCode
        ReleaseVariant = ''
        ActiveAssetPattern = ''
    })

    Set-CacheResultPairs -Cache $cache
    return $cache
}

function Invoke-GitHubReleaseCatalogRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo
    )

    return (Invoke-BlockHudGitHubReleaseCatalogRequest `
        -Owner $Owner `
        -Repo $Repo `
        -UserAgent 'DMeloper-Block-HUD-VersionCatalog' `
        -Log { param($Message, $Level) Write-Log -Message $Message -Level $Level })
}

function Write-JsonStdout {
    param([Parameter(Mandatory = $true)]$Value)

    $json = $Value | ConvertTo-Json -Depth 12
    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($json)
    }
    finally {
        $writer.Dispose()
    }
}

function Get-CompatibleReleaseCatalogCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Config,
        [int]$MaxAgeSeconds = 900,
        [switch]$AllowStale
    )

    $cached = Read-VersionManagerReleaseCatalogCache -Root $Root
    if ($null -eq $cached -or @($cached.releases).Count -eq 0) {
        return $null
    }

    foreach ($comparison in @(
        @([string](Get-VersionManagerObjectPropertyValue -Object $cached -Name 'owner' -DefaultValue ''), [string]$Config.Owner),
        @([string](Get-VersionManagerObjectPropertyValue -Object $cached -Name 'repo' -DefaultValue ''), [string]$Config.Repo),
        @([string](Get-VersionManagerObjectPropertyValue -Object $cached -Name 'release_variant' -DefaultValue ''), [string]$Config.ReleaseVariant),
        @([string](Get-VersionManagerObjectPropertyValue -Object $cached -Name 'asset_name' -DefaultValue ''), [string]$Config.AssetName)
    )) {
        if (-not [string]::Equals($comparison[0], $comparison[1], [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }

    $generatedText = [string](Get-VersionManagerObjectPropertyValue -Object $cached -Name 'generated_at_utc' -DefaultValue '')
    $generatedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
        $generatedText,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$generatedAt
    )) {
        return $null
    }

    $ageSeconds = [Math]::Max(0, ([DateTime]::UtcNow - $generatedAt.ToUniversalTime()).TotalSeconds)
    if (-not $AllowStale -and $ageSeconds -gt [Math]::Max(0, $MaxAgeSeconds)) {
        return $null
    }

    Set-VersionManagerObjectPropertyValue -Object $cached -Name 'catalog_cache_age_seconds' -Value ([Math]::Round($ageSeconds, 1))
    Set-VersionManagerObjectPropertyValue -Object $cached -Name 'catalog_cache_stale' -Value ($ageSeconds -gt [Math]::Max(0, $MaxAgeSeconds))
    Set-VersionManagerObjectPropertyValue -Object $cached -Name 'catalog_cache_reused' -Value $true
    return $cached
}

function Update-CachedReleaseCatalogLocalState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)]$Config
    )

    $installations = @(Get-InstalledBlockHudVersions -CurrentRoot $Root)
    foreach ($entry in @($Catalog.releases)) {
        $version = Convert-ToSemanticVersion -VersionText ([string]$entry.version)
        $install = if ($null -eq $version) {
            $null
        }
        else {
            Get-MatchingInstall -Installations $installations -Version $version -ReleaseVariant ([string]$Config.ReleaseVariant)
        }
        $hasAsset = -not [string]::IsNullOrWhiteSpace([string]$entry.asset_url)
        $isLatestStable = [bool]$entry.is_latest_stable
        $status = if ($isLatestStable -and -not $hasAsset) {
            'asset_missing'
        }
        elseif ($isLatestStable) {
            'latest_stable'
        }
        elseif (-not $hasAsset) {
            'asset_missing'
        }
        elseif ($null -ne $install) {
            'installed'
        }
        else {
            'available'
        }

        Set-VersionManagerObjectPropertyValue -Object $entry -Name 'installed_path' -Value $(if ($null -ne $install) { [string]$install.Path } else { '' })
        Set-VersionManagerObjectPropertyValue -Object $entry -Name 'status' -Value $status
    }

    Set-VersionManagerObjectPropertyValue -Object $Catalog -Name 'current_target_root' -Value $Root
    return $Catalog
}

function Get-VersionReleaseCatalog {
    $resolvedRoot = Resolve-SkinRootCandidate -Candidate $CurrentTargetRoot
    if (-not $resolvedRoot) {
        throw "CurrentTargetRoot is not a valid Block HUD root: $CurrentTargetRoot"
    }
    $resolvedRoot = Resolve-FullPath -Path $resolvedRoot
    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $resolvedRoot -ScriptRoot $PSScriptRoot
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedRoot
    Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath

    if (-not (Test-SkinRoot -Root $resolvedRoot)) {
        throw "CurrentTargetRoot is not a valid Block HUD root: $resolvedRoot"
    }

    $config = Get-UpdateConfiguration -Root $resolvedRoot
    if (-not [string]::Equals([string]$config.Provider, 'github', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsupported update provider: $($config.Provider)"
    }

    $script:CompatibleCachedCatalog = Get-CompatibleReleaseCatalogCache -Root $resolvedRoot -Config $config -MaxAgeSeconds $CatalogCacheMaxAgeSeconds -AllowStale
    if ($PreferFreshCache) {
        $freshCachedCatalog = Get-CompatibleReleaseCatalogCache -Root $resolvedRoot -Config $config -MaxAgeSeconds $CatalogCacheMaxAgeSeconds
        if ($null -ne $freshCachedCatalog) {
            return (Update-CachedReleaseCatalogLocalState -Root $resolvedRoot -Catalog $freshCachedCatalog -Config $config)
        }
        if ($null -ne $script:CompatibleCachedCatalog) {
            Set-VersionManagerObjectPropertyValue -Object $script:CompatibleCachedCatalog -Name 'catalog_cache_stale' -Value $true
            return (Update-CachedReleaseCatalogLocalState -Root $resolvedRoot -Catalog $script:CompatibleCachedCatalog -Config $config)
        }
    }

    $releases = @(Invoke-GitHubReleaseCatalogRequest -Owner ([string]$config.Owner) -Repo ([string]$config.Repo))
    $stableReleaseItems = @(Get-BlockHudStableReleaseEntries `
        -Releases $releases `
        -Log { param($Message, $Level) Write-Log -Message $Message -Level $Level })

    if ($stableReleaseItems.Count -eq 0) {
        throw (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.')
    }

    $latestStable = $stableReleaseItems[0]
    $latestStableAsset = Find-ReleaseAsset -Release $latestStable.Release -AssetName ([string]$config.AssetName)
    if ($null -eq $latestStableAsset) {
        Write-Log ("Latest stable release {0} is missing expected update ZIP: {1}" -f [string]$latestStable.Tag, [string]$config.AssetName) 'ERROR'
    }
    $installations = @(Get-InstalledBlockHudVersions -CurrentRoot $resolvedRoot)
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $stableReleaseItems) {
        $release = $entry.Release
        $asset = Find-ReleaseAsset -Release $release -AssetName ([string]$config.AssetName)
        $install = Get-MatchingInstall -Installations $installations -Version $entry.Version -ReleaseVariant ([string]$config.ReleaseVariant)
        $hasAsset = ($null -ne $asset)
        $isInstalled = ($null -ne $install)
        $isLatestStable = ($entry.Version.CompareTo($latestStable.Version) -eq 0 -and [string]::Equals([string]$entry.Tag, [string]$latestStable.Tag, [System.StringComparison]::OrdinalIgnoreCase))
        $status = if ($isLatestStable -and -not $hasAsset) { 'asset_missing' } elseif ($isLatestStable) { 'latest_stable' } elseif (-not $hasAsset) { 'asset_missing' } elseif ($isInstalled) { 'installed' } else { 'available' }

        [void]$items.Add([PSCustomObject]@{
            version = $entry.Version.ToString()
            tag = [string]$entry.Tag
            is_latest_stable = $isLatestStable
            release_variant = [string]$config.ReleaseVariant
            release_name = [string]$release.name
            published_at = [string]$release.published_at
            asset_name = if ($hasAsset) { [string]$asset.name } else { [string]$config.AssetName }
            asset_url = if ($hasAsset) { [string]$asset.browser_download_url } else { '' }
            asset_size = if ($hasAsset) { [long]$asset.size } else { 0 }
            changelog_summary = ConvertTo-ChangelogSummary -Body ([string]$release.body)
            status = $status
            installed_path = if ($isInstalled) { [string]$install.Path } else { '' }
        })
    }

    $result = [PSCustomObject]@{
        status = 'OK'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        current_target_root = $resolvedRoot
        provider = [string]$config.Provider
        owner = [string]$config.Owner
        repo = [string]$config.Repo
        language_code = [string]$config.LanguageCode
        release_variant = [string]$config.ReleaseVariant
        asset_name = [string]$config.AssetName
        latest_stable_version = $latestStable.Version.ToString()
        latest_stable_tag = [string]$latestStable.Tag
        releases = $items.ToArray()
    }
    Set-VersionManagerObjectPropertyValue -Object $result -Name 'catalog_cache_age_seconds' -Value 0
    Set-VersionManagerObjectPropertyValue -Object $result -Name 'catalog_cache_stale' -Value $false
    Set-VersionManagerObjectPropertyValue -Object $result -Name 'catalog_cache_reused' -Value $false
    [void](Save-VersionManagerReleaseCatalogCache -Root $resolvedRoot -Catalog $result)
    return $result
}

$catalog = $null
$script:CompatibleCachedCatalog = $null
try {
    $catalog = Get-VersionReleaseCatalog
    $catalogIsStale = [bool](Get-VersionManagerObjectPropertyValue -Object $catalog -Name 'catalog_cache_stale' -DefaultValue $false)
    $catalogWasReused = [bool](Get-VersionManagerObjectPropertyValue -Object $catalog -Name 'catalog_cache_reused' -DefaultValue $false)
    if ($SyncUpdateCache) {
        if ($catalogWasReused) {
            $existingUpdateCache = Read-VersionManagerUpdateCache -Root ([string]$catalog.current_target_root)
            Set-CacheResultPairs -Cache $existingUpdateCache
        }
        else {
            [void](Save-CatalogUpdateCache -Root ([string]$catalog.current_target_root) -Catalog $catalog)
        }
    }
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value $(if ($catalogIsStale) { 'WARN' } else { 'OK' })
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $(if ($catalogIsStale) { 'Using the last cached release catalog.' } else { 'Release catalog loaded.' })
    Write-Log ("Release catalog loaded. items={0}" -f @($catalog.releases).Count)
}
catch {
    $friendlyMessage = Get-FriendlyCatalogErrorMessage -RawMessage ([string]$_.Exception.Message)
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    if ([string]::IsNullOrWhiteSpace([string]$script:ResultPairs['DMEL_SOURCEPATH'])) {
        try {
            Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value (Resolve-FullPath -Path $CurrentTargetRoot -AllowMissing)
        }
        catch {
            Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $CurrentTargetRoot
        }
    }
    Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $friendlyMessage
    if ($SyncUpdateCache) {
        try {
            $cacheRoot = [string]$script:ResultPairs['DMEL_SOURCEPATH']
            if ([string]::IsNullOrWhiteSpace($cacheRoot)) {
                $cacheRoot = Resolve-FullPath -Path $CurrentTargetRoot -AllowMissing
            }
            $errorCode = Get-CatalogUpdateErrorCode -Exception $_.Exception
            [void](Save-CatalogUpdateFailureCache -Root $cacheRoot -Message ([string]$_.Exception.Message) -ErrorCode $errorCode)
        }
        catch {
            Write-Log ("Failed to write update-cache failure state: {0}" -f $_.Exception.Message) 'ERROR'
        }
    }
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }

    if ($null -ne $script:CompatibleCachedCatalog) {
        $catalog = $script:CompatibleCachedCatalog
        Set-VersionManagerObjectPropertyValue -Object $catalog -Name 'catalog_cache_stale' -Value $true
        Set-VersionManagerObjectPropertyValue -Object $catalog -Name 'message' -Value $friendlyMessage
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $friendlyMessage
        Write-Log 'Using the last compatible release catalog after the live refresh failed.' 'WARN'
    }
    else {
        $catalog = [PSCustomObject]@{
            status = 'ERROR'
            generated_at_utc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
            current_target_root = [string]$script:ResultPairs['DMEL_SOURCEPATH']
            message = $friendlyMessage
            releases = @()
        }
    }
}
finally {
    Save-Log
}

if ($script:ShouldOutputJson) {
    Write-JsonStdout -Value $catalog
}
Emit-ResultPairs

if ([string]::Equals([string]$script:ResultPairs['DMEL_STATUS'], 'ERROR', [System.StringComparison]::OrdinalIgnoreCase)) {
    exit 1
}
