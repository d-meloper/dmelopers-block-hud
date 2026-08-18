Add-Type -AssemblyName System.Drawing

function ConvertTo-BlockHudMinecraftSkinCacheKey {
    param([string]$Value)

    $resolved = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return ''
    }

    $pattern = '[<>:' + [char]34 + '/\\|?*\x00-\x1F]'
    return [System.Text.RegularExpressions.Regex]::Replace($resolved, $pattern, '_').Trim()
}

function Resolve-BlockHudMinecraftSkinCacheKey {
    param(
        [string]$RequestedKey,
        [string]$SourcePath
    )

    $resolved = ConvertTo-BlockHudMinecraftSkinCacheKey $RequestedKey
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        return $resolved
    }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $match = [System.Text.RegularExpressions.Regex]::Match($stem, '^MinecraftSkinTexture_(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        $stem = $match.Groups[1].Value
    }

    $resolved = ConvertTo-BlockHudMinecraftSkinCacheKey $stem
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw 'The Minecraft skin cache key is empty.'
    }
    return $resolved
}

function Get-BlockHudMinecraftSkinLookAtlasPath {
    param(
        [string]$OutputDirectory,
        [string]$CacheKey,
        [ValidateSet('wide', 'slim')]
        [string]$Model
    )

    $resolvedKey = ConvertTo-BlockHudMinecraftSkinCacheKey $CacheKey
    if ([string]::IsNullOrWhiteSpace($resolvedKey)) {
        throw 'The Minecraft skin cache key is empty.'
    }
    return [System.IO.Path]::Combine(
        (Get-BlockHudMinecraftSkinLookAtlasDirectory -OutputDirectory $OutputDirectory),
        ('MinecraftSkinLookAtlas_v2_' + $resolvedKey + '_' + $Model + '.png')
    )
}

function Get-BlockHudMinecraftSkinLookAtlasDirectory {
    param([Parameter(Mandatory = $true)][string]$OutputDirectory)

    return [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($OutputDirectory), 'atlas')
}

function Get-BlockHudMinecraftSkinLookAtlasSidecarPath {
    param(
        [string]$OutputDirectory,
        [string]$CacheKey,
        [ValidateSet('wide', 'slim')]
        [string]$Model
    )

    $atlasPath = Get-BlockHudMinecraftSkinLookAtlasPath -OutputDirectory $OutputDirectory -CacheKey $CacheKey -Model $Model
    return [System.IO.Path]::ChangeExtension($atlasPath, '.render-v2')
}

function Test-BlockHudPngDimensions {
    param(
        [string]$Path,
        [int]$Width,
        [int]$Height
    )

    if (-not [System.IO.File]::Exists($Path)) {
        return $false
    }

    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($Path)
        return ($image.Width -eq $Width -and $image.Height -eq $Height -and $image.RawFormat.Guid -eq [System.Drawing.Imaging.ImageFormat]::Png.Guid)
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $image) {
            $image.Dispose()
        }
    }
}

function Test-BlockHudMinecraftSkinLookAtlas {
    param(
        [string]$Path,
        [string]$SourcePath = ''
    )

    if (-not (Test-BlockHudPngDimensions -Path $Path -Width 1690 -Height 2340)) {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($SourcePath) -and [System.IO.File]::Exists($SourcePath)) {
        if ([System.IO.File]::GetLastWriteTimeUtc($Path) -lt [System.IO.File]::GetLastWriteTimeUtc($SourcePath)) {
            return $false
        }
    }
    return $true
}

