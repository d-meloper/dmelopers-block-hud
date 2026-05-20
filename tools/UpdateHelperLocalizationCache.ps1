[CmdletBinding()]
param(
    [string]$SkinRoot,
    [string]$LanguageCode = ''
)

$ErrorActionPreference = 'Stop'
$utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Normalize-LanguageCode {
    param([string]$Value)

    if (([string]$Value).Trim() -ieq 'en-US') {
        return 'en-US'
    }
    return 'ko-KR'
}

function Read-Utf16Text {
    param([string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return ''
    }
    return [System.IO.File]::ReadAllText($Path, $utf16LeBom)
}

function Read-LanguageCodeFromSettings {
    param([string]$Root)

    $path = [System.IO.Path]::Combine($Root, '@Resources', 'Customs', 'Settings', 'General.inc')
    $content = Read-Utf16Text -Path $path
    $match = [regex]::Match($content, '(?m)^LanguageCode=(.+?)\r?$')
    if (-not $match.Success) {
        return 'ko-KR'
    }
    return (Normalize-LanguageCode -Value $match.Groups[1].Value)
}

function Read-LocStrings {
    param([string]$Path)

    $strings = [ordered]@{}
    $content = Read-Utf16Text -Path $Path
    foreach ($line in ($content -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('[') -or $trimmed.StartsWith(';')) {
            continue
        }
        $parts = $line -split '=', 2
        if ($parts.Length -ne 2) {
            continue
        }
        $key = [string]$parts[0].Trim()
        if (-not $key.StartsWith('Loc_', [System.StringComparison]::Ordinal)) {
            continue
        }
        $strings[$key] = ([string]$parts[1]).TrimEnd("`r")
    }
    return $strings
}

if ([string]::IsNullOrWhiteSpace($SkinRoot)) {
    $SkinRoot = Join-Path $PSScriptRoot '..'
}

$resolvedSkinRoot = Resolve-FullPath -Path $SkinRoot
$resolvedLanguageCode = if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    Read-LanguageCodeFromSettings -Root $resolvedSkinRoot
} else {
    Normalize-LanguageCode -Value $LanguageCode
}

$catalogPath = [System.IO.Path]::Combine($resolvedSkinRoot, '@Resources', 'Localization', 'Languages', ($resolvedLanguageCode + '.inc'))
if (-not [System.IO.File]::Exists($catalogPath)) {
    throw "Localization catalog is missing: $catalogPath"
}

$cachePath = [System.IO.Path]::Combine($resolvedSkinRoot, '@Resources', 'Customs', 'Localization', 'HelperCache.json')
$cacheDirectory = [System.IO.Path]::GetDirectoryName($cachePath)
if (-not [System.IO.Directory]::Exists($cacheDirectory)) {
    [System.IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
}

$cache = [ordered]@{
    languageCode = $resolvedLanguageCode
    generatedAtUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    strings = Read-LocStrings -Path $catalogPath
}

$json = ($cache | ConvertTo-Json -Depth 4)
[System.IO.File]::WriteAllText($cachePath, $json + [Environment]::NewLine, $utf8Bom)
Write-Host ("Helper localization cache updated: {0}" -f $cachePath)
