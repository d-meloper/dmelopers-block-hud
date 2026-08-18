[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [Parameter(Mandatory = $true)][string]$LaunchToken
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8NoBom; $OutputEncoding = $utf8NoBom } catch { }

. (Join-Path $PSScriptRoot 'LatestUpdate.Common.ps1')
. (Join-Path $PSScriptRoot 'VersionManager.OperationLock.ps1')

$script:ResolvedRoot = ''
$script:Intent = $null
$script:OperationLock = $null
$script:Terminal = $false
$script:ErrorCode = ''
$script:Compatibility = ''
$script:RepairCount = 0
$script:RepairSummary = ''
$script:RepairPlanId = ''

function Get-LatestUpdateInstallResult {
    param(
        [switch]$AllowCompatibilityWarning,
        [AllowEmptyString()][string]$ExpectedRepairPlanId = ''
    )
    $installPath = Join-Path $PSScriptRoot 'InstallVersionRelease.ps1'
    if (-not (Test-Path -LiteralPath $installPath -PathType Leaf)) { throw "InstallVersionRelease.ps1 was not found: $installPath" }
    $stagingPath = Get-LatestUpdateStagingPath -Root $script:ResolvedRoot -LaunchToken $LaunchToken
    [void](Assert-LatestUpdateZipFile -Path $stagingPath)
    $parameters = [ordered]@{
        CurrentTargetRoot = $script:ResolvedRoot
        PackagePath = $stagingPath
        ExpectedPackageSha256 = [string]$script:Intent.ExpectedPackageSha256
        ExpectedVersion = [string]$script:Intent.ExpectedVersion
        ExpectedReleaseVariant = [string]$script:Intent.ReleaseVariant
        LatestUpdateLaunchToken = $LaunchToken
        ProgressOwnerRoot = $script:ResolvedRoot
        ProgressToken = $LaunchToken
        NonInteractive = $true
        PassThruResultObject = $true
    }
    if ($AllowCompatibilityWarning) {
        if ([string]::IsNullOrWhiteSpace($ExpectedRepairPlanId)) {
            throw 'ExpectedRepairPlanId is required for an approved compatibility repair.'
        }
        $parameters['AllowCompatibilityWarning'] = $true
        $parameters['ExpectedRepairPlanId'] = $ExpectedRepairPlanId
    }
    $output = @(& $installPath @parameters)
    $result = @($output | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['DMEL_STATUS'] } | Select-Object -Last 1)
    if ($result.Count -eq 0) { throw 'InstallVersionRelease.ps1 did not return a DMEL result object.' }
    return $result[0]
}

# DMEL_COMPAT:update.unscoped-decision-transport
function Wait-LatestUpdateCompatibilityDecision {
    while ($true) {
        $decisionPath = Get-LatestUpdateDecisionPath -Root $script:ResolvedRoot
        $decision = $null
        try { $decision = Read-LatestUpdateJson -Path $decisionPath }
        catch {
            # This unscoped JSON is a compatibility transport. A malformed or
            # stale copy must never block the tokenized native decision file.
            $decision = $null
        }
        if ($null -ne $decision) {
            $schema = [int](Get-LatestUpdateObjectProperty -Object $decision -Name 'SchemaVersion' -DefaultValue 0)
            $token = [string](Get-LatestUpdateObjectProperty -Object $decision -Name 'LaunchToken' -DefaultValue '')
            $value = ([string](Get-LatestUpdateObjectProperty -Object $decision -Name 'Decision' -DefaultValue '')).ToLowerInvariant()
            if ($schema -eq 1 -and [string]::Equals($token, $LaunchToken, [System.StringComparison]::Ordinal) -and $value -in @('continue', 'cancel')) {
                return $value
            }
        }
        $nativeDecision = Read-LatestUpdateNativeDecision -Root $script:ResolvedRoot -LaunchToken $LaunchToken
        if ($nativeDecision -in @('continue', 'cancel')) {
            return $nativeDecision
        }
        if (@(Get-Process -Name Rainmeter -ErrorAction SilentlyContinue).Count -eq 0) { return 'cancel' }
        Start-Sleep -Milliseconds 250
    }
}

