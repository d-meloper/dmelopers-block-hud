# ImportFromOldVersion helpers - Jukebox user data and optional progress state.

# Dot-sourced by the public entrypoint. Keep public CLI and DMEL_* contracts in the entrypoint file.

$script:ImportProgressLastWriteUtc = [DateTime]::MinValue
$script:ImportProgressLastCompletedBytes = -1L
$script:ImportProgressLastStage = ''

function Test-ImportProgressDetailThreshold {
    param([Parameter(Mandatory = $true)][int64]$TotalBytes)

    return ($TotalBytes -ge 67108864)
}

function Test-ImportProgressToken {
    param([AllowNull()][string]$Token)

    return (-not [string]::IsNullOrWhiteSpace($Token) -and $Token -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
}

function Initialize-ImportProgress {
    param(
        [AllowNull()][string]$OwnerRoot,
        [AllowNull()][string]$Token,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $script:ImportProgressPath = ''
    if ([string]::IsNullOrWhiteSpace($OwnerRoot) -and [string]::IsNullOrWhiteSpace($Token)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($OwnerRoot) -or -not (Test-ImportProgressToken -Token $Token)) {
        throw 'ProgressOwnerRoot and a safe ProgressToken must be supplied together.'
    }

    $resolvedOwner = Resolve-FullPath -Path $OwnerRoot
    $sourceIdentity = Resolve-FullPath -Path $SourceRoot
    $targetIdentity = Resolve-FullPath -Path $TargetRoot
    if (-not $resolvedOwner.Equals($sourceIdentity, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $resolvedOwner.Equals($targetIdentity, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'ProgressOwnerRoot must resolve exactly to SourceRoot or TargetRoot.'
    }

    $dataDirectory = Join-RootPath -Root $resolvedOwner -RelativePath '@Resources\Customs\Data'
    if (-not (Test-Path -LiteralPath $dataDirectory -PathType Container)) {
        throw 'ProgressOwnerRoot does not contain the required @Resources\Customs\Data directory.'
    }

    $script:ImportProgressPath = Join-Path $dataDirectory ("VersionImportProgress_{0}.json" -f $Token)
    $script:ImportProgressLastWriteUtc = [DateTime]::MinValue
    $script:ImportProgressLastCompletedBytes = -1L
    $script:ImportProgressLastStage = ''
}

function Write-ImportProgress {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('backup', 'audio-copy', 'jukebox-state', 'validating')][string]$Stage,
        [Parameter(Mandatory = $true)][int64]$CompletedBytes,
        [Parameter(Mandatory = $true)][int64]$TotalBytes,
        [Parameter(Mandatory = $true)][int]$CompletedFiles,
        [Parameter(Mandatory = $true)][int]$TotalFiles,
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($script:ImportProgressPath)) {
        return
    }

    $safeTotalBytes = [Math]::Max(0L, $TotalBytes)
    $safeCompletedBytes = [Math]::Min([Math]::Max(0L, $CompletedBytes), $safeTotalBytes)
    $safeTotalFiles = [Math]::Max(0, $TotalFiles)
    $safeCompletedFiles = [Math]::Min([Math]::Max(0, $CompletedFiles), $safeTotalFiles)
    $now = [DateTime]::UtcNow
    if (-not $Force -and $Stage -eq $script:ImportProgressLastStage -and
        $safeCompletedBytes -eq $script:ImportProgressLastCompletedBytes -and
        ($now - $script:ImportProgressLastWriteUtc).TotalMilliseconds -lt 250) {
        return
    }
    if (-not $Force -and ($now - $script:ImportProgressLastWriteUtc).TotalMilliseconds -lt 250) {
        return
    }

    try {
        $payload = [ordered]@{
            SchemaVersion = 1
            Token = [string]$ProgressToken
            Stage = $Stage
            CompletedBytes = $safeCompletedBytes
            TotalBytes = $safeTotalBytes
            CompletedFiles = $safeCompletedFiles
            TotalFiles = $safeTotalFiles
            DetailVisible = [bool]$script:ImportProgressDetailVisible
            UpdatedAtUtc = $now.ToString('o')
        }
        $json = ($payload | ConvertTo-Json -Depth 3) + "`n"
        $temporaryPath = Join-Path (Split-Path -Parent $script:ImportProgressPath) ('.VersionImportProgress_{0}.{1}.tmp' -f $ProgressToken, ([guid]::NewGuid().ToString('N')))
        try {
            [System.IO.File]::WriteAllText($temporaryPath, $json, $script:Utf8NoBom)
            if ([System.IO.File]::Exists($script:ImportProgressPath)) {
                $backupPath = $temporaryPath + '.bak'
                try {
                    [System.IO.File]::Replace($temporaryPath, $script:ImportProgressPath, $backupPath, $true)
                }
                finally {
                    if ([System.IO.File]::Exists($backupPath)) {
                        [System.IO.File]::Delete($backupPath)
                    }
                }
            }
            else {
                [System.IO.File]::Move($temporaryPath, $script:ImportProgressPath)
            }
        }
        finally {
            if ([System.IO.File]::Exists($temporaryPath)) {
                [System.IO.File]::Delete($temporaryPath)
            }
        }

        $script:ImportProgressLastWriteUtc = $now
        $script:ImportProgressLastCompletedBytes = $safeCompletedBytes
        $script:ImportProgressLastStage = $Stage
    }
    catch {
        Write-Log ("Import progress state could not be written and the import will continue: {0}" -f $_.Exception.Message) 'WARN'
        $script:ImportProgressPath = ''
    }
}

function Remove-ImportProgressBestEffort {
    if ([string]::IsNullOrWhiteSpace($script:ImportProgressPath)) {
        return
    }

    $path = $script:ImportProgressPath
    $script:ImportProgressPath = ''
    try {
        if ([System.IO.File]::Exists($path)) {
            [System.IO.File]::Delete($path)
        }
    }
    catch {
        try {
            Write-Log ("Import progress state could not be removed: {0} ({1})" -f $path, $_.Exception.Message) 'WARN'
        }
        catch {
        }
    }
}

function Get-RollbackBackupWorkload {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot
    )

    $directories = New-Object System.Collections.Generic.List[string]
    $entries = New-Object System.Collections.Generic.List[object]
    [int64]$totalBytes = 0
    foreach ($relativePath in (Get-TemporaryRollbackScopeRelativePaths -Root $TargetRoot)) {
        $sourcePath = Join-RootPath -Root $TargetRoot -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }
        $destinationPath = Join-Path $RollbackRoot $relativePath
        $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
        if (-not $sourceItem.PSIsContainer) {
            if (-not [string]::IsNullOrWhiteSpace($script:ImportProgressPath) -and
                $sourceItem.FullName.Equals($script:ImportProgressPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $entries.Add([pscustomobject]@{ SourcePath = $sourceItem.FullName; TargetPath = $destinationPath; Length = [int64]$sourceItem.Length })
            $totalBytes += [int64]$sourceItem.Length
            continue
        }

        $directories.Add($destinationPath)
        $sourceBase = $sourceItem.FullName.TrimEnd('\', '/') + '\'
        foreach ($child in @(Get-ChildItem -LiteralPath $sourceItem.FullName -Force -Recurse -ErrorAction Stop)) {
            $relativeChild = $child.FullName.Substring($sourceBase.Length)
            $childDestination = Join-Path $destinationPath $relativeChild
            if ($child.PSIsContainer) {
                $directories.Add($childDestination)
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($script:ImportProgressPath) -and
                $child.FullName.Equals($script:ImportProgressPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if ($child.Name -like '.VersionImportProgress_*.*.tmp*') {
                continue
            }
            $entries.Add([pscustomobject]@{ SourcePath = $child.FullName; TargetPath = $childDestination; Length = [int64]$child.Length })
            $totalBytes += [int64]$child.Length
        }
    }

    return [pscustomobject]@{
        Directories = $directories.ToArray()
        Entries = $entries.ToArray()
        TotalBytes = $totalBytes
        TotalFiles = $entries.Count
    }
}

function Copy-TargetStateToTemporaryRollbackWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$RollbackRoot
    )

    $workload = Get-RollbackBackupWorkload -TargetRoot $TargetRoot -RollbackRoot $RollbackRoot
    foreach ($directory in @($workload.Directories | Sort-Object Length)) {
        Ensure-Directory -Path $directory
    }
    [int64]$completedBytes = 0
    [int]$completedFiles = 0
    Write-ImportProgress -Stage 'backup' -CompletedBytes 0 -TotalBytes ([int64]$workload.TotalBytes) -CompletedFiles 0 -TotalFiles ([int]$workload.TotalFiles) -Force
    foreach ($entry in @($workload.Entries)) {
        Ensure-Directory -Path (Split-Path -Parent $entry.TargetPath)
        $sourceStream = $null
        $targetStream = $null
        try {
            $sourceStream = New-Object System.IO.FileStream($entry.SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $targetStream = New-Object System.IO.FileStream($entry.TargetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $buffer = New-Object byte[] (1024 * 1024)
            [int64]$fileBytes = 0
            while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $targetStream.Write($buffer, 0, $read)
                $fileBytes += $read
                Write-ImportProgress -Stage 'backup' -CompletedBytes ($completedBytes + $fileBytes) -TotalBytes ([int64]$workload.TotalBytes) -CompletedFiles $completedFiles -TotalFiles ([int]$workload.TotalFiles)
            }
            $targetStream.Flush($true)
        }
        finally {
            if ($null -ne $targetStream) { $targetStream.Dispose() }
            if ($null -ne $sourceStream) { $sourceStream.Dispose() }
        }
        $completedBytes += [int64]$entry.Length
        $completedFiles++
        Write-ImportProgress -Stage 'backup' -CompletedBytes $completedBytes -TotalBytes ([int64]$workload.TotalBytes) -CompletedFiles $completedFiles -TotalFiles ([int]$workload.TotalFiles) -Force
    }
    Write-ImportProgress -Stage 'backup' -CompletedBytes ([int64]$workload.TotalBytes) -TotalBytes ([int64]$workload.TotalBytes) -CompletedFiles ([int]$workload.TotalFiles) -TotalFiles ([int]$workload.TotalFiles) -Force
}

function Get-TopLevelRegularFilesStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }

    $rootItem = Get-Item -LiteralPath $Directory -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        $reason = ''
        if (-not (Test-NonRedirectingReparsePoint -Item $rootItem -Reason ([ref]$reason))) {
            throw "Refusing migration because $Context is an unsafe reparse point ($reason): $Directory"
        }
        Write-Log "Allowed $Context root as $reason`: $Directory"
    }

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($item in @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $reason = ''
            if (-not (Test-NonRedirectingReparsePoint -Item $item -Reason ([ref]$reason))) {
                throw "Refusing migration because $Context contains an unsafe reparse point ($reason): $($item.FullName)"
            }
            Write-Log "Allowed $Context item as $reason`: $($item.FullName)"
        }
        if (-not $item.PSIsContainer) {
            $files.Add([System.IO.FileInfo]$item)
        }
    }
    return $files.ToArray()
}

