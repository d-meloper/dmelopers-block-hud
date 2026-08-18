param(
    [string]$OutputDirectory = '',
    [ValidateSet('wide', 'slim')]
    [string]$Model = 'wide',
    [string]$SourcePath = '',
    [string]$Username = 'A',
    [string]$CacheKey = '',
    [string]$InitialDirectory = '',
    [switch]$AcceptRenderedBody
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$entrypointScriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$localizationCommonCandidates = @(
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($entrypointScriptRoot, '..', '..', 'Utilities', 'tools', 'Localization.Common.ps1')),
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($entrypointScriptRoot, '..', 'tools', 'Localization.Common.ps1'))
)
$localizationCommonPath = @($localizationCommonCandidates | Where-Object { [System.IO.File]::Exists($_) } | Select-Object -First 1)[0]
if ([string]::IsNullOrWhiteSpace($localizationCommonPath)) {
    throw 'Localization helper module is missing.'
}
. $localizationCommonPath

Add-Type -AssemblyName System.Drawing

function Resolve-MinecraftSkinHelperRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptRoot,
        [Parameter(Mandatory = $true)][string]$RequiredRelativePath
    )

    $candidateRoots = @(
        [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ScriptRoot, '..', '..')),
        [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ScriptRoot, '..'))
    )
    foreach ($candidateRoot in $candidateRoots) {
        if ([System.IO.File]::Exists([System.IO.Path]::Combine($candidateRoot, $RequiredRelativePath))) {
            return $candidateRoot
        }
    }

    return Get-LocalizationSkinRoot -ScriptRoot $ScriptRoot
}

$atlasCacheRelativePath = '@Resources\Defaults\Runtime\helpers\MinecraftSkinLookAtlasCache.Common.ps1'
$skinRoot = Resolve-MinecraftSkinHelperRoot -ScriptRoot $entrypointScriptRoot -RequiredRelativePath $atlasCacheRelativePath
$languageCode = Read-LanguageCode -SkinRoot $skinRoot
$locTable = Read-LocaleTable -SkinRoot $skinRoot -LanguageCode $languageCode
$script:DebugLogPath = Get-BlockHudCanonicalLogPath -Root $skinRoot -ScriptRoot $entrypointScriptRoot

function L([string]$Key, [string]$Fallback = '') {
    return Get-LocalizedText -Table $locTable -Key $Key -Fallback $Fallback
}

$resultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_USERNAME = ''
    DMEL_IMAGEPATH = ''
    DMEL_TEXTUREPATH = ''
    DMEL_MODEL = ''
    DMEL_CACHEKEY = ''
    DMEL_ATLASPATH = ''
    DMEL_ATLASREADY = '0'
    DMEL_ATLAS_REQUIRED = '0'
    DMEL_MESSAGE = ''
    DMEL_LOGPATH = ''
}

function Set-ResultPairValue {
    param(
        [string]$Key,
        [AllowNull()][string]$Value
    )

    $resultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
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
    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    try {
        $stdout.AutoFlush = $true
        foreach ($key in $resultPairs.Keys) {
            $stdout.WriteLine($key + '=' + (Convert-ResultPairValueToSingleLine -Value $resultPairs[$key]))
        }
    }
    finally {
        $stdout.Dispose()
    }
}

function Write-DebugLog {
    param([string]$Message)

    try {
        $line = ('[{0}] [MinecraftSkinFile] {1}' -f ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')), [string]$Message)
        [void](Write-BlockHudCanonicalLogBlock -Path $script:DebugLogPath -Type 'MinecraftSkinFile' -Lines @($line) -Encoding $utf8NoBom)
    }
    catch {
    }
}

function Emit-CancelResult {
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'CANCEL'
    Emit-ResultPairs
}

function Emit-ErrorResult {
    param(
        [string]$Message,
        [string]$LogPath = ''
    )

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $Message
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $LogPath
    Emit-ResultPairs
}

function Test-PngSignature {
    param([string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return $false
    }

    $signature = New-Object byte[] 8
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Read($signature, 0, $signature.Length) -ne 8) {
            return $false
        }
    }
    finally {
        $stream.Dispose()
    }

    $expected = 137, 80, 78, 71, 13, 10, 26, 10
    for ($i = 0; $i -lt $expected.Length; $i++) {
        if ($signature[$i] -ne $expected[$i]) {
            return $false
        }
    }

    return $true
}

