[CmdletBinding()]
param(
    [string]$TargetRoot = '..\..',
    [string]$LaunchToken = '',
    [string]$InitialAction = '',
    [switch]$EmitResultPairs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$helperProcessTimeoutMilliseconds = 40000
try {
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}
catch {
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    [Console]::Out.WriteLine($Key + '=' + [string]$Value)
}

function Get-LauncherLogPath {
    try {
        $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $logsRoot = Join-Path $root 'Logs'
        if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
        }
        return (Join-Path $logsRoot "DMeloper's Block HUD Log.log")
    }
    catch {
        return ''
    }
}

function Write-LauncherFileLog {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][string]$Message = ''
    )

    try {
        $path = Get-LauncherLogPath
        if ([string]::IsNullOrWhiteSpace($path)) {
            return
        }
        $lines = @(
            '<VersionManagerLauncher>',
            ('timeUtc={0}' -f ((Get-Date).ToUniversalTime().ToString('o'))),
            ('stage={0}' -f $Stage),
            ('pid={0}' -f $PID),
            ('scriptRoot={0}' -f $PSScriptRoot),
            ('targetRoot={0}' -f [string]$TargetRoot),
            ('launchToken={0}' -f [string]$LaunchToken),
            ('message={0}' -f [string]$Message),
            '</VersionManagerLauncher>',
            ''
        )
        [System.IO.File]::AppendAllText($path, [string]::Join("`r`n", $lines), $utf8NoBom)
    }
    catch {
    }
}

function Emit-LauncherFailure {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-LauncherFileLog -Stage 'error' -Message $Message
    if ($EmitResultPairs) {
        Write-OutputPair -Key 'DMEL_STATUS' -Value 'ERROR'
        Write-OutputPair -Key 'DMEL_SOURCEPATH' -Value ''
        Write-OutputPair -Key 'DMEL_BACKUPPATH' -Value ''
        Write-OutputPair -Key 'DMEL_LOGPATH' -Value (Get-LauncherLogPath)
        Write-OutputPair -Key 'DMEL_MESSAGE' -Value $Message
    }
}

function Emit-LauncherSuccess {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-LauncherFileLog -Stage 'success' -Message $Message
    if ($EmitResultPairs) {
        Write-OutputPair -Key 'DMEL_STATUS' -Value 'OK'
        Write-OutputPair -Key 'DMEL_SOURCEPATH' -Value ''
        Write-OutputPair -Key 'DMEL_BACKUPPATH' -Value ''
        Write-OutputPair -Key 'DMEL_LOGPATH' -Value (Get-LauncherLogPath)
        Write-OutputPair -Key 'DMEL_MESSAGE' -Value $Message
    }
}

function Test-LaunchStateShown {
    try {
        $resolvedTargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
        $statePath = Join-Path $resolvedTargetRoot '@Resources\Customs\Data\VersionManagerLaunchState.json'
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            return $false
        }
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $status = [string]$state.Status
        $token = [string]$state.LaunchToken
        if (-not [string]::Equals($status, 'shown', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace($LaunchToken) -and -not [string]::Equals($token, $LaunchToken, [System.StringComparison]::Ordinal)) {
            return $false
        }
        return $true
    }
    catch {
        Write-LauncherFileLog -Stage 'launch-state-read-error' -Message $_.Exception.Message
        return $false
    }
}

function Get-HelperParameterSet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    try {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
        if ($null -eq $ast -or $null -eq $ast.ParamBlock) {
            return ,$result
        }
        foreach ($parameter in @($ast.ParamBlock.Parameters)) {
            $name = [string]$parameter.Name.VariablePath.UserPath
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [void]$result.Add($name)
            }
        }
    }
    catch {
        Write-LauncherFileLog -Stage 'parameter-detection-error' -Message $_.Exception.Message
    }
    return ,$result
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([AllowNull()][string]$Value)

    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Get-PowerShellExecutablePath {
    $runtimeHost = [Environment]::GetEnvironmentVariable('DMEL_POWERSHELL_HOST')
    if (-not [string]::IsNullOrWhiteSpace($runtimeHost) -and (Test-Path -LiteralPath $runtimeHost -PathType Leaf)) {
        return $runtimeHost
    }

    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) {
        return $windowsPowerShell
    }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }

    throw 'powershell.exe could not be located.'
}

