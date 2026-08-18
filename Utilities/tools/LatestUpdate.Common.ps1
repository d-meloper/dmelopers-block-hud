Set-StrictMode -Version 2.0

$script:LatestUpdateToolsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$script:LatestUpdateUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

$skinLayoutCommonPath = Join-Path $script:LatestUpdateToolsRoot 'SkinLayout.Common.ps1'
if ($null -eq (Get-Command -Name 'Test-BlockHudSkinRoot' -CommandType Function -ErrorAction SilentlyContinue)) {
    . $skinLayoutCommonPath
}
$releaseIdentityPath = Join-Path $script:LatestUpdateToolsRoot 'VersionManager.ReleaseIdentity.ps1'
if ($null -eq (Get-Command -Name 'Get-BlockHudFixedUpdateZipAssetName' -CommandType Function -ErrorAction SilentlyContinue)) {
    . $releaseIdentityPath
}

function Resolve-LatestUpdateTargetRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'TargetRoot is empty.'
    }
    foreach ($character in $Path.ToCharArray()) {
        if ([char]::IsControl($character)) {
            throw 'TargetRoot contains a control character.'
        }
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $resolved = if ([System.IO.Path]::IsPathRooted($expanded)) {
        [System.IO.Path]::GetFullPath($expanded)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $script:LatestUpdateToolsRoot $expanded))
    }
    $resolved = $resolved.TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $resolved -PathType Container) -or -not (Test-BlockHudSkinRoot -Root $resolved)) {
        throw "TargetRoot is not a valid Block HUD skin root: $resolved"
    }
    return $resolved
}

function Assert-LatestUpdateToken {
    param([Parameter(Mandatory = $true)][string]$LaunchToken)

    if ($LaunchToken -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw 'LaunchToken must contain 1-128 ASCII letters, digits, dots, underscores, or hyphens.'
    }
    return $LaunchToken
}

function Assert-LatestUpdateVersion {
    param([Parameter(Mandatory = $true)][string]$ExpectedVersion)

    $value = $ExpectedVersion.Trim()
    if ($value -notmatch '^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "ExpectedVersion is not a stable semantic version: $ExpectedVersion"
    }
    return ('v{0}.{1}.{2}' -f $matches[1], $matches[2], $matches[3])
}

function Assert-LatestUpdateVariantAndAsset {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseVariant,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    if ($ReleaseVariant -notin @('Korea', 'Global')) {
        throw "ReleaseVariant must be Korea or Global: $ReleaseVariant"
    }
    $expectedAssetName = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant $ReleaseVariant -LanguageCode ''
    if (-not [string]::Equals($AssetName, $expectedAssetName, [System.StringComparison]::Ordinal)) {
        throw "AssetName does not match ReleaseVariant. expected=$expectedAssetName actual=$AssetName"
    }
    return [PSCustomObject]@{
        ReleaseVariant = $ReleaseVariant
        AssetName = $expectedAssetName
    }
}

function Get-LatestUpdateDataRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path $Root '@Resources\Customs\Data')
}

function Get-LatestUpdateIntentPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Get-LatestUpdateDataRoot -Root $Root) 'LatestUpdateIntent.json')
}

function Get-LatestUpdateStatePath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Get-LatestUpdateDataRoot -Root $Root) 'LatestUpdateState.json')
}

function Get-LatestUpdateDecisionPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Get-LatestUpdateDataRoot -Root $Root) 'LatestUpdateDecision.json')
}

function Get-LatestUpdateStagingRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Get-LatestUpdateDataRoot -Root $Root) 'VersionManagerDownloads')
}

function Get-LatestUpdateStagingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    [void](Assert-LatestUpdateToken -LaunchToken $LaunchToken)
    return (Join-Path (Get-LatestUpdateStagingRoot -Root $Root) ("LatestUpdate_{0}.zip" -f $LaunchToken))
}

function Get-LatestUpdateNativeDecisionPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    [void](Assert-LatestUpdateToken -LaunchToken $LaunchToken)
    return (Join-Path (Get-LatestUpdateStagingRoot -Root $Root) ("LatestUpdateDecision_{0}.inc" -f $LaunchToken))
}

function Get-LatestUpdateLogPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path $Root "Logs\DMeloper's Block HUD Log.log")
}

