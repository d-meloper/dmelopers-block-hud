[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [switch]$NonInteractive,
    [switch]$OutputJson,
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
    foreach ($key in @('DMEL_STATUS', 'DMEL_SOURCEPATH', 'DMEL_BACKUPPATH', 'DMEL_LOGPATH', 'DMEL_MESSAGE')) {
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

    if ([string]::Equals(([string]$LanguageCode).Trim(), 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'DMelopers-Block-HUD_Korea.zip'
    }
    return 'DMelopers-Block-HUD_Global.zip'
}

function Get-UpdateConfiguration {
    param([Parameter(Mandatory = $true)][string]$Root)

    $general = Read-VariablesFile -Path (Get-GeneralSettingsPath -Root $Root)
    $support = Read-VariablesFile -Path (Get-SupportSettingsPath -Root $Root)
    $languageCode = if ([string]::IsNullOrWhiteSpace([string]$general['LanguageCode'])) { 'en-US' } else { [string]$general['LanguageCode'] }
    $assetName = Get-FixedUpdateZipAssetName -LanguageCode $languageCode

    [PSCustomObject]@{
        Provider = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateProvider'])) { 'github' } else { [string]$support['UpdateProvider'] }
        Owner = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubOwner'])) { 'd-meloper' } else { [string]$support['UpdateGithubOwner'] }
        Repo = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubRepo'])) { 'dmelopers-block-hud' } else { [string]$support['UpdateGithubRepo'] }
        LanguageCode = $languageCode
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
            IsCurrent = [string]::Equals($resolvedCandidate, $CurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }

    & $addCandidate -Candidate $CurrentRoot
    foreach ($skinPath in Get-RainmeterSkinPaths) {
        if (-not (Test-Path -LiteralPath $skinPath -PathType Container)) {
            continue
        }
        foreach ($directory in Get-ChildItem -LiteralPath $skinPath -Directory -Force -ErrorAction SilentlyContinue) {
            & $addCandidate -Candidate $directory.FullName
        }
    }

    return $items.ToArray()
}

function Get-MatchingInstall {
    param(
        [Parameter(Mandatory = $true)][object[]]$Installations,
        [Parameter(Mandatory = $true)][version]$Version
    )

    $matches = @($Installations | Where-Object { $null -ne $_.Version -and $_.Version.CompareTo($Version) -eq 0 } | Sort-Object @{ Expression = { if ($_.IsCurrent) { 0 } else { 1 } } }, Path)
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

function Test-GitHubApiRateLimitException {
    param([AllowNull()]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        $response = $null
        try {
            $response = $current.Response
        }
        catch {
            $response = $null
        }

        if ($null -ne $response) {
            $statusCode = $null
            try {
                $statusCode = [int]$response.StatusCode
            }
            catch {
                $statusCode = $null
            }
            $statusDescription = ''
            try {
                $statusDescription = [string]$response.StatusDescription
            }
            catch {
                $statusDescription = ''
            }

            if ($statusCode -eq 429) {
                return $true
            }
            if ($statusCode -eq 403 -and $statusDescription -match '(?i)rate limit') {
                return $true
            }
        }

        $message = [string]$current.Message
        if ($message -match '(?i)rate limit') {
            return $true
        }
        $current = $current.InnerException
    }

    return $false
}

function Invoke-GitHubWebRequestText {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $headers = @{
        'User-Agent' = 'DMeloper-Block-HUD-VersionCatalog'
    }
    $response = Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing
    return [string]$response.Content
}

function Get-GitHubReleaseAssetsFromHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    $assetsUri = 'https://github.com/{0}/{1}/releases/expanded_assets/{2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($Tag)
    $html = Invoke-GitHubWebRequestText -Uri $assetsUri
    $assets = New-Object System.Collections.Generic.List[object]
    $pattern = 'href="(?<href>/{0}/{1}/releases/download/{2}/(?<name>[^"#?]+))"' -f [regex]::Escape($Owner), [regex]::Escape($Repo), [regex]::Escape($Tag)
    foreach ($match in [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $name = [System.Uri]::UnescapeDataString([string]$match.Groups['name'].Value)
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }
        [void]$assets.Add([PSCustomObject]@{
            name = $name
            browser_download_url = 'https://github.com' + [string]$match.Groups['href'].Value
            size = 0
        })
    }

    return $assets.ToArray()
}

function Invoke-GitHubReleaseCatalogHtmlFallback {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo
    )

    Write-Log 'GitHub API release catalog is rate-limited; falling back to public release feed.'
    $atomUri = 'https://github.com/{0}/{1}/releases.atom' -f $Owner, $Repo
    $atom = Invoke-GitHubWebRequestText -Uri $atomUri
    $entryPattern = '<entry>(?<entry>.*?)</entry>'
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entryMatch in [regex]::Matches($atom, $entryPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $entry = [string]$entryMatch.Groups['entry'].Value
        $tag = ''
        if ($entry -match 'href="https://github\.com/[^/]+/[^/]+/releases/tag/(?<tag>[^"]+)"') {
            $tag = [System.Net.WebUtility]::HtmlDecode([string]$matches['tag'])
        }
        if ([string]::IsNullOrWhiteSpace($tag)) {
            continue
        }

        $title = $tag
        if ($entry -match '<title>(?<title>.*?)</title>') {
            $title = [System.Net.WebUtility]::HtmlDecode([string]$matches['title'])
        }

        $body = ''
        $bodyMatch = [regex]::Match($entry, '<content[^>]*>(?<body>.*?)</content>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($bodyMatch.Success) {
            $body = [System.Net.WebUtility]::HtmlDecode([string]$bodyMatch.Groups['body'].Value)
        }

        $updated = ''
        if ($entry -match '<updated>(?<updated>.*?)</updated>') {
            $updated = [string]$matches['updated']
        }

        $assets = @(Get-GitHubReleaseAssetsFromHtml -Owner $Owner -Repo $Repo -Tag $tag)
        [void]$results.Add([PSCustomObject]@{
            draft = $false
            prerelease = $false
            tag_name = $tag
            name = $title
            html_url = ('https://github.com/{0}/{1}/releases/tag/{2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($tag))
            body = $body
            published_at = $updated
            assets = $assets
        })
    }

    return $results.ToArray()
}

function Invoke-GitHubReleaseCatalogRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo
    )

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'DMeloper-Block-HUD-VersionCatalog'
    }
    $perPage = 100
    $page = 1
    $results = New-Object System.Collections.Generic.List[object]

    try {
        while ($true) {
            $uri = 'https://api.github.com/repos/{0}/{1}/releases?per_page={2}&page={3}' -f $Owner, $Repo, $perPage, $page
            Write-Log ("Fetching releases page {0}: {1}" -f $page, $uri)
            $batch = @(Invoke-RestMethod -Uri $uri -Headers $headers -Method Get)
            Write-Log ("Fetched releases page {0}: count={1}" -f $page, $batch.Count)
            if ($batch.Count -eq 0) {
                break
            }

            foreach ($release in $batch) {
                [void]$results.Add($release)
            }

            if ($batch.Count -lt $perPage) {
                break
            }
            $page++
        }
    }
    catch {
        if (Test-GitHubApiRateLimitException -Exception $_.Exception) {
            return (Invoke-GitHubReleaseCatalogHtmlFallback -Owner $Owner -Repo $Repo)
        }
        throw
    }

    return $results.ToArray()
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

    $releases = Invoke-GitHubReleaseCatalogRequest -Owner ([string]$config.Owner) -Repo ([string]$config.Repo)
    $stableReleases = New-Object System.Collections.Generic.List[object]
    foreach ($release in $releases) {
        if ([bool]$release.draft -or [bool]$release.prerelease) {
            continue
        }
        $tag = [string]$release.tag_name
        $semanticVersion = Convert-ToSemanticVersion -VersionText $tag
        if ($null -eq $semanticVersion) {
            Write-Log ("Skipping non-semantic release tag: {0}" -f $tag) 'WARN'
            continue
        }

        [void]$stableReleases.Add([PSCustomObject]@{
            Release = $release
            Version = $semanticVersion
            Tag = $tag
        })
    }

    if ($stableReleases.Count -eq 0) {
        throw (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.')
    }

    $stableReleaseItems = @($stableReleases | Sort-Object Version -Descending)
    $latestStable = $stableReleaseItems[0]
    $installations = @(Get-InstalledBlockHudVersions -CurrentRoot $resolvedRoot)
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $stableReleaseItems) {
        $release = $entry.Release
        $asset = Find-ReleaseAsset -Release $release -AssetName ([string]$config.AssetName)
        $install = Get-MatchingInstall -Installations $installations -Version $entry.Version
        $hasAsset = ($null -ne $asset)
        $isInstalled = ($null -ne $install)
        $isLatestStable = ($entry.Version.CompareTo($latestStable.Version) -eq 0 -and [string]::Equals([string]$entry.Tag, [string]$latestStable.Tag, [System.StringComparison]::OrdinalIgnoreCase))
        $status = if ($isLatestStable) { 'latest_stable' } elseif (-not $hasAsset) { 'asset_missing' } elseif ($isInstalled) { 'installed' } else { 'available' }

        [void]$items.Add([PSCustomObject]@{
            version = $entry.Version.ToString()
            tag = [string]$entry.Tag
            is_latest_stable = $isLatestStable
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

    return [PSCustomObject]@{
        status = 'OK'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        current_target_root = $resolvedRoot
        provider = [string]$config.Provider
        owner = [string]$config.Owner
        repo = [string]$config.Repo
        language_code = [string]$config.LanguageCode
        asset_name = [string]$config.AssetName
        latest_stable_version = $latestStable.Version.ToString()
        latest_stable_tag = [string]$latestStable.Tag
        releases = $items.ToArray()
    }
}

$catalog = $null
try {
    $catalog = Get-VersionReleaseCatalog
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Release catalog loaded.'
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
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }

    $catalog = [PSCustomObject]@{
        status = 'ERROR'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        current_target_root = [string]$script:ResultPairs['DMEL_SOURCEPATH']
        message = $friendlyMessage
        releases = @()
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
