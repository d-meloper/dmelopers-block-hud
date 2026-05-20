Set-StrictMode -Version 2.0

function Get-VersionManagerUiStateUtcStamp {
    (Get-Date).ToUniversalTime().ToString('s') + 'Z'
}

function New-VersionManagerRequestOwnershipState {
    param(
        [string]$Name = 'request'
    )

    [PSCustomObject]@{
        Name = [string]$Name
        NextGeneration = 0
        ActiveGeneration = 0
        ActiveRequestId = ''
        InProgress = $false
        LastCompletedGeneration = 0
        LastCompletedRequestId = ''
        LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    }
}

function Start-VersionManagerOwnedRequest {
    param(
        [Parameter(Mandatory = $true)]$State
    )

    $generation = [int]$State.NextGeneration + 1
    $requestId = '{0}:{1}:{2}' -f [string]$State.Name, $generation, ([guid]::NewGuid().ToString('N'))

    $State.NextGeneration = $generation
    $State.ActiveGeneration = $generation
    $State.ActiveRequestId = $requestId
    $State.InProgress = $true
    $State.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp

    return [PSCustomObject]@{
        Name = [string]$State.Name
        Generation = $generation
        RequestId = $requestId
    }
}

function Test-VersionManagerOwnedRequestCurrent {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Ticket
    )

    if (-not [bool]$State.InProgress) {
        return $false
    }

    return (
        ([int]$State.ActiveGeneration -eq [int]$Ticket.Generation) -and
        [string]::Equals([string]$State.ActiveRequestId, [string]$Ticket.RequestId, [System.StringComparison]::Ordinal)
    )
}

function Complete-VersionManagerOwnedRequest {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Ticket
    )

    if (-not (Test-VersionManagerOwnedRequestCurrent -State $State -Ticket $Ticket)) {
        return $false
    }

    $State.InProgress = $false
    $State.LastCompletedGeneration = [int]$Ticket.Generation
    $State.LastCompletedRequestId = [string]$Ticket.RequestId
    $State.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $true
}

function Clear-VersionManagerOwnedRequest {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Ticket
    )

    if (-not (Test-VersionManagerOwnedRequestCurrent -State $State -Ticket $Ticket)) {
        return $false
    }

    $State.InProgress = $false
    $State.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $true
}

function New-VersionManagerTabState {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    [PSCustomObject]@{
        Name = [string]$Name
        IsLoading = $false
        IsLoaded = $false
        IsDirty = $false
        LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    }
}

function New-VersionManagerTabStateTable {
    param(
        [string[]]$TabNames = @()
    )

    $table = [ordered]@{}
    foreach ($tabName in @($TabNames)) {
        $table[[string]$tabName] = New-VersionManagerTabState -Name ([string]$tabName)
    }

    return $table
}

function Get-VersionManagerTabState {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $name = [string]$TabName
    if (-not $TabStates.Contains($name)) {
        $TabStates[$name] = New-VersionManagerTabState -Name $name
    }

    return $TabStates[$name]
}

function Reset-VersionManagerTabState {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $state = Get-VersionManagerTabState -TabStates $TabStates -TabName $TabName
    $state.IsLoading = $false
    $state.IsLoaded = $false
    $state.IsDirty = $false
    $state.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $state
}

function Start-VersionManagerTabLoad {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $state = Get-VersionManagerTabState -TabStates $TabStates -TabName $TabName
    $state.IsLoading = $true
    $state.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $state
}

function Complete-VersionManagerTabLoad {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $state = Get-VersionManagerTabState -TabStates $TabStates -TabName $TabName
    $state.IsLoading = $false
    $state.IsLoaded = $true
    $state.IsDirty = $false
    $state.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $state
}

function Stop-VersionManagerTabLoad {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $state = Get-VersionManagerTabState -TabStates $TabStates -TabName $TabName
    $state.IsLoading = $false
    $state.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $state
}

function Set-VersionManagerTabDirty {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $state = Get-VersionManagerTabState -TabStates $TabStates -TabName $TabName
    $state.IsDirty = $true
    $state.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $state
}

function Clear-VersionManagerTabDirty {
    param(
        [Parameter(Mandatory = $true)]$TabStates,
        [Parameter(Mandatory = $true)][string]$TabName
    )

    $state = Get-VersionManagerTabState -TabStates $TabStates -TabName $TabName
    $state.IsDirty = $false
    $state.LastStateChangeAtUtc = Get-VersionManagerUiStateUtcStamp
    return $state
}

function Set-VersionManagerAllTabsDirty {
    param(
        [Parameter(Mandatory = $true)]$TabStates
    )

    foreach ($tabName in @($TabStates.Keys)) {
        [void](Set-VersionManagerTabDirty -TabStates $TabStates -TabName ([string]$tabName))
    }

    return $TabStates
}