function Get-LatestUpdateObjectProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$DefaultValue = $null
    )
    if ($null -eq $Object) { return $DefaultValue }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Assert-LatestUpdateInstallResultContract {
    param([Parameter(Mandatory = $true)]$Result)

    $status = ([string](Get-LatestUpdateObjectProperty -Object $Result -Name 'DMEL_STATUS' -DefaultValue '')).Trim().ToUpperInvariant()
    if ($status -notin @('OK', 'WARN', 'NOOP')) {
        return $status
    }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('DMEL_SOURCEPATH', 'DMEL_LOGPATH')) {
        $value = [string](Get-LatestUpdateObjectProperty -Object $Result -Name $key -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($value)) {
            [void]$missing.Add($key)
        }
    }
    if ($missing.Count -gt 0) {
        throw ('InstallVersionRelease.ps1 returned {0} without required result fields: {1}' -f $status, ($missing.ToArray() -join ', '))
    }

    return $status
}

function Read-LatestUpdateJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $lastError = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try {
            $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            try {
                $reader = New-Object System.IO.StreamReader($stream, $script:LatestUpdateUtf8NoBom, $true)
                try { $raw = $reader.ReadToEnd() }
                finally { $reader.Dispose(); $stream = $null }
            }
            finally { if ($null -ne $stream) { $stream.Dispose() } }
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
            return ($raw | ConvertFrom-Json)
        }
        catch [System.IO.IOException] { $lastError = $_ }
        catch [System.UnauthorizedAccessException] { $lastError = $_ }
        catch {
            $lastError = $_
            if ($attempt -ge 8) { throw }
        }
        if ($attempt -lt 8) { Start-Sleep -Milliseconds ([Math]::Min(240, 30 * $attempt)) }
    }
    if ($null -ne $lastError) { throw $lastError }
    return $null
}

