# OpenVersionManager helpers - Configuration registry and installation state

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-ReleaseVariantForLanguageCode {
    param([AllowNull()][string]$LanguageCode)

    return (Get-BlockHudReleaseVariantForLanguageCode -LanguageCode $LanguageCode)
}

function Get-FixedUpdateZipAssetName {
    param([AllowNull()][string]$LanguageCode)

    return (Get-BlockHudFixedUpdateZipAssetName -LanguageCode $LanguageCode)
}

function Get-UpdateConfiguration {
    param([Parameter(Mandatory = $true)][string]$Root)

    $support = Read-VariablesFile -Path (Get-SupportSettingsPath -Root $Root)
    $configuredReleaseVariant = [string]$support['UpdateReleaseVariant']
    $legacyAssetPattern = [string]$support['UpdateReleaseAssetPattern']
    $defaultReleaseVariant = Normalize-BlockHudReleaseVariant `
        -ConfiguredReleaseVariant $configuredReleaseVariant `
        -LanguageCode $script:LanguageCode `
        -AssetPattern $legacyAssetPattern
    $activeAssetPattern = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant $defaultReleaseVariant -LanguageCode $script:LanguageCode

    [PSCustomObject]@{
        Provider = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateProvider'])) { 'github' } else { [string]$support['UpdateProvider'] }
        Owner = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubOwner'])) { 'd-meloper' } else { [string]$support['UpdateGithubOwner'] }
        Repo = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubRepo'])) { 'dmelopers-block-hud' } else { [string]$support['UpdateGithubRepo'] }
        ReleaseVariant = $defaultReleaseVariant
        ConfiguredReleaseVariant = $configuredReleaseVariant
        DefaultReleaseVariant = $defaultReleaseVariant
        LegacyAssetPattern = ''
        AssetPatternKorea = 'DMelopers-Block-HUD_Korea.zip'
        AssetPatternGlobal = 'DMelopers-Block-HUD_Global.zip'
        HasVariantAwareAssetSettings = $true
        ActivePatternField = 'FixedZipAssetName'
        ActiveAssetPattern = $activeAssetPattern
        AssetPattern = $activeAssetPattern
        LanguageCode = $script:LanguageCode
        Channel = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateChannel'])) { 'stable' } else { [string]$support['UpdateChannel'] }
    }
}

function Get-UpdateCache {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Read-VersionManagerUpdateCache -Root $Root)
}

function Save-UpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Cache
    )

    try {
        return (Save-VersionManagerUpdateCache -Root $Root -Cache $Cache)
    }
    catch {
        $normalized = ConvertTo-VersionManagerUpdateCacheObject -Cache $Cache
        Write-JsonFile -Path (Get-UpdateCachePath -Root $Root) -Value $normalized
        return $normalized
    }
}

function Update-UpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Patch
    )

    try {
        return (Update-VersionManagerUpdateCache -Root $Root -Patch $Patch)
    }
    catch {
        $current = Get-UpdateCache -Root $Root
        $merged = Merge-VersionManagerUpdateCache -BaseCache $current -PatchCache $Patch
        Write-JsonFile -Path (Get-UpdateCachePath -Root $Root) -Value $merged
        return $merged
    }
}

function Test-UpdateConfigured {
    param($Config)

    $activePattern = $null
    try {
        $activePattern = Resolve-ActiveUpdateAssetPattern -Config $Config
    }
    catch {
        return $false
    }

    return (
        [string]::Equals([string]$Config.Provider, 'github', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.Owner) -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.Repo) -and
        -not [string]::IsNullOrWhiteSpace([string]$activePattern.AssetPattern)
    )
}

function Get-VersionManagerBadgeProfile {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not [string]::Equals(([string]$Config.Provider).Trim(), 'github', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-provider' -Message 'The configured update provider is not supported by the badge feed.')
    }
    $channel = ([string](Get-ObjectPropertyValue -Object $Config -Name 'Channel' -DefaultValue 'stable')).Trim()
    if (-not [string]::Equals($channel, 'stable', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-channel' -Message 'The badge feed supports only the stable update channel.')
    }
    $repositorySlug = ('{0}/{1}' -f ([string]$Config.Owner).Trim(), ([string]$Config.Repo).Trim()).ToLowerInvariant()
    switch -CaseSensitive ($repositorySlug) {
        'd-meloper/dmelopers-block-hud' {
            return [PSCustomObject]@{
                RepositorySlug = $repositorySlug
                FeedUrl = 'https://raw.githubusercontent.com/d-meloper/dmelopers-block-hud/badges/badge-data.json'
            }
        }
        'oup030416/dmelopers-block-hud-test' {
            return [PSCustomObject]@{
                RepositorySlug = $repositorySlug
                FeedUrl = 'https://raw.githubusercontent.com/oup030416/dmelopers-block-hud-test/badges/badge-data.json'
            }
        }
        default {
            throw (New-UpdateOperationException `
                -ErrorCode 'badge-feed-repository' `
                -Message 'The configured update repository is not an approved Block HUD badge feed.')
        }
    }
}

function ConvertTo-VersionManagerStableComparableVersion {
    param([AllowNull()][string]$VersionText)

    $normalized = ([string]$VersionText).Trim()
    if ($normalized -notmatch '^[vV]?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
        return $null
    }
    $normalized = $normalized -replace '^[vV]', ''
    return (Convert-ToVersion -VersionText $normalized)
}

function Test-VersionManagerBadgeTimestamp {
    param([AllowNull()][string]$Value)

    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        ([string]$Value).Trim(),
        'yyyy-MM-ddTHH:mm:ssZ',
        [System.Globalization.CultureInfo]::InvariantCulture,
        ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal),
        [ref]$parsed)
}

function Get-VersionManagerBadgeRequiredString {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $value = Get-ObjectPropertyValue -Object $Payload -Name $Name -DefaultValue $null
    if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace([string]$value)) {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-format' -Message ("The badge feed field '$Name' must be a non-empty string."))
    }
    return ([string]$value).Trim()
}

function ConvertFrom-VersionManagerBadgePayload {
    param(
        [Parameter(Mandatory = $true)][string]$RawPayload,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Profile
    )

    if ([string]::IsNullOrWhiteSpace($RawPayload)) {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-format' -Message 'The badge feed response was empty.')
    }
    if ($RawPayload.Length -gt 0 -and [int]$RawPayload[0] -eq 0xFEFF) {
        $RawPayload = $RawPayload.Substring(1)
    }

    try {
        $payload = $RawPayload | ConvertFrom-Json
    }
    catch {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-format' -Message 'The badge feed did not contain valid JSON.')
    }

    $schemaVersion = Get-ObjectPropertyValue -Object $payload -Name 'SchemaVersion' -DefaultValue $null
    if ($null -eq $payload -or
        (-not ($schemaVersion -is [int]) -and -not ($schemaVersion -is [long])) -or
        [long]$schemaVersion -lt 3) {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-schema' -Message 'The badge feed schema is not supported.')
    }

    $repositorySlug = [string]$Profile.RepositorySlug
    $advertisedRepositoryProperty = $payload.PSObject.Properties['RepoSlug']
    if ($null -ne $advertisedRepositoryProperty) {
        $advertisedRepository = $advertisedRepositoryProperty.Value
        if (-not ($advertisedRepository -is [string]) -or [string]::IsNullOrWhiteSpace([string]$advertisedRepository)) {
            throw (New-UpdateOperationException -ErrorCode 'badge-feed-repository' -Message 'The advertised badge repository identity was malformed.')
        }
        if (-not [string]::Equals(([string]$advertisedRepository).Trim(), $repositorySlug, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw (New-UpdateOperationException -ErrorCode 'badge-feed-repository' -Message 'The badge feed repository identity did not match the configured repository.')
        }
    }

    $configuredVariant = ([string]$Config.ReleaseVariant).Trim()
    switch ($configuredVariant.ToLowerInvariant()) {
        'korea' {
            $variant = 'Korea'
            $releaseField = 'LatestReleaseKorea'
            $releaseNameField = 'LatestReleaseNameKorea'
            $assetField = 'LatestAssetNameKorea'
            $sha256Field = 'LatestAssetSha256Korea'
            $publishedField = 'LatestPublishedAtUtcKorea'
            $expectedAssetName = 'DMelopers-Block-HUD_Korea.zip'
        }
        'global' {
            $variant = 'Global'
            $releaseField = 'LatestReleaseGlobal'
            $releaseNameField = 'LatestReleaseNameGlobal'
            $assetField = 'LatestAssetNameGlobal'
            $sha256Field = 'LatestAssetSha256Global'
            $publishedField = 'LatestPublishedAtUtcGlobal'
            $expectedAssetName = 'DMelopers-Block-HUD_Global.zip'
        }
        default {
            throw (New-UpdateOperationException -ErrorCode 'badge-feed-variant' -Message 'The configured release variant is not supported by the badge feed.')
        }
    }

    $advertisedTag = Get-VersionManagerBadgeRequiredString -Payload $payload -Name $releaseField
    $version = ConvertTo-VersionManagerStableComparableVersion -VersionText $advertisedTag
    if ($null -eq $version) {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-version' -Message 'The badge feed release is not a stable semantic version.')
    }
    $tag = 'v{0}.{1}.{2}' -f $version.Major, $version.Minor, $version.Build
    $releaseNameValue = Get-ObjectPropertyValue -Object $payload -Name $releaseNameField -DefaultValue $null
    $releaseName = if ($releaseNameValue -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$releaseNameValue)) {
        ([string]$releaseNameValue).Trim()
    }
    else {
        $tag
    }
    $assetName = $expectedAssetName
    $advertisedAssetProperty = $payload.PSObject.Properties[$assetField]
    if ($null -ne $advertisedAssetProperty) {
        $advertisedAsset = $advertisedAssetProperty.Value
        if (-not ($advertisedAsset -is [string]) -or [string]::IsNullOrWhiteSpace([string]$advertisedAsset)) {
            throw (New-UpdateOperationException -ErrorCode 'badge-feed-asset' -Message 'The advertised badge asset identity was malformed.')
        }
        if (-not [string]::Equals(([string]$advertisedAsset).Trim(), $expectedAssetName, [System.StringComparison]::Ordinal)) {
            throw (New-UpdateOperationException -ErrorCode 'badge-feed-asset' -Message 'The badge feed asset did not match the active release variant.')
        }
    }
    $assetSha256 = Get-VersionManagerBadgeRequiredString -Payload $payload -Name $sha256Field
    if ($assetSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw (New-UpdateOperationException -ErrorCode 'badge-feed-checksum' -Message 'The badge feed asset SHA-256 was malformed.')
    }
    $assetSha256 = $assetSha256.ToUpperInvariant()
    $publishedAtUtc = ''
    $publishedValue = Get-ObjectPropertyValue -Object $payload -Name $publishedField -DefaultValue $null
    if ($publishedValue -is [string] -and (Test-VersionManagerBadgeTimestamp -Value ([string]$publishedValue))) {
        $publishedAtUtc = ([string]$publishedValue).Trim()
    }

    $escapedTag = [uri]::EscapeDataString($tag)
    $escapedAssetName = [uri]::EscapeDataString($assetName)
    $releaseUrl = 'https://github.com/{0}/releases/tag/{1}' -f $repositorySlug, $escapedTag
    $assetUrl = 'https://github.com/{0}/releases/download/{1}/{2}' -f $repositorySlug, $escapedTag, $escapedAssetName
    return [PSCustomObject]@{
        RepositorySlug = $repositorySlug
        ReleaseVariant = $variant
        Version = $version
        VersionText = ($tag -replace '^[vV]', '')
        Tag = $tag
        ReleaseName = $releaseName
        ReleaseUrl = $releaseUrl
        AssetName = $assetName
        AssetSha256 = $assetSha256
        AssetUrl = $assetUrl
        PublishedAtUtc = $publishedAtUtc
    }
}

function Invoke-VersionManagerBadgeRequest {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
    )

    $profile = Get-VersionManagerBadgeProfile -Config $Config
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [timespan]::FromSeconds($TimeoutSeconds)
    $response = $null
    $request = $null
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, [string]$profile.FeedUrl)
        $request.Headers.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue
        $request.Headers.CacheControl.NoCache = $true
        $request.Headers.CacheControl.NoStore = $true
        $requestTask = $client.SendAsync($request)
        while (-not $requestTask.IsCompleted) {
            if ($script:VersionManagerWindowClosing) {
                throw (New-UpdateOperationException -ErrorCode 'badge-feed-canceled' -Message 'The badge request was canceled because the Skin manager is closing.')
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }
        $response = $requestTask.GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw (New-UpdateOperationException -ErrorCode ('update-http-' + [int]$response.StatusCode) -Message ("The badge feed request failed with HTTP {0}." -f [int]$response.StatusCode))
        }
        $bodyTask = $response.Content.ReadAsStringAsync()
        while (-not $bodyTask.IsCompleted) {
            if ($script:VersionManagerWindowClosing) {
                throw (New-UpdateOperationException -ErrorCode 'badge-feed-canceled' -Message 'The badge request was canceled because the Skin manager is closing.')
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }
        return (ConvertFrom-VersionManagerBadgePayload -RawPayload $bodyTask.GetAwaiter().GetResult() -Config $Config -Profile $profile)
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        throw (New-UpdateOperationException -ErrorCode 'update-network-timeout' -Message 'The badge feed request exceeded the 15-second deadline.')
    }
    finally {
        if ($null -ne $request) {
            $request.Dispose()
        }
        if ($null -ne $response) {
            $response.Dispose()
        }
        $client.Dispose()
        $handler.Dispose()
    }
}

function ConvertFrom-VersionManagerReleaseAssetIntegrityPayload {
    param(
        [Parameter(Mandatory = $true)][string]$RawPayload,
        [Parameter(Mandatory = $true)][string]$RepositorySlug,
        [Parameter(Mandatory = $true)][string]$TagName,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    try {
        $release = $RawPayload | ConvertFrom-Json
    }
    catch {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-format' -Message 'The GitHub release metadata was not valid JSON.')
    }
    if ($null -eq $release -or [bool]$release.draft -or [bool]$release.prerelease -or
        -not [string]::Equals(([string]$release.tag_name).Trim(), $TagName, [System.StringComparison]::Ordinal)) {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-identity' -Message 'The GitHub release metadata did not match the requested stable release.')
    }

    $assets = @($release.assets | Where-Object { [string]$_.name -ceq $AssetName })
    if ($assets.Count -ne 1) {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-asset' -Message 'The GitHub release must contain exactly one matching ZIP asset.')
    }
    $digest = [string]$assets[0].digest
    if ($digest -notmatch '^sha256:(?<hash>[0-9A-Fa-f]{64})$') {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-digest' -Message 'The GitHub release asset did not expose a valid SHA-256 digest.')
    }
    $assetSha256 = $Matches['hash'].ToUpperInvariant()

    $checksumPattern = '(?im)^SHA256[\t ]+(?<hash>[0-9A-Fa-f]{64})[\t ]+' + [Regex]::Escape($AssetName) + '[\t ]*\r?$'
    $checksumMatches = [Regex]::Matches([string]$release.body, $checksumPattern)
    if ($checksumMatches.Count -ne 1) {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-checksum' -Message 'The release notes did not contain exactly one checksum for the requested ZIP asset.')
    }
    $publishedSha256 = $checksumMatches[0].Groups['hash'].Value.ToUpperInvariant()
    if (-not [string]::Equals($publishedSha256, $assetSha256, [System.StringComparison]::Ordinal)) {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-mismatch' -Message 'The release-note checksum did not match the GitHub asset digest.')
    }

    $expectedUrl = 'https://github.com/{0}/releases/download/{1}/{2}' -f `
        $RepositorySlug, [uri]::EscapeDataString($TagName), [uri]::EscapeDataString($AssetName)
    if (-not [string]::Equals(([string]$assets[0].browser_download_url).Trim(), $expectedUrl, [System.StringComparison]::Ordinal)) {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-url' -Message 'The GitHub release asset URL did not match the approved repository, tag, and asset.')
    }
    return [PSCustomObject]@{
        RepositorySlug = $RepositorySlug
        Tag = $TagName
        AssetName = $AssetName
        AssetUrl = $expectedUrl
        AssetSha256 = $assetSha256
    }
}

