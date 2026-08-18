param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [ValidateSet('wide', 'slim')]
    [string]$Model = 'wide',
    [ValidateSet('Static', 'LookAtlas')]
    [string]$RenderMode = 'Static',
    [ValidateRange(1, 1024)]
    [int]$FrameWidth = 130,
    [ValidateRange(1, 1024)]
    [int]$FrameHeight = 260,
    [string]$ProgressDirectory = '',
    [string]$RequestToken = ''
)

$ErrorActionPreference = 'Stop'

$rendererModulePath = @(
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..\..\@Resources\Defaults\Runtime\helpers\MinecraftSkinRenderer.Common.ps1')),
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..\@Resources\Defaults\Runtime\helpers\MinecraftSkinRenderer.Common.ps1'))
) | Where-Object { [System.IO.File]::Exists($_) } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($rendererModulePath)) {
    throw 'Minecraft skin renderer module is missing.'
}

. $rendererModulePath
$progressCallback = $null
$resolvedProgressDirectory = ([string]$ProgressDirectory).Trim()
$resolvedRequestToken = ([string]$RequestToken).Trim()
if ($RenderMode -eq 'LookAtlas' -and $resolvedProgressDirectory -ne '' -and $resolvedRequestToken -ne '') {
    $resolvedProgressDirectory = [System.IO.Path]::GetFullPath($resolvedProgressDirectory)
    [System.IO.Directory]::CreateDirectory($resolvedProgressDirectory) | Out-Null
    $safeToken = [System.Text.RegularExpressions.Regex]::Replace($resolvedRequestToken, '[^A-Za-z0-9_-]', '_')
    $progressCallback = {
        param([int]$Percent)
        $percent = [Math]::Max(0, [Math]::Min(100, [int]$Percent))
        foreach ($existingPath in [System.IO.Directory]::EnumerateFiles($resolvedProgressDirectory, ('MinecraftSkinAtlasProgress_' + $safeToken + '_*.progress'))) {
            [System.IO.File]::Delete($existingPath)
        }
        $destinationPath = [System.IO.Path]::Combine($resolvedProgressDirectory, ('MinecraftSkinAtlasProgress_' + $safeToken + '_' + $percent.ToString('000') + '.progress'))
        $temporaryPath = $destinationPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
        try {
            [System.IO.File]::WriteAllText($temporaryPath, [string]$percent, (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::Move($temporaryPath, $destinationPath)
        }
        finally {
            if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
        }
    }.GetNewClosure()
}
Invoke-MinecraftSkinRender `
    -SourcePath $SourcePath `
    -OutputPath $OutputPath `
    -Model $Model `
    -RenderMode $RenderMode `
    -FrameWidth $FrameWidth `
    -FrameHeight $FrameHeight `
    -ProgressCallback $progressCallback
