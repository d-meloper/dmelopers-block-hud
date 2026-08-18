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
    $OutputEncoding = $script:Utf8NoBom
}
catch {
}

$entrypointDirectory = $PSScriptRoot
$commonHelperPath = Join-Path $entrypointDirectory 'Runtime\Helpers\StartupAutoRun.Common.ps1'
. $commonHelperPath

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
    try {
        $startupFolder = Get-BlockHudStartupFolderPath
        $taskName = Resolve-BlockHudScheduledTaskName
        $startupState = Get-BlockHudStartupRegistrationState -StartupFolder $startupFolder -TaskName $taskName
        Write-ResultPair -Key 'DMEL_STARTUPAUTORUN' -Value $startupState.Value
        Write-ResultPair -Key 'DMEL_STARTUPFASTAUTORUN' -Value $startupState.FastValue
        Write-ResultPair -Key 'DMEL_STARTUPAUTORUN_STATUS' -Value 'OK'
    }
    catch {
        Write-ResultPair -Key 'DMEL_STARTUPAUTORUN' -Value ''
        Write-ResultPair -Key 'DMEL_STARTUPFASTAUTORUN' -Value ''
        Write-SectionFailure -Section 'STARTUPAUTORUN' -Exception $_.Exception
    }
}

Write-ResultPair -Key 'DMEL_STATUS' -Value $(if ($script:HadWarning) { 'WARN' } else { 'OK' })
