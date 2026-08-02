# UpdateToLatestVersion helpers - Replacement import switch and cleanup

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Copy-PackageToDestination {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (Test-Path -LiteralPath $DestinationRoot) {
        throw "Destination install root already exists: $DestinationRoot"
    }

    $parent = Split-Path -Parent $DestinationRoot
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "Could not resolve destination parent for: $DestinationRoot"
    }

    Ensure-Directory -Path $parent
    Copy-Item -LiteralPath $PackageRoot -Destination $DestinationRoot -Recurse -Force
}

function New-StagedLatestRoot {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$IdentityName
    )

    $stageParent = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestStage_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    $stageRoot = Join-Path $stageParent (Convert-ToSafeFolderName -Name $IdentityName)
    Ensure-Directory -Path $stageParent
    $script:StageParentRoot = (Resolve-FullPath -Path $stageParent)
    Copy-Item -LiteralPath $PackageRoot -Destination $stageRoot -Recurse -Force
    $script:ResolvedStageRoot = (Resolve-FullPath -Path $stageRoot)
    Assert-NoReparsePoints -Root $script:ResolvedStageRoot -Context 'Staged update package'
    $script:StageRootCreated = $true
    Write-Log ("StagedLatestRoot: {0}" -f $script:ResolvedStageRoot)
    return $script:ResolvedStageRoot
}

function Remove-RootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return
    }

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    try {
        Remove-Item -LiteralPath $Root -Force -Recurse
        Write-Log ("Cleaned root after {0}: {1}" -f $Reason, $Root)
    }
    catch {
        Write-Log ("Failed to clean root after {0}: {1} ({2})" -f $Reason, $Root, $_.Exception.Message) 'WARN'
    }
}

function Remove-RootWithResult {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return [PSCustomObject]@{
            Status = 'OK'
            Message = 'Root was already absent.'
        }
    }

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    try {
        Remove-Item -LiteralPath $Root -Force -Recurse
        Write-Log ("Cleaned root after {0}: {1}" -f $Reason, $Root)
        return [PSCustomObject]@{
            Status = 'OK'
            Message = 'Cleanup completed.'
        }
    }
    catch {
        $message = "Failed to clean root after ${Reason}: $Root ($($_.Exception.Message))"
        Write-Log $message 'WARN'
        return [PSCustomObject]@{
            Status = 'WARN'
            Message = $message
        }
    }
}

function Test-ConfigFileExists {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $folderPath = Join-RootPath -Root $Root -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        return $false
    }

    return (Test-Path -LiteralPath (Join-Path $folderPath $FileName) -PathType Leaf)
}

function Restore-FixedRootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$FinalRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot
    )

    if (-not (Test-Path -LiteralPath $RollbackRoot -PathType Container)) {
        throw "Rollback root is missing; manual recovery may be required: $RollbackRoot"
    }

    if (Test-Path -LiteralPath $FinalRoot) {
        throw "Final root already exists; refusing to overwrite it during rollback: $FinalRoot"
    }

    Move-Item -LiteralPath $RollbackRoot -Destination $FinalRoot
    Write-Log ("Restored fixed root from rollback root: {0}" -f $RollbackRoot)
}

function Restore-InstalledFixedRootBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$FinalRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $failedParent = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestFailed_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $failedParent
    $failedRoot = Join-Path $failedParent ([System.IO.Path]::GetFileName($FinalRoot))

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    $script:FixedRootInstalled = $false
    if (Test-Path -LiteralPath $FinalRoot) {
        Move-Item -LiteralPath $FinalRoot -Destination $failedRoot
        $script:FailedLatestRoot = $failedRoot
        Write-Log ("Moved failed fixed-root install aside after {0}: {1}" -f $Reason, $failedRoot) 'WARN'
    }

    Restore-FixedRootBestEffort -FinalRoot $FinalRoot -RollbackRoot $RollbackRoot
    $script:FixedRootReplacementStarted = $false
    return $failedRoot
}

function Get-RootConfigName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $leaf = Split-Path -Path $Root -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Could not derive a root config name from [$Root]."
    }

    return $leaf
}

