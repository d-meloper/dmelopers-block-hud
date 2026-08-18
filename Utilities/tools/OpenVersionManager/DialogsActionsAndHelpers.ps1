# OpenVersionManager helpers - Dialogs actions and helper invocation

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Test-OpenVersionManagerScriptSupportsParameter {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return $false
    }

    try {
        $content = Read-TextSmart -Path $ScriptPath
        return ($content -match ('(?i)\$' + [regex]::Escape($ParameterName) + '\b'))
    }
    catch {
        return $false
    }
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
        Start-DetachedExplorer -Target ([System.IO.Path]::GetFullPath($target))
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

    $ownerForm.TopMost = $true
    $ownerForm.BringToFront()
    $ownerForm.Activate()
    try {
        return [System.Windows.Forms.MessageBox]::Show($ownerForm, $Message, $caption, $Buttons, $Icon)
    }
    finally {
        if (-not $ownerForm.IsDisposed) {
            $ownerForm.TopMost = $true
            $ownerForm.BringToFront()
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
    $form.Add_Shown({
        $form.TopMost = $true
        $form.BringToFront()
        $form.Activate()
    })

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
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string]$ProgressOwnerRoot = '',
        [string]$ProgressToken = ''
    )

    $importScript = Get-ImportHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $importScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Install_HelperMissing' 'ImportFromOldVersion.ps1 was not found.')
    }

    $importParameters = [ordered]@{
        TargetRoot = $Root
        SourceRoot = $SourcePath
        NonInteractive = $true
    }
    $supportsProgressOwner = Test-OpenVersionManagerScriptSupportsParameter -ScriptPath $importScript -ParameterName 'ProgressOwnerRoot'
    $supportsProgressToken = Test-OpenVersionManagerScriptSupportsParameter -ScriptPath $importScript -ParameterName 'ProgressToken'
    if ($supportsProgressOwner -and $supportsProgressToken -and
        -not [string]::IsNullOrWhiteSpace($ProgressOwnerRoot) -and
        -not [string]::IsNullOrWhiteSpace($ProgressToken)) {
        $importParameters['ProgressOwnerRoot'] = $ProgressOwnerRoot
        $importParameters['ProgressToken'] = $ProgressToken
    }
    elseif ($supportsProgressOwner -xor $supportsProgressToken) {
        Write-Log 'Import helper exposes an incomplete progress contract; using the legacy non-determinate UI.' 'WARN'
    }

    $passThruResult = Invoke-VersionManagerPassThruScript `
        -ScriptPath $importScript `
        -Parameters $importParameters `
        -PassThruParameter 'PassThruResultObject' `
        -RequiredProperty 'DMEL_STATUS' `
        -TimeoutSeconds 1800
    if ($null -ne $passThruResult) {
        $status = ([string]$passThruResult.DMEL_STATUS).ToUpperInvariant()
        return [PSCustomObject]@{
            ExitCode = $(if ($status -eq 'ERROR') { 1 } else { 0 })
            Status = $status
            Message = [string]$passThruResult.DMEL_MESSAGE
            SourcePath = [string]$passThruResult.DMEL_SOURCEPATH
            LogPath = [string]$passThruResult.DMEL_LOGPATH
            Output = ''
        }
    }
    try {
        Write-Log 'Import helper uses the legacy external-process compatibility path.' 'WARN'
    }
    catch {
    }

    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-STA'
        '-File'
        $importScript
        '-TargetRoot'
        $Root
        '-SourceRoot'
        $SourcePath
        '-EmitResultPairs'
    )
    if ($supportsProgressOwner -and $supportsProgressToken -and
        -not [string]::IsNullOrWhiteSpace($ProgressOwnerRoot) -and
        -not [string]::IsNullOrWhiteSpace($ProgressToken)) {
        $arguments += @('-ProgressOwnerRoot', $ProgressOwnerRoot, '-ProgressToken', $ProgressToken)
    }
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo = New-VersionManagerHostProcessStartInfo -Arguments $arguments -RedirectOutput
        if (-not $process.Start()) {
            throw 'Import helper process could not be started.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $stdoutText = [string]$stdoutTask.Result
        $stderrText = [string]$stderrTask.Result
    }
    finally {
        $process.Dispose()
    }

    $output = @()
    foreach ($streamText in @($stdoutText, $stderrText)) {
        if (-not [string]::IsNullOrEmpty([string]$streamText)) {
            $output += @([string]$streamText -split "\r?\n" | Where-Object { $_ -ne '' })
        }
    }
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

function Test-VersionManagerScriptParameter {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )

    try {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
        if ($null -eq $ast -or $null -eq $ast.ParamBlock) {
            return $false
        }
        foreach ($parameter in @($ast.ParamBlock.Parameters)) {
            if ([string]::Equals([string]$parameter.Name.VariablePath.UserPath, $ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    catch {
        try {
            Write-Log ("Could not inspect helper parameter contract: {0}" -f $_.Exception.Message) 'WARN'
        }
        catch {
        }
    }
    return $false
}

function Invoke-VersionManagerPassThruScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Parameters,
        [Parameter(Mandatory = $true)][string]$PassThruParameter,
        [Parameter(Mandatory = $true)][string]$RequiredProperty,
        [ValidateRange(5, 3600)][int]$TimeoutSeconds = 1800
    )

    if (-not (Test-VersionManagerScriptParameter -ScriptPath $ScriptPath -ParameterName $PassThruParameter)) {
        return $null
    }
    $invocationParameters = [ordered]@{}
    foreach ($entry in $Parameters.GetEnumerator()) {
        $invocationParameters[[string]$entry.Key] = $entry.Value
    }
    $invocationParameters[$PassThruParameter] = $true
    $invocation = Invoke-VersionManagerIsolatedScript `
        -ScriptPath $ScriptPath `
        -Parameters $invocationParameters `
        -TimeoutSeconds $TimeoutSeconds `
        -CancelWhenWindowCloses
    $resultObject = Get-VersionManagerPassThruObject -Output $invocation.Output -RequiredProperty $RequiredProperty
    if ($null -eq $resultObject) {
        $detail = [string]::Join(' | ', @($invocation.Errors))
        throw ("Helper did not return the required pass-through object ({0}). {1}" -f $RequiredProperty, $detail)
    }
    return $resultObject
}

function Get-VersionInstallCompatibilityContractError {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Compatibility = '',
        [string]$RepairCount = '',
        [string]$RepairPlanId = ''
    )

    if (-not [string]::Equals($Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($Compatibility, 'REPAIRABLE', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    $countValue = 0
    if ($RepairPlanId -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not [int]::TryParse($RepairCount, [ref]$countValue) -or
        $countValue -le 0) {
        return 'Install helper reported a repairable compatibility warning without a valid repair count and SHA-256 plan id.'
    }
    return ''
}

function Invoke-VersionReleaseInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$PackageUrl,
        [string]$ExpectedPackageSha256 = '',
        [string]$ExpectedVersion,
        [string]$ExpectedReleaseVariant,
        [string]$SelectedTargetRoot,
        [switch]$AllowCompatibilityWarning,
        [string]$ExpectedRepairPlanId = '',
        [string]$ProgressOwnerRoot = '',
        [string]$ProgressToken = ''
    )

    $installScript = Get-VersionReleaseInstallHelperPath -Root $Root
    if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
        throw (T 'Helper_VersionManager_Update_InstallBackendRequired' (U '\uBC84\uC804 \uC124\uCE58 \uBC31\uC5D4\uB4DC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.'))
    }

    $passThruParameters = [ordered]@{
        CurrentTargetRoot = $Root
    }
    if (-not [string]::IsNullOrWhiteSpace($SelectedTargetRoot)) {
        $passThruParameters['SelectedTargetRoot'] = $SelectedTargetRoot
    }
    else {
        $normalizedExpectedSha256 = $ExpectedPackageSha256.Trim().ToUpperInvariant()
        if ($normalizedExpectedSha256 -notmatch '^[0-9A-F]{64}$') {
            throw 'A valid ExpectedPackageSha256 is required for a downloaded version install.'
        }
        if (-not (Test-OpenVersionManagerScriptSupportsParameter -ScriptPath $installScript -ParameterName 'ExpectedPackageSha256')) {
            throw 'The version install backend does not support required release checksum verification.'
        }
        $passThruParameters['PackageUrl'] = $PackageUrl
        $passThruParameters['ExpectedPackageSha256'] = $normalizedExpectedSha256
        $passThruParameters['ExpectedVersion'] = $ExpectedVersion
        if ($AllowCompatibilityWarning) {
            $passThruParameters['AllowCompatibilityWarning'] = $true
            if (-not [string]::IsNullOrWhiteSpace($ExpectedRepairPlanId)) {
                $passThruParameters['ExpectedRepairPlanId'] = $ExpectedRepairPlanId
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        $passThruParameters['ExpectedReleaseVariant'] = $ExpectedReleaseVariant
    }
    $supportsProgressOwner = Test-OpenVersionManagerScriptSupportsParameter -ScriptPath $installScript -ParameterName 'ProgressOwnerRoot'
    $supportsProgressToken = Test-OpenVersionManagerScriptSupportsParameter -ScriptPath $installScript -ParameterName 'ProgressToken'
    if ($supportsProgressOwner -and $supportsProgressToken -and
        -not [string]::IsNullOrWhiteSpace($ProgressOwnerRoot) -and
        -not [string]::IsNullOrWhiteSpace($ProgressToken)) {
        $passThruParameters['ProgressOwnerRoot'] = $ProgressOwnerRoot
        $passThruParameters['ProgressToken'] = $ProgressToken
    }
    elseif ($supportsProgressOwner -xor $supportsProgressToken) {
        Write-Log 'Version install helper exposes an incomplete progress contract; using the legacy non-determinate UI.' 'WARN'
    }
    $passThruResult = Invoke-VersionManagerPassThruScript `
        -ScriptPath $installScript `
        -Parameters $passThruParameters `
        -PassThruParameter 'PassThruResultObject' `
        -RequiredProperty 'DMEL_STATUS' `
        -TimeoutSeconds 3600
    if ($null -ne $passThruResult) {
        $status = ([string]$passThruResult.DMEL_STATUS).ToUpperInvariant()
        $message = [string]$passThruResult.DMEL_MESSAGE
        $compatibility = [string](Get-ObjectPropertyValue -Object $passThruResult -Name 'DMEL_COMPATIBILITY' -DefaultValue '')
        $repairCount = [string](Get-ObjectPropertyValue -Object $passThruResult -Name 'DMEL_REPAIRCOUNT' -DefaultValue '0')
        $repairSummary = [string](Get-ObjectPropertyValue -Object $passThruResult -Name 'DMEL_REPAIRSUMMARY' -DefaultValue '')
        $repairPlanId = [string](Get-ObjectPropertyValue -Object $passThruResult -Name 'DMEL_REPAIRPLANID' -DefaultValue '')
        if ($status -ne 'OK' -and $status -ne 'WARN' -and $status -ne 'ERROR' -and $status -ne 'NOOP') {
            $message = "Install helper emitted unsupported DMEL_STATUS '$status'."
            $status = 'ERROR'
        }
        if ($status -eq 'OK' -or $status -eq 'WARN' -or $status -eq 'NOOP') {
            $missingContract = New-Object System.Collections.Generic.List[string]
            if (($status -eq 'OK' -or $status -eq 'NOOP') -and [string]::IsNullOrWhiteSpace([string]$passThruResult.DMEL_SOURCEPATH)) {
                $missingContract.Add('DMEL_SOURCEPATH')
            }
            if ([string]::IsNullOrWhiteSpace([string]$passThruResult.DMEL_LOGPATH)) {
                $missingContract.Add('DMEL_LOGPATH')
            }
            if ($missingContract.Count -gt 0) {
                $message = 'Install helper reported success without required result fields: ' + ($missingContract.ToArray() -join ', ')
                $status = 'ERROR'
            }
        }
        $compatibilityContractError = Get-VersionInstallCompatibilityContractError -Status $status -Compatibility $compatibility -RepairCount $repairCount -RepairPlanId $repairPlanId
        if (-not [string]::IsNullOrWhiteSpace($compatibilityContractError)) {
            $message = $compatibilityContractError
            $status = 'ERROR'
        }
        return [PSCustomObject]@{
            ExitCode = $(if ($status -eq 'ERROR') { 1 } else { 0 })
            Status = $status
            Message = $message
            SourcePath = [string]$passThruResult.DMEL_SOURCEPATH
            LogPath = [string]$passThruResult.DMEL_LOGPATH
            Compatibility = $compatibility
            RepairCount = $repairCount
            RepairSummary = $repairSummary
            RepairPlanId = $repairPlanId
            Output = ''
        }
    }
    try {
        Write-Log 'Version install helper uses the legacy external-process compatibility path.' 'WARN'
    }
    catch {
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installScript, '-CurrentTargetRoot', $Root, '-EmitResultPairs')
    if (-not [string]::IsNullOrWhiteSpace($SelectedTargetRoot)) {
        $arguments += @('-SelectedTargetRoot', $SelectedTargetRoot)
    }
    else {
        $arguments += @('-PackageUrl', $PackageUrl, '-ExpectedPackageSha256', $normalizedExpectedSha256, '-ExpectedVersion', $ExpectedVersion)
        if ($AllowCompatibilityWarning) {
            $arguments += '-AllowCompatibilityWarning'
            if (-not [string]::IsNullOrWhiteSpace($ExpectedRepairPlanId)) {
                $arguments += @('-ExpectedRepairPlanId', $ExpectedRepairPlanId)
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseVariant)) {
        $arguments += @('-ExpectedReleaseVariant', $ExpectedReleaseVariant)
    }
    if ($supportsProgressOwner -and $supportsProgressToken -and
        -not [string]::IsNullOrWhiteSpace($ProgressOwnerRoot) -and
        -not [string]::IsNullOrWhiteSpace($ProgressToken)) {
        $arguments += @('-ProgressOwnerRoot', $ProgressOwnerRoot, '-ProgressToken', $ProgressToken)
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

    $compatibility = [string]($pairs['DMEL_COMPATIBILITY'])
    $repairCount = [string]($pairs['DMEL_REPAIRCOUNT'])
    $repairSummary = [string]($pairs['DMEL_REPAIRSUMMARY'])
    $repairPlanId = [string]($pairs['DMEL_REPAIRPLANID'])
    $compatibilityContractError = Get-VersionInstallCompatibilityContractError -Status $status -Compatibility $compatibility -RepairCount $repairCount -RepairPlanId $repairPlanId
    if (-not [string]::IsNullOrWhiteSpace($compatibilityContractError)) {
        $message = $compatibilityContractError
        $status = 'ERROR'
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Status = $status
        Message = $message
        SourcePath = [string]($pairs['DMEL_SOURCEPATH'])
        LogPath = [string]($pairs['DMEL_LOGPATH'])
        Compatibility = $compatibility
        RepairCount = $repairCount
        RepairSummary = $repairSummary
        RepairPlanId = $repairPlanId
        Output = ($output | Out-String)
    }
}

function ConvertTo-CurrentSkinResetResult {
    param(
        [AllowNull()]$ResultObject,
        [int]$ExitCode = 0,
        [string]$Output = ''
    )

    $status = ([string](Get-ObjectPropertyValue -Object $ResultObject -Name 'DMEL_STATUS' -DefaultValue '')).Trim().ToUpperInvariant()
    $message = [string](Get-ObjectPropertyValue -Object $ResultObject -Name 'DMEL_MESSAGE' -DefaultValue '')
    $sourcePath = [string](Get-ObjectPropertyValue -Object $ResultObject -Name 'DMEL_SOURCEPATH' -DefaultValue '')
    $logPath = [string](Get-ObjectPropertyValue -Object $ResultObject -Name 'DMEL_LOGPATH' -DefaultValue '')
    if ($status -ne 'OK' -and $status -ne 'NOOP' -and $status -ne 'WARN' -and $status -ne 'ERROR') {
        $message = "Current-skin reset helper emitted unsupported DMEL_STATUS '$status'."
        $status = 'ERROR'
    }
    if (($status -eq 'OK' -or $status -eq 'NOOP') -and [string]::IsNullOrWhiteSpace($sourcePath)) {
        $message = 'Current-skin reset helper reported success without DMEL_SOURCEPATH.'
        $status = 'ERROR'
    }
    if (($status -eq 'OK' -or $status -eq 'NOOP' -or $status -eq 'WARN') -and [string]::IsNullOrWhiteSpace($logPath)) {
        $message = 'Current-skin reset helper reported a result without DMEL_LOGPATH.'
        $status = 'ERROR'
    }
    return [PSCustomObject]@{
        ExitCode = $(if ($status -eq 'ERROR') { 1 } else { $ExitCode })
        Status = $status
        Message = $message
        SourcePath = $sourcePath
        LogPath = $logPath
        Output = $Output
    }
}

function ConvertTo-CurrentSkinResetUiResult {
    param(
        [AllowNull()][object[]]$InvocationOutput
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($InvocationOutput)) {
        if ($null -ne $item -and $null -ne $item.PSObject.Properties['Status']) {
            $candidates.Add($item)
        }
    }

    if ($candidates.Count -ne 1) {
        return [PSCustomObject]@{
            ExitCode = 1
            Status = 'ERROR'
            Message = ('Current-skin reset returned {0} manager result objects; exactly one is required.' -f $candidates.Count)
            SourcePath = ''
            LogPath = ''
            Output = ''
        }
    }

    $candidate = $candidates[0]
    $status = ([string](Get-ObjectPropertyValue -Object $candidate -Name 'Status' -DefaultValue '')).Trim().ToUpperInvariant()
    $message = [string](Get-ObjectPropertyValue -Object $candidate -Name 'Message' -DefaultValue '')
    $sourcePath = [string](Get-ObjectPropertyValue -Object $candidate -Name 'SourcePath' -DefaultValue '')
    $logPath = [string](Get-ObjectPropertyValue -Object $candidate -Name 'LogPath' -DefaultValue '')
    $output = [string](Get-ObjectPropertyValue -Object $candidate -Name 'Output' -DefaultValue '')
    $exitCode = 0
    try {
        $exitCode = [int](Get-ObjectPropertyValue -Object $candidate -Name 'ExitCode' -DefaultValue 0)
    }
    catch {
        $exitCode = 1
        $message = 'Current-skin reset returned an invalid manager exit code.'
        $status = 'ERROR'
    }

    if ($status -notin @('OK', 'NOOP', 'WARN', 'ERROR')) {
        $message = "Current-skin reset returned unsupported manager status '$status'."
        $status = 'ERROR'
    }
    if (($status -eq 'OK' -or $status -eq 'NOOP') -and [string]::IsNullOrWhiteSpace($sourcePath)) {
        $message = 'Current-skin reset reported success without a source path.'
        $status = 'ERROR'
    }
    if (($status -eq 'OK' -or $status -eq 'NOOP' -or $status -eq 'WARN') -and [string]::IsNullOrWhiteSpace($logPath)) {
        $message = 'Current-skin reset reported a result without a log path.'
        $status = 'ERROR'
    }

    return [PSCustomObject]@{
        ExitCode = $(if ($status -eq 'ERROR') { 1 } else { $exitCode })
        Status = $status
        Message = $message
        SourcePath = $sourcePath
        LogPath = $logPath
        Output = $output
    }
}

function Invoke-CurrentSkinReset {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$PackageUrl,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedPackageSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][ValidateSet('Korea', 'Global')][string]$ExpectedReleaseVariant,
        [AllowNull()][scriptblock]$OnStageChanged
    )

    $stableVersion = ConvertTo-VersionManagerStableComparableVersion -VersionText $ExpectedVersion
    if ($null -eq $stableVersion) {
        throw 'Current-skin reset requires a stable semantic ExpectedVersion.'
    }
    $normalizedExpectedSha256 = $ExpectedPackageSha256.Trim().ToUpperInvariant()
    $currentVersionText = Get-SkinMetadataVersion -Root $Root
    $currentVersion = ConvertTo-VersionManagerStableComparableVersion -VersionText $currentVersionText
    if ($null -eq $currentVersion -or $currentVersion -ne $stableVersion) {
        throw 'Current-skin reset ExpectedVersion did not match the active root.'
    }
    $expectedTag = ([string]$ExpectedVersion).Trim()
    if (-not $expectedTag.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $expectedTag = 'v' + $expectedTag
    }
    $expectedAssetName = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant $ExpectedReleaseVariant -LanguageCode $script:LanguageCode
    $rootConfig = Get-UpdateConfiguration -Root $Root
    $rootProfile = Get-VersionManagerBadgeProfile -Config $rootConfig
    if (-not [string]::Equals([string]$rootConfig.ReleaseVariant, $ExpectedReleaseVariant, [System.StringComparison]::Ordinal)) {
        throw 'Current-skin reset release variant did not match the active root.'
    }
    $allowedUrl = 'https://github.com/{0}/releases/download/{1}/{2}' -f `
        [string]$rootProfile.RepositorySlug,
        [uri]::EscapeDataString($expectedTag),
        [uri]::EscapeDataString($expectedAssetName)
    if (-not [string]::Equals($allowedUrl, $PackageUrl, [System.StringComparison]::Ordinal)) {
        throw 'Current-skin reset rejected an unexpected package URL.'
    }

    $resetScript = Join-Path (Get-VersionManagerToolsRoot) 'UpdateToLatestVersion.ps1'
    if (-not (Test-Path -LiteralPath $resetScript -PathType Leaf)) {
        throw 'Current-skin reset helper is missing.'
    }
    foreach ($requiredParameter in @('CurrentTargetRoot', 'PackagePath', 'ExpectedVersion', 'ExpectedReleaseVariant', 'ResetCurrentVersion', 'InheritedOperationLock')) {
        if (-not (Test-VersionManagerScriptParameter -ScriptPath $resetScript -ParameterName $requiredParameter)) {
            throw "Current-skin reset helper does not support -$requiredParameter."
        }
    }

    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [timespan]::FromSeconds(300)
    $response = $null
    $packagePath = Join-Path ([System.IO.Path]::GetTempPath()) ('DMeloper-CurrentSkinReset-' + [guid]::NewGuid().ToString('N') + '.zip')
    $request = $null
    try {
        if ($null -ne $OnStageChanged) {
            [void](& $OnStageChanged 'download')
        }
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $PackageUrl)
        $request.Headers.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue
        $request.Headers.CacheControl.NoCache = $true
        $request.Headers.CacheControl.NoStore = $true
        $requestTask = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        while (-not $requestTask.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }
        $response = $requestTask.GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw ("Current-skin reset download failed with HTTP {0}." -f [int]$response.StatusCode)
        }
        $file = New-Object System.IO.FileStream($packagePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 65536, $true)
        try {
            $copyTask = $response.Content.CopyToAsync($file)
            while (-not $copyTask.IsCompleted) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 25
            }
            $copyTask.GetAwaiter().GetResult()
            $file.Flush($true)
        }
        finally {
            $file.Dispose()
        }
        if ((Get-Item -LiteralPath $packagePath -Force).Length -lt 4) {
            throw 'Current-skin reset download was empty.'
        }
        $actualSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant()
        if (-not [string]::Equals($actualSha256, $normalizedExpectedSha256, [System.StringComparison]::Ordinal)) {
            throw 'Current-skin reset download did not match the published SHA-256 checksum.'
        }
        $signature = New-Object byte[] 4
        $signatureStream = New-Object System.IO.FileStream($packagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            if ($signatureStream.Read($signature, 0, 4) -ne 4) {
                throw 'Current-skin reset download was too small to be a ZIP package.'
            }
        }
        finally {
            $signatureStream.Dispose()
        }
        if ($signature[0] -ne 0x50 -or $signature[1] -ne 0x4B -or
            (($signature[2] -ne 0x03 -or $signature[3] -ne 0x04) -and
             ($signature[2] -ne 0x05 -or $signature[3] -ne 0x06) -and
             ($signature[2] -ne 0x07 -or $signature[3] -ne 0x08))) {
            throw 'Current-skin reset download did not have a ZIP signature.'
        }
        if ($null -ne $OnStageChanged) {
            [void](& $OnStageChanged 'validating')
            [System.Windows.Forms.Application]::DoEvents()
        }

        $parameters = [ordered]@{
            CurrentTargetRoot = $Root
            PackagePath = $packagePath
            ExpectedVersion = $expectedTag
            ExpectedReleaseVariant = $ExpectedReleaseVariant
            ResetCurrentVersion = $true
            InheritedOperationLock = $true
            NonInteractive = $true
        }
        if ($null -ne $OnStageChanged) {
            [void](& $OnStageChanged 'applying')
            [System.Windows.Forms.Application]::DoEvents()
        }
        $passThruResult = Invoke-VersionManagerPassThruScript `
            -ScriptPath $resetScript `
            -Parameters $parameters `
            -PassThruParameter 'PassThruResultObject' `
            -RequiredProperty 'DMEL_STATUS' `
            -TimeoutSeconds 3600
        if ($null -ne $passThruResult) {
            return (ConvertTo-CurrentSkinResetResult -ResultObject $passThruResult)
        }

        $arguments = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $resetScript,
            '-CurrentTargetRoot', $Root,
            '-PackagePath', $packagePath,
            '-ExpectedVersion', $expectedTag,
            '-ExpectedReleaseVariant', $ExpectedReleaseVariant,
            '-ResetCurrentVersion', '-InheritedOperationLock', '-NonInteractive', '-EmitResultPairs'
        )
        $process = New-Object System.Diagnostics.Process
        try {
            $process.StartInfo = New-VersionManagerHostProcessStartInfo -Arguments $arguments -RedirectOutput
            if (-not $process.Start()) {
                throw 'Current-skin reset helper process could not be started.'
            }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            while (-not $process.WaitForExit(100)) {
                [System.Windows.Forms.Application]::DoEvents()
            }
            $output = @(
                @(([string]$stdoutTask.Result) -split '\r?\n' | Where-Object { $_ -ne '' }) +
                @(([string]$stderrTask.Result) -split '\r?\n' | Where-Object { $_ -ne '' })
            )
            $pairs = Convert-VersionManagerOutputToResultPairs -Output $output
            $pairObject = [PSCustomObject]@{
                DMEL_STATUS = [string]$pairs['DMEL_STATUS']
                DMEL_SOURCEPATH = [string]$pairs['DMEL_SOURCEPATH']
                DMEL_LOGPATH = [string]$pairs['DMEL_LOGPATH']
                DMEL_MESSAGE = [string]$pairs['DMEL_MESSAGE']
            }
            return (ConvertTo-CurrentSkinResetResult -ResultObject $pairObject -ExitCode ([int]$process.ExitCode) -Output ($output | Out-String))
        }
        finally {
            $process.Dispose()
        }
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        throw 'Current-skin reset download exceeded the 300-second transport deadline.'
    }
    finally {
        if ($null -ne $request) {
            $request.Dispose()
        }
        if ($null -ne $response) {
            $response.Dispose()
        }
        $client.Dispose()
        $handler.Dispose()
        if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
            Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        }
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
