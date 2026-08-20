$script:MousePluginUpdateSchemaVersion = 1
$script:MousePluginUpdateVersion = '3.2.0.1'
$script:MousePluginUpdateLaunchRequestFileName = 'MousePluginUpdateLaunchRequested.inc'
$script:MousePluginUpdateRestartReadyFileName = 'MousePluginUpdateRestartReady.inc'
$script:MousePluginUpdateCancellationFileName = 'MousePluginUpdateCancelled.inc'
$script:MousePluginUpdatePatchedHashes = @{
    '32bit' = '757CEF59FAEE1DE1305A02DE49B77A5F0E70327B893A0A567D56FBB3637C584B'
    '64bit' = '76D2EB3362CCA4A5482559C02AA780142CAA4FCC12C1DC968610CBFEE6E64D5E'
}
$script:MousePluginUpdateKnownVulnerableHashes = @(
    'DAE960180BCFD84CB04A862E57A54F65E57F733A1033B6BABF940BE7B3536AB6',
    '79713B410F63A1EFA5C927AFEB825E46600AE8146F4208739CDE7C91B3FB2C9D'
)

function Get-MousePluginSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MousePluginUpdaterPayloadManifest {
    param([Parameter(Mandatory = $true)][string]$Root)

    $payloadRoot = Join-RootPath -Root $Root -RelativePath '@Resources\UpdaterPayload\Mouse'
    $manifestPath = Join-Path $payloadRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    $manifest = [System.IO.File]::ReadAllText($manifestPath, $script:StrictUtf8) | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne $script:MousePluginUpdateSchemaVersion -or
        -not [string]::Equals([string]$manifest.component, 'Mouse.dll', [System.StringComparison]::Ordinal) -or
        -not [string]::Equals([string]$manifest.version, $script:MousePluginUpdateVersion, [System.StringComparison]::Ordinal)) {
        throw 'Mouse updater payload manifest identity is invalid.'
    }

    $entries = @($manifest.architectures)
    if ($entries.Count -ne 2) {
        throw 'Mouse updater payload manifest must contain exactly two architecture entries.'
    }

    $validated = @{}
    foreach ($entry in $entries) {
        $architecture = [string]$entry.architecture
        if (-not $script:MousePluginUpdatePatchedHashes.ContainsKey($architecture) -or $validated.ContainsKey($architecture)) {
            throw "Mouse updater payload contains an unexpected or duplicate architecture: $architecture"
        }
        $expectedRelativePath = $architecture + '/Mouse.dll'
        if (-not [string]::Equals([string]$entry.relativePath, $expectedRelativePath, [System.StringComparison]::Ordinal)) {
            throw "Mouse updater payload path is invalid for ${architecture}: $([string]$entry.relativePath)"
        }
        $expectedHash = [string]$script:MousePluginUpdatePatchedHashes[$architecture]
        if (-not [string]::Equals([string]$entry.sha256, $expectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Mouse updater payload manifest hash is invalid for $architecture."
        }
        $payloadPath = Join-Path $payloadRoot ($expectedRelativePath.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
            throw "Mouse updater payload is missing: $expectedRelativePath"
        }
        if (-not [string]::Equals((Get-MousePluginSha256 -Path $payloadPath), $expectedHash, [System.StringComparison]::Ordinal)) {
            throw "Mouse updater payload SHA-256 mismatch: $expectedRelativePath"
        }
        $validated[$architecture] = [PSCustomObject]@{
            Architecture = $architecture
            Path = $payloadPath
            RelativePath = '@Resources\UpdaterPayload\Mouse\' + $expectedRelativePath.Replace('/', '\')
            Sha256 = $expectedHash
        }
    }

    return [PSCustomObject]@{
        Root = $payloadRoot
        ManifestPath = $manifestPath
        Architectures = $validated
    }
}

function Get-RunningRainmeterProcessForMouseUpdate {
    $running = @(Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue | Where-Object {
        try {
            -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and
                [string]::Equals([System.IO.Path]::GetFileName([string]$_.Path), 'Rainmeter.exe', [System.StringComparison]::OrdinalIgnoreCase)
        }
        catch { $false }
    })
    if ($running.Count -ne 1) {
        throw "Mouse plugin update requires exactly one running Rainmeter process. detected=$($running.Count)"
    }
    return $running[0]
}

function Get-PortableExecutableArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        try {
            if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Executable is not a PE image: $Path" }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) { throw "Executable PE header is invalid: $Path" }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) { throw "Executable PE signature is invalid: $Path" }
            $machine = $reader.ReadUInt16()
        }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }

    if ($machine -eq 0x014C) { return '32bit' }
    if ($machine -eq 0x8664) { return '64bit' }
    throw ('Rainmeter executable architecture is unsupported: 0x{0:X4}' -f $machine)
}

