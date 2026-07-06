[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TargetRoot,
    [string]$SourceRoot,
    [switch]$NonInteractive,
    [switch]$ResetPositions,
    [switch]$ConfirmDetectedSource,
    [switch]$ValidateOnly,
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Cmdlet = $PSCmdlet
$script:Utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}
$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = ''
$script:ResolvedTargetRoot = ''
$script:ResolvedSourceRoot = ''
$script:TouchedRainmeterFiles = New-Object System.Collections.Generic.List[string]
$script:SkippedSourceFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$script:SkippedSourceDirectories = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$script:ImportTargetMutationStarted = $false
$script:EphemeralRollbackRoot = ''
$script:AutoRollbackAttempted = $false
$script:AutoRollbackSucceeded = $false
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'LowSpecSettings.Policy.ps1')
$script:ImportFromOldVersionEntrypointRoot = $PSScriptRoot
$script:ImportFromOldVersionDefaultTargetRoot = [System.IO.Path]::GetFullPath((Join-Path $script:ImportFromOldVersionEntrypointRoot '..'))
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:SkinRootForLocalization = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$script:LanguageCode = Read-LanguageCode -SkinRoot $script:SkinRootForLocalization
$script:LocTable = Read-LocaleTable -SkinRoot $script:SkinRootForLocalization -LanguageCode $script:LanguageCode

$script:ModuleRoot = Join-Path $PSScriptRoot 'ImportFromOldVersion'
. (Join-Path $script:ModuleRoot 'CoreDiscovery.ps1')
. (Join-Path $script:ModuleRoot 'VariablesAndCompatibility.ps1')
. (Join-Path $script:ModuleRoot 'AssetsAndRollback.ps1')
. (Join-Path $script:ModuleRoot 'SettingsLayoutAndImages.ps1')
. (Join-Path $script:ModuleRoot 'PlayerEditorAndRun.ps1')



















































































































































try {
    Invoke-Migration
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    if ($ValidateOnly) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Legacy import validation passed.'
    }
    else {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Legacy import completed.'
    }
    Save-Log
    Emit-ResultPairs
    exit 0
}
catch [System.OperationCanceledException] {
    Write-Log $_.Exception.Message 'WARN'
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'CANCEL'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    Save-Log
    Emit-ResultPairs
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    if ($script:ImportTargetMutationStarted -and -not $script:AutoRollbackAttempted -and -not [string]::IsNullOrWhiteSpace($script:EphemeralRollbackRoot)) {
        $script:AutoRollbackAttempted = $true
        try {
            Restore-TargetStateFromTemporaryRollback -TargetRoot $script:ResolvedTargetRoot -RollbackRoot $script:EphemeralRollbackRoot
            $script:AutoRollbackSucceeded = $true
            Add-ResultPairMessage -Message 'Automatic rollback restored the pre-import target state from a temporary helper workspace.'
            Remove-TemporaryRollbackRootBestEffort -RollbackRoot $script:EphemeralRollbackRoot -Reason 'successful automatic rollback'
            $script:EphemeralRollbackRoot = ''
        }
        catch {
            Write-Log ("Automatic rollback failed: {0}" -f $_.Exception.Message) 'ERROR'
            if ($_.ScriptStackTrace) {
                Write-Log $_.ScriptStackTrace 'ERROR'
            }
            Add-ResultPairMessage -Message 'Automatic rollback failed after legacy import mutation. Review the helper log before retrying.'
        }
    }
    Save-Log
    Emit-ResultPairs
    exit 1
}
