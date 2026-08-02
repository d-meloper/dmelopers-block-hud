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
    $OutputEncoding = $Utf8NoBom
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

function ConvertTo-ComparableExplorerPath {
    param([AllowNull()][string]$LocationUrl)

    if ([string]::IsNullOrWhiteSpace($LocationUrl)) {
        return ''
    }

    try {
        $uri = [System.Uri]$LocationUrl
        if (-not $uri.IsFile) {
            return ''
        }
        return [System.IO.Path]::GetFullPath($uri.LocalPath).TrimEnd('\', '/')
    }
    catch {
        return ''
    }
}

function Invoke-ExplorerForegroundHint {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [AllowNull()][System.Diagnostics.Process]$StartedProcess
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds(1500)
    $wscriptShell = $null
    $shellApplication = $null
    try {
        $wscriptShell = New-Object -ComObject WScript.Shell
        $shellApplication = New-Object -ComObject Shell.Application
        $comparableTarget = [System.IO.Path]::GetFullPath($Target).TrimEnd('\', '/')

        do {
            if ($null -ne $StartedProcess) {
                try {
                    $StartedProcess.Refresh()
                    if (-not $StartedProcess.HasExited -and $StartedProcess.MainWindowHandle -ne [IntPtr]::Zero) {
                        if ($wscriptShell.AppActivate([int]$StartedProcess.Id)) {
                            return $true
                        }
                    }
                }
                catch {
                }
            }

            $matchingTitles = New-Object System.Collections.Generic.List[string]
            $titleCounts = @{}
            foreach ($window in @($shellApplication.Windows())) {
                try {
                    $title = [string]$window.LocationName
                    if (-not [string]::IsNullOrWhiteSpace($title)) {
                        $titleKey = $title.ToUpperInvariant()
                        $titleCounts[$titleKey] = 1 + [int]$titleCounts[$titleKey]
                    }
                    $windowPath = ConvertTo-ComparableExplorerPath -LocationUrl ([string]$window.LocationURL)
                    if ([string]::Equals($windowPath, $comparableTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                        if (-not [string]::IsNullOrWhiteSpace($title) -and -not $matchingTitles.Contains($title)) {
                            $matchingTitles.Add($title)
                        }
                    }
                }
                catch {
                }
            }

            $uniqueMatchingTitles = @($matchingTitles | Where-Object { [int]$titleCounts[$_.ToUpperInvariant()] -eq 1 })
            if ($uniqueMatchingTitles.Count -eq 1 -and $wscriptShell.AppActivate($uniqueMatchingTitles[0])) {
                return $true
            }

            Start-Sleep -Milliseconds 75
        } while ([DateTime]::UtcNow -lt $deadline)
    }
    catch {
    }
    finally {
        if ($null -ne $shellApplication -and [System.Runtime.InteropServices.Marshal]::IsComObject($shellApplication)) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shellApplication)
        }
        if ($null -ne $wscriptShell -and [System.Runtime.InteropServices.Marshal]::IsComObject($wscriptShell)) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wscriptShell)
        }
    }

    return $false
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
    $startedProcess = Start-Process -FilePath $explorerPath -ArgumentList $quotedTarget -WindowStyle Normal -PassThru
    try {
        [void](Invoke-ExplorerForegroundHint -Target $Target -StartedProcess $startedProcess)
    }
    finally {
        if ($null -ne $startedProcess) {
            $startedProcess.Dispose()
        }
    }
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
