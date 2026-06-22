[CmdletBinding()]
param(
    [string]$FontsPath = '',
    [switch]$IncludeFonts,
    [switch]$IncludeDrives,
    [switch]$IncludeStartupAutoRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:HadWarning = $false
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

function Write-ResultPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Value
    )

    $text = ([string]$Value) -replace '[\r\n\t]+', ' '
    [Console]::WriteLine(('{0}={1}' -f $Key, $text))
}

function Write-SectionFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][System.Exception]$Exception
    )

    $script:HadWarning = $true
    Write-ResultPair -Key ("DMEL_{0}_STATUS" -f $Section) -Value 'ERROR'
    Write-ResultPair -Key ("DMEL_{0}_MESSAGE" -f $Section) -Value $Exception.Message
}

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
    return @(
        [Environment]::GetLogicalDrives() |
            ForEach-Object { ([string]$_).TrimEnd('\', '/').ToUpperInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
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
    try {
        Write-ResultPair -Key 'DMEL_FONTFAMILIES' -Value (@(Get-UniqueFontFamilies -Path $FontsPath) -join '|')
        Write-ResultPair -Key 'DMEL_FONTS_STATUS' -Value 'OK'
    }
    catch {
        Write-ResultPair -Key 'DMEL_FONTFAMILIES' -Value ''
        Write-SectionFailure -Section 'FONTS' -Exception $_.Exception
    }
}

if ($IncludeDrives) {
    try {
        Write-ResultPair -Key 'DMEL_DRIVETARGETS' -Value (@(Get-DriveTargets) -join '|')
        Write-ResultPair -Key 'DMEL_DRIVES_STATUS' -Value 'OK'
    }
    catch {
        Write-ResultPair -Key 'DMEL_DRIVETARGETS' -Value ''
        Write-SectionFailure -Section 'DRIVES' -Exception $_.Exception
    }
}

if ($IncludeStartupAutoRun) {
    $shell = $null
    try {
        $startupFolder = Get-StartupFolderPath
        $shell = New-WscriptShell
        Write-ResultPair -Key 'DMEL_STARTUPAUTORUN' -Value (Get-StartupEnabledLiteral -StartupFolder $startupFolder -Shell $shell)
        Write-ResultPair -Key 'DMEL_STARTUPAUTORUN_STATUS' -Value 'OK'
    }
    catch {
        Write-SectionFailure -Section 'STARTUPAUTORUN' -Exception $_.Exception
    }
    finally {
        if ($null -ne $shell) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

Write-ResultPair -Key 'DMEL_STATUS' -Value $(if ($script:HadWarning) { 'WARN' } else { 'OK' })
