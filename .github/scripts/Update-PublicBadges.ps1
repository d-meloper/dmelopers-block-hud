[CmdletBinding()]
param(
    [string]$RepoSlug = 'd-meloper/dmelopers-block-hud',
    [string]$BadgeBranch = 'badges',
    [string]$AppId = $env:DMEL_BADGE_APP_ID,
    [string]$AppPrivateKey = $env:DMEL_BADGE_APP_PRIVATE_KEY,
    [string]$AppInstallationId = $env:DMEL_BADGE_APP_INSTALLATION_ID,
    [string]$OutputDirectory,
    [switch]$NoPush,
    [switch]$SkipCamoPurge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AllowedBadgeFiles = @(
    'release.svg',
    'downloads.svg',
    'stars.svg',
    'badge-data.json'
)

function ConvertTo-Base64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertTo-JsonSegment {
    param([Parameter(Mandatory = $true)][object]$Value)

    $json = $Value | ConvertTo-Json -Compress
    return ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($json))
}

function Get-GitHubAppToken {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$PrivateKey,
        [Parameter(Mandatory = $true)][string]$InstallationId
    )

    if ([string]::IsNullOrWhiteSpace($AppId) -or [string]::IsNullOrWhiteSpace($PrivateKey) -or [string]::IsNullOrWhiteSpace($InstallationId)) {
        throw 'Badge GitHub App secrets are required for branch updates.'
    }

    $normalizedPrivateKey = $PrivateKey.Trim() -replace '\\n', "`n"
    $now = [DateTimeOffset]::UtcNow
    $header = ConvertTo-JsonSegment -Value @{ alg = 'RS256'; typ = 'JWT' }
    $payload = ConvertTo-JsonSegment -Value @{
        iat = [int]$now.AddMinutes(-1).ToUnixTimeSeconds()
        exp = [int]$now.AddMinutes(9).ToUnixTimeSeconds()
        iss = $AppId
    }
    $unsignedToken = "$header.$payload"

    $rsa = [Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($normalizedPrivateKey.ToCharArray())
        $signature = $rsa.SignData(
            [Text.Encoding]::UTF8.GetBytes($unsignedToken),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    }
    finally {
        $rsa.Dispose()
    }

    $jwt = "$unsignedToken.$(ConvertTo-Base64Url -Bytes $signature)"
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "https://api.github.com/app/installations/$InstallationId/access_tokens" `
        -Headers @{
            Authorization = "Bearer $jwt"
            Accept = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent' = 'DMeloper-Block-HUD-Badge-Automation'
        }

    if ([string]::IsNullOrWhiteSpace([string]$response.token)) {
        throw 'GitHub App installation token response did not include a token.'
    }
    return [string]$response.token
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Token
    )

    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'DMeloper-Block-HUD-Badge-Automation'
    }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }
    $result = Invoke-RestMethod -Method Get -Uri "https://api.github.com/$Path" -Headers $headers
    if ($result -is [Array]) {
        foreach ($item in $result) {
            Write-Output $item
        }
        return
    }
    return $result
}

function Get-AllStableReleases {
    param(
        [Parameter(Mandatory = $true)][string]$RepoSlug,
        [string]$Token
    )

    $all = New-Object System.Collections.Generic.List[object]
    $page = 1
    while ($true) {
        $items = @(Invoke-GitHubApi -Path "repos/$RepoSlug/releases?per_page=100&page=$page" -Token $Token)
        if ($items.Count -eq 0) {
            break
        }
        foreach ($item in $items) {
            if (-not [bool]$item.draft -and -not [bool]$item.prerelease) {
                [void]$all.Add($item)
            }
        }
        if ($items.Count -lt 100) {
            break
        }
        $page++
    }
    return $all.ToArray()
}

function Get-SemanticVersionKey {
    param([Parameter(Mandatory = $true)][string]$TagName)

    if ($TagName -notmatch '^v?([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+.*)?$') {
        return $null
    }
    return [PSCustomObject]@{
        Major = [int]$Matches[1]
        Minor = [int]$Matches[2]
        Patch = [int]$Matches[3]
    }
}

function Get-LatestStableRelease {
    param([Parameter(Mandatory = $true)][object[]]$Releases)

    $semantic = @(
        foreach ($release in $Releases) {
            $key = Get-SemanticVersionKey -TagName ([string]$release.tag_name)
            if ($null -ne $key) {
                [PSCustomObject]@{
                    Release = $release
                    Major = $key.Major
                    Minor = $key.Minor
                    Patch = $key.Patch
                    PublishedAt = [DateTimeOffset]::Parse([string]$release.published_at)
                }
            }
        }
    )
    if ($semantic.Count -gt 0) {
        return ($semantic | Sort-Object Major, Minor, Patch, PublishedAt -Descending | Select-Object -First 1).Release
    }
    return ($Releases | Sort-Object { [DateTimeOffset]::Parse([string]$_.published_at) } -Descending | Select-Object -First 1)
}

function ConvertTo-DisplayCount {
    param([Parameter(Mandatory = $true)][int]$Value)

    if ($Value -ge 1000000) {
        return ('{0:0.#}M' -f ($Value / 1000000.0))
    }
    if ($Value -ge 1000) {
        return ('{0:0.#}K' -f ($Value / 1000.0))
    }
    return [string]$Value
}

function Escape-SvgText {
    param([Parameter(Mandatory = $true)][string]$Text)

    return [Security.SecurityElement]::Escape($Text)
}

function New-BadgeSvg {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$LabelColor,
        [Parameter(Mandatory = $true)][string]$MessageColor
    )

    if ($Label -notmatch '^[A-Z0-9 _-]+$') {
        throw "Unsafe badge label: $Label"
    }
    if ($Message -notmatch '^[A-Za-z0-9 ._+\-]+$') {
        throw "Unsafe badge message: $Message"
    }
    foreach ($color in @($LabelColor, $MessageColor)) {
        if ($color -notmatch '^[0-9A-Fa-f]{6}$') {
            throw "Unsafe badge color: $color"
        }
    }

    $labelWidth = [Math]::Max(54.0, [Math]::Round(($Label.Length * 8.4) + 18.0, 2))
    $messageWidth = [Math]::Max(40.5, [Math]::Round(($Message.Length * 8.4) + 18.0, 2))
    $width = [Math]::Round($labelWidth + $messageWidth, 2)
    $labelCenter = [Math]::Round($labelWidth / 2.0, 2)
    $messageCenter = [Math]::Round($labelWidth + ($messageWidth / 2.0), 2)
    $labelTextLength = [Math]::Round([Math]::Max(1, $Label.Length) * 7.0, 2)
    $messageTextLength = [Math]::Round([Math]::Max(1, $Message.Length) * 7.0, 2)
    $safeLabel = Escape-SvgText -Text $Label
    $safeMessage = Escape-SvgText -Text $Message
    $safeAria = Escape-SvgText -Text "$Label`: $Message"

    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="28" role="img" aria-label="$safeAria">
<title>$safeAria</title>
<g shape-rendering="crispEdges">
<rect width="$labelWidth" height="28" fill="#$LabelColor"/>
<rect x="$labelWidth" width="$messageWidth" height="28" fill="#$MessageColor"/>
</g>
<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="100">
<text transform="scale(.1)" x="$($labelCenter * 10)" y="175" textLength="$($labelTextLength * 10)">$safeLabel</text>
<text transform="scale(.1)" x="$($messageCenter * 10)" y="175" textLength="$($messageTextLength * 10)" font-weight="bold" fill="#333">$safeMessage</text>
</g>
</svg>
"@
}