function Test-BlockHudFileContentEqual {
    param(
        [string]$FirstPath,
        [string]$SecondPath
    )

    if (-not [System.IO.File]::Exists($FirstPath) -or -not [System.IO.File]::Exists($SecondPath)) {
        return $false
    }
    if ((New-Object System.IO.FileInfo($FirstPath)).Length -ne (New-Object System.IO.FileInfo($SecondPath)).Length) {
        return $false
    }

    $firstStream = $null
    $secondStream = $null
    $sha256 = $null
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $firstStream = [System.IO.File]::OpenRead($FirstPath)
        $firstHash = $sha256.ComputeHash($firstStream)
        $firstStream.Dispose()
        $firstStream = $null

        $secondStream = [System.IO.File]::OpenRead($SecondPath)
        $secondHash = $sha256.ComputeHash($secondStream)
        return ([System.BitConverter]::ToString($firstHash) -ceq [System.BitConverter]::ToString($secondHash))
    }
    finally {
        if ($null -ne $firstStream) { $firstStream.Dispose() }
        if ($null -ne $secondStream) { $secondStream.Dispose() }
        if ($null -ne $sha256) { $sha256.Dispose() }
    }
}

function Get-BlockHudFileSha256 {
    param([string]$Path)

    $stream = $null
    $sha256 = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return [System.BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '')
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $sha256) { $sha256.Dispose() }
    }
}

function Read-BlockHudMinecraftSkinLookAtlasSidecar {
    param([string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return $null
    }
    try {
        $values = @{}
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            $match = [System.Text.RegularExpressions.Regex]::Match([string]$line, '^([A-Z0-9_]+)=(.*)$')
            if ($match.Success) {
                $values[$match.Groups[1].Value] = $match.Groups[2].Value.Trim()
            }
        }
        if ([string]$values['FORMAT_VERSION'] -ne '2') {
            return $null
        }
        return $values
    }
    catch {
        return $null
    }
}

function Write-BlockHudMinecraftSkinLookAtlasSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CacheKey,
        [ValidateSet('wide', 'slim')][string]$Model,
        [string]$TexturePath = '',
        [Parameter(Mandatory = $true)][string]$BodyPath,
        [Parameter(Mandatory = $true)][string]$AtlasPath
    )

    if (-not [System.IO.File]::Exists($BodyPath) -or -not [System.IO.File]::Exists($AtlasPath)) {
        throw 'The Minecraft skin atlas sidecar inputs are incomplete.'
    }
    $textureHash = if (-not [string]::IsNullOrWhiteSpace($TexturePath) -and [System.IO.File]::Exists($TexturePath)) {
        Get-BlockHudFileSha256 $TexturePath
    }
    else {
        ''
    }
    $content = @(
        'DMEL_MINECRAFT_SKIN_LOOK_ATLAS'
        'FORMAT_VERSION=2'
        ('CACHE_KEY=' + (ConvertTo-BlockHudMinecraftSkinCacheKey $CacheKey))
        ('MODEL=' + $Model)
        ('TEXTURE_SHA256=' + $textureHash)
        ('BODY_SHA256=' + (Get-BlockHudFileSha256 $BodyPath))
        ('ATLAS_SHA256=' + (Get-BlockHudFileSha256 $AtlasPath))
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-BlockHudMinecraftSkinLookAtlasSidecar {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CacheKey,
        [ValidateSet('wide', 'slim')][string]$Model,
        [string]$TexturePath = '',
        [Parameter(Mandatory = $true)][string]$BodyPath,
        [Parameter(Mandatory = $true)][string]$AtlasPath
    )

    if (-not (Test-BlockHudPngDimensions -Path $BodyPath -Width 130 -Height 260) -or
        -not (Test-BlockHudMinecraftSkinLookAtlas -Path $AtlasPath)) {
        return $false
    }
    $values = Read-BlockHudMinecraftSkinLookAtlasSidecar -Path $Path
    if ($null -eq $values) {
        return $false
    }
    $expectedTextureHash = if (-not [string]::IsNullOrWhiteSpace($TexturePath) -and [System.IO.File]::Exists($TexturePath)) {
        Get-BlockHudFileSha256 $TexturePath
    }
    else {
        ''
    }
    return ([string]$values['CACHE_KEY'] -ceq (ConvertTo-BlockHudMinecraftSkinCacheKey $CacheKey)) -and
        ([string]$values['MODEL'] -ceq $Model) -and
        ([string]$values['TEXTURE_SHA256'] -ceq $expectedTextureHash) -and
        ([string]$values['BODY_SHA256'] -ceq (Get-BlockHudFileSha256 $BodyPath)) -and
        ([string]$values['ATLAS_SHA256'] -ceq (Get-BlockHudFileSha256 $AtlasPath))
}

