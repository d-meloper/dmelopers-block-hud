[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('probe', 'enable', 'disable')]
    [string]$Mode,
    [ValidateSet('shortcut', 'task', 'all')]
    [string]$Method,
    [string]$StartupFolderOverride,
    [string]$RainmeterExecutablePathOverride,
    [string]$ScheduledTaskNameOverride,
    [string]$RequestToken
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $script:Utf8NoBom
$OutputEncoding = $script:Utf8NoBom

$entrypointDirectory = $PSScriptRoot
$commonHelperPath = Join-Path $entrypointDirectory 'Runtime\Helpers\StartupAutoRun.Common.ps1'
. $commonHelperPath

function ConvertTo-SingleLineText {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return $Value.Replace("`r", '\r').Replace("`n", '\n')
}

function Write-StartupResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [AllowEmptyString()][string]$Value,
        [AllowEmptyString()][string]$Code,
        [AllowEmptyString()][string]$Message,
        [AllowEmptyString()][string]$FastValue,
        [AllowEmptyString()][string]$ShortcutValue,
        [AllowEmptyString()][string]$ResolvedMethod,
        [AllowEmptyString()][string]$TaskState,
        [AllowEmptyString()][string]$Recovery,
        [AllowEmptyString()][string]$RecoveryCode,
        [AllowEmptyString()][string]$ResultRequestToken
    )

    @(
        'DMEL_STATUS=' + $Status
        'DMEL_VALUE=' + $Value
        'DMEL_CODE=' + $Code
        'DMEL_MESSAGE=' + (ConvertTo-SingleLineText -Value $Message)
        'DMEL_FAST_VALUE=' + $FastValue
        'DMEL_SHORTCUT_VALUE=' + $ShortcutValue
        'DMEL_METHOD=' + $ResolvedMethod
        'DMEL_TASK_STATE=' + $TaskState
        'DMEL_RECOVERY=' + $Recovery
        'DMEL_RECOVERY_CODE=' + $RecoveryCode
        'DMEL_REQUEST_TOKEN=' + (ConvertTo-SingleLineText -Value $ResultRequestToken)
    ) | Write-Output

    if ($Status -eq 'OK' -and ($Value -eq '0' -or $Value -eq '1')) {
        Write-Output $Value
    }
}

$startupFolder = $null
$taskName = $null
$status = 'ERROR'
$code = 'UNEXPECTED'
$message = ''
$state = $null
$recovery = 'none'
$recoveryCode = ''

try {
    $startupFolder = Get-BlockHudStartupFolderPath -Override $StartupFolderOverride
    if ([string]::IsNullOrWhiteSpace($startupFolder)) {
        throw (New-BlockHudStartupException -Code 'STARTUP_FOLDER_UNAVAILABLE' -Message 'The Windows startup folder path is empty.')
    }
    $taskName = Resolve-BlockHudScheduledTaskName `
        -Override $ScheduledTaskNameOverride `
        -StartupFolderOverride $StartupFolderOverride `
        -RainmeterExecutablePathOverride $RainmeterExecutablePathOverride

    $effectiveMethod = $Method
    if (-not $PSBoundParameters.ContainsKey('Method')) {
        $effectiveMethod = if ($Mode -eq 'enable') { 'shortcut' } else { 'all' }
    }

    switch ($Mode) {
        'probe' {
            $state = Get-BlockHudStartupRegistrationState -StartupFolder $startupFolder -TaskName $taskName
        }
        'enable' {
            if ($effectiveMethod -eq 'shortcut') {
                $state = Set-BlockHudStartupShortcutMode `
                    -StartupFolder $startupFolder `
                    -TaskName $taskName `
                    -RainmeterExecutablePathOverride $RainmeterExecutablePathOverride
            }
            elseif ($effectiveMethod -eq 'task') {
                $state = Set-BlockHudStartupTaskMode `
                    -StartupFolder $startupFolder `
                    -TaskName $taskName `
                    -RainmeterExecutablePathOverride $RainmeterExecutablePathOverride
            }
            else {
                throw (New-BlockHudStartupException -Code 'INVALID_METHOD' -Message "Method '$effectiveMethod' cannot be enabled.")
            }
        }
        'disable' {
            if ($effectiveMethod -ne 'all') {
                throw (New-BlockHudStartupException -Code 'INVALID_METHOD' -Message "Disable requires method 'all'.")
            }
            $state = Disable-BlockHudStartupRegistration `
                -StartupFolder $startupFolder `
                -TaskName $taskName `
                -RainmeterExecutablePathOverride $RainmeterExecutablePathOverride
        }
    }

    $status = 'OK'
    $code = ''
}
catch {
    $message = [string]$_.Exception.Message
    if ($_.Exception.Data.Contains('DmelCode')) {
        $code = [string]$_.Exception.Data['DmelCode']
    }
    else {
        $code = $_.Exception.GetType().Name
    }
    if ($_.Exception.Data.Contains('DmelRecovery')) {
        $recovery = [string]$_.Exception.Data['DmelRecovery']
    }
    if ($_.Exception.Data.Contains('DmelRecoveryCode')) {
        $recoveryCode = [string]$_.Exception.Data['DmelRecoveryCode']
    }
    if ($_.Exception.Data.Contains('DmelState')) {
        $state = $_.Exception.Data['DmelState']
    }
    if (-not [string]::IsNullOrWhiteSpace($startupFolder) -and -not [string]::IsNullOrWhiteSpace($taskName)) {
        try {
            $state = Get-BlockHudStartupRegistrationState -StartupFolder $startupFolder -TaskName $taskName
        }
        catch {
            # Leave state values empty when the resulting registrations cannot be probed.
        }
    }
}

Write-StartupResult `
    -Status $status `
    -Value $(if ($null -ne $state) { [string]$state.Value } else { '' }) `
    -Code $code `
    -Message $message `
    -FastValue $(if ($null -ne $state) { [string]$state.FastValue } else { '' }) `
    -ShortcutValue $(if ($null -ne $state) { [string]$state.ShortcutValue } else { '' }) `
    -ResolvedMethod $(if ($null -ne $state) { [string]$state.Method } else { '' }) `
    -TaskState $(if ($null -ne $state) { [string]$state.TaskState } else { '' }) `
    -Recovery $recovery `
    -RecoveryCode $recoveryCode `
    -ResultRequestToken $RequestToken

if ($status -ne 'OK') {
    exit 1
}
