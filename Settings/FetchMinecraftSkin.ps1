param(
    [string]$Username = '',
    [string]$OutputDirectory = '',
    [ValidateSet('wide', 'slim')]
    [string]$Model = 'wide',
    [int]$TimeoutSeconds = 12,
    [switch]$ShowErrorDialog
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$script:DebugLogPath = $null
$script:DebugLogSectionStarted = $false
. (Join-Path $PSScriptRoot '..\tools\Localization.Common.ps1')

Add-Type -AssemblyName System.Drawing

$skinRoot = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$languageCode = Read-LanguageCode -SkinRoot $skinRoot
$locTable = Read-LocaleTable -SkinRoot $skinRoot -LanguageCode $languageCode

$resultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_USERNAME = ''
    DMEL_UUID = ''
    DMEL_IMAGEPATH = ''
    DMEL_TEXTUREPATH = ''
    DMEL_MODEL = ''
    DMEL_MESSAGE = ''
    DMEL_LOGPATH = ''
    DMEL_DEBUGLOG = ''
}

function L([string]$Key, [string]$Fallback = '') {
    return Get-LocalizedText -Table $locTable -Key $Key -Fallback $Fallback
}

function Set-ResultPairValue {
    param(
        [string]$Key,
        [AllowNull()][string]$Value
    )

    if ($resultPairs.Contains($Key)) {
        $resultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
    }
}

function Convert-ResultPairValueToSingleLine {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $singleLine = [string]$Value
    $singleLine = $singleLine.Replace("`r", ' ').Replace("`n", ' ')
    while ($singleLine.Contains('  ')) {
        $singleLine = $singleLine.Replace('  ', ' ')
    }

    return $singleLine.Trim()
}

function Emit-ResultPairs {
    if ([string]::IsNullOrWhiteSpace([string]$resultPairs['DMEL_LOGPATH'])) {
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value (Get-DebugLogOutputValue)
    }
    if ([string]::IsNullOrWhiteSpace([string]$resultPairs['DMEL_DEBUGLOG'])) {
        Set-ResultPairValue -Key 'DMEL_DEBUGLOG' -Value (Get-DebugLogOutputValue)
    }

    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    try {
        $writer.AutoFlush = $true
        foreach ($key in $resultPairs.Keys) {
            $writer.WriteLine($key + '=' + (Convert-ResultPairValueToSingleLine -Value $resultPairs[$key]))
        }
    }
    finally {
        $writer.Dispose()
    }
}

function Trim-Text([string]$Value) {
    return ([string]$Value).Trim()
}

function Normalize-MinecraftSkinModel([string]$Value) {
    if ((Trim-Text $Value).ToLowerInvariant() -eq 'slim') {
        return 'slim'
    }

    return 'wide'
}

function Write-DebugLog([string]$Message) {
    if ([string]::IsNullOrWhiteSpace($script:DebugLogPath)) {
        return
    }
    try {
        $directory = Split-Path -Parent $script:DebugLogPath
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        }
        $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
        $line = '[' + $timestamp + '] [FetchMinecraftSkin] ' + [string]$Message
        $writer = New-Object System.IO.StreamWriter($script:DebugLogPath, $true, $utf8NoBom)
        try {
            if (-not $script:DebugLogSectionStarted) {
                $writer.WriteLine('<MinecraftSkin>')
                $script:DebugLogSectionStarted = $true
            }
            $writer.WriteLine($line)
        }
        finally {
            $writer.Dispose()
        }
    }
    catch {
    }
}

function Get-DebugLogOutputValue() {
    if ([string]::IsNullOrWhiteSpace($script:DebugLogPath)) {
        return ''
    }
    return [string]$script:DebugLogPath
}

function Sanitize-FileComponent([string]$Value) {
    $resolved = Trim-Text $Value
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return ''
    }
    $pattern = '[<>:' + [char]34 + '/\\|?*\x00-\x1F]'
    $resolved = [System.Text.RegularExpressions.Regex]::Replace($resolved, $pattern, '_')
    return $resolved.Trim()
}

function Test-MinecraftUsername([string]$Value) {
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[A-Za-z0-9_]{3,16}$'
}

