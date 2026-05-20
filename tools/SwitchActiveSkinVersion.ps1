[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [Parameter(Mandatory = $true)][string]$SelectedTargetRoot,
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
}
$script:ResolvedCurrentRoot = ''
$script:ResolvedSelectedRoot = ''
$script:SelectedPersistentActivationStarted = $false

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
    $parent = Split-Path -Parent $script:LogPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [void](Write-BlockHudCanonicalLogBlock -Path $script:LogPath -Type 'SwitchActiveSkinVersion' -Lines $script:LogMessages -Encoding $script:Utf8NoBom)
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
            $shortcutPath = Join-Path $startupFolder 'Rainmeter.lnk'
            if (Test-Path -LiteralPath $shortcutPath) {
                $targetPath = Resolve-ShortcutTargetPath -Shell $shell -ShortcutPath $shortcutPath
                if (-not [string]::IsNullOrWhiteSpace($targetPath) -and (Test-Path -LiteralPath $targetPath)) {
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

    throw 'Rainmeter.exe could not be located.'
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

function Get-RootConfigName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $leaf = Split-Path -Path $Root -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Could not derive a root config name from [$Root]."
    }

    return $leaf
}

function Get-ConfigName {
    param(
        [Parameter(Mandatory = $true)][string]$RootConfigName,
        [AllowNull()][string]$RelativeConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($RelativeConfigPath)) {
        return $RootConfigName
    }

    return ($RootConfigName + '\' + $RelativeConfigPath.Trim('\'))
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

function Ensure-RainmeterIniNativeMethods {
    if ('BlockHudRainmeterIniNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class BlockHudRainmeterIniNative
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetPrivateProfileString(string section, string key, string defaultValue, StringBuilder returnValue, uint size, string filePath);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool WritePrivateProfileString(string section, string key, string value, string filePath);
}
'@
}

function Get-RainmeterIniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )

    Ensure-RainmeterIniNativeMethods
    $buffer = New-Object System.Text.StringBuilder 256
    [void][BlockHudRainmeterIniNative]::GetPrivateProfileString($Section, $Key, '', $buffer, [uint32]$buffer.Capacity, $Path)
    return $buffer.ToString()
}

function Set-RainmeterIniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Ensure-RainmeterIniNativeMethods
    if (-not [BlockHudRainmeterIniNative]::WritePrivateProfileString($Section, $Key, $Value, $Path)) {
        throw "Failed to write Rainmeter.ini value: [$Section] $Key"
    }
}

function Ensure-HotbarLoadOrder {
    param([Parameter(Mandatory = $true)][string]$Root)

    $configPath = Get-RainmeterConfigPath
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        Write-Log 'Rainmeter.ini was not found; Hotbar LoadOrder pre-sync was skipped.' 'WARN'
        return
    }

    $section = (Get-RootConfigName -Root $Root) + '\Hotbar'
    $current = Get-RainmeterIniValue -Path $configPath -Section $section -Key 'LoadOrder'
    if ([string]::Equals($current, '100', [System.StringComparison]::Ordinal)) {
        Write-Log ("Hotbar LoadOrder already 100 for [{0}]." -f $section)
        return
    }

    Set-RainmeterIniValue -Path $configPath -Section $section -Key 'LoadOrder' -Value '100'
    Write-Log ("Set Hotbar LoadOrder=100 for [{0}] before persistent activation." -f $section)
}

function Test-ConfigFileExists {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowNull()][string]$RelativeConfigPath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $folderPath = if ([string]::IsNullOrWhiteSpace($RelativeConfigPath)) {
        $Root
    }
    else {
        Join-RootPath -Root $Root -RelativePath $RelativeConfigPath
    }

    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        return $false
    }

    return (Test-Path -LiteralPath (Join-Path $folderPath $FileName) -PathType Leaf)
}

function Get-CurrentRootDeactivateSpecs {
    @(
        [PSCustomObject]@{ RelativePath = 'Hotbar'; FileName = 'Hotbar.ini' }
        [PSCustomObject]@{ RelativePath = 'Clock'; FileName = 'Clock.ini' }
        [PSCustomObject]@{ RelativePath = 'ClockSprite'; FileName = 'ClockSprite.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Heart'; FileName = 'Heart.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Armor'; FileName = 'Armor.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Food'; FileName = 'Food.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Air'; FileName = 'Air.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Exp'; FileName = 'Exp.ini' }
        [PSCustomObject]@{ RelativePath = 'Settings'; FileName = 'Settings.ini' }
        [PSCustomObject]@{ RelativePath = 'Editor'; FileName = 'Editor.ini' }
        [PSCustomObject]@{ RelativePath = 'Inventory'; FileName = 'Inventory.ini' }
        [PSCustomObject]@{ RelativePath = 'InventoryBG'; FileName = 'InventoryBG.ini' }
    )
}

