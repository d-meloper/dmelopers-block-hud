$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)

function Normalize-LanguageCode {
    param(
        [string]$LanguageCode,
        [string]$SkinRoot = ''
    )

    $registry = Read-LanguageRegistry -SkinRoot $SkinRoot
    $resolved = Resolve-RegisteredLanguageCode -Registry $registry -Value $LanguageCode -Fallback $registry.DefaultFallbackLanguageCode
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        return $resolved
    }

    'en-US'
}

function Get-LanguageRegistryPath {
    param([string]$SkinRoot)

    if ([string]::IsNullOrWhiteSpace($SkinRoot)) {
        $SkinRoot = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
    }

    return [System.IO.Path]::Combine($SkinRoot, '@Resources', 'Localization', 'LanguageRegistry.inc')
}

function Read-RainmeterVariablesFromText {
    param([string]$Content)

    $variables = [ordered]@{}
    $inVariables = $false
    foreach ($line in (([string]$Content) -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
            $inVariables = $trimmed.Equals('[Variables]', [System.StringComparison]::OrdinalIgnoreCase)
            continue
        }
        if (-not $inVariables -or [string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) {
            continue
        }
        $separator = $line.IndexOf('=')
        if ($separator -lt 0) {
            continue
        }
        $variables[$line.Substring(0, $separator).Trim()] = $line.Substring($separator + 1).TrimEnd("`r")
    }
    return $variables
}

function Read-LanguageRegistry {
    param([string]$SkinRoot = '')

    $path = Get-LanguageRegistryPath -SkinRoot $SkinRoot
    $variables = Read-RainmeterVariablesFromText -Content (Read-Utf16Text -Path $path)
    $fallback = if ($variables.Contains('DefaultFallbackLanguageCode') -and -not [string]::IsNullOrWhiteSpace([string]$variables['DefaultFallbackLanguageCode'])) {
        [string]$variables['DefaultFallbackLanguageCode']
    } else {
        'en-US'
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $count = 0
    [void][int]::TryParse([string]$variables['LanguageCount'], [ref]$count)
    for ($index = 1; $index -le $count; $index++) {
        $prefix = "Language_${index}_"
        $code = if ($variables.Contains("${prefix}Code")) { ([string]$variables["${prefix}Code"]).Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($code)) {
            continue
        }
        $displayName = if ($variables.Contains("${prefix}DisplayName")) { [string]$variables["${prefix}DisplayName"] } else { $code }
        $inventoryLabel = if ($variables.Contains("${prefix}InventoryLabel")) { [string]$variables["${prefix}InventoryLabel"] } else { '' }
        [void]$entries.Add([PSCustomObject]@{
            Code = $code
            DisplayName = $displayName
            InventoryLabel = $inventoryLabel
        })
    }

    $entryArray = @($entries.ToArray())
    [PSCustomObject]@{
        Path = $path
        DefaultFallbackLanguageCode = $fallback
        Entries = $entryArray
    }
}

function Resolve-RegisteredLanguageCode {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [AllowNull()][string]$Value,
        [AllowNull()][string]$Fallback
    )

    $candidate = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = ([string]$Fallback).Trim()
    }
    $candidateLower = $candidate.ToLowerInvariant()

    foreach ($entry in @($Registry.Entries)) {
        $code = [string]$entry.Code
        if ($candidateLower -eq $code.ToLowerInvariant()) {
            return $code
        }
        $baseAlias = ($code -split '[-_]', 2)[0]
        if (-not [string]::IsNullOrWhiteSpace($baseAlias) -and $candidateLower -eq $baseAlias.ToLowerInvariant()) {
            return $code
        }
        if ($candidateLower -eq ([string]$entry.DisplayName).Trim().ToLowerInvariant()) {
            return $code
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Fallback) -and $Fallback -ne $Value) {
        return (Resolve-RegisteredLanguageCode -Registry $Registry -Value $Fallback -Fallback '')
    }

    if (@($Registry.Entries).Count -gt 0) {
        return [string]$Registry.Entries[0].Code
    }

    ''
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
        return (Normalize-LanguageCode -LanguageCode '' -SkinRoot $SkinRoot)
    }

    $value = ([string]$match.Groups[1].Value).Trim()
    return (Normalize-LanguageCode -LanguageCode $value -SkinRoot $SkinRoot)
}

function Get-LocaleFilePath {
    param(
        [string]$SkinRoot,
        [string]$LanguageCode
    )

    $resolved = Normalize-LanguageCode -LanguageCode $LanguageCode -SkinRoot $SkinRoot
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
            $expectedLanguageCode = Normalize-LanguageCode -LanguageCode $LanguageCode -SkinRoot $SkinRoot
            $cacheLanguageCode = Normalize-LanguageCode -LanguageCode ([string]$cache.languageCode) -SkinRoot $SkinRoot
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