function Move-BlockHudLegacyMinecraftSkinLookAtlases {
    param([Parameter(Mandatory = $true)][string]$OutputDirectory)

    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    $atlasDirectory = Get-BlockHudMinecraftSkinLookAtlasDirectory -OutputDirectory $resolvedOutputDirectory
    [System.IO.Directory]::CreateDirectory($atlasDirectory) | Out-Null
    $warnings = New-Object System.Collections.ArrayList
    $legacyAtlasPaths = @([System.IO.Directory]::EnumerateFiles($resolvedOutputDirectory, 'MinecraftSkinLookAtlas_v*_*.png', [System.IO.SearchOption]::TopDirectoryOnly) |
        Sort-Object @{ Expression = { if ([System.IO.Path]::GetFileName($_) -match '^MinecraftSkinLookAtlas_v2_') { 0 } else { 1 } } }, @{ Expression = { [System.IO.Path]::GetFileName($_) } })
    foreach ($sourcePath in $legacyAtlasPaths) {
        $fileName = [System.IO.Path]::GetFileName($sourcePath)
        $match = [regex]::Match($fileName, '^MinecraftSkinLookAtlas_v([12])_(.+)_(wide|slim)\.png$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            continue
        }
        if (-not (Test-BlockHudMinecraftSkinLookAtlas -Path $sourcePath)) {
            try {
                [System.IO.File]::Delete($sourcePath)
                $invalidSidecarPath = [System.IO.Path]::ChangeExtension($sourcePath, '.render-v2')
                if ([System.IO.File]::Exists($invalidSidecarPath)) { [System.IO.File]::Delete($invalidSidecarPath) }
            }
            catch {
                [void]$warnings.Add(($fileName + ': invalid legacy atlas cleanup failed: ' + [string]$_.Exception.Message))
            }
            continue
        }
        $sourceVersion = [int]$match.Groups[1].Value
        $cacheKey = $match.Groups[2].Value
        $model = $match.Groups[3].Value.ToLowerInvariant()
        $destinationFileName = 'MinecraftSkinLookAtlas_v2_' + $cacheKey + '_' + $model + '.png'
        $destinationPath = [System.IO.Path]::Combine($atlasDirectory, $destinationFileName)
        $legacySidecarPath = [System.IO.Path]::ChangeExtension($sourcePath, '.render-v2')
        $destinationSidecarPath = [System.IO.Path]::ChangeExtension($destinationPath, '.render-v2')
        try {
            $sourceHash = Get-BlockHudFileSha256 $sourcePath
            if ([System.IO.File]::Exists($destinationPath) -and (Test-BlockHudMinecraftSkinLookAtlas -Path $destinationPath)) {
                if ($sourceVersion -eq 2 -and [System.IO.File]::Exists($legacySidecarPath) -and -not [System.IO.File]::Exists($destinationSidecarPath)) {
                    [System.IO.File]::Copy($legacySidecarPath, $destinationSidecarPath, $false)
                }
                [System.IO.File]::Delete($sourcePath)
                if ([System.IO.File]::Exists($legacySidecarPath)) { [System.IO.File]::Delete($legacySidecarPath) }
                continue
            }

            $temporaryPath = $destinationPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
            [System.IO.File]::Copy($sourcePath, $temporaryPath, $true)
            if (-not (Test-BlockHudMinecraftSkinLookAtlas -Path $temporaryPath) -or (Get-BlockHudFileSha256 $temporaryPath) -cne $sourceHash) {
                throw 'Legacy atlas copy verification failed.'
            }
            if ([System.IO.File]::Exists($destinationPath)) {
                $backupPath = $temporaryPath + '.bak'
                [System.IO.File]::Replace($temporaryPath, $destinationPath, $backupPath, $true)
                if ([System.IO.File]::Exists($backupPath)) { [System.IO.File]::Delete($backupPath) }
            }
            else {
                [System.IO.File]::Move($temporaryPath, $destinationPath)
            }
            if ((Get-BlockHudFileSha256 $destinationPath) -cne $sourceHash) {
                throw 'Legacy atlas destination verification failed.'
            }
            [System.IO.File]::Delete($sourcePath)
            if ($sourceVersion -eq 2 -and [System.IO.File]::Exists($legacySidecarPath) -and -not [System.IO.File]::Exists($destinationSidecarPath)) {
                [System.IO.File]::Move($legacySidecarPath, $destinationSidecarPath)
            }
            elseif ([System.IO.File]::Exists($legacySidecarPath)) {
                [System.IO.File]::Delete($legacySidecarPath)
            }
        }
        catch {
            [void]$warnings.Add(($fileName + ': ' + [string]$_.Exception.Message))
        }
    }
    return [string[]]$warnings.ToArray()
}