function Get-PersistentConfigSpecs {
    @(
        [PSCustomObject]@{ RelativePath = 'Hotbar'; FileName = 'Hotbar.ini' }
        [PSCustomObject]@{ RelativePath = 'Clock'; FileName = 'Clock.ini' }
        [PSCustomObject]@{ RelativePath = 'ClockSprite'; FileName = 'ClockSprite.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Heart'; FileName = 'Heart.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Armor'; FileName = 'Armor.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Food'; FileName = 'Food.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Air'; FileName = 'Air.ini' }
        [PSCustomObject]@{ RelativePath = 'Indicators\Exp'; FileName = 'Exp.ini' }
    )
}

function Assert-SiblingInstalledRoots {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SelectedRoot
    )

    $currentParent = Split-Path -Parent $CurrentRoot
    $selectedParent = Split-Path -Parent $SelectedRoot
    if ([string]::IsNullOrWhiteSpace($currentParent) -or [string]::IsNullOrWhiteSpace($selectedParent)) {
        throw 'CurrentTargetRoot and SelectedTargetRoot must both be direct skin roots.'
    }

    $resolvedCurrentParent = Resolve-FullPath -Path $currentParent
    $resolvedSelectedParent = Resolve-FullPath -Path $selectedParent
    if (-not [string]::Equals($resolvedCurrentParent, $resolvedSelectedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'CurrentTargetRoot and SelectedTargetRoot must be sibling skin roots under the same parent directory.'
    }
}

function Invoke-DeactivateConfigList {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Specs
    )

    $rootConfigName = Get-RootConfigName -Root $Root
    foreach ($spec in $Specs) {
        $configName = Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath)
        Write-Log ("Deactivating [{0}]" -f $configName)
        Invoke-RainmeterBang -Bang '!DeactivateConfig' -Arguments @($configName)
    }
}

function Invoke-ActivatePersistentConfigList {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Specs
    )

    $rootConfigName = Get-RootConfigName -Root $Root
    foreach ($spec in $Specs) {
        if (-not (Test-ConfigFileExists -Root $Root -RelativeConfigPath ([string]$spec.RelativePath) -FileName ([string]$spec.FileName))) {
            Write-Log ("Skipping missing persistent config [{0}]" -f (Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath))) 'WARN'
            continue
        }

        $script:SelectedPersistentActivationStarted = $true
        $configName = Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath)
        Write-Log ("Activating [{0}] ({1})" -f $configName, [string]$spec.FileName)
        Invoke-RainmeterBang -Bang '!ActivateConfig' -Arguments @($configName, [string]$spec.FileName)
    }
}

function Assert-PersistentActivationCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Specs
    )

    $candidateCount = 0
    foreach ($spec in $Specs) {
        if (Test-ConfigFileExists -Root $Root -RelativeConfigPath ([string]$spec.RelativePath) -FileName ([string]$spec.FileName)) {
            $candidateCount++
        }
    }

    if ($candidateCount -le 0) {
        throw ("SelectedTargetRoot has no persistent activation candidates: {0}" -f $Root)
    }

    Write-Log ("Selected persistent activation candidates: {0}" -f $candidateCount)
}

