[CmdletBinding()]
param(
    [string]$TargetRoot
)

$ErrorActionPreference = 'Continue'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Show-Pause {
    try {
        [void](Read-Host 'Press Enter to continue')
    }
    catch {
    }
}

function Parse-ResultPairs {
    param([string[]]$Lines)

    $pairs = @{}
    foreach ($entry in @($Lines)) {
        $text = [string]$entry

        $match = [regex]::Match($text, '^(DMEL_[A-Z_]+)=(.*)$')
        if ($match.Success) {
            $pairs[$match.Groups[1].Value] = $match.Groups[2].Value
        }
        else {
            Write-Host $text
        }
    }

    return $pairs
}

function Quote-ProcessArgument {
    param([AllowNull()][string]$Value)

    return '"' + ([string]$Value).Replace('"', '\"') + '"'
}

function Get-PowerShellExePath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if ([System.IO.File]::Exists($candidate)) {
        return $candidate
    }

    return 'powershell.exe'
}

function Invoke-ImportHelper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedTargetRoot
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-PowerShellExePath
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File ' +
        (Quote-ProcessArgument $ScriptPath) +
        ' -TargetRoot ' +
        (Quote-ProcessArgument $ResolvedTargetRoot) +
        ' -ConfirmDetectedSource -EmitResultPairs'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8NoBom
    $psi.StandardErrorEncoding = $script:Utf8NoBom

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $exitCode = $process.ExitCode
    $process.Dispose()

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($block in @($stdout, $stderr)) {
        if ([string]::IsNullOrEmpty($block)) {
            continue
        }
        foreach ($line in ($block -split "`r?`n")) {
            if ($line -ne '') {
                [void]$lines.Add($line)
            }
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Lines = @($lines.ToArray())
    }
}

if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
    $TargetRoot = Join-Path $PSScriptRoot '..'
}

$resolvedTargetRoot = Resolve-FullPath -Path $TargetRoot
$scriptPath = Join-Path $PSScriptRoot 'ImportFromOldVersion.ps1'
if (-not [System.IO.File]::Exists($scriptPath)) {
    Write-Host 'Old-data import script was not found:'
    Write-Host $scriptPath
    Write-Host 'Reinstall the v1.2.0 skin package or restore the tools folder.'
    Show-Pause
    exit 1
}

$helperResult = Invoke-ImportHelper -ScriptPath $scriptPath -ResolvedTargetRoot $resolvedTargetRoot
$exitCode = [int]$helperResult.ExitCode
$pairs = Parse-ResultPairs -Lines $helperResult.Lines
$status = ''
$logPath = ''
$message = ''
if ($pairs.ContainsKey('DMEL_STATUS')) {
    $status = ([string]$pairs['DMEL_STATUS']).Trim()
}
if ($pairs.ContainsKey('DMEL_LOGPATH')) {
    $logPath = ([string]$pairs['DMEL_LOGPATH']).Trim()
}
if ($pairs.ContainsKey('DMEL_MESSAGE')) {
    $message = ([string]$pairs['DMEL_MESSAGE']).Trim()
}

if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host ''
    Write-Host 'Old-data import failed because the helper did not emit DMEL_STATUS.'
    Write-Host 'Review the PowerShell error text above.'
    Show-Pause
    exit 1
}

if ($status -ieq 'CANCEL') {
    Write-Host ''
    Write-Host 'Old-data import was canceled. No changes were applied.'
    if (-not [string]::IsNullOrWhiteSpace($logPath)) {
        Write-Host 'Review the log path printed above if needed.'
    }
    Show-Pause
    exit 0
}

if ($status -ieq 'OK' -and $exitCode -eq 0) {
    Write-Host ''
    Write-Host 'Old-data import completed successfully. Review the log path printed above.'
    Show-Pause
    exit 0
}

Write-Host ''
Write-Host 'Old-data import failed. Review the log path printed above.'
if (-not [string]::IsNullOrWhiteSpace($message)) {
    Write-Host $message
}
if ([string]::IsNullOrWhiteSpace($logPath)) {
    Write-Host 'If no log path was printed, review the PowerShell error text above.'
}
Show-Pause
if ($exitCode -ne 0) {
    exit $exitCode
}
exit 1