function Resolve-BlockHudMinecraftSkinLookAtlas {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$CacheKey,
        [ValidateSet('wide', 'slim')][string]$Model,
        [string]$TexturePath = '',
        [Parameter(Mandatory = $true)][string]$BodyPath,
        [switch]$AllowLegacyBodyOnly
    )

    $warnings = @(Move-BlockHudLegacyMinecraftSkinLookAtlases -OutputDirectory $OutputDirectory)
    $atlasPath = Get-BlockHudMinecraftSkinLookAtlasPath -OutputDirectory $OutputDirectory -CacheKey $CacheKey -Model $Model
    $sidecarPath = Get-BlockHudMinecraftSkinLookAtlasSidecarPath -OutputDirectory $OutputDirectory -CacheKey $CacheKey -Model $Model
    if (-not (Test-BlockHudPngDimensions -Path $BodyPath -Width 130 -Height 260) -or
        -not (Test-BlockHudMinecraftSkinLookAtlas -Path $atlasPath)) {
        return [PSCustomObject]@{ Ready = $false; AtlasPath = ''; SidecarPath = $sidecarPath; Promoted = $false; Warnings = $warnings }
    }
    if (Test-BlockHudMinecraftSkinLookAtlasSidecar -Path $sidecarPath -CacheKey $CacheKey -Model $Model -TexturePath $TexturePath -BodyPath $BodyPath -AtlasPath $atlasPath) {
        return [PSCustomObject]@{ Ready = $true; AtlasPath = $atlasPath; SidecarPath = $sidecarPath; Promoted = $false; Warnings = $warnings }
    }

    $canPromote = $false
    if (-not [string]::IsNullOrWhiteSpace($TexturePath) -and [System.IO.File]::Exists($TexturePath)) {
        $markerPath = Get-BlockHudMinecraftSkinRenderMarkerPath -OutputDirectory $OutputDirectory -CacheKey $CacheKey
        $canPromote = (Test-BlockHudMinecraftSkinRenderMarker -Path $markerPath -Model $Model -TexturePath $TexturePath) -and
            ([System.IO.File]::GetLastWriteTimeUtc($atlasPath) -ge [System.IO.File]::GetLastWriteTimeUtc($TexturePath))
    }
    elseif ($AllowLegacyBodyOnly) {
        $canPromote = $true
    }
    if (-not $canPromote) {
        return [PSCustomObject]@{ Ready = $false; AtlasPath = ''; SidecarPath = $sidecarPath; Promoted = $false; Warnings = $warnings }
    }

    $temporarySidecarPath = $sidecarPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        Write-BlockHudMinecraftSkinLookAtlasSidecar -Path $temporarySidecarPath -CacheKey $CacheKey -Model $Model -TexturePath $TexturePath -BodyPath $BodyPath -AtlasPath $atlasPath
        Install-BlockHudFileSetTransactionally -Entries @([PSCustomObject]@{ SourcePath = $temporarySidecarPath; DestinationPath = $sidecarPath })
        $temporarySidecarPath = $null
    }
    finally {
        if ($temporarySidecarPath -and [System.IO.File]::Exists($temporarySidecarPath)) {
            [System.IO.File]::Delete($temporarySidecarPath)
        }
    }
    return [PSCustomObject]@{ Ready = $true; AtlasPath = $atlasPath; SidecarPath = $sidecarPath; Promoted = $true; Warnings = $warnings }
}

