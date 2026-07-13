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

function Get-VersionCatalogInstallUnavailableDetail {
    param(
        [AllowNull()]$Entry,
        [AllowNull()][string]$TargetVersion,
        [AllowNull()][string]$TargetRoot,
        [switch]$OperationInProgress,
        [switch]$IsCurrent
    )

    $reason = if ($OperationInProgress) { 'catalog-operation-in-progress' } elseif ($null -eq $Entry) { 'latest-entry-missing' } elseif ($IsCurrent) { 'latest-entry-is-current-target' } else { 'latest-entry-not-actionable' }
    $entryVersion = [string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue '')
    $entryTag = [string](Get-ObjectPropertyValue -Object $Entry -Name 'tag' -DefaultValue '')
    $entryVariant = [string](Get-ObjectPropertyValue -Object $Entry -Name 'release_variant' -DefaultValue '')
    $status = [string](Get-ObjectPropertyValue -Object $Entry -Name 'status' -DefaultValue '')
    $assetUrl = [string](Get-ObjectPropertyValue -Object $Entry -Name 'asset_url' -DefaultValue '')
    $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
    $installedPathMatchesCurrent = $false
    if (-not [string]::IsNullOrWhiteSpace($installedPath) -and -not [string]::IsNullOrWhiteSpace($TargetRoot)) {
        $installedPathMatchesCurrent = [string]::Equals((Resolve-FullPath -Path $installedPath -AllowMissing), (Resolve-FullPath -Path $TargetRoot), [System.StringComparison]::OrdinalIgnoreCase)
    }

    [string]::Join("`r`n", @(
        (T 'Helper_VersionManager_Update_LatestCatalogInstallUnavailable' 'The latest version is not available for selected-version installation. Refresh the version list and try again.'), '',
        'Diagnostic: code=update-latest-catalog-install-unavailable',
        ('reason=' + $reason),
        ('entry_version=' + $entryVersion),
        ('entry_tag=' + $entryTag),
        ('entry_variant=' + $entryVariant),
        ('entry_status=' + $status),
        ('target_version=' + [string]$TargetVersion),
        ('target_root=' + [string]$TargetRoot),
        ('installed_path=' + $installedPath),
        ('installed_path_matches_current=' + [string]$installedPathMatchesCurrent),
        ('asset_url_present=' + [string](-not [string]::IsNullOrWhiteSpace($assetUrl)))
    ))
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

    $value = Read-JsonFile -Path (Get-SourceRegistryPath -Root $Root)
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
