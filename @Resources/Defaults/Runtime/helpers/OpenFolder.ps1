[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$Create
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
try {
    [Console]::OutputEncoding = $Utf8NoBom
}
catch {
}

function Write-DmelPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Value
    )

    $text = ([string]$Value) -replace '[\r\n\t]+', ' '
    [Console]::WriteLine(('{0}={1}' -f $Key, $text))
}

function Start-DetachedExplorer {
    param([Parameter(Mandatory = $true)][string]$Target)

    $windowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($windowsRoot)) {
        $windowsRoot = [Environment]::ExpandEnvironmentVariables('%SystemRoot%')
    }
    $explorerPath = [System.IO.Path]::Combine($windowsRoot, 'explorer.exe')
    if (-not [System.IO.File]::Exists($explorerPath)) {
        throw 'File Explorer is unavailable.'
    }

    $quotedTarget = '"' + $Target.Replace('"', '') + '"'
    Start-Process -FilePath $explorerPath -ArgumentList $quotedTarget -WindowStyle Normal | Out-Null
}

try {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Folder path is empty.'
    }

    $target = [Environment]::ExpandEnvironmentVariables($Path)
    $target = [System.IO.Path]::GetFullPath($target)

    if ($Create) {
        [void][System.IO.Directory]::CreateDirectory($target)
    }
    elseif (-not [System.IO.Directory]::Exists($target)) {
        throw 'Folder path does not exist.'
    }

    Start-DetachedExplorer -Target $target
    Write-DmelPair 'DMEL_STATUS' 'OK'
    Write-DmelPair 'DMEL_CODE' 'FOLDER_OPEN_STARTED'
    Write-DmelPair 'DMEL_MESSAGE' 'File Explorer was started.'
}
catch {
    Write-DmelPair 'DMEL_STATUS' 'ERROR'
    Write-DmelPair 'DMEL_CODE' 'FOLDER_OPEN_FAILED'
    Write-DmelPair 'DMEL_MESSAGE' $_.Exception.Message
}
