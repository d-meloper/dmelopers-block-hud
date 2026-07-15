# OpenVersionManager helpers - Dialogs actions and helper invocation

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Open-FolderPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $target = if (Test-Path -LiteralPath $Path -PathType Container) {
        $Path
    }
    elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        Split-Path -Parent $Path
    }
    else {
        Split-Path -Parent $Path
    }
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        Invoke-Item -LiteralPath $target
    }
}

function Open-FilePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File does not exist: $Path"
    }

    Start-Process -FilePath $Path
}

function Get-VersionManagerDownloadPageUrl {
    $languageCode = [string]$script:LanguageCode
    if ([string]::Equals($languageCode, 'ko-KR', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'https://www.notion.so/aismash/DMeloper-s-Block-HUD-2f72dc0bb4ae80b3bcbad602859e30d2?source=copy_link'
    }

    return 'https://www.notion.so/aismash/DMeloper-s-Block-HUD-Download-Page-35c2dc0bb4ae8184b118c9cbe2508d4c?source=copy_link'
}

function Get-VersionManagerRepositoryUrl {
    param([Parameter(Mandatory = $true)][string]$Root)

    $config = Get-UpdateConfiguration -Root $Root
    $owner = [string]$config.Owner
    $repo = [string]$config.Repo
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
        throw (T 'Helper_VersionManager_Update_RepositoryInfoMissing' 'GitHub repository information is missing.')
    }

    return ('https://github.com/{0}/{1}' -f $owner.Trim(), $repo.Trim())
}

function Confirm-Dialog {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.IWin32Window]$Owner,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = ''
    )

    $dialogResult = Show-VersionManagerMessageBox `
        -Owner $Owner `
        -Message $Message `
        -Title $(if ($Title) { $Title } else { T 'Helper_VersionManager_WindowTitle' 'Skins' }) `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::OKCancel) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    return ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK)
}

function Show-VersionManagerMessageBox {
    param(
        [AllowNull()][System.Windows.Forms.IWin32Window]$Owner,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = '',
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::None
    )

    $caption = if ($Title) { $Title } else { T 'Helper_VersionManager_WindowTitle' 'Skins' }
    $ownerForm = $Owner -as [System.Windows.Forms.Form]
    if ($null -eq $Owner) {
        return [System.Windows.Forms.MessageBox]::Show($Message, $caption, $Buttons, $Icon)
    }
    if ($null -eq $ownerForm) {
        return [System.Windows.Forms.MessageBox]::Show($Owner, $Message, $caption, $Buttons, $Icon)
    }
    if ($ownerForm.IsDisposed) {
        return [System.Windows.Forms.MessageBox]::Show($Message, $caption, $Buttons, $Icon)
    }

    $wasTopMost = [bool]$ownerForm.TopMost
    try {
        $ownerForm.TopMost = $false
        $ownerForm.Activate()
        return [System.Windows.Forms.MessageBox]::Show($ownerForm, $Message, $caption, $Buttons, $Icon)
    }
    finally {
        if (-not $ownerForm.IsDisposed) {
            $ownerForm.TopMost = $wasTopMost
            $ownerForm.Activate()
        }
    }
}