function Test-SafeBadgeSvg {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Content
    )

    if ($Content.Length -gt 10000) {
        throw "Badge SVG is too large: $Name"
    }
    $forbidden = @(
        '<script',
        '<foreignObject',
        ' onload=',
        ' onclick=',
        ' onerror=',
        'javascript:',
        '<image',
        'href=',
        'xlink:href'
    )
    foreach ($needle in $forbidden) {
        if ($Content.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Unsafe SVG content in $Name`: $needle"
        }
    }
    if ($Content -notmatch '^<svg xmlns="http://www\.w3\.org/2000/svg"') {
        throw "Badge SVG has an unexpected template root: $Name"
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Get-BadgePayload {
    param(
        [Parameter(Mandatory = $true)][string]$RepoSlug,
        [string]$Token
    )

    $repo = Invoke-GitHubApi -Path "repos/$RepoSlug" -Token $Token
    $releases = @(Get-AllStableReleases -RepoSlug $RepoSlug -Token $Token)
    if ($releases.Count -eq 0) {
        throw "No stable GitHub releases found for $RepoSlug."
    }
    $latest = Get-LatestStableRelease -Releases $releases
    $downloadCount = 0
    foreach ($release in $releases) {
        foreach ($asset in @($release.assets)) {
            $downloadCount += [int]$asset.download_count
        }
    }

    return [PSCustomObject]@{
        RepoSlug = $RepoSlug
        GeneratedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        LatestRelease = [string]$latest.tag_name
        LatestReleaseName = [string]$latest.name
        TotalDownloads = $downloadCount
        Stars = [int]$repo.stargazers_count
    }
}

function Write-BadgeFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][object]$Payload
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $releaseSvg = New-BadgeSvg -Label 'RELEASE' -Message ([string]$Payload.LatestRelease) -LabelColor '2F334D' -MessageColor '9FE870'
    $downloadsSvg = New-BadgeSvg -Label 'DOWNLOADS' -Message (ConvertTo-DisplayCount -Value ([int]$Payload.TotalDownloads)) -LabelColor '4A4F63' -MessageColor 'FFB07C'
    $starsSvg = New-BadgeSvg -Label 'STARS' -Message (ConvertTo-DisplayCount -Value ([int]$Payload.Stars)) -LabelColor '2F334D' -MessageColor 'C6C4FF'

    Test-SafeBadgeSvg -Name 'release.svg' -Content $releaseSvg
    Test-SafeBadgeSvg -Name 'downloads.svg' -Content $downloadsSvg
    Test-SafeBadgeSvg -Name 'stars.svg' -Content $starsSvg

    Write-Utf8NoBomFile -Path (Join-Path $Directory 'release.svg') -Content $releaseSvg
    Write-Utf8NoBomFile -Path (Join-Path $Directory 'downloads.svg') -Content $downloadsSvg
    Write-Utf8NoBomFile -Path (Join-Path $Directory 'stars.svg') -Content $starsSvg
    Write-Utf8NoBomFile -Path (Join-Path $Directory 'badge-data.json') -Content (($Payload | ConvertTo-Json -Depth 6) + "`n")
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $output = @(& git -C $WorkingDirectory @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code: $LASTEXITCODE): $($output -join "`n")"
    }
    return ($output -join "`n")
}

