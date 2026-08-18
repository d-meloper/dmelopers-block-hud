$EditorSkinRoot = [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($PSScriptRoot).FullName).FullName
$ItemImageAssetPolicyPath = [System.IO.Path]::Combine($EditorSkinRoot, 'Utilities', 'tools', 'ItemImageAsset.Policy.ps1')
if (-not [System.IO.File]::Exists($ItemImageAssetPolicyPath)) {
    throw "Shared item-image asset policy was not found: $ItemImageAssetPolicyPath"
}
. $ItemImageAssetPolicyPath

$SupportedExtensions = @(Get-BlockHudSupportedItemImageExtensions)
$ResizableExtensions = @('.png', '.jpg', '.jpeg', '.jpe', '.bmp', '.tif', '.tiff')
$MaxLongEdge = 64
$ReservedRuntimeAssetName = 'more.png'
$ItemGifMaxBytes = 50MB
$ItemGifMaxCanvasDimension = 4096
$ItemGifMaxSourceFrames = 240
$ItemGifMaxExpandedCells = 512
$ItemGifMaxAtlasDimension = 2048
$ItemGifTickMs = 50

function Get-EditorImageImportIoExceptionCode {
    param([System.Exception] $Exception)

    if ($null -eq $Exception) {
        return ''
    }

    return ('0x{0:X8}' -f ($Exception.HResult -band 0xffffffff))
}

function Test-EditorImageImportRetryCandidate {
    param([System.Exception] $Exception)

    if ($null -eq $Exception) {
        return $false
    }

    return ($Exception -is [System.IO.IOException]) -or
        ($Exception -is [System.UnauthorizedAccessException]) -or
        ($Exception -is [System.Security.SecurityException]) -or
        ($Exception -is [System.Runtime.InteropServices.ExternalException])
}

function Invoke-EditorImageImportIoWithRetry {
    param(
        [string] $Operation,
        [scriptblock] $Action,
        [int] $MaxAttempts = 5
    )

    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        $attempt += 1
        try {
            return & $Action
        }
        catch {
            if ($attempt -ge $MaxAttempts -or -not (Test-EditorImageImportRetryCandidate -Exception $_.Exception)) {
                throw
            }

            Start-Sleep -Milliseconds (150 * $attempt)
        }
    }
}

function Get-EditorImageImportAssets {
    param(
        [string] $ItemImageDirectory,
        [AllowNull()][string] $AtlasProfiles
    )

    $assets = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @(Get-ChildItem -LiteralPath $ItemImageDirectory | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)) {
        if ((Test-BlockHudItemImageAssetName -Value $file.Name) -and $seen.Add([string]$file.Name)) {
            $assets.Add([string]$file.Name)
        }
    }

    $manifestPath = Get-ItemImageManifestPath -ItemImageDirectory $ItemImageDirectory
    $profileValue = if ($PSBoundParameters.ContainsKey('AtlasProfiles')) {
        [string]$AtlasProfiles
    }
    else {
        Get-BlockHudItemGifAtlasProfilesValue -ManifestPath $manifestPath
    }
    $parsed = ConvertFrom-BlockHudItemGifAtlasProfiles -Value $profileValue
    foreach ($entry in @($parsed.Entries | Sort-Object SourceName)) {
        if ((Test-BlockHudItemGifAtlasProfileFiles -Entry $entry -ItemImageDirectory $ItemImageDirectory) -and
            $seen.Add([string]$entry.SourceName)) {
            $assets.Add([string]$entry.SourceName)
        }
    }
    return @($assets.ToArray() | Sort-Object)
}

function Test-EditorImagePathInsideAtlasDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ItemImageDirectory
    )

    $atlasPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ItemImageDirectory, 'atlas')).TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    return [System.IO.Path]::GetFullPath($Path).StartsWith($atlasPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ItemImageManifestPath {
    param([string] $ItemImageDirectory)

    $customsPath = [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($ItemImageDirectory).FullName).FullName
    $dataPath = [System.IO.Path]::Combine($customsPath, 'Data')
    return [System.IO.Path]::Combine($dataPath, 'ItemImages.inc')
}

function Get-EditorImageImportFailureMessage {
    param(
        [string] $Operation,
        [string] $TargetPath,
        [System.Exception] $Exception,
        [switch] $PartialSuccess
    )

    $resolvedOperation = if ([string]::IsNullOrWhiteSpace($Operation)) { 'processing the selected image' } else { $Operation }
    $resolvedTargetPath = [string]$TargetPath
    $exceptionMessage = ''
    if ($null -ne $Exception) {
        $exceptionMessage = ([string]$Exception.Message).Trim()
    }
    $ioCode = Get-EditorImageImportIoExceptionCode -Exception $Exception

    if (($Exception -is [System.UnauthorizedAccessException]) -or ($Exception -is [System.Security.SecurityException])) {
        if ($PartialSuccess) {
            $prefix = 'The image file was copied, but a follow-up write was blocked.'
        }
        else {
            $prefix = 'Image import was blocked while writing to the skin folder.'
        }
        return ($prefix + ' Security software, Windows Defender Controlled folder access, or folder permissions may be blocking writes to ' + $resolvedTargetPath + '. Allow Rainmeter or PowerShell to modify the skin folder and try again. [' + $resolvedOperation + '; ' + $ioCode + '; ' + $exceptionMessage + ']')
    }

    if ($Exception -is [System.IO.IOException]) {
        if ($PartialSuccess) {
            $prefix = 'The image file was copied, but a follow-up file update failed.'
        }
        else {
            $prefix = 'Image import hit a file I/O error.'
        }
        return ($prefix + ' Another process may be locking the file or scanning it, which can happen during antivirus inspection. Close any app using the image, wait a moment, and try again. [' + $resolvedOperation + '; ' + $ioCode + '; ' + $exceptionMessage + ']')
    }

    if ($PartialSuccess) {
        $prefix = 'The image file was copied, but the import could not finish cleanly.'
    }
    else {
        $prefix = 'Image import failed.'
    }
    return ($prefix + ' [' + $resolvedOperation + '; ' + $ioCode + '; ' + $exceptionMessage + ']')
}

function Test-SupportedImageExtension {
    param([string] $Path)

    $extension = [System.IO.Path]::GetExtension($Path)
    if ([string]::IsNullOrEmpty($extension)) {
        return $false
    }

    return $SupportedExtensions -contains $extension.ToLowerInvariant()
}

function Get-SafeAssetFileName {
    param(
        [string] $Path,
        [string] $PreferredBaseName
    )

    $name = [string]$PreferredBaseName
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $safeName = [System.Text.RegularExpressions.Regex]::Replace($name, '[\\/:*?"<>|#\[\];]', '_')
    $safeName = [System.Text.RegularExpressions.Regex]::Replace($safeName, '\s+', ' ').Trim()

    if ([string]::IsNullOrEmpty($safeName)) {
        $safeName = 'item'
    }

    $candidate = $safeName + $extension
    if ([string]::Equals($candidate, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase)) {
        $candidate = 'item_more.png'
    }

    $policyName = ConvertTo-BlockHudItemImageAssetName -Value $candidate
    if ([string]::IsNullOrWhiteSpace($policyName)) {
        $policyName = ConvertTo-BlockHudItemImageAssetName -Value ('item' + $extension)
    }
    return $policyName
}

function Get-UniqueAssetDestinationPath {
    param(
        [string] $ItemImageDirectory,
        [string] $PreferredFileName
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($PreferredFileName)
    $extension = [System.IO.Path]::GetExtension($PreferredFileName)
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = 'item'
    }

    $registered = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in @(Get-EditorImageImportAssets -ItemImageDirectory $ItemImageDirectory)) { [void]$registered.Add([string]$asset) }

    $candidatePath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $ItemImageDirectory -AssetName $PreferredFileName
    if (-not [System.IO.File]::Exists($candidatePath) -and -not $registered.Contains($PreferredFileName)) {
        return $candidatePath
    }

    for ($index = 2; $index -le 9999; $index += 1) {
        $candidateName = $baseName + '-' + $index + $extension
        if ([string]::Equals($candidateName, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidatePath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $ItemImageDirectory -AssetName $candidateName
        if (-not [System.IO.File]::Exists($candidatePath) -and -not $registered.Contains($candidateName)) {
            return $candidatePath
        }
    }

    return (Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $ItemImageDirectory -AssetName ($baseName + '-' + [System.Guid]::NewGuid().ToString('N') + $extension))
}

function Write-ItemImageManifest {
    param(
        [string] $ItemImageDirectory,
        [AllowNull()][string] $AtlasProfiles
    )

    $manifestPath = Get-ItemImageManifestPath -ItemImageDirectory $ItemImageDirectory
    $dataPath = [System.IO.Path]::GetDirectoryName($manifestPath)

    if (-not [System.IO.Directory]::Exists($dataPath)) {
        [System.IO.Directory]::CreateDirectory($dataPath) | Out-Null
    }

    if (-not $PSBoundParameters.ContainsKey('AtlasProfiles')) {
        $AtlasProfiles = Get-BlockHudItemGifAtlasProfilesValue -ManifestPath $manifestPath
    }
    $assets = @(Get-EditorImageImportAssets -ItemImageDirectory $ItemImageDirectory -AtlasProfiles $AtlasProfiles)
    $content = "[Variables]`r`nItemImageAssets=$($assets -join '|')`r`nItemImageAtlasProfiles=$([string]$AtlasProfiles)`r`n"
    $utf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)
    Invoke-EditorImageImportIoWithRetry -Operation 'write item image manifest' -Action {
        [System.IO.File]::WriteAllText($manifestPath, $content, $utf16LeBom)
    }

    return $assets
}

function Get-ImageCodec {
    param([string] $Extension)

    $normalized = $Extension.ToLowerInvariant()
    switch ($normalized) {
        '.jpg' { $normalized = '.jpeg' }
        '.jpe' { $normalized = '.jpeg' }
        '.tif' { $normalized = '.tiff' }
    }

    foreach ($codec in [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()) {
        foreach ($entry in ($codec.FilenameExtension -split ';')) {
            if ($entry.TrimStart('*').ToLowerInvariant() -eq $normalized) {
                return $codec
            }
        }
    }

    return $null
}

function Save-ResizedCopy {
    param(
        [string] $SourcePath,
        [string] $DestinationPath,
        [int] $MaxDimension
    )

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationPath)
    $samePath = [string]::Equals($sourceFullPath, $destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)
    $extension = [System.IO.Path]::GetExtension($destinationFullPath).ToLowerInvariant()
    if ($ResizableExtensions -notcontains $extension) {
        if ($samePath) {
            return
        }
        [System.IO.File]::Copy($sourceFullPath, $destinationFullPath, $true)
        return
    }

    $sourceImage = $null
    $bitmap = $null
    $graphics = $null
    $encoderParams = $null
    $tempDestinationPath = $null
    $saveSucceeded = $false

    try {
        $sourceImage = [System.Drawing.Image]::FromFile($sourceFullPath)
        $longEdge = [Math]::Max($sourceImage.Width, $sourceImage.Height)
        if ($longEdge -le $MaxDimension) {
            if ($samePath) {
                return
            }
            Invoke-EditorImageImportIoWithRetry -Operation 'copy source image without resize' -Action {
                [System.IO.File]::Copy($sourceFullPath, $destinationFullPath, $true)
            }
            return
        }

        $scale = $MaxDimension / [double]$longEdge
        $targetWidth = [Math]::Max(1, [int][Math]::Round($sourceImage.Width * $scale))
        $targetHeight = [Math]::Max(1, [int][Math]::Round($sourceImage.Height * $scale))
        $savePath = $destinationFullPath

        if ($samePath) {
            $tempDestinationPath = [System.IO.Path]::Combine(
                [System.IO.Path]::GetDirectoryName($destinationFullPath),
                ([System.IO.Path]::GetRandomFileName() + $extension)
            )
            $savePath = $tempDestinationPath
        }

        $bitmap = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($sourceImage, 0, 0, $targetWidth, $targetHeight)

        $codec = Get-ImageCodec $extension
        if ($codec -and ($extension -eq '.jpg' -or $extension -eq '.jpeg' -or $extension -eq '.jpe')) {
            $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 92L)
            $bitmap.Save($savePath, $codec, $encoderParams)
        }
        elseif ($codec) {
            $bitmap.Save($savePath, $codec, $null)
        }
        else {
            $bitmap.Save($savePath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        $saveSucceeded = $true
    }
    finally {
        if ($encoderParams) { $encoderParams.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($sourceImage) { $sourceImage.Dispose() }
        if ($tempDestinationPath -and [System.IO.File]::Exists($tempDestinationPath)) {
            try {
                if ($saveSucceeded) {
                    Invoke-EditorImageImportIoWithRetry -Operation 'replace resized item image' -Action {
                        [System.IO.File]::Copy($tempDestinationPath, $destinationFullPath, $true)
                    }
                }
            }
            finally {
                [System.IO.File]::Delete($tempDestinationPath)
            }
        }
    }
}

function Get-EditorItemGifOwnerHash {
    param([string]$SourceName)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(([string]$SourceName).ToLowerInvariant())
        return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })).Substring(0, 16)
    }
    finally {
        $sha.Dispose()
    }
}

