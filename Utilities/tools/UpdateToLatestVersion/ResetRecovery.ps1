# Fixed-root replacement recovery coordination.
# Dot-sourced by UpdateToLatestVersion.ps1; the detached guard is started before mutation.

function Write-ResetRecoveryJournalAtomic {
    param([Parameter(Mandatory = $true)]$Transaction)

    $payload = [ordered]@{
        SchemaVersion = 1
        Token = [string]$Transaction.Token
        Phase = [string]$Transaction.Phase
        ParentProcessId = [int]$Transaction.ParentProcessId
        ParentStartTimeUtcTicks = [long]$Transaction.ParentStartTimeUtcTicks
        CurrentRoot = [string]$Transaction.CurrentRoot
        RollbackRoot = [string]$Transaction.RollbackRoot
        StageParentRoot = [string]$Transaction.StageParentRoot
        ExtractRoot = [string]$Transaction.ExtractRoot
        SkinsRoot = [string]$Transaction.SkinsRoot
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $temporaryPath = [string]$Transaction.JournalPath + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Depth 4), $script:Utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination ([string]$Transaction.JournalPath) -Force
}

function New-ResetRecoveryTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [Parameter(Mandatory = $true)][string]$StageParentRoot,
        [Parameter(Mandatory = $true)][string]$ExtractRoot
    )

    $token = [guid]::NewGuid().ToString('N')
    $tempRoot = Resolve-FullPath -Path ([System.IO.Path]::GetTempPath())
    $journalRoot = Join-Path $tempRoot ("DMeloperResetRecovery_{0}" -f $token)
    $rollbackParent = Join-Path $tempRoot ("DMeloperResetRollback_{0}" -f $token)
    $rollbackRoot = Join-Path $rollbackParent ([System.IO.Path]::GetFileName($CurrentRoot))
    Ensure-Directory -Path $journalRoot

    $parent = Get-Process -Id $PID -ErrorAction Stop
    $transaction = [PSCustomObject]@{
        Token = $token
        Phase = 'Prepared'
        ParentProcessId = [int]$PID
        ParentStartTimeUtcTicks = [long]$parent.StartTime.ToUniversalTime().Ticks
        CurrentRoot = (Resolve-FullPath -Path $CurrentRoot)
        RollbackRoot = (Resolve-FullPath -Path $rollbackRoot -AllowMissing)
        StageParentRoot = (Resolve-FullPath -Path $StageParentRoot)
        ExtractRoot = (Resolve-FullPath -Path $ExtractRoot)
        SkinsRoot = (Resolve-FullPath -Path $SkinsRoot)
        JournalRoot = (Resolve-FullPath -Path $journalRoot)
        JournalPath = (Join-Path $journalRoot 'ResetTransaction.json')
        ReadyPath = (Join-Path $journalRoot 'GuardReady.txt')
    }
    Write-ResetRecoveryJournalAtomic -Transaction $transaction
    return $transaction
}

function Start-ResetRecoveryGuard {
    param([Parameter(Mandatory = $true)]$Transaction)

    $guardPath = Join-Path $script:ModuleRoot 'ResetRecoveryGuard.ps1'
    if (-not (Test-Path -LiteralPath $guardPath -PathType Leaf)) {
        throw "Current-version reset recovery guard is missing: $guardPath"
    }

    Start-DetachedRuntimeHostScript -ScriptPath $guardPath -Arguments @(
        '-Token', [string]$Transaction.Token,
        '-ParentProcessId', [string]$Transaction.ParentProcessId,
        '-ParentStartTimeUtcTicks', [string]$Transaction.ParentStartTimeUtcTicks,
        '-CurrentRoot', [string]$Transaction.CurrentRoot,
        '-RollbackRoot', [string]$Transaction.RollbackRoot,
        '-StageParentRoot', [string]$Transaction.StageParentRoot,
        '-ExtractRoot', [string]$Transaction.ExtractRoot,
        '-SkinsRoot', [string]$Transaction.SkinsRoot,
        '-JournalPath', [string]$Transaction.JournalPath,
        '-ReadyPath', [string]$Transaction.ReadyPath
    )

    # A cold Windows PowerShell launch may be delayed substantially by AMSI/AV.
    # Mutation remains blocked until the detached recovery owner acknowledges.
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    $guardErrorPath = Join-Path ([string]$Transaction.JournalRoot) 'GuardError.txt'
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $guardErrorPath -PathType Leaf) {
            $guardError = ([System.IO.File]::ReadAllText($guardErrorPath, $script:Utf8NoBom)).Trim()
            throw ("Current-version reset recovery guard failed before mutation: {0}" -f $guardError)
        }
        if (Test-Path -LiteralPath ([string]$Transaction.ReadyPath) -PathType Leaf) {
            $readyToken = ([System.IO.File]::ReadAllText([string]$Transaction.ReadyPath, $script:Utf8NoBom)).Trim()
            if ([string]::Equals($readyToken, [string]$Transaction.Token, [System.StringComparison]::Ordinal)) {
                Write-Log ("Current-version reset recovery guard is ready. token={0}" -f [string]$Transaction.Token)
                $script:ResetRecoveryGuardReady = $true
                return
            }
        }
        Start-Sleep -Milliseconds 100
    }

    throw 'Current-version reset recovery guard did not acknowledge startup within 180 seconds; no skin data was changed.'
}

