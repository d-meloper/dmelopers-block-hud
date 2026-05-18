[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('probe', 'enable', 'disable')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

function Get-RainmeterExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder,
        [Parameter(Mandatory = $true)]
        $Shell
    )

    $runningPath = Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
        Select-Object -First 1 -ExpandProperty Path
    if ($runningPath -and (Test-Path -LiteralPath $runningPath)) {
        return [System.IO.Path]::GetFullPath($runningPath)
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

    $canonicalShortcut = Join-Path $StartupFolder 'Rainmeter.lnk'
    if (Test-Path -LiteralPath $canonicalShortcut) {
        $targetPath = Resolve-ShortcutTargetPath -Shell $Shell -ShortcutPath $canonicalShortcut
        if ((Test-RainmeterShortcutTarget -TargetPath $targetPath) -and (Test-Path -LiteralPath $targetPath)) {
            return [System.IO.Path]::GetFullPath($targetPath)
        }
    }

    return $null
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

function Remove-RainmeterStartupShortcuts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder,
        [Parameter(Mandatory = $true)]
        $Shell
    )

    Get-RainmeterStartupShortcuts -StartupFolder $StartupFolder -Shell $Shell | ForEach-Object {
        Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-CanonicalRainmeterShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartupFolder,
        [Parameter(Mandatory = $true)]
        $Shell
    )

    $rainmeterExePath = Get-RainmeterExecutablePath -StartupFolder $StartupFolder -Shell $Shell
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

    $shortcut = $Shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $rainmeterExePath
    $shortcut.WorkingDirectory = Split-Path -Parent $rainmeterExePath
    $shortcut.IconLocation = $rainmeterExePath
    $shortcut.Save()
    return $true
}

$startupFolder = Get-StartupFolderPath
$shell = New-WscriptShell

try {
    switch ($Mode) {
        'probe' {
            Write-Output (Get-StartupEnabledLiteral -StartupFolder $startupFolder -Shell $shell)
        }
        'enable' {
            [void](Ensure-CanonicalRainmeterShortcut -StartupFolder $startupFolder -Shell $shell)
            Write-Output (Get-StartupEnabledLiteral -StartupFolder $startupFolder -Shell $shell)
        }
        'disable' {
            Remove-RainmeterStartupShortcuts -StartupFolder $startupFolder -Shell $shell
            Write-Output (Get-StartupEnabledLiteral -StartupFolder $startupFolder -Shell $shell)
        }
    }
} finally {
    if ($null -ne $shell) {
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}