function Get-SkinRootLabel {
    param([Parameter(Mandatory = $true)][string]$Root)

    return [System.IO.Path]::GetFileName($Root.TrimEnd('\', '/'))
}

function Show-SourceEntryDialog {
    param(
        [System.Windows.Forms.IWin32Window]$Owner,
        [string]$InitialPath = ''
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T 'Helper_VersionManager_SourceDialog_Title' 'Source entry'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(560, 128)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = T 'Helper_VersionManager_Common_Path' 'Path'
    $pathLabel.AutoSize = $true
    $pathLabel.Location = New-Object System.Drawing.Point(12, 16)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Bounds = New-Object System.Drawing.Rectangle(88, 12, 364, 24)
    $pathBox.Text = $InitialPath

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = T 'Helper_VersionManager_SourceDialog_Browse' 'Browse'
    $browseButton.Bounds = New-Object System.Drawing.Rectangle(460, 10, 80, 28)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = T 'Helper_VersionManager_SourceDialog_Hint' 'Choose the old skin root folder or its parent folder.'
    $hint.AutoSize = $false
    $hint.Bounds = New-Object System.Drawing.Rectangle(12, 50, 528, 28)
    $hint.ForeColor = [System.Drawing.Color]::DimGray

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = T 'Common_Save' 'Save'
    $okButton.Bounds = New-Object System.Drawing.Rectangle(352, 88, 88, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = T 'Common_Close' 'Close'
    $cancelButton.Bounds = New-Object System.Drawing.Rectangle(452, 88, 88, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $skinsRoot = Get-RainmeterSkinsRoot

    $browseButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = T 'Helper_VersionManager_SourceDialog_FolderPrompt' 'Select the old Block HUD folder.'
        $dialog.ShowNewFolderButton = $false
        if (-not [string]::IsNullOrWhiteSpace($pathBox.Text) -and (Test-Path -LiteralPath $pathBox.Text -PathType Container)) {
            $dialog.SelectedPath = $pathBox.Text
        }
        elseif (-not [string]::IsNullOrWhiteSpace($skinsRoot)) {
            $dialog.SelectedPath = $skinsRoot
        }

        $dialogOwner = [System.Windows.Forms.IWin32Window]$form
        if ($dialog.ShowDialog($dialogOwner) -eq [System.Windows.Forms.DialogResult]::OK) {
            $pathBox.Text = $dialog.SelectedPath
        }
    })

    $form.Controls.AddRange(@($pathLabel, $pathBox, $browseButton, $hint, $okButton, $cancelButton))
    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog($Owner) -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $null
    }

    $resolved = Resolve-SkinRootCandidate -Candidate $pathBox.Text
    if (-not $resolved) {
        Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_SourceDialog_InvalidRoot' 'The selected path is not a valid Block HUD skin root.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $form.Dispose()
        return $null
    }

    $result = [PSCustomObject]@{
        Label = Get-SkinRootLabel -Root $resolved
        Path = $resolved
    }
    $form.Dispose()
    return $result
}

function Invoke-ImportFromInstallation {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $importScript = Get-ImportHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $importScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Install_HelperMissing' 'ImportFromOldVersion.ps1 was not found.')
    }

    $output = @(& (Get-PowerShellExecutablePath) -NoProfile -ExecutionPolicy Bypass -STA -File $importScript -TargetRoot $Root -SourceRoot $SourcePath -EmitResultPairs 2>&1)
    $exitCode = $LASTEXITCODE
    $pairs = @{}
    foreach ($line in $output) {
        $textLine = [string]$line
        if ($textLine -match '^(DMEL_[A-Z]+)=(.*)$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }

    $status = [string]($pairs['DMEL_STATUS'])
    $message = [string]($pairs['DMEL_MESSAGE'])
    $sourcePath = [string]($pairs['DMEL_SOURCEPATH'])
    $logPath = [string]($pairs['DMEL_LOGPATH'])
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'ERROR'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = T 'Helper_VersionManager_Install_HelperStatusMissing' 'Import helper did not emit DMEL_STATUS.'
        }
    }
    else {
        $status = $status.ToUpperInvariant()
    }

    if ($status -eq 'OK') {
        $missingContract = New-Object System.Collections.Generic.List[string]
        if ([string]::IsNullOrWhiteSpace($sourcePath)) {
            $missingContract.Add('DMEL_SOURCEPATH')
        }
        if ([string]::IsNullOrWhiteSpace($logPath)) {
            $missingContract.Add('DMEL_LOGPATH')
        }
        if ($missingContract.Count -gt 0) {
            $status = 'ERROR'
            $message = 'Import helper reported success without required result fields: ' + ($missingContract.ToArray() -join ', ')
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = $sourcePath
        LogPath = $logPath
        Output = ($output | Out-String)
    }
}

function Get-UpdateCache {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (Read-VersionManagerUpdateCache -Root $Root)
}

function Save-UpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Cache
    )

    try {
        return (Save-VersionManagerUpdateCache -Root $Root -Cache $Cache)
    }
    catch {
        $normalized = ConvertTo-VersionManagerUpdateCacheObject -Cache $Cache
        Write-JsonFile -Path (Get-UpdateCachePath -Root $Root) -Value $normalized
        return $normalized
    }
}

