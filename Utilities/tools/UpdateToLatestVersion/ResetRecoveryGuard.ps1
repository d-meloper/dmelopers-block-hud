[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{32}$')][string]$Token,
    [Parameter(Mandatory = $true)][int]$ParentProcessId,
    [Parameter(Mandatory = $true)][long]$ParentStartTimeUtcTicks,
    [Parameter(Mandatory = $true)][string]$CurrentRoot,
    [Parameter(Mandatory = $true)][string]$RollbackRoot,
    [Parameter(Mandatory = $true)][string]$StageParentRoot,
    [Parameter(Mandatory = $true)][string]$ExtractRoot,
    [Parameter(Mandatory = $true)][string]$SkinsRoot,
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [Parameter(Mandatory = $true)][string]$ReadyPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Set-Location ([System.IO.Path]::GetTempPath())

function Resolve-GuardFullPath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)

    $full = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\', '/')
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Recovery path does not exist: $full"
    }
    return $full
}

function Test-GuardPathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Path)

    $rootFull = (Resolve-GuardFullPath -Path $Root).ToLowerInvariant()
    $pathFull = (Resolve-GuardFullPath -Path $Path -AllowMissing).ToLowerInvariant()
    return ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\'))
}

function Assert-GuardTempPath {
    param([Parameter(Mandatory = $true)][string]$TempRoot, [Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-GuardFullPath -Path $Path -AllowMissing
    if (-not (Test-GuardPathWithinRoot -Root $TempRoot -Path $resolved) -or
        [string]::Equals($resolved, $TempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Recovery path is outside TEMP: $resolved"
    }
    return $resolved
}

function Test-OriginalParentAlive {
    $process = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $false
    }
    try {
        return ([long]$process.StartTime.ToUniversalTime().Ticks -eq $ParentStartTimeUtcTicks)
    }
    catch {
        return $false
    }
}

function Read-RecoveryJournalStrict {
    if (-not (Test-Path -LiteralPath $script:ResolvedJournalPath -PathType Leaf)) {
        throw 'Recovery journal is missing.'
    }
    $journal = [System.IO.File]::ReadAllText($script:ResolvedJournalPath, $utf8NoBom) | ConvertFrom-Json
    if ([int]$journal.SchemaVersion -ne 1 -or
        -not [string]::Equals([string]$journal.Token, $Token, [System.StringComparison]::Ordinal) -or
        [int]$journal.ParentProcessId -ne $ParentProcessId -or
        [long]$journal.ParentStartTimeUtcTicks -ne $ParentStartTimeUtcTicks -or
        -not [string]::Equals([string]$journal.CurrentRoot, $script:ResolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$journal.RollbackRoot, $script:ResolvedRollbackRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$journal.StageParentRoot, $script:ResolvedStageParentRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$journal.ExtractRoot, $script:ResolvedExtractRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$journal.SkinsRoot, $script:ResolvedSkinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recovery journal identity did not match the active reset transaction.'
    }
    return $journal
}

function Read-RecoveryPhase {
    try {
        return [string](Read-RecoveryJournalStrict).Phase
    }
    catch {
        return ''
    }
}

function Remove-GuardTempRootBestEffort {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    catch {
    }
}

function Restore-OriginalRoot {
    if (-not (Test-Path -LiteralPath $script:ResolvedRollbackRoot -PathType Container)) {
        return $false
    }

    $quarantineRoot = Join-Path $script:ResolvedJournalRoot 'FailedReplacement'
    if (Test-Path -LiteralPath $script:ResolvedCurrentRoot) {
        if (Test-Path -LiteralPath $quarantineRoot) {
            Remove-Item -LiteralPath $quarantineRoot -Recurse -Force
        }
        Move-Item -LiteralPath $script:ResolvedCurrentRoot -Destination $quarantineRoot
    }

    try {
        Move-Item -LiteralPath $script:ResolvedRollbackRoot -Destination $script:ResolvedCurrentRoot
    }
    catch {
        if (-not (Test-Path -LiteralPath $script:ResolvedCurrentRoot) -and
            (Test-Path -LiteralPath $quarantineRoot -PathType Container)) {
            Move-Item -LiteralPath $quarantineRoot -Destination $script:ResolvedCurrentRoot
        }
        throw
    }

    Remove-GuardTempRootBestEffort -Path $quarantineRoot
    return $true
}

function Invoke-PostRestoreRefreshBestEffort {
    try {
        $rainmeter = Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
            Select-Object -First 1
        if ($null -eq $rainmeter -or -not (Test-Path -LiteralPath $rainmeter.Path -PathType Leaf)) {
            return
        }

        & $rainmeter.Path '!RefreshApp' | Out-Null
        & $rainmeter.Path '!RefreshGroup' 'DMeloper' | Out-Null
        $bootstrapRelativePath = 'Utilities\Bootstrap'
        $bootstrapFileName = 'ZPosBootstrap.ini'
        $bootstrapPath = Join-Path (Join-Path $script:ResolvedCurrentRoot $bootstrapRelativePath) $bootstrapFileName
        if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) {
            $rootConfigName = [System.IO.Path]::GetFileName($script:ResolvedCurrentRoot)
            $bootstrapConfigName = $rootConfigName + '\' + $bootstrapRelativePath
            & $rainmeter.Path '!ActivateConfig' $bootstrapConfigName $bootstrapFileName | Out-Null
        }
    }
    catch {
        # Folder restoration is authoritative. A failed best-effort refresh must
        # never remove the restored root or retry mutation.
    }
}

try {
    $tempRoot = Resolve-GuardFullPath -Path ([System.IO.Path]::GetTempPath())
    $script:ResolvedSkinsRoot = Resolve-GuardFullPath -Path $SkinsRoot
    $script:ResolvedCurrentRoot = Resolve-GuardFullPath -Path $CurrentRoot -AllowMissing
    if (-not (Test-GuardPathWithinRoot -Root $script:ResolvedSkinsRoot -Path $script:ResolvedCurrentRoot) -or
        [string]::Equals($script:ResolvedSkinsRoot, $script:ResolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recovery current root is outside the Rainmeter skins root.'
    }

    $script:ResolvedRollbackRoot = Assert-GuardTempPath -TempRoot $tempRoot -Path $RollbackRoot
    $script:ResolvedStageParentRoot = Assert-GuardTempPath -TempRoot $tempRoot -Path $StageParentRoot
    $script:ResolvedExtractRoot = Assert-GuardTempPath -TempRoot $tempRoot -Path $ExtractRoot
    $script:ResolvedJournalPath = Assert-GuardTempPath -TempRoot $tempRoot -Path $JournalPath
    $script:ResolvedReadyPath = Assert-GuardTempPath -TempRoot $tempRoot -Path $ReadyPath
    $script:ResolvedJournalRoot = Split-Path -Parent $script:ResolvedJournalPath
    if (-not [string]::Equals((Split-Path -Parent $script:ResolvedReadyPath), $script:ResolvedJournalRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recovery ready file and journal must share one transaction directory.'
    }

    $initialJournal = Read-RecoveryJournalStrict
    if (-not [string]::Equals([string]$initialJournal.Phase, 'Prepared', [System.StringComparison]::Ordinal)) {
        throw "Recovery guard expected a Prepared journal, but found: $([string]$initialJournal.Phase)"
    }
    [System.IO.File]::WriteAllText($script:ResolvedReadyPath, $Token, $utf8NoBom)

    while ($true) {
        $phase = Read-RecoveryPhase
        if ($phase -eq 'Committed') {
            Remove-GuardTempRootBestEffort -Path $script:ResolvedJournalRoot
            exit 0
        }
        if ($phase -eq 'Restored') {
            Remove-GuardTempRootBestEffort -Path (Split-Path -Parent $script:ResolvedRollbackRoot)
            Remove-GuardTempRootBestEffort -Path $script:ResolvedStageParentRoot
            Remove-GuardTempRootBestEffort -Path $script:ResolvedExtractRoot
            Remove-GuardTempRootBestEffort -Path $script:ResolvedJournalRoot
            exit 0
        }
        if ($phase -eq 'CleanupPending') {
            Remove-GuardTempRootBestEffort -Path (Split-Path -Parent $script:ResolvedRollbackRoot)
            if (-not (Test-Path -LiteralPath (Split-Path -Parent $script:ResolvedRollbackRoot))) {
                Remove-GuardTempRootBestEffort -Path $script:ResolvedStageParentRoot
                Remove-GuardTempRootBestEffort -Path $script:ResolvedExtractRoot
                Remove-GuardTempRootBestEffort -Path $script:ResolvedJournalRoot
                exit 0
            }
        }
        if ($phase -eq 'RecoveryPending') {
            try {
                $restoredOriginalRoot = Restore-OriginalRoot
                if ($restoredOriginalRoot) {
                    Invoke-PostRestoreRefreshBestEffort
                }
                Remove-GuardTempRootBestEffort -Path (Split-Path -Parent $script:ResolvedRollbackRoot)
                Remove-GuardTempRootBestEffort -Path $script:ResolvedStageParentRoot
                Remove-GuardTempRootBestEffort -Path $script:ResolvedExtractRoot
                Remove-GuardTempRootBestEffort -Path $script:ResolvedJournalRoot
                exit 0
            }
            catch {
                Start-Sleep -Milliseconds 500
                continue
            }
        }

        if (-not (Test-OriginalParentAlive)) {
            if ($phase -eq 'Activated' -or $phase -eq 'CleanupPending') {
                Remove-GuardTempRootBestEffort -Path (Split-Path -Parent $script:ResolvedRollbackRoot)
            }
            else {
                $restoredOriginalRoot = Restore-OriginalRoot
                if ($restoredOriginalRoot) {
                    Invoke-PostRestoreRefreshBestEffort
                }
                Remove-GuardTempRootBestEffort -Path (Split-Path -Parent $script:ResolvedRollbackRoot)
            }
            Remove-GuardTempRootBestEffort -Path $script:ResolvedStageParentRoot
            Remove-GuardTempRootBestEffort -Path $script:ResolvedExtractRoot
            Remove-GuardTempRootBestEffort -Path $script:ResolvedJournalRoot
            exit 0
        }
        Start-Sleep -Milliseconds 250
    }
}
catch {
    try {
        $errorPath = Join-Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($JournalPath))) 'GuardError.txt'
        [System.IO.File]::WriteAllText($errorPath, $_.Exception.Message, $utf8NoBom)
    }
    catch {
    }
    exit 1
}