function Show-ErrorDialog([string]$Message) {
    if (-not $ShowErrorDialog) {
        return
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            [string]$Message,
            (L 'Helper_Minecraft_ErrorTitle' 'Minecraft Skin Error'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
    }
}

function Test-PngSignature([string]$Path) {
    if (-not [System.IO.File]::Exists($Path)) {
        return $false
    }
    $signature = New-Object byte[] 8
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $read = $stream.Read($signature, 0, $signature.Length)
        if ($read -ne 8) {
            return $false
        }
    }
    finally {
        $stream.Dispose()
    }
    $expected = 137,80,78,71,13,10,26,10
    for ($i = 0; $i -lt $expected.Length; $i++) {
        if ($signature[$i] -ne $expected[$i]) {
            return $false
        }
    }
    return $true
}

function Get-PngDimensions([string]$Path) {
    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($Path)
        return [PSCustomObject]@{
            Width = [int]$image.Width
            Height = [int]$image.Height
        }
    }
    finally {
        if ($null -ne $image) {
            $image.Dispose()
        }
    }
}

function Copy-ResponseStreamBounded(
    [System.IO.Stream]$Source,
    [string]$DestinationPath,
    [long]$MaxBytes
) {
    $buffer = New-Object byte[] 81920
    $total = [long]0
    $fileStream = [System.IO.File]::Create($DestinationPath)
    try {
        while ($true) {
            $read = $Source.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                break
            }
            $total += [long]$read
            if ($total -gt $MaxBytes) {
                throw 'Minecraft skin image exceeded the maximum allowed size.'
            }
            $fileStream.Write($buffer, 0, $read)
        }
    }
    finally {
        $fileStream.Dispose()
    }
    return $total
}

function Copy-TextureRegion {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Source,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Destination,
        [int]$SourceX,
        [int]$SourceY,
        [int]$DestinationX,
        [int]$DestinationY,
        [int]$Width,
        [int]$Height,
        [switch]$FlipX
    )

    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $sourcePixelX = if ($FlipX) { $SourceX + $Width - 1 - $x } else { $SourceX + $x }
            $Destination.SetPixel(
                ($DestinationX + $x),
                ($DestinationY + $y),
                $Source.GetPixel($sourcePixelX, ($SourceY + $y))
            )
        }
    }
}

function New-Legacy64x64MinecraftSkinTexture {
    param([Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Source)

    $expanded = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 0 -SourceY 0 -DestinationX 0 -DestinationY 0 -Width 64 -Height 32

        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 4 -SourceY 16 -DestinationX 20 -DestinationY 48 -Width 4 -Height 4 -FlipX
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 8 -SourceY 16 -DestinationX 24 -DestinationY 48 -Width 4 -Height 4 -FlipX
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 8 -SourceY 20 -DestinationX 16 -DestinationY 52 -Width 4 -Height 12
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 4 -SourceY 20 -DestinationX 20 -DestinationY 52 -Width 4 -Height 12 -FlipX
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 0 -SourceY 20 -DestinationX 24 -DestinationY 52 -Width 4 -Height 12
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 12 -SourceY 20 -DestinationX 28 -DestinationY 52 -Width 4 -Height 12 -FlipX

        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 44 -SourceY 16 -DestinationX 36 -DestinationY 48 -Width 4 -Height 4 -FlipX
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 48 -SourceY 16 -DestinationX 40 -DestinationY 48 -Width 4 -Height 4 -FlipX
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 48 -SourceY 20 -DestinationX 32 -DestinationY 52 -Width 4 -Height 12
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 44 -SourceY 20 -DestinationX 36 -DestinationY 52 -Width 4 -Height 12 -FlipX
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 40 -SourceY 20 -DestinationX 40 -DestinationY 52 -Width 4 -Height 12
        Copy-TextureRegion -Source $Source -Destination $expanded -SourceX 52 -SourceY 20 -DestinationX 44 -DestinationY 52 -Width 4 -Height 12 -FlipX

        return $expanded
    }
    catch {
        $expanded.Dispose()
        throw
    }
}

