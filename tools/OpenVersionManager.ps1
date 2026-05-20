[CmdletBinding()]
param(
    [string]$TargetRoot,
    [switch]$EmitResultPairs,
    [switch]$WindowSession,
    [string]$LaunchToken
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = ''
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
}
catch {
}
[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.UpdateCache.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.UiState.ps1')

$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot

$script:SkinRootForLocalization = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$script:LanguageCode = Read-LanguageCode -SkinRoot $script:SkinRootForLocalization
$script:LocTable = Read-LocaleTable -SkinRoot $script:SkinRootForLocalization -LanguageCode $script:LanguageCode

function U {
    param([Parameter(Mandatory = $true)][string]$Value)
    [regex]::Unescape($Value)
}

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Fallback = ''
    )

    Get-LocalizedText -Table $script:LocTable -Key $Key -Fallback $Fallback
}

function TF {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object[]]$Arguments,
        [string]$Fallback = ''
    )

    $normalizedArguments = @()
    foreach ($argument in @($Arguments)) {
        $normalizedArguments += ,([string]$argument)
    }

    Format-LocalizedText -Table $script:LocTable -Key $Key -Arguments $normalizedArguments -Fallback $Fallback
}

function Set-ResultPairValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $script:Utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($Key + '=' + [string]$Value)
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
    if ($script:LogMessages.Count -eq 0) {
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
        return
    }

    [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'VersionManager' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Set-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    else {
        $property.Value = $Value
    }
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

function Get-PowerShellExecutablePath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }

    throw 'powershell.exe could not be located.'
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
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

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return $script:Utf16LeBom.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
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

function Get-SkinMetadataVersion {
    param([Parameter(Mandatory = $true)][string]$Root)

    $settingsIni = Join-RootPath -Root $Root -RelativePath 'Settings\Settings.ini'
    if (-not (Test-Path -LiteralPath $settingsIni -PathType Leaf)) {
        return ''
    }

    $content = Read-TextSmart -Path $settingsIni
    $inVariables = $false
    foreach ($rawLine in ($content -split "`r?`n")) {
        $line = [string]$rawLine
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inVariables = ($matches[1] -ieq 'Variables')
            continue
        }
        if ($inVariables -and $trimmed -match '^AppVersion=(.*)$') {
            return [string]$matches[1].Trim()
        }
        if ($trimmed -match '^Version=(.*)$') {
            return [string]$matches[1].Trim()
        }
    }

    return ''
}

function Convert-ToVersion {
    param([AllowNull()][string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    try {
        $normalized = $VersionText.Trim()
        if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(1)
        }
        return [version]$normalized
    }
    catch {
        return $null
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
        if ($line.TrimStart().StartsWith('[')) {
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

function Set-VariablesInFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Values
    )

    $content = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [System.IO.File]::ReadAllText($Path, $script:Utf16LeBom)
    }
    else {
        "[Variables]`r`n"
    }

    foreach ($key in $Values.Keys) {
        $value = [string]$Values[$key]
        $pattern = "(?m)^" + [regex]::Escape($key) + "=.*$"
        if ([regex]::IsMatch($content, $pattern)) {
            $content = [regex]::Replace($content, $pattern, ($key + '=' + $value), 1)
        }
        else {
            if (-not $content.EndsWith("`r`n")) {
                $content += "`r`n"
            }
            $content += ($key + '=' + $value + "`r`n")
        }
    }

    [System.IO.File]::WriteAllText($Path, $content, $script:Utf16LeBom)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $raw = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    $json = $Value | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
}

function Save-VersionManagerLaunchState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$LaunchTokenValue = '',
        [string]$Message = ''
    )

    $payload = [ordered]@{
        LaunchToken = [string]$LaunchTokenValue
        Status = [string]$Status
        Message = [string]$Message
        UpdatedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    }
    Write-JsonFile -Path (Get-VersionManagerLaunchStatePath -Root $Root) -Value $payload
    if (Get-Command Set-VersionManagerSettingsCacheVariables -ErrorAction SilentlyContinue) {
        Set-VersionManagerSettingsCacheVariables -Root $Root -Values ([ordered]@{
            VersionManagerLaunchToken = [string]$payload.LaunchToken
            VersionManagerLaunchStatus = [string]$payload.Status
            VersionManagerLaunchMessage = [string]$payload.Message
        })
    }
}

function Wait-VersionManagerLaunchShown {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ExpectedLaunchToken = '',
        [int]$TimeoutMilliseconds = 5000,
        [int]$PollMilliseconds = 100
    )

    $statePath = Get-VersionManagerLaunchStatePath -Root $Root
    $deadline = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(1, $TimeoutMilliseconds))
    $lastStatus = ''
    $lastMessage = ''
    $lastToken = ''
    do {
        try {
            $state = Read-JsonFile -Path $statePath
            if ($null -ne $state) {
                $lastStatus = [string](Get-ObjectPropertyValue -Object $state -Name 'Status' -DefaultValue '')
                $lastMessage = [string](Get-ObjectPropertyValue -Object $state -Name 'Message' -DefaultValue '')
                $lastToken = [string](Get-ObjectPropertyValue -Object $state -Name 'LaunchToken' -DefaultValue '')
                $tokenMatches = [string]::Equals($lastToken, [string]$ExpectedLaunchToken, [System.StringComparison]::Ordinal)
                if ($tokenMatches -and [string]::Equals($lastStatus, 'shown', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [PSCustomObject]@{
                        Status = 'OK'
                        Message = ''
                        ObservedStatus = $lastStatus
                        ObservedToken = $lastToken
                    }
                }
                if ($tokenMatches -and [string]::Equals($lastStatus, 'error', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [PSCustomObject]@{
                        Status = 'ERROR'
                        Message = $lastMessage
                        ObservedStatus = $lastStatus
                        ObservedToken = $lastToken
                    }
                }
            }
        }
        catch {
            $lastMessage = $_.Exception.Message
        }

        if ([DateTime]::UtcNow -ge $deadline) {
            break
        }
        Start-Sleep -Milliseconds ([Math]::Max(10, $PollMilliseconds))
    } while ($true)

    return [PSCustomObject]@{
        Status = 'WARN'
        Message = ("Skins launch was started, but the window did not report shown before the confirmation timeout. expectedToken={0}; observedToken={1}; observedStatus={2}" -f [string]$ExpectedLaunchToken, $lastToken, $lastStatus)
        ObservedStatus = $lastStatus
        ObservedToken = $lastToken
    }
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

function Get-RainmeterSkinsRoot {
    $configPath = Get-RainmeterConfigPath
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        return ''
    }

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

    return ''
}

function Test-RainmeterShortcutTarget {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        return $false
    }

    $leafName = [System.IO.Path]::GetFileName($TargetPath)
    return [string]::Equals($leafName, 'Rainmeter.exe', [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ShortcutTargetPath {
    param(
        [Parameter(Mandatory = $true)]$Shell,
        [Parameter(Mandatory = $true)][string]$ShortcutPath
    )

    try {
        $shortcut = $Shell.CreateShortcut($ShortcutPath)
        $targetPath = [string]$shortcut.TargetPath
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            return $null
        }
        return $targetPath
    }
    catch {
        return $null
    }
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

    $startupFolder = [Environment]::GetFolderPath('Startup')
    if (-not [string]::IsNullOrWhiteSpace($startupFolder)) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $canonicalShortcut = Join-Path $startupFolder 'Rainmeter.lnk'
            if (Test-Path -LiteralPath $canonicalShortcut) {
                $targetPath = Resolve-ShortcutTargetPath -Shell $shell -ShortcutPath $canonicalShortcut
                if ((Test-RainmeterShortcutTarget -TargetPath $targetPath) -and (Test-Path -LiteralPath $targetPath)) {
                    return [System.IO.Path]::GetFullPath($targetPath)
                }
            }
        }
        finally {
            if ($shell -and [System.Runtime.InteropServices.Marshal]::IsComObject($shell)) {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
            }
        }
    }

    return $null
}

function Invoke-RainmeterBang {
    param(
        [Parameter(Mandatory = $true)][string]$Bang,
        [string[]]$Arguments = @()
    )

    $rainmeterExe = Get-RainmeterExecutablePath
    if (-not $rainmeterExe) {
        throw 'Rainmeter.exe could not be located for refresh.'
    }

    $argList = @($Bang) + @($Arguments)
    & $rainmeterExe @argList | Out-Null
    $exitCode = $LASTEXITCODE
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        throw "Rainmeter bang failed with exit code ${exitCode}: $Bang"
    }
}

function Get-TargetRoot {
    if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        return (Resolve-FullPath -Path (Join-Path $PSScriptRoot '..'))
    }
    return (Resolve-FullPath -Path $TargetRoot)
}

function Get-VersionManagerDataRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Data'
}

function Get-SourceRegistryPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root (Get-VersionManagerDataRoot -Root $Root) -RelativePath 'VersionManagerSources.json'
}

function Get-UpdateCachePath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root (Get-VersionManagerDataRoot -Root $Root) -RelativePath 'VersionManagerUpdateCache.json'
}

function Get-VersionManagerLaunchStatePath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root (Get-VersionManagerDataRoot -Root $Root) -RelativePath 'VersionManagerLaunchState.json'
}

function Get-ImportHelperPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath 'tools\ImportFromOldVersion.ps1'
}

function Get-VersionCatalogHelperPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath 'tools\GetVersionReleaseCatalog.ps1'
}

function Get-VersionReleaseInstallHelperPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath 'tools\InstallVersionRelease.ps1'
}

function Get-SupportSettingsPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    Join-RootPath -Root $Root -RelativePath '@Resources\Customs\Settings\Support.inc'
}