function Invoke-VersionManagerReleaseAssetIntegrityRequest {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$TagName,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
    )

    $profile = Get-VersionManagerBadgeProfile -Config $Config
    if ($TagName -notmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-version' -Message 'The requested release tag was not a stable semantic version.')
    }
    $expectedAssetName = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant ([string]$Config.ReleaseVariant) -LanguageCode ([string]$Config.LanguageCode)
    if (-not [string]::Equals($AssetName, $expectedAssetName, [System.StringComparison]::Ordinal)) {
        throw (New-UpdateOperationException -ErrorCode 'release-integrity-asset' -Message 'The requested release asset did not match the configured release variant.')
    }

    $apiUrl = 'https://api.github.com/repos/{0}/releases/tags/{1}' -f $profile.RepositorySlug, [uri]::EscapeDataString($TagName)
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [timespan]::FromSeconds($TimeoutSeconds)
    $request = $null
    $response = $null
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $apiUrl)
        [void]$request.Headers.TryAddWithoutValidation('Accept', 'application/vnd.github+json')
        [void]$request.Headers.TryAddWithoutValidation('X-GitHub-Api-Version', '2022-11-28')
        [void]$request.Headers.TryAddWithoutValidation('User-Agent', 'DMeloper-Block-HUD-Version-Manager')
        $requestTask = $client.SendAsync($request)
        while (-not $requestTask.IsCompleted) {
            if ($script:VersionManagerWindowClosing) {
                throw (New-UpdateOperationException -ErrorCode 'release-integrity-canceled' -Message 'The release integrity request was canceled because the Skin manager is closing.')
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }
        $response = $requestTask.GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw (New-UpdateOperationException -ErrorCode ('update-http-' + [int]$response.StatusCode) -Message ("The release integrity request failed with HTTP {0}." -f [int]$response.StatusCode))
        }
        $bodyTask = $response.Content.ReadAsStringAsync()
        while (-not $bodyTask.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }
        return (ConvertFrom-VersionManagerReleaseAssetIntegrityPayload `
            -RawPayload $bodyTask.GetAwaiter().GetResult() `
            -RepositorySlug ([string]$profile.RepositorySlug) `
            -TagName $TagName `
            -AssetName $AssetName)
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        throw (New-UpdateOperationException -ErrorCode 'update-network-timeout' -Message 'The release integrity request exceeded its deadline.')
    }
    finally {
        if ($null -ne $request) { $request.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-UpdateConfigurationErrorCode {
    param([AllowNull()]$Exception)

    if ($null -eq $Exception) {
        return ''
    }

    $exceptionChain = @()
    $current = $Exception
    while ($null -ne $current) {
        $exceptionChain += ,$current
        $current = $current.InnerException
    }

    foreach ($currentException in $exceptionChain) {
        try {
            if ($currentException.Data -and $currentException.Data.Contains('DMEL_ERROR_CODE')) {
                return [string]$currentException.Data['DMEL_ERROR_CODE']
            }
        }
        catch {
        }
    }

    foreach ($currentException in $exceptionChain) {
        $webStatus = [string](Get-ObjectPropertyValue -Object $currentException -Name 'Status' -DefaultValue '')
        switch ($webStatus) {
            'NameResolutionFailure' { return 'update-network-dns' }
            'ProxyNameResolutionFailure' { return 'update-network-dns' }
            'Timeout' { return 'update-network-timeout' }
            'TrustFailure' { return 'update-network-tls' }
            'SecureChannelFailure' { return 'update-network-tls' }
            'ConnectFailure' { return 'update-network-offline' }
            'SendFailure' { return 'update-network-offline' }
            'ReceiveFailure' { return 'update-network-offline' }
        }
    }

    foreach ($currentException in $exceptionChain) {
        $response = Get-ObjectPropertyValue -Object $currentException -Name 'Response' -DefaultValue $null
        if ($null -eq $response) {
            continue
        }

        $statusCode = $null
        try {
            $statusCode = [int]$response.StatusCode
        }
        catch {
            $statusCode = $null
        }

        if ($null -eq $statusCode) {
            continue
        }

        switch ($statusCode) {
            401 { return 'update-http-unauthorized' }
            403 {
                $messageText = [string]$currentException.Message
                $statusDescription = ''
                try {
                    $statusDescription = [string]$response.StatusDescription
                }
                catch {
                    $statusDescription = ''
                }
                if ($messageText -match '(?i)rate limit') {
                    return 'update-http-rate-limit'
                }
                if ($statusDescription -match '(?i)rate limit') {
                    return 'update-http-rate-limit'
                }
                return 'update-http-forbidden'
            }
            404 { return 'update-http-not-found' }
            408 { return 'update-network-timeout' }
            429 { return 'update-http-rate-limit' }
            default {
                if ($statusCode -ge 500) {
                    return 'update-http-server'
                }
                if ($statusCode -ge 400) {
                    return 'update-http-client'
                }
            }
        }
    }

    $combinedMessage = (($exceptionChain | ForEach-Object { [string]$_.Message }) -join ' | ').ToLowerInvariant()
    if ($combinedMessage -match 'no such host is known|remote name could not be resolved|name or service not known|could not resolve host') {
        return 'update-network-dns'
    }
    if ($combinedMessage -match 'timed out|timeout') {
        return 'update-network-timeout'
    }
    if ($combinedMessage -match 'trust relationship|secure channel|ssl|tls|certificate') {
        return 'update-network-tls'
    }
    if ($combinedMessage -match 'actively refused|unable to connect|connection refused|network is unreachable|unreachable|internet connection') {
        return 'update-network-offline'
    }

    return 'update-unexpected'
}

function New-UpdateOperationException {
    param(
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $messageText = [string]$Message
    if (-not [string]::IsNullOrWhiteSpace($ErrorCode) -and $messageText -notmatch '(?m)^Diagnostic:\s*code=') {
        $messageText = [string]::Join("`r`n", @(
            $messageText,
            '',
            ('Diagnostic: code=' + $ErrorCode)
        ))
    }

    $exception = New-Object System.InvalidOperationException($messageText)
    $exception.Data['DMEL_ERROR_CODE'] = $ErrorCode
    return $exception
}

function Get-UpdateFriendlyMessage {
    param(
        [AllowNull()][string]$ErrorCode,
        [AllowNull()][string]$DefaultMessage,
        [Parameter(Mandatory = $true)][ValidateSet('summary', 'dialog')][string]$Surface
    )

    $normalizedCode = if ([string]::IsNullOrWhiteSpace($ErrorCode)) { 'update-unexpected' } else { $ErrorCode.Trim().ToLowerInvariant() }
    $resolvedDefault = [string]$DefaultMessage

    if ($Surface -eq 'summary') {
        switch ($normalizedCode) {
            'update-source-unconfigured' { return (T 'Helper_VersionManager_Summary_UpdateUnconfigured' 'Update status: update source not configured') }
            'update-no-stable-release' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_NoStableRelease' 'no stable release found')) 'Update status: %1') }
            'update-asset-match-failed' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_AssetMismatch' 'release asset does not match')) 'Update status: %1') }
            'update-asset-url-missing' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_AssetUrlMissing' 'release asset URL is missing')) 'Update status: %1') }
            'update-zip-missing' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_ZipMissing' 'downloaded package is missing')) 'Update status: %1') }
            'update-helper-missing' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_HelperMissing' 'update helper is missing')) 'Update status: %1') }
            'update-latest-catalog-install-unavailable' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_LatestCatalogInstallUnavailable' 'latest catalog row cannot be installed')) 'Update status: %1') }
            'update-network-offline' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Offline' 'internet connection unavailable')) 'Update status: %1') }
            'update-network-dns' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Dns' 'GitHub address could not be resolved')) 'Update status: %1') }
            'update-network-timeout' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Timeout' 'request timed out')) 'Update status: %1') }
            'update-network-tls' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Tls' 'secure connection failed')) 'Update status: %1') }
            'update-http-not-found' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_RepoNotFound' 'GitHub release source not found')) 'Update status: %1') }
            'update-http-unauthorized' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Unauthorized' 'GitHub authentication required')) 'Update status: %1') }
            'update-http-forbidden' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Forbidden' 'GitHub access denied')) 'Update status: %1') }
            'update-http-rate-limit' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_RateLimited' 'GitHub request limit reached')) 'Update status: %1') }
            'update-http-server' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Server' 'GitHub server error')) 'Update status: %1') }
            'update-http-client' { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Client' 'GitHub request failed')) 'Update status: %1') }
            default { return (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @((T 'Helper_VersionManager_Update_ErrorShort_Unexpected' 'unexpected error')) 'Update status: %1') }
        }
    }

    switch ($normalizedCode) {
        'update-source-unconfigured' {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return $resolvedDefault
            }
            return (T 'Helper_VersionManager_Update_SourceUnconfigured' 'The update source is not configured yet.')
        }
        'update-no-stable-release' {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return $resolvedDefault
            }
            return (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.')
        }
        'update-asset-match-failed' {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return $resolvedDefault
            }
            return (T 'Helper_VersionManager_Update_AssetMismatchGeneric' 'The configured release asset could not be selected from the latest release.')
        }
        'update-asset-url-missing' {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return $resolvedDefault
            }
            return (T 'Helper_VersionManager_Update_AssetUrlMissing' 'The latest release asset URL is missing.')
        }
        'update-zip-missing' {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return $resolvedDefault
            }
            return (T 'Helper_VersionManager_Update_ZipMissing' 'The downloaded update ZIP was not found.')
        }
        'update-latest-catalog-install-unavailable' {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return $resolvedDefault
            }
            return (T 'Helper_VersionManager_Update_LatestCatalogInstallUnavailable' 'The latest version is not available for selected-version installation. Refresh the version list and try again.')
        }
        'update-helper-missing' { return (T 'Helper_VersionManager_Update_HelperMissing' 'The update helper file is missing. Reinstall or repair the skin files and try again.') }
        'update-network-offline' { return (T 'Helper_VersionManager_Update_Error_Offline' 'The internet connection is unavailable. Check the connection and try again.') }
        'update-network-dns' { return (T 'Helper_VersionManager_Update_Error_Dns' 'The GitHub address could not be resolved. Check DNS or network settings and try again.') }
        'update-network-timeout' { return (T 'Helper_VersionManager_Update_Error_Timeout' 'The update request timed out. Try again after the network connection stabilizes.') }
        'update-network-tls' { return (T 'Helper_VersionManager_Update_Error_Tls' 'A secure connection to GitHub could not be established. Check system time, certificates, or security software and try again.') }
        'update-http-not-found' { return (T 'Helper_VersionManager_Update_Error_RepoNotFound' 'The configured GitHub release source could not be found. Check the owner, repo, and release asset settings.') }
        'update-http-unauthorized' { return (T 'Helper_VersionManager_Update_Error_Unauthorized' 'GitHub authentication is required for this request. Check the release source or network policy and try again.') }
        'update-http-forbidden' { return (T 'Helper_VersionManager_Update_Error_Forbidden' 'Access to the GitHub release source was denied. Check network policy or repository visibility and try again.') }
        'update-http-rate-limit' { return (T 'Helper_VersionManager_Update_Error_RateLimited' 'The GitHub request limit has been reached. Wait a little and try again.') }
        'update-http-server' { return (T 'Helper_VersionManager_Update_Error_Server' 'GitHub responded with a server error. Try again later.') }
        'update-http-client' { return (T 'Helper_VersionManager_Update_Error_Client' 'GitHub could not process the update request. Check the release source settings and try again.') }
        default {
            if (-not [string]::IsNullOrWhiteSpace($resolvedDefault)) {
                return (TF 'Helper_VersionManager_Update_Error_UnexpectedWithDetail' @($resolvedDefault) 'An unexpected error occurred while processing the update.`r`n`r`n%1')
            }
            return (T 'Helper_VersionManager_Update_Error_Unexpected' 'An unexpected error occurred while processing the update. Check the log and try again.')
        }
    }
}