function Get-BlockHudMinecraftSkinRenderMarkerPath {
    param(
        [string]$OutputDirectory,
        [string]$CacheKey
    )

    $resolvedKey = ConvertTo-BlockHudMinecraftSkinCacheKey $CacheKey
    if ([string]::IsNullOrWhiteSpace($resolvedKey)) {
        throw 'The Minecraft skin cache key is empty.'
    }
    return [System.IO.Path]::Combine(
        [System.IO.Path]::GetFullPath($OutputDirectory),
        ('MinecraftSkinBody_' + $resolvedKey + '.render-v1')
    )
}

function Write-BlockHudMinecraftSkinRenderMarker {
    param(
        [string]$Path,
        [ValidateSet('wide', 'slim')]
        [string]$Model,
        [string]$TexturePath
    )

    $content = "DMEL_MINECRAFT_SKIN_RENDER_V1`nMODEL=$Model`nTEXTURE_SHA256=$(Get-BlockHudFileSha256 $TexturePath)`n"
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-BlockHudMinecraftSkinRenderMarker {
    param(
        [string]$Path,
        [ValidateSet('wide', 'slim')]
        [string]$Model,
        [string]$TexturePath
    )

    if (-not [System.IO.File]::Exists($Path) -or -not [System.IO.File]::Exists($TexturePath)) {
        return $false
    }
    try {
        $expected = "DMEL_MINECRAFT_SKIN_RENDER_V1`nMODEL=$Model`nTEXTURE_SHA256=$(Get-BlockHudFileSha256 $TexturePath)`n"
        $actual = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
        return $actual -ceq $expected
    }
    catch {
        return $false
    }
}

function Test-BlockHudMinecraftSkinRenderCache {
    param(
        [string]$IncomingTexturePath,
        [string]$InstalledTexturePath,
        [string]$BodyPath,
        [string]$AtlasPath,
        [string]$MarkerPath,
        [ValidateSet('wide', 'slim')]
        [string]$Model
    )

    return (Test-BlockHudFileContentEqual -FirstPath $IncomingTexturePath -SecondPath $InstalledTexturePath) -and
        (Test-BlockHudPngDimensions -Path $BodyPath -Width 130 -Height 260) -and
        (Test-BlockHudMinecraftSkinLookAtlas -Path $AtlasPath -SourcePath $InstalledTexturePath) -and
        (Test-BlockHudMinecraftSkinRenderMarker -Path $MarkerPath -Model $Model -TexturePath $InstalledTexturePath)
}

function Test-BlockHudMinecraftSkinStaticCache {
    param(
        [string]$IncomingTexturePath,
        [string]$InstalledTexturePath,
        [string]$BodyPath,
        [string]$MarkerPath,
        [ValidateSet('wide', 'slim')]
        [string]$Model
    )

    return (Test-BlockHudFileContentEqual -FirstPath $IncomingTexturePath -SecondPath $InstalledTexturePath) -and
        (Test-BlockHudPngDimensions -Path $BodyPath -Width 130 -Height 260) -and
        (Test-BlockHudMinecraftSkinRenderMarker -Path $MarkerPath -Model $Model -TexturePath $InstalledTexturePath)
}

function Invoke-BlockHudMinecraftSkinLookAtlasEnsure {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [string]$CacheKey = '',
        [ValidateSet('wide', 'slim')][string]$Model = 'wide',
        [string]$BodyPath = '',
        [Parameter(Mandatory = $true)][string]$RendererPath,
        [string]$RequestToken = '',
        [string]$ProgressDirectory = ''
    )

    $resolvedSourcePath = [System.IO.Path]::GetFullPath(([string]$SourcePath).Trim())
    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath(([string]$OutputDirectory).Trim())
    if (-not [System.IO.File]::Exists($resolvedSourcePath)) {
        throw 'The Minecraft skin texture does not exist.'
    }
    $sourceImage = $null
    try {
        $sourceImage = [System.Drawing.Image]::FromFile($resolvedSourcePath)
        if ($sourceImage.Width -ne 64 -or $sourceImage.Height -ne 64 -or $sourceImage.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Png.Guid) {
            throw 'The Minecraft skin texture must be a 64x64 PNG.'
        }
    }
    finally {
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
    }

    [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
    [System.IO.Directory]::CreateDirectory((Get-BlockHudMinecraftSkinLookAtlasDirectory -OutputDirectory $resolvedOutputDirectory)) | Out-Null
    $resolvedCacheKey = Resolve-BlockHudMinecraftSkinCacheKey -RequestedKey $CacheKey -SourcePath $resolvedSourcePath
    $resolvedBodyPath = if ([string]::IsNullOrWhiteSpace($BodyPath)) {
        [System.IO.Path]::Combine($resolvedOutputDirectory, ('MinecraftSkinBody_' + $resolvedCacheKey + '.png'))
    }
    else {
        [System.IO.Path]::GetFullPath($BodyPath)
    }
    if (-not (Test-BlockHudPngDimensions -Path $resolvedBodyPath -Width 130 -Height 260)) {
        throw 'The Minecraft skin static body cache is missing or invalid.'
    }

    $lookup = Resolve-BlockHudMinecraftSkinLookAtlas -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey -Model $Model -TexturePath $resolvedSourcePath -BodyPath $resolvedBodyPath
    if ($lookup.Ready) {
        return [PSCustomObject]@{ AtlasPath = [string]$lookup.AtlasPath; CacheHit = $true; CacheKey = $resolvedCacheKey; Warnings = @($lookup.Warnings) }
    }
    if (-not [System.IO.File]::Exists($RendererPath)) {
        throw 'The Minecraft skin renderer is missing.'
    }

    $atlasPath = Get-BlockHudMinecraftSkinLookAtlasPath -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey -Model $Model
    $sidecarPath = Get-BlockHudMinecraftSkinLookAtlasSidecarPath -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey -Model $Model
    $tempAtlasPath = $atlasPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $tempSidecarPath = $sidecarPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $renderArguments = @{
            SourcePath = $resolvedSourcePath
            OutputPath = $tempAtlasPath
            Model = $Model
            RenderMode = 'LookAtlas'
            FrameWidth = 130
            FrameHeight = 260
        }
        if (-not [string]::IsNullOrWhiteSpace($RequestToken) -and -not [string]::IsNullOrWhiteSpace($ProgressDirectory)) {
            $renderArguments.RequestToken = $RequestToken
            $renderArguments.ProgressDirectory = $ProgressDirectory
        }
        & $RendererPath @renderArguments
        if (-not (Test-BlockHudMinecraftSkinLookAtlas -Path $tempAtlasPath)) {
            throw 'The Minecraft skin renderer returned an invalid look atlas.'
        }
        Write-BlockHudMinecraftSkinLookAtlasSidecar -Path $tempSidecarPath -CacheKey $resolvedCacheKey -Model $Model -TexturePath $resolvedSourcePath -BodyPath $resolvedBodyPath -AtlasPath $tempAtlasPath
        if (-not (Test-BlockHudMinecraftSkinLookAtlasSidecar -Path $tempSidecarPath -CacheKey $resolvedCacheKey -Model $Model -TexturePath $resolvedSourcePath -BodyPath $resolvedBodyPath -AtlasPath $tempAtlasPath)) {
            throw 'The Minecraft skin renderer returned an invalid atlas sidecar.'
        }
        Install-BlockHudFileSetTransactionally -Entries @(
            [PSCustomObject]@{ SourcePath = $tempAtlasPath; DestinationPath = $atlasPath },
            [PSCustomObject]@{ SourcePath = $tempSidecarPath; DestinationPath = $sidecarPath }
        )
        $tempAtlasPath = $null
        $tempSidecarPath = $null
        if (-not (Test-BlockHudMinecraftSkinLookAtlasSidecar -Path $sidecarPath -CacheKey $resolvedCacheKey -Model $Model -TexturePath $resolvedSourcePath -BodyPath $resolvedBodyPath -AtlasPath $atlasPath)) {
            throw 'The installed Minecraft skin atlas cache is invalid.'
        }
        return [PSCustomObject]@{ AtlasPath = $atlasPath; CacheHit = $false; CacheKey = $resolvedCacheKey; Warnings = @($lookup.Warnings) }
    }
    finally {
        foreach ($temporaryPath in @($tempAtlasPath, $tempSidecarPath)) {
            if ($temporaryPath -and [System.IO.File]::Exists($temporaryPath)) {
                [System.IO.File]::Delete($temporaryPath)
            }
        }
    }
}