function Get-PngDimensions {
    param([string]$Path)

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

function Get-DefaultPickerInitialDirectory {
    $downloadsKnownFolderId = '{374DE290-123F-4565-9164-39C4925E467B}'
    foreach ($registryPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    )) {
        try {
            $value = [string]((Get-ItemProperty -LiteralPath $registryPath -Name $downloadsKnownFolderId -ErrorAction Stop).$downloadsKnownFolderId)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $expandedPath = [Environment]::ExpandEnvironmentVariables($value)
                if ([System.IO.Directory]::Exists($expandedPath)) {
                    return [System.IO.Path]::GetFullPath($expandedPath)
                }
            }
        }
        catch {
        }
    }

    $userProfilePath = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($userProfilePath)) {
        $downloadsPath = [System.IO.Path]::Combine($userProfilePath, 'Downloads')
        if ([System.IO.Directory]::Exists($downloadsPath)) {
            return [System.IO.Path]::GetFullPath($downloadsPath)
        }
    }

    $picturesPath = [Environment]::GetFolderPath('MyPictures')
    if (-not [string]::IsNullOrWhiteSpace($picturesPath) -and [System.IO.Directory]::Exists($picturesPath)) {
        return [System.IO.Path]::GetFullPath($picturesPath)
    }

    return ''
}

function Resolve-SelectedSkinPath {
    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        return [System.IO.Path]::GetFullPath($SourcePath)
    }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    if ($AcceptRenderedBody) {
        $dialog.Title = L 'Helper_MinecraftSkinFile_TextureOrCachedBodyTitle' 'Select a Minecraft skin texture or cached player image'
        $dialog.Filter = (L 'Helper_MinecraftSkinFile_TextureOrCachedBodyFilterLabel' 'PNG skin texture or cached player image') + ' (*.png)|*.png'
    }
    else {
        $dialog.Title = L 'Helper_MinecraftSkinFile_Title' 'Select a Minecraft skin texture'
        $dialog.Filter = (L 'Helper_MinecraftSkinFile_FilterLabel' 'PNG skin texture') + ' (*.png)|*.png'
    }
    $dialog.FilterIndex = 1
    $dialog.Multiselect = $false
    $dialog.CheckFileExists = $true
    $dialog.RestoreDirectory = $true

    if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and [System.IO.Directory]::Exists($InitialDirectory)) {
        $dialog.InitialDirectory = [System.IO.Path]::GetFullPath($InitialDirectory)
    }
    else {
        $defaultInitialDirectory = Get-DefaultPickerInitialDirectory
        if (-not [string]::IsNullOrWhiteSpace($defaultInitialDirectory)) {
            $dialog.InitialDirectory = $defaultInitialDirectory
        }
    }

    $ownerForm = New-Object System.Windows.Forms.Form
    $ownerForm.ShowInTaskbar = $false
    $ownerForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $ownerForm.Location = New-Object System.Drawing.Point(-32000, -32000)
    $ownerForm.Size = New-Object System.Drawing.Size(1, 1)
    $ownerForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $ownerForm.Opacity = 0
    $ownerForm.TopMost = $true
    $ownerForm.Add_Shown({
        $ownerForm.TopMost = $true
        $ownerForm.BringToFront()
        $ownerForm.Activate()
    })
    try {
        $ownerForm.Show()
        $ownerForm.BringToFront()
        $ownerForm.Activate()
        if ($dialog.ShowDialog($ownerForm) -ne [System.Windows.Forms.DialogResult]::OK) {
            return ''
        }
        return [System.IO.Path]::GetFullPath($dialog.FileName)
    }
    finally {
        $ownerForm.Dispose()
        $dialog.Dispose()
    }
}

function Sanitize-FileComponent {
    param([string]$Value)

    $resolved = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return ''
    }

    $pattern = '[<>:' + [char]34 + '/\\|?*\x00-\x1F]'
    $resolved = [System.Text.RegularExpressions.Regex]::Replace($resolved, $pattern, '_')
    return $resolved.Trim()
}

