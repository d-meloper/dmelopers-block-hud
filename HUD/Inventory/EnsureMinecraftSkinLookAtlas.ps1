param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [string]$CacheKey = '',
    [ValidateSet('wide', 'slim')]
    [string]$Model = 'wide'
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$cacheModulePath = @(
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..\..\@Resources\Defaults\Runtime\helpers\MinecraftSkinLookAtlasCache.Common.ps1')),
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..\@Resources\Defaults\Runtime\helpers\MinecraftSkinLookAtlasCache.Common.ps1'))
) | Where-Object { [System.IO.File]::Exists($_) } | Select-Object -First 1

function Convert-DmelValueToSingleLine {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $singleLine = ([string]$Value).Replace("`r", ' ').Replace("`n", ' ')
    while ($singleLine.Contains('  ')) {
        $singleLine = $singleLine.Replace('  ', ' ')
    }
    return $singleLine.Trim()
}

function Write-DmelResult {
    param(
        [string]$Status,
        [string]$AtlasPath,
        [string]$CacheHit,
        [string]$Message
    )

    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    try {
        $stdout.AutoFlush = $true
        $stdout.WriteLine('DMEL_STATUS=' + (Convert-DmelValueToSingleLine $Status))
        $stdout.WriteLine('DMEL_ATLASPATH=' + (Convert-DmelValueToSingleLine $AtlasPath))
        $stdout.WriteLine('DMEL_CACHE_HIT=' + (Convert-DmelValueToSingleLine $CacheHit))
        $stdout.WriteLine('DMEL_MESSAGE=' + (Convert-DmelValueToSingleLine $Message))
    }
    finally {
        $stdout.Dispose()
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($cacheModulePath)) {
        throw 'Minecraft skin atlas cache module is missing.'
    }
    . $cacheModulePath

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
        if ($null -ne $sourceImage) {
            $sourceImage.Dispose()
        }
    }

    $rendererPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..\Settings\RenderMinecraftSkinTexture.ps1'))
    $ensureResult = Invoke-BlockHudMinecraftSkinLookAtlasEnsure `
        -SourcePath $resolvedSourcePath `
        -OutputDirectory $resolvedOutputDirectory `
        -CacheKey $CacheKey `
        -Model $Model `
        -RendererPath $rendererPath
    foreach ($warning in @($ensureResult.Warnings)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$warning)) {
            Write-Warning ([string]$warning)
        }
    }
    Write-DmelResult -Status 'OK' -AtlasPath ([string]$ensureResult.AtlasPath) -CacheHit $(if ($ensureResult.CacheHit) { '1' } else { '0' }) -Message ''
    exit 0
}
catch {
    Write-DmelResult -Status 'ERROR' -AtlasPath '' -CacheHit '0' -Message ([string]$_.Exception.Message)
    exit 1
}
