Set-StrictMode -Version 2.0

function ConvertTo-BlockHudReleaseArray {
    param([AllowNull()]$Response)

    if ($null -eq $Response) {
        return @()
    }
    if ($Response -is [System.Array]) {
        return @($Response)
    }

    $tagProperty = $Response.PSObject.Properties['tag_name']
    if ($null -ne $tagProperty -and $tagProperty.Value -is [System.Array]) {
        $count = @($tagProperty.Value).Count
        $items = New-Object System.Collections.Generic.List[object]
        for ($index = 0; $index -lt $count; $index++) {
            $item = [ordered]@{}
            foreach ($property in $Response.PSObject.Properties) {
                $value = $property.Value
                if ($value -is [System.Array] -and @($value).Count -eq $count) {
                    $item[$property.Name] = @($value)[$index]
                }
                else {
                    $item[$property.Name] = $value
                }
            }
            [void]$items.Add([PSCustomObject]$item)
        }
        return $items.ToArray()
    }

    return @($Response)
}

function ConvertTo-BlockHudSemanticVersion {
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

function Get-BlockHudReleaseVariantForLanguageCode {
    param([AllowNull()][string]$LanguageCode)

    if ([string]::Equals(([string]$LanguageCode).Trim(), 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Korea'
    }

    return 'Global'
}

function Normalize-BlockHudReleaseVariant {
    param(
        [AllowNull()][string]$ConfiguredReleaseVariant,
        [AllowNull()][string]$LanguageCode,
        [AllowNull()][string]$AssetPattern
    )

    $configured = ([string]$ConfiguredReleaseVariant).Trim()
    if ([string]::Equals($configured, 'Korea', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Korea'
    }
    if ([string]::Equals($configured, 'Global', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Global'
    }

    $asset = ([string]$AssetPattern).Trim()
    if ($asset -match '(?i)(^|[_\-.])Korea([_\-.]|$)') {
        return 'Korea'
    }
    if ($asset -match '(?i)(^|[_\-.])Global([_\-.]|$)') {
        return 'Global'
    }

    return (Get-BlockHudReleaseVariantForLanguageCode -LanguageCode $LanguageCode)
}

function Get-BlockHudFixedUpdateZipAssetName {
    param(
        [AllowNull()][string]$ReleaseVariant,
        [AllowNull()][string]$LanguageCode
    )

    $variant = Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ReleaseVariant -LanguageCode $LanguageCode -AssetPattern ''
    if ([string]::Equals($variant, 'Korea', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'DMelopers-Block-HUD_Korea.zip'
    }

    return 'DMelopers-Block-HUD_Global.zip'
}

function Test-BlockHudReleaseAssetNameMatch {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedName,
        [Parameter(Mandatory = $true)][string]$ActualName
    )

    return [string]::Equals($ExpectedName, $ActualName, [System.StringComparison]::OrdinalIgnoreCase)
}

function Find-BlockHudReleaseAssetByName {
    param(
        [AllowNull()]$Release,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    foreach ($asset in @($Release.assets)) {
        if (Test-BlockHudReleaseAssetNameMatch -ExpectedName $AssetName -ActualName ([string]$asset.name)) {
            return $asset
        }
    }

    return $null
}

function Test-BlockHudGitHubApiRateLimitException {
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

function Invoke-BlockHudGitHubWebRequestText {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager',
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 15
    )

    $headers = @{
        'User-Agent' = $UserAgent
    }
    $response = Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSeconds
    return [string]$response.Content
}

function Invoke-BlockHudGitHubRestMethodArray {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)]$Headers,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 15
    )

    $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -TimeoutSec $TimeoutSeconds
    return @(ConvertTo-BlockHudReleaseArray -Response $response)
}

function Invoke-BlockHudGitHubReleaseAssetDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager',
        [ValidateRange(5, 3600)][int]$TimeoutSeconds = 1800
    )

    $headers = @{
        'User-Agent' = $UserAgent
    }
    Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSeconds
}

function Get-BlockHudGitHubReleaseAssetsFromHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager'
    )

    $assetsUri = 'https://github.com/{0}/{1}/releases/expanded_assets/{2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($Tag)
    $html = Invoke-BlockHudGitHubWebRequestText -Uri $assetsUri -UserAgent $UserAgent
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

