param(
    [string]$Username = '',
    [string]$OutputDirectory = '',
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

$skinRoot = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$languageCode = Read-LanguageCode -SkinRoot $skinRoot
$locTable = Read-LocaleTable -SkinRoot $skinRoot -LanguageCode $languageCode

function L([string]$Key, [string]$Fallback = '') {
    return Get-LocalizedText -Table $locTable -Key $Key -Fallback $Fallback
}

function Write-OutputPair([string]$Key, [string]$Value) {
    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($Key + '=' + [string]$Value)
    }
    finally {
        $writer.Dispose()
    }
}

function Trim-Text([string]$Value) {
    return ([string]$Value).Trim()
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
        $request.UserAgent = 'DMeloper-BlockHUD/1.1'
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

$tempPath = $null
$response = $null
$requestStage = ''
try {
    $resolvedUsername = Trim-Text $Username
    $resolvedOutputDirectory = Trim-Text $OutputDirectory
    $boundedTimeoutSeconds = [Math]::Max(1, [Math]::Min(60, $TimeoutSeconds))
    $timeoutMilliseconds = [int]($boundedTimeoutSeconds * 1000)
    if (-not [string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
        $script:DebugLogPath = Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
    }
    Write-DebugLog ("BEGIN username='" + $resolvedUsername + "' outputDirectory='" + $resolvedOutputDirectory + "' timeoutSeconds=" + $boundedTimeoutSeconds)

    if ([string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
        throw (L 'Helper_Minecraft_OutputDirMissing' 'The player skin cache directory is empty.')
    }

    if ([string]::IsNullOrWhiteSpace($resolvedUsername)) {
        Write-DebugLog 'RESET because username is blank.'
        Write-OutputPair 'DMEL_STATUS' 'RESET'
        exit 0
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

    $finalPath = Join-Path $resolvedOutputDirectory ('MinecraftSkinBody_' + $sanitizedUsername + '.png')
    $tempPath = Join-Path $resolvedOutputDirectory ('MinecraftSkinBody_' + $sanitizedUsername + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    $url = 'https://mineskin.eu/armor/body/' + [System.Uri]::EscapeDataString($resolvedUuid) + '/130.png'
    $requestStage = 'imageDownload'
    Write-DebugLog ("Resolved sanitizedUsername='" + $sanitizedUsername + "' finalPath='" + $finalPath + "' uuidUrl='" + $url + "'")

    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.Method = 'GET'
    $request.UserAgent = 'DMeloper-BlockHUD/1.1'
    $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $request.Timeout = $timeoutMilliseconds
    $request.ReadWriteTimeout = $timeoutMilliseconds

    $response = [System.Net.HttpWebResponse]$request.GetResponse()
    Write-DebugLog ('HTTP status=' + [int]$response.StatusCode)
    if ([int]$response.StatusCode -ne 200) {
        throw ('MineSkin returned HTTP ' + [int]$response.StatusCode)
    }

    $responseStream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Create($tempPath)
    try {
        $responseStream.CopyTo($fileStream)
    }
    finally {
        if ($null -ne $responseStream) {
            $responseStream.Dispose()
        }
        $fileStream.Dispose()
    }

    if (-not (Test-PngSignature $tempPath)) {
        Write-DebugLog ("PNG signature validation failed for tempPath='" + $tempPath + "'")
        throw 'MineSkin returned an invalid PNG image.'
    }

    Move-Item -LiteralPath $tempPath -Destination $finalPath -Force
    $tempPath = $null
    Write-DebugLog ("SUCCESS finalPath='" + [System.IO.Path]::GetFullPath($finalPath) + "' length=" + ([System.IO.FileInfo]$finalPath).Length)

    Write-OutputPair 'DMEL_STATUS' 'OK'
    Write-OutputPair 'DMEL_USERNAME' $canonicalUsername
    Write-OutputPair 'DMEL_UUID' $resolvedUuid
    Write-OutputPair 'DMEL_IMAGEPATH' ([System.IO.Path]::GetFullPath($finalPath))
    Write-OutputPair 'DMEL_DEBUGLOG' (Get-DebugLogOutputValue)
}
catch [System.Net.WebException] {
    $message = L 'Helper_Minecraft_DownloadFailed' 'Minecraft skin download failed. Please try again shortly.'
    if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
        if ($requestStage -eq 'profileLookup') {
            $message = L 'Helper_Minecraft_ProfileTimeout' 'Minecraft profile lookup timed out. Please try again shortly.'
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
        elseif ($requestStage -eq 'imageDownload' -and $statusCode -eq 404) {
            $message = L 'Helper_Minecraft_SkinNotFound' 'No Minecraft skin was found for that username.'
        }
        else {
            if ($requestStage -eq 'profileLookup') {
                $message = L 'Helper_Minecraft_ProfileFailed' 'Minecraft profile lookup failed. Please try again shortly.'
            }
            else {
                $message = L 'Helper_Minecraft_DownloadFailed' 'Minecraft skin download failed. Please try again shortly.'
            }
        }
    }
    Write-DebugLog ('WEB_EXCEPTION message=' + $message + ' raw=' + [string]$_.Exception.Message)
    Show-ErrorDialog $message
    Write-OutputPair 'DMEL_STATUS' 'ERROR'
    Write-OutputPair 'DMEL_MESSAGE' $message
    Write-OutputPair 'DMEL_DEBUGLOG' (Get-DebugLogOutputValue)
}
catch {
    $rawMessage = [string]$_.Exception.Message
    $outputDirMissingMessage = L 'Helper_Minecraft_OutputDirMissing' 'The player skin cache directory is empty.'
    $invalidUsernameMessage = L 'Helper_Minecraft_InvalidUsername' 'Enter a valid Minecraft username.'

    if ($rawMessage -eq 'NO_JAVA_PROFILE') {
        $message = L 'Helper_Minecraft_ProfileNotFound' 'No Java Edition Minecraft profile was found for that username.'
    }
    elseif ($rawMessage -eq $outputDirMissingMessage -or $rawMessage -eq $invalidUsernameMessage) {
        $message = $rawMessage
    }
    elseif ($rawMessage -like 'Minecraft profile lookup returned *') {
        $message = L 'Helper_Minecraft_ProfileFailed' 'Minecraft profile lookup failed. Please try again shortly.'
    }
    elseif ($rawMessage -like 'MineSkin returned *') {
        $message = L 'Helper_Minecraft_DownloadFailed' 'Minecraft skin download failed. Please try again shortly.'
    }
    else {
        $message = L 'Helper_Minecraft_UnexpectedError' 'An unexpected error occurred while processing the Minecraft skin.'
    }
    Write-DebugLog ('EXCEPTION message=' + $message + ' raw=' + $rawMessage)
    Show-ErrorDialog $message
    Write-OutputPair 'DMEL_STATUS' 'ERROR'
    Write-OutputPair 'DMEL_MESSAGE' $message
    Write-OutputPair 'DMEL_DEBUGLOG' (Get-DebugLogOutputValue)
}
finally {
    if ($null -ne $response) {
        $response.Dispose()
    }
    if ($tempPath -and [System.IO.File]::Exists($tempPath)) {
        Write-DebugLog ("Cleaning tempPath='" + $tempPath + "'")
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}