function Get-RainmeterSettingsRootForMouseUpdate {
    param([Parameter(Mandatory = $true)][string]$RainmeterPath)

    $programRoot = Split-Path -Parent $RainmeterPath
    if (Test-Path -LiteralPath (Join-Path $programRoot 'Rainmeter.ini') -PathType Leaf) {
        return $programRoot
    }
    foreach ($candidate in @(
        (Join-Path $env:APPDATA 'Rainmeter'),
        (Join-Path $env:LOCALAPPDATA 'Rainmeter')
    )) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'Rainmeter.ini') -PathType Leaf) {
            return $candidate
        }
    }
    return (Join-Path $env:APPDATA 'Rainmeter')
}

function Test-MousePluginTargetWritable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            if ((Get-Item -LiteralPath $Path -Force).IsReadOnly) {
                return $false
            }
        }
        catch {
            return $false
        }
    }

    # A loaded Rainmeter plugin can legitimately reject an open-for-write probe
    # even when the caller owns the directory and can replace it after Rainmeter
    # exits. Probe the nearest existing parent instead, using a delete-on-close
    # file so ValidateOnly does not leave state behind.
    $probeRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    while (-not [string]::IsNullOrWhiteSpace($probeRoot) -and -not (Test-Path -LiteralPath $probeRoot -PathType Container)) {
        $parent = Split-Path -Parent $probeRoot
        if ([string]::Equals($parent, $probeRoot, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $probeRoot = $parent
    }
    if ([string]::IsNullOrWhiteSpace($probeRoot) -or -not (Test-Path -LiteralPath $probeRoot -PathType Container)) {
        return $false
    }

    $probePath = Join-Path $probeRoot ('.dmel-mouse-write-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        $stream = [System.IO.FileStream]::new(
            $probePath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None,
            1,
            [System.IO.FileOptions]::DeleteOnClose
        )
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $probePath -PathType Leaf) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-MousePluginInstalledVersion {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $raw = [string]([System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path).FileVersion)
        $match = [regex]::Match($raw, '^\s*(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?')
        if (-not $match.Success) { return $null }
        $revision = if ($match.Groups[4].Success) { [int]$match.Groups[4].Value } else { 0 }
        return New-Object System.Version([int]$match.Groups[1].Value, [int]$match.Groups[2].Value, [int]$match.Groups[3].Value, $revision)
    }
    catch { return $null }
}

function Get-MousePluginUpdatePlan {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $payload = Get-MousePluginUpdaterPayloadManifest -Root $TargetRoot
    if ($null -eq $payload) {
        return [PSCustomObject]@{ Action = 'None'; Reason = 'Updater payload is absent.' }
    }

    $rainmeter = Get-RunningRainmeterProcessForMouseUpdate
    $rainmeterPath = [System.IO.Path]::GetFullPath([string]$rainmeter.Path)
    $architecture = Get-PortableExecutableArchitecture -Path $rainmeterPath
    $programRoot = Split-Path -Parent $rainmeterPath
    $settingsRoot = Get-RainmeterSettingsRootForMouseUpdate -RainmeterPath $rainmeterPath
    $programPlugin = Join-Path $programRoot 'Plugins\Mouse.dll'
    $userPlugin = Join-Path $settingsRoot 'Plugins\Mouse.dll'
    $targetPath = if (Test-Path -LiteralPath $programPlugin -PathType Leaf) {
        $programPlugin
    }
    elseif (Test-Path -LiteralPath $userPlugin -PathType Leaf) {
        $userPlugin
    }
    else {
        $userPlugin
    }

    $action = 'Install'
    $reason = 'Mouse.dll is not installed in Rainmeter plugin precedence paths.'
    $installedHash = ''
    $installedVersion = $null
    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
        try { $installedHash = Get-MousePluginSha256 -Path $targetPath } catch { $installedHash = '' }
        $installedVersion = Get-MousePluginInstalledVersion -Path $targetPath
        if ([string]::Equals($installedHash, [string]$script:MousePluginUpdatePatchedHashes[$architecture], [System.StringComparison]::Ordinal)) {
            $action = 'Noop'
            $reason = 'Mouse.dll already matches the Block HUD safety patch.'
        }
        elseif ($script:MousePluginUpdateKnownVulnerableHashes -contains $installedHash) {
            $action = 'Replace'
            $reason = 'Mouse.dll matches a known vulnerable 3.2.0 binary.'
        }
        elseif ($null -ne $installedVersion -and $installedVersion -le [Version]'3.2.0.0') {
            $action = 'Replace'
            $reason = "Mouse.dll FileVersion is vulnerable or older: $installedVersion"
        }
        else {
            $action = 'Preserve'
            $versionLabel = if ($null -eq $installedVersion) { 'unreadable' } else { [string]$installedVersion }
            $reason = "Unknown Mouse.dll was preserved because its FileVersion is newer or unreadable: $versionLabel"
        }
    }

    if (($action -eq 'Install' -or $action -eq 'Replace') -and -not (Test-MousePluginTargetWritable -Path $targetPath)) {
        throw "Mouse.dll requires replacement in a protected Rainmeter program path. Update cannot continue without write access: $targetPath"
    }

    if ($action -eq 'Preserve') {
        Write-Log $reason 'WARN'
    }
    else {
        Write-Log ("Mouse plugin update decision: action={0}; architecture={1}; target={2}; reason={3}" -f $action, $architecture, $targetPath, $reason)
    }

    return [PSCustomObject]@{
        Action = $action
        Reason = $reason
        Architecture = $architecture
        TargetPath = [System.IO.Path]::GetFullPath($targetPath)
        PayloadPath = [string]$payload.Architectures[$architecture].Path
        PayloadRelativePath = [string]$payload.Architectures[$architecture].RelativePath
        ExpectedSha256 = [string]$payload.Architectures[$architecture].Sha256
        InstalledSha256 = $installedHash
        InstalledVersion = if ($null -eq $installedVersion) { '' } else { [string]$installedVersion }
        OriginalExists = Test-Path -LiteralPath $targetPath -PathType Leaf
        RainmeterPath = $rainmeterPath
        RainmeterProcessId = [int]$rainmeter.Id
        RainmeterStartTimeUtcTicks = [int64]$rainmeter.StartTime.ToUniversalTime().Ticks
        SettingsPath = (Join-Path $settingsRoot 'Rainmeter.ini')
    }
}