function Invoke-BestEffortRollback {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SelectedRoot,
        [Parameter(Mandatory = $true)][object[]]$PersistentSpecs
    )

    Write-Log 'Starting best-effort rollback for persistent skins only.' 'WARN'
    $selectedRootConfig = Get-RootConfigName -Root $SelectedRoot
    foreach ($spec in $PersistentSpecs) {
        $configName = Get-ConfigName -RootConfigName $selectedRootConfig -RelativeConfigPath ([string]$spec.RelativePath)
        try {
            Write-Log ("Rollback deactivating [{0}]" -f $configName) 'WARN'
            Invoke-RainmeterBang -Bang '!DeactivateConfig' -Arguments @($configName)
        }
        catch {
            Write-Log ("Rollback deactivate failed for [{0}]: {1}" -f $configName, $_.Exception.Message) 'WARN'
        }
    }

    $currentRootConfig = Get-RootConfigName -Root $CurrentRoot
    foreach ($spec in $PersistentSpecs) {
        if (-not (Test-ConfigFileExists -Root $CurrentRoot -RelativeConfigPath ([string]$spec.RelativePath) -FileName ([string]$spec.FileName))) {
            continue
        }

        $configName = Get-ConfigName -RootConfigName $currentRootConfig -RelativeConfigPath ([string]$spec.RelativePath)
        try {
            Write-Log ("Rollback reactivating [{0}] ({1})" -f $configName, [string]$spec.FileName) 'WARN'
            Invoke-RainmeterBang -Bang '!ActivateConfig' -Arguments @($configName, [string]$spec.FileName)
        }
        catch {
            Write-Log ("Rollback reactivate failed for [{0}]: {1}" -f $configName, $_.Exception.Message) 'WARN'
        }
    }
}

function Invoke-VersionSwitch {
    $resolvedCurrentRoot = Resolve-SkinRootCandidate -Candidate $CurrentTargetRoot
    if (-not $resolvedCurrentRoot) {
        throw 'CurrentTargetRoot is not a valid Block HUD install root.'
    }
    $script:ResolvedCurrentRoot = $resolvedCurrentRoot

    $resolvedSelectedRoot = Resolve-SkinRootCandidate -Candidate $SelectedTargetRoot
    if (-not $resolvedSelectedRoot) {
        throw 'SelectedTargetRoot is not a valid Block HUD install root.'
    }
    $script:ResolvedSelectedRoot = $resolvedSelectedRoot

    if ([string]::Equals($resolvedCurrentRoot, $resolvedSelectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'NOOP'
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedSelectedRoot
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'The selected installation is already active.'
        return
    }

    Assert-SiblingInstalledRoots -CurrentRoot $resolvedCurrentRoot -SelectedRoot $resolvedSelectedRoot
    Write-Log ("Current root: {0}" -f $resolvedCurrentRoot)
    Write-Log ("Selected root: {0}" -f $resolvedSelectedRoot)
    Write-Log ("Current root config: {0}" -f (Get-RootConfigName -Root $resolvedCurrentRoot))
    Write-Log ("Selected root config: {0}" -f (Get-RootConfigName -Root $resolvedSelectedRoot))
    Write-Log 'Switch policy: fixed config bang sequence with no observed-state waits; z-pos is runtime-owned.'

    $currentDeactivateSpecs = @(Get-CurrentRootDeactivateSpecs)
    $persistentSpecs = @(Get-PersistentConfigSpecs)
    Assert-PersistentActivationCandidates -Root $resolvedSelectedRoot -Specs $persistentSpecs

    try {
        Invoke-DeactivateConfigList -Root $resolvedCurrentRoot -Specs $currentDeactivateSpecs
        Ensure-HotbarLoadOrder -Root $resolvedSelectedRoot
        Invoke-ActivatePersistentConfigList -Root $resolvedSelectedRoot -Specs $persistentSpecs

        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedSelectedRoot
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Switched the active Block HUD installation.'
    }
    catch {
        Write-Log ("Switch failed: {0}" -f $_.Exception.Message) 'ERROR'
        if ($script:SelectedPersistentActivationStarted) {
            Invoke-BestEffortRollback -CurrentRoot $resolvedCurrentRoot -SelectedRoot $resolvedSelectedRoot -PersistentSpecs $persistentSpecs
        }
        throw
    }
}

try {
    $resolvedLogRoot = Resolve-SkinRootCandidate -Candidate $CurrentTargetRoot
    if ($resolvedLogRoot) {
        $script:LogPath = Get-BlockHudCanonicalLogPath -Root $resolvedLogRoot -ScriptRoot $PSScriptRoot
    }
    else {
        $script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
    }
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath

    Invoke-VersionSwitch
}
catch {
    if (-not [string]::Equals([string]$script:ResultPairs['DMEL_STATUS'], 'NOOP', [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    }
    if ([string]::IsNullOrWhiteSpace([string]$script:ResultPairs['DMEL_SOURCEPATH']) -and -not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot)) {
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $script:ResolvedCurrentRoot
    }
    Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    if ([string]::IsNullOrWhiteSpace([string]$script:ResultPairs['DMEL_MESSAGE'])) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
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