function Resolve-ActiveUpdateAssetPattern {
    param([Parameter(Mandatory = $true)]$Config)

    $languageCode = [string](Get-ObjectPropertyValue -Object $Config -Name 'LanguageCode' -DefaultValue $script:LanguageCode)
    $releaseVariant = Normalize-BlockHudReleaseVariant `
        -ConfiguredReleaseVariant ([string](Get-ObjectPropertyValue -Object $Config -Name 'ReleaseVariant' -DefaultValue '')) `
        -LanguageCode $languageCode `
        -AssetPattern ([string](Get-ObjectPropertyValue -Object $Config -Name 'ActiveAssetPattern' -DefaultValue ''))
    $assetPattern = [string](Get-ObjectPropertyValue -Object $Config -Name 'ActiveAssetPattern' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($assetPattern)) {
        $assetPattern = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant $releaseVariant -LanguageCode $languageCode
    }

    return [PSCustomObject]@{
        Mode = 'fixed'
        ReleaseVariant = $releaseVariant
        PatternField = 'FixedZipAssetName'
        AssetPattern = $assetPattern
    }
}

function Save-UpdateConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$AssetPattern
    )

    Set-VariablesInFile -Path (Get-SupportSettingsPath -Root $Root) -Values @{
        UpdateProvider = 'github'
        UpdateGithubOwner = 'd-meloper'
        UpdateGithubRepo = $Repo.Trim()
        UpdateReleaseAssetPattern = $AssetPattern.Trim()
        UpdateChannel = 'stable'
    }
}

function Read-SourceRegistry {
    param([Parameter(Mandatory = $true)][string]$Root)

    $path = Get-SourceRegistryPath -Root $Root
    try {
        $value = Read-JsonFile -Path $path
    }
    catch {
        try {
            Write-Log -Level 'WARN' -Message ("Ignoring unreadable version manager source registry '{0}': {1}" -f $path, $_.Exception.Message)
        }
        catch {
        }
        return @()
    }

    if ($null -eq $value) {
        return @()
    }
    return @($value)
}

function Write-SourceRegistry {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Entries
    )

    Write-JsonFile -Path (Get-SourceRegistryPath -Root $Root) -Value $Entries
}

function New-SourceRegistryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Path
    )

    [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString()
        Label = $Label.Trim()
        Path = $Path.Trim()
    }
}

function Get-InstallationStatus {
    param(
        [Parameter(Mandatory = $true)][bool]$IsCurrent,
        [Parameter(Mandatory = $true)][bool]$IsValid,
        [AllowNull()][version]$Version,
        [Parameter(Mandatory = $true)][version]$TargetVersion
    )

    if ($IsCurrent) {
        return [PSCustomObject]@{ Text = T 'Helper_VersionManager_Install_StatusCurrent' 'Current installation'; ImportAllowed = $false }
    }
    if (-not $IsValid -or $null -eq $Version) {
        return [PSCustomObject]@{ Text = T 'Helper_VersionManager_Install_StatusInvalid' 'Path missing or invalid'; ImportAllowed = $false }
    }
    if ($Version -lt [version]'1.1.0') {
        return [PSCustomObject]@{ Text = T 'Helper_VersionManager_Install_StatusTooOld' 'Import unavailable: below v1.1.0'; ImportAllowed = $false }
    }
    if ($Version -gt $TargetVersion) {
        return [PSCustomObject]@{ Text = T 'Helper_VersionManager_Install_StatusTooNew' 'Import unavailable: newer than current'; ImportAllowed = $false }
    }
    return [PSCustomObject]@{ Text = T 'Helper_VersionManager_Install_StatusCompatible' 'Compatible'; ImportAllowed = $true }
}

function Get-Installations {
    param([Parameter(Mandatory = $true)][string]$Root)

    $targetVersionText = Get-SkinMetadataVersion -Root $Root
    $targetVersion = Convert-ToVersion -VersionText $targetVersionText
    if (-not $targetVersion) {
        throw 'Current target version could not be read.'
    }

    $items = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $addItem = {
        param(
            [string]$Path,
            [string]$Label,
            [string]$Source
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return
        }

        $resolvedCandidate = $null
        try {
            $resolvedCandidate = Resolve-SkinRootCandidate -Candidate $Path
        }
        catch {
            $resolvedCandidate = $null
        }

        if (-not $resolvedCandidate) {
            return
        }
        if (-not (Test-VersionManagerDisplayableSkinRoot -Root $resolvedCandidate)) {
            return
        }

        $dedupeKey = $resolvedCandidate
        if (-not $seen.Add($dedupeKey)) {
            return
        }

        $isCurrent = $false
        $isValid = $false
        $version = $null
        $versionText = ''
        $finalPath = $dedupeKey
        $finalPath = $resolvedCandidate
        $isValid = $true
        $isCurrent = [string]::Equals($resolvedCandidate, $Root, [System.StringComparison]::OrdinalIgnoreCase)
        $versionText = Get-SkinMetadataVersion -Root $resolvedCandidate
        $version = Convert-ToVersion -VersionText $versionText
        $status = Get-InstallationStatus -IsCurrent:$isCurrent -IsValid:$isValid -Version $version -TargetVersion $targetVersion
        $items.Add([PSCustomObject]@{
            Label = if ([string]::IsNullOrWhiteSpace($Label)) { Get-SkinRootLabel -Root $finalPath } else { $Label }
            Path = $finalPath
            Source = $Source
            Version = $version
            VersionText = if ($versionText -ne '') { 'v' + $versionText } else { 'v?' }
            Status = $status.Text
            ImportAllowed = [bool]$status.ImportAllowed
            IsCurrent = $isCurrent
            IsReadOnly = ($Source -ne 'manual')
            IsValid = $isValid
        })
    }

    & $addItem -Path $Root -Label (T 'Helper_VersionManager_Install_CurrentSkinLabel' 'Current skin') -Source 'current'

    $skinsRoot = Get-RainmeterSkinsRoot
    if (-not [string]::IsNullOrWhiteSpace($skinsRoot) -and (Test-Path -LiteralPath $skinsRoot -PathType Container)) {
        $skinDirectories = @(Get-ChildItem -LiteralPath $skinsRoot -Directory -Force -ErrorAction SilentlyContinue)
        foreach ($directory in $skinDirectories) {
            & $addItem -Path $directory.FullName -Label $directory.Name -Source 'auto'
        }
    }

    foreach ($entry in @(Read-SourceRegistry -Root $Root)) {
        $label = if ($entry.PSObject.Properties['Label']) { [string]$entry.Label } else { '' }
        $path = if ($entry.PSObject.Properties['Path']) { [string]$entry.Path } else { '' }
        & $addItem -Path $path -Label $label -Source 'manual'
    }

    $sortedItems = @($items | Sort-Object @{ Expression = { if ($_.IsCurrent) { 0 } elseif ($_.Source -eq 'auto') { 1 } else { 2 } } }, @{ Expression = { $_.Version }; Descending = $true }, Label)
    return $sortedItems
}
