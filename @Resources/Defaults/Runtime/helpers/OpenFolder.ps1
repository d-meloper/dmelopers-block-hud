[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$Create
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

Invoke-Item -LiteralPath $target
