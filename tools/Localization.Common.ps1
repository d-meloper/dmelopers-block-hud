$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)

function Normalize-LanguageCode {
    param([string]$LanguageCode)

    if (([string]$LanguageCode).Trim() -ieq 'en-US') {
        return 'en-US'
    }
    return 'ko-KR'
}

function Convert-LocalizationEscapes {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $resolved = [string]$Text
    $resolved = $resolved.Replace('\r\n', "`r`n")
    $resolved = $resolved.Replace('\n', "`n")
    $resolved = $resolved.Replace('\r', "`r")
    $resolved = $resolved.Replace('\t', "`t")
    return $resolved
}

function Get-LocalizationSkinRoot {
    param([string]$ScriptRoot)

    if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
        $ScriptRoot = $PSScriptRoot
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
}

function Get-LanguageCodePath {
    param([string]$SkinRoot)

    return [System.IO.Path]::Combine($SkinRoot, '@Resources', 'Customs', 'Settings', 'General.inc')
}

function Read-Utf16Text {
    param([string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return ''
    }

    return [System.IO.File]::ReadAllText($Path, $utf16LeBom)
}

function Read-LanguageCode {
    param([string]$SkinRoot)

    $content = Read-Utf16Text (Get-LanguageCodePath -SkinRoot $SkinRoot)
    $match = [regex]::Match($content, '(?m)^LanguageCode=(.+?)\r?$')
    if (-not $match.Success) {
        return 'ko-KR'
    }

    $value = ([string]$match.Groups[1].Value).Trim()
    if ($value -ieq 'en-US') {
        return 'en-US'
    }
    return 'ko-KR'
}

function Get-LocaleFilePath {
    param(
        [string]$SkinRoot,
        [string]$LanguageCode
    )

    $resolved = if ($LanguageCode -ieq 'en-US') { 'en-US' } else { 'ko-KR' }
    return [System.IO.Path]::Combine($SkinRoot, '@Resources', 'Localization', 'Languages', ($resolved + '.inc'))
}

function Get-HelperLocalizationCachePath {
    param([string]$SkinRoot)

    return [System.IO.Path]::Combine($SkinRoot, '@Resources', 'Customs', 'Localization', 'HelperCache.json')
}

function Get-BlockHudCanonicalLogFileName {
    return "DMeloper's Block HUD Log.log"
}

function Get-BlockHudCanonicalLogPath {
    param(
        [AllowNull()][string]$Root,
        [AllowNull()][string]$ScriptRoot
    )

    $resolvedRoot = ''
    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        try {
            $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
        }
        catch {
            $resolvedRoot = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
        $resolvedRoot = Get-LocalizationSkinRoot -ScriptRoot $ScriptRoot
    }

    return [System.IO.Path]::Combine($resolvedRoot, 'Logs', (Get-BlockHudCanonicalLogFileName))
}

function Write-BlockHudCanonicalLogBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Type,
        [AllowNull()][object]$Lines,
        [AllowNull()][System.Text.Encoding]$Encoding
    )

    $resolvedEncoding = if ($null -ne $Encoding) { $Encoding } else { $utf8NoBom }
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $parent = [System.IO.Path]::GetDirectoryName($resolvedPath)
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not [System.IO.Directory]::Exists($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine(('<{0}>' -f [string]$Type))
    if ($null -ne $Lines) {
        if (($Lines -is [System.Collections.IEnumerable]) -and -not ($Lines -is [string])) {
            foreach ($line in $Lines) {
                [void]$builder.AppendLine([string]$line)
            }
        }
        else {
            [void]$builder.AppendLine([string]$Lines)
        }
    }
    [void]$builder.AppendLine()

    [System.IO.File]::AppendAllText($resolvedPath, $builder.ToString(), $resolvedEncoding)
    return $resolvedPath
}

function Write-HelperLocalizationCacheWarning {
    param(
        [string]$SkinRoot,
        [string]$Message
    )

    try {
        $logPath = Get-BlockHudCanonicalLogPath -Root $SkinRoot -ScriptRoot $PSScriptRoot
        $line = ('[{0}] [Localization] {1}' -f ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')), [string]$Message)
        [void](Write-BlockHudCanonicalLogBlock -Path $logPath -Type 'Localization' -Lines @($line) -Encoding $utf8NoBom)
    }
    catch {
    }
}

function Read-CanonicalLocaleTable {
    param(
        [string]$SkinRoot,
        [string]$LanguageCode
    )

    $table = @{}
    $localePath = Get-LocaleFilePath -SkinRoot $SkinRoot -LanguageCode $LanguageCode
    if (-not [System.IO.File]::Exists($localePath)) {
        Write-HelperLocalizationCacheWarning -SkinRoot $SkinRoot -Message ("Canonical localization catalog is missing: {0}" -f $localePath)
        return $table
    }

    try {
        $content = Read-Utf16Text -Path $localePath
        foreach ($line in ($content -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) {
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

            $table[$key] = ([string]$parts[1]).TrimEnd("`r")
        }
    }
    catch {
        Write-HelperLocalizationCacheWarning -SkinRoot $SkinRoot -Message ("Canonical localization catalog could not be read: {0}" -f $_.Exception.Message)
    }

    return $table
}

function Read-LocaleTable {
    param(
        [string]$SkinRoot,
        [string]$LanguageCode
    )

    $table = Read-CanonicalLocaleTable -SkinRoot $SkinRoot -LanguageCode $LanguageCode
    $cachePath = Get-HelperLocalizationCachePath -SkinRoot $SkinRoot
    if ([System.IO.File]::Exists($cachePath)) {
        try {
            $raw = [System.IO.File]::ReadAllText($cachePath, $utf8NoBom)
            $cache = $raw | ConvertFrom-Json
            $expectedLanguageCode = Normalize-LanguageCode -LanguageCode $LanguageCode
            $cacheLanguageCode = Normalize-LanguageCode -LanguageCode ([string]$cache.languageCode)
            if ($cacheLanguageCode -eq $expectedLanguageCode -and $null -ne $cache.strings) {
                foreach ($property in $cache.strings.PSObject.Properties) {
                    $propertyName = [string]$property.Name
                    if (-not $table.ContainsKey($propertyName)) {
                        $table[$propertyName] = [string]$property.Value
                    }
                }
            }
        }
        catch {
        }
    }

    return $table
}

function Get-LocalizedText {
    param(
        [hashtable]$Table,
        [string]$Key,
        [string]$Fallback = ''
    )

    $resolvedKey = if ($Key -like 'Loc_*') { $Key } else { 'Loc_' + $Key }
    if ($Table.ContainsKey($resolvedKey)) {
        return (Convert-LocalizationEscapes ([string]$Table[$resolvedKey]))
    }
    return (Convert-LocalizationEscapes ([string]$Fallback))
}

function Format-LocalizedText {
    param(
        [hashtable]$Table,
        [string]$Key,
        [string[]]$Arguments,
        [string]$Fallback = ''
    )

    $text = Get-LocalizedText -Table $Table -Key $Key -Fallback $Fallback
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $text = $text.Replace('%' + ($i + 1), [string]$Arguments[$i])
    }
    return $text
}