function Get-ConfigName {
    param(
        [Parameter(Mandatory = $true)][string]$RootConfigName,
        [Parameter(Mandatory = $true)][string]$RelativeConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($RelativeConfigPath)) {
        return $RootConfigName
    }

    return ($RootConfigName + '\' + $RelativeConfigPath.Trim('\'))
}

function Get-ZPosBootstrapSpec {
    [PSCustomObject]@{ RelativePath = 'Utilities\Bootstrap'; FileName = 'ZPosBootstrap.ini' }
}

function Get-RetiredCurrentRootConfigSpecs {
    @(
        [PSCustomObject]@{ RelativePath = 'ExtraContent\Jukebox\Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'Activities\Jukebox\Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'Contents\Jukebox\Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'Jukebox_minimized' }
        [PSCustomObject]@{ RelativePath = 'JukeboxMinimized' }
    )
}

function Get-RainmeterActiveConfigSet {
    $activeConfigs = @{}
    $configPath = Get-RainmeterConfigPath
    if ([string]::IsNullOrWhiteSpace($configPath) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-Log 'Rainmeter.ini was not available for retired active-config cleanup; skipping active-only cleanup.' 'WARN'
        return $activeConfigs
    }

    $currentSection = ''
    foreach ($rawLine in ((Read-TextSmart -Path $configPath) -split "`r?`n")) {
        $line = [string]$rawLine
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            continue
        }

        if ($currentSection -eq '' -or $trimmed.StartsWith(';')) {
            continue
        }

        if ($trimmed -match '^Active\s*=\s*1\s*$') {
            $activeConfigs[$currentSection] = $true
        }
    }

    return $activeConfigs
}

function Invoke-RetiredCurrentRootConfigCleanup {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootConfigName = Get-RootConfigName -Root $Root
    $activeConfigs = Get-RainmeterActiveConfigSet
    foreach ($spec in @(Get-RetiredCurrentRootConfigSpecs)) {
        $configName = Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath)
        if (-not $activeConfigs.ContainsKey($configName)) {
            Write-Log ("Retired config cleanup skipped inactive [{0}]" -f $configName)
            continue
        }

        try {
            Write-Log ("Deactivating retired config [{0}]" -f $configName)
            Invoke-RainmeterBang -Bang '!DeactivateConfig' -Arguments @($configName)
        }
        catch {
            Write-Log ("Retired config cleanup failed for [{0}]: {1}" -f $configName, $_.Exception.Message) 'WARN'
        }
    }
}

function Invoke-ActivateZPosBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $spec = Get-ZPosBootstrapSpec
    $rootConfigName = Get-RootConfigName -Root $Root
    if (-not (Test-ConfigFileExists -Root $Root -RelativePath ([string]$spec.RelativePath) -FileName ([string]$spec.FileName))) {
        throw ("Fixed-root update is missing the z-position bootstrap skin: {0}\{1}" -f $Root, [string]$spec.RelativePath)
    }

    $configName = Get-ConfigName -RootConfigName $rootConfigName -RelativeConfigPath ([string]$spec.RelativePath)
    Write-Log ("Activating z-position bootstrap [{0}] ({1})" -f $configName, [string]$spec.FileName)
    Invoke-RainmeterBang -Bang '!ActivateConfig' -Arguments @($configName, [string]$spec.FileName)
}

function Invoke-PostUpdateRefresh {
    param([Parameter(Mandatory = $true)][string]$Root)

    Write-Log 'Refreshing Rainmeter app and running z-position bootstrap after fixed-root update.'
    Invoke-RainmeterBang -Bang '!RefreshApp'
    Invoke-RainmeterBang -Bang '!RefreshGroup' -Arguments @('DMeloper')
    Invoke-ActivateZPosBootstrap -Root $Root
}

