# OpenVersionManager helpers - Core process paths logging and Rainmeter

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-VersionManagerToolsRoot {
    $toolsRootVariable = Get-Variable -Scope Script -Name 'VersionManagerToolsRoot' -ErrorAction SilentlyContinue
    if ($null -ne $toolsRootVariable -and -not [string]::IsNullOrWhiteSpace([string]$toolsRootVariable.Value)) {
        return [System.IO.Path]::GetFullPath([string]$toolsRootVariable.Value)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-VersionManagerEntrypointPath {
    $entrypointVariable = Get-Variable -Scope Script -Name 'VersionManagerEntrypointPath' -ErrorAction SilentlyContinue
    if ($null -ne $entrypointVariable -and -not [string]::IsNullOrWhiteSpace([string]$entrypointVariable.Value)) {
        return [System.IO.Path]::GetFullPath([string]$entrypointVariable.Value)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-VersionManagerToolsRoot) 'OpenVersionManager.ps1'))
}

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

function Write-VersionManagerLaunchDiagnostic {
    param(
        [AllowNull()][string]$Root,
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][string]$LaunchTokenValue = '',
        [AllowNull()][string]$Message = '',
        [AllowNull()][object[]]$Details
    )

    try {
        $logPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot (Get-VersionManagerToolsRoot)
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add(('timeUtc={0}' -f ((Get-Date).ToUniversalTime().ToString('o'))))
        $lines.Add(('stage={0}' -f [string]$Stage))
        $lines.Add(('pid={0}' -f [string]$PID))
        if (-not [string]::IsNullOrWhiteSpace($Root)) {
            $lines.Add(('root={0}' -f [string]$Root))
        }
        if (-not [string]::IsNullOrWhiteSpace($LaunchTokenValue)) {
            $lines.Add(('launchToken={0}' -f [string]$LaunchTokenValue))
        }
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $lines.Add(('message={0}' -f [string]$Message))
        }
        foreach ($detail in @($Details)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$detail)) {
                $lines.Add([string]$detail)
            }
        }
        [void](Write-BlockHudCanonicalLogBlock -Path $logPath -Type 'VersionManagerLaunchDebug' -Lines $lines -Encoding $script:Utf8NoBom)

        $summaryParts = New-Object System.Collections.Generic.List[string]
        $summaryParts.Add(('stage={0}' -f [string]$Stage))
        if (-not [string]::IsNullOrWhiteSpace($LaunchTokenValue)) {
            $summaryParts.Add(('launchToken={0}' -f [string]$LaunchTokenValue))
        }
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $summaryParts.Add(('message={0}' -f [string]$Message))
        }
        foreach ($detail in @($Details)) {
            $detailText = [string]$detail
            if (-not [string]::IsNullOrWhiteSpace($detailText)) {
                $summaryParts.Add($detailText)
            }
            if ($summaryParts.Count -ge 6) {
                break
            }
        }
        $summary = [string]::Join('; ', [string[]]$summaryParts.ToArray())
        Write-Host ('[VersionManagerLaunchDebug] ' + $summary)
        $rainmeterLevel = if ([string]$Stage -match '(?i)error|failed') { 'Error' } elseif ([string]$Stage -match '(?i)warn|timeout') { 'Warning' } else { 'Notice' }
        Write-RainmeterRuntimeLog -Message ('VersionManagerLaunchDebug ' + $summary) -Level $rainmeterLevel
    }
    catch {
    }
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
    Write-VersionManagerLaunchDiagnostic -Root $Root -Stage ('state:' + [string]$Status) -LaunchTokenValue $LaunchTokenValue -Message $Message -Details @(
        ('statePath={0}' -f (Get-VersionManagerLaunchStatePath -Root $Root))
    )
}

function Wait-VersionManagerLaunchShown {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ExpectedLaunchToken = '',
        [int]$TimeoutMilliseconds = 5000,
        [int]$PollMilliseconds = 100,
        [AllowNull()][System.Diagnostics.Process]$Process
    )

    $statePath = Get-VersionManagerLaunchStatePath -Root $Root
    $deadline = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(1, $TimeoutMilliseconds))
    $lastStatus = ''
    $lastMessage = ''
    $lastToken = ''
    $observedProcessExit = $false
    $observedExitCode = ''
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

        if ($null -ne $Process) {
            try {
                $Process.Refresh()
                if ($Process.HasExited) {
                    $observedProcessExit = $true
                    $observedExitCode = [string]$Process.ExitCode
                    if (-not [string]::Equals($lastStatus, 'shown', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $message = ("Skins window session exited before reporting shown. processId={0}; exitCode={1}; observedToken={2}; observedStatus={3}" -f $Process.Id, $observedExitCode, $lastToken, $lastStatus)
                        return [PSCustomObject]@{
                            Status = 'ERROR'
                            Message = $message
                            ObservedStatus = $lastStatus
                            ObservedToken = $lastToken
                        }
                    }
                }
            }
            catch {
                $lastMessage = $_.Exception.Message
            }
        }

        if ([DateTime]::UtcNow -ge $deadline) {
            break
        }
        Start-Sleep -Milliseconds ([Math]::Max(10, $PollMilliseconds))
    } while ($true)

    return [PSCustomObject]@{
        Status = 'WARN'
        Message = ("Skins launch was started, but the window did not report shown before the confirmation timeout. expectedToken={0}; observedToken={1}; observedStatus={2}; processExited={3}; exitCode={4}" -f [string]$ExpectedLaunchToken, $lastToken, $lastStatus, $observedProcessExit, $observedExitCode)
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

function Write-RainmeterRuntimeLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Notice', 'Warning', 'Error')][string]$Level = 'Notice'
    )

    try {
        $text = '[DMeloper Block HUD] ' + ([string]$Message)
        Invoke-RainmeterBang -Bang '!Log' -Arguments @($text, $Level)
    }
    catch {
    }
}

function Get-TargetRoot {
    if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        return (Resolve-FullPath -Path (Join-Path (Get-VersionManagerToolsRoot) '..'))
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

    $managerLocalHelper = Join-Path (Get-VersionManagerToolsRoot) 'GetVersionReleaseCatalog.ps1'
    if (Test-Path -LiteralPath $managerLocalHelper -PathType Leaf) {
        return $managerLocalHelper
    }

    Join-RootPath -Root $Root -RelativePath 'tools\GetVersionReleaseCatalog.ps1'
}

function Get-VersionReleaseInstallHelperPath {
    param([Parameter(Mandatory = $true)][string]$Root)

    $managerLocalHelper = Join-Path (Get-VersionManagerToolsRoot) 'InstallVersionRelease.ps1'
    if (Test-Path -LiteralPath $managerLocalHelper -PathType Leaf) {
        return $managerLocalHelper
    }

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

    return (Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot (Get-VersionManagerToolsRoot))
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

    $canonicalLogPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot (Get-VersionManagerToolsRoot)
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

    $result = [PSCustomObject]@{
        HasContent = $hasContent
        Text = if ($blocks.Count -gt 0) { [string]::Join("`r`n`r`n", $blocks) } else { [string](T 'Helper_VersionManager_Log_Empty' 'The skin log file is empty.') }
    }
    return $result
}

function Clear-VersionManagerLogs {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$CurrentLogPath
    )

    $canonicalLogPath = Get-BlockHudCanonicalLogPath -Root $Root -ScriptRoot (Get-VersionManagerToolsRoot)
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