function New-JukeboxFileMap {
    param([System.IO.FileInfo[]]$Files)

    $map = New-CaseInsensitiveHashtable
    foreach ($file in @($Files)) {
        if ($map.ContainsKey($file.Name)) {
            throw "Jukebox audio directory contains names that collide case-insensitively: $($file.Name)"
        }
        $map[$file.Name] = $file
    }
    return $map
}

function Get-JukeboxAudioMigrationWorkload {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $targetJukeboxEntrypoint = Join-RootPath -Root $TargetRoot -RelativePath 'ExtraContent\Jukebox\Jukebox.ini'
    $sourceDirectory = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Audios\Jukebox Disc'
    $targetDirectory = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Audios\Jukebox Disc'
    if (-not (Test-Path -LiteralPath $targetJukeboxEntrypoint -PathType Leaf)) {
        return [pscustomobject]@{
            SourceDirectory = $sourceDirectory
            TargetDirectory = $targetDirectory
            Entries = @()
            TotalBytes = 0L
            TotalFiles = 0
        }
    }
    $sourceFiles = @()
    if (Test-SkippedSourcePath -Path $sourceDirectory) {
        Write-Log "Skipped source Jukebox audio workload marked unreadable during preflight: $sourceDirectory" 'WARN'
    }
    else {
        $sourceFiles = @(Get-TopLevelRegularFilesStrict -Directory $sourceDirectory -Context 'source Jukebox audio directory' | Where-Object {
            -not (Test-SkippedSourcePath -Path $_.FullName)
        })
    }
    $targetFiles = @(Get-TopLevelRegularFilesStrict -Directory $targetDirectory -Context 'target Jukebox audio directory')
    $targetMap = New-JukeboxFileMap -Files $targetFiles
    $entries = New-Object System.Collections.Generic.List[object]
    [int64]$totalBytes = 0
    foreach ($sourceFile in @($sourceFiles | Sort-Object Name)) {
        $targetFile = if ($targetMap.ContainsKey($sourceFile.Name)) { [System.IO.FileInfo]$targetMap[$sourceFile.Name] } else { $null }
        if ($null -ne $targetFile -and $sourceFile.Length -eq $targetFile.Length -and
            (Get-Sha256HashString -Path $sourceFile.FullName) -eq (Get-Sha256HashString -Path $targetFile.FullName)) {
            continue
        }

        $entries.Add([pscustomobject]@{
            Name = [string]$sourceFile.Name
            SourcePath = [string]$sourceFile.FullName
            Length = [int64]$sourceFile.Length
            LastWriteTimeUtcTicks = [int64]$sourceFile.LastWriteTimeUtc.Ticks
        })
        $totalBytes += [int64]$sourceFile.Length
    }

    return [pscustomobject]@{
        SourceDirectory = $sourceDirectory
        TargetDirectory = $targetDirectory
        Entries = $entries.ToArray()
        TotalBytes = $totalBytes
        TotalFiles = $entries.Count
    }
}

