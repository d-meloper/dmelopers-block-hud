# ImportFromOldVersion helpers - Text variables and compatibility shim

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-TextSmart {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-SkippedSourcePath -Path $Path) {
        return ''
    }

    [byte[]]$bytes = Read-AllBytesShared -Path $Path
    if ($null -eq $bytes) {
        $bytes = [byte[]]@()
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return $script:Utf16LeBom.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    try {
        return $script:StrictUtf8.GetString($bytes)
    }
    catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Write-Utf16Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
)

    Assert-SafeTargetPath -Path $Path
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf16LeBom)
    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension.Equals('.ini', [System.StringComparison]::OrdinalIgnoreCase) -or $extension.Equals('.inc', [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:TouchedRainmeterFiles.Add($Path)
    }
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
)

    Assert-SafeTargetPath -Path $Path
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function Test-PathStartsWith {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Prefix)) {
        return $false
    }

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $normalizedPrefix = [System.IO.Path]::GetFullPath($Prefix).TrimEnd('\', '/')
    return (
        $normalizedPath.Equals($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedPrefix + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedPrefix + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-SystemPSModulePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $systemPrefixes = New-Object System.Collections.Generic.List[string]
    foreach ($prefix in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($prefix)) {
            $systemPrefixes.Add($prefix)
        }
    }

    foreach ($prefix in $systemPrefixes) {
        if (Test-PathStartsWith -Path $Path -Prefix $prefix) {
            return $true
        }
    }

    return $false
}

function Get-UserPSModulePathCandidates {
    $candidates = New-Object System.Collections.Generic.List[object]
    $entries = @([string]$env:PSModulePath -split [regex]::Escape([System.IO.Path]::PathSeparator))

    $index = 0
    foreach ($entry in $entries) {
        $trimmed = ([string]$entry).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $index++
            continue
        }

        try {
            $full = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($trimmed)).TrimEnd('\', '/')
        }
        catch {
            $index++
            continue
        }

        if (Test-SystemPSModulePath -Path $full) {
            $index++
            continue
        }

        $candidates.Add([pscustomobject]@{
            Path = $full
            Index = $index
        })
        $index++
    }

    return @($candidates | Sort-Object -Property Index | ForEach-Object { [string]$_.Path })
}

function Test-SourceInstallerNeedsRootConfigNameCompat {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    $installerPath = Get-BlockHudRuntimeToolPath -Root $SourceRoot -RelativeToolPath 'InstallVersionRelease.ps1' -AllowMissing
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        return $false
    }

    $content = Read-TextSmart -Path $installerPath
    $usesRootConfigName = ($content -match '\bGet-RootConfigName\b')
    $definesRootConfigName = ($content -match '(?m)^\s*function\s+Get-RootConfigName\b')
    return ($usesRootConfigName -and -not $definesRootConfigName)
}

function New-RootConfigNameCompatModuleContent {
    return @'
function Get-RootConfigName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $leaf = Split-Path -Path $Root -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Could not derive a root config name from [$Root]."
    }

    return $leaf
}

Export-ModuleMember -Function Get-RootConfigName
'@
}

function New-RootConfigNameCompatManifestContent {
    return @'
@{
    RootModule = 'DMeloperBlockHudCompat.psm1'
    ModuleVersion = '1.3.9'
    GUID = '7e2698fc-2f2e-4cda-b6e8-b0df5cbf8931'
    Author = 'DMeloper'
    CompanyName = 'DMeloper'
    Copyright = '(c) DMeloper. All rights reserved.'
    Description = 'Compatibility shim for DMeloper Block HUD v1.2.0 skin-manager updates.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-RootConfigName')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
'@
}

