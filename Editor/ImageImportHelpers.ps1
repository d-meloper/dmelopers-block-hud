$SupportedExtensions = @('.png', '.jpg', '.jpeg', '.jpe', '.bmp', '.gif', '.tif', '.tiff', '.ico', '.jxr', '.wdp', '.dds')
$ResizableExtensions = @('.png', '.jpg', '.jpeg', '.jpe', '.bmp', '.gif', '.tif', '.tiff')
$MaxLongEdge = 64
$ReservedRuntimeAssetName = 'more.png'

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
    param([string] $ItemImageDirectory)

    return @(
        Get-ChildItem -LiteralPath $ItemImageDirectory |
            Where-Object { -not $_.PSIsContainer } |
            Where-Object { Test-SupportedImageExtension $_.FullName } |
            Where-Object { -not [string]::Equals($_.Name, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object Name |
            ForEach-Object { $_.Name }
    )
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
        return 'item_more.png'
    }

    return $candidate
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

    $candidatePath = [System.IO.Path]::Combine($ItemImageDirectory, $PreferredFileName)
    if (-not [System.IO.File]::Exists($candidatePath)) {
        return $candidatePath
    }

    for ($index = 2; $index -le 9999; $index += 1) {
        $candidateName = $baseName + '-' + $index + $extension
        if ([string]::Equals($candidateName, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidatePath = [System.IO.Path]::Combine($ItemImageDirectory, $candidateName)
        if (-not [System.IO.File]::Exists($candidatePath)) {
            return $candidatePath
        }
    }

    return [System.IO.Path]::Combine($ItemImageDirectory, ($baseName + '-' + [System.Guid]::NewGuid().ToString('N') + $extension))
}

function Write-ItemImageManifest {
    param([string] $ItemImageDirectory)

    $manifestPath = Get-ItemImageManifestPath -ItemImageDirectory $ItemImageDirectory
    $dataPath = [System.IO.Path]::GetDirectoryName($manifestPath)

    if (-not [System.IO.Directory]::Exists($dataPath)) {
        [System.IO.Directory]::CreateDirectory($dataPath) | Out-Null
    }

    $assets = @(Get-EditorImageImportAssets -ItemImageDirectory $ItemImageDirectory)

    $content = "[Variables]`r`nItemImageAssets=$($assets -join '|')`r`n"
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
    $safeFileName = Get-SafeAssetFileName -Path $selectedPath -PreferredBaseName $PreferredBaseName
    if ([string]::Equals($safeFileName, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $selectedFileName = [System.IO.Path]::GetFileName($selectedPath)
    $extension = [System.IO.Path]::GetExtension($selectedPath).ToLowerInvariant()
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

    $targetPath = [System.IO.Path]::Combine($itemImageDirectory, $safeFileName)
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
        ManifestPersisted = $manifestPersisted
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
