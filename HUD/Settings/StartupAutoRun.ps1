[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('probe', 'enable', 'disable')]
    [string]$Mode,
    [string]$StartupFolderOverride,
    [string]$RainmeterExecutablePathOverride
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $script:Utf8NoBom
$OutputEncoding = $script:Utf8NoBom

function ConvertTo-SingleLineText {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return $Value.Replace("`r", '\r').Replace("`n", '\n')
}

function Write-StartupResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [AllowEmptyString()][string]$Value,
        [AllowEmptyString()][string]$Code,
        [AllowEmptyString()][string]$Message
    )

    $lines = @(
        'DMEL_STATUS=' + $Status
        'DMEL_VALUE=' + $Value
        'DMEL_CODE=' + $Code
        'DMEL_MESSAGE=' + (ConvertTo-SingleLineText -Value $Message)
    )

    $lines | Write-Output
    if ($Status -eq 'OK' -and ($Value -eq '0' -or $Value -eq '1')) {
        Write-Output $Value
    }
}

function New-ShortcutShell {
    return (New-Object -ComObject WScript.Shell)
}

function Close-ComObject {
    param([AllowNull()][object]$Value)

    if ($null -ne $Value -and [System.Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}

function ConvertTo-ShortcutComPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$ExistingFile
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fileSystem = $null
    $entry = $null
    try {
        $fileSystem = New-Object -ComObject Scripting.FileSystemObject
        if ($ExistingFile) {
            $entry = $fileSystem.GetFile($fullPath)
            $shortPath = [string]$entry.ShortPath
            if (-not [string]::IsNullOrWhiteSpace($shortPath)) {
                return $shortPath
            }
        }

        $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
        $entry = $fileSystem.GetFolder($parentPath)
        $shortParent = [string]$entry.ShortPath
        if (-not [string]::IsNullOrWhiteSpace($shortParent)) {
            return (Join-Path $shortParent ([System.IO.Path]::GetFileName($fullPath)))
        }
        return $fullPath
    }
    finally {
        Close-ComObject -Value $entry
        Close-ComObject -Value $fileSystem
    }
}

function Get-StartupFolderPath {
    if (-not [string]::IsNullOrWhiteSpace($StartupFolderOverride)) {
        return [System.IO.Path]::GetFullPath($StartupFolderOverride)
    }
    [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
}

function Resolve-ShortcutTargetPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath
    )

    $shell = $null
    $shortcut = $null
    try {
        $shell = New-ShortcutShell
        $shortcut = $shell.CreateShortcut((ConvertTo-ShortcutComPath -Path $ShortcutPath -ExistingFile))
        $targetPath = [string]$shortcut.TargetPath
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            return $null
        }
        return $targetPath
    }
    catch {
        return $null
    }
    finally {
        Close-ComObject -Value $shortcut
        Close-ComObject -Value $shell
    }
}

function Test-RainmeterShortcutTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        return $false
    }

    $leafName = [System.IO.Path]::GetFileName($TargetPath)
    return [string]::Equals($leafName, 'Rainmeter.exe', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RainmeterStartupShortcuts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder
    )

    $matches = @()
    if ([string]::IsNullOrWhiteSpace($StartupFolder)) {
        return $matches
    }
    if (-not (Test-Path -LiteralPath $StartupFolder)) {
        return $matches
    }

    Get-ChildItem -LiteralPath $StartupFolder -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $targetPath = Resolve-ShortcutTargetPath -ShortcutPath $_.FullName
        if (-not [string]::IsNullOrWhiteSpace($targetPath) -and (Test-RainmeterShortcutTarget -TargetPath $targetPath)) {
            $matches += $_.FullName
        }
    }

    return $matches
}

