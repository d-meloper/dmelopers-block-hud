[CmdletBinding()]
param(
    [string]$FontsPath = '',
    [switch]$IncludeFonts,
    [switch]$IncludeDrives,
    [switch]$IncludeStartupAutoRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-UniqueFontFamilies {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    Add-Type -AssemblyName System.Drawing

    $fonts = New-Object System.Drawing.Text.PrivateFontCollection
    Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $fonts.AddFontFile($_.FullName)
        } catch {
        }
    }

    $names = @()
    foreach ($family in $fonts.Families) {
        if (-not [string]::IsNullOrWhiteSpace($family.Name)) {
            $names += [string]$family.Name
        }
    }

    if ($names.Count -gt 0) {
        return @($names | Sort-Object -Unique)
    }

    return @(
        Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-DriveTargets {
    $values = @()
    foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        $root = [string]$drive.Root
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $values += $root.TrimEnd('\', '/').ToUpperInvariant()
        }
    }

    return @($values | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-StartupFolderPath {
    [Environment]::GetFolderPath('Startup')
}

function New-WscriptShell {
    New-Object -ComObject WScript.Shell
}

function Resolve-ShortcutTargetPath {
    param(
        [Parameter(Mandatory = $true)]
        $Shell,
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath
    )

    try {
        $shortcut = $Shell.CreateShortcut($ShortcutPath)
        $targetPath = [string]$shortcut.TargetPath
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            return $null
        }
        return $targetPath
    } catch {
        return $null
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
        [string]$StartupFolder,
        [Parameter(Mandatory = $true)]
        $Shell
    )

    $matches = @()
    if (-not (Test-Path -LiteralPath $StartupFolder)) {
        return $matches
    }

    Get-ChildItem -LiteralPath $StartupFolder -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $targetPath = Resolve-ShortcutTargetPath -Shell $Shell -ShortcutPath $_.FullName
        if (Test-RainmeterShortcutTarget -TargetPath $targetPath) {
            $matches += $_.FullName
        }
    }

    return $matches
}

function Get-StartupEnabledLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder,
        [Parameter(Mandatory = $true)]
        $Shell
    )

    if (@(Get-RainmeterStartupShortcuts -StartupFolder $StartupFolder -Shell $Shell).Count -gt 0) {
        return '1'
    }
    return '0'
}

if ($IncludeFonts) {
    Write-Output ('DMEL_FONTFAMILIES=' + (@(Get-UniqueFontFamilies -Path $FontsPath) -join '|'))
}

if ($IncludeDrives) {
    Write-Output ('DMEL_DRIVETARGETS=' + (@(Get-DriveTargets) -join '|'))
}

if ($IncludeStartupAutoRun) {
    $startupFolder = Get-StartupFolderPath
    $shell = New-WscriptShell
    try {
        Write-Output ('DMEL_STARTUPAUTORUN=' + (Get-StartupEnabledLiteral -StartupFolder $startupFolder -Shell $shell))
    } finally {
        if ($null -ne $shell) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}