function Invoke-HelperProcess {
    param(
        [Parameter(Mandatory = $true)][string]$HelperPath,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    $command = '$ProgressPreference = ''SilentlyContinue''; & ' + (ConvertTo-PowerShellSingleQuotedLiteral -Value $HelperPath)
    foreach ($name in @('TargetRoot', 'LaunchToken', 'InitialAction')) {
        if ($Parameters.ContainsKey($name)) {
            $command += ' -' + $name + ' ' + (ConvertTo-PowerShellSingleQuotedLiteral -Value ([string]$Parameters[$name]))
        }
    }
    if ($Parameters.ContainsKey('EmitResultPairs') -and [bool]$Parameters['EmitResultPairs']) {
        $command += ' -EmitResultPairs'
    }

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-PowerShellExecutablePath
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encodedCommand
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    if (-not $process.Start()) {
        throw 'OpenVersionManager helper process could not be started.'
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($helperProcessTimeoutMilliseconds)
    if ($timedOut) {
        try {
            $process.Kill()
        }
        catch {
        }
        try {
            $process.WaitForExit(1000) | Out-Null
        }
        catch {
        }
        if (-not $process.HasExited) {
            throw 'OpenVersionManager helper exceeded wrapper timeout and could not be terminated.'
        }
    }
    $stdoutText = [string]$stdoutTask.Result
    $stderrText = [string]$stderrTask.Result

    $stdout = @()
    if (-not [string]::IsNullOrEmpty($stdoutText)) {
        $stdout = @($stdoutText -split "\r?\n" | Where-Object { $_ -ne '' })
    }
    $stderr = @()
    if (-not [string]::IsNullOrEmpty($stderrText)) {
        $stderr = @($stderrText -split "\r?\n" | Where-Object { $_ -ne '' })
    }

    $exitCode = ''
    if ($process.HasExited) {
        $exitCode = [string]$process.ExitCode
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        TimedOut = $timedOut
        Stdout = [string[]]$stdout
        Stderr = [string[]]$stderr
    }
}

try {
    $helperPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Utilities\tools\OpenVersionManager.ps1'))
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw ("OpenVersionManager helper was not found: {0}" -f $helperPath)
    }

    $supportedParameters = Get-HelperParameterSet -Path $helperPath
    $helperParameters = @{}
    if ($supportedParameters.Contains('TargetRoot')) {
        $helperParameters['TargetRoot'] = $TargetRoot
    }
    if ($supportedParameters.Contains('LaunchToken')) {
        $helperParameters['LaunchToken'] = $LaunchToken
    }
    if ($supportedParameters.Contains('InitialAction') -and -not [string]::IsNullOrWhiteSpace($InitialAction)) {
        $helperParameters['InitialAction'] = $InitialAction
    }
    if ($EmitResultPairs -and $supportedParameters.Contains('EmitResultPairs')) {
        $helperParameters['EmitResultPairs'] = $true
    }

    $result = Invoke-HelperProcess -HelperPath $helperPath -Parameters $helperParameters
    $output = @($result.Stdout)
    $diagnosticOutput = @($result.Stdout + $result.Stderr)
    if ($result.TimedOut) {
        $preview = (($diagnosticOutput | ForEach-Object { [string]$_ }) -join ' | ')
        if ($preview.Length -gt 600) {
            $preview = $preview.Substring(0, 600) + '...'
        }
        if ([string]::IsNullOrWhiteSpace($preview)) {
            $preview = 'OpenVersionManager helper returned no stdout before timeout.'
        }
        Emit-LauncherFailure -Message ('OpenVersionManager helper exceeded wrapper timeout. timeoutMilliseconds=' + [string]$helperProcessTimeoutMilliseconds + '. ' + $preview)
        return
    }
    $hasStatus = $false
    foreach ($line in @($output)) {
        $text = [string]$line
        if ($text -match '^DMEL_STATUS=') {
            $hasStatus = $true
        }
        [Console]::Out.WriteLine($text)
    }

    if (-not $hasStatus) {
        $preview = (($diagnosticOutput | ForEach-Object { [string]$_ }) -join ' | ')
        if ($preview.Length -gt 600) {
            $preview = $preview.Substring(0, 600) + '...'
        }
        if ([string]::IsNullOrWhiteSpace($preview)) {
            $preview = 'OpenVersionManager helper returned no stdout.'
        }
        if (Test-LaunchStateShown) {
            Emit-LauncherSuccess -Message ('OpenVersionManager helper did not emit DMEL_STATUS, but matching launch state reported shown. exitCode=' + [string]$result.ExitCode + '. ' + $preview)
            return
        }
        Emit-LauncherFailure -Message ('OpenVersionManager helper returned no DMEL_STATUS. exitCode=' + [string]$result.ExitCode + '. ' + $preview)
    }
}
catch {
    Emit-LauncherFailure -Message $_.Exception.Message
}