function Copy-JukeboxFileAtomic {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][int64]$BaseCompletedBytes,
        [Parameter(Mandatory = $true)][int]$CompletedFiles,
        [Parameter(Mandatory = $true)]$Workload
    )

    Assert-SafeTargetPath -Path $TargetPath
    $targetDirectory = Split-Path -Parent $TargetPath
    Ensure-Directory -Path $targetDirectory
    $temporaryPath = Join-Path $targetDirectory ('.{0}.{1}.import.tmp' -f ([System.IO.Path]::GetFileName($TargetPath)), ([guid]::NewGuid().ToString('N')))
    $replaceBackupPath = $temporaryPath + '.bak'
    [int64]$copiedBytes = 0
    $sourceStream = $null
    $targetStream = $null
    $sha = $null
    try {
        $sourceStream = New-Object System.IO.FileStream($Entry.SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        if ([int64]$sourceStream.Length -ne [int64]$Entry.Length) {
            throw "Source Jukebox file changed before copy: $($Entry.SourcePath)"
        }
        $targetStream = New-Object System.IO.FileStream($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $buffer = New-Object byte[] (1024 * 1024)
        while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $targetStream.Write($buffer, 0, $read)
            [void]$sha.TransformBlock($buffer, 0, $read, $null, 0)
            $copiedBytes += $read
            Write-ImportProgress -Stage 'audio-copy' -CompletedBytes ($BaseCompletedBytes + $copiedBytes) -TotalBytes ([int64]$Workload.TotalBytes) -CompletedFiles $CompletedFiles -TotalFiles ([int]$Workload.TotalFiles)
        }
        [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $copyHash = (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
        $targetStream.Flush($true)
        $targetStream.Dispose()
        $targetStream = $null
        $sourceStream.Dispose()
        $sourceStream = $null

        $currentSource = Get-Item -LiteralPath $Entry.SourcePath -Force -ErrorAction Stop
        if ([int64]$currentSource.Length -ne [int64]$Entry.Length -or
            [int64]$currentSource.LastWriteTimeUtc.Ticks -ne [int64]$Entry.LastWriteTimeUtcTicks -or
            (Get-Sha256HashString -Path $Entry.SourcePath) -ne $copyHash) {
            throw "Source Jukebox file changed during copy: $($Entry.SourcePath)"
        }
        if ((Get-Sha256HashString -Path $temporaryPath) -ne $copyHash) {
            throw "Copied Jukebox file failed hash verification: $($Entry.Name)"
        }

        if ([System.IO.File]::Exists($TargetPath)) {
            [System.IO.File]::Replace($temporaryPath, $TargetPath, $replaceBackupPath, $true)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $TargetPath)
        }
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $targetStream) { $targetStream.Dispose() }
        if ($null -ne $sourceStream) { $sourceStream.Dispose() }
        try { if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) } } catch { }
        try { if ([System.IO.File]::Exists($replaceBackupPath)) { [System.IO.File]::Delete($replaceBackupPath) } } catch { }
    }
}

