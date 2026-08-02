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
$script:ResolvedTargetRoot = ''
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
        $loggedTargetRoot = [string]$script:ResolvedTargetRoot
        if ([string]::IsNullOrWhiteSpace($loggedTargetRoot)) {
            $loggedTargetRoot = [string]$TargetRoot
        }
        $lines = @(
            '<VersionManagerLauncher>',
            ('timeUtc={0}' -f ((Get-Date).ToUniversalTime().ToString('o'))),
            ('stage={0}' -f $Stage),
            ('pid={0}' -f $PID),
            ('scriptRoot={0}' -f $PSScriptRoot),
            ('targetRootInput={0}' -f [string]$TargetRoot),
            ('targetRoot={0}' -f $loggedTargetRoot),
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

function Read-LaunchStateJsonShared {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lastError = $null
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            try {
                $reader = New-Object System.IO.StreamReader($stream, $utf8NoBom, $true)
                try {
                    $raw = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                    $stream = $null
                }
            }
            finally {
                if ($null -ne $stream) {
                    $stream.Dispose()
                }
            }

            if ([string]::IsNullOrWhiteSpace($raw)) {
                return $null
            }
            return ($raw | ConvertFrom-Json)
        }
        catch [System.IO.IOException] {
            $lastError = $_
        }
        catch [System.UnauthorizedAccessException] {
            $lastError = $_
        }
        catch {
            $lastError = $_
            if ($attempt -ge 6) {
                throw
            }
        }

        if ($attempt -lt 6) {
            Start-Sleep -Milliseconds ([Math]::Min(180, 30 * $attempt))
        }
    }

    if ($null -ne $lastError) {
        throw $lastError
    }
    return $null
}

function Resolve-LauncherTargetRoot {
    param([AllowNull()][string]$Value)

    $candidate = [string]$Value
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'TargetRoot is empty.'
    }

    while ($candidate.Length -ge 2) {
        $first = $candidate.Substring(0, 1)
        $last = $candidate.Substring($candidate.Length - 1, 1)
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $candidate = $candidate.Substring(1, $candidate.Length - 2)
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                throw 'TargetRoot is empty after removing wrapper quotes.'
            }
            continue
        }
        break
    }

    foreach ($character in $candidate.ToCharArray()) {
        if ([char]::IsControl($character)) {
            throw 'TargetRoot contains a control character.'
        }
    }

    $candidate = [Environment]::ExpandEnvironmentVariables($candidate)
    if ([System.IO.Path]::IsPathRooted($candidate)) {
        $resolved = [System.IO.Path]::GetFullPath($candidate)
    }
    else {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $candidate))
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw ("TargetRoot does not exist: {0}" -f $resolved)
    }
    return $resolved
}

function Test-LaunchStateShown {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    try {
        $statePath = Join-Path $ResolvedTargetRoot '@Resources\Customs\Data\VersionManagerLaunchState.json'
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            return $false
        }
        $state = Read-LaunchStateJsonShared -Path $statePath
        if ($null -eq $state) {
            return $false
        }
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

function ConvertTo-WindowsCommandLineArgument {
    param([AllowNull()][string]$Value)

    $text = [string]$Value
    if ($text.Length -eq 0) {
        return '""'
    }
    if ($text.IndexOfAny([char[]]@(' ', "`t", "`r", "`n", '"')) -lt 0) {
        return $text
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $text.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-WindowsCommandLineArguments {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $quoted = foreach ($argument in $Arguments) {
        ConvertTo-WindowsCommandLineArgument -Value $argument
    }
    return ($quoted -join ' ')
}

function Get-PowerShellExecutablePath {
    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($candidate)
    }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [System.IO.Path]::GetFullPath($command.Source)
    }

    throw 'powershell.exe could not be located.'
}

function Invoke-HelperProcess {
    param(
        [Parameter(Mandatory = $true)][string]$HelperPath,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $HelperPath)) {
        [void]$arguments.Add([string]$argument)
    }
    foreach ($name in @('TargetRoot', 'LaunchToken', 'InitialAction')) {
        if ($Parameters.ContainsKey($name)) {
            [void]$arguments.Add('-' + $name)
            [void]$arguments.Add([string]$Parameters[$name])
        }
    }
    [void]$arguments.Add('-WindowSession')

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-PowerShellExecutablePath
    $startInfo.Arguments = Join-WindowsCommandLineArguments -Arguments @($arguments.ToArray())
    $startInfo.UseShellExecute = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $false
    $startInfo.RedirectStandardError = $false

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'OpenVersionManager helper process could not be started.'
        }
        $deadline = [DateTime]::UtcNow.AddMilliseconds($helperProcessTimeoutMilliseconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-LaunchStateShown -ResolvedTargetRoot ([string]$Parameters['TargetRoot'])) {
                return [PSCustomObject]@{
                    ExitCode = ''
                    TimedOut = $false
                    Stdout = @('DMEL_STATUS=OK', 'DMEL_MESSAGE=Skins opened.')
                    Stderr = @()
                }
            }
            if ($process.HasExited) {
                return [PSCustomObject]@{
                    ExitCode = [string]$process.ExitCode
                    TimedOut = $false
                    Stdout = @()
                    Stderr = @('The Skin manager window session exited before reporting shown.')
                }
            }
            Start-Sleep -Milliseconds 50
        }

        return [PSCustomObject]@{
            ExitCode = ''
            TimedOut = $false
            Stdout = @('DMEL_STATUS=WARN', 'DMEL_MESSAGE=Skins launch is still pending; the window session was left running.')
            Stderr = @()
        }
    }
    finally {
        $process.Dispose()
    }
}

try {
    $script:ResolvedTargetRoot = Resolve-LauncherTargetRoot -Value $TargetRoot
    $helperPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Utilities\tools\OpenVersionManager.ps1'))
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw ("OpenVersionManager helper was not found: {0}" -f $helperPath)
    }
    $operationLockPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Utilities\tools\VersionManager.OperationLock.ps1'))
    if (Test-Path -LiteralPath $operationLockPath -PathType Leaf) {
        . $operationLockPath
        $operationProbe = Enter-VersionManagerOperationMutex -TargetRoot $script:ResolvedTargetRoot
        try {
            if (-not [bool]$operationProbe.Acquired) {
                Emit-LauncherFailure -Message 'A latest update or another Skin manager operation is already running. Wait for it to finish before opening Skin manager.'
                return
            }
        }
        finally { Exit-VersionManagerOperationMutex -Lock $operationProbe }
    }

    $supportedParameters = Get-HelperParameterSet -Path $helperPath
    $helperParameters = @{}
    if ($supportedParameters.Contains('TargetRoot')) {
        $helperParameters['TargetRoot'] = $script:ResolvedTargetRoot
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
        if (Test-LaunchStateShown -ResolvedTargetRoot $script:ResolvedTargetRoot) {
            Emit-LauncherSuccess -Message ('OpenVersionManager helper did not emit DMEL_STATUS, but matching launch state reported shown. exitCode=' + [string]$result.ExitCode + '. ' + $preview)
            return
        }
        Emit-LauncherFailure -Message ('OpenVersionManager helper returned no DMEL_STATUS. exitCode=' + [string]$result.ExitCode + '. ' + $preview)
    }
}
catch {
    Emit-LauncherFailure -Message $_.Exception.Message
}