function Write-MousePluginUpdatePending {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][object]$Plan
    )

    if ($Plan.Action -ne 'Install' -and $Plan.Action -ne 'Replace') {
        return
    }

    $dataRoot = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\Customs\Data'
    if (-not (Test-Path -LiteralPath $dataRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
    }
    $pendingPath = Join-Path $dataRoot 'MousePluginUpdatePending.json'
    if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
        throw "A Mouse.dll update handoff is already pending and will not be overwritten: $pendingPath"
    }
    foreach ($markerName in @($script:MousePluginUpdateLaunchRequestFileName, $script:MousePluginUpdateRestartReadyFileName, $script:MousePluginUpdateCancellationFileName)) {
        $markerPath = Join-Path $dataRoot $markerName
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            Remove-Item -LiteralPath $markerPath -Force
        }
    }
    $token = [Guid]::NewGuid().ToString('N')
    $state = [ordered]@{
        SchemaVersion = $script:MousePluginUpdateSchemaVersion
        Token = $token
        Phase = 'Pending'
        Action = [string]$Plan.Action
        Architecture = [string]$Plan.Architecture
        TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
        PreviousRoot = [System.IO.Path]::GetFullPath($SourceRoot)
        RootConfig = Split-Path -Leaf $TargetRoot
        SettingsPath = [string]$Plan.SettingsPath
        RainmeterPath = [string]$Plan.RainmeterPath
        RainmeterProcessId = [int]$Plan.RainmeterProcessId
        RainmeterStartTimeUtcTicks = [int64]$Plan.RainmeterStartTimeUtcTicks
        PluginTargetPath = [string]$Plan.TargetPath
        PayloadRelativePath = [string]$Plan.PayloadRelativePath
        ExpectedSha256 = [string]$Plan.ExpectedSha256
        OriginalExists = [bool]$Plan.OriginalExists
        OriginalSha256 = [string]$Plan.InstalledSha256
        OriginalFileVersion = [string]$Plan.InstalledVersion
        CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $temporaryPath = $pendingPath + '.' + $PID + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, ($state | ConvertTo-Json -Depth 4), $script:Utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $pendingPath -Force
    Write-Log "Staged Mouse.dll update handoff token $token."
}

function Complete-MousePluginUpdateImportHandoff {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][object]$Plan
    )

    if ($Plan.Action -eq 'Install' -or $Plan.Action -eq 'Replace' -or $Plan.Action -eq 'None') {
        return
    }
    $payloadRoot = Join-RootPath -Root $TargetRoot -RelativePath '@Resources\UpdaterPayload\Mouse'
    if (Test-Path -LiteralPath $payloadRoot -PathType Container) {
        Remove-Item -LiteralPath $payloadRoot -Recurse -Force
    }
    $payloadParent = Split-Path -Parent $payloadRoot
    if ((Test-Path -LiteralPath $payloadParent -PathType Container) -and
        @(Get-ChildItem -LiteralPath $payloadParent -Force).Count -eq 0) {
        Remove-Item -LiteralPath $payloadParent -Force
    }
    Write-Log ("Removed unused Mouse.dll updater payload after action={0}." -f [string]$Plan.Action)
}