function Invoke-FixedRootReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$StagedRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [string]$PreparedRollbackRoot = ''
    )

    $resolvedCurrentRoot = Resolve-FullPath -Path $CurrentRoot
    $resolvedStagedRoot = Resolve-FullPath -Path $StagedRoot
    $resolvedSkinsRoot = Resolve-FullPath -Path $SkinsRoot
    if (-not (Test-PathWithinRoot -Root $resolvedSkinsRoot -Path $resolvedCurrentRoot) -or
        [string]::Equals($resolvedCurrentRoot, $resolvedSkinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace a path outside the Rainmeter skins root: $resolvedCurrentRoot"
    }

    if ((Test-PathWithinRoot -Root $resolvedCurrentRoot -Path $resolvedStagedRoot) -or
        (Test-PathWithinRoot -Root $resolvedStagedRoot -Path $resolvedCurrentRoot)) {
        throw 'Fixed-root replacement requires separate current and staged roots.'
    }

    if ([string]::IsNullOrWhiteSpace($PreparedRollbackRoot)) {
        $rollbackParent = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestRollback_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
        $rollbackRoot = Join-Path $rollbackParent ([System.IO.Path]::GetFileName($resolvedCurrentRoot))
    }
    else {
        $rollbackRoot = Resolve-FullPath -Path $PreparedRollbackRoot -AllowMissing
        $rollbackParent = Split-Path -Parent $rollbackRoot
        $tempRoot = Resolve-FullPath -Path ([System.IO.Path]::GetTempPath())
        if (-not (Test-PathWithinRoot -Root $tempRoot -Path $rollbackRoot) -or
            [string]::Equals($rollbackRoot, $tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Prepared rollback root must be a transaction-owned path under TEMP: $rollbackRoot"
        }
        if (Test-Path -LiteralPath $rollbackRoot) {
            throw "Prepared rollback root already exists: $rollbackRoot"
        }
    }
    Ensure-Directory -Path $rollbackParent
    $script:ReplacementRollbackParent = $rollbackParent
    $script:ReplacementRollbackRoot = $rollbackRoot
    Write-Log ("ReplacementRollbackRoot: {0}" -f $rollbackRoot)

    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    $script:FixedRootReplacementStarted = $true
    try {
        Move-Item -LiteralPath $resolvedCurrentRoot -Destination $rollbackRoot
        Write-Log ("Moved current fixed root to rollback root: {0}" -f $rollbackRoot)

        $stagedMovedToFinal = $false
        try {
            Move-Item -LiteralPath $resolvedStagedRoot -Destination $resolvedCurrentRoot
            $script:StageRootCreated = $false
            $stagedMovedToFinal = $true
            if (-not (Test-SkinRoot -Root $resolvedCurrentRoot)) {
                throw "Replacement root failed post-move skin-root validation: $resolvedCurrentRoot"
            }
            $script:FixedRootInstalled = $true
            Write-Log ("Installed staged latest root at fixed path: {0}" -f $resolvedCurrentRoot)
        }
        catch {
            $replaceFailure = $_.Exception.Message
            Write-Log ("Fixed-root replacement failed after rollback root was created: {0}" -f $replaceFailure) 'ERROR'
            try {
                if ($stagedMovedToFinal -and (Test-Path -LiteralPath $resolvedCurrentRoot)) {
                    Restore-InstalledFixedRootBestEffort -FinalRoot $resolvedCurrentRoot -RollbackRoot $rollbackRoot -Reason 'fixed-root replacement failure' | Out-Null
                }
                else {
                    Restore-FixedRootBestEffort -FinalRoot $resolvedCurrentRoot -RollbackRoot $rollbackRoot
                    $script:FixedRootReplacementStarted = $false
                }
            }
            catch {
                throw ("Fixed-root replacement failed and automatic restore also failed. replacement_error={0}; restore_error={1}" -f $replaceFailure, $_.Exception.Message)
            }

            throw ("Fixed-root replacement failed; restored the previous fixed root. {0}" -f $replaceFailure)
        }
    }
    catch {
        throw
    }

    return $rollbackRoot
}

function Test-ScriptSupportsParameter {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    $content = Read-TextSmart -Path $ScriptPath
    return ($content -match ('(?i)\$' + [regex]::Escape($ParameterName) + '\b'))
}

function Convert-OutputToResultPairs {
    param([object[]]$Output)

    $pairs = @{}
    foreach ($line in $Output) {
        $textLine = [string]$line
        if ($textLine -match '^(DMEL_[A-Z]+)=(.*)$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }

    return $pairs
}

function Get-UpdateRuntimePowerShellPath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($candidate)
    }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [System.IO.Path]::GetFullPath($command.Source)
    }

    throw 'powershell.exe could not be located.'
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowNull()][string]$Value)

    $text = [string]$Value
    if ($text.Length -eq 0) {
        return '""'
    }
    if ($text.IndexOfAny([char[]]@(' ', "`t", "`r", "`n", '"')) -lt 0) {
        return $text
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $text.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-WindowsCommandLineArguments {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $quoted = foreach ($argument in $Arguments) {
        ConvertTo-WindowsCommandLineArgument -Value $argument
    }
    return ($quoted -join ' ')
}

function Start-DetachedRuntimeHostScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-UpdateRuntimePowerShellPath
    $startInfo.Arguments = Join-WindowsCommandLineArguments -Arguments $argumentList
    $startInfo.WorkingDirectory = [System.IO.Path]::GetTempPath()
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        throw "Detached runtime helper could not be started: $ScriptPath"
    }
    $process.Dispose()
}

function Invoke-HelperScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Write-Log ("Starting {0}: {1}" -f $Operation, $ScriptPath)
    $output = @(& (Get-UpdateRuntimePowerShellPath) -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $pairs = Convert-OutputToResultPairs -Output $output
    $status = [string]($pairs['DMEL_STATUS'])
    $message = [string]($pairs['DMEL_MESSAGE'])
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'ERROR'
        $detail = Convert-ResultPairValueToSingleLine -Value ($output | Out-String)
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = if ([string]::IsNullOrWhiteSpace($detail)) {
                ("{0} helper did not emit DMEL_STATUS." -f $Operation)
            }
            else {
                ("{0} helper did not emit DMEL_STATUS. output={1}" -f $Operation, $detail)
            }
        }
    }
    $status = $status.ToUpperInvariant()

    Write-Log ("{0} completed with status={1} exitCode={2}" -f $Operation, $status, $exitCode)
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        Write-Log ("{0} message: {1}" -f $Operation, $message)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]($pairs['DMEL_LOGPATH']))) {
        Write-Log ("{0} log: {1}" -f $Operation, [string]($pairs['DMEL_LOGPATH']))
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = [string]($pairs['DMEL_SOURCEPATH'])
        LogPath = [string]($pairs['DMEL_LOGPATH'])
        Output = ($output | Out-String)
    }
}

