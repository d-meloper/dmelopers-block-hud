param(
    [string] $TargetPath = '',
    [string] $Arguments = ''
)

$ErrorActionPreference = 'Stop'

$target = ($TargetPath -as [string]).Trim()
if ([string]::IsNullOrWhiteSpace($target)) {
    exit 1
}

try {
    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        Start-Process -FilePath $target | Out-Null
    } else {
        Start-Process -FilePath $target -ArgumentList $Arguments | Out-Null
    }
    exit 0
} catch {
    exit 1
}
