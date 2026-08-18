param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$CacheKey,
    [ValidateSet('wide', 'slim')][string]$Model = 'wide',
    [Parameter(Mandatory = $true)][string]$BodyPath,
    [Parameter(Mandatory = $true)][string]$RequestToken,
    [Parameter(Mandatory = $true)][string]$ProgressDirectory
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
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace("`r", ' ').Replace("`n", ' ').Trim()
}

function Write-DmelResult {
    param([string]$Status, [string]$AtlasPath, [string]$CacheHit, [string]$Message)
    $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine('DMEL_STATUS=' + (Convert-DmelValueToSingleLine $Status))
        $writer.WriteLine('DMEL_ATLASPATH=' + (Convert-DmelValueToSingleLine $AtlasPath))
        $writer.WriteLine('DMEL_CACHE_HIT=' + (Convert-DmelValueToSingleLine $CacheHit))
        $writer.WriteLine('DMEL_MESSAGE=' + (Convert-DmelValueToSingleLine $Message))
        $writer.WriteLine('DMEL_REQUEST_TOKEN=' + (Convert-DmelValueToSingleLine $RequestToken))
    }
    finally {
        $writer.Dispose()
    }
}

$safeToken = [System.Text.RegularExpressions.Regex]::Replace(([string]$RequestToken).Trim(), '[^A-Za-z0-9_-]', '_')
$resolvedProgressDirectory = $null
try {
    if ([string]::IsNullOrWhiteSpace($cacheModulePath)) {
        throw 'Minecraft skin atlas cache module is missing.'
    }
    . $cacheModulePath
    $resolvedProgressDirectory = [System.IO.Path]::GetFullPath(([string]$ProgressDirectory).Trim())
    $rendererPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, 'RenderMinecraftSkinTexture.ps1'))
    $result = Invoke-BlockHudMinecraftSkinLookAtlasEnsure `
        -SourcePath $SourcePath `
        -OutputDirectory $OutputDirectory `
        -CacheKey $CacheKey `
        -Model $Model `
        -BodyPath $BodyPath `
        -RendererPath $rendererPath `
        -RequestToken $RequestToken `
        -ProgressDirectory $resolvedProgressDirectory
    Write-DmelResult -Status 'OK' -AtlasPath ([string]$result.AtlasPath) -CacheHit $(if ($result.CacheHit) { '1' } else { '0' }) -Message ''
    exit 0
}
catch {
    Write-DmelResult -Status 'ERROR' -AtlasPath '' -CacheHit '0' -Message ([string]$_.Exception.Message)
    exit 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($resolvedProgressDirectory) -and -not [string]::IsNullOrWhiteSpace($safeToken) -and [System.IO.Directory]::Exists($resolvedProgressDirectory)) {
        foreach ($path in [System.IO.Directory]::EnumerateFiles($resolvedProgressDirectory, ('MinecraftSkinAtlasProgress_' + $safeToken + '_*'))) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}
