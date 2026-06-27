[CmdletBinding()]
param(
    [string]$TargetRoot = '..',
    [string]$LaunchToken = '',
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

function Write-RainmeterLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Notice', 'Warning', 'Error')][string]$Level = 'Notice'
    )

    try {
        $rainmeter = Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
            Select-Object -First 1 -ExpandProperty Path
        if ([string]::IsNullOrWhiteSpace($rainmeter) -or -not (Test-Path -LiteralPath $rainmeter)) {
            return
        }
        & $rainmeter '!Log' ('[DMeloper Block HUD] VersionManagerLauncher ' + [string]$Message) $Level | Out-Null
    }
    catch {
    }
}

function Get-LauncherLogPath {
    try {
        $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
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
    Write-RainmeterLog -Message ('ERROR ' + $Message) -Level 'Error'
    if ($EmitResultPairs) {
        Write-OutputPair -Key 'DMEL_STATUS' -Value 'ERROR'
        Write-OutputPair -Key 'DMEL_MESSAGE' -Value $Message
        Write-OutputPair -Key 'DMEL_LOGPATH' -Value (Get-LauncherLogPath)
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
        Write-RainmeterLog -Message ('parameter-detection-error ' + $_.Exception.Message) -Level 'Warning'
    }
    return ,$result
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([AllowNull()][string]$Value)

    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Get-PowerShellExecutablePath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }

    return 'powershell.exe'
}

function Invoke-HelperProcess {
    param(
        [Parameter(Mandatory = $true)][string]$HelperPath,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    $command = '$ProgressPreference = ''SilentlyContinue''; & ' + (ConvertTo-PowerShellSingleQuotedLiteral -Value $HelperPath)
    foreach ($name in @('TargetRoot', 'LaunchToken')) {
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
    Write-LauncherFileLog -Stage 'start' -Message 'Settings launcher wrapper started.'
    Write-RainmeterLog -Message ('start launchToken=' + [string]$LaunchToken) -Level 'Notice'

    $helperPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\tools\OpenVersionManager.ps1'))
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw ("OpenVersionManager helper was not found: {0}" -f $helperPath)
    }

    $supportedParameters = Get-HelperParameterSet -Path $helperPath
    $helperParameters = @{}
    if ($supportedParameters.Contains('TargetRoot')) {
        $helperParameters['TargetRoot'] = $TargetRoot
    }
    else {
        Write-LauncherFileLog -Stage 'legacy-helper-missing-target-root' -Message 'OpenVersionManager helper does not declare TargetRoot.'
        Write-RainmeterLog -Message 'legacy-helper-missing-target-root' -Level 'Warning'
    }
    if ($supportedParameters.Contains('LaunchToken')) {
        $helperParameters['LaunchToken'] = $LaunchToken
    }
    else {
        Write-LauncherFileLog -Stage 'legacy-helper-missing-launch-token' -Message 'OpenVersionManager helper does not declare LaunchToken; launching without a token for mixed-version compatibility.'
        Write-RainmeterLog -Message 'legacy-helper-missing-launch-token' -Level 'Warning'
    }
    if ($EmitResultPairs -and $supportedParameters.Contains('EmitResultPairs')) {
        $helperParameters['EmitResultPairs'] = $true
    }
    elseif ($EmitResultPairs) {
        Write-LauncherFileLog -Stage 'legacy-helper-missing-result-pairs' -Message 'OpenVersionManager helper does not declare EmitResultPairs.'
        Write-RainmeterLog -Message 'legacy-helper-missing-result-pairs' -Level 'Warning'
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
        Emit-LauncherFailure -Message ('OpenVersionManager helper returned no DMEL_STATUS. exitCode=' + [string]$result.ExitCode + '. ' + $preview)
    }
}
catch {
    Emit-LauncherFailure -Message $_.Exception.Message
}
