# PackageUrl-only transport for InstallVersionRelease.ps1.
# The WebParser latest-update path uses PackagePath and never loads this file.

. (Join-Path $PSScriptRoot 'VersionManager.ReleaseCatalog.ps1')

function Get-InstallReleaseUrlFileName {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $uri = [System.Uri]$Url
        $fileName = [System.IO.Path]::GetFileName($uri.LocalPath)
    }
    catch {
        $fileName = ''
    }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'release.zip'
    }

    $extension = [System.IO.Path]::GetExtension($fileName)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $fileName += '.zip'
    }
    elseif (-not [string]::Equals($extension, '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'PackageUrl must resolve to a ZIP release package.'
    }

    return (Convert-ToSafeFolderName -Name $fileName)
}

function Invoke-InstallReleasePackageDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$RetryCount
    )

    $maxAttempts = [Math]::Max(1, $RetryCount + 1)
    $lastMessage = ''
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            }
            Write-Log ("Retrying release package download: attempt {0}/{1}" -f $attempt, $maxAttempts) 'WARN'
        }

        try {
            Invoke-BlockHudGitHubReleaseAssetDownload -Uri $Url -OutFile $DestinationPath -TimeoutSeconds $TimeoutSeconds
            if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
                throw 'The download completed without creating the ZIP file.'
            }
            $downloadedFile = Get-Item -LiteralPath $DestinationPath -Force
            if ($downloadedFile.Length -le 0) {
                throw 'The downloaded ZIP file is empty.'
            }
            return
        }
        catch {
            $lastMessage = [string]$_.Exception.Message
            if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            }
            if ($attempt -lt $maxAttempts) {
                Write-Log ("Release package download attempt {0}/{1} failed: {2}" -f $attempt, $maxAttempts, $lastMessage) 'WARN'
                Start-Sleep -Seconds ([Math]::Min(15, 3 * $attempt))
                continue
            }
        }
    }

    throw ("Release package download failed after {0} attempt(s). Each attempt allows up to {1} seconds. Last error: {2}" -f $maxAttempts, $TimeoutSeconds, $lastMessage)
}

function Resolve-DownloadedInstallReleasePackagePath {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRoot,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$RetryCount,
        [Parameter(Mandatory = $true)][string]$LogStamp
    )

    $downloadRoot = Join-RootPath -Root $CurrentRoot -RelativePath '@Resources\Customs\Data\VersionManagerDownloads'
    Ensure-Directory -Path $downloadRoot
    $fileName = Get-InstallReleaseUrlFileName -Url $Url
    $downloadPath = Join-Path $downloadRoot $fileName
    if (Test-Path -LiteralPath $downloadPath -PathType Leaf) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $downloadPath = Join-Path $downloadRoot ("{0}_{1}.zip" -f $baseName, $LogStamp)
    }

    Write-Log ("Downloading PackageUrl to: {0} (timeout={1}s retries={2})" -f $downloadPath, $TimeoutSeconds, $RetryCount)
    Invoke-InstallReleasePackageDownload -Url $Url -DestinationPath $downloadPath -TimeoutSeconds $TimeoutSeconds -RetryCount $RetryCount
    if (-not [string]::Equals([System.IO.Path]::GetExtension($downloadPath), '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Downloaded package path must be a ZIP release package.'
    }

    return (Resolve-FullPath -Path $downloadPath)
}
