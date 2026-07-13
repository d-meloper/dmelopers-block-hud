[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [ValidateSet('core', 'extras', 'manager', 'assemblies')]
    [string]$Step = 'core',
    [int]$MaxFiles = 0,
    [switch]$EmitResultPairs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ResultPairs = [ordered]@{
    DMEL_STATUS = 'OK'
    DMEL_STEP = $Step
    DMEL_SCANNED = '0'
    DMEL_WARNINGS = '0'
    DMEL_DURATION_MS = '0'
    DMEL_MESSAGE = ''
}
$script:WarningCount = 0

function Set-ResultPairValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Value
    )

    $script:ResultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Write-ResultPairs {
    foreach ($key in $script:ResultPairs.Keys) {
        Write-Output ("{0}={1}" -f $key, $script:ResultPairs[$key])
    }
}

function Add-Warning {
    param([AllowEmptyString()][string]$Message)

    $script:WarningCount++
    if ([string]::IsNullOrWhiteSpace($script:ResultPairs.DMEL_MESSAGE)) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $Message
    }
}

function Resolve-RootPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $resolved = [System.IO.Path]::GetFullPath($expanded)
    if (-not [System.IO.Directory]::Exists($resolved)) {
        throw "Skin root does not exist: $resolved"
    }
    return $resolved
}

function Join-RootPath {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($RootPath, $RelativePath))
}

function Get-ExistingScriptFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string[]]$RelativeRoots
    )

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($relativeRoot in $RelativeRoots) {
        $candidateRoot = Join-RootPath -RootPath $RootPath -RelativePath $relativeRoot
        if (-not [System.IO.Directory]::Exists($candidateRoot)) {
            continue
        }

        Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\(_Development|docs|CodexDocs|BestPractice|PublicGitHub|dist|Logs|MigrationBackup)(\\|$)'
            } |
            ForEach-Object { [void]$files.Add($_) }
    }

    $selected = @($files | Sort-Object FullName)
    if ($MaxFiles -gt 0) {
        $selected = @($selected | Select-Object -First $MaxFiles)
    }
    return $selected
}

function Get-ManagerScriptFiles {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $relativeFiles = @(
        'ImportFromOldVersion.ps1',
        'OpenSettingsLogFolder.ps1',
        'OpenVersionManager.ps1',
        'UpdateHelperLocalizationCache.ps1',
        'UpdateToLatestVersion.ps1',
        'GetVersionReleaseCatalog.ps1',
        'InstallVersionRelease.ps1',
        'SwitchActiveSkinVersion.ps1',
        'Remove-LegacyLayoutTransportAdapter.ps1',
        'VersionManager.ReleaseCatalog.ps1',
        'VersionManager.UiState.ps1',
        'VersionManager.UpdateCache.ps1',
        'LowSpecSettings.Policy.ps1',
        'Localization.Common.ps1'
    )
    $relativeRoots = @(
        'Utilities\tools\ImportFromOldVersion',
        'Utilities\tools\OpenVersionManager',
        'Utilities\tools\UpdateToLatestVersion'
    )

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($relativeFile in $relativeFiles) {
        $path = Join-RootPath -RootPath $RootPath -RelativePath ("Utilities\tools\{0}" -f $relativeFile)
        if ([System.IO.File]::Exists($path)) {
            [void]$files.Add([System.IO.FileInfo]::new($path))
        }
    }
    foreach ($relativeRoot in $relativeRoots) {
        foreach ($file in @(Get-ExistingScriptFiles -RootPath $RootPath -RelativeRoots @($relativeRoot))) {
            [void]$files.Add($file)
        }
    }

    $selected = @($files | Sort-Object FullName -Unique)
    if ($MaxFiles -gt 0) {
        $selected = @($selected | Select-Object -First $MaxFiles)
    }
    return $selected
}

function Invoke-ParseWarmup {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo[]]$Files)

    $scanned = 0
    foreach ($file in $Files) {
        try {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $scanned++
            if ($null -ne $errors -and $errors.Count -gt 0) {
                Add-Warning -Message ("PowerShell parse warnings in {0}" -f $file.Name)
            }
        }
        catch {
            Add-Warning -Message ("PowerShell warmup could not parse {0}: {1}" -f $file.Name, $_.Exception.Message)
        }
    }
    Set-ResultPairValue -Key 'DMEL_SCANNED' -Value $scanned
}

function Invoke-AssemblyWarmup {
    $assemblies = @(
        'System.Drawing',
        'System.Windows.Forms',
        'WindowsBase',
        'PresentationCore',
        'PresentationFramework'
    )
    $loaded = 0
    foreach ($assembly in $assemblies) {
        try {
            Add-Type -AssemblyName $assembly
            $loaded++
        }
        catch {
            Add-Warning -Message ("Assembly warmup skipped {0}: {1}" -f $assembly, $_.Exception.Message)
        }
    }
    Set-ResultPairValue -Key 'DMEL_SCANNED' -Value $loaded
}

$startedAt = Get-Date
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $rootPath = Resolve-RootPath -Path $Root

    switch ($Step) {
        'core' {
            Invoke-ParseWarmup -Files @(Get-ExistingScriptFiles -RootPath $rootPath -RelativeRoots @(
                '@Resources\Defaults\Runtime\helpers',
                'HUD\Settings',
                'HUD\Editor'
            ))
        }
        'extras' {
            Invoke-ParseWarmup -Files @(Get-ExistingScriptFiles -RootPath $rootPath -RelativeRoots @(
                'ExtraContent'
            ))
        }
        'manager' {
            Invoke-ParseWarmup -Files @(Get-ManagerScriptFiles -RootPath $rootPath)
        }
        'assemblies' {
            Invoke-AssemblyWarmup
        }
    }

    if ($script:WarningCount -gt 0) {
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'WARN'
    }
    if ([string]::IsNullOrWhiteSpace($script:ResultPairs.DMEL_MESSAGE)) {
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value 'Warmup step completed.'
    }
}
catch {
    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
}
finally {
    Set-ResultPairValue -Key 'DMEL_WARNINGS' -Value $script:WarningCount
    Set-ResultPairValue -Key 'DMEL_DURATION_MS' -Value ([int]((Get-Date) - $startedAt).TotalMilliseconds)
    if ($EmitResultPairs) {
        Write-ResultPairs
    }
    else {
        Write-ResultPairs
    }
}
