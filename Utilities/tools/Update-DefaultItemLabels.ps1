[CmdletBinding()]
param(
    [string]$SkinRoot,
    [string]$LanguageCode = '',
    [switch]$UpdateHelperLocalizationCache
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

. (Join-Path $PSScriptRoot 'DefaultItemLocalization.Common.ps1')

function Resolve-DefaultItemLabelsFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Read-DefaultItemLabelsLanguageCode {
    param([Parameter(Mandatory = $true)][string]$Root)

    $settingsPath = [System.IO.Path]::Combine($Root, '@Resources', 'Customs', 'Settings', 'General.inc')
    $content = Read-DefaultItemLocalizationUtf16Text -Path $settingsPath
    $match = [regex]::Match($content, '(?m)^LanguageCode=(.+?)\r?$')
    if (-not $match.Success) {
        return (Resolve-DefaultItemLocalizationLanguageCode -SkinRoot $Root -LanguageCode '')
    }

    Resolve-DefaultItemLocalizationLanguageCode -SkinRoot $Root -LanguageCode $match.Groups[1].Value
}

$helperLocalizationCacheStatus = ''
$helperLocalizationCacheMessage = ''

try {
    if ([string]::IsNullOrWhiteSpace($SkinRoot)) {
        $SkinRoot = Get-DefaultItemLocalizationSkinRoot -ScriptRoot $PSScriptRoot
    }

    $resolvedSkinRoot = Resolve-DefaultItemLabelsFullPath -Path $SkinRoot
    $resolvedLanguageCode = if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
        Read-DefaultItemLabelsLanguageCode -Root $resolvedSkinRoot
    } else {
        Resolve-DefaultItemLocalizationLanguageCode -SkinRoot $resolvedSkinRoot -LanguageCode $LanguageCode
    }

    if ($UpdateHelperLocalizationCache) {
        try {
            $null = & (Join-Path $PSScriptRoot 'UpdateHelperLocalizationCache.ps1') `
                -SkinRoot $resolvedSkinRoot `
                -LanguageCode $resolvedLanguageCode `
                -InformationAction SilentlyContinue
            $helperLocalizationCacheStatus = 'OK'
        }
        catch {
            $helperLocalizationCacheStatus = 'WARN'
            $helperLocalizationCacheMessage = [string]$_.Exception.Message
        }
    }

    $result = Invoke-DefaultItemLabelLocalization -SkinRoot $resolvedSkinRoot -LanguageCode $resolvedLanguageCode

    Write-Output 'DMEL_STATUS=OK'
    Write-Output ('DMEL_LANGUAGECODE={0}' -f $result.LanguageCode)
    Write-Output ('DMEL_CHANGEDCOUNT={0}' -f $result.ChangedLabelCount)
    Write-Output ('DMEL_CHANGEDFILES={0}' -f (($result.ChangedFiles | ForEach-Object { [string]$_ }) -join '|'))
    if ($UpdateHelperLocalizationCache) {
        Write-Output ('DMEL_CACHESTATUS={0}' -f $helperLocalizationCacheStatus)
        if (-not [string]::IsNullOrWhiteSpace($helperLocalizationCacheMessage)) {
            Write-Output ('DMEL_CACHEMESSAGE={0}' -f $helperLocalizationCacheMessage)
        }
    }
}
catch {
    Write-Output 'DMEL_STATUS=ERROR'
    Write-Output ('DMEL_MESSAGE={0}' -f ([string]$_.Exception.Message))
    if ($UpdateHelperLocalizationCache) {
        Write-Output ('DMEL_CACHESTATUS={0}' -f $helperLocalizationCacheStatus)
        if (-not [string]::IsNullOrWhiteSpace($helperLocalizationCacheMessage)) {
            Write-Output ('DMEL_CACHEMESSAGE={0}' -f $helperLocalizationCacheMessage)
        }
    }
    exit 1
}
