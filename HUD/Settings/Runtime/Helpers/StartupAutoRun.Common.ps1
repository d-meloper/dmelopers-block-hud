$script:BlockHudStartupTaskSource = 'DMeloper.BlockHUD.Settings.StartupAutoRun'
$script:BlockHudStartupTaskAuthor = 'DMeloper'
$script:BlockHudStartupTaskPrefix = "DMeloper's Block HUD - Rainmeter Fast Startup"
$script:BlockHudStartupTestTaskPrefix = "DMeloper's Block HUD Test - "

function New-BlockHudStartupException {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()][System.Exception]$InnerException = $null
    )

    $exception = if ($null -ne $InnerException) {
        New-Object System.InvalidOperationException($Message, $InnerException)
    }
    else {
        New-Object System.InvalidOperationException($Message)
    }
    $exception.Data['DmelCode'] = $Code
    return $exception
}

function Get-BlockHudStartupExceptionCode {
    param(
        [AllowNull()][System.Exception]$Exception,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FallbackCode
    )

    $current = $Exception
    while ($null -ne $current) {
        if ($current.Data.Contains('DmelCode')) {
            $code = [string]$current.Data['DmelCode']
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                return $code
            }
        }
        $current = $current.InnerException
    }
    return $FallbackCode
}

function ConvertTo-BlockHudTaskException {
    param(
        [Parameter(Mandatory = $true)][System.Exception]$Exception,
        [Parameter(Mandatory = $true)][string]$FallbackCode,
        [Parameter(Mandatory = $true)][string]$FallbackMessage
    )

    $existingCode = Get-BlockHudStartupExceptionCode -Exception $Exception -FallbackCode ''
    if (-not [string]::IsNullOrWhiteSpace($existingCode)) {
        return $Exception
    }

    $hResult = ([int64]$Exception.HResult) -band 0xFFFFFFFFL
    $code = $FallbackCode
    $message = $FallbackMessage
    if ($hResult -eq 0x80070005L) {
        $code = 'TASK_ACCESS_DENIED'
        $message = 'Windows denied access to the Rainmeter fast-startup scheduled task.'
    }
    elseif ($hResult -eq 0x80041315L -or
        $hResult -eq 0x80041322L -or
        $hResult -eq 0x80070422L -or
        $hResult -eq 0x800706BAL) {
        $code = 'TASK_SERVICE_UNAVAILABLE'
        $message = 'The Windows Task Scheduler service is unavailable.'
    }

    return (New-BlockHudStartupException -Code $code -Message $message -InnerException $Exception)
}