function Merge-JukeboxAudioFiles {
    param([Parameter(Mandatory = $true)]$Workload)

    if (@($Workload.Entries).Count -eq 0) {
        Write-ImportProgress -Stage 'audio-copy' -CompletedBytes 0 -TotalBytes 0 -CompletedFiles 0 -TotalFiles 0 -Force
        Write-Log 'No Jukebox files required migration.'
        return
    }

    Ensure-Directory -Path $Workload.TargetDirectory
    [int64]$completedBytes = 0
    [int]$completedFiles = 0
    Write-ImportProgress -Stage 'audio-copy' -CompletedBytes 0 -TotalBytes ([int64]$Workload.TotalBytes) -CompletedFiles 0 -TotalFiles ([int]$Workload.TotalFiles) -Force
    foreach ($entry in @($Workload.Entries)) {
        $targetPath = Join-Path $Workload.TargetDirectory $entry.Name
        Copy-JukeboxFileAtomic -Entry $entry -TargetPath $targetPath -BaseCompletedBytes $completedBytes -CompletedFiles $completedFiles -Workload $Workload
        $completedBytes += [int64]$entry.Length
        $completedFiles++
        Write-ImportProgress -Stage 'audio-copy' -CompletedBytes $completedBytes -TotalBytes ([int64]$Workload.TotalBytes) -CompletedFiles $completedFiles -TotalFiles ([int]$Workload.TotalFiles) -Force
        Write-Log ("Migrated Jukebox file with source precedence: {0}" -f $entry.Name)
    }
}