function Convert-ToCleanPng([string]$Path) {
    $cleanPath = $null
    $sourceBitmap = $null
    $bitmap = $null
    try {
        $image = [System.Drawing.Image]::FromFile($Path)
        try {
            if ($image.Width -ne 64 -or ($image.Height -ne 64 -and $image.Height -ne 32)) {
                throw 'Minecraft skin texture dimensions are outside the allowed range.'
            }
            $sourceBitmap = New-Object System.Drawing.Bitmap $image
        }
        finally {
            $image.Dispose()
        }

        if ($sourceBitmap.Width -eq 64 -and $sourceBitmap.Height -eq 32) {
            Write-DebugLog 'Normalizing legacy 64x32 skin texture to 64x64.'
            $bitmap = New-Legacy64x64MinecraftSkinTexture -Source $sourceBitmap
        }
        else {
            $bitmap = New-Object System.Drawing.Bitmap $sourceBitmap
        }

        $cleanPath = $Path + '.clean.png'
        try {
            $bitmap.Save($cleanPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            if ($null -ne $bitmap) {
                $bitmap.Dispose()
                $bitmap = $null
            }
        }

        Move-Item -LiteralPath $cleanPath -Destination $Path -Force
    }
    catch {
        if ($cleanPath -and [System.IO.File]::Exists($cleanPath)) {
            Remove-Item -LiteralPath $cleanPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if ($null -ne $bitmap) {
            $bitmap.Dispose()
        }
        if ($null -ne $sourceBitmap) {
            $sourceBitmap.Dispose()
        }
    }
}

function Assert-ValidMinecraftSkinTexture([string]$Path) {
    if (-not (Test-PngSignature $Path)) {
        Write-DebugLog ("PNG signature validation failed for path='" + $Path + "'")
        throw 'Minecraft skin texture download returned an invalid PNG image.'
    }

    try {
        $size = Get-PngDimensions $Path
    }
    catch {
        Write-DebugLog ('PNG dimension read failed: ' + [string]$_.Exception.Message)
        throw 'Minecraft skin texture download returned an invalid PNG image.'
    }

    if ($size.Width -ne 64 -or ($size.Height -ne 64 -and $size.Height -ne 32)) {
        Write-DebugLog ("Invalid texture dimensions: $($size.Width)x$($size.Height)")
        throw 'Minecraft skin texture dimensions are outside the allowed range.'
    }

    Convert-ToCleanPng -Path $Path

    $normalizedSize = Get-PngDimensions $Path
    if ($normalizedSize.Width -ne 64 -or $normalizedSize.Height -ne 64) {
        Write-DebugLog ("Normalized texture dimensions are invalid: $($normalizedSize.Width)x$($normalizedSize.Height)")
        throw 'Minecraft skin texture dimensions are outside the allowed range.'
    }
}

function Read-ResponseText([System.Net.HttpWebResponse]$Response) {
    if ($null -eq $Response) {
        return ''
    }
    $stream = $Response.GetResponseStream()
    if ($null -eq $stream) {
        return ''
    }
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
    try {
        return [string]($reader.ReadToEnd())
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Resolve-MinecraftProfile([string]$Username, [int]$TimeoutMilliseconds) {
    $url = 'https://api.mojang.com/users/profiles/minecraft/' + [System.Uri]::EscapeDataString($Username)
    Write-DebugLog ("PROFILE_LOOKUP url='" + $url + "'")
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Method = 'GET'
        $request.UserAgent = 'DMeloper-BlockHUD/1.2'
        $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $request.Timeout = $TimeoutMilliseconds
        $request.ReadWriteTimeout = $TimeoutMilliseconds

        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $statusCode = [int]$response.StatusCode
        Write-DebugLog ('PROFILE_LOOKUP status=' + $statusCode)
        if ($statusCode -eq 204) {
            return $null
        }
        if ($statusCode -ne 200) {
            throw ('Minecraft profile lookup returned HTTP ' + $statusCode)
        }

        $content = Read-ResponseText $response
        Write-DebugLog ("PROFILE_LOOKUP content='" + $content + "'")
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $null
        }

        $profile = $content | ConvertFrom-Json
        $canonicalUsername = Trim-Text ([string]$profile.name)
        $resolvedUuid = ([string]$profile.id) -replace '[^0-9A-Fa-f]', ''
        if ([string]::IsNullOrWhiteSpace($canonicalUsername) -or $resolvedUuid.Length -ne 32) {
            throw 'Minecraft profile lookup returned an invalid profile payload.'
        }

        return @{
            Username = $canonicalUsername
            Uuid = $resolvedUuid.ToLowerInvariant()
        }
    }
    catch [System.Net.WebException] {
        $statusCode = 0
        if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
            $statusCode = [int]([System.Net.HttpWebResponse]$_.Exception.Response).StatusCode
        }
        if ($statusCode -eq 204 -or $statusCode -eq 404) {
            Write-DebugLog ('PROFILE_LOOKUP no profile found status=' + $statusCode)
            return $null
        }
        throw
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
    }
}

function Resolve-MinecraftSkinTexture(
    [string]$Uuid,
    [string]$FallbackModel,
    [int]$TimeoutMilliseconds
) {
    $url = 'https://sessionserver.mojang.com/session/minecraft/profile/' + [System.Uri]::EscapeDataString($Uuid)
    Write-DebugLog ("TEXTURE_LOOKUP url='" + $url + "'")
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Method = 'GET'
        $request.UserAgent = 'DMeloper-BlockHUD/1.2'
        $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $request.Timeout = $TimeoutMilliseconds
        $request.ReadWriteTimeout = $TimeoutMilliseconds

        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $statusCode = [int]$response.StatusCode
        Write-DebugLog ('TEXTURE_LOOKUP status=' + $statusCode)
        if ($statusCode -ne 200) {
            throw ('Minecraft texture lookup returned HTTP ' + $statusCode)
        }

        $content = Read-ResponseText $response
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw 'NO_SKIN_TEXTURE'
        }

        $profile = $content | ConvertFrom-Json
        $textureProperty = $null
        foreach ($property in @($profile.properties)) {
            if ([string]$property.name -eq 'textures' -and -not [string]::IsNullOrWhiteSpace([string]$property.value)) {
                $textureProperty = $property
                break
            }
        }
        if ($null -eq $textureProperty) {
            throw 'NO_SKIN_TEXTURE'
        }

        $decodedBytes = [Convert]::FromBase64String([string]$textureProperty.value)
        $decodedJson = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        Write-DebugLog ("TEXTURE_LOOKUP decoded='" + $decodedJson + "'")
        $texturePayload = $decodedJson | ConvertFrom-Json
        $skinTexture = $texturePayload.textures.SKIN
        $textureUrl = Trim-Text ([string]$skinTexture.url)
        if ([string]::IsNullOrWhiteSpace($textureUrl)) {
            throw 'NO_SKIN_TEXTURE'
        }

        $resolvedModel = Normalize-MinecraftSkinModel $FallbackModel
        $metadataModel = ''
        if ($null -ne $skinTexture.metadata) {
            $metadataModel = Trim-Text ([string]$skinTexture.metadata.model).ToLowerInvariant()
        }

        if ($metadataModel -eq 'slim') {
            $resolvedModel = 'slim'
        }
        elseif ($metadataModel -eq 'wide' -or $metadataModel -eq 'default' -or $metadataModel -eq 'classic') {
            $resolvedModel = 'wide'
        }

        return [PSCustomObject]@{
            Url = $textureUrl
            Model = $resolvedModel
            MetadataModel = $metadataModel
        }
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
    }
}