function Set-ResetRecoveryPhase {
    param([Parameter(Mandatory = $true)][ValidateSet('Prepared', 'NewRootInstalled', 'Activating', 'Activated', 'RecoveryPending', 'CleanupPending', 'Committed', 'Restored')][string]$Phase)

    if ($null -eq $script:ResetRecoveryTransaction) {
        return
    }
    if ([string]::Equals([string]$script:ResetRecoveryTransaction.Phase, $Phase, [System.StringComparison]::Ordinal)) {
        return
    }
    $script:ResetRecoveryTransaction.Phase = $Phase
    Write-ResetRecoveryJournalAtomic -Transaction $script:ResetRecoveryTransaction
    Write-Log ("Current-version reset recovery phase: {0}" -f $Phase)
}

function Initialize-FixedRootActivationHandoff {
    param(
        [Parameter(Mandatory = $true)][string]$StagedRoot,
        [Parameter(Mandatory = $true)]$Transaction
    )

    $paths = Get-BlockHudFixedRootHandoffPaths -Root $StagedRoot
    Ensure-Directory -Path $paths.DataRoot
    foreach ($stalePath in @($paths.RequestPath, $paths.AckPath, ([string]$paths.AckPath + '.tmp'))) {
        if (Test-Path -LiteralPath $stalePath) {
            Remove-Item -LiteralPath $stalePath -Force
        }
    }
    $request = [ordered]@{
        SchemaVersion = 1
        Token = [string]$Transaction.Token
        CurrentRoot = [string]$Transaction.CurrentRoot
        RequestedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [System.IO.File]::WriteAllText($paths.RequestPath, ($request | ConvertTo-Json -Depth 3), $script:Utf8NoBom)
    Write-Log ("Prepared fixed-root Bootstrap activation handoff. token={0}" -f [string]$Transaction.Token)
}

function Remove-FixedRootActivationHandoffBestEffort {
    param([Parameter(Mandatory = $true)][string]$Root)

    try {
        $paths = Get-BlockHudFixedRootHandoffPaths -Root $Root
        foreach ($path in @($paths.RequestPath, $paths.AckPath, ([string]$paths.AckPath + '.tmp'))) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }
    catch {
        Write-Log ("Could not remove fixed-root activation handoff files: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Wait-FixedRootActivationHandoff {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)]$ImmutableSnapshot,
        [ValidateRange(10, 300)][int]$TimeoutSeconds = 240
    )

    $resolvedRoot = Resolve-FullPath -Path $Root
    $paths = Get-BlockHudFixedRootHandoffPaths -Root $resolvedRoot
    $layoutContract = Get-BlockHudLayoutContract -Root $resolvedRoot
    $adapterManifestPath = Join-Path $resolvedRoot ([string]$layoutContract.legacyTransportAdapter.manifestRelativePath)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $paths.AckPath -PathType Leaf) {
            try {
                $ack = [System.IO.File]::ReadAllText($paths.AckPath, $script:Utf8NoBom) | ConvertFrom-Json
                if ([int]$ack.SchemaVersion -eq 1 -and
                    [string]::Equals([string]$ack.Token, [string]$Transaction.Token, [System.StringComparison]::Ordinal) -and
                    [string]::Equals([string]$ack.CurrentRoot, $resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
                    [string]::Equals([string]$ack.Status, 'OK', [System.StringComparison]::Ordinal)) {
                    Assert-BlockHudFixedRootRuntimeContract `
                        -Root $resolvedRoot `
                        -Context 'Activated fixed root' `
                        -RequireTransportAdapterAbsent
                    Assert-BlockHudFixedRootImmutableSnapshot `
                        -Root $resolvedRoot `
                        -Snapshot $ImmutableSnapshot `
                        -Context 'Activated fixed root'
                    Remove-FixedRootActivationHandoffBestEffort -Root $resolvedRoot
                    Write-Log ("Received verified fixed-root Bootstrap activation handoff. token={0}" -f [string]$Transaction.Token)
                    return
                }
            }
            catch {
                throw ("Fixed-root Bootstrap activation handoff was invalid: {0}" -f $_.Exception.Message)
            }
        }
        elseif (-not (Test-Path -LiteralPath $adapterManifestPath)) {
            # Same-version public packages can predate the explicit acknowledgement
            # writer. The signed adapter manifest is removed only at the end of the
            # package-local Bootstrap cleanup, so its exact disappearance plus two
            # immutable-runtime validations is the backward-compatible completion gate.
            Assert-BlockHudFixedRootRuntimeContract `
                -Root $resolvedRoot `
                -Context 'Activated fixed root' `
                -RequireTransportAdapterAbsent
            Assert-BlockHudFixedRootImmutableSnapshot `
                -Root $resolvedRoot `
                -Snapshot $ImmutableSnapshot `
                -Context 'Activated fixed root'
            Start-Sleep -Milliseconds 500
            Assert-BlockHudFixedRootRuntimeContract `
                -Root $resolvedRoot `
                -Context 'Stable activated fixed root' `
                -RequireTransportAdapterAbsent
            Assert-BlockHudFixedRootImmutableSnapshot `
                -Root $resolvedRoot `
                -Snapshot $ImmutableSnapshot `
                -Context 'Stable activated fixed root'
            Remove-FixedRootActivationHandoffBestEffort -Root $resolvedRoot
            Write-Log ("Verified backward-compatible fixed-root Bootstrap completion. token={0}" -f [string]$Transaction.Token)
            return
        }
        Start-Sleep -Milliseconds 100
    }

    throw "Fixed-root Bootstrap did not acknowledge verified activation within $TimeoutSeconds seconds."
}