function Test-JukeboxLeafFileName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq '.' -or $Name -eq '..' -or [System.IO.Path]::IsPathRooted($Name)) {
        return $false
    }
    if ($Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $Name.IndexOfAny([char[]]@('/', '\')) -ge 0) {
        return $false
    }
    return ([System.IO.Path]::GetFileName($Name) -ceq $Name)
}

function Read-JukeboxSlotOrder {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        $payload = (Read-TextSmart -Path $Path) | ConvertFrom-Json -ErrorAction Stop
        if ([int]$payload.Version -ne 1) {
            throw 'Unsupported Jukebox slot schema.'
        }
        $seenSlots = New-CaseInsensitiveHashtable
        $seenNames = New-CaseInsensitiveHashtable
        $entries = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($payload.Assignments)) {
            $slot = 0
            if (-not [int]::TryParse(([string]$entry.Slot), [ref]$slot) -or $slot -lt 1) {
                throw 'Invalid Jukebox slot index.'
            }
            $name = [string]$entry.Name
            if (-not (Test-JukeboxLeafFileName -Name $name) -or $seenSlots.ContainsKey([string]$slot) -or $seenNames.ContainsKey($name)) {
                throw 'Invalid or duplicate Jukebox slot assignment.'
            }
            $seenSlots[[string]$slot] = $true
            $seenNames[$name] = $true
            $entries.Add([pscustomobject]@{ Slot = $slot; Name = $name })
        }
        return @($entries.ToArray() | Sort-Object Slot, Name)
    }
    catch {
        Write-Log ("Jukebox slot state was invalid and will be regenerated from files: {0} ({1})" -f $Path, $_.Exception.Message) 'WARN'
        return $null
    }
}

function Write-JsonAtomicUtf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    Assert-SafeTargetPath -Path $Path
    Ensure-Directory -Path (Split-Path -Parent $Path)
    $temporaryPath = $Path + ('.{0}.{1}.tmp' -f $PID, ([guid]::NewGuid().ToString('N')))
    $backupPath = $temporaryPath + '.bak'
    try {
        [System.IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 6) + "`n"), $script:Utf8NoBom)
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temporaryPath, $Path, $backupPath, $true)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $Path)
        }
    }
    finally {
        try { if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) } } catch { }
        try { if ([System.IO.File]::Exists($backupPath)) { [System.IO.File]::Delete($backupPath) } } catch { }
    }
}