function Get-EditorImageDecodedPixelHash {
    param([string]$Path)

    $source = $null
    $bitmap = $null
    $graphics = $null
    $data = $null
    $sha = $null
    try {
        $source = [System.Drawing.Image]::FromFile($Path)
        $bitmap = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.DrawImageUnscaled($source, 0, 0)
        $rectangle = New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)
        $data = $bitmap.LockBits($rectangle, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $rowBytes = $bitmap.Width * 4
        $pixels = New-Object byte[] ($rowBytes * $bitmap.Height)
        for ($row = 0; $row -lt $bitmap.Height; $row += 1) {
            $sourcePointer = [IntPtr]::Add($data.Scan0, $row * $data.Stride)
            [System.Runtime.InteropServices.Marshal]::Copy($sourcePointer, $pixels, $row * $rowBytes, $rowBytes)
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return -join ($sha.ComputeHash($pixels) | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        if ($null -ne $data -and $null -ne $bitmap) { $bitmap.UnlockBits($data) }
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
    }
}

function Optimize-EditorItemGifAtlasPng {
    param([string]$RawPath)

    $rawInfo = Get-Item -LiteralPath $RawPath
    if ($rawInfo.Length -lt 64KB) {
        return $RawPath
    }

    $candidatePath = $RawPath + '.wpf.png'
    try {
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        $stream = [System.IO.File]::Open($RawPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
                $stream,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($decoder.Frames[0]))
            $output = [System.IO.File]::Open($candidatePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $encoder.Save($output) } finally { $output.Dispose() }
        }
        finally {
            $stream.Dispose()
        }

        $rawImage = $null
        $candidateImage = $null
        try {
            $rawImage = [System.Drawing.Image]::FromFile($RawPath)
            $candidateImage = [System.Drawing.Image]::FromFile($candidatePath)
            $sameDimensions = $rawImage.Width -eq $candidateImage.Width -and $rawImage.Height -eq $candidateImage.Height
        }
        finally {
            if ($null -ne $candidateImage) { $candidateImage.Dispose() }
            if ($null -ne $rawImage) { $rawImage.Dispose() }
        }
        if ($sameDimensions -and
            (Get-EditorImageDecodedPixelHash -Path $RawPath) -ceq (Get-EditorImageDecodedPixelHash -Path $candidatePath) -and
            (Get-Item -LiteralPath $candidatePath).Length -lt $rawInfo.Length) {
            [System.IO.File]::Delete($RawPath)
            [System.IO.File]::Move($candidatePath, $RawPath)
        }
    }
    catch {
        # Optimization is optional; the validated System.Drawing PNG remains canonical.
    }
    finally {
        if ([System.IO.File]::Exists($candidatePath)) {
            [System.IO.File]::Delete($candidatePath)
        }
    }
    return $RawPath
}

function Test-EditorItemGifFirstFrame {
    param([System.Drawing.Image]$Image)

    $probe = $null
    $graphics = $null
    try {
        [void]$Image.SelectActiveFrame([System.Drawing.Imaging.FrameDimension]::Time, 0)
        $probe = New-Object System.Drawing.Bitmap(1, 1, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($probe)
        $graphics.DrawImage($Image, 0, 0, 1, 1)
        return $true
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $probe) { $probe.Dispose() }
    }
}

function Get-EditorItemGifAtlasGrid {
    param(
        [int]$CellCount,
        [int]$CellWidth,
        [int]$CellHeight,
        [int]$MaxDimension = $ItemGifMaxAtlasDimension
    )

    if ($CellCount -lt 1 -or $CellWidth -lt 1 -or $CellHeight -lt 1 -or $MaxDimension -lt 1) {
        return $null
    }

    $maxColumns = [Math]::Min($CellCount, [int][Math]::Floor($MaxDimension / [double]$CellWidth))
    $best = $null
    for ($columns = 1; $columns -le $maxColumns; $columns += 1) {
        $rows = [int][Math]::Ceiling($CellCount / [double]$columns)
        $atlasWidth = $columns * $CellWidth
        $atlasHeight = $rows * $CellHeight
        if ($atlasHeight -gt $MaxDimension) {
            continue
        }

        $candidate = [PSCustomObject]@{
            Columns = $columns
            Rows = $rows
            Width = $atlasWidth
            Height = $atlasHeight
            AllocatedCells = $columns * $rows
            MaxPixelDimension = [Math]::Max($atlasWidth, $atlasHeight)
            PixelAspectDifference = [Math]::Abs($atlasWidth - $atlasHeight)
        }
        if ($null -eq $best -or
            $candidate.AllocatedCells -lt $best.AllocatedCells -or
            ($candidate.AllocatedCells -eq $best.AllocatedCells -and $candidate.MaxPixelDimension -lt $best.MaxPixelDimension) -or
            ($candidate.AllocatedCells -eq $best.AllocatedCells -and $candidate.MaxPixelDimension -eq $best.MaxPixelDimension -and $candidate.PixelAspectDifference -lt $best.PixelAspectDifference) -or
            ($candidate.AllocatedCells -eq $best.AllocatedCells -and $candidate.MaxPixelDimension -eq $best.MaxPixelDimension -and $candidate.PixelAspectDifference -eq $best.PixelAspectDifference -and $candidate.Columns -lt $best.Columns)) {
            $best = $candidate
        }
    }
    return $best
}

function New-EditorItemGifAtlas {
    param(
        [string]$SourcePath,
        [string]$SourceName,
        [string]$OutputPath
    )

    $sourceLength = (Get-Item -LiteralPath $SourcePath).Length
    $sourceSha256 = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $image = $null
    $atlas = $null
    $graphics = $null
    try {
        $image = [System.Drawing.Image]::FromFile($SourcePath)
        if ($image.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Gif.Guid) {
            throw 'The selected .gif file does not contain GIF image data.'
        }
        $frameCount = $image.GetFrameCount([System.Drawing.Imaging.FrameDimension]::Time)
        if ($frameCount -lt 1 -or -not (Test-EditorItemGifFirstFrame -Image $image)) {
            throw 'The selected GIF has no decodable first frame.'
        }

        $limitReasons = New-Object System.Collections.Generic.List[string]
        if ($sourceLength -gt $ItemGifMaxBytes) { $limitReasons.Add('file size exceeds 50 MB') }
        if ($image.Width -gt $ItemGifMaxCanvasDimension -or $image.Height -gt $ItemGifMaxCanvasDimension) { $limitReasons.Add('canvas exceeds 4096x4096') }
        if ($frameCount -gt $ItemGifMaxSourceFrames) { $limitReasons.Add('source frame count exceeds 240') }
        if ($limitReasons.Count -gt 0) {
            return [PSCustomObject]@{
                StaticOnly = $true
                WarningMessage = 'Animated GIF atlas was not generated because ' + ($limitReasons.ToArray() -join ', ') + '. The original GIF was kept and will display its first frame.'
                SourceSha256 = $sourceSha256
                SourceFrameCount = $frameCount
            }
        }

        $cellFrames = New-Object System.Collections.Generic.List[int]
        if ($frameCount -eq 1) {
            $cellFrames.Add(0)
        }
        else {
            $delayBytes = $null
            try { $delayBytes = $image.GetPropertyItem(0x5100).Value } catch { $delayBytes = $null }
            for ($frame = 0; $frame -lt $frameCount; $frame += 1) {
                $delayCs = 10
                if ($null -ne $delayBytes -and $delayBytes.Length -ge (($frame + 1) * 4)) {
                    $delayCs = [BitConverter]::ToInt32($delayBytes, $frame * 4)
                    if ($delayCs -le 0) { $delayCs = 10 }
                }
                $delayMs = [Math]::Max(50, $delayCs * 10)
                $repetitions = [Math]::Max(1, [int][Math]::Floor(($delayMs / [double]$ItemGifTickMs) + 0.5))
                for ($repeat = 0; $repeat -lt $repetitions; $repeat += 1) { $cellFrames.Add($frame) }
                if ($cellFrames.Count -gt $ItemGifMaxExpandedCells) { break }
            }
        }
        if ($cellFrames.Count -gt $ItemGifMaxExpandedCells) {
            return [PSCustomObject]@{
                StaticOnly = $true
                WarningMessage = 'Animated GIF atlas was not generated because its 50 ms timing expansion exceeds 512 cells. The original GIF was kept and will display its first frame.'
                SourceSha256 = $sourceSha256
                SourceFrameCount = $frameCount
            }
        }

        $longEdge = [Math]::Max($image.Width, $image.Height)
        $scale = [Math]::Min(1.0, $MaxLongEdge / [double]$longEdge)
        $cellWidth = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
        $cellHeight = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))
        $grid = Get-EditorItemGifAtlasGrid -CellCount $cellFrames.Count -CellWidth $cellWidth -CellHeight $cellHeight
        if ($null -eq $grid) {
            return [PSCustomObject]@{
                StaticOnly = $true
                WarningMessage = 'Animated GIF atlas was not generated because the final atlas exceeds 2048x2048. The original GIF was kept and will display its first frame.'
                SourceSha256 = $sourceSha256
                SourceFrameCount = $frameCount
            }
        }
        $columns = $grid.Columns
        $atlasWidth = $grid.Width
        $atlasHeight = $grid.Height

        $atlas = New-Object System.Drawing.Bitmap($atlasWidth, $atlasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($atlas)
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $cell = 0
        for ($frame = 0; $frame -lt $frameCount; $frame += 1) {
            $firstCell = $cell
            while ($cell -lt $cellFrames.Count -and $cellFrames[$cell] -eq $frame) {
                $cell += 1
            }
            $repetitions = $cell - $firstCell
            if ($repetitions -lt 1) {
                continue
            }

            [void]$image.SelectActiveFrame([System.Drawing.Imaging.FrameDimension]::Time, $frame)
            if ($repetitions -eq 1) {
                $x = ($firstCell % $columns) * $cellWidth
                $y = [Math]::Floor($firstCell / $columns) * $cellHeight
                $graphics.DrawImage($image, $x, $y, $cellWidth, $cellHeight)
                continue
            }

            $renderedFrame = $null
            $frameGraphics = $null
            try {
                $renderedFrame = New-Object System.Drawing.Bitmap($cellWidth, $cellHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
                $frameGraphics = [System.Drawing.Graphics]::FromImage($renderedFrame)
                $frameGraphics.Clear([System.Drawing.Color]::Transparent)
                $frameGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                $frameGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $frameGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $frameGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $frameGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $frameGraphics.DrawImage($image, 0, 0, $cellWidth, $cellHeight)
                $frameGraphics.Dispose(); $frameGraphics = $null

                for ($renderCell = $firstCell; $renderCell -lt $cell; $renderCell += 1) {
                    $x = ($renderCell % $columns) * $cellWidth
                    $y = [Math]::Floor($renderCell / $columns) * $cellHeight
                    $graphics.DrawImageUnscaled($renderedFrame, $x, $y)
                }
            }
            finally {
                if ($null -ne $frameGraphics) { $frameGraphics.Dispose() }
                if ($null -ne $renderedFrame) { $renderedFrame.Dispose() }
            }
        }
        $graphics.Dispose(); $graphics = $null
        $atlas.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $atlas.Dispose(); $atlas = $null
        [void](Optimize-EditorItemGifAtlasPng -RawPath $OutputPath)

        $validationImage = $null
        try {
            $validationImage = [System.Drawing.Image]::FromFile($OutputPath)
            if ($validationImage.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Png.Guid -or
                $validationImage.Width -ne $atlasWidth -or $validationImage.Height -ne $atlasHeight) {
                throw 'The generated GIF atlas failed PNG format or dimension validation.'
            }
        }
        finally {
            if ($null -ne $validationImage) { $validationImage.Dispose() }
        }

        $atlasSha256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $ownerHash = Get-EditorItemGifOwnerHash -SourceName $SourceName
        return [PSCustomObject]@{
            StaticOnly = $false
            WarningMessage = ''
            SourceSha256 = $sourceSha256
            AtlasSha256 = $atlasSha256
            SourceFrameCount = $frameCount
            ExpandedCellCount = $cellFrames.Count
            Columns = $columns
            CellWidth = $cellWidth
            CellHeight = $cellHeight
            AtlasName = 'ItemGifAtlas_v1_' + $ownerHash + '_' + $sourceSha256.Substring(0, 16) + '.png'
        }
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $atlas) { $atlas.Dispose() }
        if ($null -ne $image) { $image.Dispose() }
    }
}

