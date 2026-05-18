function Get-VersionManagerJsonEncoding {
    return New-Object System.Text.UTF8Encoding($false)
}

function Ensure-VersionManagerDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-VersionManagerSettingsCachePath {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Join-Path $Root 'Settings\Cache.inc')
}

function ConvertTo-VersionManagerIniValue {
    param([AllowNull()]$Value)

    return ([string]$Value) -replace '[\r\n]+', ' '
}

function Set-VersionManagerSettingsCacheVariables {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Values
    )

    $path = Get-VersionManagerSettingsCachePath -Root $Root
    $parent = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-VersionManagerDirectory -Path $parent
    }

    $encoding = [System.Text.Encoding]::Unicode
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $content = [System.IO.File]::ReadAllText($path, $encoding)
    }
    else {
        $content = "[Variables]`r`n"
    }

    if ($content -notmatch '(?m)^\[Variables\]\s*$') {
        $content = "[Variables]`r`n" + $content
    }

    foreach ($entry in $Values.GetEnumerator()) {
        $name = [string]$entry.Key
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $value = ConvertTo-VersionManagerIniValue -Value $entry.Value
        $line = $name + '=' + $value
        $pattern = '(?m)^' + [regex]::Escape($name) + '=.*$'
        if ([regex]::IsMatch($content, $pattern)) {
            $content = [regex]::Replace(
                $content,
                $pattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $line },
                1
            )
        }
        else {
            $content = [regex]::Replace(
                $content,
                '(?m)^(\[Variables\]\s*\r?\n)',
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + $line + "`r`n" },
                1
            )
        }
    }

    [System.IO.File]::WriteAllText($path, $content, $encoding)
}

function Sync-VersionManagerUpdateCacheVariables {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Cache
    )

    Set-VersionManagerSettingsCacheVariables -Root $Root -Values ([ordered]@{
        VersionManagerCacheLatestVersion = [string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'LatestVersion' -DefaultValue '')
        VersionManagerCacheStatus = [string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'Status' -DefaultValue '')
        VersionManagerCacheErrorCode = [string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'ErrorCode' -DefaultValue '')
        VersionManagerCacheFailureHint = [string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'FailureHint' -DefaultValue '')
        VersionManagerCacheLastCheckedAtUtc = [string](Get-VersionManagerObjectPropertyValue -Object $Cache -Name 'LastCheckedAtUtc' -DefaultValue '')
    })
}

function Get-VersionManagerObjectPropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Set-VersionManagerObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    else {
        $property.Value = $Value
    }
}

function Test-VersionManagerMapLikeValue {
    param([AllowNull()]$Value)

    return ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject])
}

function ConvertTo-VersionManagerOrderedDictionary {
    param([AllowNull()]$InputObject)

    $dictionary = [ordered]@{}
    if ($null -eq $InputObject) {
        return $dictionary
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($entry in $InputObject.GetEnumerator()) {
            $dictionary[[string]$entry.Key] = $entry.Value
        }
        return $dictionary
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $dictionary[[string]$property.Name] = $property.Value
    }

    return $dictionary
}

function ConvertTo-VersionManagerPsObject {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if (-not (Test-VersionManagerMapLikeValue -Value $InputObject)) {
        return $InputObject
    }

    $result = [PSCustomObject]@{}
    $source = ConvertTo-VersionManagerOrderedDictionary -InputObject $InputObject
    foreach ($entry in $source.GetEnumerator()) {
        $value = $entry.Value
        if (Test-VersionManagerMapLikeValue -Value $value) {
            $value = ConvertTo-VersionManagerPsObject -InputObject $value
        }
        Set-VersionManagerObjectPropertyValue -Object $result -Name ([string]$entry.Key) -Value $value
    }

    return $result
}

function Merge-VersionManagerJsonValue {
    param(
        [AllowNull()]$BaseValue,
        [AllowNull()]$PatchValue
    )

    if ($null -eq $PatchValue) {
        return $null
    }

    if ((Test-VersionManagerMapLikeValue -Value $BaseValue) -and (Test-VersionManagerMapLikeValue -Value $PatchValue)) {
        $merged = ConvertTo-VersionManagerPsObject -InputObject $BaseValue
        foreach ($entry in (ConvertTo-VersionManagerOrderedDictionary -InputObject $PatchValue).GetEnumerator()) {
            $existingValue = Get-VersionManagerObjectPropertyValue -Object $merged -Name ([string]$entry.Key)
            $nextValue = Merge-VersionManagerJsonValue -BaseValue $existingValue -PatchValue $entry.Value
            Set-VersionManagerObjectPropertyValue -Object $merged -Name ([string]$entry.Key) -Value $nextValue
        }
        return $merged
    }

    if (Test-VersionManagerMapLikeValue -Value $PatchValue) {
        return (ConvertTo-VersionManagerPsObject -InputObject $PatchValue)
    }

    return $PatchValue
}