function Install-RootConfigNameCompatModule {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    if (-not (Test-SourceInstallerNeedsRootConfigNameCompat -SourceRoot $SourceRoot)) {
        return
    }

    $moduleName = 'DMeloperBlockHudCompat'
    $moduleContent = New-RootConfigNameCompatModuleContent
    $manifestContent = New-RootConfigNameCompatManifestContent
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($basePath in Get-UserPSModulePathCandidates) {
        $moduleDirectory = Join-Path $basePath $moduleName
        $probePath = Join-Path $moduleDirectory '.write-test'
        $modulePath = Join-Path $moduleDirectory ($moduleName + '.psm1')
        $manifestPath = Join-Path $moduleDirectory ($moduleName + '.psd1')

        try {
            if (-not $script:Cmdlet.ShouldProcess($moduleDirectory, 'Install v1.2.0 updater Get-RootConfigName compatibility module')) {
                $errors.Add(("{0}: module install was skipped by ShouldProcess" -f $moduleDirectory))
                continue
            }

            if (-not (Test-Path -LiteralPath $moduleDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
            }

            [System.IO.File]::WriteAllText($probePath, 'ok', $script:Utf8NoBom)
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            [System.IO.File]::WriteAllText($modulePath, $moduleContent, $script:Utf8NoBom)
            [System.IO.File]::WriteAllText($manifestPath, $manifestContent, $script:Utf8NoBom)
            Write-Log ("Installed v1.2.0 updater compatibility module for Get-RootConfigName: {0}" -f $moduleDirectory)
            return
        }
        catch {
            $errors.Add(("{0}: {1}" -f $moduleDirectory, $_.Exception.Message))
        }
        finally {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }

    $detail = if ($errors.Count -gt 0) { $errors -join ' | ' } else { 'No writable user PSModulePath entry was available.' }
    throw "Could not install the v1.2.0 updater compatibility module required for Get-RootConfigName autoload. $detail"
}

function Test-Utf16LeBomStrict {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 2 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xFE) {
        return $false
    }
    if (($bytes.Length % 2) -ne 0) {
        return $false
    }
    if ($bytes.Length -ge 4 -and $bytes[2] -eq 0xFF -and $bytes[3] -eq 0xFE) {
        return $false
    }

    try {
        [void]$script:Utf16LeBom.GetString($bytes)
        return $true
    }
    catch {
        return $false
    }
}

function Validate-TouchedRainmeterFiles {
    $seen = @{}
    foreach ($path in $script:TouchedRainmeterFiles) {
        if ($seen.ContainsKey($path)) {
            continue
        }
        $seen[$path] = $true
        if (-not (Test-Utf16LeBomStrict -Path $path)) {
            throw "Touched Rainmeter file is not valid UTF-16 LE BOM: $path"
        }
    }
}

function New-VariablesMap {
    New-Object System.Collections.Specialized.OrderedDictionary
}

function Set-MapValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowNull()]
        [string]$Value
    )

    if ($Map.Contains($Key)) {
        $Map[$Key] = $Value
    }
    else {
        $Map.Add($Key, $Value)
    }
}

function Normalize-JukeboxPlaybackSourceMode {
    param([AllowNull()][string]$Value)

    $mode = ([string]$Value).Trim().ToLowerInvariant()
    if ($mode -eq 'external') {
        return 'external'
    }

    return 'local'
}

function Normalize-MinecraftSkinModel {
    param([AllowNull()][string]$Value)

    $model = ([string]$Value).Trim().ToLowerInvariant()
    if ($model -eq 'slim' -or $model -eq 'alex') {
        return 'slim'
    }

    return 'wide'
}

function Normalize-ImportedVariableValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowNull()]
        [string]$Value
    )

    if ($Key -eq 'JukeboxPlaybackSourceMode') {
        return (Normalize-JukeboxPlaybackSourceMode -Value $Value)
    }
    if ($Key -eq 'MinecraftSkinModel') {
        return (Normalize-MinecraftSkinModel -Value $Value)
    }

    return $Value
}