function Merge-JukeboxSlotState {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$TargetAudioDirectory
    )

    $targetStatePath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\JukeboxDiscSlots.json'
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $targetStatePath) -PathType Container)) {
        Write-Log 'Skipped Jukebox slot migration because the target data contract is unavailable.'
        return
    }
    $sourceStatePath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\JukeboxDiscSlots.json'
    $sourceOrder = Read-JukeboxSlotOrder -Path $sourceStatePath
    $targetFiles = @(Get-TopLevelRegularFilesStrict -Directory $TargetAudioDirectory -Context 'target Jukebox audio directory')
    $filesByName = New-JukeboxFileMap -Files $targetFiles
    $used = New-CaseInsensitiveHashtable
    $orderedNames = New-Object System.Collections.Generic.List[string]
    if ($null -ne $sourceOrder) {
        foreach ($assignment in @($sourceOrder)) {
            if ($filesByName.ContainsKey($assignment.Name) -and -not $used.ContainsKey($assignment.Name)) {
                $used[$assignment.Name] = $true
                $orderedNames.Add([string]$filesByName[$assignment.Name].Name)
            }
        }
    }
    foreach ($file in @($targetFiles | Where-Object { -not $used.ContainsKey($_.Name) } | Sort-Object @{ Expression = 'Name'; Descending = $true })) {
        $used[$file.Name] = $true
        $orderedNames.Add([string]$file.Name)
    }

    $assignments = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $orderedNames.Count; $index++) {
        $assignments.Add([ordered]@{ Slot = ($index + 1); Name = $orderedNames[$index] })
    }
    Write-JsonAtomicUtf8 -Path $targetStatePath -Value ([ordered]@{
        Version = 1
        UpdatedAt = [DateTime]::UtcNow.ToString('o')
        Assignments = $assignments.ToArray()
    })
}

function Normalize-JukeboxDurableValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value,
        [AllowNull()][string]$Fallback
    )

    $text = ([string]$Value).Trim()
    switch ($Key) {
        'JukeboxDisplayMode' { if ($text -in @('main', 'minimized')) { return $text }; return $Fallback }
        'JukeboxPlaybackRepeatMode' { if ($text -in @('all', 'one', 'off')) { return $text }; return $Fallback }
        'JukeboxPlaybackShuffle' { if ($text -eq '1') { return '1' }; if ($text -eq '0') { return '0' }; return $Fallback }
        'JukeboxDiscSlotOptionsVisible' { if ($text -eq '1') { return '1' }; if ($text -eq '0') { return '0' }; return $Fallback }
        'JukeboxMainFormY' {
            $number = 0
            if ([int]::TryParse($text, [ref]$number)) { return [string]$number }
            return $Fallback
        }
        'JukeboxDiscSlotCurrentPage' {
            $number = 0
            if ([int]::TryParse($text, [ref]$number) -and $number -ge 1) { return [string]$number }
            return $Fallback
        }
        'JukeboxPlaybackVolume' {
            $number = 0
            if ([int]::TryParse($text, [ref]$number)) { return [string][Math]::Min(100, [Math]::Max(0, $number)) }
            return $Fallback
        }
    }
    return $Fallback
}

function Merge-JukeboxPlaybackState {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\JukeboxPlaybackState.inc'
    $targetPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\JukeboxPlaybackState.inc'
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        Write-Log 'Skipped Jukebox playback-state migration because the target state contract is unavailable.'
        return
    }

    $sourceVariables = Read-VariablesFile -Path $sourcePath
    $targetVariables = Read-VariablesFile -Path $targetPath
    foreach ($key in @(
        'JukeboxPlaybackVolume',
        'JukeboxPlaybackRepeatMode',
        'JukeboxPlaybackShuffle',
        'JukeboxDisplayMode',
        'JukeboxMainFormY',
        'JukeboxDiscSlotCurrentPage',
        'JukeboxDiscSlotOptionsVisible'
    )) {
        if ($targetVariables.Contains($key) -and $sourceVariables.Contains($key)) {
            Set-MapValue -Map $targetVariables -Key $key -Value (Normalize-JukeboxDurableValue -Key $key -Value $sourceVariables[$key] -Fallback $targetVariables[$key])
        }
    }
    foreach ($entry in @(
        @{ Key = 'JukeboxPlaybackSelectedActive'; Value = '0' },
        @{ Key = 'JukeboxPlaybackSelectedSlotIndex'; Value = '0' },
        @{ Key = 'JukeboxPlaybackSelectedName'; Value = '' },
        @{ Key = 'JukeboxPlaybackSelectedPath'; Value = '' }
    )) {
        if ($targetVariables.Contains($entry.Key)) {
            Set-MapValue -Map $targetVariables -Key $entry.Key -Value $entry.Value
        }
    }

    Write-Utf16Text -Path $targetPath -Content (ConvertTo-VariablesContent -Variables $targetVariables)
}