function Update-UpdateCache {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Patch
    )

    try {
        return (Update-VersionManagerUpdateCache -Root $Root -Patch $Patch)
    }
    catch {
        $current = Get-UpdateCache -Root $Root
        $merged = Merge-VersionManagerUpdateCache -BaseCache $current -PatchCache $Patch
        Write-JsonFile -Path (Get-UpdateCachePath -Root $Root) -Value $merged
        return $merged
    }
}

function Test-UpdateConfigured {
    param($Config)

    $activePattern = $null
    try {
        $activePattern = Resolve-ActiveUpdateAssetPattern -Config $Config
    }
    catch {
        return $false
    }

    return (
        [string]::Equals([string]$Config.Provider, 'github', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.Owner) -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.Repo) -and
        -not [string]::IsNullOrWhiteSpace([string]$activePattern.AssetPattern)
    )
}

function Convert-VersionManagerOutputToResultPairs {
    param([object[]]$Output)

    $pairs = @{}
    foreach ($line in @($Output)) {
        $textLine = [string]$line
        if ($textLine -match '^(DMEL_[A-Z]+)=(.*)$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }

    return $pairs
}

function Invoke-VersionReleaseCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$ForceRefresh,
        [ValidateRange(5, 120)][int]$ProcessTimeoutSeconds = 25
    )

    $catalogScript = Get-VersionCatalogHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $catalogScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Update_VersionCatalogBackendRequired' (U '\uBC84\uC804 \uBAA9\uB85D \uC870\uD68C/\uC124\uCE58 \uBC31\uC5D4\uB4DC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.'))
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $catalogScript, '-CurrentTargetRoot', $Root, '-OutputJson', '-SyncUpdateCache')
    if (-not $ForceRefresh) {
        $arguments += '-PreferFreshCache'
    }

    $process = $null
    $exitCode = $null
    $jsonText = ''
    $errorText = ''
    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = New-VersionManagerHostProcessStartInfo -Arguments $arguments -RedirectOutput
        if (-not $process.Start()) {
            throw 'Version catalog helper process could not be started.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $deadline = [DateTime]::UtcNow.AddSeconds($ProcessTimeoutSeconds)
        while (-not $process.WaitForExit(50)) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:VersionManagerWindowClosing) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
                throw 'Version catalog request was canceled because the Skin manager is closing.'
            }
            if ([DateTime]::UtcNow -ge $deadline) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
                throw ("Version catalog request exceeded the {0}-second operation deadline." -f $ProcessTimeoutSeconds)
            }
        }
        $process.Refresh()
        $candidateExitCode = $process.ExitCode
        if ($null -ne $candidateExitCode) {
            $exitCode = [int]$candidateExitCode
        }
        $jsonText = ([string]$stdoutTask.Result).Trim()
        $errorText = ([string]$stderrTask.Result).Trim()
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw ("Version catalog helper did not emit JSON. {0}" -f $errorText)
    }

    $catalog = $null
    try {
        $catalog = $jsonText | ConvertFrom-Json
    }
    catch {
        throw ("Version catalog helper emitted invalid JSON. exitCode={0}; output={1}; error={2}" -f $exitCode, $jsonText, $errorText)
    }

    $status = [string](Get-ObjectPropertyValue -Object $catalog -Name 'status' -DefaultValue '')
    $message = [string](Get-ObjectPropertyValue -Object $catalog -Name 'message' -DefaultValue '')
    if ((($null -ne $exitCode) -and $exitCode -ne 0) -or [string]::Equals($status, 'ERROR', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Version catalog helper failed with exit code $exitCode."
        }
        throw $message
    }

    return $catalog
}