function Normalize-ImportedVariablesInPlace {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Variables
    )

    if ($Variables.Contains('JukeboxPlaybackSourceMode')) {
        Set-MapValue -Map $Variables -Key 'JukeboxPlaybackSourceMode' -Value (Normalize-JukeboxPlaybackSourceMode -Value $Variables['JukeboxPlaybackSourceMode'])
    }
    if ($Variables.Contains('MinecraftSkinModel')) {
        Set-MapValue -Map $Variables -Key 'MinecraftSkinModel' -Value (Normalize-MinecraftSkinModel -Value $Variables['MinecraftSkinModel'])
    }
}

function Read-VariablesFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $variables = New-VariablesMap
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $variables
    }
    if (Test-SkippedSourcePath -Path $Path) {
        return $variables
    }

    $content = Read-TextSmart -Path $Path
    $inVariables = $false
    foreach ($line in ($content -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inVariables = ($matches[1] -ieq 'Variables')
            continue
        }

        if (-not $inVariables -or $trimmed.Length -eq 0 -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1)
        if ($key.Length -gt 0) {
            Set-MapValue -Map $variables -Key $key -Value $value
        }
    }

    return $variables
}

function ConvertTo-VariablesContent {
    param([Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Variables)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("[Variables]`r`n")
    foreach ($key in $Variables.Keys) {
        [void]$builder.Append($key)
        [void]$builder.Append('=')
        [void]$builder.Append($Variables[$key])
        [void]$builder.Append("`r`n")
    }

    return $builder.ToString()
}

function Merge-VariablesFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [switch]$SameKeysOnly,
        [string[]]$ExcludeKeyPatterns = @(),
        [System.Collections.Specialized.OrderedDictionary]$Backfill,
        [switch]$BackfillBeforeMerge,
        [hashtable]$ImageRenameMap
    )

    $targetVariables = Read-VariablesFile -Path $TargetPath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Log "Skipped missing source variables: $SourcePath"
        if ($Backfill) {
            foreach ($key in $Backfill.Keys) {
                if (-not $targetVariables.Contains($key)) {
                    Set-MapValue -Map $targetVariables -Key $key -Value $Backfill[$key]
                }
            }

            Normalize-ImportedVariablesInPlace -Variables $targetVariables
            $backfillContent = ConvertTo-VariablesContent -Variables $targetVariables
            $null = Invoke-MigrationAction -Action 'Backfill variables' -Target $TargetPath -ScriptBlock {
                Write-Utf16Text -Path $TargetPath -Content $backfillContent
            }
        }
        return
    }

    $sourceVariables = Read-VariablesFile -Path $SourcePath

    if ($Backfill -and $BackfillBeforeMerge) {
        foreach ($key in $Backfill.Keys) {
            if (-not $targetVariables.Contains($key)) {
                Set-MapValue -Map $targetVariables -Key $key -Value $Backfill[$key]
            }
        }
    }

    foreach ($key in $sourceVariables.Keys) {
        $excluded = $false
        foreach ($pattern in $ExcludeKeyPatterns) {
            if ($key -match $pattern) {
                $excluded = $true
                break
            }
        }
        if ($excluded) {
            continue
        }

        if ($SameKeysOnly -and -not $targetVariables.Contains($key)) {
            continue
        }

        $value = $sourceVariables[$key]
        if ($key -match '_Image$') {
            $value = Repair-ImportImageValue -Value $value -ImageRenameMap $ImageRenameMap
        }
        $value = Normalize-ImportedVariableValue -Key $key -Value $value

        Set-MapValue -Map $targetVariables -Key $key -Value $value
    }

    if ($Backfill -and -not $BackfillBeforeMerge) {
        foreach ($key in $Backfill.Keys) {
            if (-not $targetVariables.Contains($key)) {
                Set-MapValue -Map $targetVariables -Key $key -Value $Backfill[$key]
            }
        }
    }

    Normalize-ImportedVariablesInPlace -Variables $targetVariables
    $content = ConvertTo-VariablesContent -Variables $targetVariables
    $null = Invoke-MigrationAction -Action 'Merge variables' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Get-HerobrineStatsKeys {
    return @(
        'HerobrineTotalAppearances',
        'HerobrineVisibleSeconds',
        'HerobrineCaptures'
    )
}

