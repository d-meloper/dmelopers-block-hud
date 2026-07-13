[CmdletBinding()]
param(
    [string]$TargetRoot,
    [switch]$EmitResultPairs,
    [switch]$WindowSession,
    [string]$LaunchToken,
    [string]$InitialAction = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:VersionManagerWindowClosing = $false

$script:VersionManagerEntrypointPath = [System.IO.Path]::GetFullPath($PSCommandPath)
$script:VersionManagerToolsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
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
. (Join-Path $PSScriptRoot 'VersionManager.ReleaseCatalog.ps1')

$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot

$script:SkinRootForLocalization = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$script:LanguageCode = Read-LanguageCode -SkinRoot $script:SkinRootForLocalization
$script:LocTable = Read-LocaleTable -SkinRoot $script:SkinRootForLocalization -LanguageCode $script:LanguageCode

$script:ModuleRoot = Join-Path $PSScriptRoot 'OpenVersionManager'
. (Join-Path $script:ModuleRoot 'CoreProcessAndPaths.ps1')
. (Join-Path $script:ModuleRoot 'ConfigurationAndInstallations.ps1')
. (Join-Path $script:ModuleRoot 'DialogsActionsAndHelpers.ps1')
. (Join-Path $script:ModuleRoot 'MainForm.ps1')



























































































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
    $failedRoot = ''
    try {
        $failedRoot = Get-TargetRoot
        if (-not [string]::IsNullOrWhiteSpace($failedRoot) -and (Test-Path -LiteralPath $failedRoot -PathType Container)) {
            Save-VersionManagerLaunchState -Root $failedRoot -Status 'error' -LaunchTokenValue $LaunchToken -Message (T 'Helper_VersionManager_Result_OpenFailed' 'Skins could not be opened. Check the log file for details.')
        }
    }
    catch {
    }
    Write-VersionManagerLaunchDiagnostic -Root $failedRoot -Stage 'top-level-error' -LaunchTokenValue $LaunchToken -Message $_.Exception.Message -Details @(
        $_.Exception.ToString()
    )
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.InvocationInfo) {
        Write-Log ("at {0}, {1}: line {2}" -f $_.InvocationInfo.MyCommand, $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber) 'ERROR'
    }
}
finally {
    Save-Log
    Emit-ResultPairs
}
