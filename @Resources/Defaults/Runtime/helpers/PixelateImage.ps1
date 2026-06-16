param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [string]$OutputPath = '',
    [string]$CacheRoot = '',
    [string]$CacheNamespace = 'default',
    [string]$OutputName = '',
    [int]$Width = 280,
    [int]$Height = 280,
    [int]$BlockSize = 16,
    [ValidateSet('Cover', 'Contain', 'Stretch')]
    [string]$FitMode = 'Cover',
    [ValidateSet('Average', 'Nearest')]
    [string]$SampleMode = 'Average',
    [string]$Token = ''
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}
$OutputEncoding = $script:Utf8NoBom
$MaxSourceBytes = 64MB
$MaxSourceDimension = 16384
$MaxSourcePixels = 67108864
$MaxTargetDimension = 4096
$script:PixelateErrorCode = ''
$script:PixelateErrorDetail = ''
$script:PixelateSourceLength = ''
$script:PixelateSourceFormat = ''
$script:PixelateDecodeMethod = ''

function Write-DmelPair {
    param(
        [string]$Name,
        [AllowNull()]
        [object]$Value
    )

    $text = [string]$Value
    $text = $text -replace "(`r|`n)+", ' '
    Write-Output ('{0}={1}' -f $Name, $text)
}

function Write-DmelResult {
    param(
        [string]$Status,
        [string]$Message,
        [string]$ResolvedOutputPath = '',
        [string]$ErrorCode = '',
        [string]$ErrorDetail = '',
        [string]$SourceLength = '',
        [string]$SourceFormat = '',
        [string]$DecodeMethod = ''
    )

    Write-DmelPair -Name 'DMEL_STATUS' -Value $Status
    Write-DmelPair -Name 'DMEL_OUTPUTPATH' -Value $ResolvedOutputPath
    Write-DmelPair -Name 'DMEL_TOKEN' -Value $Token
    Write-DmelPair -Name 'DMEL_MESSAGE' -Value $Message
    Write-DmelPair -Name 'DMEL_ERROR_CODE' -Value $ErrorCode
    Write-DmelPair -Name 'DMEL_ERROR_DETAIL' -Value $ErrorDetail
    Write-DmelPair -Name 'DMEL_SOURCE_LENGTH' -Value $SourceLength
    Write-DmelPair -Name 'DMEL_SOURCE_FORMAT' -Value $SourceFormat
    Write-DmelPair -Name 'DMEL_DECODE_METHOD' -Value $DecodeMethod
}