function Get-EditorItemGifAtlasEntries {
    param([string]$ItemImageDirectory)

    $manifestPath = Get-ItemImageManifestPath -ItemImageDirectory $ItemImageDirectory
    $parsed = ConvertFrom-BlockHudItemGifAtlasProfiles -Value (Get-BlockHudItemGifAtlasProfilesValue -ManifestPath $manifestPath)
    return @($parsed.Entries)
}

function Invoke-EditorItemGifInstallTransaction {
    param(
        [string]$StagedSourcePath,
        [string]$FinalSourcePath,
        [AllowNull()][string]$StagedAtlasPath,
        [AllowNull()][string]$FinalAtlasPath,
        [string[]]$StaleAtlasPaths,
        [string]$ItemImageDirectory,
        [object[]]$Profiles,
        [switch]$InstallSource,
        [switch]$InstallAtlas,
        [switch]$RemoveSource,
        [switch]$PreserveManifest
    )

    $manifestPath = Get-ItemImageManifestPath -ItemImageDirectory $ItemImageDirectory
    $transactionRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'BlockHudItemGifTxn_' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($transactionRoot) | Out-Null
    $manifestBackup = [System.IO.Path]::Combine($transactionRoot, 'ItemImages.inc')
    $manifestExisted = [System.IO.File]::Exists($manifestPath)
    $sourceInstalled = $false
    $atlasInstalled = $false
    $quarantined = New-Object System.Collections.Generic.List[object]
    try {
        if ($InstallSource -and $RemoveSource) { throw 'GIF import cannot install and remove the source in the same transaction.' }
        if ($manifestExisted) { [System.IO.File]::Copy($manifestPath, $manifestBackup, $true) }
        if ($InstallSource) {
            [System.IO.File]::Copy($StagedSourcePath, $FinalSourcePath, $false)
            $sourceInstalled = $true
        }
        if ($RemoveSource -and [System.IO.File]::Exists($FinalSourcePath)) {
            $resolvedSource = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $ItemImageDirectory -AssetName ([System.IO.Path]::GetFileName($FinalSourcePath))
            if (-not [string]::Equals($resolvedSource, [System.IO.Path]::GetFullPath($FinalSourcePath), [System.StringComparison]::OrdinalIgnoreCase) -or
                [System.IO.Path]::GetExtension($resolvedSource) -ine '.gif') {
                throw "Refusing to quarantine a non-item GIF source: $FinalSourcePath"
            }
            $sourceBackup = [System.IO.Path]::Combine($transactionRoot, [guid]::NewGuid().ToString('N') + '.gif')
            [System.IO.File]::Move($resolvedSource, $sourceBackup)
            $quarantined.Add([PSCustomObject]@{ Original = $resolvedSource; Backup = $sourceBackup })
        }
        foreach ($stalePath in @($StaleAtlasPaths)) {
            if ([string]::IsNullOrWhiteSpace($stalePath) -or -not [System.IO.File]::Exists($stalePath)) { continue }
            if (-not (Test-BlockHudManagedItemGifAtlasName -Value ([System.IO.Path]::GetFileName($stalePath)))) {
                throw "Refusing to quarantine a non-managed atlas: $stalePath"
            }
            $quarantinePath = [System.IO.Path]::Combine($transactionRoot, [guid]::NewGuid().ToString('N') + '.png')
            [System.IO.File]::Move($stalePath, $quarantinePath)
            $quarantined.Add([PSCustomObject]@{ Original = $stalePath; Backup = $quarantinePath })
        }
        if ($InstallAtlas) {
            $atlasDirectory = [System.IO.Path]::GetDirectoryName($FinalAtlasPath)
            [System.IO.Directory]::CreateDirectory($atlasDirectory) | Out-Null
            [System.IO.File]::Copy($StagedAtlasPath, $FinalAtlasPath, $false)
            $atlasInstalled = $true
        }
        $profileValue = ConvertTo-BlockHudItemGifAtlasProfiles -Entries $Profiles
        $assets = if ($PreserveManifest) {
            @(Get-EditorImageImportAssets -ItemImageDirectory $ItemImageDirectory -AtlasProfiles $profileValue)
        }
        else {
            @(Write-ItemImageManifest -ItemImageDirectory $ItemImageDirectory -AtlasProfiles $profileValue)
        }
        return [PSCustomObject]@{ Assets = $assets; Profiles = $profileValue }
    }
    catch {
        if ($manifestExisted -and [System.IO.File]::Exists($manifestBackup)) {
            [System.IO.File]::Copy($manifestBackup, $manifestPath, $true)
        }
        elseif (-not $manifestExisted -and [System.IO.File]::Exists($manifestPath)) {
            [System.IO.File]::Delete($manifestPath)
        }
        if ($atlasInstalled -and [System.IO.File]::Exists($FinalAtlasPath)) { [System.IO.File]::Delete($FinalAtlasPath) }
        if ($sourceInstalled -and [System.IO.File]::Exists($FinalSourcePath)) { [System.IO.File]::Delete($FinalSourcePath) }
        foreach ($entry in @($quarantined.ToArray())) {
            if ([System.IO.File]::Exists([string]$entry.Backup)) {
                [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName([string]$entry.Original)) | Out-Null
                [System.IO.File]::Move([string]$entry.Backup, [string]$entry.Original)
            }
        }
        throw
    }
    finally {
        if ([System.IO.Directory]::Exists($transactionRoot)) {
            try { [System.IO.Directory]::Delete($transactionRoot, $true) } catch { }
        }
    }
}