function Test-VersionManagerDisplayableSkinRoot {
    param([AllowNull()][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    $leafName = [System.IO.Path]::GetFileName($Root.TrimEnd('\', '/'))
    if ([string]::IsNullOrWhiteSpace($leafName)) {
        return $false
    }

    return ($leafName.IndexOf("DMeloper's Block HUD", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Test-VersionManagerSupportedSkinRoot {
    param([AllowNull()][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    if (-not (Test-SkinRoot -Root $Root)) {
        return $false
    }

    $versionText = Get-SkinMetadataVersion -Root $Root
    $versionValue = Convert-ToVersion -VersionText $versionText
    if ($null -eq $versionValue) {
        return $false
    }

    return ($versionValue -ge [version]'1.2.0')
}

function Test-VersionManagerUnsupportedVersionText {
    param([AllowNull()][string]$VersionText)

    $versionValue = Convert-ToVersion -VersionText $VersionText
    return ($null -ne $versionValue -and $versionValue -lt [version]'1.2.0')
}

function Get-Pre12VersionManagerNotice {
    return (T 'Helper_VersionManager_Install_Pre12ManagerNotice' (U '\uAD6C\uBC84\uC804(v1.2.0 \uBBF8\uB9CC)\uC73C\uB85C \uC804\uD658\uD558\uBA74 \uC2A4\uD0A8 \uAD00\uB9AC \uCC3D\uC774 \uB2E4\uC2DC \uC5F4\uB9AC\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uC0C8\uB85C\uC6B4 \uBC84\uC804\uC744 \uD45C\uC2DC\uD558\uB824\uBA74 \uB178\uC158 \uD398\uC774\uC9C0\uC758 \uC790\uC8FC \uBB3B\uB294 \uC9C8\uBB38\uC744 \uD655\uC778\uD574 \uC8FC\uC138\uC694.'))
}

function Test-PathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedPath = (Resolve-FullPath -Path $Path).TrimEnd('\', '/')
    $resolvedRoot = (Resolve-FullPath -Path $Root).TrimEnd('\', '/')
    if ([string]::Equals($resolvedPath, $resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    return $resolvedPath.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-InstalledSkinFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CurrentRoot
    )

    $resolvedPath = Resolve-FullPath -Path $Path
    $resolvedCurrentRoot = Resolve-FullPath -Path $CurrentRoot
    if ([string]::Equals($resolvedPath, $resolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (T 'Helper_VersionManager_Install_DeleteCurrentBlocked' 'The current active skin cannot be deleted.')
    }
    if (-not (Test-SkinRoot -Root $resolvedPath) -or -not (Test-VersionManagerDisplayableSkinRoot -Root $resolvedPath)) {
        throw (T 'Helper_VersionManager_Install_DeleteInvalidBlocked' 'Only a valid Block HUD skin folder can be deleted here.')
    }

    $skinsRoot = Get-RainmeterSkinsRoot
    if ([string]::IsNullOrWhiteSpace($skinsRoot) -or -not (Test-Path -LiteralPath $skinsRoot -PathType Container)) {
        throw (T 'Helper_VersionManager_Install_DeleteSkinsRootMissing' 'Rainmeter skins root could not be verified.')
    }
    if (-not (Test-PathUnderRoot -Path $resolvedPath -Root $skinsRoot)) {
        throw (T 'Helper_VersionManager_Install_DeleteOutsideSkinsRootBlocked' 'Only installed skins under the Rainmeter skins folder can be deleted here.')
    }

    if (-not ('Microsoft.VisualBasic.FileIO.FileSystem' -as [type])) {
        throw (T 'Helper_VersionManager_Install_DeleteRecycleUnavailable' 'Recycle Bin deletion is unavailable in this PowerShell session.')
    }

    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $resolvedPath,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

function Get-LatestHelperLogPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot $PSScriptRoot)
}

function Get-VersionManagerLogsRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Join-RootPath -Root $Root -RelativePath 'Logs')
}

function Get-LogDisplayPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $resolvedRoot = Resolve-FullPath -Path $Root
    $resolvedPath = Resolve-FullPath -Path $Path
    if ($resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Substring($resolvedRoot.Length).TrimStart('\')
    }

    return $resolvedPath
}

function Get-VersionManagerLogView {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$CurrentLogPath
    )

    $blocks = New-Object System.Collections.Generic.List[string]
    $hasContent = $false
    $currentLines = @($script:LogMessages | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($currentLines.Count -gt 0) {
        $hasContent = $true
        $blocks.Add(([string]::Join("`r`n", @(
            '<VersionManager>',
            ('===== ' + (T 'Helper_VersionManager_Log_CurrentSessionHeader' 'Current session') + ' ====='),
            ([string]::Join("`r`n", $currentLines))
        ))))
    }

    $canonicalLogPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot $PSScriptRoot
    if (Test-Path -LiteralPath $canonicalLogPath -PathType Leaf) {
        $content = ''
        try {
            $content = [System.IO.File]::ReadAllText($canonicalLogPath, $script:Utf8NoBom)
        }
        catch {
            $content = ''
        }

        if (-not [string]::IsNullOrWhiteSpace($content)) {
            $hasContent = $true
            $displayPath = Get-LogDisplayPath -Root $Root -Path $canonicalLogPath
            $file = Get-Item -LiteralPath $canonicalLogPath -Force
            $header = TF 'Helper_VersionManager_Log_FileHeader' @([string]$displayPath, $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) 'Saved log: %1 (%2)'
            $blocks.Add(([string]::Join("`r`n", @(
                ('===== ' + $header + ' ====='),
                ($content.TrimEnd())
            ))))
        }
    }

    return [PSCustomObject]@{
        HasContent = $hasContent
        Text = if ($blocks.Count -gt 0) { [string]::Join("`r`n`r`n", $blocks) } else { [string](T 'Helper_VersionManager_Log_Empty' 'The skin log file is empty.') }
    }
}

function Clear-VersionManagerLogs {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$CurrentLogPath
    )

    $canonicalLogPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot $PSScriptRoot
    $parent = Split-Path -Parent $canonicalLogPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $script:LogMessages.Clear()
    [System.IO.File]::WriteAllText($canonicalLogPath, '', $script:Utf8NoBom)
    $script:LogPath = $canonicalLogPath
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
}

function Draw-VersionManagerStatusBadge {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('latest', 'unknown', 'error', 'not-latest')][string]$State,
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$BackgroundColor,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $Graphics.Clear($BackgroundColor)

    $badgeBounds = New-Object System.Drawing.RectangleF(1.5, 1.5, ($Width - 3.0), ($Height - 3.0))
    $fillColor = [System.Drawing.Color]::DarkGoldenrod
    switch ($State) {
        'latest' { $fillColor = [System.Drawing.Color]::ForestGreen }
        'error' { $fillColor = [System.Drawing.Color]::Firebrick }
    }

    $fillBrush = New-Object System.Drawing.SolidBrush $fillColor
    $outlinePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 0, 0, 0)), 1.0
    try {
        $Graphics.FillEllipse($fillBrush, $badgeBounds)
        $Graphics.DrawEllipse($outlinePen, $badgeBounds)

        switch ($State) {
            'latest' {
                $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2.8
                $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                try {
                    $Graphics.DrawLines($pen, @(
                        (New-Object System.Drawing.Point -ArgumentList 6, 12),
                        (New-Object System.Drawing.Point -ArgumentList 10, 16),
                        (New-Object System.Drawing.Point -ArgumentList 18, 8)
                    ))
                }
                finally {
                    $pen.Dispose()
                }
            }
            'error' {
                $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2.8
                $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                try {
                    $Graphics.DrawLine($pen, 7, 7, 17, 17)
                    $Graphics.DrawLine($pen, 17, 7, 7, 17)
                }
                finally {
                    $pen.Dispose()
                }
            }
            default {
                $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2.6
                $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                $dotBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
                try {
                    $Graphics.DrawLine($pen, 12, 6, 12, 14)
                    $Graphics.FillEllipse($dotBrush, 10.5, 16.0, 3.0, 3.0)
                }
                finally {
                    $pen.Dispose()
                    $dotBrush.Dispose()
                }
            }
        }
    }
    finally {
        $fillBrush.Dispose()
        $outlinePen.Dispose()
    }
}

function Get-ReleaseVariantForLanguageCode {
    param([AllowNull()][string]$LanguageCode)

    $normalized = ([string]$LanguageCode).Trim()
    if ([string]::Equals($normalized, 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Korea'
    }

    return 'Global'
}

function Get-FixedUpdateZipAssetName {
    param([AllowNull()][string]$LanguageCode)

    if ([string]::Equals(([string]$LanguageCode).Trim(), 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'DMelopers-Block-HUD_Korea.zip'
    }

    return 'DMelopers-Block-HUD_Global.zip'
}

function Get-UpdateConfiguration {
    param([Parameter(Mandatory = $true)][string]$Root)

    $support = Read-VariablesFile -Path (Get-SupportSettingsPath -Root $Root)
    $defaultReleaseVariant = Get-ReleaseVariantForLanguageCode -LanguageCode $script:LanguageCode
    $activeAssetPattern = Get-FixedUpdateZipAssetName -LanguageCode $script:LanguageCode

    [PSCustomObject]@{
        Provider = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateProvider'])) { 'github' } else { [string]$support['UpdateProvider'] }
        Owner = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubOwner'])) { 'd-meloper' } else { [string]$support['UpdateGithubOwner'] }
        Repo = if ([string]::IsNullOrWhiteSpace([string]$support['UpdateGithubRepo'])) { 'dmelopers-block-hud' } else { [string]$support['UpdateGithubRepo'] }
        ReleaseVariant = $defaultReleaseVariant
        ConfiguredReleaseVariant = ''
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

function New-UpdateConfigurationException {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $exception = New-Object System.InvalidOperationException($Message)
    [void]$exception.Data.Add('DMEL_ERROR_CODE', $Code)
    return $exception
}

function Test-NetworkAvailable {
    try {
        return [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
    }
    catch {
        return $true
    }
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

function Get-UpdateFailureHint {
    param([AllowNull()][string]$ErrorCode)

    $normalizedCode = if ([string]::IsNullOrWhiteSpace($ErrorCode)) { '' } else { $ErrorCode.Trim().ToLowerInvariant() }
    switch ($normalizedCode) {
        'update-network-offline' { return 'offline' }
        default { return '' }
    }
}

function Resolve-ActiveUpdateAssetPattern {
    param([Parameter(Mandatory = $true)]$Config)

    $languageCode = [string](Get-ObjectPropertyValue -Object $Config -Name 'LanguageCode' -DefaultValue $script:LanguageCode)
    $releaseVariant = Get-ReleaseVariantForLanguageCode -LanguageCode $languageCode
    $assetPattern = [string](Get-ObjectPropertyValue -Object $Config -Name 'ActiveAssetPattern' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($assetPattern)) {
        $assetPattern = Get-FixedUpdateZipAssetName -LanguageCode $languageCode
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
        foreach ($directory in Get-ChildItem -LiteralPath $skinsRoot -Directory -Force -ErrorAction SilentlyContinue) {
            & $addItem -Path $directory.FullName -Label $directory.Name -Source 'auto'
        }
    }

    foreach ($entry in @(Read-SourceRegistry -Root $Root)) {
        $label = if ($entry.PSObject.Properties['Label']) { [string]$entry.Label } else { '' }
        $path = if ($entry.PSObject.Properties['Path']) { [string]$entry.Path } else { '' }
        & $addItem -Path $path -Label $label -Source 'manual'
    }

    return @($items | Sort-Object @{ Expression = { if ($_.IsCurrent) { 0 } elseif ($_.Source -eq 'auto') { 1 } else { 2 } } }, @{ Expression = { $_.Version }; Descending = $true }, Label)
}

function Open-FolderPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $target = if (Test-Path -LiteralPath $Path -PathType Container) {
        $Path
    }
    elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        Split-Path -Parent $Path
    }
    else {
        Split-Path -Parent $Path
    }
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        Invoke-Item -LiteralPath $target
    }
}

function Open-FilePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File does not exist: $Path"
    }

    Start-Process -FilePath $Path
}

function Get-VersionManagerDownloadPageUrl {
    $languageCode = [string]$script:LanguageCode
    if ([string]::Equals($languageCode, 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'https://www.notion.so/aismash/DMeloper-s-Block-HUD-2f72dc0bb4ae80b3bcbad602859e30d2?source=copy_link'
    }

    return 'https://www.notion.so/aismash/DMeloper-s-Block-HUD-Download-Page-35c2dc0bb4ae8184b118c9cbe2508d4c?source=copy_link'
}

function Get-VersionManagerRepositoryUrl {
    param([Parameter(Mandatory = $true)][string]$Root)

    $config = Get-UpdateConfiguration -Root $Root
    $owner = [string]$config.Owner
    $repo = [string]$config.Repo
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
        throw (T 'Helper_VersionManager_Update_RepositoryInfoMissing' 'GitHub repository information is missing.')
    }

    return ('https://github.com/{0}/{1}' -f $owner.Trim(), $repo.Trim())
}

function Confirm-Dialog {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.IWin32Window]$Owner,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = ''
    )

    [System.Windows.Forms.MessageBox]::Show(
        $Owner,
        $Message,
        $(if ($Title) { $Title } else { T 'Helper_VersionManager_WindowTitle' 'Skins' }),
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question
    ) -eq [System.Windows.Forms.DialogResult]::OK
}

function Get-SkinRootLabel {
    param([Parameter(Mandatory = $true)][string]$Root)

    return [System.IO.Path]::GetFileName($Root.TrimEnd('\', '/'))
}

function Show-SourceEntryDialog {
    param(
        [System.Windows.Forms.IWin32Window]$Owner,
        [string]$InitialPath = ''
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T 'Helper_VersionManager_SourceDialog_Title' 'Source entry'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(560, 128)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = T 'Helper_VersionManager_Common_Path' 'Path'
    $pathLabel.AutoSize = $true
    $pathLabel.Location = New-Object System.Drawing.Point(12, 16)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Bounds = New-Object System.Drawing.Rectangle(88, 12, 364, 24)
    $pathBox.Text = $InitialPath

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = T 'Helper_VersionManager_SourceDialog_Browse' 'Browse'
    $browseButton.Bounds = New-Object System.Drawing.Rectangle(460, 10, 80, 28)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = T 'Helper_VersionManager_SourceDialog_Hint' 'Choose the old skin root folder or its parent folder.'
    $hint.AutoSize = $false
    $hint.Bounds = New-Object System.Drawing.Rectangle(12, 50, 528, 28)
    $hint.ForeColor = [System.Drawing.Color]::DimGray

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = T 'Helper_VersionManager_Common_Save' 'Save'
    $okButton.Bounds = New-Object System.Drawing.Rectangle(352, 88, 88, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = T 'Helper_VersionManager_Common_Close' 'Close'
    $cancelButton.Bounds = New-Object System.Drawing.Rectangle(452, 88, 88, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $skinsRoot = Get-RainmeterSkinsRoot

    $browseButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = T 'Helper_VersionManager_SourceDialog_FolderPrompt' 'Select the old Block HUD folder.'
        $dialog.ShowNewFolderButton = $false
        if (-not [string]::IsNullOrWhiteSpace($pathBox.Text) -and (Test-Path -LiteralPath $pathBox.Text -PathType Container)) {
            $dialog.SelectedPath = $pathBox.Text
        }
        elseif (-not [string]::IsNullOrWhiteSpace($skinsRoot)) {
            $dialog.SelectedPath = $skinsRoot
        }

        $dialogOwner = [System.Windows.Forms.IWin32Window]$form
        if ($dialog.ShowDialog($dialogOwner) -eq [System.Windows.Forms.DialogResult]::OK) {
            $pathBox.Text = $dialog.SelectedPath
        }
    })

    $form.Controls.AddRange(@($pathLabel, $pathBox, $browseButton, $hint, $okButton, $cancelButton))
    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog($Owner) -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $null
    }

    $resolved = Resolve-SkinRootCandidate -Candidate $pathBox.Text
    if (-not $resolved) {
        [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_SourceDialog_InvalidRoot' 'The selected path is not a valid Block HUD skin root.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $form.Dispose()
        return $null
    }

    $result = [PSCustomObject]@{
        Label = Get-SkinRootLabel -Root $resolved
        Path = $resolved
    }
    $form.Dispose()
    return $result
}

function Invoke-ImportFromInstallation {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $importScript = Get-ImportHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $importScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Install_HelperMissing' 'ImportFromOldVersion.ps1 was not found.')
    }

    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -STA -File $importScript -TargetRoot $Root -SourceRoot $SourcePath -EmitResultPairs 2>&1)
    $exitCode = $LASTEXITCODE
    $pairs = @{}
    foreach ($line in $output) {
        $textLine = [string]$line
        if ($textLine -match '^(DMEL_[A-Z]+)=(.*)$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }

    $status = [string]($pairs['DMEL_STATUS'])
    $message = [string]($pairs['DMEL_MESSAGE'])
    $sourcePath = [string]($pairs['DMEL_SOURCEPATH'])
    $logPath = [string]($pairs['DMEL_LOGPATH'])
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'ERROR'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = T 'Helper_VersionManager_Install_HelperStatusMissing' 'Import helper did not emit DMEL_STATUS.'
        }
    }
    else {
        $status = $status.ToUpperInvariant()
    }

    if (($status -eq 'OK' -or $status -eq 'CANCEL') -and $exitCode -ne 0) {
        $status = 'ERROR'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Import helper exited with code $exitCode despite reporting a successful status."
        }
    }

    if ($status -eq 'OK') {
        $missingContract = New-Object System.Collections.Generic.List[string]
        if ([string]::IsNullOrWhiteSpace($sourcePath)) {
            $missingContract.Add('DMEL_SOURCEPATH')
        }
        if ([string]::IsNullOrWhiteSpace($logPath)) {
            $missingContract.Add('DMEL_LOGPATH')
        }
        if ($missingContract.Count -gt 0) {
            $status = 'ERROR'
            $message = 'Import helper reported success without required result fields: ' + ($missingContract.ToArray() -join ', ')
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = $sourcePath
        LogPath = $logPath
        Output = ($output | Out-String)
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

function Test-UpdateCacheStagedDownloadPresent {
    param([AllowNull()]$Cache)

    $downloadedZipPath = [string](Get-ObjectPropertyValue -Object $Cache -Name 'DownloadedZipPath' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($downloadedZipPath)) {
        return $false
    }

    return (Test-Path -LiteralPath $downloadedZipPath -PathType Leaf)
}

function Test-UpdateCacheReleasePayloadMatch {
    param(
        [AllowNull()]$LeftCache,
        [AllowNull()]$RightCache
    )

    foreach ($propertyName in @(
        'LatestVersion',
        'AssetName',
        'AssetUrl',
        'AssetSize',
        'ReleaseVariant',
        'ActiveAssetPattern'
    )) {
        $leftValue = [string](Get-ObjectPropertyValue -Object $LeftCache -Name $propertyName -DefaultValue '')
        $rightValue = [string](Get-ObjectPropertyValue -Object $RightCache -Name $propertyName -DefaultValue '')
        if (-not [string]::Equals($leftValue, $rightValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    return $true
}

function Test-UpdateCacheStagedDownloadMatchesPayload {
    param(
        [AllowNull()]$Cache,
        [AllowNull()]$ReferenceCache
    )

    if (-not (Test-UpdateCacheStagedDownloadPresent -Cache $Cache)) {
        return $false
    }

    if ($null -eq $ReferenceCache) {
        return $true
    }

    return (Test-UpdateCacheReleasePayloadMatch -LeftCache $Cache -RightCache $ReferenceCache)
}

function Copy-UpdateCacheStagedDownloadFields {
    param(
        [Parameter(Mandatory = $true)]$TargetCache,
        [AllowNull()]$SourceCache
    )

    Set-ObjectPropertyValue -Object $TargetCache -Name 'DownloadedZipPath' -Value ([string](Get-ObjectPropertyValue -Object $SourceCache -Name 'DownloadedZipPath' -DefaultValue ''))
    Set-ObjectPropertyValue -Object $TargetCache -Name 'DownloadedAtUtc' -Value ([string](Get-ObjectPropertyValue -Object $SourceCache -Name 'DownloadedAtUtc' -DefaultValue ''))
}

function Merge-LatestCheckSuccessCache {
    param(
        [AllowNull()]$ExistingCache,
        [Parameter(Mandatory = $true)]$LatestCache
    )

    if (Test-UpdateCacheStagedDownloadMatchesPayload -Cache $ExistingCache -ReferenceCache $LatestCache) {
        Copy-UpdateCacheStagedDownloadFields -TargetCache $LatestCache -SourceCache $ExistingCache
    }
    else {
        Copy-UpdateCacheStagedDownloadFields -TargetCache $LatestCache -SourceCache $null
    }

    return $LatestCache
}

function New-LatestCheckFailureCachePatch {
    param(
        [AllowNull()]$ExistingCache,
        [Parameter(Mandatory = $true)][string]$ErrorMessage,
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [AllowNull()]$UpdateConfig
    )

    $patch = [PSCustomObject]@{
        LastCheckedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        LatestVersion = ''
        ReleaseName = ''
        ReleaseUrl = ''
        AssetName = ''
        AssetUrl = ''
        AssetSize = 0
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = 'error'
        Error = $ErrorMessage
        ErrorCode = $ErrorCode
        FailureHint = Get-UpdateFailureHint -ErrorCode $ErrorCode
        ReleaseVariant = [string](Get-ObjectPropertyValue -Object $UpdateConfig -Name 'ReleaseVariant' -DefaultValue '')
        ActiveAssetPattern = [string](Get-ObjectPropertyValue -Object $UpdateConfig -Name 'ActiveAssetPattern' -DefaultValue '')
    }

    if (Test-UpdateCacheStagedDownloadMatchesPayload -Cache $ExistingCache -ReferenceCache $ExistingCache) {
        Copy-UpdateCacheStagedDownloadFields -TargetCache $patch -SourceCache $ExistingCache
    }

    return $patch
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

function Test-AssetPatternMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return [string]::Equals($Pattern, $Name, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-GitHubApiRateLimitException {
    param([AllowNull()]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        $response = $null
        try {
            $response = $current.Response
        }
        catch {
            $response = $null
        }

        if ($null -ne $response) {
            $statusCode = $null
            try {
                $statusCode = [int]$response.StatusCode
            }
            catch {
                $statusCode = $null
            }
            $statusDescription = ''
            try {
                $statusDescription = [string]$response.StatusDescription
            }
            catch {
                $statusDescription = ''
            }

            if ($statusCode -eq 429) {
                return $true
            }
            if ($statusCode -eq 403 -and $statusDescription -match '(?i)rate limit') {
                return $true
            }
        }

        $message = [string]$current.Message
        if ($message -match '(?i)rate limit') {
            return $true
        }
        $current = $current.InnerException
    }

    return $false
}

function Invoke-GitHubWebRequestText {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $headers = @{
        'User-Agent' = 'DMeloper-Block-HUD-VersionManager'
    }
    $response = Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing
    return [string]$response.Content
}

function Get-GitHubReleaseAssetsFromHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    $assetsUri = 'https://github.com/{0}/{1}/releases/expanded_assets/{2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($Tag)
    $html = Invoke-GitHubWebRequestText -Uri $assetsUri
    $assets = New-Object System.Collections.Generic.List[object]
    $pattern = 'href="(?<href>/{0}/{1}/releases/download/{2}/(?<name>[^"#?]+))"' -f [regex]::Escape($Owner), [regex]::Escape($Repo), [regex]::Escape($Tag)
    foreach ($match in [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $name = [System.Uri]::UnescapeDataString([string]$match.Groups['name'].Value)
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }
        [void]$assets.Add([PSCustomObject]@{
            name = $name
            browser_download_url = 'https://github.com' + [string]$match.Groups['href'].Value
            size = 0
        })
    }

    return $assets.ToArray()
}

function Invoke-GitHubReleaseCatalogHtmlFallback {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo
    )

    Write-Log 'GitHub API latest-release check is rate-limited; falling back to public release feed.'
    $atomUri = 'https://github.com/{0}/{1}/releases.atom' -f $Owner, $Repo
    $atom = Invoke-GitHubWebRequestText -Uri $atomUri
    $entryPattern = '<entry>(?<entry>.*?)</entry>'
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entryMatch in [regex]::Matches($atom, $entryPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $entry = [string]$entryMatch.Groups['entry'].Value
        $tag = ''
        if ($entry -match 'href="https://github\.com/[^/]+/[^/]+/releases/tag/(?<tag>[^"]+)"') {
            $tag = [System.Net.WebUtility]::HtmlDecode([string]$matches['tag'])
        }
        if ([string]::IsNullOrWhiteSpace($tag)) {
            continue
        }

        $title = $tag
        if ($entry -match '<title>(?<title>.*?)</title>') {
            $title = [System.Net.WebUtility]::HtmlDecode([string]$matches['title'])
        }

        $body = ''
        $bodyMatch = [regex]::Match($entry, '<content[^>]*>(?<body>.*?)</content>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($bodyMatch.Success) {
            $body = [System.Net.WebUtility]::HtmlDecode([string]$bodyMatch.Groups['body'].Value)
            $body = [regex]::Replace($body, '<[^>]+>', ' ')
            $body = [regex]::Replace($body, '\s+', ' ').Trim()
        }

        $updated = ''
        if ($entry -match '<updated>(?<updated>.*?)</updated>') {
            $updated = [string]$matches['updated']
        }

        $assets = @(Get-GitHubReleaseAssetsFromHtml -Owner $Owner -Repo $Repo -Tag $tag)
        [void]$results.Add([PSCustomObject]@{
            draft = $false
            prerelease = $false
            tag_name = $tag
            name = $title
            html_url = ('https://github.com/{0}/{1}/releases/tag/{2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($tag))
            body = $body
            published_at = $updated
            assets = $assets
        })
    }

    return $results.ToArray()
}

function Invoke-CheckLatestReleaseApi {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$AssetPattern
    )

    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'DMeloper-Block-HUD-VersionManager'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $perPage = 100
    $page = 1
    $stable = New-Object System.Collections.Generic.List[object]

    while ($true) {
        $uri = 'https://api.github.com/repos/{0}/{1}/releases?per_page={2}&page={3}' -f $Config.Owner, $Config.Repo, $perPage, $page
        $batch = @(Invoke-RestMethod -Uri $uri -Headers $headers -Method Get)
        if ($batch.Count -eq 0) {
            break
        }

        foreach ($release in $batch) {
            if ($release.prerelease -or $release.draft) {
                continue
            }
            $semanticVersion = Convert-ToVersion -VersionText ([string]$release.tag_name)
            if ($null -eq $semanticVersion) {
                continue
            }
            $hasAsset = $false
            foreach ($asset in @($release.assets)) {
                if (Test-AssetPatternMatch -Pattern $AssetPattern -Name ([string]$asset.name)) {
                    $hasAsset = $true
                    break
                }
            }
            if ($hasAsset) {
                [void]$stable.Add([PSCustomObject]@{
                    Release = $release
                    Version = $semanticVersion
                })
            }
        }

        if ($batch.Count -lt $perPage) {
            break
        }
        $page++
    }

    if ($stable.Count -eq 0) {
        throw (New-UpdateConfigurationException -Code 'update-asset-match-failed' -Message (TF 'Helper_VersionManager_Update_AssetMismatch' @($AssetPattern) 'The expected update ZIP "%1" was not found in the latest release.'))
    }

    return (@($stable | Sort-Object Version -Descending)[0].Release)
}

function Invoke-CheckLatestReleaseFallback {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$AssetPattern
    )

    $releases = @(Invoke-GitHubReleaseCatalogHtmlFallback -Owner ([string]$Config.Owner) -Repo ([string]$Config.Repo))
    $stable = New-Object System.Collections.Generic.List[object]
    foreach ($release in $releases) {
        $semanticVersion = Convert-ToVersion -VersionText ([string]$release.tag_name)
        if ($null -ne $semanticVersion) {
            $hasAsset = $false
            foreach ($asset in @($release.assets)) {
                if (Test-AssetPatternMatch -Pattern $AssetPattern -Name ([string]$asset.name)) {
                    $hasAsset = $true
                    break
                }
            }
            if (-not $hasAsset) {
                continue
            }
            [void]$stable.Add([PSCustomObject]@{
                Release = $release
                Version = $semanticVersion
            })
        }
    }
    if ($stable.Count -eq 0) {
        throw (New-UpdateConfigurationException -Code 'update-asset-match-failed' -Message (TF 'Helper_VersionManager_Update_AssetMismatch' @($AssetPattern) 'The expected update ZIP "%1" was not found in the latest release.'))
    }

    return (@($stable | Sort-Object Version -Descending)[0].Release)
}

function Invoke-CheckLatestRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Config
    )

    $activePattern = Resolve-ActiveUpdateAssetPattern -Config $Config
    if (-not [string]::Equals([string]$Config.Provider, 'github', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::IsNullOrWhiteSpace([string]$Config.Owner) -or
        [string]::IsNullOrWhiteSpace([string]$Config.Repo) -or
        [string]::IsNullOrWhiteSpace([string]$activePattern.AssetPattern)) {
        $assetName = if ([string]::IsNullOrWhiteSpace([string]$activePattern.AssetPattern)) { Get-FixedUpdateZipAssetName -LanguageCode $script:LanguageCode } else { [string]$activePattern.AssetPattern }
        throw (New-UpdateConfigurationException -Code 'update-source-unconfigured' -Message (TF 'Helper_VersionManager_Update_SourceUnconfiguredDetailed' @($assetName) 'The update source is not configured yet. Set UpdateGithubOwner and UpdateGithubRepo. The updater then uses %1.'))
    }

    if (-not (Test-NetworkAvailable)) {
        throw (New-UpdateConfigurationException -Code 'update-network-offline' -Message (T 'Helper_VersionManager_Update_Error_Offline' 'The internet connection is unavailable. Check the connection and try again.'))
    }

    try {
        $response = Invoke-CheckLatestReleaseApi -Config $Config -AssetPattern ([string]$activePattern.AssetPattern)
    }
    catch {
        if (Test-GitHubApiRateLimitException -Exception $_.Exception) {
            $response = Invoke-CheckLatestReleaseFallback -Config $Config -AssetPattern ([string]$activePattern.AssetPattern)
        }
        else {
            throw
        }
    }
    if ($response.prerelease -or $response.draft) {
        throw (New-UpdateConfigurationException -Code 'update-no-stable-release' -Message (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.'))
    }

    $matchedAssets = New-Object System.Collections.Generic.List[object]
    foreach ($asset in @($response.assets)) {
        if (Test-AssetPatternMatch -Pattern ([string]$activePattern.AssetPattern) -Name ([string]$asset.name)) {
            [void]$matchedAssets.Add($asset)
        }
    }
    if ($matchedAssets.Count -eq 0) {
        throw (New-UpdateConfigurationException -Code 'update-asset-match-failed' -Message (TF 'Helper_VersionManager_Update_AssetMismatch' @([string]$activePattern.AssetPattern) 'The expected update ZIP "%1" was not found in the latest release.'))
    }
    if ($matchedAssets.Count -gt 1) {
        $matchedNames = @($matchedAssets | ForEach-Object { [string]$_.name }) -join ', '
        throw (New-UpdateConfigurationException -Code 'update-asset-match-failed' -Message (TF 'Helper_VersionManager_Update_AssetMultipleMatches' @([string]$activePattern.AssetPattern, $matchedNames) 'The expected update ZIP "%1" matched multiple assets in the latest release: %2'))
    }
    $matchedAsset = $matchedAssets[0]

    $body = [string]$response.body
    if ($body.Length -gt 600) {
        $body = $body.Substring(0, 600).Trim() + '...'
    }

    $cache = [PSCustomObject]@{
        LastCheckedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        LatestVersion = [string]$response.tag_name
        ReleaseName = [string]$response.name
        ReleaseUrl = [string]$response.html_url
        AssetName = [string]$matchedAsset.name
        AssetUrl = [string]$matchedAsset.browser_download_url
        AssetSize = [long]$matchedAsset.size
        PublishedAtUtc = [string]$response.published_at
        ChangelogSummary = $body
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = 'ready'
        Error = ''
        ErrorCode = ''
        FailureHint = ''
        ReleaseVariant = [string]$activePattern.ReleaseVariant
        ActiveAssetPattern = [string]$activePattern.AssetPattern
    }
    return $cache
}

function Convert-VersionManagerOutputToResultPairs {
    param([object[]]$Output)

    $pairs = @{}
    foreach ($line in @($Output)) {
        $textLine = [string]$line
        if ($textLine -match '^(DMEL_[A-Z]+)=(.*)$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }

    return $pairs
}

function Invoke-VersionReleaseCatalog {
    param([Parameter(Mandatory = $true)][string]$Root)

    $catalogScript = Get-VersionCatalogHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $catalogScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Update_VersionCatalogBackendRequired' (U '\uBC84\uC804 \uBAA9\uB85D \uC870\uD68C/\uC124\uCE58 \uBC31\uC5D4\uB4DC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.'))
    }

    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $catalogScript -CurrentTargetRoot $Root -OutputJson 2>&1)
    $exitCode = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw 'Version catalog helper did not emit JSON.'
    }

    $catalog = $null
    try {
        $catalog = $jsonText | ConvertFrom-Json
    }
    catch {
        throw ("Version catalog helper emitted invalid JSON. exitCode={0}; output={1}" -f $exitCode, $jsonText)
    }

    $status = [string](Get-ObjectPropertyValue -Object $catalog -Name 'status' -DefaultValue '')
    $message = [string](Get-ObjectPropertyValue -Object $catalog -Name 'message' -DefaultValue '')
    if ($exitCode -ne 0 -or [string]::Equals($status, 'ERROR', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Version catalog helper failed with exit code $exitCode."
        }
        throw $message
    }

    return $catalog
}

function Invoke-VersionReleaseInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$PackageUrl,
        [string]$ExpectedVersion,
        [string]$SelectedTargetRoot,
        [switch]$AllowCompatibilityWarning
    )

    $installScript = Get-VersionReleaseInstallHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Update_VersionCatalogBackendRequired' (U '\uBC84\uC804 \uBAA9\uB85D \uC870\uD68C/\uC124\uCE58 \uBC31\uC5D4\uB4DC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.'))
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $installScript,
        '-CurrentTargetRoot',
        $Root,
        '-EmitResultPairs'
    )
    if (-not [string]::IsNullOrWhiteSpace($SelectedTargetRoot)) {
        $arguments += @('-SelectedTargetRoot', $SelectedTargetRoot)
    }
    else {
        $arguments += @('-PackageUrl', $PackageUrl, '-ExpectedVersion', $ExpectedVersion)
        if ($AllowCompatibilityWarning) {
            $arguments += '-AllowCompatibilityWarning'
        }
    }

    $output = @(& powershell @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $pairs = Convert-VersionManagerOutputToResultPairs -Output $output
    $status = [string]($pairs['DMEL_STATUS'])
    $message = [string]($pairs['DMEL_MESSAGE'])
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'ERROR'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Install helper did not emit DMEL_STATUS."
        }
    }
    $status = $status.ToUpperInvariant()

    if ($status -ne 'OK' -and $status -ne 'WARN' -and $status -ne 'ERROR' -and $status -ne 'NOOP') {
        $message = "Install helper emitted unsupported DMEL_STATUS '$status'."
        $status = 'ERROR'
    }

    if (($status -eq 'OK' -or $status -eq 'WARN' -or $status -eq 'NOOP') -and $exitCode -ne 0) {
        $status = 'ERROR'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Install helper exited with code $exitCode despite reporting a successful status."
        }
    }

    if ($status -eq 'OK' -or $status -eq 'WARN' -or $status -eq 'NOOP') {
        $missingContract = New-Object System.Collections.Generic.List[string]
        if (($status -eq 'OK' -or $status -eq 'NOOP') -and [string]::IsNullOrWhiteSpace([string]($pairs['DMEL_SOURCEPATH']))) {
            $missingContract.Add('DMEL_SOURCEPATH')
        }
        if ([string]::IsNullOrWhiteSpace([string]($pairs['DMEL_LOGPATH']))) {
            $missingContract.Add('DMEL_LOGPATH')
        }
        if ($missingContract.Count -gt 0) {
            $status = 'ERROR'
            $message = 'Install helper reported success without required result fields: ' + ($missingContract.ToArray() -join ', ')
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = [string]($pairs['DMEL_SOURCEPATH'])
        LogPath = [string]($pairs['DMEL_LOGPATH'])
        Output = ($output | Out-String)
    }
}

function Invoke-ClearDownloadCache {
    param([Parameter(Mandatory = $true)][string]$Root)

    $downloadsRoot = Join-RootPath -Root (Get-VersionManagerDataRoot -Root $Root) -RelativePath 'VersionManagerDownloads'
    if (Test-Path -LiteralPath $downloadsRoot -PathType Container) {
        Remove-Item -LiteralPath $downloadsRoot -Force -Recurse
    }
    $cache = Update-UpdateCache -Root $Root -Patch ([PSCustomObject]@{
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
    })
    return $cache
}

function Get-VersionManagerSessionProcesses {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $rootPattern = [regex]::Escape($ResolvedTargetRoot)
    $scriptPattern = [regex]::Escape($scriptPath)
    $windowFlagPattern = '(?i)(^|[\s"''])-WindowSession($|[\s"''])'

    return @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $commandLine = [string](Get-ObjectPropertyValue -Object $_ -Name 'CommandLine' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            return $false
        }
        return (
            ($commandLine -match $scriptPattern) -and
            ($commandLine -match $rootPattern) -and
            ($commandLine -match $windowFlagPattern)
        )
    })
}

function Stop-VersionManagerSessions {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    foreach ($process in @(Get-VersionManagerSessionProcesses -ResolvedTargetRoot $ResolvedTargetRoot)) {
        try {
            $processId = [int](Get-ObjectPropertyValue -Object $process -Name 'ProcessId' -DefaultValue 0)
            if ($processId -le 0) {
                continue
            }
            Write-Log ("Stopping existing version manager session PID {0}" -f $processId)
            Stop-Process -Id $processId -Force -ErrorAction Stop
            try {
                Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
            }
            catch {
            }
        }
        catch {
            Write-Log ("Failed to stop existing version manager session: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Start-VersionManagerLauncherForRoot {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    if (-not (Test-SkinRoot -Root $resolvedTargetRoot)) {
        throw 'TargetRoot is not a valid Block HUD skin root.'
    }

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $resolvedTargetRoot -ScriptRoot $PSScriptRoot
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    Save-VersionManagerLaunchState -Root $resolvedTargetRoot -Status 'launching' -LaunchTokenValue $LaunchToken

    Stop-VersionManagerSessions -ResolvedTargetRoot $resolvedTargetRoot

    $powershellExe = Get-PowerShellExecutablePath
    $command = '& ' + (ConvertTo-PowerShellSingleQuotedLiteral -Value $PSCommandPath) +
        ' -TargetRoot ' + (ConvertTo-PowerShellSingleQuotedLiteral -Value $resolvedTargetRoot) +
        ' -WindowSession' +
        $(if ([string]::IsNullOrWhiteSpace($LaunchToken)) { '' } else { ' -LaunchToken ' + (ConvertTo-PowerShellSingleQuotedLiteral -Value $LaunchToken) })
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-STA'
        '-EncodedCommand'
        $encodedCommand
    )
    Start-Process -FilePath $powershellExe -ArgumentList $argumentList -WindowStyle Hidden | Out-Null
}

function Start-VersionManagerLauncherForSupportedRoot {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    if (Test-VersionManagerSupportedSkinRoot -Root $ResolvedTargetRoot) {
        Start-VersionManagerLauncherForRoot -ResolvedTargetRoot $ResolvedTargetRoot
        return $true
    }

    $versionText = Get-SkinMetadataVersion -Root $ResolvedTargetRoot
    if ([string]::IsNullOrWhiteSpace($versionText)) {
        $versionText = '?'
    }
    Write-Log ("Selected root version v{0} predates Skins support; keeping the manager closed after switch: {1}" -f $versionText, $ResolvedTargetRoot) 'INFO'
    return $false
}

function Start-VersionManagerLauncher {
    $root = Get-TargetRoot
    Start-VersionManagerLauncherForRoot -ResolvedTargetRoot $root
    return (Wait-VersionManagerLaunchShown -Root $root -ExpectedLaunchToken $LaunchToken)
}

function Start-VersionManager {
    $root = Get-TargetRoot
    if (-not (Test-SkinRoot -Root $root)) {
        throw 'TargetRoot is not a valid Block HUD skin root.'
    }

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $root -ScriptRoot $PSScriptRoot
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    Save-VersionManagerLaunchState -Root $root -Status 'initializing' -LaunchTokenValue $LaunchToken

    $ui = [ordered]@{}
    $ui.Root = $root
    $ui.TargetVersionText = Get-SkinMetadataVersion -Root $root
    $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
    $ui.Installations = @()
    $ui.UpdateConfig = [PSCustomObject]@{
        Provider = 'github'
        Owner = ''
        Repo = ''
        ReleaseVariant = ''
        ConfiguredReleaseVariant = ''
        DefaultReleaseVariant = ''
        LegacyAssetPattern = ''
        AssetPatternKorea = ''
        AssetPatternGlobal = ''
        HasVariantAwareAssetSettings = $true
        ActivePatternField = ''
        ActiveAssetPattern = ''
        AssetPattern = ''
        LanguageCode = $script:LanguageCode
        Channel = 'stable'
    }
    $ui.UpdateCache = [PSCustomObject]@{
        LastCheckedAtUtc = ''
        LatestVersion = ''
        ReleaseName = ''
        ReleaseUrl = ''
        AssetName = ''
        AssetUrl = ''
        AssetSize = 0
        PublishedAtUtc = ''
        ChangelogSummary = ''
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = ''
        Error = ''
        ErrorCode = ''
        FailureHint = ''
        ReleaseVariant = ''
        ActiveAssetPattern = ''
    }
    $ui.CurrentInstallation = $null
    $ui.OtherInstallations = @()
    $ui.SelectedInstallation = $null
    $ui.VersionCatalog = $null
    $ui.VersionCatalogEntries = @()
    $ui.SelectedVersionCatalogEntry = $null
    $ui.VersionCatalogOperationInProgress = $false
    $ui.InstallationOperationInProgress = $false
    $ui.UpdateCheckInProgress = $false
    $ui.BusyOverlayVisible = $false
    $ui.BusyOverlayControlStates = @()
    $ui.HasSessionUpdateStatus = $false
    $ui.SettingsLogHasContent = $false
    $ui.CloseAfterSwitch = $false
    $ui.InitialHydrationStageIndex = 0
    $ui.DeferredHydrationStageIndex = 0
    $ui.InitialHydrationCompleted = $false
    $ui.LatestCheckRequestState = New-VersionManagerRequestOwnershipState -Name 'latest-check'
    $ui.TabStates = New-VersionManagerTabStateTable -TabNames @('summary', 'installations', 'settingsLog')

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T 'Helper_VersionManager_WindowTitle' 'Skins'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(784, 393)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Bounds = New-Object System.Drawing.Rectangle(12, 12, 760, 331)
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $tabs.ItemSize = New-Object System.Drawing.Size(132, 24)

    $installTab = New-Object System.Windows.Forms.TabPage
    $installTab.Text = T 'Helper_VersionManager_Tab_Update' 'Update'
    $foldersTab = New-Object System.Windows.Forms.TabPage
    $foldersTab.Text = T 'Helper_VersionManager_Tab_Folders' (U '\uC124\uCE58\uB41C \uC2A4\uD0A8')
    $settingsTab = New-Object System.Windows.Forms.TabPage
    $settingsTab.Text = T 'Helper_VersionManager_Tab_Settings' (U '\uC815\uBCF4')

    $tabs.TabPages.AddRange(@($installTab, $foldersTab, $settingsTab))

    $currentInstallGroup = New-Object System.Windows.Forms.GroupBox
    $currentInstallGroup.Text = T 'Helper_VersionManager_Install_CurrentGroup' 'Current install version'
    $currentInstallGroup.Bounds = New-Object System.Drawing.Rectangle(12, 8, 720, 100)

    $currentVersionValue = New-Object System.Windows.Forms.Label
    $currentVersionValue.Location = New-Object System.Drawing.Point(18, 24)
    $currentVersionValue.AutoSize = $true
    $currentVersionValue.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $currentVersionStateIcon = New-Object System.Windows.Forms.Control
    $currentVersionStateIcon.Size = New-Object System.Drawing.Size(24, 24)
    $currentVersionStateIcon.Location = New-Object System.Drawing.Point(506, 27)
    $currentVersionStateIcon.BackColor = $currentInstallGroup.BackColor
    $currentVersionStateIcon.Tag = 'unknown'
    $currentVersionStateIcon.Add_Paint({
        param($sender, $eventArgs)

        $state = [string]$sender.Tag
        if ([string]::IsNullOrWhiteSpace($state)) {
            $state = 'unknown'
        }
        Draw-VersionManagerStatusBadge -State $state -Graphics $eventArgs.Graphics -BackgroundColor $sender.BackColor -Width $sender.Width -Height $sender.Height
    })
    $currentVersionStatusText = New-Object System.Windows.Forms.Label
    $currentVersionStatusText.Location = New-Object System.Drawing.Point(18, 60)
    $currentVersionStatusText.Size = New-Object System.Drawing.Size(500, 18)
    $currentVersionStatusText.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)

    $footerCheckLatest = New-Object System.Windows.Forms.Button
    $footerCheckLatest.Text = T 'Helper_VersionManager_Action_CheckLatest' 'Check latest version'
    $footerCheckLatest.Bounds = New-Object System.Drawing.Rectangle(536, 24, 176, 26)
    $footerInstallLatest = New-Object System.Windows.Forms.Button
    $footerInstallLatest.Text = T 'Helper_VersionManager_Action_InstallLatest' 'Update to latest version'
    $footerInstallLatest.Bounds = New-Object System.Drawing.Rectangle(536, 56, 176, 26)
    $currentInstallGroup.Controls.AddRange(@(
        $currentVersionValue,
        $currentVersionStateIcon,
        $currentVersionStatusText,
        $footerCheckLatest,
        $footerInstallLatest
    ))

    $versionCatalogGroup = New-Object System.Windows.Forms.GroupBox
    $versionCatalogGroup.Text = T 'Helper_VersionManager_Update_VersionCatalogGroup' (U '\uBC84\uC804 \uBAA9\uB85D')
    $versionCatalogGroup.Bounds = New-Object System.Drawing.Rectangle(12, 112, 720, 180)

    $versionCatalogList = New-Object System.Windows.Forms.ListView
    $versionCatalogList.Bounds = New-Object System.Drawing.Rectangle(10, 20, 576, 150)
    $versionCatalogList.View = [System.Windows.Forms.View]::Details
    $versionCatalogList.FullRowSelect = $true
    $versionCatalogList.HideSelection = $false
    $versionCatalogList.MultiSelect = $false
    $versionCatalogList.GridLines = $true
    $versionCatalogList.Enabled = $false
    [void]$versionCatalogList.Columns.Add((T 'Helper_VersionManager_List_Version' 'Version'), 88)
    [void]$versionCatalogList.Columns.Add((T 'Helper_VersionManager_Update_ReleaseColumn' (U '\uB9B4\uB9AC\uC988')), 204)
    [void]$versionCatalogList.Columns.Add((T 'Helper_VersionManager_List_Status' 'Status'), 284)

    $versionCatalogInstallButton = New-Object System.Windows.Forms.Button
    $versionCatalogInstallButton.Text = T 'Helper_VersionManager_Action_InstallVersion' (U '\uC774 \uBC84\uC804 \uC124\uCE58\uD558\uAE30')
    $versionCatalogInstallButtonWidth = [Math]::Max(112, [System.Windows.Forms.TextRenderer]::MeasureText($versionCatalogInstallButton.Text, $versionCatalogInstallButton.Font).Width + 24)
    $versionCatalogInstallButtonX = 706 - $versionCatalogInstallButtonWidth
    $versionCatalogList.Width = $versionCatalogInstallButtonX - 18
    $versionCatalogInstallButton.Bounds = New-Object System.Drawing.Rectangle($versionCatalogInstallButtonX, 18, $versionCatalogInstallButtonWidth, 24)
    $versionCatalogInstallButton.Enabled = $false

    $versionCatalogGroup.Controls.AddRange(@($versionCatalogList, $versionCatalogInstallButton))

    $otherInstallGroup = New-Object System.Windows.Forms.GroupBox
    $otherInstallGroup.Text = T 'Helper_VersionManager_Install_OtherGroup' (U '\uCEF4\uD4E8\uD130\uC5D0 \uC124\uCE58\uB41C \uC2A4\uD0A8')
    $otherInstallGroup.Bounds = New-Object System.Drawing.Rectangle(12, 8, 720, 280)

    $otherInstallList = New-Object System.Windows.Forms.ListView
    $otherInstallList.Bounds = New-Object System.Drawing.Rectangle(10, 20, 576, 250)
    $otherInstallList.View = [System.Windows.Forms.View]::Details
    $otherInstallList.FullRowSelect = $true
    $otherInstallList.HideSelection = $false
    $otherInstallList.MultiSelect = $false
    $otherInstallList.GridLines = $true
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_List_Status' 'Status'), 132)
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_List_Version' 'Version'), 76)
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_Common_Label' 'Label'), 118)
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_Common_Path' 'Path'), 250)

    $installButtons = [ordered]@{}
    $installButtons.UseVersion = New-Object System.Windows.Forms.Button
    $installButtons.UseVersion.Text = T 'Helper_VersionManager_Action_UseVersion' 'Use this skin'
    $installButtons.UseVersion.Bounds = New-Object System.Drawing.Rectangle(594, 18, 112, 24)
    $installButtons.UseVersion.Enabled = $false
    $installButtons.Import = New-Object System.Windows.Forms.Button
    $installButtons.Import.Text = T 'Helper_VersionManager_Action_ImportData' 'Import data'
    $installButtons.Import.Bounds = New-Object System.Drawing.Rectangle(594, 46, 112, 24)
    $installButtons.Delete = New-Object System.Windows.Forms.Button
    $installButtons.Delete.Text = T 'Helper_VersionManager_Action_Delete' 'Delete'
    $installButtons.Delete.Bounds = New-Object System.Drawing.Rectangle(594, 74, 112, 24)

    $installResult = New-Object System.Windows.Forms.TextBox
    $installResult.Bounds = New-Object System.Drawing.Rectangle(12, 293, 720, 20)
    $installResult.ReadOnly = $true

    $otherInstallGroup.Controls.Add($otherInstallList)
    foreach ($button in $installButtons.Values) {
        $otherInstallGroup.Controls.Add($button)
    }
    $installTab.Controls.AddRange(@($currentInstallGroup, $versionCatalogGroup))

    $foldersTab.Controls.AddRange(@($otherInstallGroup, $installResult))

    $settingsUtilityGroup = New-Object System.Windows.Forms.GroupBox
    $settingsUtilityGroup.Text = T 'Helper_VersionManager_Settings_UtilitiesGroup' 'Utilities'
    $settingsUtilityGroup.Bounds = New-Object System.Drawing.Rectangle(12, 12, 720, 64)
    $settingsOpenLogButton = New-Object System.Windows.Forms.Button
    $settingsOpenLogButton.Text = T 'Helper_VersionManager_Action_OpenLogFolder' 'Open log folder'
    $settingsOpenLogButton.Bounds = New-Object System.Drawing.Rectangle(16, 24, 156, 24)
    $settingsOpenSkinButton = New-Object System.Windows.Forms.Button
    $settingsOpenSkinButton.Text = T 'Helper_VersionManager_Action_OpenCurrentSkinFolder' 'Open current skin folder'
    $settingsOpenSkinButton.Bounds = New-Object System.Drawing.Rectangle(184, 24, 176, 24)
    $settingsUtilityGroup.Controls.AddRange(@($settingsOpenLogButton, $settingsOpenSkinButton))

    $settingsLogGroup = New-Object System.Windows.Forms.GroupBox
    $settingsLogGroup.Text = T 'Helper_VersionManager_Log_Group' 'Skin logs'
    $settingsLogGroup.Bounds = New-Object System.Drawing.Rectangle(12, 84, 720, 190)
    $settingsLogText = New-Object System.Windows.Forms.TextBox
    $settingsLogText.Bounds = New-Object System.Drawing.Rectangle(16, 24, 688, 126)
    $settingsLogText.Multiline = $true
    $settingsLogText.ReadOnly = $true
    $settingsLogText.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $settingsLogText.WordWrap = $false
    $settingsLogCopyButton = New-Object System.Windows.Forms.Button
    $settingsLogCopyButton.Text = T 'Helper_VersionManager_Action_CopyAll' 'Copy all'
    $settingsLogCopyButton.Bounds = New-Object System.Drawing.Rectangle(16, 156, 96, 24)
    $settingsLogClearButton = New-Object System.Windows.Forms.Button
    $settingsLogClearButton.Text = T 'Helper_VersionManager_Action_ClearAll' 'Clear all'
    $settingsLogClearButton.Bounds = New-Object System.Drawing.Rectangle(120, 156, 96, 24)
    $settingsLogGroup.Controls.AddRange(@($settingsLogText, $settingsLogCopyButton, $settingsLogClearButton))
    $settingsTab.Controls.AddRange(@($settingsUtilityGroup, $settingsLogGroup))

    $loadingListItem = {
        param([string]$text)
        $item = New-Object System.Windows.Forms.ListViewItem([string]$text)
        return $item
    }

    $footerRefresh = New-Object System.Windows.Forms.Button
    $footerRefresh.Text = T 'Helper_VersionManager_Action_Refresh' 'Refresh'
    $footerRefresh.Bounds = New-Object System.Drawing.Rectangle(12, 353, 88, 28)
    $footerOpenDownloadPage = New-Object System.Windows.Forms.Button
    $footerOpenDownloadPage.Text = T 'Helper_VersionManager_Action_OpenReleasePage' 'Download page'
    $footerOpenDownloadPage.Bounds = New-Object System.Drawing.Rectangle(108, 353, 148, 28)
    $footerOpenRepositoryPage = New-Object System.Windows.Forms.Button
    $footerOpenRepositoryPage.Text = T 'Helper_VersionManager_Action_OpenRepositoryPage' 'GitHub page'
    $footerOpenRepositoryPage.Bounds = New-Object System.Drawing.Rectangle(264, 353, 148, 28)
    $footerClose = New-Object System.Windows.Forms.Button
    $footerClose.Text = T 'Helper_VersionManager_Common_Close' 'Close'
    $footerClose.Bounds = New-Object System.Drawing.Rectangle(660, 353, 112, 28)
    $footerClose.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $busyOverlay = New-Object System.Windows.Forms.Panel
    $busyOverlay.Bounds = New-Object System.Drawing.Rectangle(0, 0, 784, 393)
    $busyOverlay.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $busyOverlay.Visible = $false

    $busyOverlayCard = New-Object System.Windows.Forms.Panel
    $busyOverlayCard.Bounds = New-Object System.Drawing.Rectangle(150, 128, 484, 136)
    $busyOverlayCard.BackColor = [System.Drawing.Color]::White
    $busyOverlayCard.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $busyOverlayTitle = New-Object System.Windows.Forms.Label
    $busyOverlayTitle.Bounds = New-Object System.Drawing.Rectangle(22, 20, 438, 24)
    $busyOverlayTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $busyOverlayTitle.Text = T 'Helper_VersionManager_Busy_Title' 'Update in progress'

    $busyOverlayMessage = New-Object System.Windows.Forms.Label
    $busyOverlayMessage.Bounds = New-Object System.Drawing.Rectangle(22, 50, 438, 38)
    $busyOverlayMessage.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $busyOverlayMessage.Text = T 'Helper_VersionManager_Busy_Default' 'Downloading files and preparing skin data. Please do not close this window.'

    $busyOverlayProgress = New-Object System.Windows.Forms.ProgressBar
    $busyOverlayProgress.Bounds = New-Object System.Drawing.Rectangle(22, 102, 438, 16)
    $busyOverlayProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $busyOverlayProgress.MarqueeAnimationSpeed = 35

    $busyOverlayCard.Controls.AddRange(@($busyOverlayTitle, $busyOverlayMessage, $busyOverlayProgress))
    $busyOverlay.Controls.Add($busyOverlayCard)

    $form.Controls.AddRange(@($tabs, $footerRefresh, $footerOpenDownloadPage, $footerOpenRepositoryPage, $footerClose, $busyOverlay))
    $form.CancelButton = $footerClose
    $busyOverlay.BringToFront()

    $busyOverlayControls = @(
        $tabs,
        $footerRefresh,
        $footerOpenDownloadPage,
        $footerOpenRepositoryPage,
        $footerClose
    )

    $showBusyOverlay = {
        param([AllowNull()][string]$Message)

        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = T 'Helper_VersionManager_Busy_Default' 'Downloading files and preparing skin data. Please do not close this window.'
        }

        $busyOverlayTitle.Text = T 'Helper_VersionManager_Busy_Title' 'Update in progress'
        $busyOverlayMessage.Text = $Message

        if (-not $ui.BusyOverlayVisible) {
            $states = New-Object System.Collections.Generic.List[object]
            foreach ($control in @($busyOverlayControls)) {
                if ($null -ne $control) {
                    [void]$states.Add([PSCustomObject]@{
                        Control = $control
                        Enabled = [bool]$control.Enabled
                    })
                    $control.Enabled = $false
                }
            }
            $ui.BusyOverlayControlStates = @($states.ToArray())
            $ui.BusyOverlayVisible = $true
        }

        $form.UseWaitCursor = $true
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        $busyOverlay.Visible = $true
        $busyOverlay.Enabled = $true
        $busyOverlay.BringToFront()
        $busyOverlay.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }

    $hideBusyOverlay = {
        if ($ui.BusyOverlayVisible) {
            foreach ($entry in @($ui.BusyOverlayControlStates)) {
                $control = $entry.Control
                if ($null -ne $control -and -not $control.IsDisposed) {
                    $control.Enabled = [bool]$entry.Enabled
                }
            }
            $ui.BusyOverlayControlStates = @()
            $ui.BusyOverlayVisible = $false
        }

        $busyOverlay.Visible = $false
        $form.UseWaitCursor = $false
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
        [System.Windows.Forms.Application]::DoEvents()
    }

    $setCurrentVersionState = {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('latest', 'unknown', 'error', 'not-latest')][string]$State,
            [Parameter(Mandatory = $true)][string]$StatusText
        )

        $currentVersionStateIcon.Location = New-Object System.Drawing.Point(($currentVersionValue.Left + $currentVersionValue.PreferredWidth + 8), 27)
        $currentVersionStateIcon.Tag = $State
        $currentVersionStateIcon.BringToFront()
        $currentVersionStateIcon.Refresh()
        $currentVersionStatusText.Text = $StatusText
    }

    $handleInitialHydrationStageFailure = {
        param(
            [Parameter(Mandatory = $true)][string]$StageName,
            [Parameter(Mandatory = $true)][System.Exception]$Exception
        )

        switch ($StageName) {
            'summary' { [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary') }
            'installations' { [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations') }
            'settingsLog' { [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog') }
        }

        $message = if ([string]::IsNullOrWhiteSpace([string]$Exception.Message)) {
            T 'Helper_VersionManager_Common_LoadFailed' 'The requested data could not be loaded.'
        }
        else {
            [string]$Exception.Message
        }
        Write-Log ("Initial version manager hydration stage failed ({0}): {1}" -f $StageName, $Exception.ToString()) 'ERROR'

        switch ($StageName) {
            'summary' {
                $errorCode = Get-UpdateConfigurationErrorCode -Exception $Exception
                $friendlyStatus = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage $message -Surface 'summary'
                & $setCurrentVersionState 'error' $friendlyStatus
                $footerInstallLatest.Enabled = $false
            }
            'settingsLog' {
                $settingsLogText.Text = $message
                $settingsLogCopyButton.Enabled = $false
                $settingsLogClearButton.Enabled = $false
            }
            default {
                $installResult.Text = $message
            }
        }
    }

    $refreshSummary = {
        [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary')
        $completedRefresh = $false
        try {
            $ui.UpdateConfig = Get-UpdateConfiguration -Root $ui.Root
            $ui.UpdateCache = Get-UpdateCache -Root $ui.Root
            $updateConfigured = Test-UpdateConfigured -Config $ui.UpdateConfig

            if (-not $updateConfigured) {
                & $setCurrentVersionState 'error' (T 'Helper_VersionManager_Summary_UpdateUnconfigured' 'Update status: update source not configured')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            if ($ui.UpdateCheckInProgress -or -not $ui.HasSessionUpdateStatus) {
                & $setCurrentVersionState 'unknown' (T 'Helper_VersionManager_Summary_UpdateChecking' 'Update status: checking latest version...')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$ui.UpdateCache.Error)) {
                $friendlyStatus = Get-UpdateFriendlyMessage -ErrorCode ([string]$ui.UpdateCache.ErrorCode) -DefaultMessage ([string]$ui.UpdateCache.Error) -Surface 'summary'
                & $setCurrentVersionState 'error' $friendlyStatus
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            $latestComparableVersion = Convert-ToVersion -VersionText ([string]$ui.UpdateCache.LatestVersion)
            if ($latestComparableVersion -and $ui.TargetVersion -and ($latestComparableVersion -gt $ui.TargetVersion)) {
                & $setCurrentVersionState 'not-latest' (TF 'Helper_VersionManager_Summary_UpdateAvailable' @([string]$ui.UpdateCache.LatestVersion) 'Update status: update available (%1)')
                $footerInstallLatest.Enabled = -not $ui.UpdateCheckInProgress
                $completedRefresh = $true
                return
            }

            if ($latestComparableVersion -and $ui.TargetVersion -and ($latestComparableVersion -eq $ui.TargetVersion)) {
                & $setCurrentVersionState 'latest' (T 'Helper_VersionManager_Summary_UpdateLatest' 'Update status: current install is latest')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            & $setCurrentVersionState 'unknown' (T 'Helper_VersionManager_Summary_UpdateOlder' 'Update status: current install is newer than the latest release')
            $footerInstallLatest.Enabled = $false
            $completedRefresh = $true
        }
        catch {
            [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary')
            throw
        }
        finally {
            if ($completedRefresh) {
                [void](Complete-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary')
            }
        }
    }

    $testVersionCatalogEntryCurrent = {
        param([AllowNull()]$Entry)

        if ($null -eq $Entry) {
            return $false
        }

        $entryVersion = Convert-ToVersion -VersionText ([string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue ''))
        if ($entryVersion -and $ui.TargetVersion -and ($entryVersion -eq $ui.TargetVersion)) {
            return $true
        }

        $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
        return (-not [string]::IsNullOrWhiteSpace($installedPath) -and [string]::Equals((Resolve-FullPath -Path $installedPath -AllowMissing), (Resolve-FullPath -Path $ui.Root), [System.StringComparison]::OrdinalIgnoreCase))
    }

    $testVersionCatalogEntryActionable = {
        param([AllowNull()]$Entry)

        if ($ui.VersionCatalogOperationInProgress -or $null -eq $Entry) {
            return $false
        }
        if (& $testVersionCatalogEntryCurrent $Entry) {
            return $false
        }
        $entryVersion = Convert-ToVersion -VersionText ([string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue ''))
        $status = [string](Get-ObjectPropertyValue -Object $Entry -Name 'status' -DefaultValue '')
        $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
        $assetUrl = [string](Get-ObjectPropertyValue -Object $Entry -Name 'asset_url' -DefaultValue '')
        $isLatestStable = [bool](Get-ObjectPropertyValue -Object $Entry -Name 'is_latest_stable' -DefaultValue $false)
        if ($isLatestStable) {
            if (-not [string]::IsNullOrWhiteSpace($installedPath)) {
                return $true
            }
            return ($entryVersion -and $ui.TargetVersion -and ($entryVersion -gt $ui.TargetVersion) -and -not [string]::IsNullOrWhiteSpace($assetUrl))
        }

        if ([string]::Equals($status, 'installed', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($installedPath)) {
            return $true
        }

        return ([string]::Equals($status, 'available', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($assetUrl))
    }

    $formatVersionCatalogStatus = {
        param([AllowNull()]$Entry)

        $parts = New-Object System.Collections.Generic.List[string]
        $isLatestStable = [bool](Get-ObjectPropertyValue -Object $Entry -Name 'is_latest_stable' -DefaultValue $false)
        if ($isLatestStable -and -not (& $testVersionCatalogEntryCurrent $Entry)) {
            [void]$parts.Add((T 'Helper_VersionManager_Update_StatusLatest' (U '\uAC00\uC7A5 \uCD5C\uC2E0 \uBC84\uC804')))
        }
        if (& $testVersionCatalogEntryCurrent $Entry) {
            [void]$parts.Add((T 'Helper_VersionManager_Update_StatusCurrent' 'current'))
        }

        $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($installedPath) -and -not (& $testVersionCatalogEntryCurrent $Entry)) {
            [void]$parts.Add((T 'Helper_VersionManager_Update_StatusLocal' 'local install'))
        }

        $status = [string](Get-ObjectPropertyValue -Object $Entry -Name 'status' -DefaultValue '')
        switch -Regex ($status) {
            '^latest_stable$' {
                if (-not (& $testVersionCatalogEntryCurrent $Entry) -and [string]::IsNullOrWhiteSpace($installedPath)) {
                    $assetUrl = [string](Get-ObjectPropertyValue -Object $Entry -Name 'asset_url' -DefaultValue '')
                    if (-not [string]::IsNullOrWhiteSpace($assetUrl)) {
                        [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAvailable' 'available'))
                    } else {
                        [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAssetMissing' 'download asset missing'))
                    }
                }
            }
            '^available$' {
                if (-not (& $testVersionCatalogEntryCurrent $Entry)) {
                    [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAvailable' 'available'))
                }
            }
            '^installed$' {
                if ([string]::IsNullOrWhiteSpace($installedPath)) {
                    [void]$parts.Add((T 'Helper_VersionManager_Update_StatusInstalled' 'installed'))
                }
            }
            '^asset_missing$' { [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAssetMissing' 'download asset missing')) }
            default {
                if (-not [string]::IsNullOrWhiteSpace($status)) {
                    [void]$parts.Add($status)
                }
            }
        }

        if ($parts.Count -eq 0) {
            return (T 'Helper_VersionManager_Update_StatusUnknown' 'unknown')
        }
        return ($parts.ToArray() -join ' / ')
    }

    $syncVersionCatalogSelectionState = {
        $versionCatalogInstallButton.Enabled = (& $testVersionCatalogEntryActionable $ui.SelectedVersionCatalogEntry)
    }

    $syncInstallationSelectionState = {
        $entry = $ui.SelectedInstallation
        $canUseSelected = ($null -ne $entry) -and
            (-not [bool]$entry.IsCurrent) -and
            [bool]$entry.IsValid -and
            (-not $ui.InstallationOperationInProgress)
        $canImportSelected = ($null -ne $entry) -and
            [bool]$entry.ImportAllowed -and
            (-not $ui.InstallationOperationInProgress)
        $canDeleteSelected = ($null -ne $entry) -and
            (-not [bool]$entry.IsCurrent) -and
            ($entry.Source -eq 'manual' -or $entry.Source -eq 'auto') -and
            (-not $ui.InstallationOperationInProgress)

        $installButtons.UseVersion.Enabled = $canUseSelected
        $installButtons.Import.Enabled = $canImportSelected
        $installButtons.Delete.Enabled = $canDeleteSelected
    }

    $refreshVersionCatalog = {
        if ($ui.VersionCatalogOperationInProgress) {
            return
        }

        $ui.VersionCatalogOperationInProgress = $true
        $ui.VersionCatalog = $null
        $ui.VersionCatalogEntries = @()
        $ui.SelectedVersionCatalogEntry = $null
        $versionCatalogInstallButton.Enabled = $false
        $versionCatalogList.Enabled = $false
        $versionCatalogList.BeginUpdate()
        try {
            $versionCatalogList.Items.Clear()
            [void]$versionCatalogList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
        }
        finally {
            $versionCatalogList.EndUpdate()
        }
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $ui.TargetVersionText = Get-SkinMetadataVersion -Root $ui.Root
            $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
            $ui.VersionCatalog = Invoke-VersionReleaseCatalog -Root $ui.Root
            $ui.VersionCatalogEntries = @($ui.VersionCatalog.releases)

            $versionCatalogList.BeginUpdate()
            $versionCatalogList.Items.Clear()
            foreach ($entry in $ui.VersionCatalogEntries) {
                $versionText = [string](Get-ObjectPropertyValue -Object $entry -Name 'version' -DefaultValue '')
                $releaseName = [string](Get-ObjectPropertyValue -Object $entry -Name 'release_name' -DefaultValue '')
                if ([string]::IsNullOrWhiteSpace($releaseName)) {
                    $releaseName = [string](Get-ObjectPropertyValue -Object $entry -Name 'tag' -DefaultValue '')
                }
                $item = New-Object System.Windows.Forms.ListViewItem($versionText)
                [void]$item.SubItems.Add($releaseName)
                [void]$item.SubItems.Add((& $formatVersionCatalogStatus $entry))
                $item.Tag = $entry
                [void]$versionCatalogList.Items.Add($item)
            }

            if ($versionCatalogList.Items.Count -eq 0) {
                $emptyItem = New-Object System.Windows.Forms.ListViewItem('')
                [void]$emptyItem.SubItems.Add('')
                [void]$emptyItem.SubItems.Add((T 'Helper_VersionManager_Update_VersionCatalogEmpty' 'No releases were found.'))
                [void]$versionCatalogList.Items.Add($emptyItem)
            }
        }
        catch {
            Write-Log ("Version catalog load failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            $versionCatalogList.BeginUpdate()
            $versionCatalogList.Items.Clear()
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            $friendlyMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
            $errorItem = New-Object System.Windows.Forms.ListViewItem('')
            [void]$errorItem.SubItems.Add('')
            [void]$errorItem.SubItems.Add($friendlyMessage)
            [void]$versionCatalogList.Items.Add($errorItem)
        }
        finally {
            $versionCatalogList.EndUpdate()
            $ui.VersionCatalogOperationInProgress = $false
            $versionCatalogList.Enabled = $true
            if ($versionCatalogList.Items.Count -gt 0 -and $null -ne $versionCatalogList.Items[0].Tag) {
                $versionCatalogList.Items[0].Selected = $true
                $versionCatalogList.Items[0].Focused = $true
            }
            & $syncVersionCatalogSelectionState
        }
    }

    $selectVersionCatalogEntry = {
        param([AllowNull()]$Entry)

        $ui.SelectedVersionCatalogEntry = $Entry
        foreach ($item in @($versionCatalogList.Items)) {
            $item.Selected = $false
            $item.Focused = $false
        }

        if ($null -eq $Entry) {
            & $syncVersionCatalogSelectionState
            return
        }

        $entryVersion = [string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue '')
        $entryTag = [string](Get-ObjectPropertyValue -Object $Entry -Name 'tag' -DefaultValue '')
        foreach ($item in @($versionCatalogList.Items)) {
            $candidate = $item.Tag
            if ($null -eq $candidate) {
                continue
            }

            $candidateVersion = [string](Get-ObjectPropertyValue -Object $candidate -Name 'version' -DefaultValue '')
            $candidateTag = [string](Get-ObjectPropertyValue -Object $candidate -Name 'tag' -DefaultValue '')
            if ([string]::Equals($candidateVersion, $entryVersion, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals($candidateTag, $entryTag, [System.StringComparison]::OrdinalIgnoreCase)) {
                $item.Selected = $true
                $item.Focused = $true
                $item.EnsureVisible()
                break
            }
        }

        & $syncVersionCatalogSelectionState
    }

    $getLatestVersionCatalogEntryForInstall = {
        if ($ui.VersionCatalogOperationInProgress) {
            return $null
        }

        & $refreshVersionCatalog

        $latestEntry = $null
        foreach ($entry in @($ui.VersionCatalogEntries)) {
            $isLatestStable = [bool](Get-ObjectPropertyValue -Object $entry -Name 'is_latest_stable' -DefaultValue $false)
            if ($isLatestStable) {
                $latestEntry = $entry
                break
            }
        }

        if ($null -eq $latestEntry -and @($ui.VersionCatalogEntries).Count -gt 0) {
            $latestEntry = @($ui.VersionCatalogEntries)[0]
        }

        if ($null -eq $latestEntry) {
            throw (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.')
        }

        if (-not (& $testVersionCatalogEntryActionable $latestEntry)) {
            throw (T 'Helper_VersionManager_Update_LatestCatalogInstallUnavailable' 'The latest version is not available for selected-version installation.')
        }

        return $latestEntry
    }

    $refreshInstallations = {
        [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
        $completedRefresh = $false
        try {
            $ui.Installations = @(Get-Installations -Root $ui.Root)
            $ui.CurrentInstallation = $null
            $ui.OtherInstallations = @()
            foreach ($entry in $ui.Installations) {
                if ($entry.IsCurrent -and -not $ui.CurrentInstallation) {
                    $ui.CurrentInstallation = $entry
                }
                elseif (-not $entry.IsCurrent) {
                    $ui.OtherInstallations += ,$entry
                }
            }

            if ($ui.CurrentInstallation) {
                $currentVersionValue.Text = [string]$ui.CurrentInstallation.VersionText
            }
            else {
                $currentVersionValue.Text = ''
            }

            $otherInstallList.BeginUpdate()
            $otherInstallList.Items.Clear()
            foreach ($entry in $ui.OtherInstallations) {
                $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Status)
                [void]$item.SubItems.Add([string]$entry.VersionText)
                [void]$item.SubItems.Add([string]$entry.Label)
                [void]$item.SubItems.Add([string]$entry.Path)
                $item.Tag = $entry
                [void]$otherInstallList.Items.Add($item)
            }
            $otherInstallList.EndUpdate()
            if ($otherInstallList.Items.Count -gt 0) {
                $otherInstallList.Items[0].Selected = $true
                $otherInstallList.Items[0].Focused = $true
                $ui.SelectedInstallation = $otherInstallList.Items[0].Tag
            }
            else {
                $ui.SelectedInstallation = $null
            }
            & $syncInstallationSelectionState
            $completedRefresh = $true
        }
        catch {
            [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
            throw
        }
        finally {
            if ($completedRefresh) {
                [void](Complete-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
            }
        }
    }

    $refreshSettingsTab = {
        [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
        $completedRefresh = $false
        try {
            $logView = Get-VersionManagerLogView -Root $ui.Root -CurrentLogPath $script:LogPath
            $ui.SettingsLogHasContent = [bool]$logView.HasContent
            $settingsLogText.Text = [string]$logView.Text
            $settingsLogCopyButton.Enabled = [bool]$logView.HasContent
            $settingsLogClearButton.Enabled = [bool]$logView.HasContent
            $completedRefresh = $true
        }
        catch {
            [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
            throw
        }
        finally {
            if ($completedRefresh) {
                [void](Complete-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
            }
        }
    }

    $setVersionManagerTabsDirty = {
        param([string[]]$TabNames)

        foreach ($tabName in @($TabNames)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$tabName)) {
                [void](Set-VersionManagerTabDirty -TabStates $ui.TabStates -TabName ([string]$tabName))
            }
        }
    }

    $setVersionManagerTabsDirtyForLatestStateMutation = {
        & $setVersionManagerTabsDirty @('summary', 'settingsLog')
    }

    $setVersionManagerTabsDirtyForInstallationMutation = {
        & $setVersionManagerTabsDirty @('installations')
    }

    $setVersionManagerTabsDirtyForGlobalMutation = {
        [void](Set-VersionManagerAllTabsDirty -TabStates $ui.TabStates)
    }

    $refreshAll = {
        & $setVersionManagerTabsDirtyForGlobalMutation
        $ui.TargetVersionText = Get-SkinMetadataVersion -Root $ui.Root
        $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
        & $refreshSummary
        & $refreshVersionCatalog
        & $refreshInstallations
        & $refreshSettingsTab
    }

    $runLatestCheck = {
        param([bool]$Silent)

        if ($ui.UpdateCheckInProgress) {
            return
        }

        $requestTicket = Start-VersionManagerOwnedRequest -State $ui.LatestCheckRequestState
        $requestCompleted = $false
        try {
            $ui.UpdateCheckInProgress = $true
            & $refreshSummary
            [System.Windows.Forms.Application]::DoEvents()
            $existingCache = Get-UpdateCache -Root $ui.Root
            $latestCache = Invoke-CheckLatestRelease -Root $ui.Root -Config (Get-UpdateConfiguration -Root $ui.Root)
            if (-not (Test-VersionManagerOwnedRequestCurrent -State $ui.LatestCheckRequestState -Ticket $requestTicket)) {
                return
            }
            $latestCache = Merge-LatestCheckSuccessCache -ExistingCache $existingCache -LatestCache $latestCache
            $latestCache = Save-UpdateCache -Root $ui.Root -Cache $latestCache
            [void](Complete-VersionManagerOwnedRequest -State $ui.LatestCheckRequestState -Ticket $requestTicket)
            $requestCompleted = $true
            $ui.UpdateCache = $latestCache
            $ui.HasSessionUpdateStatus = $true
            $ui.UpdateCheckInProgress = $false
            & $setVersionManagerTabsDirtyForLatestStateMutation
            & $refreshSummary
            & $refreshSettingsTab
        }
        catch {
            if (-not (Test-VersionManagerOwnedRequestCurrent -State $ui.LatestCheckRequestState -Ticket $requestTicket)) {
                return
            }
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            Write-Log ("Latest version check failed ({0}): {1}" -f $errorCode, $_.Exception.ToString()) 'ERROR'
            $existingCache = Get-UpdateCache -Root $ui.Root
            $failedCache = Update-UpdateCache -Root $ui.Root -Patch (New-LatestCheckFailureCachePatch -ExistingCache $existingCache -ErrorMessage $_.Exception.Message -ErrorCode $errorCode -UpdateConfig $ui.UpdateConfig)
            [void](Complete-VersionManagerOwnedRequest -State $ui.LatestCheckRequestState -Ticket $requestTicket)
            $requestCompleted = $true
            $ui.UpdateCache = $failedCache
            $ui.HasSessionUpdateStatus = $true
            $ui.UpdateCheckInProgress = $false
            & $setVersionManagerTabsDirtyForLatestStateMutation
            & $refreshSummary
            & $refreshSettingsTab
            if (-not $Silent) {
                $dialogMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
                [System.Windows.Forms.MessageBox]::Show($form, $dialogMessage, $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
        finally {
            if (-not $requestCompleted) {
                [void](Clear-VersionManagerOwnedRequest -State $ui.LatestCheckRequestState -Ticket $requestTicket)
            }
        }
    }

    $installLatestVersion = {
        if ($ui.UpdateCheckInProgress -or $ui.VersionCatalogOperationInProgress) {
            return
        }

        try {
            $config = Get-UpdateConfiguration -Root $ui.Root
            if (-not (Test-UpdateConfigured -Config $config)) {
                throw (T 'Helper_VersionManager_Update_SourceUnconfigured' 'The update source is not configured yet.')
            }

            $latestEntry = & $getLatestVersionCatalogEntryForInstall
            if ($null -eq $latestEntry) {
                return
            }

            $latestComparableVersion = Convert-ToVersion -VersionText ([string](Get-ObjectPropertyValue -Object $latestEntry -Name 'version' -DefaultValue ''))
            if (-not $latestComparableVersion -or -not $ui.TargetVersion -or ($latestComparableVersion -le $ui.TargetVersion)) {
                return
            }

            & $selectVersionCatalogEntry $latestEntry
            & $installVersionCatalogEntry $latestEntry $true
        }
        catch {
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            Write-Log ("Latest version update failed ({0}): {1}" -f $errorCode, $_.Exception.ToString()) 'ERROR'
            $ui.UpdateCheckInProgress = $false
            & $refreshSummary
            $dialogMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
            [System.Windows.Forms.MessageBox]::Show($form, $dialogMessage, $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }

    $otherInstallList.Add_SelectedIndexChanged({
        $ui.SelectedInstallation = if ($otherInstallList.SelectedItems.Count -gt 0) { $otherInstallList.SelectedItems[0].Tag } else { $null }
        & $syncInstallationSelectionState
    })

    $versionCatalogList.Add_SelectedIndexChanged({
        $ui.SelectedVersionCatalogEntry = if ($versionCatalogList.SelectedItems.Count -gt 0) { $versionCatalogList.SelectedItems[0].Tag } else { $null }
        & $syncVersionCatalogSelectionState
    })

    $installButtons.UseVersion.Add_Click({
        if ($ui.InstallationOperationInProgress) {
            return
        }

        $entry = $ui.SelectedInstallation
        if ($null -eq $entry -or [bool]$entry.IsCurrent -or -not [bool]$entry.IsValid) {
            return
        }

        try {
            $confirmLines = @(
                (T 'Helper_VersionManager_Install_UseSelectedConfirm' (U '\uC120\uD0DD\uD55C \uC2A4\uD0A8\uC744 \uC0AC\uC6A9\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?')),
                '',
                (TF 'Helper_VersionManager_Install_UseSelectedSource' @([string]$entry.Path) 'Target: %1')
            )
            if (Test-VersionManagerUnsupportedVersionText -VersionText ([string]$entry.VersionText)) {
                $confirmLines += ''
                $confirmLines += (Get-Pre12VersionManagerNotice)
            }
            if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", $confirmLines)))) {
                return
            }

            $ui.InstallationOperationInProgress = $true
            & $syncInstallationSelectionState
            & $showBusyOverlay (T 'Helper_VersionManager_Busy_Switching' 'Switching to the selected installation. Please do not close this window.')
            try {
                $result = Invoke-VersionReleaseInstall -Root $ui.Root -SelectedTargetRoot ([string]$entry.Path)
            }
            finally {
                & $hideBusyOverlay
            }

            if ([string]::Equals([string]$result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$result.Status, 'NOOP', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $result.SourcePath
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $result.LogPath
                }
                & $setVersionManagerTabsDirtyForGlobalMutation
                [void](Start-VersionManagerLauncherForSupportedRoot -ResolvedTargetRoot ([string]$result.SourcePath))
                Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$result.Status)
                $ui.CloseAfterSwitch = $true
                $form.Close()
                return
            }

            $switchFailureMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                (T 'Helper_VersionManager_Install_UseSelectedFailed' 'The selected skin could not be activated. Check the log file for details.')
            }
            else {
                [string]$result.Message
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                $switchFailureMessage += "`r`n`r`n" + [string]$result.LogPath
            }
            [System.Windows.Forms.MessageBox]::Show($form, $switchFailureMessage, $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        catch {
            Write-Log ("Installed skin switch failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Install_UseSelectedFailed' 'The selected skin could not be activated. Check the log file for details.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        finally {
            & $hideBusyOverlay
            $ui.InstallationOperationInProgress = $false
            & $syncInstallationSelectionState
        }
    })

    $installVersionCatalogEntry = {
        param(
            [AllowNull()]$entry,
            [bool]$SkipInitialConfirm = $false
        )

        if ($ui.VersionCatalogOperationInProgress) {
            return
        }

        if (-not (& $testVersionCatalogEntryActionable $entry)) {
            return
        }

        $versionText = [string](Get-ObjectPropertyValue -Object $entry -Name 'version' -DefaultValue '')
        $tagText = [string](Get-ObjectPropertyValue -Object $entry -Name 'tag' -DefaultValue '')
        $expectedVersion = if ([string]::IsNullOrWhiteSpace($tagText)) { $versionText } else { $tagText }
        $assetUrl = [string](Get-ObjectPropertyValue -Object $entry -Name 'asset_url' -DefaultValue '')
        $installedPath = [string](Get-ObjectPropertyValue -Object $entry -Name 'installed_path' -DefaultValue '')
        $isInstalled = -not [string]::IsNullOrWhiteSpace($installedPath)
        $isPre12Target = Test-VersionManagerUnsupportedVersionText -VersionText $versionText

        try {
            $confirmMessage = if ($isInstalled) {
                $confirmLines = @(
                    (TF 'Helper_VersionManager_Update_VersionAlreadyInstalledConfirm' @($expectedVersion) (U '\uC774 \uBC84\uC804\uC758 \uC2A4\uD0A8\uC774 \uC774\uBBF8 \uCEF4\uD4E8\uD130\uC5D0 \uC124\uCE58\uB3FC \uC788\uC2B5\uB2C8\uB2E4.')),
                    '',
                    (T 'Helper_VersionManager_Update_VersionUseInstalledConfirm' (U '\uC774 \uBC84\uC804\uC744 \uC0AC\uC6A9\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?'))
                )
                if ($isPre12Target) {
                    $confirmLines += ''
                    $confirmLines += (Get-Pre12VersionManagerNotice)
                }
                [string]::Join("`r`n", $confirmLines)
            }
            else {
                $confirmLines = @(
                    (TF 'Helper_VersionManager_Update_VersionInstallConfirm' @($expectedVersion) (U '\uC774 \uBC84\uC804\uC744 \uC124\uCE58\uD560\uAE4C\uC694?')),
                    '',
                    (T 'Helper_VersionManager_Update_VersionInstallDataNotice' (U '\uC124\uCE58 \uC804 \uD604\uC7AC \uB370\uC774\uD130 \uC5F0\uB3D9 \uD638\uD658\uC131\uC744 \uD655\uC778\uD569\uB2C8\uB2E4.'))
                )
                if ($isPre12Target) {
                    $confirmLines += ''
                    $confirmLines += (Get-Pre12VersionManagerNotice)
                }
                [string]::Join("`r`n", $confirmLines)
            }
            if (-not $SkipInitialConfirm) {
                if (-not (Confirm-Dialog -Owner $form -Message $confirmMessage)) {
                    return
                }
            }

            $ui.VersionCatalogOperationInProgress = $true
            & $syncVersionCatalogSelectionState
            $busyMessage = if ($isInstalled) {
                T 'Helper_VersionManager_Busy_Switching' 'Switching to the selected installation. Please do not close this window.'
            }
            else {
                T 'Helper_VersionManager_Busy_InstallingSelected' 'Installing the selected version. Please do not close this window.'
            }
            & $showBusyOverlay $busyMessage
            try {
                $result = if ($isInstalled) {
                    Invoke-VersionReleaseInstall -Root $ui.Root -SelectedTargetRoot $installedPath
                }
                else {
                    Invoke-VersionReleaseInstall -Root $ui.Root -PackageUrl $assetUrl -ExpectedVersion $expectedVersion
                }
            }
            finally {
                & $hideBusyOverlay
            }
            if ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase) -and -not $isInstalled) {
                $warningMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                    (T 'Helper_VersionManager_Update_CompatibilityWarn' (U '\uD604\uC7AC \uB370\uC774\uD130\uC640 \uC120\uD0DD\uD55C \uBC84\uC804\uC758 \uC5F0\uB3D9\uC774 \uC644\uC804\uD788 \uD638\uD658\uB418\uC9C0 \uC54A\uC744 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uB370\uC774\uD130 \uC190\uC2E4\uC774 \uBC1C\uC0DD\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.'))
                }
                else {
                    [string]$result.Message
                }
                if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", @(
                    $warningMessage,
                    '',
                    (T 'Helper_VersionManager_Update_CompatibilityWarnProceed' (U '\uADF8\uB798\uB3C4 \uC124\uCE58\uB97C \uACC4\uC18D\uD560\uAE4C\uC694?'))
                ))))) {
                    return
                }
                & $showBusyOverlay (T 'Helper_VersionManager_Busy_InstallingSelected' 'Installing the selected version. Please do not close this window.')
                try {
                    $result = Invoke-VersionReleaseInstall -Root $ui.Root -PackageUrl $assetUrl -ExpectedVersion $expectedVersion -AllowCompatibilityWarning
                }
                finally {
                    & $hideBusyOverlay
                }
            }
            if ([string]::Equals([string]$result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$result.Status, 'NOOP', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $result.SourcePath
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $result.LogPath
                }
                & $setVersionManagerTabsDirtyForGlobalMutation
                [void](Start-VersionManagerLauncherForSupportedRoot -ResolvedTargetRoot ([string]$result.SourcePath))
                Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$result.Status)
                $ui.CloseAfterSwitch = $true
                $form.Close()
                return
            }

            $dialogIcon = [System.Windows.Forms.MessageBoxIcon]::Error
            $dialogMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                (T 'Helper_VersionManager_Update_ApplyFailed' 'The update could not be applied. Check the log file for details.')
            }
            else {
                [string]$result.Message
            }
            if ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase)) {
                $dialogIcon = [System.Windows.Forms.MessageBoxIcon]::Warning
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                $dialogMessage += "`r`n`r`n" + [string]$result.LogPath
            }
            [System.Windows.Forms.MessageBox]::Show($form, $dialogMessage, $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, $dialogIcon) | Out-Null
        }
        catch {
            Write-Log ("Version catalog install failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Update_ApplyFailed' 'The update could not be applied. Check the log file for details.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        finally {
            & $hideBusyOverlay
            $ui.VersionCatalogOperationInProgress = $false
            & $syncVersionCatalogSelectionState
            if (-not $ui.CloseAfterSwitch) {
                & $refreshVersionCatalog
                & $refreshSettingsTab
            }
        }
    }

    $versionCatalogInstallButton.Add_Click({
        & $installVersionCatalogEntry $ui.SelectedVersionCatalogEntry
    })

    $installButtons.Import.Add_Click({
        try {
            $entry = $ui.SelectedInstallation
            if ($null -eq $entry -or -not $entry.ImportAllowed) {
                return
            }
            if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", @(
                (T 'Helper_VersionManager_Import_ConfirmIntro' 'Import the selected installation data into the current version.'),
                '',
                (TF 'Helper_VersionManager_Import_ConfirmSource' @([string]$entry.Path) 'Source: %1')
            ))))) {
                return
            }

            $result = Invoke-ImportFromInstallation -Root $ui.Root -SourcePath ([string]$entry.Path)
            $installResult.Text = [string]$result.Message
            if ($result.Status -eq 'OK') {
                if (-not [string]::IsNullOrWhiteSpace($result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $result.SourcePath
                }
                if (-not [string]::IsNullOrWhiteSpace($result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $result.LogPath
                }
                Invoke-RainmeterBang -Bang '!RefreshGroup' -Arguments @('DMeloper')
                [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Import_Success' 'Old-data import completed.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            elseif ($result.Status -eq 'CANCEL') {
                [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Import_Canceled' 'Old-data import was canceled.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            else {
                [System.Windows.Forms.MessageBox]::Show($form, ([string]$result.Message + "`r`n`r`n" + [string]$result.LogPath), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            & $setVersionManagerTabsDirtyForGlobalMutation
            & $refreshAll
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Import_Failed' 'Old-data import failed. Check the log file for details.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $installButtons.Delete.Add_Click({
        try {
            $entry = $ui.SelectedInstallation
            if ($null -eq $entry -or [bool]$entry.IsCurrent) {
                return
            }
            $confirmMessage = if ($entry.Source -eq 'manual') {
                T 'Helper_VersionManager_SourceDialog_DeleteConfirm' 'Remove this item from the manual source list. The actual folder is not deleted.'
            }
            else {
                [string]::Join("`r`n", @(
                    (T 'Helper_VersionManager_Install_DeleteInstalledConfirm' (U '\uC120\uD0DD\uD55C \uC2A4\uD0A8 \uD3F4\uB354\uB97C \uD734\uC9C0\uD1B5\uC73C\uB85C \uBCF4\uB0BC\uAE4C\uC694?')),
                    '',
                    (TF 'Helper_VersionManager_Install_DeleteInstalledSource' @([string]$entry.Path) 'Folder: %1')
                ))
            }
            if (-not (Confirm-Dialog -Owner $form -Message $confirmMessage)) {
                return
            }

            if ($entry.Source -eq 'manual') {
                $next = foreach ($item in @(Read-SourceRegistry -Root $ui.Root)) {
                    if (-not [string]::Equals([string]$item.Path, [string]$entry.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $item
                    }
                }
                Write-SourceRegistry -Root $ui.Root -Entries @($next)
            }
            else {
                Remove-InstalledSkinFolder -Path ([string]$entry.Path) -CurrentRoot $ui.Root
            }
            & $setVersionManagerTabsDirtyForInstallationMutation
            & $refreshInstallations
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Install_DeleteFailed' 'The selected skin could not be removed. Check the log file for details.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $footerRefresh.Add_Click({
        & $refreshAll
    })
    $footerCheckLatest.Add_Click({
        & $runLatestCheck $false
    })
    $footerInstallLatest.Add_Click({
        & $installLatestVersion
    })
    $settingsOpenLogButton.Add_Click({
        $logFolder = Split-Path -Parent (Get-LatestHelperLogPath -Root $ui.Root)
        if ([string]::IsNullOrWhiteSpace($logFolder)) {
            $logFolder = Get-VersionManagerLogsRoot -Root $ui.Root
        }
        Open-FolderPath -Path $logFolder
    })
    $footerOpenDownloadPage.Add_Click({
        Start-Process -FilePath (Get-VersionManagerDownloadPageUrl)
    })
    $footerOpenRepositoryPage.Add_Click({
        Start-Process -FilePath (Get-VersionManagerRepositoryUrl -Root $ui.Root)
    })
    $settingsOpenSkinButton.Add_Click({
        Open-FolderPath -Path $ui.Root
    })
    $settingsLogCopyButton.Add_Click({
        if (-not $ui.SettingsLogHasContent) {
            return
        }

        try {
            [System.Windows.Forms.Clipboard]::SetText([string]$settingsLogText.Text)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Log_CopyFailed' 'Could not copy the log text.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })
    $settingsLogClearButton.Add_Click({
        if (-not $ui.SettingsLogHasContent) {
            return
        }

        if (-not (Confirm-Dialog -Owner $form -Message (T 'Helper_VersionManager_Log_ClearConfirm' 'Delete the skin log file contents and clear the current session log view?'))) {
            return
        }

        try {
            Clear-VersionManagerLogs -Root $ui.Root -CurrentLogPath $script:LogPath
            & $setVersionManagerTabsDirty 'settingsLog'
            & $refreshSettingsTab
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, (T 'Helper_VersionManager_Log_ClearFailed' 'The logs could not be cleared. Check the log file for details.'), $form.Text, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $currentVersionValue.Text = [string]$ui.TargetVersionText
    & $setCurrentVersionState 'unknown' (T 'Helper_VersionManager_Summary_UpdateChecking' 'Update status: checking latest version...')
    $footerRefresh.Enabled = $false
    $footerCheckLatest.Enabled = $false
    $footerInstallLatest.Enabled = $false
    $versionCatalogInstallButton.Enabled = $false
    $installButtons.UseVersion.Enabled = $false
    $installButtons.Import.Enabled = $false
    $installButtons.Delete.Enabled = $false
    $settingsLogCopyButton.Enabled = $false
    $settingsLogClearButton.Enabled = $false
    [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
    [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
    [void]$otherInstallList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
    [void]$versionCatalogList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
    $settingsLogText.Text = T 'Helper_VersionManager_Common_Loading' 'Loading...'

    $autoCheckTimer = New-Object System.Windows.Forms.Timer
    $autoCheckTimer.Interval = 200
    $autoCheckTimer.Add_Tick({
        $autoCheckTimer.Stop()
        & $runLatestCheck $true
    })

    $initialHydrationStages = @(
        [PSCustomObject]@{
            Name = 'summary'
            Action = {
                & $refreshSummary
            }
        },
        [PSCustomObject]@{
            Name = 'finalize'
            Action = {
                $ui.InitialHydrationCompleted = $true
                $footerRefresh.Enabled = $true
                $footerCheckLatest.Enabled = $true
                if ($deferredHydrationStages.Count -gt 0) {
                    $deferredHydrationTimer.Start()
                }
                elseif (-not $ui.HasSessionUpdateStatus -and -not $ui.UpdateCheckInProgress) {
                    $autoCheckTimer.Start()
                }
            }
        }
    )

    $deferredHydrationStages = @(
        [PSCustomObject]@{
            Name = 'versionCatalog'
            Action = {
                & $refreshVersionCatalog
            }
        },
        [PSCustomObject]@{
            Name = 'installations'
            Action = {
                & $refreshInstallations
            }
        },
        [PSCustomObject]@{
            Name = 'settingsLog'
            Action = {
                & $refreshSettingsTab
            }
        }
    )

    $initialHydrationTimer = New-Object System.Windows.Forms.Timer
    $initialHydrationTimer.Interval = 1
    $initialHydrationTimer.Add_Tick({
        $initialHydrationTimer.Stop()
        if ($ui.InitialHydrationCompleted) {
            return
        }
        if ($ui.InitialHydrationStageIndex -ge $initialHydrationStages.Count) {
            return
        }

        $stage = $initialHydrationStages[$ui.InitialHydrationStageIndex]
        try {
            & $stage.Action
        }
        catch {
            & $handleInitialHydrationStageFailure ([string]$stage.Name) $_.Exception
        }
        finally {
            $ui.InitialHydrationStageIndex += 1
            if ($ui.InitialHydrationStageIndex -lt $initialHydrationStages.Count) {
                $initialHydrationTimer.Start()
            }
        }
    })

    $deferredHydrationTimer = New-Object System.Windows.Forms.Timer
    $deferredHydrationTimer.Interval = 25
    $deferredHydrationTimer.Add_Tick({
        $deferredHydrationTimer.Stop()
        if ($ui.DeferredHydrationStageIndex -ge $deferredHydrationStages.Count) {
            return
        }

        $stage = $deferredHydrationStages[$ui.DeferredHydrationStageIndex]
        try {
            & $stage.Action
        }
        catch {
            & $handleInitialHydrationStageFailure ([string]$stage.Name) $_.Exception
        }
        finally {
            $ui.DeferredHydrationStageIndex += 1
            if ($ui.DeferredHydrationStageIndex -lt $deferredHydrationStages.Count) {
                $deferredHydrationTimer.Start()
            }
            elseif (-not $ui.HasSessionUpdateStatus -and -not $ui.UpdateCheckInProgress) {
                $autoCheckTimer.Start()
            }
        }
    })

    $form.Add_Shown({
        Save-VersionManagerLaunchState -Root $ui.Root -Status 'shown' -LaunchTokenValue $LaunchToken
        $initialHydrationTimer.Start()
    })
    [void]$form.ShowDialog()
}

try {
    Write-Log ('TargetRoot: ' + (Get-TargetRoot))
    if ($WindowSession) {
        Start-VersionManager
        if (-not [string]::IsNullOrWhiteSpace([string]$script:ResultPairs['DMEL_STATUS'])) {
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Result_ClosedAfterOperation' 'Skins closed after completing an operation.')
        }
        else {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Result_Closed' 'Skins closed.')
        }
    }
    else {
        $launchResult = Start-VersionManagerLauncher
        if ([string]::Equals([string]$launchResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Result_Launched' 'Skins opened.')
        }
        elseif ([string]::Equals([string]$launchResult.Status, 'ERROR', [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
            $launchErrorMessage = [string]$launchResult.Message
            if ([string]::IsNullOrWhiteSpace($launchErrorMessage)) {
                $launchErrorMessage = (T 'Helper_VersionManager_Result_OpenFailed' 'Skins could not be opened. Check the log file for details.')
            }
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $launchErrorMessage
        }
        else {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
            $launchWarningMessage = [string]$launchResult.Message
            if ([string]::IsNullOrWhiteSpace($launchWarningMessage)) {
                $launchWarningMessage = 'Skins launch confirmation timed out; Settings will keep watching for the window state.'
            }
            Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $launchWarningMessage
            Write-Log $launchWarningMessage 'WARN'
        }
    }
}
catch {
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value (T 'Helper_VersionManager_Result_OpenFailed' 'Skins could not be opened. Check the log file for details.')
    try {
        $failedRoot = Get-TargetRoot
        if (-not [string]::IsNullOrWhiteSpace($failedRoot) -and (Test-Path -LiteralPath $failedRoot -PathType Container)) {
            Save-VersionManagerLaunchState -Root $failedRoot -Status 'error' -LaunchTokenValue $LaunchToken -Message (T 'Helper_VersionManager_Result_OpenFailed' 'Skins could not be opened. Check the log file for details.')
        }
    }
    catch {
    }
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.InvocationInfo) {
        Write-Log ("at {0}, {1}: line {2}" -f $_.InvocationInfo.MyCommand, $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber) 'ERROR'
    }
}
finally {
    Save-Log
    Emit-ResultPairs
}