function Assert-OnlyAllowedGitChanges {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    $status = Invoke-Git -WorkingDirectory $RepositoryPath -Arguments @('status', '--porcelain=v1') -FailureMessage 'Could not inspect badge branch status'
    $changed = @(
        $status -split "`n" |
            ForEach-Object { $_.TrimEnd() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $path = $_.Substring(3).Trim()
                if ($path.Contains(' -> ')) {
                    $path = ($path -split ' -> ', 2)[1]
                }
                $path -replace '\\', '/'
            }
    )
    foreach ($path in $changed) {
        if ($script:AllowedBadgeFiles -notcontains $path) {
            throw "Badge automation attempted to change a non-badge path: $path"
        }
    }
    return $changed
}

function Assert-OnlyAllowedBadgeTree {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    $files = @(Get-ChildItem -LiteralPath $RepositoryPath -File -Recurse -Force | Where-Object {
        $_.FullName -notmatch '[\\/]\.git([\\/]|$)'
    })
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($RepositoryPath.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($script:AllowedBadgeFiles -notcontains $relative) {
            throw "Badge branch contains a non-badge path: $relative"
        }
    }
}

function Update-BadgeBranch {
    param(
        [Parameter(Mandatory = $true)][string]$RepoSlug,
        [Parameter(Mandatory = $true)][string]$BadgeBranch,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][object]$Payload
    )

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dmel-badges-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $remoteUrl = "https://github.com/$RepoSlug.git"
        $authHeader = 'AUTHORIZATION: basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$Token"))
        Invoke-Git -WorkingDirectory $tempRoot -Arguments @('clone', '--no-checkout', $remoteUrl, 'repo') -FailureMessage 'Badge repository clone failed' | Out-Null
        $repoPath = Join-Path $tempRoot 'repo'
        Invoke-Git -WorkingDirectory $repoPath -Arguments @('config', 'http.https://github.com/.extraheader', $authHeader) -FailureMessage 'Could not configure authenticated git header' | Out-Null
        Invoke-Git -WorkingDirectory $repoPath -Arguments @('config', 'user.name', 'DMeloper Badge Automation') -FailureMessage 'Could not configure git user.name' | Out-Null
        Invoke-Git -WorkingDirectory $repoPath -Arguments @('config', 'user.email', 'badge-automation@users.noreply.github.com') -FailureMessage 'Could not configure git user.email' | Out-Null

        $branchProbe = @(& git -C $repoPath ls-remote --heads origin $BadgeBranch 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect remote badge branch: $($branchProbe -join "`n")"
        }

        if (($branchProbe -join "`n").Trim().Length -gt 0) {
            Invoke-Git -WorkingDirectory $repoPath -Arguments @('checkout', '-B', $BadgeBranch, "origin/$BadgeBranch") -FailureMessage 'Could not check out existing badge branch' | Out-Null
            Assert-OnlyAllowedBadgeTree -RepositoryPath $repoPath
        }
        else {
            Invoke-Git -WorkingDirectory $repoPath -Arguments @('checkout', '--orphan', $BadgeBranch) -FailureMessage 'Could not create orphan badge branch' | Out-Null
            $tracked = @(git -C $repoPath ls-files)
            if ($tracked.Count -gt 0) {
                Invoke-Git -WorkingDirectory $repoPath -Arguments @('rm', '-rf', '--', '.') -FailureMessage 'Could not clear orphan badge branch' | Out-Null
            }
        }

        Write-BadgeFiles -Directory $repoPath -Payload $Payload
        Assert-OnlyAllowedBadgeTree -RepositoryPath $repoPath
        $changed = @(Assert-OnlyAllowedGitChanges -RepositoryPath $repoPath)
        if ($changed.Count -eq 0) {
            Write-Host 'Badge branch is already up to date.'
            return $false
        }

        Invoke-Git -WorkingDirectory $repoPath -Arguments @('add', '--', 'release.svg', 'downloads.svg', 'stars.svg', 'badge-data.json') -FailureMessage 'Could not stage badge files' | Out-Null
        Assert-OnlyAllowedGitChanges -RepositoryPath $repoPath | Out-Null
        Invoke-Git -WorkingDirectory $repoPath -Arguments @('commit', '-m', 'Update public badges') -FailureMessage 'Could not commit badge files' | Out-Null
        Invoke-Git -WorkingDirectory $repoPath -Arguments @('push', 'origin', "HEAD:refs/heads/$BadgeBranch") -FailureMessage 'Could not push badge branch' | Out-Null
        Write-Host "Updated badge branch '$BadgeBranch'."
        return $true
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