function Assert-HelperOk {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if ($Result.ExitCode -ne 0 -or -not [string]::Equals([string]$Result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
        $detail = if ([string]::IsNullOrWhiteSpace([string]$Result.Message)) { [string]$Result.Output } else { [string]$Result.Message }
        throw ("{0} failed: {1}" -f $Operation, (Convert-ResultPairValueToSingleLine -Value $detail))
    }
}

function Invoke-ImportValidation {
    param(
        [Parameter(Mandatory = $true)][string]$ImportScript,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs')
    if (Test-ScriptSupportsParameter -ScriptPath $ImportScript -ParameterName 'ValidateOnly') {
        $arguments += '-ValidateOnly'
    }
    else {
        throw 'ImportFromOldVersion.ps1 does not expose the required -ValidateOnly validation contract.'
    }

    $result = Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import validation'
    Assert-HelperOk -Result $result -Operation 'Legacy import validation'
}

function Invoke-RealImport {
    param(
        [Parameter(Mandatory = $true)][string]$ImportScript,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $arguments = @('-TargetRoot', $TargetRoot, '-SourceRoot', $SourceRoot, '-NonInteractive', '-EmitResultPairs')
    $script:ImportStarted = $true
    $result = Invoke-HelperScript -ScriptPath $ImportScript -Arguments $arguments -Operation 'legacy import'
    Assert-HelperOk -Result $result -Operation 'Legacy import'
}

function Invoke-VersionSwitch {
    param(
        [Parameter(Mandatory = $true)][string]$SwitchScript,
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SelectedRoot
    )

    $arguments = @('-CurrentTargetRoot', $CurrentRoot, '-SelectedTargetRoot', $SelectedRoot, '-EmitResultPairs')
    $result = Invoke-HelperScript -ScriptPath $SwitchScript -Arguments $arguments -Operation 'active version switch'
    Assert-HelperOk -Result $result -Operation 'Active version switch'
    $script:SwitchSucceeded = $true
}

function Resolve-SwitchScript {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$SelectedRoot
    )

    $currentScript = Get-BlockHudRuntimeToolPath -Root $CurrentRoot -RelativeToolPath 'SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $currentScript -PathType Leaf) {
        return $currentScript
    }

    $selectedScript = Get-BlockHudRuntimeToolPath -Root $SelectedRoot -RelativeToolPath 'SwitchActiveSkinVersion.ps1'
    if (Test-Path -LiteralPath $selectedScript -PathType Leaf) {
        return $selectedScript
    }

    throw 'SwitchActiveSkinVersion.ps1 was not found in the selected or current root.'
}

function Resolve-UpdateCleanupHelperPath {
    param([Parameter(Mandatory = $true)][ValidateSet('CleanupOldRoot.ps1', 'CleanupTempRoot.ps1')][string]$FileName)

    foreach ($root in @($script:ResolvedLatestRoot, $script:ResolvedCurrentRoot)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) {
            continue
        }

        $candidate = Get-BlockHudRuntimeToolPath `
            -Root ([string]$root) `
            -RelativeToolPath (Join-Path 'UpdateToLatestVersion' $FileName)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw "Packaged update cleanup helper was not found: $FileName"
}

function Invoke-DetachedOldRootCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$OldRoot,
        [Parameter(Mandatory = $true)][string]$SkinsRoot,
        [int]$CleanupTimeoutSeconds = 20,
        [int]$ResultTimeoutSeconds = 30
    )

    $resultRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestCleanup_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $resultRoot
    $runnerPath = Resolve-UpdateCleanupHelperPath -FileName 'CleanupOldRoot.ps1'
    $resultPath = Join-Path $resultRoot 'CleanupResult.json'

    Start-DetachedRuntimeHostScript -ScriptPath $runnerPath -Arguments @(
        '-OldRoot', $OldRoot,
        '-SkinsRoot', $SkinsRoot,
        '-ResultPath', $resultPath,
        '-CleanupTimeoutSeconds', [string]$CleanupTimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($ResultTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            return [PSCustomObject]@{
                Status = [string]$result.Status
                Message = [string]$result.Message
                ResultPath = $resultPath
            }
        }
        Start-Sleep -Milliseconds 250
    }

    return [PSCustomObject]@{
        Status = 'TIMEOUT'
        Message = "Old-root cleanup did not report a result within $ResultTimeoutSeconds seconds."
        ResultPath = $resultPath
    }
}