function Get-ImageFormatName {
    param(
        [byte[]]$Bytes,
        [int]$Count
    )

    if ($null -eq $Bytes -or $Count -lt 1) {
        return 'EMPTY'
    }

    $ascii = [System.Text.Encoding]::ASCII.GetString($Bytes, 0, $Count)
    if ($Count -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return 'PNG' }
    if ($Count -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return 'JPEG' }
    if ($Count -ge 6 -and ($ascii.StartsWith('GIF87a') -or $ascii.StartsWith('GIF89a'))) { return 'GIF' }
    if ($Count -ge 2 -and $ascii.StartsWith('BM')) { return 'BMP' }
    if ($Count -ge 4 -and (($Bytes[0] -eq 0x49 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x2A -and $Bytes[3] -eq 0x00) -or ($Bytes[0] -eq 0x4D -and $Bytes[1] -eq 0x4D -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x2A))) { return 'TIFF' }
    if ($Count -ge 4 -and $Bytes[0] -eq 0x00 -and $Bytes[1] -eq 0x00 -and $Bytes[2] -eq 0x01 -and $Bytes[3] -eq 0x00) { return 'ICO' }
    if ($Count -ge 12 -and $ascii.Substring(0, 4) -eq 'RIFF' -and $ascii.Substring(8, 4) -eq 'WEBP') { return 'WEBP' }
    if ($Count -ge 12 -and $ascii.Substring(4, 4) -eq 'ftyp') {
        $brand = $ascii.Substring(8, 4)
        if ($brand -eq 'avif' -or $brand -eq 'avis') { return 'AVIF' }
        if ($brand -eq 'heic' -or $brand -eq 'heix' -or $brand -eq 'hevc' -or $brand -eq 'hevx' -or $brand -eq 'mif1' -or $brand -eq 'msf1') { return 'HEIF' }
        return 'ISO-BMFF-' + $brand.Trim()
    }

    $trimmed = $ascii.TrimStart()
    if ($trimmed.StartsWith('<!DOCTYPE', [System.StringComparison]::OrdinalIgnoreCase) -or $trimmed.StartsWith('<html', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'HTML'
    }

    return 'UNKNOWN'
}

function Get-StableHash {
    param(
        [string]$Value,
        [int]$Length = 12
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        $hash = $sha.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
        if ($Length -gt 0 -and $Length -lt $hex.Length) {
            return $hex.Substring(0, $Length)
        }
        return $hex
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertTo-SafePathSegment {
    param(
        [string]$Value,
        [string]$Fallback,
        [int]$MaxLength = 96
    )

    $original = [string]$Value
    $segment = $original.Trim()
    $segment = $segment -replace '[^A-Za-z0-9_.-]', '_'
    $segment = $segment -replace '_+', '_'
    $segment = $segment.Trim([char[]]@(' ', '.', '_', '-'))
    if ([string]::IsNullOrWhiteSpace($segment)) {
        $segment = [string]$Fallback
    }
    if ([string]::IsNullOrWhiteSpace($segment)) {
        $segment = 'default'
    }
    if ($segment.Length -gt $MaxLength) {
        $suffix = Get-StableHash -Value $original -Length 10
        $prefixLength = [Math]::Max(1, $MaxLength - $suffix.Length - 1)
        $segment = $segment.Substring(0, $prefixLength).TrimEnd([char[]]@('.', '_', '-')) + '-' + $suffix
    }
    return $segment
}

function Get-DefaultCacheRoot {
    $appData = [Environment]::GetFolderPath('ApplicationData')
    if ([string]::IsNullOrWhiteSpace($appData)) {
        $appData = [System.IO.Path]::GetTempPath()
    }
    return [System.IO.Path]::Combine($appData, 'Rainmeter', 'DMeloperBlockHUD', 'ImageEffects', 'Pixelate')
}

function Resolve-OutputPath {
    param(
        [string]$ExplicitOutputPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitOutputPath)) {
        if ($ExplicitOutputPath.Contains([string][char]0xFFFD)) {
            throw 'Output path contains Unicode replacement characters.'
        }
        return [System.IO.Path]::GetFullPath($ExplicitOutputPath)
    }

    $root = [string]$CacheRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Get-DefaultCacheRoot
    }
    elseif ($root.Contains([string][char]0xFFFD)) {
        throw 'Cache root contains Unicode replacement characters.'
    }

    $namespace = ConvertTo-SafePathSegment -Value $CacheNamespace -Fallback 'default' -MaxLength 96
    $name = ConvertTo-SafePathSegment -Value $OutputName -Fallback '' -MaxLength 120
    if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'default') {
        $seed = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $SourcePath, $Width, $Height, $BlockSize, $FitMode, $SampleMode, $Token
        $name = '{0}-{1}x{2}-b{3}.png' -f (Get-StableHash -Value $seed -Length 12), $Width, $Height, $BlockSize
    }
    elseif (-not $name.EndsWith('.png', [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = $name + '.png'
    }

    return [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($root), $namespace, $name)
}

function Get-SourceImageFormat {
    param(
        [string]$Path
    )

    $stream = $null
    try {
        $buffer = New-Object byte[] 32
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $count = $stream.Read($buffer, 0, $buffer.Length)
        return Get-ImageFormatName -Bytes $buffer -Count $count
    }
    catch {
        return ''
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-CoverSourceRectangle {
    param(
        [int]$SourceWidth,
        [int]$SourceHeight,
        [int]$TargetWidth,
        [int]$TargetHeight
    )

    $sourceAspect = [double]$SourceWidth / [double]$SourceHeight
    $targetAspect = [double]$TargetWidth / [double]$TargetHeight
    if ($sourceAspect -gt $targetAspect) {
        $cropWidth = [double]$SourceHeight * $targetAspect
        $cropX = ([double]$SourceWidth - $cropWidth) / 2.0
        return New-Object System.Drawing.RectangleF([single]$cropX, [single]0, [single]$cropWidth, [single]$SourceHeight)
    }

    $cropHeight = [double]$SourceWidth / $targetAspect
    $cropY = ([double]$SourceHeight - $cropHeight) / 2.0
    return New-Object System.Drawing.RectangleF([single]0, [single]$cropY, [single]$SourceWidth, [single]$cropHeight)
}

function Get-ContainDestinationRectangle {
    param(
        [int]$SourceWidth,
        [int]$SourceHeight,
        [int]$TargetWidth,
        [int]$TargetHeight
    )

    $scale = [Math]::Min(([double]$TargetWidth / [double]$SourceWidth), ([double]$TargetHeight / [double]$SourceHeight))
    $destWidth = [Math]::Max(1.0, [double]$SourceWidth * $scale)
    $destHeight = [Math]::Max(1.0, [double]$SourceHeight * $scale)
    $destX = ([double]$TargetWidth - $destWidth) / 2.0
    $destY = ([double]$TargetHeight - $destHeight) / 2.0
    return New-Object System.Drawing.RectangleF([single]$destX, [single]$destY, [single]$destWidth, [single]$destHeight)
}

function Assert-SourceImageBounds {
    param(
        [int]$Width,
        [int]$Height,
        [string]$Format = ''
    )

    if ($Width -lt 1 -or $Height -lt 1) {
        $script:PixelateErrorCode = 'SOURCE_INVALID_DIMENSIONS'
        $script:PixelateErrorDetail = 'width={0}; height={1}; format={2}' -f $Width, $Height, $Format
        throw [System.IO.InvalidDataException]::new('Source image has invalid dimensions.')
    }

    $pixels = [int64]$Width * [int64]$Height
    if ($Width -gt $MaxSourceDimension -or $Height -gt $MaxSourceDimension -or $pixels -gt $MaxSourcePixels) {
        $script:PixelateErrorCode = 'SOURCE_TOO_LARGE'
        $script:PixelateErrorDetail = 'width={0}; height={1}; pixels={2}; maxDimension={3}; maxPixels={4}; format={5}' -f $Width, $Height, $pixels, $MaxSourceDimension, $MaxSourcePixels, $Format
        throw [System.IO.InvalidDataException]::new('Source image dimensions are too large.')
    }
}

function Convert-WicStreamToDrawingBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    Add-Type -AssemblyName PresentationCore

    $pngMemory = $null
    $decodedImage = $null
    try {
        $Stream.Position = 0
        $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
            $Stream,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )
        if ($decoder.Frames.Count -lt 1) {
            throw 'WIC decoder returned no image frames.'
        }
        $frame = $decoder.Frames[0]
        Assert-SourceImageBounds -Width $frame.PixelWidth -Height $frame.PixelHeight -Format $script:PixelateSourceFormat

        $pngMemory = New-Object System.IO.MemoryStream
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($frame))
        $encoder.Save($pngMemory)
        $pngMemory.Position = 0
        $decodedImage = [System.Drawing.Image]::FromStream($pngMemory, $false, $true)
        Assert-SourceImageBounds -Width $decodedImage.Width -Height $decodedImage.Height -Format $script:PixelateSourceFormat
        return (New-Object System.Drawing.Bitmap($decodedImage))
    }
    finally {
        if ($null -ne $decodedImage) { $decodedImage.Dispose() }
        if ($null -ne $pngMemory) { $pngMemory.Dispose() }
    }
}

function Open-SourceImageWithRetry {
    param(
        [string]$Path,
        [int]$Attempts = 6,
        [int]$DelayMilliseconds = 120
    )

    $lastError = $null
    $lastCode = ''
    $lastDetail = ''
    $lastLength = ''
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $stream = $null
        $memory = $null
        $decodedImage = $null
        $lastError = $null
        $lastCode = ''
        $lastDetail = ''
        $lastLength = ''
        $script:PixelateErrorCode = ''
        $script:PixelateErrorDetail = ''
        try {
            $fileInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
            $lastLength = [string]$fileInfo.Length
            $script:PixelateSourceLength = $lastLength
            if ([string]::IsNullOrWhiteSpace($script:PixelateSourceFormat)) {
                $script:PixelateSourceFormat = Get-SourceImageFormat -Path $Path
            }
            if ($script:PixelateSourceFormat -eq 'HTML') {
                $lastError = 'Source file is not an image.'
                $lastCode = 'SOURCE_NOT_IMAGE'
                $lastDetail = 'attempt={0}/{1}; bytes={2}; format={3}' -f $attempt, $Attempts, $fileInfo.Length, $script:PixelateSourceFormat
                throw [System.IO.InvalidDataException]::new($lastError)
            }
            if ($fileInfo.Length -le 0) {
                $lastError = 'Source image is empty.'
                $lastCode = 'SOURCE_EMPTY'
                $lastDetail = 'attempt={0}/{1}; bytes={2}' -f $attempt, $Attempts, $fileInfo.Length
                throw [System.IO.InvalidDataException]::new($lastError)
            }
            if ($fileInfo.Length -gt $MaxSourceBytes) {
                $lastError = 'Source image is too large.'
                $lastCode = 'SOURCE_TOO_LARGE'
                $lastDetail = 'attempt={0}/{1}; bytes={2}; maxBytes={3}; format={4}' -f $attempt, $Attempts, $fileInfo.Length, $MaxSourceBytes, $script:PixelateSourceFormat
                throw [System.IO.InvalidDataException]::new($lastError)
            }

            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $memory = New-Object System.IO.MemoryStream
            $stream.CopyTo($memory)
            $memory.Position = 0
            try {
                $decodedImage = [System.Drawing.Image]::FromStream($memory, $false, $true)
            }
            catch [System.OutOfMemoryException] {
                $decodedImage = $null
            }
            catch [System.ArgumentException] {
                $decodedImage = $null
            }
            if ($null -eq $decodedImage) {
                $script:PixelateDecodeMethod = 'WIC'
                return (Convert-WicStreamToDrawingBitmap -Stream $memory)
            }
            $script:PixelateDecodeMethod = 'GDI+'
            Assert-SourceImageBounds -Width $decodedImage.Width -Height $decodedImage.Height -Format $script:PixelateSourceFormat
            return (New-Object System.Drawing.Bitmap($decodedImage))
        }
        catch [System.IO.InvalidDataException] {
            $lastError = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Source image is invalid.' } else { [string]$_.Exception.Message }
            if ([string]::IsNullOrWhiteSpace($lastCode)) {
                $lastCode = if ([string]::IsNullOrWhiteSpace($script:PixelateErrorCode)) { 'SOURCE_INVALID' } else { $script:PixelateErrorCode }
            }
            if ([string]::IsNullOrWhiteSpace($lastDetail)) {
                $lastDetail = if ([string]::IsNullOrWhiteSpace($script:PixelateErrorDetail)) {
                    'attempt={0}/{1}; exception={2}; bytes={3}; format={4}' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength, $script:PixelateSourceFormat
                } else {
                    $script:PixelateErrorDetail
                }
            }
        }
        catch [System.InvalidOperationException] {
            $lastError = 'Source image could not be decoded.'
            $lastCode = 'SOURCE_DECODE_FAILED'
            $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; hint=unsupported-or-incomplete-image-or-missing-wic-codec; fallback=WIC' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength
        }
        catch [System.NotSupportedException] {
            $lastError = 'Source image could not be decoded.'
            $lastCode = 'SOURCE_DECODE_FAILED'
            $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; hint=unsupported-or-incomplete-image-or-missing-wic-codec; fallback=WIC' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength
        }
        catch [System.Runtime.InteropServices.COMException] {
            $lastError = 'Source image could not be decoded.'
            $lastCode = 'SOURCE_DECODE_FAILED'
            $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; hint=unsupported-or-incomplete-image-or-missing-wic-codec; fallback=WIC' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength
        }
        catch [System.OutOfMemoryException] {
            $lastError = 'Source image could not be decoded.'
            $lastCode = 'SOURCE_DECODE_FAILED'
            $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; hint=unsupported-or-incomplete-image' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength
        }
        catch [System.ArgumentException] {
            $lastError = 'Source image could not be decoded.'
            $lastCode = 'SOURCE_DECODE_FAILED'
            $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; hint=unsupported-or-incomplete-image' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength
        }
        catch [System.IO.IOException] {
            $lastError = 'Source image is not ready.'
            $lastCode = 'SOURCE_NOT_READY'
            $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; message={4}' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength, $_.Exception.Message
        }
        catch {
            if ([string]::IsNullOrWhiteSpace($lastError)) {
                $lastError = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Source image could not be opened.' } else { [string]$_.Exception.Message }
            }
            if ([string]::IsNullOrWhiteSpace($lastCode)) {
                $lastCode = 'SOURCE_OPEN_FAILED'
            }
            if ([string]::IsNullOrWhiteSpace($lastDetail)) {
                $lastDetail = 'attempt={0}/{1}; exception={2}; bytes={3}; message={4}' -f $attempt, $Attempts, $_.Exception.GetType().FullName, $lastLength, $_.Exception.Message
            }
        }
        finally {
            if ($null -ne $decodedImage) { $decodedImage.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
            if ($null -ne $memory) { $memory.Dispose() }
        }

        if ($lastCode -eq 'SOURCE_EMPTY' -or $lastCode -eq 'SOURCE_TOO_LARGE' -or $lastCode -eq 'SOURCE_NOT_IMAGE' -or $lastCode -eq 'SOURCE_INVALID_DIMENSIONS') {
            break
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    $script:PixelateErrorCode = $lastCode
    $script:PixelateErrorDetail = $lastDetail
    $script:PixelateSourceLength = $lastLength
    throw $lastError
}

$sourceImage = $null
$lowBitmap = $null
$finalBitmap = $null
$lowGraphics = $null
$finalGraphics = $null
$tempOutputPath = ''
$resolvedOutputPath = ''

try {
    Add-Type -AssemblyName System.Drawing

    $Width = [Math]::Max(1, [int]$Width)
    $Height = [Math]::Max(1, [int]$Height)
    $BlockSize = [Math]::Max(1, [int]$BlockSize)
    if ($Width -gt $MaxTargetDimension -or $Height -gt $MaxTargetDimension) {
        $script:PixelateErrorCode = 'TARGET_TOO_LARGE'
        $script:PixelateErrorDetail = 'width={0}; height={1}; maxDimension={2}' -f $Width, $Height, $MaxTargetDimension
        throw 'Target image dimensions are too large.'
    }

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    if (-not [System.IO.File]::Exists($sourceFullPath)) {
        throw "Source image does not exist: $sourceFullPath"
    }

    $resolvedOutputPath = Resolve-OutputPath -ExplicitOutputPath $OutputPath
    $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        throw 'Output path must include a directory.'
    }
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

    $sourceImage = Open-SourceImageWithRetry -Path $sourceFullPath
    Assert-SourceImageBounds -Width $sourceImage.Width -Height $sourceImage.Height -Format $script:PixelateSourceFormat

    $lowWidth = [Math]::Max(1, [int][Math]::Ceiling([double]$Width / [double]$BlockSize))
    $lowHeight = [Math]::Max(1, [int][Math]::Ceiling([double]$Height / [double]$BlockSize))
    $sourceRect = New-Object System.Drawing.RectangleF([single]0, [single]0, [single]$sourceImage.Width, [single]$sourceImage.Height)
    $lowDestRect = New-Object System.Drawing.RectangleF([single]0, [single]0, [single]$lowWidth, [single]$lowHeight)

    if ($FitMode -eq 'Cover') {
        $sourceRect = Get-CoverSourceRectangle -SourceWidth $sourceImage.Width -SourceHeight $sourceImage.Height -TargetWidth $Width -TargetHeight $Height
    }
    elseif ($FitMode -eq 'Contain') {
        $lowDestRect = Get-ContainDestinationRectangle -SourceWidth $sourceImage.Width -SourceHeight $sourceImage.Height -TargetWidth $lowWidth -TargetHeight $lowHeight
    }

    $lowBitmap = New-Object System.Drawing.Bitmap($lowWidth, $lowHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $lowGraphics = [System.Drawing.Graphics]::FromImage($lowBitmap)
    $lowGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $lowGraphics.Clear([System.Drawing.Color]::Transparent)
    if ($SampleMode -eq 'Nearest') {
        $lowGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $lowGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $lowGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    }
    else {
        $lowGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $lowGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $lowGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    }
    $lowGraphics.DrawImage($sourceImage, $lowDestRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)

    $finalBitmap = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $finalGraphics = [System.Drawing.Graphics]::FromImage($finalBitmap)
    $finalGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $finalGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $finalGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $finalGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $finalGraphics.Clear([System.Drawing.Color]::Transparent)
    $finalGraphics.DrawImage($lowBitmap, 0, 0, $Width, $Height)

    $tempOutputPath = $resolvedOutputPath + '.tmp-' + [System.Guid]::NewGuid().ToString('N') + '.png'
    $finalBitmap.Save($tempOutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Move-Item -LiteralPath $tempOutputPath -Destination $resolvedOutputPath -Force
    $tempOutputPath = ''
    $outputInfo = Get-Item -LiteralPath $resolvedOutputPath -ErrorAction Stop
    if ($outputInfo.Length -le 0) {
        $script:PixelateErrorCode = 'OUTPUT_EMPTY'
        $script:PixelateErrorDetail = 'outputPath={0}' -f $resolvedOutputPath
        throw 'Pixelated image output is empty.'
    }

    Write-DmelResult -Status 'OK' -Message 'Pixelated image written.' -ResolvedOutputPath $resolvedOutputPath -SourceLength $script:PixelateSourceLength -SourceFormat $script:PixelateSourceFormat -DecodeMethod $script:PixelateDecodeMethod
    exit 0
}
catch {
    if ($tempOutputPath -ne '' -and [System.IO.File]::Exists($tempOutputPath)) {
        Remove-Item -LiteralPath $tempOutputPath -Force -ErrorAction SilentlyContinue
    }
    $errorCode = if ([string]::IsNullOrWhiteSpace($script:PixelateErrorCode)) { 'PIXELATION_FAILED' } else { $script:PixelateErrorCode }
    $errorDetail = if ([string]::IsNullOrWhiteSpace($script:PixelateErrorDetail)) { $_.Exception.GetType().FullName } else { $script:PixelateErrorDetail }
    $sourceLength = $script:PixelateSourceLength
    if ([string]::IsNullOrWhiteSpace($sourceLength) -and -not [string]::IsNullOrWhiteSpace($sourceFullPath) -and [System.IO.File]::Exists($sourceFullPath)) {
        $sourceLength = [string]((Get-Item -LiteralPath $sourceFullPath -ErrorAction SilentlyContinue).Length)
    }
    Write-DmelResult -Status 'ERROR' -Message ([string]$_.Exception.Message) -ResolvedOutputPath $resolvedOutputPath -ErrorCode $errorCode -ErrorDetail $errorDetail -SourceLength $sourceLength -SourceFormat $script:PixelateSourceFormat -DecodeMethod $script:PixelateDecodeMethod
    exit 1
}
finally {
    if ($null -ne $finalGraphics) { $finalGraphics.Dispose() }
    if ($null -ne $lowGraphics) { $lowGraphics.Dispose() }
    if ($null -ne $finalBitmap) { $finalBitmap.Dispose() }
    if ($null -ne $lowBitmap) { $lowBitmap.Dispose() }
    if ($null -ne $sourceImage) { $sourceImage.Dispose() }
}