function Download-MinecraftSkinTexture(
    [string]$Url,
    [string]$DestinationPath,
    [int]$TimeoutMilliseconds
) {
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.UserAgent = 'DMeloper-BlockHUD/1.2'
        $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $request.Timeout = $TimeoutMilliseconds
        $request.ReadWriteTimeout = $TimeoutMilliseconds

        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        Write-DebugLog ('TEXTURE_DOWNLOAD status=' + [int]$response.StatusCode)
        if ([int]$response.StatusCode -ne 200) {
            throw ('Minecraft texture download returned HTTP ' + [int]$response.StatusCode)
        }
        $contentType = [string]$response.ContentType
        if (-not [string]::IsNullOrWhiteSpace($contentType) -and $contentType -notmatch '^\s*image/png\b') {
            throw ('Minecraft texture download returned unexpected content type ' + $contentType)
        }
        $maxImageBytes = [long](2 * 1024 * 1024)
        if ($response.ContentLength -gt $maxImageBytes) {
            throw 'Minecraft skin image exceeded the maximum allowed size.'
        }

        $responseStream = $response.GetResponseStream()
        try {
            $bytesWritten = Copy-ResponseStreamBounded -Source $responseStream -DestinationPath $DestinationPath -MaxBytes $maxImageBytes
        }
        finally {
            if ($null -ne $responseStream) {
                $responseStream.Dispose()
            }
        }
        Write-DebugLog ('TEXTURE_DOWNLOAD bytes=' + $bytesWritten)
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
    }
}