function Close-BlockHudComObject {
    param([AllowNull()][object]$Value)

    if ($null -ne $Value -and [System.Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}

function Get-BlockHudStartupFolderPath {
    param([AllowEmptyString()][string]$Override = '')

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return [System.IO.Path]::GetFullPath($Override)
    }
    return [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
}

function Test-BlockHudRainmeterExecutablePath {
    param(
        [AllowNull()][string]$Path,
        [switch]$RequireExisting
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    if (-not [string]::Equals([System.IO.Path]::GetFileName($Path), 'Rainmeter.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    return -not $RequireExisting -or (Test-Path -LiteralPath $Path -PathType Leaf)
}

function ConvertTo-BlockHudShortcutComPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$ExistingFile
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fileSystem = $null
    $entry = $null
    try {
        $fileSystem = New-Object -ComObject Scripting.FileSystemObject
        if ($ExistingFile) {
            $entry = $fileSystem.GetFile($fullPath)
            $shortPath = [string]$entry.ShortPath
            if (-not [string]::IsNullOrWhiteSpace($shortPath)) {
                return $shortPath
            }
        }

        $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
        $entry = $fileSystem.GetFolder($parentPath)
        $shortParent = [string]$entry.ShortPath
        if (-not [string]::IsNullOrWhiteSpace($shortParent)) {
            return (Join-Path $shortParent ([System.IO.Path]::GetFileName($fullPath)))
        }
        return $fullPath
    }
    finally {
        Close-BlockHudComObject -Value $entry
        Close-BlockHudComObject -Value $fileSystem
    }
}

function Resolve-BlockHudShortcutTargetPath {
    param([Parameter(Mandatory = $true)][string]$ShortcutPath)

    $shellApplication = $null
    $folderNamespace = $null
    $shortcutItem = $null
    $shellLink = $null
    try {
        $shortcutComPath = ConvertTo-BlockHudShortcutComPath -Path $ShortcutPath -ExistingFile
        $shellApplication = New-Object -ComObject Shell.Application
        $folderNamespace = $shellApplication.NameSpace([System.IO.Path]::GetDirectoryName($shortcutComPath))
        if ($null -eq $folderNamespace) {
            return $null
        }
        $shortcutItem = $folderNamespace.ParseName([System.IO.Path]::GetFileName($shortcutComPath))
        if ($null -eq $shortcutItem) {
            return $null
        }
        $shellLink = $shortcutItem.GetLink
        $targetPath = [string]$shellLink.Path
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            return $null
        }
        return $targetPath
    }
    catch {
        return $null
    }
    finally {
        Close-BlockHudComObject -Value $shellLink
        Close-BlockHudComObject -Value $shortcutItem
        Close-BlockHudComObject -Value $folderNamespace
        Close-BlockHudComObject -Value $shellApplication
    }
}

function Get-BlockHudRainmeterStartupShortcuts {
    param([Parameter(Mandatory = $true)][string]$StartupFolder)

    $matches = @()
    if ([string]::IsNullOrWhiteSpace($StartupFolder) -or -not (Test-Path -LiteralPath $StartupFolder -PathType Container)) {
        return $matches
    }

    Get-ChildItem -LiteralPath $StartupFolder -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $targetPath = Resolve-BlockHudShortcutTargetPath -ShortcutPath $_.FullName
        if (Test-BlockHudRainmeterExecutablePath -Path $targetPath) {
            $matches += $_.FullName
        }
    }
    return $matches
}

function Get-BlockHudRainmeterExecutablePath {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [AllowEmptyString()][string]$Override = '',
        [AllowEmptyString()][string]$PreferredPath = ''
    )

    foreach ($explicitPath in @($Override, $PreferredPath)) {
        if (-not [string]::IsNullOrWhiteSpace($explicitPath)) {
            $fullPath = [System.IO.Path]::GetFullPath($explicitPath)
            if (Test-BlockHudRainmeterExecutablePath -Path $fullPath -RequireExisting) {
                return $fullPath
            }
            if ($explicitPath -eq $Override) {
                return $null
            }
        }
    }

    foreach ($process in @(Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue)) {
        try {
            $runningPath = [string]$process.Path
            if (Test-BlockHudRainmeterExecutablePath -Path $runningPath -RequireExisting) {
                return [System.IO.Path]::GetFullPath($runningPath)
            }
        }
        catch {
            # Some process owners do not expose the executable path.
        }
    }

    $candidatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidatePaths += Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidatePaths += Join-Path ${env:ProgramFiles(x86)} 'Rainmeter\Rainmeter.exe'
    }
    foreach ($candidate in $candidatePaths) {
        if (Test-BlockHudRainmeterExecutablePath -Path $candidate -RequireExisting) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    foreach ($registryPath in @(
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths\Rainmeter.exe',
        'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths\Rainmeter.exe'
    )) {
        try {
            $candidate = [string](Get-ItemPropertyValue -LiteralPath $registryPath -Name '(default)' -ErrorAction Stop)
            if (Test-BlockHudRainmeterExecutablePath -Path $candidate -RequireExisting) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        }
        catch {
            # App Paths registration is optional.
        }
    }

    foreach ($shortcutPath in @(Get-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder)) {
        $targetPath = Resolve-BlockHudShortcutTargetPath -ShortcutPath $shortcutPath
        if (Test-BlockHudRainmeterExecutablePath -Path $targetPath -RequireExisting) {
            return [System.IO.Path]::GetFullPath($targetPath)
        }
    }
    return $null
}

function Ensure-BlockHudCanonicalRainmeterShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [Parameter(Mandatory = $true)][string]$RainmeterExecutablePath
    )

    if (-not (Test-BlockHudRainmeterExecutablePath -Path $RainmeterExecutablePath -RequireExisting)) {
        throw (New-BlockHudStartupException -Code 'RAINMETER_NOT_FOUND' -Message 'A valid Rainmeter executable could not be resolved.')
    }
    if (-not (Test-Path -LiteralPath $StartupFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $StartupFolder -Force | Out-Null
    }

    $shortcutPath = Join-Path $StartupFolder 'Rainmeter.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        $existingTarget = Resolve-BlockHudShortcutTargetPath -ShortcutPath $shortcutPath
        if ((Test-BlockHudRainmeterExecutablePath -Path $existingTarget -RequireExisting) -and
            (Test-BlockHudSamePath -Left $existingTarget -Right $RainmeterExecutablePath)) {
            return $shortcutPath
        }
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
    }

    $shell = $null
    $shortcut = $null
    try {
        $shortcutTargetPath = ConvertTo-BlockHudShortcutComPath -Path $RainmeterExecutablePath -ExistingFile
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((ConvertTo-BlockHudShortcutComPath -Path $shortcutPath))
        $shortcut.TargetPath = $shortcutTargetPath
        $shortcut.WorkingDirectory = Split-Path -Parent $shortcutTargetPath
        $shortcut.IconLocation = $shortcutTargetPath + ',0'
        $shortcut.Save()
    }
    finally {
        Close-BlockHudComObject -Value $shortcut
        Close-BlockHudComObject -Value $shell
    }

    $verifiedTarget = Resolve-BlockHudShortcutTargetPath -ShortcutPath $shortcutPath
    if ((-not (Test-BlockHudRainmeterExecutablePath -Path $verifiedTarget -RequireExisting)) -or
        (-not (Test-BlockHudSamePath -Left $verifiedTarget -Right $RainmeterExecutablePath))) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        throw (New-BlockHudStartupException -Code 'SHORTCUT_VERIFY_FAILED' -Message 'The Rainmeter startup shortcut could not be verified.')
    }
    return $shortcutPath
}