function Resolve-CacheKey {
    param(
        [string]$SelectedPath,
        [string]$ResolvedOutputDirectory,
        [switch]$RenderedBody
    )

    $resolvedCacheKey = Sanitize-FileComponent -Value $CacheKey
    if (-not [string]::IsNullOrWhiteSpace($resolvedCacheKey)) {
        return $resolvedCacheKey
    }

    try {
        $fullSelectedPath = [System.IO.Path]::GetFullPath($SelectedPath)
        $fullOutputDirectory = [System.IO.Path]::GetFullPath($ResolvedOutputDirectory).TrimEnd('\', '/')
        $selectedDirectory = ([System.IO.Path]::GetDirectoryName($fullSelectedPath)).TrimEnd('\', '/')
        $selectedName = [System.IO.Path]::GetFileName($fullSelectedPath)
        $match = [System.Text.RegularExpressions.Regex]::Match($selectedName, '^MinecraftSkinTexture_(.+)\.png$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            $match = [System.Text.RegularExpressions.Regex]::Match($selectedName, '^MinecraftSkinBody_(.+)\.png$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        if ($match.Success -and ($RenderedBody -or $selectedDirectory -ieq $fullOutputDirectory)) {
            $fromFileName = Sanitize-FileComponent -Value $match.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($fromFileName)) {
                return $fromFileName
            }
        }
    }
    catch {
    }

    $originalStem = Sanitize-FileComponent -Value ([System.IO.Path]::GetFileNameWithoutExtension($SelectedPath))
    if (-not [string]::IsNullOrWhiteSpace($originalStem)) {
        return $originalStem
    }

    $resolvedUsername = Sanitize-FileComponent -Value $Username
    return $(if ([string]::IsNullOrWhiteSpace($resolvedUsername)) { 'A' } else { $resolvedUsername })
}

function Test-IsPathInsideDirectory {
    param(
        [string]$Path,
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Directory)) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $fullDirectory = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
        $pathDirectory = ([System.IO.Path]::GetDirectoryName($fullPath)).TrimEnd('\', '/')
        return [string]::Equals($pathDirectory, $fullDirectory, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-InvalidMinecraftSkinSelectionMessage {
    if ($AcceptRenderedBody) {
        return (L 'Helper_MinecraftSkinFile_InvalidTextureOrCachedBody' 'Select a 64x64 PNG skin texture or a 130x260 static player image.')
    }

    return (L 'Helper_MinecraftSkinFile_InvalidDimensions' 'Attach a correct 64x64 PNG skin texture.')
}

$tempTexturePath = $null
$tempBodyPath = $null
$tempAtlasPath = $null
$tempMarkerPath = $null

try {
    $resolvedOutputDirectory = ([string]$OutputDirectory).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
        throw (L 'Helper_Minecraft_OutputDirMissing' 'The player skin cache directory is empty.')
    }
    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($resolvedOutputDirectory)

    Write-DebugLog ("BEGIN outputDirectory='$resolvedOutputDirectory' model='$Model' username='$Username' cacheKey='$CacheKey' sourcePath='$SourcePath' acceptRenderedBody='$AcceptRenderedBody'")

    $selectedPath = Resolve-SelectedSkinPath
    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        Write-DebugLog 'CANCEL'
        Emit-CancelResult
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($selectedPath) -or -not [System.IO.File]::Exists($selectedPath)) {
        throw (L 'Helper_MinecraftSkinFile_InvalidTexture' 'Select a valid 64x64 PNG Minecraft skin texture.')
    }
    if ([System.IO.Path]::GetExtension($selectedPath) -ine '.png') {
        throw (L 'Helper_MinecraftSkinFile_UnsupportedType' 'Select a PNG Minecraft skin texture file.')
    }
    if (-not (Test-PngSignature -Path $selectedPath)) {
        throw (L 'Helper_MinecraftSkinFile_InvalidPng' 'The selected file is not a valid PNG image.')
    }

    try {
        $selectedSize = Get-PngDimensions -Path $selectedPath
    }
    catch {
        Write-DebugLog ('PNG dimension read failed: ' + [string]$_.Exception.Message)
        throw (L 'Helper_MinecraftSkinFile_InvalidPng' 'The selected file is not a valid PNG image.')
    }

    [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

    $resolvedCacheKey = Resolve-CacheKey -SelectedPath $selectedPath -ResolvedOutputDirectory $resolvedOutputDirectory -RenderedBody:($AcceptRenderedBody -and $selectedSize.Width -eq 130 -and $selectedSize.Height -eq 260)
    $resolvedUsername = ([string]$Username).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedUsername)) {
        $resolvedUsername = $resolvedCacheKey
    }

    $texturePath = [System.IO.Path]::Combine($resolvedOutputDirectory, ('MinecraftSkinTexture_' + $resolvedCacheKey + '.png'))
    $bodyPath = [System.IO.Path]::Combine($resolvedOutputDirectory, ('MinecraftSkinBody_' + $resolvedCacheKey + '.png'))
    $atlasCacheModulePath = Join-Path $skinRoot $atlasCacheRelativePath
    if (-not [System.IO.File]::Exists($atlasCacheModulePath)) {
        throw 'Minecraft skin atlas cache module is missing.'
    }
    . $atlasCacheModulePath
    $atlasPath = Get-BlockHudMinecraftSkinLookAtlasPath -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey -Model $Model
    $markerPath = Get-BlockHudMinecraftSkinRenderMarkerPath -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey

    if ($AcceptRenderedBody -and $selectedSize.Width -eq 130 -and $selectedSize.Height -eq 260) {
        $resolvedBodyPath = [System.IO.Path]::GetFullPath($bodyPath)
        if (-not [string]::Equals([System.IO.Path]::GetFullPath($selectedPath), $resolvedBodyPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tempBodyPath = $bodyPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
            [System.IO.File]::Copy($selectedPath, $tempBodyPath, $true)
            $copiedBodySize = Get-PngDimensions -Path $tempBodyPath
            if ($copiedBodySize.Width -ne 130 -or $copiedBodySize.Height -ne 260) {
                throw (Get-InvalidMinecraftSkinSelectionMessage)
            }
            Install-BlockHudFileSetTransactionally -Entries @(
                [PSCustomObject]@{ SourcePath = $tempBodyPath; DestinationPath = $resolvedBodyPath }
            )
            $tempBodyPath = $null
        }

        $resolvedTexturePath = if ([System.IO.File]::Exists($texturePath)) { [System.IO.Path]::GetFullPath($texturePath) } else { '' }
        $resolvedUsername = ([string]$Username).Trim()
        if ([string]::IsNullOrWhiteSpace($resolvedUsername)) { $resolvedUsername = 'A' }

        $bodyAtlasResult = Resolve-BlockHudMinecraftSkinLookAtlas -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey -Model $Model -TexturePath $resolvedTexturePath -BodyPath $resolvedBodyPath -AllowLegacyBodyOnly:([string]::IsNullOrWhiteSpace($resolvedTexturePath))
        $bodyAtlasReady = $bodyAtlasResult.Ready -eq $true
        foreach ($migrationWarning in @($bodyAtlasResult.Warnings)) {
            Write-DebugLog ('ATLAS_MIGRATION_WARNING ' + [string]$migrationWarning)
        }
        Write-DebugLog ("SUCCESS rendered-body username='$resolvedUsername' cacheKey='$resolvedCacheKey' texturePath='$resolvedTexturePath' bodyPath='$resolvedBodyPath' atlasPath='$([string]$bodyAtlasResult.AtlasPath)' atlasReady='$bodyAtlasReady' model='$Model'")
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
        Set-ResultPairValue -Key 'DMEL_USERNAME' -Value $resolvedUsername
        Set-ResultPairValue -Key 'DMEL_IMAGEPATH' -Value $resolvedBodyPath
        Set-ResultPairValue -Key 'DMEL_TEXTUREPATH' -Value $resolvedTexturePath
        Set-ResultPairValue -Key 'DMEL_MODEL' -Value $Model
        Set-ResultPairValue -Key 'DMEL_CACHEKEY' -Value $resolvedCacheKey
        Set-ResultPairValue -Key 'DMEL_ATLASPATH' -Value $(if ($bodyAtlasReady) { [string]$bodyAtlasResult.AtlasPath } else { '' })
        Set-ResultPairValue -Key 'DMEL_ATLASREADY' -Value $(if ($bodyAtlasReady) { '1' } else { '0' })
        Set-ResultPairValue -Key 'DMEL_ATLAS_REQUIRED' -Value $(if (-not $bodyAtlasReady -and -not [string]::IsNullOrWhiteSpace($resolvedTexturePath)) { '1' } else { '0' })
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:DebugLogPath
        Emit-ResultPairs
        exit 0
    }

    if ($selectedSize.Width -ne 64 -or $selectedSize.Height -ne 64) {
        Write-DebugLog ("Invalid texture dimensions: $($selectedSize.Width)x$($selectedSize.Height)")
        throw (Get-InvalidMinecraftSkinSelectionMessage)
    }

    $tempTexturePath = $texturePath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $tempBodyPath = $bodyPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $tempMarkerPath = $markerPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'

    Copy-Item -LiteralPath $selectedPath -Destination $tempTexturePath -Force

    $rendererPath = [System.IO.Path]::Combine($entrypointScriptRoot, 'RenderMinecraftSkinTexture.ps1')
    if (-not [System.IO.File]::Exists($rendererPath)) {
        throw 'Renderer script is missing.'
    }

    $cacheHit = Test-BlockHudMinecraftSkinStaticCache `
        -IncomingTexturePath $tempTexturePath `
        -InstalledTexturePath $texturePath `
        -BodyPath $bodyPath `
        -MarkerPath $markerPath `
        -Model $Model

    if ($cacheHit) {
        Remove-Item -LiteralPath $tempTexturePath -Force
        $tempTexturePath = $null
    }
    else {
        & $rendererPath -SourcePath $tempTexturePath -OutputPath $tempBodyPath -Model $Model
        if (-not (Test-BlockHudPngDimensions -Path $tempBodyPath -Width 130 -Height 260)) {
            throw 'Renderer returned an invalid static PNG image.'
        }
        Write-BlockHudMinecraftSkinRenderMarker -Path $tempMarkerPath -Model $Model -TexturePath $tempTexturePath
        if (-not (Test-BlockHudMinecraftSkinRenderMarker -Path $tempMarkerPath -Model $Model -TexturePath $tempTexturePath)) {
            throw 'Renderer returned an invalid model cache marker.'
        }

        Install-BlockHudFileSetTransactionally -Entries @(
            [PSCustomObject]@{ SourcePath = $tempTexturePath; DestinationPath = $texturePath },
            [PSCustomObject]@{ SourcePath = $tempBodyPath; DestinationPath = $bodyPath },
            [PSCustomObject]@{ SourcePath = $tempMarkerPath; DestinationPath = $markerPath }
        )
        $tempTexturePath = $null
        $tempBodyPath = $null
        $tempMarkerPath = $null
    }

    $atlasResult = Resolve-BlockHudMinecraftSkinLookAtlas -OutputDirectory $resolvedOutputDirectory -CacheKey $resolvedCacheKey -Model $Model -TexturePath $texturePath -BodyPath $bodyPath
    $atlasReady = $atlasResult.Ready -eq $true
    foreach ($migrationWarning in @($atlasResult.Warnings)) {
        Write-DebugLog ('ATLAS_MIGRATION_WARNING ' + [string]$migrationWarning)
    }
    Write-DebugLog ("SUCCESS username='$resolvedUsername' cacheKey='$resolvedCacheKey' texturePath='$texturePath' bodyPath='$bodyPath' atlasPath='$([string]$atlasResult.AtlasPath)' atlasReady='$atlasReady' model='$Model' staticCacheHit='$cacheHit'")
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'OK'
    Set-ResultPairValue -Key 'DMEL_USERNAME' -Value $resolvedUsername
    Set-ResultPairValue -Key 'DMEL_IMAGEPATH' -Value $bodyPath
    Set-ResultPairValue -Key 'DMEL_TEXTUREPATH' -Value $texturePath
    Set-ResultPairValue -Key 'DMEL_MODEL' -Value $Model
    Set-ResultPairValue -Key 'DMEL_CACHEKEY' -Value $resolvedCacheKey
    Set-ResultPairValue -Key 'DMEL_ATLASPATH' -Value $(if ($atlasReady) { [string]$atlasResult.AtlasPath } else { '' })
    Set-ResultPairValue -Key 'DMEL_ATLASREADY' -Value $(if ($atlasReady) { '1' } else { '0' })
    Set-ResultPairValue -Key 'DMEL_ATLAS_REQUIRED' -Value $(if ($atlasReady) { '0' } else { '1' })
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:DebugLogPath
    Emit-ResultPairs
}
catch {
    $rawMessage = [string]$_.Exception.Message
    Write-DebugLog ('ERROR raw=' + $rawMessage)

    $knownMessages = @(
        (L 'Helper_Minecraft_OutputDirMissing' 'The player skin cache directory is empty.'),
        (L 'Helper_MinecraftSkinFile_InvalidTexture' 'Select a valid 64x64 PNG Minecraft skin texture.'),
        (L 'Helper_MinecraftSkinFile_UnsupportedType' 'Select a PNG Minecraft skin texture file.'),
        (L 'Helper_MinecraftSkinFile_InvalidPng' 'The selected file is not a valid PNG image.'),
        (L 'Helper_MinecraftSkinFile_InvalidDimensions' 'Attach a correct 64x64 PNG skin texture.'),
        (Get-InvalidMinecraftSkinSelectionMessage)
    )

    if ($knownMessages -contains $rawMessage) {
        $message = $rawMessage
    }
    else {
        $message = L 'Helper_MinecraftSkinFile_ImportFailed' 'The selected skin texture could not be imported. Attach a correct 64x64 PNG skin texture.'
    }

    Emit-ErrorResult -Message $message -LogPath $script:DebugLogPath
}
finally {
    foreach ($tempPath in @($tempTexturePath, $tempBodyPath, $tempAtlasPath, $tempMarkerPath)) {
        if (-not [string]::IsNullOrWhiteSpace($tempPath) -and [System.IO.File]::Exists($tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