$tempTexturePath = $null
$tempBodyPath = $null
$requestStage = ''
try {
    $resolvedUsername = Trim-Text $Username
    $resolvedOutputDirectory = Trim-Text $OutputDirectory
    $requestedModel = Normalize-MinecraftSkinModel $Model
    $boundedTimeoutSeconds = [Math]::Max(1, [Math]::Min(60, $TimeoutSeconds))
    $timeoutMilliseconds = [int]($boundedTimeoutSeconds * 1000)
    if (-not [string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
        $script:DebugLogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
    }
    Write-DebugLog ("BEGIN username='" + $resolvedUsername + "' outputDirectory='" + $resolvedOutputDirectory + "' requestedModel='" + $requestedModel + "' timeoutSeconds=" + $boundedTimeoutSeconds)

    if ([string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
        throw (L 'Helper_Minecraft_OutputDirMissing' 'The player skin cache directory is empty.')
    }

    if ([string]::IsNullOrWhiteSpace($resolvedUsername)) {
        Write-DebugLog 'RESET because username is blank.'
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'RESET'
        Emit-ResultPairs
        exit 0
    }

    if (-not (Test-MinecraftUsername $resolvedUsername)) {
        throw (L 'Helper_Minecraft_InvalidUsername' 'Enter a valid Minecraft username.')
    }

    $requestStage = 'profileLookup'
    $profile = Resolve-MinecraftProfile -Username $resolvedUsername -TimeoutMilliseconds $timeoutMilliseconds
    if ($null -eq $profile) {
        throw 'NO_JAVA_PROFILE'
    }

    $canonicalUsername = Trim-Text ([string]$profile.Username)
    $resolvedUuid = Trim-Text ([string]$profile.Uuid)
    Write-DebugLog ("PROFILE_LOOKUP resolved username='" + $canonicalUsername + "' uuid='" + $resolvedUuid + "'")

    $sanitizedUsername = Sanitize-FileComponent $canonicalUsername
    if ([string]::IsNullOrWhiteSpace($sanitizedUsername)) {
        throw (L 'Helper_Minecraft_InvalidUsername' 'Enter a valid Minecraft username.')
    }

    [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

    $requestStage = 'textureLookup'
    $texture = Resolve-MinecraftSkinTexture -Uuid $resolvedUuid -FallbackModel $requestedModel -TimeoutMilliseconds $timeoutMilliseconds
    $renderModel = Normalize-MinecraftSkinModel ([string]$texture.Model)
    Write-DebugLog ("TEXTURE_LOOKUP resolved model='" + $renderModel + "' metadataModel='" + [string]$texture.MetadataModel + "' textureUrl='" + [string]$texture.Url + "'")

    $finalTexturePath = Join-Path $resolvedOutputDirectory ('MinecraftSkinTexture_' + $sanitizedUsername + '.png')
    $finalBodyPath = Join-Path $resolvedOutputDirectory ('MinecraftSkinBody_' + $sanitizedUsername + '.png')
    $tempTexturePath = Join-Path $resolvedOutputDirectory ('MinecraftSkinTexture_' + $sanitizedUsername + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    $tempBodyPath = Join-Path $resolvedOutputDirectory ('MinecraftSkinBody_' + $sanitizedUsername + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')

    $requestStage = 'textureDownload'
    Download-MinecraftSkinTexture -Url ([string]$texture.Url) -DestinationPath $tempTexturePath -TimeoutMilliseconds $timeoutMilliseconds
    Assert-ValidMinecraftSkinTexture -Path $tempTexturePath

    $rendererPath = [System.IO.Path]::Combine($PSScriptRoot, 'RenderMinecraftSkinTexture.ps1')
    if (-not [System.IO.File]::Exists($rendererPath)) {
        throw 'Renderer script is missing.'
    }

    $requestStage = 'textureRender'
    & $rendererPath -SourcePath $tempTexturePath -OutputPath $tempBodyPath -Model $renderModel
    if (-not (Test-PngSignature $tempBodyPath)) {
        throw 'Renderer returned an invalid PNG image.'
    }

    Move-Item -LiteralPath $tempTexturePath -Destination $finalTexturePath -Force
    $tempTexturePath = $null
    Move-Item -LiteralPath $tempBodyPath -Destination $finalBodyPath -Force
    $tempBodyPath = $null
    Write-DebugLog ("SUCCESS texturePath='" + [System.IO.Path]::GetFullPath($finalTexturePath) + "' bodyPath='" + [System.IO.Path]::GetFullPath($finalBodyPath) + "' model='" + $renderModel + "'")

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    Set-ResultPairValue -Key 'DMEL_USERNAME' -Value $canonicalUsername
    Set-ResultPairValue -Key 'DMEL_UUID' -Value $resolvedUuid
    Set-ResultPairValue -Key 'DMEL_IMAGEPATH' -Value ([System.IO.Path]::GetFullPath($finalBodyPath))
    Set-ResultPairValue -Key 'DMEL_TEXTUREPATH' -Value ([System.IO.Path]::GetFullPath($finalTexturePath))
    Set-ResultPairValue -Key 'DMEL_MODEL' -Value $renderModel
    Emit-ResultPairs
}
catch [System.Net.WebException] {
    $message = L 'Helper_Minecraft_DownloadFailed' 'Minecraft skin download failed. Please try again shortly.'
    if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
        if ($requestStage -eq 'profileLookup') {
            $message = L 'Helper_Minecraft_ProfileTimeout' 'Minecraft profile lookup timed out. Please try again shortly.'
        }
        elseif ($requestStage -eq 'textureLookup') {
            $message = L 'Helper_Minecraft_ProfileFailed' 'Minecraft profile lookup failed. Please try again shortly.'
        }
        else {
            $message = L 'Helper_Minecraft_DownloadTimeout' 'Minecraft skin download timed out. Please try again shortly.'
        }
    }
    elseif ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
        $statusCode = [int]([System.Net.HttpWebResponse]$_.Exception.Response).StatusCode
        if ($requestStage -eq 'profileLookup' -and ($statusCode -eq 204 -or $statusCode -eq 404)) {
            $message = L 'Helper_Minecraft_ProfileNotFound' 'No Java Edition Minecraft profile was found for that username.'
        }
        elseif (($requestStage -eq 'textureLookup' -or $requestStage -eq 'textureDownload') -and $statusCode -eq 404) {
            $message = L 'Helper_Minecraft_SkinNotFound' 'No Minecraft skin was found for that username.'
        }
        elseif ($requestStage -eq 'profileLookup' -or $requestStage -eq 'textureLookup') {
            $message = L 'Helper_Minecraft_ProfileFailed' 'Minecraft profile lookup failed. Please try again shortly.'
        }
    }
    Write-DebugLog ('WEB_EXCEPTION stage=' + $requestStage + ' message=' + $message + ' raw=' + [string]$_.Exception.Message)
    Show-ErrorDialog $message
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $message
    Emit-ResultPairs
}
catch {
    $rawMessage = [string]$_.Exception.Message
    $outputDirMissingMessage = L 'Helper_Minecraft_OutputDirMissing' 'The player skin cache directory is empty.'
    $invalidUsernameMessage = L 'Helper_Minecraft_InvalidUsername' 'Enter a valid Minecraft username.'

    if ($rawMessage -eq 'NO_JAVA_PROFILE') {
        $message = L 'Helper_Minecraft_ProfileNotFound' 'No Java Edition Minecraft profile was found for that username.'
    }
    elseif ($rawMessage -eq 'NO_SKIN_TEXTURE') {
        $message = L 'Helper_Minecraft_SkinNotFound' 'No Minecraft skin was found for that username.'
    }
    elseif ($rawMessage -eq $outputDirMissingMessage -or $rawMessage -eq $invalidUsernameMessage) {
        $message = $rawMessage
    }
    elseif ($rawMessage -like 'Minecraft profile lookup returned *' -or $rawMessage -like 'Minecraft texture lookup returned *') {
        $message = L 'Helper_Minecraft_ProfileFailed' 'Minecraft profile lookup failed. Please try again shortly.'
    }
    elseif ($rawMessage -like 'Minecraft texture download returned *' -or $rawMessage -like 'Minecraft skin texture *' -or $rawMessage -like 'Minecraft skin image exceeded *') {
        $message = L 'Helper_Minecraft_DownloadFailed' 'Minecraft skin download failed. Please try again shortly.'
    }
    else {
        $message = L 'Helper_Minecraft_UnexpectedError' 'An unexpected error occurred while processing the Minecraft skin.'
    }
    Write-DebugLog ('EXCEPTION stage=' + $requestStage + ' message=' + $message + ' raw=' + $rawMessage)
    Show-ErrorDialog $message
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $message
    Emit-ResultPairs
}
finally {
    foreach ($tempPath in @($tempTexturePath, $tempBodyPath)) {
        if ($tempPath -and [System.IO.File]::Exists($tempPath)) {
            Write-DebugLog ("Cleaning tempPath='" + $tempPath + "'")
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