function Remove-BlockHudRainmeterStartupShortcuts {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [AllowEmptyString()][string]$ExceptPath = ''
    )

    $exceptFullPath = if ([string]::IsNullOrWhiteSpace($ExceptPath)) { '' } else { [System.IO.Path]::GetFullPath($ExceptPath) }
    foreach ($shortcutPath in @(Get-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder)) {
        $fullPath = [System.IO.Path]::GetFullPath($shortcutPath)
        if ($exceptFullPath -ne '' -and [string]::Equals($fullPath, $exceptFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
    }
}

function Get-BlockHudCurrentUserSid {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $null -eq $identity.User) {
        throw (New-BlockHudStartupException -Code 'USER_SID_UNAVAILABLE' -Message 'The current Windows user SID could not be resolved.')
    }
    return [string]$identity.User.Value
}

function Test-BlockHudTaskUserIdentity {
    param(
        [AllowEmptyString()][string]$Identity,
        [Parameter(Mandatory = $true)][string]$ExpectedSid
    )

    if ([string]::Equals($Identity, $ExpectedSid, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return $false
    }

    try {
        $account = New-Object System.Security.Principal.NTAccount($Identity)
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
        return [string]::Equals([string]$sid.Value, $ExpectedSid, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Resolve-BlockHudScheduledTaskName {
    param(
        [AllowEmptyString()][string]$Override = '',
        [AllowEmptyString()][string]$StartupFolderOverride = '',
        [AllowEmptyString()][string]$RainmeterExecutablePathOverride = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if ([string]::IsNullOrWhiteSpace($StartupFolderOverride) -or [string]::IsNullOrWhiteSpace($RainmeterExecutablePathOverride)) {
            throw (New-BlockHudStartupException -Code 'TEST_OVERRIDE_REJECTED' -Message 'A scheduled-task name override requires isolated startup-folder and Rainmeter-path overrides.')
        }
        if (-not $Override.StartsWith($script:BlockHudStartupTestTaskPrefix, [System.StringComparison]::Ordinal)) {
            throw (New-BlockHudStartupException -Code 'TEST_OVERRIDE_REJECTED' -Message 'The scheduled-task name override did not use the required Block HUD test prefix.')
        }
        if ($Override.IndexOf('\') -ge 0 -or $Override.IndexOf('/') -ge 0 -or $Override.IndexOf([char]0) -ge 0) {
            throw (New-BlockHudStartupException -Code 'TEST_OVERRIDE_REJECTED' -Message 'The scheduled-task name override contains an invalid character.')
        }
        return $Override
    }
    return $script:BlockHudStartupTaskPrefix + ' (' + (Get-BlockHudCurrentUserSid) + ')'
}

function New-BlockHudTaskService {
    $service = $null
    try {
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        return $service
    }
    catch {
        Close-BlockHudComObject -Value $service
        throw (ConvertTo-BlockHudTaskException `
            -Exception $_.Exception `
            -FallbackCode 'TASK_SERVICE_UNAVAILABLE' `
            -FallbackMessage 'The Windows Task Scheduler service could not be opened.')
    }
}

function Test-BlockHudSamePath {
    param([AllowNull()][string]$Left, [AllowNull()][string]$Right)

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    try {
        $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\')
        $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
        return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-BlockHudScheduledTaskState {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [AllowEmptyString()][string]$ExpectedRainmeterExecutablePath = ''
    )

    $service = $null
    $folder = $null
    $registeredTask = $null
    $definition = $null
    $registrationInfo = $null
    $principal = $null
    $triggers = $null
    $trigger = $null
    $actions = $null
    $action = $null
    $settings = $null
    try {
        $service = New-BlockHudTaskService
        $folder = $service.GetFolder('\')
        try {
            $registeredTask = $folder.GetTask('\' + $TaskName)
        }
        catch {
            $hResult = [int]$_.Exception.HResult
            if ($hResult -eq -2147024894 -or $hResult -eq -2147024893 -or $hResult -eq -2147216625) {
                return [PSCustomObject]@{
                    TaskState = 'absent'; Exists = $false; Owned = $false; Enabled = $false; Valid = $false; ExecutablePath = ''
                }
            }
            throw
        }

        $definition = $registeredTask.Definition
        $registrationInfo = $definition.RegistrationInfo
        $source = [string]$registrationInfo.Source
        if (-not [string]::Equals($source, $script:BlockHudStartupTaskSource, [System.StringComparison]::Ordinal)) {
            return [PSCustomObject]@{
                TaskState = 'foreign'; Exists = $true; Owned = $false; Enabled = [bool]$registeredTask.Enabled; Valid = $false; ExecutablePath = ''
            }
        }

        $principal = $definition.Principal
        $triggers = $definition.Triggers
        $actions = $definition.Actions
        $settings = $definition.Settings
        $enabled = [bool]$registeredTask.Enabled -and [bool]$settings.Enabled
        $invalidReasons = New-Object System.Collections.Generic.List[string]
        function Add-ValidationResult {
            param([bool]$Condition, [string]$Name)
            if (-not $Condition) {
                [void]$invalidReasons.Add($Name)
            }
        }
        $currentSid = Get-BlockHudCurrentUserSid
        Add-ValidationResult -Condition (Test-BlockHudTaskUserIdentity -Identity ([string]$principal.UserId) -ExpectedSid $currentSid) -Name 'principal-user'
        Add-ValidationResult -Condition ([int]$principal.LogonType -eq 3) -Name 'principal-logon-type'
        Add-ValidationResult -Condition ([int]$principal.RunLevel -eq 0) -Name 'principal-run-level'
        Add-ValidationResult -Condition ([int]$triggers.Count -eq 1) -Name 'trigger-count'
        Add-ValidationResult -Condition ([int]$actions.Count -eq 1) -Name 'action-count'

        $executablePath = ''
        if ([int]$triggers.Count -eq 1) {
            $trigger = $triggers.Item(1)
            $delay = [string]$trigger.Delay
            Add-ValidationResult -Condition ([int]$trigger.Type -eq 9) -Name 'trigger-type'
            Add-ValidationResult -Condition ([bool]$trigger.Enabled) -Name 'trigger-enabled'
            Add-ValidationResult -Condition (Test-BlockHudTaskUserIdentity -Identity ([string]$trigger.UserId) -ExpectedSid $currentSid) -Name 'trigger-user'
            Add-ValidationResult -Condition ([string]::IsNullOrWhiteSpace($delay) -or $delay -eq 'PT0S') -Name 'trigger-delay'
        }
        if ([int]$actions.Count -eq 1) {
            $action = $actions.Item(1)
            $executablePath = [string]$action.Path
            $expectedWorkingDirectory = if ([string]::IsNullOrWhiteSpace($executablePath)) { '' } else { Split-Path -Parent $executablePath }
            Add-ValidationResult -Condition ([int]$action.Type -eq 0) -Name 'action-type'
            Add-ValidationResult -Condition (Test-BlockHudRainmeterExecutablePath -Path $executablePath -RequireExisting) -Name 'action-rainmeter-path'
            Add-ValidationResult -Condition ([string]::IsNullOrWhiteSpace([string]$action.Arguments)) -Name 'action-arguments'
            Add-ValidationResult -Condition (Test-BlockHudSamePath -Left ([string]$action.WorkingDirectory) -Right $expectedWorkingDirectory) -Name 'action-working-directory'
            if (-not [string]::IsNullOrWhiteSpace($ExpectedRainmeterExecutablePath)) {
                Add-ValidationResult -Condition (Test-BlockHudSamePath -Left $executablePath -Right $ExpectedRainmeterExecutablePath) -Name 'action-expected-path'
            }
        }

        Add-ValidationResult -Condition ([int]$settings.Priority -eq 4) -Name 'priority'
        Add-ValidationResult -Condition ([string]$settings.ExecutionTimeLimit -eq 'PT0S') -Name 'execution-time-limit'
        Add-ValidationResult -Condition ([int]$settings.MultipleInstances -eq 2) -Name 'multiple-instances'
        Add-ValidationResult -Condition (-not [bool]$settings.RunOnlyIfIdle) -Name 'idle-condition'
        Add-ValidationResult -Condition (-not [bool]$settings.RunOnlyIfNetworkAvailable) -Name 'network-condition'
        Add-ValidationResult -Condition (-not [bool]$settings.DisallowStartIfOnBatteries) -Name 'battery-start-condition'
        Add-ValidationResult -Condition (-not [bool]$settings.StopIfGoingOnBatteries) -Name 'battery-stop-condition'
        Add-ValidationResult -Condition (-not [bool]$settings.Hidden) -Name 'hidden'
        Add-ValidationResult -Condition (-not [bool]$settings.StartWhenAvailable) -Name 'start-when-available'
        Add-ValidationResult -Condition ([int]$settings.RestartCount -eq 0) -Name 'restart-count'

        $valid = $invalidReasons.Count -eq 0
        $taskState = if (-not $enabled) { 'disabled' } elseif ($valid) { 'valid' } else { 'invalid' }
        return [PSCustomObject]@{
            TaskState = $taskState
            Exists = $true
            Owned = $true
            Enabled = $enabled
            Valid = $enabled -and $valid
            ExecutablePath = $executablePath
            InvalidReasons = @($invalidReasons)
        }
    }
    catch {
        throw (ConvertTo-BlockHudTaskException `
            -Exception $_.Exception `
            -FallbackCode 'TASK_PROBE_FAILED' `
            -FallbackMessage 'The Rainmeter fast-startup scheduled task state could not be read.')
    }
    finally {
        Close-BlockHudComObject -Value $action
        Close-BlockHudComObject -Value $actions
        Close-BlockHudComObject -Value $trigger
        Close-BlockHudComObject -Value $triggers
        Close-BlockHudComObject -Value $settings
        Close-BlockHudComObject -Value $principal
        Close-BlockHudComObject -Value $registrationInfo
        Close-BlockHudComObject -Value $definition
        Close-BlockHudComObject -Value $registeredTask
        Close-BlockHudComObject -Value $folder
        Close-BlockHudComObject -Value $service
    }
}

function Ensure-BlockHudRainmeterScheduledTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$RainmeterExecutablePath
    )

    if (-not (Test-BlockHudRainmeterExecutablePath -Path $RainmeterExecutablePath -RequireExisting)) {
        throw (New-BlockHudStartupException -Code 'RAINMETER_NOT_FOUND' -Message 'A valid Rainmeter executable could not be resolved.')
    }
    $existing = Get-BlockHudScheduledTaskState -TaskName $TaskName -ExpectedRainmeterExecutablePath $RainmeterExecutablePath
    if ($existing.TaskState -eq 'foreign') {
        throw (New-BlockHudStartupException -Code 'TASK_NAME_CONFLICT' -Message 'A scheduled task with the Block HUD fast-startup name already exists but is not owned by Block HUD.')
    }
    if ($existing.TaskState -eq 'valid') {
        return $existing
    }

    $service = $null
    $folder = $null
    $definition = $null
    $registrationInfo = $null
    $principal = $null
    $trigger = $null
    $action = $null
    $settings = $null
    $registeredTask = $null
    try {
        $service = New-BlockHudTaskService
        $folder = $service.GetFolder('\')
        $definition = $service.NewTask(0)
        $registrationInfo = $definition.RegistrationInfo
        $registrationInfo.Author = $script:BlockHudStartupTaskAuthor
        $registrationInfo.Source = $script:BlockHudStartupTaskSource
        $registrationInfo.Description = 'Starts Rainmeter at the current user logon for DMeloper''s Block HUD fast startup.'

        $currentSid = Get-BlockHudCurrentUserSid
        $principal = $definition.Principal
        $principal.UserId = $currentSid
        $principal.LogonType = 3
        $principal.RunLevel = 0

        $trigger = $definition.Triggers.Create(9)
        $trigger.UserId = $currentSid
        $trigger.Enabled = $true

        $action = $definition.Actions.Create(0)
        $action.Path = [System.IO.Path]::GetFullPath($RainmeterExecutablePath)
        $action.Arguments = ''
        $action.WorkingDirectory = Split-Path -Parent $RainmeterExecutablePath

        $settings = $definition.Settings
        $settings.Enabled = $true
        $settings.Priority = 4
        $settings.ExecutionTimeLimit = 'PT0S'
        $settings.MultipleInstances = 2
        $settings.RunOnlyIfIdle = $false
        $settings.RunOnlyIfNetworkAvailable = $false
        $settings.DisallowStartIfOnBatteries = $false
        $settings.StopIfGoingOnBatteries = $false
        $settings.Hidden = $false
        $settings.StartWhenAvailable = $false
        $settings.RestartCount = 0

        $registeredTask = $folder.RegisterTaskDefinition($TaskName, $definition, 6, $currentSid, $null, 3, $null)
    }
    catch {
        throw (ConvertTo-BlockHudTaskException `
            -Exception $_.Exception `
            -FallbackCode 'TASK_REGISTRATION_FAILED' `
            -FallbackMessage 'The Rainmeter fast-startup scheduled task could not be registered.')
    }
    finally {
        Close-BlockHudComObject -Value $registeredTask
        Close-BlockHudComObject -Value $action
        Close-BlockHudComObject -Value $trigger
        Close-BlockHudComObject -Value $settings
        Close-BlockHudComObject -Value $principal
        Close-BlockHudComObject -Value $registrationInfo
        Close-BlockHudComObject -Value $definition
        Close-BlockHudComObject -Value $folder
        Close-BlockHudComObject -Value $service
    }

    $verified = Get-BlockHudScheduledTaskState -TaskName $TaskName -ExpectedRainmeterExecutablePath $RainmeterExecutablePath
    if ($verified.TaskState -ne 'valid') {
        if (-not $existing.Exists) {
            try {
                [void](Remove-BlockHudOwnedScheduledTask -TaskName $TaskName)
            }
            catch {
                # The caller's final probe reports any cleanup failure.
            }
        }
        throw (New-BlockHudStartupException -Code 'TASK_VERIFY_FAILED' -Message 'The Rainmeter fast-startup scheduled task could not be verified after registration.')
    }
    return $verified
}

function Remove-BlockHudOwnedScheduledTask {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    $current = Get-BlockHudScheduledTaskState -TaskName $TaskName
    if (-not $current.Exists -or -not $current.Owned) {
        return $false
    }

    $service = $null
    $folder = $null
    try {
        $service = New-BlockHudTaskService
        $folder = $service.GetFolder('\')
        $folder.DeleteTask($TaskName, 0)
    }
    catch {
        throw (ConvertTo-BlockHudTaskException `
            -Exception $_.Exception `
            -FallbackCode 'TASK_REMOVE_FAILED' `
            -FallbackMessage 'The owned Rainmeter fast-startup task could not be removed.')
    }
    finally {
        Close-BlockHudComObject -Value $folder
        Close-BlockHudComObject -Value $service
    }

    $verified = Get-BlockHudScheduledTaskState -TaskName $TaskName
    if ($verified.TaskState -ne 'absent') {
        throw (New-BlockHudStartupException -Code 'TASK_REMOVE_FAILED' -Message 'The owned Rainmeter fast-startup task could not be removed.')
    }
    return $true
}

function Get-BlockHudStartupRegistrationState {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    $shortcuts = @(Get-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder)
    $task = Get-BlockHudScheduledTaskState -TaskName $TaskName
    $shortcutEnabled = $shortcuts.Count -gt 0
    $fastEnabled = $task.TaskState -eq 'valid'
    $ownedEnabledTask = $task.Owned -and $task.Enabled
    $overallEnabled = $shortcutEnabled -or $ownedEnabledTask
    $method = 'none'
    if ($shortcutEnabled -and $ownedEnabledTask) {
        $method = 'conflict'
    }
    elseif ($shortcutEnabled) {
        $method = 'shortcut'
    }
    elseif ($fastEnabled) {
        $method = 'task'
    }
    elseif ($ownedEnabledTask) {
        $method = 'invalid'
    }

    return [PSCustomObject]@{
        Value = if ($overallEnabled) { '1' } else { '0' }
        FastValue = if ($fastEnabled) { '1' } else { '0' }
        ShortcutValue = if ($shortcutEnabled) { '1' } else { '0' }
        Method = $method
        TaskState = [string]$task.TaskState
        TaskExecutablePath = [string]$task.ExecutablePath
        ShortcutPaths = $shortcuts
    }
}

function Set-BlockHudStartupShortcutMode {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [AllowEmptyString()][string]$RainmeterExecutablePathOverride = ''
    )

    $before = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
    $rainmeterPath = Get-BlockHudRainmeterExecutablePath -StartupFolder $StartupFolder -Override $RainmeterExecutablePathOverride -PreferredPath $before.TaskExecutablePath
    if ([string]::IsNullOrWhiteSpace($rainmeterPath)) {
        throw (New-BlockHudStartupException -Code 'RAINMETER_NOT_FOUND' -Message 'A valid Rainmeter executable could not be resolved.')
    }

    $canonicalShortcut = Ensure-BlockHudCanonicalRainmeterShortcut -StartupFolder $StartupFolder -RainmeterExecutablePath $rainmeterPath
    Remove-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder -ExceptPath $canonicalShortcut
    try {
        [void](Remove-BlockHudOwnedScheduledTask -TaskName $TaskName)
    }
    catch {
        if ($before.FastValue -eq '1' -and $before.ShortcutValue -eq '0') {
            try { Remove-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder } catch {}
        }
        throw
    }

    $after = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
    if ($after.Value -ne '1' -or $after.ShortcutValue -ne '1' -or $after.FastValue -ne '0') {
        throw (New-BlockHudStartupException -Code 'SHORTCUT_TRANSITION_FAILED' -Message 'The startup state did not converge to the standard shortcut method.')
    }
    return $after
}

function Set-BlockHudStartupTaskMode {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [AllowEmptyString()][string]$RainmeterExecutablePathOverride = ''
    )

    $before = $null
    $rainmeterPath = $null
    try {
        $before = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
        $rainmeterPath = Get-BlockHudRainmeterExecutablePath -StartupFolder $StartupFolder -Override $RainmeterExecutablePathOverride -PreferredPath $before.TaskExecutablePath
        if ([string]::IsNullOrWhiteSpace($rainmeterPath)) {
            throw (New-BlockHudStartupException -Code 'RAINMETER_NOT_FOUND' -Message 'A valid Rainmeter executable could not be resolved.')
        }

        [void](Ensure-BlockHudRainmeterScheduledTask -TaskName $TaskName -RainmeterExecutablePath $rainmeterPath)
        Remove-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder

        $after = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
        if ($after.Value -ne '1' -or $after.FastValue -ne '1' -or $after.ShortcutValue -ne '0') {
            throw (New-BlockHudStartupException -Code 'TASK_TRANSITION_FAILED' -Message 'The startup state did not converge to the fast scheduled-task method.')
        }
        return $after
    }
    catch {
        $primaryException = $_.Exception
        if ([string]::IsNullOrWhiteSpace($rainmeterPath)) {
            try {
                $rainmeterPath = Get-BlockHudRainmeterExecutablePath `
                    -StartupFolder $StartupFolder `
                    -Override $RainmeterExecutablePathOverride
            }
            catch {
                $rainmeterPath = ''
            }
        }
        $recovery = Restore-BlockHudStandardStartupFallback `
            -StartupFolder $StartupFolder `
            -TaskName $TaskName `
            -RainmeterExecutablePath $rainmeterPath
        $primaryCode = Get-BlockHudStartupExceptionCode -Exception $primaryException -FallbackCode 'TASK_TRANSITION_FAILED'
        $wrapped = New-BlockHudStartupException -Code $primaryCode -Message ([string]$primaryException.Message) -InnerException $primaryException
        $wrapped.Data['DmelRecovery'] = [string]$recovery.Recovery
        $wrapped.Data['DmelRecoveryCode'] = [string]$recovery.RecoveryCode
        if ($null -ne $recovery.State) {
            $wrapped.Data['DmelState'] = $recovery.State
        }
        throw $wrapped
    }
}

function Restore-BlockHudStandardStartupFallback {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [AllowEmptyString()][string]$RainmeterExecutablePath = ''
    )

    if ([string]::IsNullOrWhiteSpace($RainmeterExecutablePath) -or
        -not (Test-BlockHudRainmeterExecutablePath -Path $RainmeterExecutablePath -RequireExisting)) {
        return [PSCustomObject]@{
            Recovery = 'failed'
            RecoveryCode = 'RAINMETER_NOT_FOUND'
            State = $null
        }
    }

    try {
        $canonical = Ensure-BlockHudCanonicalRainmeterShortcut `
            -StartupFolder $StartupFolder `
            -RainmeterExecutablePath $RainmeterExecutablePath
        Remove-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder -ExceptPath $canonical
    }
    catch {
        $fallbackCode = Get-BlockHudStartupExceptionCode -Exception $_.Exception -FallbackCode 'SHORTCUT_FALLBACK_FAILED'
        $state = $null
        try {
            $state = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
        }
        catch {}
        return [PSCustomObject]@{
            Recovery = 'failed'
            RecoveryCode = $fallbackCode
            State = $state
        }
    }

    try {
        [void](Remove-BlockHudOwnedScheduledTask -TaskName $TaskName)
    }
    catch {
        $removeCode = Get-BlockHudStartupExceptionCode -Exception $_.Exception -FallbackCode 'TASK_REMOVE_FAILED'
        $state = $null
        try {
            $state = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
        }
        catch {}
        if ($null -eq $state) {
            $state = [PSCustomObject]@{
                Value = '1'
                FastValue = ''
                ShortcutValue = '1'
                Method = ''
                TaskState = ''
                TaskExecutablePath = ''
                ShortcutPaths = @($canonical)
            }
        }
        return [PSCustomObject]@{
            Recovery = 'partial'
            RecoveryCode = $removeCode
            State = $state
        }
    }

    try {
        $state = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
    }
    catch {
        return [PSCustomObject]@{
            Recovery = 'partial'
            RecoveryCode = (Get-BlockHudStartupExceptionCode -Exception $_.Exception -FallbackCode 'TASK_PROBE_FAILED')
            State = [PSCustomObject]@{
                Value = '1'
                FastValue = ''
                ShortcutValue = '1'
                Method = ''
                TaskState = ''
                TaskExecutablePath = ''
                ShortcutPaths = @($canonical)
            }
        }
    }

    $recovery = if ($state.Value -eq '1' -and $state.ShortcutValue -eq '1' -and $state.FastValue -eq '0') { 'shortcut' } else { 'partial' }
    $recoveryCode = if ($recovery -eq 'shortcut') { '' } else { 'FAST_STARTUP_RECOVERY_FAILED' }
    return [PSCustomObject]@{
        Recovery = $recovery
        RecoveryCode = $recoveryCode
        State = $state
    }
}

function Disable-BlockHudStartupRegistration {
    param(
        [Parameter(Mandatory = $true)][string]$StartupFolder,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [AllowEmptyString()][string]$RainmeterExecutablePathOverride = ''
    )

    $before = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
    try {
        Remove-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder
        [void](Remove-BlockHudOwnedScheduledTask -TaskName $TaskName)
    }
    catch {
        try {
            $rainmeterPath = Get-BlockHudRainmeterExecutablePath -StartupFolder $StartupFolder -Override $RainmeterExecutablePathOverride -PreferredPath $before.TaskExecutablePath
            if ($before.FastValue -eq '1' -and -not [string]::IsNullOrWhiteSpace($rainmeterPath)) {
                [void](Ensure-BlockHudRainmeterScheduledTask -TaskName $TaskName -RainmeterExecutablePath $rainmeterPath)
            }
            if ($before.ShortcutValue -eq '1' -and -not [string]::IsNullOrWhiteSpace($rainmeterPath)) {
                $canonical = Ensure-BlockHudCanonicalRainmeterShortcut -StartupFolder $StartupFolder -RainmeterExecutablePath $rainmeterPath
                Remove-BlockHudRainmeterStartupShortcuts -StartupFolder $StartupFolder -ExceptPath $canonical
            }
        }
        catch {
            # The final caller probe owns reporting the actual state if rollback also fails.
        }
        throw
    }

    $after = Get-BlockHudStartupRegistrationState -StartupFolder $StartupFolder -TaskName $TaskName
    if ($after.Value -ne '0' -or $after.FastValue -ne '0' -or $after.ShortcutValue -ne '0') {
        throw (New-BlockHudStartupException -Code 'DISABLE_TRANSITION_FAILED' -Message 'The Rainmeter startup registrations could not all be disabled.')
    }
    return $after
}