function Complete-LatestUpdateSession {
    param(
        [ValidateSet('success', 'canceled', 'error')][string]$Status,
        [AllowNull()][string]$Message = '',
        [AllowNull()][string]$LogPath = '',
        [AllowNull()][string]$Compatibility = '',
        [int]$RepairCount = 0,
        [AllowNull()][string]$RepairSummary = '',
        [AllowNull()][string]$RepairPlanId = ''
    )
    [void](Save-LatestUpdateState `
        -Root $script:ResolvedRoot `
        -Intent $script:Intent `
        -Status $Status `
        -SessionPid $PID `
        -Message $Message `
        -LogPath $LogPath `
        -ErrorCode $script:ErrorCode `
        -Compatibility $Compatibility `
        -RepairCount $RepairCount `
        -RepairSummary $RepairSummary `
        -RepairPlanId $RepairPlanId)
    Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage $Status -Message $Message
    $script:Terminal = $true
}

try {
    $script:ResolvedRoot = Resolve-LatestUpdateTargetRoot -Path $TargetRoot
    [void](Assert-LatestUpdateToken -LaunchToken $LaunchToken)
    $rawIntent = Read-LatestUpdateJson -Path (Get-LatestUpdateIntentPath -Root $script:ResolvedRoot)
    if ($null -eq $rawIntent) { throw 'Latest update intent was not found.' }
    $script:Intent = Assert-LatestUpdateIntent -Intent $rawIntent -ExpectedLaunchToken $LaunchToken
    $script:OperationLock = Enter-VersionManagerOperationMutex -TargetRoot $script:ResolvedRoot
    if (-not [bool]$script:OperationLock.Acquired) {
        $script:ErrorCode = 'operation-conflict'
        throw 'Skin manager or another version operation is already active.'
    }
    if ([bool]$script:OperationLock.Abandoned) { Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage 'mutex-recovered' -Message $script:OperationLock.Name }

    [void](Save-LatestUpdateState -Root $script:ResolvedRoot -Intent $script:Intent -Status 'installing' -SessionPid $PID -Message 'Installing the downloaded update.' -LogPath (Get-LatestUpdateLogPath -Root $script:ResolvedRoot))
    $result = Get-LatestUpdateInstallResult
    $status = Assert-LatestUpdateInstallResultContract -Result $result
    $approvedRepairPlanId = ''
    while ($status -eq 'WARN') {
        $compatibility = ([string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_COMPATIBILITY' -DefaultValue '')).ToUpperInvariant()
        $repairSummary = [string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_REPAIRSUMMARY' -DefaultValue '')
        $repairPlanId = [string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_REPAIRPLANID' -DefaultValue '')
        $repairCount = 0
        [void][int]::TryParse(
            [string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_REPAIRCOUNT' -DefaultValue '0'),
            [ref]$repairCount)
        $script:Compatibility = $compatibility
        $script:RepairCount = $repairCount
        $script:RepairSummary = $repairSummary
        $script:RepairPlanId = $repairPlanId
        if ($compatibility -eq 'FATAL') {
            $script:ErrorCode = 'compatibility-fatal'
            $fatalMessage = [string]$result.DMEL_MESSAGE
            if ([string]::IsNullOrWhiteSpace($fatalMessage)) {
                $fatalMessage = 'The current data cannot be imported safely into the selected version.'
            }
            throw $fatalMessage
        }
        if ($compatibility -ne 'REPAIRABLE' -or $repairCount -le 0 -or $repairPlanId -notmatch '^[0-9A-Fa-f]{64}$') {
            $script:ErrorCode = 'compatibility-contract-invalid'
            throw 'InstallVersionRelease.ps1 returned WARN without a complete repair plan.'
        }
        if (-not [string]::IsNullOrWhiteSpace($approvedRepairPlanId) -and
            [string]::Equals($approvedRepairPlanId, $repairPlanId, [System.StringComparison]::Ordinal)) {
            $script:ErrorCode = 'compatibility-approval-not-applied'
            throw 'InstallVersionRelease.ps1 repeated the same compatibility warning after its repair plan was approved.'
        }
        try {
            [void](Publish-LatestUpdateCompatibilityWarning `
                -Root $script:ResolvedRoot `
                -Intent $script:Intent `
                -LaunchToken $LaunchToken `
                -SessionPid $PID `
                -Message ([string]$result.DMEL_MESSAGE) `
                -LogPath ([string]$result.DMEL_LOGPATH) `
                -Compatibility $compatibility `
                -RepairCount $repairCount `
                -RepairSummary $repairSummary `
                -RepairPlanId $repairPlanId)
        }
        catch {
            $script:ErrorCode = 'decision-transport-unavailable'
            throw "The compatibility decision transport could not be initialized: $($_.Exception.Message)"
        }
        $decision = Wait-LatestUpdateCompatibilityDecision
        if ($decision -eq 'cancel') {
            Complete-LatestUpdateSession `
                -Status 'canceled' `
                -Message 'Latest update was canceled at the compatibility warning.' `
                -LogPath ([string]$result.DMEL_LOGPATH) `
                -Compatibility $compatibility `
                -RepairCount $repairCount `
                -RepairSummary $repairSummary `
                -RepairPlanId $repairPlanId
            Remove-LatestUpdateDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
            Remove-LatestUpdateNativeDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
            return
        }
        [void](Save-LatestUpdateState `
            -Root $script:ResolvedRoot `
            -Intent $script:Intent `
            -Status 'installing' `
            -SessionPid $PID `
            -Message 'Importing current data with the approved compatibility repairs.' `
            -LogPath ([string]$result.DMEL_LOGPATH) `
            -Compatibility $compatibility `
            -RepairCount $repairCount `
            -RepairSummary $repairSummary `
            -RepairPlanId $repairPlanId)
        Remove-LatestUpdateDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
        Remove-LatestUpdateNativeDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
        $approvedRepairPlanId = $repairPlanId
        $result = Get-LatestUpdateInstallResult `
            -AllowCompatibilityWarning `
            -ExpectedRepairPlanId $approvedRepairPlanId
        $status = Assert-LatestUpdateInstallResultContract -Result $result
    }
    if ($status -notin @('OK', 'NOOP')) {
        $detail = [string]$result.DMEL_MESSAGE
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "InstallVersionRelease.ps1 failed with status $status." }
        throw $detail
    }
    $successRepairCount = 0
    [void][int]::TryParse(
        [string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_REPAIRCOUNT' -DefaultValue '0'),
        [ref]$successRepairCount)
    Complete-LatestUpdateSession `
        -Status 'success' `
        -Message ([string]$result.DMEL_MESSAGE) `
        -LogPath ([string]$result.DMEL_LOGPATH) `
        -Compatibility ([string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_COMPATIBILITY' -DefaultValue '')) `
        -RepairCount $successRepairCount `
        -RepairSummary ([string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_REPAIRSUMMARY' -DefaultValue '')) `
        -RepairPlanId ([string](Get-LatestUpdateObjectProperty -Object $result -Name 'DMEL_REPAIRPLANID' -DefaultValue ''))
}
catch {
    $message = [string]$_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedRoot)) { Write-LatestUpdateLog -Root $script:ResolvedRoot -Stage 'session-error' -Message $message }
    if ($null -ne $script:Intent -and -not [string]::IsNullOrWhiteSpace($script:ResolvedRoot)) {
        try {
            Complete-LatestUpdateSession `
                -Status 'error' `
                -Message $message `
                -LogPath (Get-LatestUpdateLogPath -Root $script:ResolvedRoot) `
                -Compatibility $script:Compatibility `
                -RepairCount $script:RepairCount `
                -RepairSummary $script:RepairSummary `
                -RepairPlanId $script:RepairPlanId
        }
        catch { }
    }
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($script:ResolvedRoot)) {
        Remove-LatestUpdateDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
        Remove-LatestUpdateNativeDecisionForToken -Root $script:ResolvedRoot -LaunchToken $LaunchToken
        Remove-LatestUpdateStagingPackage -Root $script:ResolvedRoot -LaunchToken $LaunchToken
    }
    Exit-VersionManagerOperationMutex -Lock $script:OperationLock
}