function Get-VersionManagerUpdateCacheDefaults {
    return [ordered]@{
        LastCheckedAtUtc = ''
        LatestVersion = ''
        ReleaseName = ''
        ReleaseUrl = ''
        AssetName = ''
        AssetUrl = ''
        AssetSize = 0
        PublishedAtUtc = ''
        ChangelogSummary = ''
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = ''
        Error = ''
        ErrorCode = ''
        FailureHint = ''
        ReleaseVariant = ''
        ActiveAssetPattern = ''
    }
}

function ConvertTo-VersionManagerUpdateCacheObject {
    param([AllowNull()]$Cache)

    $normalized = ConvertTo-VersionManagerPsObject -InputObject $Cache
    if ($null -eq $normalized) {
        $normalized = [PSCustomObject]@{}
    }

    foreach ($entry in (Get-VersionManagerUpdateCacheDefaults).GetEnumerator()) {
        if ($null -eq $normalized.PSObject.Properties[[string]$entry.Key]) {
            Set-VersionManagerObjectPropertyValue -Object $normalized -Name ([string]$entry.Key) -Value $entry.Value
        }
    }

    return $normalized
}

function Merge-VersionManagerUpdateCache {
    param(
        [AllowNull()]$BaseCache,
        [AllowNull()]$PatchCache
    )

    $merged = Merge-VersionManagerJsonValue -BaseValue (ConvertTo-VersionManagerUpdateCacheObject -Cache $BaseCache) -PatchValue $PatchCache
    return (ConvertTo-VersionManagerUpdateCacheObject -Cache $merged)
}

function Get-VersionManagerUpdateCachePath {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Join-Path $Root '@Resources\Customs\Data\VersionManagerUpdateCache.json')
}

function Get-VersionManagerUpdateCacheMutexName {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullPath.ToUpperInvariant())
        $hash = [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }

    return "Local\DMeloper.VersionManager.UpdateCache.$hash"
}

function Invoke-VersionManagerSynchronized {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [int]$TimeoutMilliseconds = 15000
    )

    $mutexName = Get-VersionManagerUpdateCacheMutexName -Path $Path
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $lockTaken = $false
    try {
        try {
            $lockTaken = $mutex.WaitOne($TimeoutMilliseconds)
        }
        catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }
        if (-not $lockTaken) {
            throw "Timed out waiting for update cache lock: $Path"
        }

        return (& $ScriptBlock)
    }
    finally {
        if ($lockTaken) {
            [void]$mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Read-VersionManagerJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $raw = [System.IO.File]::ReadAllText($Path, (Get-VersionManagerJsonEncoding))
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return ($raw | ConvertFrom-Json)
}

function Write-VersionManagerAtomicJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $resolvedPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-VersionManagerDirectory -Path $parent
    }

    $fileName = [System.IO.Path]::GetFileName($resolvedPath)
    $tempPath = Join-Path $parent ($fileName + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $parent ($fileName + '.' + [System.Guid]::NewGuid().ToString('N') + '.bak')
    $json = $Value | ConvertTo-Json -Depth 8
    $encoding = Get-VersionManagerJsonEncoding

    try {
        [System.IO.File]::WriteAllText($tempPath, $json, $encoding)
        if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $resolvedPath, $backupPath, $true)
        }
        else {
            [System.IO.File]::Move($tempPath, $resolvedPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-VersionManagerUpdateCache {
    param([Parameter(Mandatory = $true)][string]$Root)

    $path = Get-VersionManagerUpdateCachePath -Root $Root
    return (Invoke-VersionManagerSynchronized -Path $path -ScriptBlock {
        ConvertTo-VersionManagerUpdateCacheObject -Cache (Read-VersionManagerJsonFile -Path $path)
    })
}

function Save-VersionManagerUpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Cache
    )

    $path = Get-VersionManagerUpdateCachePath -Root $Root
    return (Invoke-VersionManagerSynchronized -Path $path -ScriptBlock {
        $normalized = ConvertTo-VersionManagerUpdateCacheObject -Cache $Cache
        Write-VersionManagerAtomicJsonFile -Path $path -Value $normalized
        Sync-VersionManagerUpdateCacheVariables -Root $Root -Cache $normalized
        return $normalized
    })
}

function Update-VersionManagerUpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Patch
    )

    $path = Get-VersionManagerUpdateCachePath -Root $Root
    return (Invoke-VersionManagerSynchronized -Path $path -ScriptBlock {
        $current = ConvertTo-VersionManagerUpdateCacheObject -Cache (Read-VersionManagerJsonFile -Path $path)
        $merged = Merge-VersionManagerUpdateCache -BaseCache $current -PatchCache $Patch
        Write-VersionManagerAtomicJsonFile -Path $path -Value $merged
        Sync-VersionManagerUpdateCacheVariables -Root $Root -Cache $merged
        return $merged
    })
}