function Invoke-DetachedTempRootCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Reason,
        [int]$CleanupTimeoutSeconds = 20,
        [int]$ResultTimeoutSeconds = 30
    )

    $resolvedRoot = Resolve-FullPath -Path $Root
    $tempRoot = Resolve-FullPath -Path ([System.IO.Path]::GetTempPath())
    if (-not (Test-PathWithinRoot -Root $tempRoot -Path $resolvedRoot) -or
        [string]::Equals($resolvedRoot, $tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing detached cleanup outside TEMP for $($Reason): $resolvedRoot"
    }

    $resultRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestCleanup_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $resultRoot
    $runnerPath = Resolve-UpdateCleanupHelperPath -FileName 'CleanupTempRoot.ps1'
    $resultPath = Join-Path $resultRoot 'CleanupResult.json'

    Start-DetachedRuntimeHostScript -ScriptPath $runnerPath -Arguments @(
        '-Root', $resolvedRoot,
        '-TempRoot', $tempRoot,
        '-Reason', $Reason,
        '-ResultPath', $resultPath,
        '-CleanupTimeoutSeconds', [string]$CleanupTimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($ResultTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            return [PSCustomObject]@{
                Status = [string]$result.Status
                Message = [string]$result.Message
                ResultPath = $resultPath
            }
        }
        Start-Sleep -Milliseconds 250
    }

    return [PSCustomObject]@{
        Status = 'TIMEOUT'
        Message = "Temporary old-root cleanup did not report a result within $ResultTimeoutSeconds seconds."
        ResultPath = $resultPath
    }
}