function New-HerobrineStatsDefaultVariables {
    $variables = New-VariablesMap
    foreach ($key in Get-HerobrineStatsKeys) {
        Set-MapValue -Map $variables -Key $key -Value '0'
    }

    return $variables
}

function Normalize-HerobrineStatsCounterValue {
    param([AllowNull()][string]$Value)

    $text = ([string]$Value).Trim()
    if ($text -match '^\d+$') {
        return $text
    }

    return '0'
}

function Merge-HerobrineStatsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $mergedVariables = New-HerobrineStatsDefaultVariables
    if (Test-SkippedSourcePath -Path $SourcePath) {
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            Write-Log "Skipped unreadable source Herobrine stats and preserved current target data: $SourcePath" 'WARN'
            return
        }
        Write-Log "Initialized missing target Herobrine stats with current defaults because the source file was marked unreadable during preflight: $TargetPath" 'WARN'
    }
    elseif (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
        $sourceVariables = Read-VariablesFile -Path $SourcePath
        foreach ($key in Get-HerobrineStatsKeys) {
            if ($sourceVariables.Contains($key)) {
                Set-MapValue -Map $mergedVariables -Key $key -Value (Normalize-HerobrineStatsCounterValue -Value $sourceVariables[$key])
            }
        }

        Write-Log 'Imported Herobrine stats counters into the current persistent extra-content schema.'
    }
    else {
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            Write-Log "Source Herobrine stats are absent; preserved current target data: $TargetPath"
            return
        }
        Write-Log "Initialized missing target Herobrine stats with current defaults: $TargetPath"
    }

    $content = ConvertTo-VariablesContent -Variables $mergedVariables
    $null = Invoke-MigrationAction -Action 'Merge Herobrine stats' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}

function Get-HerobrineStateKeys {
    return @(
        'HerobrineApparitionActive',
        'HerobrineApparitionX',
        'HerobrineApparitionY',
        'HerobrineApparitionW',
        'HerobrineApparitionH',
        'HerobrineApparitionMessageIndex'
    )
}

function New-HerobrineStateDefaultVariables {
    $variables = New-VariablesMap
    Set-MapValue -Map $variables -Key 'HerobrineApparitionActive' -Value '0'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionX' -Value '0'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionY' -Value '0'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionW' -Value '39'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionH' -Value '57'
    Set-MapValue -Map $variables -Key 'HerobrineApparitionMessageIndex' -Value '0'

    return $variables
}

function Merge-HerobrineStateFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $mergedVariables = New-HerobrineStateDefaultVariables
    if (Test-SkippedSourcePath -Path $SourcePath) {
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            Write-Log "Skipped unreadable source Herobrine apparition state and preserved current target data: $SourcePath" 'WARN'
            return
        }
        Write-Log "Initialized missing target Herobrine apparition state with inactive defaults because the source file was marked unreadable during preflight: $TargetPath" 'WARN'
    }
    elseif (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
        Write-Log "Reset Herobrine apparition state to inactive defaults; source active apparition state is not imported."
    }
    else {
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            Write-Log "Source Herobrine apparition state is absent; preserved current target data: $TargetPath"
            return
        }
        Write-Log "Initialized missing target Herobrine apparition state with inactive defaults: $TargetPath"
    }

    $content = ConvertTo-VariablesContent -Variables $mergedVariables
    $null = Invoke-MigrationAction -Action 'Merge Herobrine state' -Target $TargetPath -ScriptBlock {
        Write-Utf16Text -Path $TargetPath -Content $content
    }
}