function Get-RainmeterExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder
    )

    if (-not [string]::IsNullOrWhiteSpace($RainmeterExecutablePathOverride)) {
        $overridePath = [System.IO.Path]::GetFullPath($RainmeterExecutablePathOverride)
        if ((Test-RainmeterShortcutTarget -TargetPath $overridePath) -and (Test-Path -LiteralPath $overridePath)) {
            return $overridePath
        }
        return $null
    }

    foreach ($process in @(Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue)) {
        $runningPath = $null
        try {
            $runningPath = [string]$process.Path
        } catch {
            # Some process owners do not expose the executable path.
        }
        if ($runningPath -and (Test-Path -LiteralPath $runningPath)) {
            return [System.IO.Path]::GetFullPath($runningPath)
        }
    }

    $candidatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidatePaths += Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidatePaths += Join-Path ${env:ProgramFiles(x86)} 'Rainmeter\Rainmeter.exe'
    }

    foreach ($candidate in $candidatePaths) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    foreach ($registryPath in @(
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths\Rainmeter.exe',
        'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths\Rainmeter.exe'
    )) {
        try {
            $candidate = [string](Get-ItemPropertyValue -LiteralPath $registryPath -Name '(default)' -ErrorAction Stop)
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        } catch {
            # App Paths registration is optional.
        }
    }

    $canonicalShortcut = Join-Path $StartupFolder 'Rainmeter.lnk'
    if (Test-Path -LiteralPath $canonicalShortcut) {
        $targetPath = Resolve-ShortcutTargetPath -ShortcutPath $canonicalShortcut
        if ((Test-RainmeterShortcutTarget -TargetPath $targetPath) -and (Test-Path -LiteralPath $targetPath)) {
            return [System.IO.Path]::GetFullPath($targetPath)
        }
    }

    return $null
}

function Get-StartupEnabledLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder
    )

    if (@(Get-RainmeterStartupShortcuts -StartupFolder $StartupFolder).Count -gt 0) {
        return '1'
    }
    return '0'
}

function Remove-RainmeterStartupShortcuts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder
    )

    Get-RainmeterStartupShortcuts -StartupFolder $StartupFolder | ForEach-Object {
        Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-CanonicalRainmeterShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder
    )

    $rainmeterExePath = Get-RainmeterExecutablePath -StartupFolder $StartupFolder
    if ([string]::IsNullOrWhiteSpace($rainmeterExePath) -or -not (Test-Path -LiteralPath $rainmeterExePath)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $StartupFolder)) {
        New-Item -ItemType Directory -Path $StartupFolder -Force | Out-Null
    }

    $shortcutPath = Join-Path $StartupFolder 'Rainmeter.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    $shell = $null
    $shortcut = $null
    try {
        $shortcutTargetPath = ConvertTo-ShortcutComPath -Path $rainmeterExePath -ExistingFile
        $shell = New-ShortcutShell
        $shortcut = $shell.CreateShortcut((ConvertTo-ShortcutComPath -Path $shortcutPath))
        $shortcut.TargetPath = $shortcutTargetPath
        $shortcut.WorkingDirectory = Split-Path -Parent $shortcutTargetPath
        $shortcut.IconLocation = $shortcutTargetPath + ',0'
        $shortcut.Save()
    }
    finally {
        Close-ComObject -Value $shortcut
        Close-ComObject -Value $shell
    }
    return $true
}

$startupFolder = $null
$status = 'ERROR'
$value = ''
$code = 'UNEXPECTED'
$message = ''
try {
    $startupFolder = Get-StartupFolderPath
    if ([string]::IsNullOrWhiteSpace($startupFolder)) {
        throw [System.InvalidOperationException]::new('The Windows startup folder path is empty.')
    }
    switch ($Mode) {
        'probe' {
            # The final probe below owns the result.
        }
        'enable' {
            $created = Ensure-CanonicalRainmeterShortcut -StartupFolder $startupFolder
            if (-not $created) {
                throw [System.InvalidOperationException]::new('A valid Rainmeter executable could not be resolved.')
            }
        }
        'disable' {
            Remove-RainmeterStartupShortcuts -StartupFolder $startupFolder
        }
    }

    $value = Get-StartupEnabledLiteral -StartupFolder $startupFolder

    if (($Mode -eq 'enable' -and $value -ne '1') -or ($Mode -eq 'disable' -and $value -ne '0')) {
        throw [System.InvalidOperationException]::new("The startup state did not match the requested mode '$Mode'.")
    }

    $status = 'OK'
    $code = ''
} catch {
    $code = $_.Exception.GetType().Name
    $message = [string]$_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($startupFolder)) {
        try {
            $value = Get-StartupEnabledLiteral -StartupFolder $startupFolder
        } catch {
            # Leave the value empty when the resulting state cannot be probed.
        }
    }
}

Write-StartupResult -Status $status -Value $value -Code $code -Message $message
if ($status -ne 'OK') {
    exit 1
}