function Invoke-VersionReleaseInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$PackageUrl,
        [string]$ExpectedVersion,
        [string]$ExpectedReleaseVariant,
        [string]$SelectedTargetRoot,
        [switch]$AllowCompatibilityWarning
    )

    $installScript = Get-VersionReleaseInstallHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Update_VersionCatalogBackendRequired' (U '\uBC84\uC804 \uBAA9\uB85D \uC870\uD68C/\uC124\uCE58 \uBC31\uC5D4\uB4DC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.'))
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installScript, '-CurrentTargetRoot', $Root, '-EmitResultPairs')
    if (-not [string]::IsNullOrWhiteSpace($SelectedTargetRoot)) {
        $arguments += @('-SelectedTargetRoot', $SelectedTargetRoot)
    }
    else {
        $arguments += @('-PackageUrl', $PackageUrl, '-ExpectedVersion', $ExpectedVersion)
        if ($AllowCompatibilityWarning) {
            $arguments += '-AllowCompatibilityWarning'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        $arguments += @('-ExpectedReleaseVariant', $ExpectedReleaseVariant)
    }
    $process = $null
    $exitCode = $null
    $output = @()
    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = New-VersionManagerHostProcessStartInfo -Arguments $arguments -RedirectOutput
        if (-not $process.Start()) {
            throw 'Version install helper process could not be started.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(100)) {
            [System.Windows.Forms.Application]::DoEvents()
        }
        $process.Refresh()
        $candidateExitCode = $process.ExitCode
        if ($null -ne $candidateExitCode) {
            $exitCode = [int]$candidateExitCode
        }
        $outputLines = @(([string]$stdoutTask.Result) -split "\r?\n" | Where-Object { $_ -ne '' })
        $errorLines = @(([string]$stderrTask.Result) -split "\r?\n" | Where-Object { $_ -ne '' })
        $output = @($outputLines + $errorLines)
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    $pairs = Convert-VersionManagerOutputToResultPairs -Output $output
    $status = [string]($pairs['DMEL_STATUS'])
    $message = [string]($pairs['DMEL_MESSAGE'])
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = 'ERROR'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Install helper did not emit DMEL_STATUS."
        }
    }
    $status = $status.ToUpperInvariant()

    if ($status -ne 'OK' -and $status -ne 'WARN' -and $status -ne 'ERROR' -and $status -ne 'NOOP') {
        $message = "Install helper emitted unsupported DMEL_STATUS '$status'."
        $status = 'ERROR'
    }

    if ($status -eq 'OK' -or $status -eq 'WARN' -or $status -eq 'NOOP') {
        $missingContract = New-Object System.Collections.Generic.List[string]
        if (($status -eq 'OK' -or $status -eq 'NOOP') -and [string]::IsNullOrWhiteSpace([string]($pairs['DMEL_SOURCEPATH']))) {
            $missingContract.Add('DMEL_SOURCEPATH')
        }
        if ([string]::IsNullOrWhiteSpace([string]($pairs['DMEL_LOGPATH']))) {
            $missingContract.Add('DMEL_LOGPATH')
        }
        if ($missingContract.Count -gt 0) {
            $status = 'ERROR'
            $message = 'Install helper reported success without required result fields: ' + ($missingContract.ToArray() -join ', ')
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = [string]($pairs['DMEL_SOURCEPATH'])
        LogPath = [string]($pairs['DMEL_LOGPATH'])
        Output = ($output | Out-String)
    }
}

function Invoke-ClearDownloadCache {
    param([Parameter(Mandatory = $true)][string]$Root)

    $downloadsRoot = Join-RootPath -Root (Get-VersionManagerDataRoot -Root $Root) -RelativePath 'VersionManagerDownloads'
    if (Test-Path -LiteralPath $downloadsRoot -PathType Container) {
        Remove-Item -LiteralPath $downloadsRoot -Force -Recurse
    }
    $cache = Update-UpdateCache -Root $Root -Patch ([PSCustomObject]@{
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
    })
    return $cache
}

