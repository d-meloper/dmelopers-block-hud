Set-StrictMode -Version 2.0

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
