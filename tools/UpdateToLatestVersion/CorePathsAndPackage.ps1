# UpdateToLatestVersion helpers - Result path metadata and package roots

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Set-ResultPairValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Convert-ResultPairValueToSingleLine {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $singleLine = [string]$Value
    $singleLine = $singleLine.Replace("`r", ' ').Replace("`n", ' ')
    while ($singleLine.Contains('  ')) {
        $singleLine = $singleLine.Replace('  ', ' ')
    }

    return $singleLine.Trim()
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($Key + '=' + (Convert-ResultPairValueToSingleLine -Value $Value))
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
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] {1}' -f $Level, $Message
    $script:LogMessages.Add($line)
    Write-Host $line
}

function Save-Log {
    try {
        $parent = Split-Path -Parent $script:LogPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'UpdateToLatestVersion' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    }
    catch {
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value ''
        Write-Host ("Log save failed: {0}" -f $_.Exception.Message)
    }
}

function Use-CanonicalHelperLogPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot $PSScriptRoot
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([string]::IsNullOrWhiteSpace($expanded)) {
        throw 'Path is empty.'
    }

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
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    Join-Path $Root $RelativePath
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-TextSmart {
    param([Parameter(Mandatory = $true)][string]$Path)

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Read-IniMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    $inMetadata = $false
    foreach ($line in ((Read-TextSmart -Path $Path) -split "`r?`n")) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inMetadata = ($matches[1] -ieq 'Metadata')
            continue
        }

        if (-not $inMetadata -or [string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) {
            continue
        }

        $parts = $trimmed -split '=', 2
        if ($parts.Length -eq 2) {
            $values[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    return $values
}

function Get-SkinMetadata {
    param([Parameter(Mandatory = $true)][string]$Root)

    $settingsPath = Join-RootPath -Root $Root -RelativePath 'Settings\Settings.ini'
    $metadata = Read-IniMetadata -Path $settingsPath
    $name = if ($metadata.ContainsKey('Name')) { [string]$metadata['Name'] } else { '' }
    $metadataVersion = if ($metadata.ContainsKey('Version')) { [string]$metadata['Version'] } else { '' }
    $appVersion = ''

    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        foreach ($line in ((Read-TextSmart -Path $settingsPath) -split "`r?`n")) {
            $trimmed = ([string]$line).Trim()
            if ($trimmed -match '^AppVersion\s*=\s*(.+?)\s*$') {
                $appVersion = $matches[1].Trim()
                break
            }
        }
    }

    $version = if (-not [string]::IsNullOrWhiteSpace($appVersion)) { $appVersion } else { $metadataVersion }

    return [PSCustomObject]@{
        Name = $name
        Version = $version
        MetadataVersion = $metadataVersion
        AppVersion = $appVersion
    }
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
        if ($line.TrimStart().StartsWith('[') -or $line.TrimStart().StartsWith(';')) {
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

function Get-GeneralSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\General.inc'
}

function Get-SupportSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\Support.inc'
}

function Get-SkinRootReleaseVariant {
    param([Parameter(Mandatory = $true)][string]$Root)

    $general = Read-VariablesFile -Path (Get-GeneralSettingsPath -Root $Root)
    $support = Read-VariablesFile -Path (Get-SupportSettingsPath -Root $Root)
    $languageCode = if ([string]::IsNullOrWhiteSpace([string]$general['LanguageCode'])) { 'en-US' } else { [string]$general['LanguageCode'] }
    $assetPattern = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateReleaseAssetPattern'])) { '' } else { [string]$support['UpdateReleaseAssetPattern'] }

    return (Normalize-BlockHudReleaseVariant `
        -ConfiguredReleaseVariant ([string]$support['UpdateReleaseVariant']) `
        -LanguageCode $languageCode `
        -AssetPattern $assetPattern)
}

function Assert-ExpectedReleaseVariant {
    param(
        [Parameter(Mandatory = $true)][string]$ActualReleaseVariant,
        [AllowNull()][string]$ExpectedReleaseVariant,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        return
    }

    if (-not [string]::Equals($ExpectedReleaseVariant, 'Korea', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($ExpectedReleaseVariant, 'Global', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("ExpectedReleaseVariant must be Korea or Global. value={0}" -f [string]$ExpectedReleaseVariant)
    }
    $expected = Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ExpectedReleaseVariant -LanguageCode '' -AssetPattern ''
    if (-not [string]::Equals($ActualReleaseVariant, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("{0} release variant did not match ExpectedReleaseVariant. expected={1} actual={2}" -f $Context, $expected, $ActualReleaseVariant)
    }
}

function ConvertTo-SkinVersion {
    param(
        [AllowNull()][string]$VersionText,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        throw "$Context metadata version is missing."
    }

    try {
        $normalized = $VersionText.Trim()
        if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(1)
        }
        return [version]$normalized
    }
    catch {
        throw "$Context metadata version is invalid: '$VersionText'."
    }
}

function Test-SkinRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    foreach ($relativePath in @('@Resources\Customs', 'Settings', 'Inventory', 'Hotbar')) {
        if (-not (Test-Path -LiteralPath (Join-RootPath -Root $Root -RelativePath $relativePath) -PathType Container)) {
            return $false
        }
    }

    return $true
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

function Resolve-PackageRoot {
    param([Parameter(Mandatory = $true)][string]$ExtractRoot)

    if (Test-SkinRoot -Root $ExtractRoot) {
        return $ExtractRoot
    }

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($directory in Get-ChildItem -LiteralPath $ExtractRoot -Directory -Force -ErrorAction SilentlyContinue) {
        if (Test-SkinRoot -Root $directory.FullName) {
            $matches.Add((Resolve-FullPath -Path $directory.FullName))
        }
    }

    if ($matches.Count -eq 1) {
        return $matches[0]
    }
    if ($matches.Count -gt 1) {
        throw 'Extracted package contains more than one valid Block HUD skin root.'
    }

    throw 'Extracted package did not contain a valid Block HUD skin root.'
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

function Get-RainmeterExecutablePath {
    $runningPath = Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
        Select-Object -First 1 -ExpandProperty Path
    if ($runningPath -and (Test-Path -LiteralPath $runningPath)) {
        return [System.IO.Path]::GetFullPath($runningPath)
    }

    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Rainmeter\Rainmeter.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Rainmeter.exe could not be located for post-update refresh.'
}

function Invoke-RainmeterBang {
    param(
        [Parameter(Mandatory = $true)][string]$Bang,
        [string[]]$Arguments = @()
    )

    $rainmeterExe = Get-RainmeterExecutablePath
    $argList = @($Bang) + @($Arguments)
    & $rainmeterExe @argList | Out-Null
    $exitCode = $LASTEXITCODE
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        throw ("Rainmeter bang failed with exit code {0}: {1}" -f $exitCode, ($argList -join ' '))
    }
}

function Get-RainmeterSkinsRoot {
    param([Parameter(Mandatory = $true)][string]$CurrentRoot)

    $configPath = Get-RainmeterConfigPath
    if (-not [string]::IsNullOrWhiteSpace($configPath)) {
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
                return (Resolve-FullPath -Path $matches[1].Trim())
            }
        }
    }

    $fallbackRoot = Split-Path -Parent $CurrentRoot
    if ([string]::IsNullOrWhiteSpace($fallbackRoot)) {
        throw 'Rainmeter SkinPath could not be resolved.'
    }

    Write-Log ("Rainmeter SkinPath could not be read; falling back to current root parent: {0}" -f $fallbackRoot) 'WARN'
    return (Resolve-FullPath -Path $fallbackRoot)
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = (Resolve-FullPath -Path $Root).TrimEnd('\', '/').ToLowerInvariant()
    $pathFull = (Resolve-FullPath -Path $Path -AllowMissing).TrimEnd('\', '/').ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Convert-ToSafeFolderName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $trimmed = $Name.Trim()
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $trimmed = $trimmed.Replace([string]$character, '_')
    }

    while ($trimmed.Contains('  ')) {
        $trimmed = $trimmed.Replace('  ', ' ')
    }

    $trimmed = $trimmed.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'Package identity resolved to an empty folder name.'
    }

    return $trimmed
}

function Get-PackageIdentityName {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)]$PackageMetadata,
        [Parameter(Mandatory = $true)][string]$ExtractRoot
    )

    $identity = [System.IO.Path]::GetFileName($PackageRoot.TrimEnd('\', '/'))
    if ([string]::Equals((Resolve-FullPath -Path $PackageRoot), (Resolve-FullPath -Path $ExtractRoot), [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageMetadata.Name)) {
        $identity = [string]$PackageMetadata.Name
    }

    $identity = $identity -replace '\s+(?i:settings)$', ''
    $identity = $identity -replace '\s+[vV]?\d+(\.\d+){1,3}.*$', ''
    return (Convert-ToSafeFolderName -Name $identity)
}

function Resolve-LatestDestinationRoot {
    param(
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [Parameter(Mandatory = $true)][string]$IdentityName
    )

    $folderName = Convert-ToSafeFolderName -Name $IdentityName
    return (Resolve-FullPath -Path (Join-Path $SkinsRoot $folderName) -AllowMissing)
}