function Import-EditorItemGifFromFileDetailed {
    param(
        [string]$SourcePath,
        [string]$ItemImageDirectory,
        [string]$SafeFileName
    )

    $itemRoot = [System.IO.Path]::GetFullPath($ItemImageDirectory)
    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    if ((Test-EditorImagePathInsideAtlasDirectory -Path $sourceFullPath -ItemImageDirectory $itemRoot) -or
        (Test-BlockHudManagedItemGifAtlasName -Value ([System.IO.Path]::GetFileName($sourceFullPath)))) {
        return $null
    }

    $targetPath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $itemRoot -AssetName $SafeFileName
    $selectedIsTarget = [string]::Equals($sourceFullPath, $targetPath, [System.StringComparison]::OrdinalIgnoreCase)
    $sourceHash = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $existingProfiles = @(Get-EditorItemGifAtlasEntries -ItemImageDirectory $itemRoot)
    $cacheEntry = @($existingProfiles | Where-Object {
        [string]::Equals([string]$_.SourceName, $SafeFileName, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$_.SourceSha256, $sourceHash, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-BlockHudItemGifAtlasProfileFiles -Entry $_ -ItemImageDirectory $itemRoot)
    })
    if ($cacheEntry.Count -eq 1) {
        $cacheStalePaths = New-Object System.Collections.Generic.List[string]
        $cacheOwnerHash = Get-EditorItemGifOwnerHash -SourceName $SafeFileName
        $cacheAtlasDirectory = [System.IO.Path]::Combine($itemRoot, 'atlas')
        if ([System.IO.Directory]::Exists($cacheAtlasDirectory)) {
            foreach ($ownedAtlasPath in @([System.IO.Directory]::GetFiles($cacheAtlasDirectory, 'ItemGifAtlas_v1_' + $cacheOwnerHash + '_*.png', [System.IO.SearchOption]::TopDirectoryOnly))) {
                if (-not [string]::Equals([System.IO.Path]::GetFileName($ownedAtlasPath), [string]$cacheEntry[0].AtlasName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $cacheStalePaths.Add($ownedAtlasPath)
                }
            }
        }
        $transaction = Invoke-EditorItemGifInstallTransaction `
            -StagedSourcePath $sourceFullPath `
            -FinalSourcePath $targetPath `
            -StagedAtlasPath '' `
            -FinalAtlasPath '' `
            -StaleAtlasPaths @($cacheStalePaths.ToArray()) `
            -ItemImageDirectory $itemRoot `
            -Profiles $existingProfiles `
            -RemoveSource:([System.IO.File]::Exists($targetPath)) `
            -PreserveManifest
        return [PSCustomObject]@{
            FinalPath = $targetPath
            ItemImageAssets = ($transaction.Assets -join '|')
            ItemImageAtlasProfiles = [string]$transaction.Profiles
            ManifestPersisted = $true
            Status = 'OK'
            WarningMessage = ''
        }
    }

    $finalPath = if ($selectedIsTarget) { $targetPath } else { Get-UniqueAssetDestinationPath -ItemImageDirectory $itemRoot -PreferredFileName $SafeFileName }
    $finalName = [System.IO.Path]::GetFileName($finalPath)

    $stagingRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'BlockHudItemGif_' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
    $stagedSource = [System.IO.Path]::Combine($stagingRoot, 'source.gif')
    $stagedAtlas = [System.IO.Path]::Combine($stagingRoot, 'atlas.png')
    try {
        [System.IO.File]::Copy($sourceFullPath, $stagedSource, $true)
        $atlasResult = New-EditorItemGifAtlas -SourcePath $stagedSource -SourceName $finalName -OutputPath $stagedAtlas
        if ($selectedIsTarget -and (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash -ine $sourceHash) {
            throw 'The selected GIF changed while it was being imported. Try again.'
        }

        $profiles = New-Object System.Collections.Generic.List[object]
        $stalePaths = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $existingProfiles) {
            if ([string]::Equals([string]$entry.SourceName, $finalName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $oldPath = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $itemRoot -AtlasName ([string]$entry.AtlasName)
                if ($atlasResult.StaticOnly -or -not [string]::Equals([string]$entry.AtlasName, [string]$atlasResult.AtlasName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $stalePaths.Add($oldPath)
                }
                continue
            }
            if (Test-BlockHudItemGifAtlasProfileFiles -Entry $entry -ItemImageDirectory $itemRoot) {
                $profiles.Add($entry)
            }
        }

        $ownerHash = Get-EditorItemGifOwnerHash -SourceName $finalName
        $atlasDirectory = [System.IO.Path]::Combine($itemRoot, 'atlas')
        if ([System.IO.Directory]::Exists($atlasDirectory)) {
            foreach ($ownedAtlasPath in @([System.IO.Directory]::GetFiles($atlasDirectory, 'ItemGifAtlas_v1_' + $ownerHash + '_*.png', [System.IO.SearchOption]::TopDirectoryOnly))) {
                if ($atlasResult.StaticOnly -or
                    -not [string]::Equals([System.IO.Path]::GetFileName($ownedAtlasPath), [string]$atlasResult.AtlasName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $stalePaths.Add($ownedAtlasPath)
                }
            }
        }

        $finalAtlasPath = ''
        $installAtlas = $false
        if (-not $atlasResult.StaticOnly) {
            $finalAtlasPath = Resolve-BlockHudItemGifAtlasPath -ItemImageDirectory $itemRoot -AtlasName ([string]$atlasResult.AtlasName)
            $installAtlas = -not [System.IO.File]::Exists($finalAtlasPath)
            if (-not $installAtlas -and (Get-FileHash -LiteralPath $finalAtlasPath -Algorithm SHA256).Hash -ine [string]$atlasResult.AtlasSha256) {
                $stalePaths.Add($finalAtlasPath)
                $installAtlas = $true
            }
            $profiles.Add([PSCustomObject]@{
                SourceName = $finalName
                AtlasName = [string]$atlasResult.AtlasName
                SourceSha256 = [string]$atlasResult.SourceSha256
                AtlasSha256 = [string]$atlasResult.AtlasSha256
                SourceFrameCount = [int]$atlasResult.SourceFrameCount
                ExpandedCellCount = [int]$atlasResult.ExpandedCellCount
                Columns = [int]$atlasResult.Columns
                CellWidth = [int]$atlasResult.CellWidth
                CellHeight = [int]$atlasResult.CellHeight
            })
        }

        $transaction = Invoke-EditorItemGifInstallTransaction `
            -StagedSourcePath $stagedSource `
            -FinalSourcePath $finalPath `
            -StagedAtlasPath $stagedAtlas `
            -FinalAtlasPath $finalAtlasPath `
            -StaleAtlasPaths @($stalePaths.ToArray()) `
            -ItemImageDirectory $itemRoot `
            -Profiles @($profiles.ToArray()) `
            -InstallSource:($atlasResult.StaticOnly -and -not $selectedIsTarget) `
            -InstallAtlas:$installAtlas `
            -RemoveSource:((-not $atlasResult.StaticOnly) -and [System.IO.File]::Exists($finalPath))
        return [PSCustomObject]@{
            FinalPath = $finalPath
            ItemImageAssets = ($transaction.Assets -join '|')
            ItemImageAtlasProfiles = [string]$transaction.Profiles
            ManifestPersisted = $true
            Status = if ([string]::IsNullOrWhiteSpace([string]$atlasResult.WarningMessage)) { 'OK' } else { 'WARN' }
            WarningMessage = [string]$atlasResult.WarningMessage
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($stagingRoot)) { [System.IO.Directory]::Delete($stagingRoot, $true) }
    }
}

function Import-EditorItemImageFromFileDetailed {
    param(
        [string] $SourcePath,
        [string] $ItemImageDirectory,
        [string] $PreferredBaseName
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or [string]::IsNullOrWhiteSpace($ItemImageDirectory)) {
        return $null
    }

    if (-not [System.IO.Directory]::Exists($ItemImageDirectory)) {
        return $null
    }

    $selectedPath = [System.IO.Path]::GetFullPath($SourcePath)
    if (-not [System.IO.File]::Exists($selectedPath)) {
        return $null
    }

    if (-not (Test-SupportedImageExtension $selectedPath)) {
        return $null
    }

    $itemImageDirectory = [System.IO.Path]::GetFullPath($ItemImageDirectory)
    $selectedDirectory = [System.IO.Path]::GetDirectoryName($selectedPath)
    $selectedFileName = [System.IO.Path]::GetFileName($selectedPath)
    if ((Test-EditorImagePathInsideAtlasDirectory -Path $selectedPath -ItemImageDirectory $itemImageDirectory) -or
        (Test-BlockHudManagedItemGifAtlasName -Value $selectedFileName)) {
        return $null
    }
    $safeFileName = Get-SafeAssetFileName -Path $selectedPath -PreferredBaseName $PreferredBaseName
    if ([string]::IsNullOrWhiteSpace($safeFileName) -or
        [string]::Equals($safeFileName, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $extension = [System.IO.Path]::GetExtension($selectedPath).ToLowerInvariant()
    if ($extension -eq '.gif') {
        return Import-EditorItemGifFromFileDetailed -SourcePath $selectedPath -ItemImageDirectory $itemImageDirectory -SafeFileName $safeFileName
    }
    $sameDirectory = [string]::Equals($selectedDirectory, $itemImageDirectory, [System.StringComparison]::OrdinalIgnoreCase)
    $sameSafeName = [string]::Equals($safeFileName, $selectedFileName, [System.StringComparison]::Ordinal)
    $requiresResize = $false

    if ($ResizableExtensions -contains $extension) {
        $probeImage = $null
        try {
            $probeImage = [System.Drawing.Image]::FromFile($selectedPath)
            $requiresResize = [Math]::Max($probeImage.Width, $probeImage.Height) -gt $MaxLongEdge
        }
        catch {
            $requiresResize = $false
        }
        finally {
            if ($probeImage) { $probeImage.Dispose() }
        }
    }

    $targetPath = Resolve-BlockHudItemImageAssetPath -ItemImageDirectory $itemImageDirectory -AssetName $safeFileName
    $selectedIsTarget = [string]::Equals($selectedPath, [System.IO.Path]::GetFullPath($targetPath), [System.StringComparison]::OrdinalIgnoreCase)
    $needsMaterialize = ((-not $sameDirectory) -or (-not $sameSafeName) -or $requiresResize) -and (-not $selectedIsTarget)
    $finalPath = $selectedPath

    if ($needsMaterialize) {
        $finalPath = Get-UniqueAssetDestinationPath -ItemImageDirectory $itemImageDirectory -PreferredFileName $safeFileName
        Save-ResizedCopy -SourcePath $selectedPath -DestinationPath $finalPath -MaxDimension $MaxLongEdge
    }

    $itemImageAssets = @()
    $manifestPersisted = $true
    $warningMessage = ''
    try {
        $itemImageAssets = @(Write-ItemImageManifest -ItemImageDirectory $itemImageDirectory)
    }
    catch {
        $manifestPersisted = $false
        $itemImageAssets = @(Get-EditorImageImportAssets -ItemImageDirectory $itemImageDirectory)
        $warningMessage = Get-EditorImageImportFailureMessage -Operation 'write item image manifest' -TargetPath (Get-ItemImageManifestPath -ItemImageDirectory $itemImageDirectory) -Exception $_.Exception -PartialSuccess
    }

    return [PSCustomObject]@{
        FinalPath = $finalPath
        ItemImageAssets = ($itemImageAssets -join '|')
        ItemImageAtlasProfiles = Get-BlockHudItemGifAtlasProfilesValue -ManifestPath (Get-ItemImageManifestPath -ItemImageDirectory $itemImageDirectory)
        ManifestPersisted = $manifestPersisted
        Status = if ($manifestPersisted) { 'OK' } else { 'WARN' }
        WarningMessage = $warningMessage
    }
}

function Import-EditorItemImageFromFile {
    param(
        [string] $SourcePath,
        [string] $ItemImageDirectory,
        [string] $PreferredBaseName
    )
    $result = Import-EditorItemImageFromFileDetailed -SourcePath $SourcePath -ItemImageDirectory $ItemImageDirectory -PreferredBaseName $PreferredBaseName
    if ($null -eq $result) {
        return $null
    }

    return [string]$result.FinalPath
}
