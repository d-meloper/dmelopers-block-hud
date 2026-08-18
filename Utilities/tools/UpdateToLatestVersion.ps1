[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$ExpectedVersion,
    [string]$ExpectedReleaseVariant,
    [switch]$ResetCurrentVersion,
    [switch]$InheritedOperationLock,
    [switch]$NonInteractive,
    [switch]$EmitResultPairs,
    [switch]$PassThruResultObject
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:LogStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
    $OutputEncoding = $script:Utf8NoBom
}
catch {
}

. (Join-Path $PSScriptRoot 'Localization.Common.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.ReleaseIdentity.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.OperationLock.ps1')

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:ResolvedCurrentRoot = ''
$script:ResolvedLatestRoot = ''
$script:ResolvedStageRoot = ''
$script:ExtractRoot = ''
$script:StageParentRoot = ''
$script:ReplacementRollbackRoot = ''
$script:ReplacementRollbackParent = ''
$script:FailedLatestRoot = ''
$script:LatestRootCreated = $false
$script:StageRootCreated = $false
$script:FixedRootReplacementStarted = $false
$script:FixedRootInstalled = $false
$script:FixedRootQuiesced = $false
$script:ImportStarted = $false
$script:SwitchSucceeded = $false
$script:PostUpdateActivationSucceeded = $false
$script:ResetRecoveryTransaction = $null
$script:ResetRecoveryGuardReady = $false
$script:UpdateOperationLock = $null
$script:ResultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_SOURCEPATH = ''
    DMEL_BACKUPPATH = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
}

$script:ModuleRoot = Join-Path $PSScriptRoot 'UpdateToLatestVersion'
. (Join-Path $script:ModuleRoot 'CorePathsAndPackage.ps1')
. (Join-Path $script:ModuleRoot 'ReplacementAndSwitch.ps1')
. (Join-Path $script:ModuleRoot 'CurrentVersionDataReset.ps1')
. (Join-Path $script:ModuleRoot 'ResetRecovery.ps1')




























































try {
    Invoke-UpdateToLatest
}
catch {
    $operationError = $_
    if ($null -ne $script:ResetRecoveryTransaction -and -not $script:PostUpdateActivationSucceeded) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($script:ReplacementRollbackRoot) -and
                (Test-Path -LiteralPath $script:ReplacementRollbackRoot -PathType Container)) {
                if (Test-Path -LiteralPath $script:ResolvedCurrentRoot -PathType Container) {
                    Invoke-QuiesceCurrentRoot -Root $script:ResolvedCurrentRoot
                }
                if (Test-Path -LiteralPath $script:ResolvedCurrentRoot -PathType Container) {
                    Restore-InstalledFixedRootBestEffort `
                        -FinalRoot $script:ResolvedCurrentRoot `
                        -RollbackRoot $script:ReplacementRollbackRoot `
                        -Reason 'current-version reset failure' | Out-Null
                }
                else {
                    Restore-FixedRootBestEffort -FinalRoot $script:ResolvedCurrentRoot -RollbackRoot $script:ReplacementRollbackRoot
                    $script:FixedRootReplacementStarted = $false
                }
            }
            Set-ResetRecoveryPhase -Phase 'Restored'
            if (-not $script:ResetRecoveryGuardReady) {
                Remove-SafeUpdateTempRootBestEffort -Root ([string]$script:ResetRecoveryTransaction.JournalRoot) -Reason 'recovery guard startup failure'
            }
            if ($script:FixedRootQuiesced -and (Test-Path -LiteralPath $script:ResolvedCurrentRoot -PathType Container)) {
                Invoke-PostUpdateRefresh -Root $script:ResolvedCurrentRoot
            }
        }
        catch {
            Write-Log ("Fixed-root restore attempt failed in outer catch: {0}" -f $_.Exception.Message) 'ERROR'
            try {
                Set-ResetRecoveryPhase -Phase 'RecoveryPending'
            }
            catch {
                Write-Log ("Could not hand failed fixed-root restoration to the recovery guard: {0}" -f $_.Exception.Message) 'ERROR'
            }
        }
    }
    elseif ($script:FixedRootReplacementStarted -and -not $script:PostUpdateActivationSucceeded -and
        -not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot) -and
        -not [string]::IsNullOrWhiteSpace($script:ReplacementRollbackRoot)) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($script:ReplacementRollbackRoot) -and
                (Test-Path -LiteralPath $script:ReplacementRollbackRoot -PathType Container)) {
                if (Test-Path -LiteralPath $script:ResolvedCurrentRoot -PathType Container) {
                    Restore-InstalledFixedRootBestEffort `
                        -FinalRoot $script:ResolvedCurrentRoot `
                        -RollbackRoot $script:ReplacementRollbackRoot `
                        -Reason 'fixed-root update failure' | Out-Null
                }
                else {
                    Restore-FixedRootBestEffort -FinalRoot $script:ResolvedCurrentRoot -RollbackRoot $script:ReplacementRollbackRoot
                    $script:FixedRootReplacementStarted = $false
                }
            }
        }
        catch {
            Write-Log ("Fixed-root restore attempt failed in outer catch: {0}" -f $_.Exception.Message) 'ERROR'
        }
    }

    if ($script:LatestRootCreated -and -not $script:SwitchSucceeded -and -not [string]::IsNullOrWhiteSpace($script:ResolvedLatestRoot)) {
        Remove-RootBestEffort -Root $script:ResolvedLatestRoot -Reason 'error rollback'
    }
    if ($script:StageRootCreated -and -not $script:ImportStarted -and -not [string]::IsNullOrWhiteSpace($script:ResolvedStageRoot)) {
        Remove-RootBestEffort -Root $script:ResolvedStageRoot -Reason 'error rollback'
    }
    elseif ($script:StageRootCreated -and $script:ImportStarted -and -not [string]::IsNullOrWhiteSpace($script:ResolvedStageRoot)) {
        Remove-RootBestEffort -Root $script:ResolvedStageRoot -Reason 'failed import or replacement'
        if (Test-Path -LiteralPath $script:ResolvedStageRoot -PathType Container) {
            Write-Log ("Preserved staged root after failed cleanup for diagnostics: {0}" -f $script:ResolvedStageRoot) 'WARN'
        }
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot)) {
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $script:ResolvedCurrentRoot
        if (-not $script:SwitchSucceeded) {
            Use-CanonicalHelperLogPath -Root $script:ResolvedCurrentRoot -Prefix 'UpdateToLatestVersion'
        }
    }
    if (-not $script:ImportStarted) {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    }
    else {
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
    }
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $operationError.Exception.Message
    Write-Log $operationError.Exception.Message 'ERROR'
    if ($operationError.ScriptStackTrace) {
        Write-Log $operationError.ScriptStackTrace 'ERROR'
    }
}
finally {
    Remove-UpdateExtractRootBestEffort
    Remove-UpdateStageParentBestEffort
    Remove-UpdateFailedRootBestEffort
    Exit-VersionManagerOperationMutex -Lock $script:UpdateOperationLock
    $script:UpdateOperationLock = $null
    Save-Log
    if ($PassThruResultObject) {
        Write-Output ([PSCustomObject]$script:ResultPairs)
    }
    else {
        Emit-ResultPairs
    }
}
