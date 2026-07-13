[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentTargetRoot,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$ExpectedReleaseVariant,
    [switch]$NonInteractive,
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
. (Join-Path $PSScriptRoot 'VersionManager.ReleaseCatalog.ps1')

$script:LogMessages = New-Object System.Collections.Generic.List[string]
$script:LogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
$script:ResolvedCurrentRoot = ''
$script:ResolvedLatestRoot = ''
$script:ResolvedStageRoot = ''
$script:ReplacementRollbackRoot = ''
$script:FailedLatestRoot = ''
$script:LatestRootCreated = $false
$script:StageRootCreated = $false
$script:FixedRootReplacementStarted = $false
$script:FixedRootInstalled = $false
$script:ImportStarted = $false
$script:SwitchSucceeded = $false
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




























































try {
    Invoke-UpdateToLatest
}
catch {
    if ($script:FixedRootReplacementStarted -and -not $script:FixedRootInstalled -and
        -not [string]::IsNullOrWhiteSpace($script:ResolvedCurrentRoot) -and
        -not [string]::IsNullOrWhiteSpace($script:ReplacementRollbackRoot)) {
        try {
            if (-not (Test-Path -LiteralPath $script:ResolvedCurrentRoot) -and
                (Test-Path -LiteralPath $script:ReplacementRollbackRoot -PathType Container)) {
                Restore-FixedRootBestEffort -FinalRoot $script:ResolvedCurrentRoot -RollbackRoot $script:ReplacementRollbackRoot
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
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
}
finally {
    Save-Log
    Emit-ResultPairs
}