function Assert-JukeboxUserDataIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)]$Workload
    )

    foreach ($entry in @($Workload.Entries)) {
        $targetPath = Join-Path $Workload.TargetDirectory $entry.Name
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf) -or
            (Get-Sha256HashString -Path $entry.SourcePath) -ne (Get-Sha256HashString -Path $targetPath)) {
            throw "Jukebox post-import audio verification failed: $($entry.Name)"
        }
    }

    $slotPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\JukeboxDiscSlots.json'
    $slotOrder = Read-JukeboxSlotOrder -Path $slotPath
    $targetFiles = @(Get-TopLevelRegularFilesStrict -Directory $Workload.TargetDirectory -Context 'target Jukebox audio directory')
    if ($null -eq $slotOrder -and $targetFiles.Count -gt 0) {
        throw 'Jukebox post-import slot verification failed because the target slot state is invalid.'
    }
    $slotNames = New-CaseInsensitiveHashtable
    $expectedSlot = 1
    foreach ($entry in @($slotOrder)) {
        if ([int]$entry.Slot -ne $expectedSlot -or $slotNames.ContainsKey($entry.Name)) {
            throw 'Jukebox post-import slot verification found a gap or duplicate assignment.'
        }
        $slotNames[$entry.Name] = $true
        $expectedSlot++
    }
    foreach ($file in $targetFiles) {
        if (-not $slotNames.ContainsKey($file.Name)) {
            throw "Jukebox post-import slot verification omitted a file: $($file.Name)"
        }
    }
    if ($slotNames.Count -ne $targetFiles.Count) {
        throw 'Jukebox post-import slot verification retained a missing file reference.'
    }

    $playbackPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\JukeboxPlaybackState.inc'
    if (Test-Path -LiteralPath $playbackPath -PathType Leaf) {
        $sourcePlaybackPath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\JukeboxPlaybackState.inc'
        $sourcePlayback = Read-VariablesFile -Path $sourcePlaybackPath
        $playback = Read-VariablesFile -Path $playbackPath
        foreach ($key in @(
            'JukeboxPlaybackVolume',
            'JukeboxPlaybackRepeatMode',
            'JukeboxPlaybackShuffle',
            'JukeboxDisplayMode',
            'JukeboxMainFormY',
            'JukeboxDiscSlotCurrentPage',
            'JukeboxDiscSlotOptionsVisible'
        )) {
            if ($playback.Contains($key) -and $sourcePlayback.Contains($key)) {
                $expected = Normalize-JukeboxDurableValue -Key $key -Value $sourcePlayback[$key] -Fallback '__invalid__'
                if ($expected -ne '__invalid__' -and [string]$playback[$key] -cne $expected) {
                    throw "Jukebox post-import durable setting verification failed for $key."
                }
            }
        }
        foreach ($entry in @(
            @{ Key = 'JukeboxPlaybackSelectedActive'; Value = '0' },
            @{ Key = 'JukeboxPlaybackSelectedSlotIndex'; Value = '0' },
            @{ Key = 'JukeboxPlaybackSelectedName'; Value = '' },
            @{ Key = 'JukeboxPlaybackSelectedPath'; Value = '' }
        )) {
            if ($playback.Contains($entry.Key) -and [string]$playback[$entry.Key] -cne [string]$entry.Value) {
                throw "Jukebox post-import playback verification failed for $($entry.Key)."
            }
        }
    }

    Write-Log 'Jukebox audio, slot, and playback state passed post-import integrity validation.'
}