function Get-BlockHudGitHubReleasePrereleaseFromHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager',
        [scriptblock]$Log
    )

    $tagUri = 'https://github.com/{0}/{1}/releases/tag/{2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($Tag)
    try {
        $html = Invoke-BlockHudGitHubWebRequestText -Uri $tagUri -UserAgent $UserAgent
    }
    catch {
        if ($Log) {
            & $Log ("Could not verify release prerelease state from public HTML for {0}; excluding it from fallback stable selection. {1}" -f $Tag, $_.Exception.Message) 'WARN'
        }
        return $null
    }

    $preReleaseLabelPattern = '<span\b[^>]*class="[^"]*\bLabel\b[^"]*\bLabel--warning\b[^"]*"[^>]*>\s*Pre-release\s*</span>'
    return [regex]::IsMatch($html, $preReleaseLabelPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Invoke-BlockHudGitHubReleaseCatalogHtmlFallback {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager',
        [scriptblock]$Log
    )

    if ($Log) {
        & $Log 'GitHub API release catalog request is rate-limited; falling back to public release feed.' 'WARN'
    }

    $atomUri = 'https://github.com/{0}/{1}/releases.atom' -f $Owner, $Repo
    $atom = Invoke-BlockHudGitHubWebRequestText -Uri $atomUri -UserAgent $UserAgent
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
            $body = [regex]::Replace($body, '<[^>]+>', ' ')
            $body = [regex]::Replace($body, '\s+', ' ').Trim()
        }

        $updated = ''
        if ($entry -match '<updated>(?<updated>.*?)</updated>') {
            $updated = [string]$matches['updated']
        }

        $assets = @(Get-BlockHudGitHubReleaseAssetsFromHtml -Owner $Owner -Repo $Repo -Tag $tag -UserAgent $UserAgent)
        $prerelease = Get-BlockHudGitHubReleasePrereleaseFromHtml -Owner $Owner -Repo $Repo -Tag $tag -UserAgent $UserAgent -Log $Log
        if ($null -eq $prerelease) {
            continue
        }
        [void]$results.Add([PSCustomObject]@{
            draft = $false
            prerelease = [bool]$prerelease
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

function Invoke-BlockHudGitHubReleaseCatalogRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager',
        [scriptblock]$Log
    )

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = $UserAgent
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $perPage = 100
    $page = 1
    $results = New-Object System.Collections.Generic.List[object]

    try {
        while ($true) {
            $uri = 'https://api.github.com/repos/{0}/{1}/releases?per_page={2}&page={3}' -f $Owner, $Repo, $perPage, $page
            if ($Log) {
                & $Log ("Fetching releases page {0}: {1}" -f $page, $uri) 'INFO'
            }
            $batch = @(Invoke-BlockHudGitHubRestMethodArray -Uri $uri -Headers $headers)
            if ($Log) {
                & $Log ("Fetched releases page {0}: count={1}" -f $page, $batch.Count) 'INFO'
            }
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
        if (Test-BlockHudGitHubApiRateLimitException -Exception $_.Exception) {
            return (Invoke-BlockHudGitHubReleaseCatalogHtmlFallback -Owner $Owner -Repo $Repo -UserAgent $UserAgent -Log $Log)
        }
        throw
    }

    return $results.ToArray()
}

function Get-BlockHudStableReleaseEntries {
    param(
        [Parameter(Mandatory = $true)][object[]]$Releases,
        [scriptblock]$Log
    )

    $stable = New-Object System.Collections.Generic.List[object]
    foreach ($release in @($Releases)) {
        if ([bool]$release.draft -or [bool]$release.prerelease) {
            continue
        }

        $tag = [string]$release.tag_name
        $semanticVersion = ConvertTo-BlockHudSemanticVersion -VersionText $tag
        if ($null -eq $semanticVersion) {
            if ($Log) {
                & $Log ("Skipping non-semantic release tag: {0}" -f $tag) 'WARN'
            }
            continue
        }

        [void]$stable.Add([PSCustomObject]@{
            Release = $release
            Version = $semanticVersion
            Tag = $tag
        })
    }

    return @($stable.ToArray() | Sort-Object Version -Descending)
}

function Get-BlockHudLatestStableReleaseSelection {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [string]$UserAgent = 'DMeloper-Block-HUD-VersionManager',
        [scriptblock]$Log
    )

    $releases = @(Invoke-BlockHudGitHubReleaseCatalogRequest -Owner $Owner -Repo $Repo -UserAgent $UserAgent -Log $Log)
    $stableItems = @(Get-BlockHudStableReleaseEntries -Releases $releases -Log $Log)
    if ($stableItems.Count -eq 0) {
        return [PSCustomObject]@{
            StableItems = @()
            LatestStable = $null
            LatestAsset = $null
            HasExpectedAsset = $false
        }
    }

    $latestStable = $stableItems[0]
    $asset = Find-BlockHudReleaseAssetByName -Release $latestStable.Release -AssetName $AssetName
    return [PSCustomObject]@{
        StableItems = $stableItems
        LatestStable = $latestStable
        LatestAsset = $asset
        HasExpectedAsset = ($null -ne $asset)
    }
}