function Write-LatestUpdateJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 8
    $temporaryPath = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($Path) + '.' + $PID + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = $temporaryPath + '.bak'
    [System.IO.File]::WriteAllText($temporaryPath, $json, $script:LatestUpdateUtf8NoBom)
    try {
        $lastError = $null
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            try {
                if (Test-Path -LiteralPath $Path -PathType Leaf) {
                    try { [System.IO.File]::Replace($temporaryPath, $Path, $backupPath, $true) }
                    catch [System.IO.FileNotFoundException] { [System.IO.File]::Move($temporaryPath, $Path) }
                }
                else { [System.IO.File]::Move($temporaryPath, $Path) }
                return
            }
            catch [System.IO.IOException] { $lastError = $_ }
            catch [System.UnauthorizedAccessException] { $lastError = $_ }
            if ($attempt -lt 10) { Start-Sleep -Milliseconds ([Math]::Min(300, 30 * $attempt)) }
        }
        if ($null -ne $lastError) { throw $lastError }
    }
    finally {
        foreach ($candidate in @($temporaryPath, $backupPath)) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Assert-LatestUpdateSha256 {
    param([Parameter(Mandatory = $true)][string]$ExpectedPackageSha256)

    $normalized = $ExpectedPackageSha256.Trim().ToUpperInvariant()
    if ($normalized -notmatch '^[0-9A-F]{64}$') {
        throw 'ExpectedPackageSha256 must be a 64-character hexadecimal SHA-256 value.'
    }
    return $normalized
}

function New-LatestUpdateIntent {
    param(
        [Parameter(Mandatory = $true)][string]$LaunchToken,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseVariant,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageSha256,
        [Parameter(Mandatory = $true)][long]$StartedAtUnixSeconds
    )
    [void](Assert-LatestUpdateToken -LaunchToken $LaunchToken)
    $version = Assert-LatestUpdateVersion -ExpectedVersion $ExpectedVersion
    $identity = Assert-LatestUpdateVariantAndAsset -ReleaseVariant $ReleaseVariant -AssetName $AssetName
    $sha256 = Assert-LatestUpdateSha256 -ExpectedPackageSha256 $ExpectedPackageSha256
    if ($StartedAtUnixSeconds -le 0) { throw 'StartedAtUnixSeconds must be a positive integer.' }
    return [ordered]@{
        SchemaVersion = 2
        LaunchToken = $LaunchToken
        ExpectedVersion = $version
        ReleaseVariant = [string]$identity.ReleaseVariant
        AssetName = [string]$identity.AssetName
        ExpectedPackageSha256 = $sha256
        StartedAtUnixSeconds = [long]$StartedAtUnixSeconds
        CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Assert-LatestUpdateIntent {
    param(
        [Parameter(Mandatory = $true)]$Intent,
        [Parameter(Mandatory = $true)][string]$ExpectedLaunchToken
    )
    if ([int](Get-LatestUpdateObjectProperty -Object $Intent -Name 'SchemaVersion' -DefaultValue 0) -ne 2) {
        throw 'Latest update intent SchemaVersion must be 2.'
    }
    $token = [string](Get-LatestUpdateObjectProperty -Object $Intent -Name 'LaunchToken' -DefaultValue '')
    [void](Assert-LatestUpdateToken -LaunchToken $token)
    if (-not [string]::Equals($token, $ExpectedLaunchToken, [System.StringComparison]::Ordinal)) {
        throw 'Latest update intent token does not match the requested token.'
    }
    $version = Assert-LatestUpdateVersion -ExpectedVersion ([string](Get-LatestUpdateObjectProperty -Object $Intent -Name 'ExpectedVersion' -DefaultValue ''))
    $identity = Assert-LatestUpdateVariantAndAsset `
        -ReleaseVariant ([string](Get-LatestUpdateObjectProperty -Object $Intent -Name 'ReleaseVariant' -DefaultValue '')) `
        -AssetName ([string](Get-LatestUpdateObjectProperty -Object $Intent -Name 'AssetName' -DefaultValue ''))
    $sha256 = Assert-LatestUpdateSha256 -ExpectedPackageSha256 ([string](Get-LatestUpdateObjectProperty -Object $Intent -Name 'ExpectedPackageSha256' -DefaultValue ''))
    $started = [long](Get-LatestUpdateObjectProperty -Object $Intent -Name 'StartedAtUnixSeconds' -DefaultValue 0)
    if ($started -le 0) { throw 'Latest update intent has an invalid StartedAtUnixSeconds value.' }
    return [PSCustomObject]@{
        SchemaVersion = 2
        LaunchToken = $token
        ExpectedVersion = $version
        ReleaseVariant = [string]$identity.ReleaseVariant
        AssetName = [string]$identity.AssetName
        ExpectedPackageSha256 = $sha256
        StartedAtUnixSeconds = $started
    }
}

function Save-LatestUpdateState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Intent,
        [ValidateSet('downloading', 'staging', 'installing', 'warning', 'switching', 'success', 'canceled', 'error')]
        [string]$Status,
        [int]$SessionPid = $PID,
        [AllowNull()][string]$Message = '',
        [AllowNull()][string]$LogPath = '',
        [AllowNull()][string]$ErrorCode = '',
        [AllowNull()][string]$Compatibility = '',
        [int]$RepairCount = 0,
        [AllowNull()][string]$RepairSummary = '',
        [AllowNull()][string]$RepairPlanId = ''
    )
    $sessionStartedAtUtcTicks = 0L
    try {
        $sessionProcess = Get-Process -Id $SessionPid -ErrorAction Stop
        if ([string]::Equals([string]$sessionProcess.ProcessName, 'powershell', [System.StringComparison]::OrdinalIgnoreCase)) {
            $sessionStartedAtUtcTicks = [long]$sessionProcess.StartTime.ToUniversalTime().Ticks
        }
    }
    catch { }
    $payload = [ordered]@{
        SchemaVersion = 2
        LaunchToken = [string]$Intent.LaunchToken
        Status = $Status
        StartedAtUnixSeconds = [long]$Intent.StartedAtUnixSeconds
        UpdatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        SessionPid = [int]$SessionPid
        SessionStartedAtUtcTicks = $sessionStartedAtUtcTicks
        ExpectedVersion = [string]$Intent.ExpectedVersion
        ReleaseVariant = [string]$Intent.ReleaseVariant
        AssetName = [string]$Intent.AssetName
        ExpectedPackageSha256 = [string]$Intent.ExpectedPackageSha256
        ErrorCode = [string]$ErrorCode
        Message = [string]$Message
        LogPath = [string]$LogPath
        Compatibility = [string]$Compatibility
        RepairCount = [int]$RepairCount
        RepairSummary = [string]$RepairSummary
        RepairPlanId = [string]$RepairPlanId
    }
    Write-LatestUpdateJson -Path (Get-LatestUpdateStatePath -Root $Root) -Value $payload
    return [PSCustomObject]$payload
}

function Test-LatestUpdateProcessLive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $false }
    return [string]::Equals([string]$process.ProcessName, 'powershell', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-LatestUpdateProcessIdentity {
    param(
        [int]$ProcessId,
        [long]$StartedAtUtcTicks
    )
    if ($ProcessId -le 0 -or $StartedAtUtcTicks -le 0) { return $false }
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        if (-not [string]::Equals([string]$process.ProcessName, 'powershell', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return [long]$process.StartTime.ToUniversalTime().Ticks -eq $StartedAtUtcTicks
    }
    catch { return $false }
}

function Assert-LatestUpdateZipFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Downloaded package was not found: $resolved" }
    if (-not [string]::Equals([System.IO.Path]::GetExtension($resolved), '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Downloaded package must be a ZIP file.'
    }
    $file = Get-Item -LiteralPath $resolved -Force
    if ($file.Length -lt 4) { throw 'Downloaded ZIP is empty or truncated.' }
    $stream = [System.IO.File]::Open($resolved, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))
    try {
        $signature = New-Object byte[] 4
        if ($stream.Read($signature, 0, 4) -ne 4 -or $signature[0] -ne 0x50 -or $signature[1] -ne 0x4B -or $signature[2] -ne 0x03 -or $signature[3] -ne 0x04) {
            throw 'Downloaded package does not have a valid ZIP signature.'
        }
    }
    finally { $stream.Dispose() }
    return $resolved
}

function Copy-LatestUpdatePackageToStaging {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageSha256
    )
    $expectedSha256 = Assert-LatestUpdateSha256 -ExpectedPackageSha256 $ExpectedPackageSha256
    $resolvedSource = Assert-LatestUpdateZipFile -Path $SourcePath
    $stagingRoot = Get-LatestUpdateStagingRoot -Root $Root
    if (-not (Test-Path -LiteralPath $stagingRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    }
    $destination = Get-LatestUpdateStagingPath -Root $Root -LaunchToken $LaunchToken
    $temporary = $destination + '.' + $PID + '.' + [guid]::NewGuid().ToString('N') + '.tmp.zip'
    try {
        [System.IO.File]::Copy($resolvedSource, $temporary, $true)
        [void](Assert-LatestUpdateZipFile -Path $temporary)
        $actualSha256 = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToUpperInvariant()
        if (-not [string]::Equals($actualSha256, $expectedSha256, [System.StringComparison]::Ordinal)) {
            throw "Downloaded update SHA-256 did not match the published checksum. expected=$expectedSha256 actual=$actualSha256"
        }
        if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
        [System.IO.File]::Move($temporary, $destination)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    [void](Assert-LatestUpdateZipFile -Path $destination)
    return $destination
}

function Remove-LatestUpdateStagingPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    $path = Get-LatestUpdateStagingPath -Root $Root -LaunchToken $LaunchToken
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Remove-LatestUpdateDecisionForToken {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    $path = Get-LatestUpdateDecisionPath -Root $Root
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    try {
        $decision = Read-LatestUpdateJson -Path $path
        $token = [string](Get-LatestUpdateObjectProperty -Object $decision -Name 'LaunchToken' -DefaultValue '')
        if ([string]::Equals($token, $LaunchToken, [System.StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function Remove-LatestUpdateDecisionFile {
    param([Parameter(Mandatory = $true)][string]$Root)
    $path = Get-LatestUpdateDecisionPath -Root $Root
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Read-LatestUpdateNativeDecision {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    $path = Get-LatestUpdateNativeDecisionPath -Root $Root -LaunchToken $LaunchToken
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    try {
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        }
        elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        }
        else { $text = [System.Text.Encoding]::UTF8.GetString($bytes) }
        $inVariables = $false
        foreach ($line in ($text -split "`r?`n")) {
            $trimmed = ([string]$line).Trim()
            if ($trimmed -match '^\[(.+)\]$') {
                $inVariables = [string]::Equals($matches[1], 'Variables', [System.StringComparison]::OrdinalIgnoreCase)
                continue
            }
            if ($inVariables -and $trimmed -match '^Decision\s*=\s*(continue|cancel)\s*$') {
                return $matches[1].ToLowerInvariant()
            }
        }
    }
    catch { }
    return ''
}

function Initialize-LatestUpdateNativeDecision {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    $path = Get-LatestUpdateNativeDecisionPath -Root $Root -LaunchToken $LaunchToken
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $temporaryPath = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($path) + '.' + $PID + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = $temporaryPath + '.bak'
    $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
    $lastError = $null
    try {
        [System.IO.File]::WriteAllText($temporaryPath, "[Variables]`r`nDecision=`r`n", $encoding)
        [byte[]]$writtenBytes = [System.IO.File]::ReadAllBytes($temporaryPath)
        if ($writtenBytes.Length -lt 2 -or $writtenBytes[0] -ne 0xFF -or $writtenBytes[1] -ne 0xFE) {
            throw 'Latest-update native decision file was not encoded as UTF-16 LE BOM.'
        }

        for ($attempt = 1; $attempt -le 10; $attempt++) {
            try {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    [System.IO.File]::Replace($temporaryPath, $path, $backupPath, $true)
                }
                else {
                    [System.IO.File]::Move($temporaryPath, $path)
                }
                $lastError = $null
                break
            }
            catch [System.IO.IOException] { $lastError = $_ }
            catch [System.UnauthorizedAccessException] { $lastError = $_ }
            if ($attempt -lt 10) { Start-Sleep -Milliseconds ([Math]::Min(300, 30 * $attempt)) }
        }
        if ($null -ne $lastError) { throw $lastError }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Latest-update native decision file was not created.'
        }
        [byte[]]$finalBytes = [System.IO.File]::ReadAllBytes($path)
        if ($finalBytes.Length -lt 2 -or $finalBytes[0] -ne 0xFF -or $finalBytes[1] -ne 0xFE) {
            throw 'Latest-update native decision file lost its UTF-16 LE BOM.'
        }
        $finalText = [System.Text.Encoding]::Unicode.GetString($finalBytes, 2, $finalBytes.Length - 2)
        if (-not [string]::Equals($finalText, "[Variables]`r`nDecision=`r`n", [System.StringComparison]::Ordinal)) {
            throw 'Latest-update native decision file was not reset to the canonical empty template.'
        }
        return $path
    }
    finally {
        foreach ($candidate in @($temporaryPath, $backupPath)) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Publish-LatestUpdateCompatibilityWarning {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Intent,
        [Parameter(Mandatory = $true)][string]$LaunchToken,
        [int]$SessionPid = $PID,
        [AllowNull()][string]$Message = '',
        [AllowNull()][string]$LogPath = '',
        [Parameter(Mandatory = $true)][ValidateSet('REPAIRABLE')][string]$Compatibility,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$RepairCount,
        [AllowNull()][string]$RepairSummary = '',
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$RepairPlanId
    )
    [void](Assert-LatestUpdateToken -LaunchToken $LaunchToken)
    $intentToken = [string]$Intent.LaunchToken
    if (-not [string]::Equals($intentToken, $LaunchToken, [System.StringComparison]::Ordinal)) {
        throw 'Latest-update warning token does not match the validated intent.'
    }
    [void](Initialize-LatestUpdateNativeDecision -Root $Root -LaunchToken $LaunchToken)
    return (Save-LatestUpdateState `
        -Root $Root `
        -Intent $Intent `
        -Status 'warning' `
        -SessionPid $SessionPid `
        -Message $Message `
        -LogPath $LogPath `
        -Compatibility $Compatibility `
        -RepairCount $RepairCount `
        -RepairSummary $RepairSummary `
        -RepairPlanId $RepairPlanId)
}

function Remove-LatestUpdateNativeDecisionForToken {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LaunchToken
    )
    $path = Get-LatestUpdateNativeDecisionPath -Root $Root -LaunchToken $LaunchToken
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Write-LatestUpdateLog {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][string]$Message = ''
    )
    try {
        $path = Get-LatestUpdateLogPath -Root $Root
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $lines = @('<LatestUpdate>', ('timeUtc={0}' -f (Get-Date).ToUniversalTime().ToString('o')), ('stage={0}' -f $Stage), ('pid={0}' -f $PID), ('message={0}' -f ([string]$Message).Replace("`r", ' ').Replace("`n", ' ')), '</LatestUpdate>', '')
        [System.IO.File]::AppendAllText($path, [string]::Join("`r`n", $lines), $script:LatestUpdateUtf8NoBom)
    }
    catch { }
}
