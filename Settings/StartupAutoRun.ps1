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

function Initialize-NativeShortcutApi {
    if ('DMeloper.StartupShortcutApi' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace DMeloper
{
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink
    {
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int maxPath, IntPtr findData, uint flags);
        void GetIDList(out IntPtr idList);
        void SetIDList(IntPtr idList);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int maxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder directory, int maxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments, int maxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int showCommand);
        void SetShowCmd(int showCommand);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder iconPath, int iconPathLength, out int iconIndex);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string iconPath, int iconIndex);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr windowHandle, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }

    public static class StartupShortcutApi
    {
        public static void Create(string shortcutPath, string targetPath, string workingDirectory, string iconPath)
        {
            object instance = new ShellLink();
            try
            {
                IShellLinkW link = (IShellLinkW)instance;
                link.SetPath(targetPath);
                link.SetWorkingDirectory(workingDirectory);
                link.SetIconLocation(iconPath, 0);
                ((IPersistFile)instance).Save(shortcutPath, true);
            }
            finally
            {
                Marshal.FinalReleaseComObject(instance);
            }
        }

        public static string ReadTarget(string shortcutPath)
        {
            object instance = new ShellLink();
            try
            {
                ((IPersistFile)instance).Load(shortcutPath, 0);
                StringBuilder target = new StringBuilder(32768);
                ((IShellLinkW)instance).GetPath(target, target.Capacity, IntPtr.Zero, 0);
                return target.ToString();
            }
            finally
            {
                Marshal.FinalReleaseComObject(instance);
            }
        }
    }
}
'@ | Out-Null
}

function Get-StartupFolderPath {
    if (-not [string]::IsNullOrWhiteSpace($StartupFolderOverride)) {
        return [System.IO.Path]::GetFullPath($StartupFolderOverride)
    }
    [Environment]::GetFolderPath('Startup')
}

function Resolve-ShortcutTargetPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath
    )

    try {
        Initialize-NativeShortcutApi
        $targetPath = [DMeloper.StartupShortcutApi]::ReadTarget($ShortcutPath)
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
        [string]$StartupFolder
    )

    $matches = @()
    if (-not (Test-Path -LiteralPath $StartupFolder)) {
        return $matches
    }

    Get-ChildItem -LiteralPath $StartupFolder -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $targetPath = Resolve-ShortcutTargetPath -ShortcutPath $_.FullName
        if (Test-RainmeterShortcutTarget -TargetPath $targetPath) {
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

    Initialize-NativeShortcutApi
    [DMeloper.StartupShortcutApi]::Create(
        $shortcutPath,
        $rainmeterExePath,
        (Split-Path -Parent $rainmeterExePath),
        $rainmeterExePath
    )
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