function Invoke-CamoPurge {
    param(
        [Parameter(Mandatory = $true)][string]$RepoSlug,
        [Parameter(Mandatory = $true)][string]$BadgeBranch
    )

    $rawBase = "https://raw.githubusercontent.com/$RepoSlug/$BadgeBranch"
    $badgeSources = @(
        "$rawBase/release.svg",
        "$rawBase/downloads.svg",
        "$rawBase/stars.svg"
    )
    $pages = @(
        "https://github.com/$RepoSlug",
        "https://github.com/$RepoSlug/blob/main/README.ko-KR.md"
    )

    foreach ($page in $pages) {
        try {
            $html = (Invoke-WebRequest -Uri $page -UseBasicParsing -TimeoutSec 30).Content
            $matches = [Regex]::Matches($html, '<img[^>]+src="(?<src>https://camo\.githubusercontent\.com/[^"]+)"[^>]+data-canonical-src="(?<canonical>[^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                $canonical = [Net.WebUtility]::HtmlDecode($match.Groups['canonical'].Value)
                if ($badgeSources -contains $canonical) {
                    try {
                        Invoke-WebRequest -Uri $match.Groups['src'].Value -Method 'PURGE' -UseBasicParsing -TimeoutSec 30 | Out-Null
                        Write-Host "Requested Camo purge for $canonical"
                    }
                    catch {
                        Write-Warning "Camo purge failed for $canonical`: $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not inspect rendered README page for Camo purge: $page - $($_.Exception.Message)"
        }
    }
}

$apiToken = $null
if (-not $NoPush) {
    $apiToken = Get-GitHubAppToken -AppId $AppId -PrivateKey $AppPrivateKey -InstallationId $AppInstallationId
}

$payload = Get-BadgePayload -RepoSlug $RepoSlug -Token $apiToken
if ($NoPush) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        throw '-OutputDirectory is required when -NoPush is set.'
    }
    Write-BadgeFiles -Directory $OutputDirectory -Payload $payload
    Write-Host "Wrote badge files to $OutputDirectory"
    return
}

$updated = Update-BadgeBranch -RepoSlug $RepoSlug -BadgeBranch $BadgeBranch -Token $apiToken -Payload $payload
if ($updated -and -not $SkipCamoPurge) {
    Invoke-CamoPurge -RepoSlug $RepoSlug -BadgeBranch $BadgeBranch
}