function Invoke-UpdateToLatest {
    $resolvedCurrentRoot = Resolve-SkinRootCandidate -Candidate $CurrentTargetRoot
    if (-not $resolvedCurrentRoot) {
        throw 'CurrentTargetRoot is not a valid Block HUD install root.'
    }
    $script:ResolvedCurrentRoot = $resolvedCurrentRoot
    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedCurrentRoot
    Use-CanonicalHelperLogPath -Root $resolvedCurrentRoot -Prefix 'UpdateToLatestVersion'

    if ($ResetCurrentVersion) {
        if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
            throw 'ExpectedVersion is required when ResetCurrentVersion is used.'
        }
        [void](ConvertTo-StableSkinVersionTag -VersionText $ExpectedVersion -Context 'ExpectedVersion')
        if ([string]::IsNullOrWhiteSpace($ExpectedReleaseVariant) -or
            ($ExpectedReleaseVariant -notin @('Korea', 'Global'))) {
            throw 'ExpectedReleaseVariant must be explicitly set to Korea or Global when ResetCurrentVersion is used.'
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        [void](ConvertTo-StableSkinVersionTag -VersionText $ExpectedVersion -Context 'ExpectedVersion')
    }

    $resolvedPackagePath = Resolve-FullPath -Path $PackagePath
    if (-not (Test-Path -LiteralPath $resolvedPackagePath -PathType Leaf)) {
        throw 'PackagePath was not found.'
    }
    $packageExtension = [System.IO.Path]::GetExtension($resolvedPackagePath)
    if (-not [string]::Equals($packageExtension, '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'PackagePath must be a ZIP update package. RMSKIN installers are not supported by the updater.'
    }

    $skinsRoot = Get-RainmeterSkinsRoot -CurrentRoot $resolvedCurrentRoot
    if (-not (Test-Path -LiteralPath $skinsRoot -PathType Container)) {
        throw "Rainmeter skins root does not exist: $skinsRoot"
    }
    if (-not (Test-PathWithinRoot -Root $skinsRoot -Path $resolvedCurrentRoot) -or
        [string]::Equals($resolvedCurrentRoot, $skinsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "CurrentTargetRoot must be an installed skin root under Rainmeter SkinPath. current=$resolvedCurrentRoot skinPath=$skinsRoot"
    }

    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DMeloperLatestExtract_{0}_{1}" -f $script:LogStamp, ([guid]::NewGuid().ToString('N')))
    $script:ExtractRoot = (Resolve-FullPath -Path $extractRoot -AllowMissing)
    Assert-ZipPackageSafeToExtract -PackagePath $resolvedPackagePath -ExtractRoot $script:ExtractRoot
    Ensure-Directory -Path $extractRoot
    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $extractRoot -Force
    Assert-NoReparsePoints -Root $extractRoot -Context 'Extracted update package'
    $packageRoot = Resolve-PackageRoot -ExtractRoot $extractRoot

    $currentMetadata = Get-SkinMetadata -Root $resolvedCurrentRoot
    $packageMetadata = Get-SkinMetadata -Root $packageRoot
    $currentReleaseVariant = Get-SkinRootReleaseVariant -Root $resolvedCurrentRoot
    Assert-ExpectedReleaseVariant -ActualReleaseVariant $currentReleaseVariant -ExpectedReleaseVariant $ExpectedReleaseVariant -Context 'CurrentTargetRoot'
    $effectiveExpectedReleaseVariant = if ([string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        $currentReleaseVariant
    }
    else {
        Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ExpectedReleaseVariant -LanguageCode '' -AssetPattern ''
    }
    $packageReleaseVariant = Get-SkinRootReleaseVariant -Root $packageRoot
    Assert-ExpectedReleaseVariant -ActualReleaseVariant $packageReleaseVariant -ExpectedReleaseVariant $effectiveExpectedReleaseVariant -Context 'Package'
    $currentVersion = ConvertTo-SkinVersion -VersionText ([string]$currentMetadata.Version) -Context 'CurrentTargetRoot'
    $packageVersion = ConvertTo-SkinVersion -VersionText ([string]$packageMetadata.Version) -Context 'Package'
    if ($ResetCurrentVersion) {
        $expectedStableTag = ConvertTo-StableSkinVersionTag -VersionText $ExpectedVersion -Context 'ExpectedVersion'
        $currentStableTag = ConvertTo-StableSkinVersionTag -VersionText ([string]$currentMetadata.Version) -Context 'CurrentTargetRoot'
        $packageStableTag = ConvertTo-StableSkinVersionTag -VersionText ([string]$packageMetadata.Version) -Context 'Package'
        if (-not [string]::Equals($currentStableTag, $expectedStableTag, [System.StringComparison]::Ordinal) -or
            -not [string]::Equals($packageStableTag, $expectedStableTag, [System.StringComparison]::Ordinal)) {
            throw ("Current-version reset requires current, expected, and package versions to match exactly. current={0} expected={1} package={2}" -f $currentStableTag, $expectedStableTag, $packageStableTag)
        }
    }
    else {
        if ($packageVersion -le $currentVersion) {
            throw "Package version must be newer than current target version. current=$($currentMetadata.Version) package=$($packageMetadata.Version)"
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
            $expectedStableTag = ConvertTo-StableSkinVersionTag -VersionText $ExpectedVersion -Context 'ExpectedVersion'
            $packageStableTag = ConvertTo-StableSkinVersionTag -VersionText ([string]$packageMetadata.Version) -Context 'Package'
            if (-not [string]::Equals($packageStableTag, $expectedStableTag, [System.StringComparison]::Ordinal)) {
                throw "Package version did not match ExpectedVersion. expected=$expectedStableTag package=$packageStableTag"
            }
        }
    }

    $identityName = Get-PackageIdentityName -PackageRoot $packageRoot -PackageMetadata $packageMetadata -ExtractRoot $extractRoot
    $fixedRootName = "DMeloper's Block HUD"
    if (-not [string]::Equals($identityName, $fixedRootName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package identity must resolve to the fixed installed root '$fixedRootName', but was '$identityName'."
    }
    $latestRoot = if ($ResetCurrentVersion) {
        $resolvedCurrentRoot
    }
    else {
        Resolve-LatestDestinationRoot -SkinsRoot $skinsRoot -IdentityName $identityName
    }
    $script:ResolvedLatestRoot = $latestRoot

    Write-Log ("CurrentTargetRoot: {0}" -f $resolvedCurrentRoot)
    Write-Log ("PackagePath: {0}" -f $resolvedPackagePath)
    Write-Log ("PackageRoot: {0}" -f $packageRoot)
    Write-Log ("CurrentVersion: {0}" -f [string]$currentMetadata.Version)
    Write-Log ("LatestVersion: {0}" -f [string]$packageMetadata.Version)
    Write-Log ("CurrentReleaseVariant: {0}" -f $currentReleaseVariant)
    Write-Log ("PackageReleaseVariant: {0}" -f $packageReleaseVariant)
    Write-Log ("ExpectedReleaseVariant: {0}" -f $effectiveExpectedReleaseVariant)
    Write-Log ("PackageIdentity: {0}" -f $identityName)
    Write-Log ("DestinationRoot: {0}" -f $latestRoot)
    if ($ResetCurrentVersion) {
        Write-Log 'DestinationRoot policy: exact CurrentTargetRoot replacement for explicit same-version reset; current data import is disabled.'
    }
    else {
        Write-Log 'DestinationRoot policy: fixed package identity root; version-suffixed side-by-side update roots are disabled.'
    }

    if (-not (Test-PathWithinRoot -Root $skinsRoot -Path $latestRoot)) {
        throw "Destination root is outside the Rainmeter skins root: $latestRoot"
    }

    if (Test-Path -LiteralPath $latestRoot) {
        if (-not [string]::Equals((Resolve-FullPath -Path $latestRoot), $resolvedCurrentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Destination install root already exists and is not the current root: $latestRoot"
        }
    }

    if (-not $ResetCurrentVersion) {
        $packageImportScript = Get-BlockHudRuntimeToolPath -Root $packageRoot -RelativeToolPath 'ImportFromOldVersion.ps1'
        if (-not (Test-Path -LiteralPath $packageImportScript -PathType Leaf)) {
            throw 'Package is missing Utilities\tools\ImportFromOldVersion.ps1.'
        }
        Invoke-ImportValidation -ImportScript $packageImportScript -TargetRoot $packageRoot -SourceRoot $resolvedCurrentRoot
    }
    else {
        Write-Log 'Current-version reset preflight intentionally skipped legacy import validation because no live data may be imported.'
    }

    if (Test-Path -LiteralPath $latestRoot) {
        Write-Log 'Fixed-root update path: destination resolves to the current active root; staging latest package before replacement.'

        $stageRoot = New-StagedLatestRoot -PackageRoot $packageRoot -IdentityName $identityName
        if (-not $ResetCurrentVersion) {
            $stageImportScript = Get-BlockHudRuntimeToolPath -Root $stageRoot -RelativeToolPath 'ImportFromOldVersion.ps1'
            if (-not (Test-Path -LiteralPath $stageImportScript -PathType Leaf)) {
                throw 'Staged latest root is missing Utilities\tools\ImportFromOldVersion.ps1.'
            }
            Invoke-RealImport -ImportScript $stageImportScript -TargetRoot $stageRoot -SourceRoot $resolvedCurrentRoot
        }
        else {
            $stagedMetadata = Get-SkinMetadata -Root $stageRoot
            $stagedStableTag = ConvertTo-StableSkinVersionTag -VersionText ([string]$stagedMetadata.Version) -Context 'Staged reset package'
            if (-not [string]::Equals($stagedStableTag, $expectedStableTag, [System.StringComparison]::Ordinal)) {
                throw "Staged reset package version changed unexpectedly. expected=$expectedStableTag actual=$stagedStableTag"
            }
            $stagedReleaseVariant = Get-SkinRootReleaseVariant -Root $stageRoot
            Assert-ExpectedReleaseVariant -ActualReleaseVariant $stagedReleaseVariant -ExpectedReleaseVariant $effectiveExpectedReleaseVariant -Context 'Staged reset package'
            Write-Log 'Current-version reset staged a pristine package without importing any current-root data.'

            $script:ResetRecoveryTransaction = New-ResetRecoveryTransaction `
                -CurrentRoot $resolvedCurrentRoot `
                -SkinsRoot $skinsRoot `
                -StageParentRoot $script:StageParentRoot `
                -ExtractRoot $script:ExtractRoot
            Start-ResetRecoveryGuard -Transaction $script:ResetRecoveryTransaction
        }

        Invoke-RetiredCurrentRootConfigCleanup -Root $resolvedCurrentRoot
        $replacementParameters = @{
            CurrentRoot = $resolvedCurrentRoot
            StagedRoot = $stageRoot
            SkinsRoot = $skinsRoot
        }
        if ($ResetCurrentVersion) {
            $replacementParameters['PreparedRollbackRoot'] = [string]$script:ResetRecoveryTransaction.RollbackRoot
        }
        $rollbackRoot = Invoke-FixedRootReplacement @replacementParameters
        if ($ResetCurrentVersion) {
            Set-ResetRecoveryPhase -Phase 'NewRootInstalled'
        }
        Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $resolvedCurrentRoot
        Set-ResultPairValue -Key 'DMEL_BACKUPPATH' -Value ''
        Use-CanonicalHelperLogPath -Root $resolvedCurrentRoot -Prefix 'UpdateToLatestVersion'

        try {
            if ($ResetCurrentVersion) {
                Set-ResetRecoveryPhase -Phase 'Activating'
            }
            Invoke-PostUpdateRefresh -Root $resolvedCurrentRoot
            if ($ResetCurrentVersion) {
                Set-ResetRecoveryPhase -Phase 'Activated'
            }
            $script:PostUpdateActivationSucceeded = $true
        }
        catch {
            $refreshFailure = $_.Exception.Message
            Write-Log ("Post-update refresh failed after fixed-root replacement: {0}" -f $refreshFailure) 'ERROR'
            try {
                Restore-InstalledFixedRootBestEffort -FinalRoot $resolvedCurrentRoot -RollbackRoot $rollbackRoot -Reason 'post-update refresh failure'
                if ($ResetCurrentVersion) {
                    try {
                        Set-ResetRecoveryPhase -Phase 'Restored'
                    }
                    catch {
                        Write-Log ("Restored the previous root, but could not acknowledge recovery in the journal: {0}" -f $_.Exception.Message) 'WARN'
                    }
                }
            }
            catch {
                throw ("Post-update refresh failed and automatic fixed-root restore also failed. refresh_error={0}; restore_error={1}" -f $refreshFailure, $_.Exception.Message)
            }

            throw ("Post-update refresh failed; restored the previous fixed root. {0}" -f $refreshFailure)
        }

        if ($ResetCurrentVersion) {
            # The manager-local helper set may be newer than the same-version package
            # that just replaced CurrentTargetRoot. Keep reset cleanup owned by this
            # already-loaded process and its recovery guard, not by package-local code.
            $cleanupResult = Remove-RootWithResult -Root $script:ReplacementRollbackParent -Reason 'successful current-version reset'
        }
        else {
            $cleanupResult = Invoke-DetachedTempRootCleanup -Root $rollbackRoot -Reason 'successful fixed-root update'
        }
        if ([string]::Equals([string]$cleanupResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
            if ($ResetCurrentVersion) {
                Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Reset the current skin to a pristine package of the same version and replaced the exact active install root.'
                try {
                    Set-ResetRecoveryPhase -Phase 'Committed'
                }
                catch {
                    Write-Log ("Current-version reset completed, but the recovery journal could not be finalized: {0}" -f $_.Exception.Message) 'WARN'
                    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
                    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Reset the current skin successfully, but temporary recovery metadata cleanup is still pending.'
                }
            }
            else {
                Remove-SafeUpdateTempRootBestEffort -Root $script:ReplacementRollbackParent -Reason 'fixed-root rollback parent'
                Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Updated to the latest version, imported data, and replaced the fixed install root.'
            }
        }
        else {
            Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
            if ($ResetCurrentVersion) {
                Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ("Reset the current skin and activated the pristine same-version package, but rollback-root cleanup is still pending: {0}" -f [string]$cleanupResult.Message)
                try {
                    Set-ResetRecoveryPhase -Phase 'CleanupPending'
                }
                catch {
                    Write-Log ("Could not hand pending rollback cleanup to the recovery guard: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            else {
                Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ("Updated to the latest version and replaced the fixed install root, but temporary rollback-root cleanup did not complete: {0}" -f [string]$cleanupResult.Message)
            }
        }

        return
    }

    if ($ResetCurrentVersion) {
        throw 'Current-version reset must replace the exact existing CurrentTargetRoot and cannot use a side-by-side destination.'
    }

    try {
        Copy-PackageToDestination -PackageRoot $packageRoot -DestinationRoot $latestRoot
        $script:LatestRootCreated = $true
        Use-CanonicalHelperLogPath -Root $latestRoot -Prefix 'UpdateToLatestVersion'

        $latestImportScript = Get-BlockHudRuntimeToolPath -Root $latestRoot -RelativeToolPath 'ImportFromOldVersion.ps1'
        if (-not (Test-Path -LiteralPath $latestImportScript -PathType Leaf)) {
            throw 'Installed latest root is missing Utilities\tools\ImportFromOldVersion.ps1.'
        }
        Invoke-RealImport -ImportScript $latestImportScript -TargetRoot $latestRoot -SourceRoot $resolvedCurrentRoot

        $switchScript = Resolve-SwitchScript -CurrentRoot $resolvedCurrentRoot -SelectedRoot $latestRoot
        Invoke-VersionSwitch -SwitchScript $switchScript -CurrentRoot $resolvedCurrentRoot -SelectedRoot $latestRoot
    }
    catch {
        $failureMessage = $_.Exception.Message
        if ($script:LatestRootCreated -and -not $script:SwitchSucceeded) {
            Remove-RootBestEffort -Root $latestRoot -Reason 'failed latest update'
        }
        throw $failureMessage
    }

    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $latestRoot
    try {
        Set-Location ([System.IO.Path]::GetTempPath())
    }
    catch {
    }

    try {
        $cleanupResult = Invoke-DetachedOldRootCleanup -OldRoot $resolvedCurrentRoot -SkinsRoot $skinsRoot
    }
    catch {
        $cleanupResult = [PSCustomObject]@{
            Status = 'ERROR'
            Message = $_.Exception.Message
            ResultPath = ''
        }
    }
    Write-Log ("Old-root cleanup result: {0} - {1}" -f [string]$cleanupResult.Status, [string]$cleanupResult.Message)
    if ([string]::Equals([string]$cleanupResult.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase)) {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Updated to the latest version, imported data, switched active configs, and deleted the old root.'
    }
    else {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ("Updated to the latest version and switched active configs, but old-root cleanup did not complete: {0}" -f [string]$cleanupResult.Message)
    }
}