function Read-ProgramActionLabelEntries {
    param([Parameter(Mandatory = $true)][string]$Path)

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Read-NonEmptyLines -Path $Path)) {
        $parts = [string]$line -split "`t", 2
        if ($parts.Length -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            continue
        }
        $entries.Add([pscustomobject]@{ Action = [string]$parts[0]; Label = ([string]$parts[1]).Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ') })
    }
    return $entries.ToArray()
}

function Merge-ProgramActionLabels {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\ProgramActionLabels.txt'
    $targetPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\ProgramActionLabels.txt'
    $sourceEntries = @(Read-ProgramActionLabelEntries -Path $sourcePath)
    if ($sourceEntries.Count -eq 0) {
        Write-Log 'No source program action labels found to merge.'
        return
    }

    $used = New-CaseInsensitiveHashtable
    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $sourceEntries) {
        if (-not $used.ContainsKey($entry.Action)) {
            $used[$entry.Action] = $true
            $merged.Add($entry)
        }
    }
    foreach ($entry in (Read-ProgramActionLabelEntries -Path $targetPath)) {
        if (-not $used.ContainsKey($entry.Action)) {
            $used[$entry.Action] = $true
            $merged.Add($entry)
        }
    }

    $lines = @($merged | ForEach-Object { $_.Action + "`t" + $_.Label })
    Write-Utf8Text -Path $targetPath -Content (($lines -join "`r`n") + "`r`n")

    $postEntries = @(Read-ProgramActionLabelEntries -Path $targetPath)
    $postMap = New-CaseInsensitiveHashtable
    foreach ($entry in $postEntries) { $postMap[$entry.Action] = $entry.Label }
    foreach ($entry in $sourceEntries) {
        if (-not $postMap.ContainsKey($entry.Action) -or [string]$postMap[$entry.Action] -cne [string]$entry.Label) {
            throw "Program action label post-import verification failed for action: $($entry.Action)"
        }
    }
}

function Assert-MinecraftSkinHistoryIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $sourcePath = Join-RootPath -Root $SourceRoot -RelativePath '@Resources\Customs\Data\MinecraftSkinHistory.txt'
    $targetPath = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data\MinecraftSkinHistory.txt'
    $targetValues = New-CaseInsensitiveHashtable
    foreach ($line in (Read-NonEmptyLines -Path $targetPath)) { $targetValues[$line.Trim()] = $true }
    foreach ($line in (Read-NonEmptyLines -Path $sourcePath)) {
        if (-not $targetValues.ContainsKey($line.Trim())) {
            throw "Minecraft skin history post-import verification failed for entry: $line"
        }
    }
}

function Merge-JukeboxUserData {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)]$Workload
    )

    # A target without the Jukebox runtime contract must keep the old safe behavior.
    $targetJukeboxEntrypoint = Join-RootPath -Root $TargetRoot -RelativePath 'ExtraContent\Jukebox\Jukebox.ini'
    if (-not (Test-Path -LiteralPath $targetJukeboxEntrypoint -PathType Leaf)) {
        Write-Log 'Skipped Jukebox user-data migration because the target package does not support the Jukebox contract.'
        return
    }

    Merge-JukeboxAudioFiles -Workload $Workload
    Write-ImportProgress -Stage 'jukebox-state' -CompletedBytes 0 -TotalBytes 2 -CompletedFiles 0 -TotalFiles 2 -Force
    Merge-JukeboxSlotState -SourceRoot $SourceRoot -TargetRoot $TargetRoot -TargetAudioDirectory $Workload.TargetDirectory
    Write-ImportProgress -Stage 'jukebox-state' -CompletedBytes 1 -TotalBytes 2 -CompletedFiles 1 -TotalFiles 2 -Force
    Merge-JukeboxPlaybackState -SourceRoot $SourceRoot -TargetRoot $TargetRoot
    Write-ImportProgress -Stage 'jukebox-state' -CompletedBytes 2 -TotalBytes 2 -CompletedFiles 2 -TotalFiles 2 -Force
    Assert-JukeboxUserDataIntegrity -SourceRoot $SourceRoot -TargetRoot $TargetRoot -Workload $Workload
}