function Get-VersionManagerSessionProcesses {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    try {
        $state = Read-JsonFile -Path (Get-VersionManagerLaunchStatePath -Root $ResolvedTargetRoot)
        if ($null -eq $state) {
            return @()
        }

        $status = [string](Get-ObjectPropertyValue -Object $state -Name 'Status' -DefaultValue '')
        if ($status -notin @('launching', 'initializing', 'shown')) {
            return @()
        }

        $processId = [int](Get-ObjectPropertyValue -Object $state -Name 'ProcessId' -DefaultValue 0)
        if ($processId -le 0 -or $processId -eq $PID) {
            return @()
        }

        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return @()
        }

        if ($process.ProcessName -notin @('BlockHudPowerShellHost', 'powershell', 'pwsh')) {
            Write-Log ("Skipping existing version manager session cleanup because launch-state PID {0} is now '{1}'." -f $processId, $process.ProcessName) 'WARN'
            return @()
        }

        return @($process)
    }
    catch {
        Write-Log ("Skipping existing version manager session cleanup after launch-state check failed: {0}" -f $_.Exception.Message) 'WARN'
    }
    return @()
}

function Stop-VersionManagerSessions {
    param([Parameter(Mandatory = $true)][string]$ResolvedTargetRoot)

    foreach ($process in @(Get-VersionManagerSessionProcesses -ResolvedTargetRoot $ResolvedTargetRoot)) {
        try {
            $processId = [int]$process.Id
            if ($processId -le 0) {
                continue
            }
            Write-Log ("Stopping existing version manager session PID {0}" -f $processId)
            Stop-Process -Id $processId -Force -ErrorAction Stop
            try {
                Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
            }
            catch {
            }
        }
        catch {
            Write-Log ("Failed to stop existing version manager session: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Start-VersionManagerLauncherForRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedTargetRoot
    )

    if (-not (Test-SkinRoot -Root $resolvedTargetRoot)) {
        throw 'TargetRoot is not a valid Block HUD skin root.'
    }

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $resolvedTargetRoot -ScriptRoot (Get-VersionManagerToolsRoot)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath

    Write-VersionManagerLaunchDiagnostic -Root $resolvedTargetRoot -Stage 'launcher-before-session-cleanup' -LaunchTokenValue $LaunchToken -Details @(
        ('script={0}' -f (Get-VersionManagerEntrypointPath))
    )
    Stop-VersionManagerSessions -ResolvedTargetRoot $resolvedTargetRoot
    Write-VersionManagerLaunchDiagnostic -Root $resolvedTargetRoot -Stage 'launcher-after-session-cleanup' -LaunchTokenValue $LaunchToken
    Save-VersionManagerLaunchState -Root $resolvedTargetRoot -Status 'launching' -LaunchTokenValue $LaunchToken

    $powershellExe = Get-PowerShellExecutablePath
    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-STA'
        '-File'
        (Get-VersionManagerEntrypointPath)
        '-TargetRoot'
        $resolvedTargetRoot
        '-WindowSession'
    )
    if (-not [string]::IsNullOrWhiteSpace($LaunchToken)) {
        $argumentList += @('-LaunchToken', $LaunchToken)
    }
    if (-not [string]::IsNullOrWhiteSpace($InitialAction)) {
        $argumentList += @('-InitialAction', $InitialAction)
    }

    $startInfo = New-VersionManagerHostProcessStartInfo -Arguments $argumentList
    $startedProcess = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $startedProcess) {
        throw 'The Skin manager window session process could not be started.'
    }
    Write-Log ("Started version manager window session PID {0}" -f $startedProcess.Id)
    Write-VersionManagerLaunchDiagnostic -Root $resolvedTargetRoot -Stage 'launcher-child-started' -LaunchTokenValue $LaunchToken -Details @(
        ('childPid={0}' -f $startedProcess.Id),
        ('powershell={0}' -f $powershellExe)
    )
    return $startedProcess
}

function Start-VersionManagerLauncher {
    $root = Get-TargetRoot
    $process = Start-VersionManagerLauncherForRoot -ResolvedTargetRoot $root
    $launchResult = Wait-VersionManagerLaunchShown -Root $root -ExpectedLaunchToken $LaunchToken -Process $process
    Write-VersionManagerLaunchDiagnostic -Root $root -Stage ('launcher-wait-' + [string]$launchResult.Status) -LaunchTokenValue $LaunchToken -Message ([string]$launchResult.Message) -Details @(
        ('observedStatus={0}' -f [string]$launchResult.ObservedStatus),
        ('observedToken={0}' -f [string]$launchResult.ObservedToken)
    )
    return $launchResult
}
