Set-StrictMode -Version 2.0

function Get-BlockHudReleaseVariantForLanguageCode {
    param([AllowNull()][string]$LanguageCode)

    if ([string]::Equals(([string]$LanguageCode).Trim(), 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Korea'
    }

    return 'Global'
}

function Normalize-BlockHudReleaseVariant {
    param(
        [AllowNull()][string]$ConfiguredReleaseVariant,
        [AllowNull()][string]$LanguageCode,
        [AllowNull()][string]$AssetPattern
    )

    $configured = ([string]$ConfiguredReleaseVariant).Trim()
    if ([string]::Equals($configured, 'Korea', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Korea'
    }
    if ([string]::Equals($configured, 'Global', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Global'
    }

    $asset = ([string]$AssetPattern).Trim()
    if ($asset -match '(?i)(^|[_\-.])Korea([_\-.]|$)') {
        return 'Korea'
    }
    if ($asset -match '(?i)(^|[_\-.])Global([_\-.]|$)') {
        return 'Global'
    }

    return (Get-BlockHudReleaseVariantForLanguageCode -LanguageCode $LanguageCode)
}

function Get-BlockHudFixedUpdateZipAssetName {
    param(
        [AllowNull()][string]$ReleaseVariant,
        [AllowNull()][string]$LanguageCode
    )

    $variant = Normalize-BlockHudReleaseVariant -ConfiguredReleaseVariant $ReleaseVariant -LanguageCode $LanguageCode -AssetPattern ''
    if ([string]::Equals($variant, 'Korea', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'DMelopers-Block-HUD_Korea.zip'
    }

    return 'DMelopers-Block-HUD_Global.zip'
}

function Test-BlockHudReleaseAssetNameMatch {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedName,
        [Parameter(Mandatory = $true)][string]$ActualName
    )

    return [string]::Equals($ExpectedName, $ActualName, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-BlockHudZipPackageSafeToExtract {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$ExtractRoot
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

    $expandedExtractRoot = [Environment]::ExpandEnvironmentVariables($ExtractRoot)
    if ([string]::IsNullOrWhiteSpace($expandedExtractRoot)) {
        throw 'ZIP extraction root is empty.'
    }
    $resolvedExtractRoot = if ([System.IO.Path]::IsPathRooted($expandedExtractRoot)) {
        [System.IO.Path]::GetFullPath($expandedExtractRoot)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $expandedExtractRoot))
    }
    $resolvedExtractRoot = $resolvedExtractRoot.TrimEnd('\', '/')
    $extractPrefix = $resolvedExtractRoot + '\'

    $seenTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $fileTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $requiredDirectoryTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $invalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()

    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        foreach ($entry in $archive.Entries) {
            $entryName = ([string]$entry.FullName).Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($entryName)) {
                throw 'ZIP package contains an empty entry name.'
            }
            if ([System.IO.Path]::IsPathRooted($entryName) -or $entryName.StartsWith('\') -or $entryName.Contains(':')) {
                throw "ZIP package contains a rooted entry: $entryName"
            }

            $isDirectory = $entryName.EndsWith('\', [System.StringComparison]::Ordinal)
            $segments = @($entryName.Split([char[]]@('\'), [System.StringSplitOptions]::RemoveEmptyEntries))
            if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw "ZIP package contains an unsafe path segment: $entryName"
            }
            foreach ($segment in $segments) {
                if ($segment.EndsWith('.', [System.StringComparison]::Ordinal) -or
                    $segment.EndsWith(' ', [System.StringComparison]::Ordinal)) {
                    throw "ZIP package contains a Windows-aliased path segment: $entryName"
                }
                if ($segment.IndexOfAny($invalidFileNameChars) -ge 0) {
                    throw "ZIP package contains an invalid Windows path segment: $entryName"
                }
            }

            $canonicalRelativePath = [string]::Join('\', [string[]]$segments)
            $destination = [System.IO.Path]::GetFullPath((Join-Path $resolvedExtractRoot $canonicalRelativePath))
            if (-not $destination.StartsWith($extractPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP package entry escapes the extraction root: $entryName"
            }
            if (-not $seenTargets.Add($destination)) {
                throw "ZIP package contains a duplicate Windows extraction target: $entryName"
            }

            $parent = [System.IO.Path]::GetDirectoryName($destination)
            while (-not [string]::IsNullOrWhiteSpace($parent) -and
                $parent.StartsWith($extractPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($fileTargets.Contains($parent)) {
                    throw "ZIP package contains a file/descendant path conflict: $entryName"
                }
                [void]$requiredDirectoryTargets.Add($parent)
                $parent = [System.IO.Path]::GetDirectoryName($parent)
            }

            if ($isDirectory) {
                [void]$requiredDirectoryTargets.Add($destination)
            }
            else {
                if ($requiredDirectoryTargets.Contains($destination)) {
                    throw "ZIP package contains a file/descendant path conflict: $entryName"
                }
                [void]$fileTargets.Add($destination)
            }

            $unixFileType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixFileType -eq 0xA000) {
                throw "ZIP package contains a symbolic-link entry: $entryName"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}