function Install-BlockHudFileSetTransactionally {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Entries,
        [ValidateRange(0, 100)]
        [int]$FailureAfter = 0,
        [ValidateRange(0, 100)]
        [int]$CleanupFailureAfter = 0
    )

    if ($Entries.Count -eq 0) {
        return
    }

    $transactionId = [System.Guid]::NewGuid().ToString('N')
    $installed = New-Object System.Collections.ArrayList
    try {
        foreach ($entry in $Entries) {
            $sourcePath = [System.IO.Path]::GetFullPath([string]$entry.SourcePath)
            $destinationPath = [System.IO.Path]::GetFullPath([string]$entry.DestinationPath)
            if (-not [System.IO.File]::Exists($sourcePath)) {
                throw "Transaction source is missing: $sourcePath"
            }

            $destinationExisted = [System.IO.File]::Exists($destinationPath)
            $backupPath = $destinationPath + '.dmel-' + $transactionId + '.bak'
            if ($destinationExisted) {
                [System.IO.File]::Replace($sourcePath, $destinationPath, $backupPath, $true)
            }
            else {
                [System.IO.File]::Move($sourcePath, $destinationPath)
            }

            [void]$installed.Add([PSCustomObject]@{
                DestinationPath = $destinationPath
                BackupPath = $backupPath
                DestinationExisted = $destinationExisted
            })
            if ($FailureAfter -gt 0 -and $installed.Count -eq $FailureAfter) {
                throw "Injected file transaction failure after $FailureAfter installs."
            }
        }

    }
    catch {
        $originalError = $_
        $rollbackErrors = New-Object System.Collections.ArrayList
        for ($index = $installed.Count - 1; $index -ge 0; $index--) {
            $record = $installed[$index]
            try {
                if ($record.DestinationExisted) {
                    if ([System.IO.File]::Exists($record.BackupPath)) {
                        if ([System.IO.File]::Exists($record.DestinationPath)) {
                            $discardPath = $record.BackupPath + '.discard'
                            try {
                                [System.IO.File]::Replace($record.BackupPath, $record.DestinationPath, $discardPath, $true)
                            }
                            finally {
                                if ([System.IO.File]::Exists($discardPath)) {
                                    [System.IO.File]::Delete($discardPath)
                                }
                            }
                        }
                        else {
                            [System.IO.File]::Move($record.BackupPath, $record.DestinationPath)
                        }
                    }
                }
                elseif ([System.IO.File]::Exists($record.DestinationPath)) {
                    [System.IO.File]::Delete($record.DestinationPath)
                }
            }
            catch {
                [void]$rollbackErrors.Add([string]$_.Exception.Message)
            }
        }

        if ($rollbackErrors.Count -gt 0) {
            throw (([string]$originalError.Exception.Message) + ' Rollback failed: ' + ($rollbackErrors -join ' | '))
        }
        throw $originalError
    }

    $cleanupIndex = 0
    foreach ($record in $installed) {
        if (-not $record.DestinationExisted -or -not [System.IO.File]::Exists($record.BackupPath)) {
            continue
        }
        $cleanupIndex = $cleanupIndex + 1
        try {
            if ($CleanupFailureAfter -gt 0 -and $cleanupIndex -eq $CleanupFailureAfter) {
                throw "Injected backup cleanup failure after $CleanupFailureAfter attempts."
            }
            [System.IO.File]::Delete($record.BackupPath)
        }
        catch {
            Write-Verbose ("Committed file transaction left rollback backup '{0}': {1}" -f $record.BackupPath, [string]$_.Exception.Message)
        }
    }
}
