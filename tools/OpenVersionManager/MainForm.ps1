# OpenVersionManager helpers - Main WinForms UI

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Start-VersionManager {
    $root = Get-TargetRoot
    if (-not (Test-SkinRoot -Root $root)) {
        throw 'TargetRoot is not a valid Block HUD skin root.'
    }

    $script:LogPath = Get-BlockHudCanonicalLogPath -Root $root -ScriptRoot (Get-VersionManagerToolsRoot)
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $script:LogPath
    Save-VersionManagerLaunchState -Root $root -Status 'initializing' -LaunchTokenValue $LaunchToken
    Write-VersionManagerLaunchDiagnostic -Root $root -Stage 'window-session-initializing' -LaunchTokenValue $LaunchToken -Details @(
        ('script={0}' -f (Get-VersionManagerEntrypointPath))
    )

    $ui = [ordered]@{}
    $ui.Root = $root
    $ui.TargetVersionText = Get-SkinMetadataVersion -Root $root
    $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
    $ui.Installations = @()
    $ui.UpdateConfig = [PSCustomObject]@{
        Provider = 'github'
        Owner = ''
        Repo = ''
        ReleaseVariant = ''
        ConfiguredReleaseVariant = ''
        DefaultReleaseVariant = ''
        LegacyAssetPattern = ''
        AssetPatternKorea = ''
        AssetPatternGlobal = ''
        HasVariantAwareAssetSettings = $true
        ActivePatternField = ''
        ActiveAssetPattern = ''
        AssetPattern = ''
        LanguageCode = $script:LanguageCode
        Channel = 'stable'
    }
    $ui.UpdateCache = [PSCustomObject]@{
        LastCheckedAtUtc = ''
        LatestVersion = ''
        ReleaseName = ''
        ReleaseUrl = ''
        AssetName = ''
        AssetUrl = ''
        AssetSize = 0
        PublishedAtUtc = ''
        ChangelogSummary = ''
        DownloadedZipPath = ''
        DownloadedAtUtc = ''
        Status = ''
        Error = ''
        ErrorCode = ''
        FailureHint = ''
        ReleaseVariant = ''
        ActiveAssetPattern = ''
    }
    $ui.CurrentInstallation = $null
    $ui.OtherInstallations = @()
    $ui.SelectedInstallation = $null
    $ui.VersionCatalog = $null
    $ui.VersionCatalogEntries = @()
    $ui.SelectedVersionCatalogEntry = $null
    $ui.VersionCatalogOperationInProgress = $false
    $ui.InstallationOperationInProgress = $false
    $ui.UpdateCheckInProgress = $false
    $ui.BusyOverlayVisible = $false
    $ui.BusyOverlayControlStates = @()
    $ui.HasSessionUpdateStatus = $false
    $ui.SettingsLogHasContent = $false
    $ui.CloseAfterSwitch = $false
    $ui.InitialHydrationStageIndex = 0
    $ui.DeferredHydrationStageIndex = 0
    $ui.InitialHydrationCompleted = $false
    $ui.TabStates = New-VersionManagerTabStateTable -TabNames @('summary', 'installations', 'settingsLog')

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T 'Helper_VersionManager_WindowTitle' 'Skins'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(784, 393)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Bounds = New-Object System.Drawing.Rectangle(12, 12, 760, 331)
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $tabs.ItemSize = New-Object System.Drawing.Size(132, 24)

    $installTab = New-Object System.Windows.Forms.TabPage
    $installTab.Text = T 'Helper_VersionManager_Tab_Update' 'Update'
    $foldersTab = New-Object System.Windows.Forms.TabPage
    $foldersTab.Text = T 'Helper_VersionManager_Tab_Folders' (U '\uC124\uCE58\uB41C \uC2A4\uD0A8')
    $settingsTab = New-Object System.Windows.Forms.TabPage
    $settingsTab.Text = T 'Helper_VersionManager_Tab_Settings' (U '\uC815\uBCF4')

    $tabs.TabPages.AddRange(@($installTab, $foldersTab, $settingsTab))

    $currentInstallGroup = New-Object System.Windows.Forms.GroupBox
    $currentInstallGroup.Text = T 'Helper_VersionManager_Install_CurrentGroup' 'Current install version'
    $currentInstallGroup.Bounds = New-Object System.Drawing.Rectangle(12, 8, 720, 100)

    $currentVersionValue = New-Object System.Windows.Forms.Label
    $currentVersionValue.Location = New-Object System.Drawing.Point(18, 24)
    $currentVersionValue.AutoSize = $true
    $currentVersionValue.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $currentVersionStateIcon = New-Object System.Windows.Forms.Control
    $currentVersionStateIcon.Size = New-Object System.Drawing.Size(24, 24)
    $currentVersionStateIcon.Location = New-Object System.Drawing.Point(506, 27)
    $currentVersionStateIcon.BackColor = $currentInstallGroup.BackColor
    $currentVersionStateIcon.Tag = 'unknown'
    $currentVersionStateIcon.Add_Paint({
        param($sender, $eventArgs)

        $state = [string]$sender.Tag
        if ([string]::IsNullOrWhiteSpace($state)) {
            $state = 'unknown'
        }
        Draw-VersionManagerStatusBadge -State $state -Graphics $eventArgs.Graphics -BackgroundColor $sender.BackColor -Width $sender.Width -Height $sender.Height
    })
    $currentVersionStatusText = New-Object System.Windows.Forms.Label
    $currentVersionStatusText.Location = New-Object System.Drawing.Point(18, 60)
    $currentVersionStatusText.Size = New-Object System.Drawing.Size(500, 18)
    $currentVersionStatusText.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)

    $footerCheckLatest = New-Object System.Windows.Forms.Button
    $footerCheckLatest.Text = T 'Helper_VersionManager_Action_CheckLatest' 'Check latest version'
    $footerCheckLatest.Bounds = New-Object System.Drawing.Rectangle(536, 24, 176, 26)
    $footerInstallLatest = New-Object System.Windows.Forms.Button
    $footerInstallLatest.Text = T 'Helper_VersionManager_Action_InstallLatest' 'Update to latest version'
    $footerInstallLatest.Bounds = New-Object System.Drawing.Rectangle(536, 56, 176, 26)
    $currentInstallGroup.Controls.AddRange(@(
        $currentVersionValue,
        $currentVersionStateIcon,
        $currentVersionStatusText,
        $footerCheckLatest,
        $footerInstallLatest
    ))

    $versionCatalogGroup = New-Object System.Windows.Forms.GroupBox
    $versionCatalogGroup.Text = T 'Helper_VersionManager_Update_VersionCatalogGroup' (U '\uBC84\uC804 \uBAA9\uB85D')
    $versionCatalogGroup.Bounds = New-Object System.Drawing.Rectangle(12, 112, 720, 180)

    $versionCatalogList = New-Object System.Windows.Forms.ListView
    $versionCatalogList.Bounds = New-Object System.Drawing.Rectangle(10, 20, 576, 150)
    $versionCatalogList.View = [System.Windows.Forms.View]::Details
    $versionCatalogList.FullRowSelect = $true
    $versionCatalogList.HideSelection = $false
    $versionCatalogList.MultiSelect = $false
    $versionCatalogList.GridLines = $true
    $versionCatalogList.Enabled = $false
    [void]$versionCatalogList.Columns.Add((T 'Helper_VersionManager_List_Version' 'Version'), 88)
    [void]$versionCatalogList.Columns.Add((T 'Helper_VersionManager_Update_ReleaseColumn' (U '\uB9B4\uB9AC\uC988')), 204)
    [void]$versionCatalogList.Columns.Add((T 'Helper_VersionManager_List_Status' 'Status'), 284)

    $versionCatalogInstallButton = New-Object System.Windows.Forms.Button
    $versionCatalogInstallButton.Text = T 'Helper_VersionManager_Action_InstallVersion' (U '\uC774 \uBC84\uC804 \uC124\uCE58\uD558\uAE30')
    $versionCatalogInstallButtonWidth = [Math]::Max(112, [System.Windows.Forms.TextRenderer]::MeasureText($versionCatalogInstallButton.Text, $versionCatalogInstallButton.Font).Width + 24)
    $versionCatalogInstallButtonX = 706 - $versionCatalogInstallButtonWidth
    $versionCatalogList.Width = $versionCatalogInstallButtonX - 18
    $versionCatalogInstallButton.Bounds = New-Object System.Drawing.Rectangle($versionCatalogInstallButtonX, 18, $versionCatalogInstallButtonWidth, 24)
    $versionCatalogInstallButton.Enabled = $false

    $versionCatalogGroup.Controls.AddRange(@($versionCatalogList, $versionCatalogInstallButton))

    $otherInstallGroup = New-Object System.Windows.Forms.GroupBox
    $otherInstallGroup.Text = T 'Helper_VersionManager_Install_OtherGroup' (U '\uCEF4\uD4E8\uD130\uC5D0 \uC124\uCE58\uB41C \uC2A4\uD0A8')
    $otherInstallGroup.Bounds = New-Object System.Drawing.Rectangle(12, 8, 720, 280)

    $otherInstallList = New-Object System.Windows.Forms.ListView
    $otherInstallList.Bounds = New-Object System.Drawing.Rectangle(10, 20, 576, 250)
    $otherInstallList.View = [System.Windows.Forms.View]::Details
    $otherInstallList.FullRowSelect = $true
    $otherInstallList.HideSelection = $false
    $otherInstallList.MultiSelect = $false
    $otherInstallList.GridLines = $true
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_List_Status' 'Status'), 132)
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_List_Version' 'Version'), 76)
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_Common_Label' 'Label'), 118)
    [void]$otherInstallList.Columns.Add((T 'Helper_VersionManager_Common_Path' 'Path'), 250)

    $installButtons = [ordered]@{}
    $installButtons.UseVersion = New-Object System.Windows.Forms.Button
    $installButtons.UseVersion.Text = T 'Helper_VersionManager_Action_UseVersion' 'Use this skin'
    $installButtons.UseVersion.Bounds = New-Object System.Drawing.Rectangle(594, 18, 112, 24)
    $installButtons.UseVersion.Enabled = $false
    $installButtons.Import = New-Object System.Windows.Forms.Button
    $installButtons.Import.Text = T 'Helper_VersionManager_Action_ImportData' 'Import data'
    $installButtons.Import.Bounds = New-Object System.Drawing.Rectangle(594, 46, 112, 24)
    $installButtons.Delete = New-Object System.Windows.Forms.Button
    $installButtons.Delete.Text = T 'Helper_VersionManager_Action_Delete' 'Delete'
    $installButtons.Delete.Bounds = New-Object System.Drawing.Rectangle(594, 74, 112, 24)

    $installResult = New-Object System.Windows.Forms.TextBox
    $installResult.Bounds = New-Object System.Drawing.Rectangle(12, 293, 720, 20)
    $installResult.ReadOnly = $true

    $otherInstallGroup.Controls.Add($otherInstallList)
    foreach ($button in $installButtons.Values) {
        $otherInstallGroup.Controls.Add($button)
    }
    $installTab.Controls.AddRange(@($currentInstallGroup, $versionCatalogGroup))

    $foldersTab.Controls.AddRange(@($otherInstallGroup, $installResult))

    $settingsUtilityGroup = New-Object System.Windows.Forms.GroupBox
    $settingsUtilityGroup.Text = T 'Helper_VersionManager_Settings_UtilitiesGroup' 'Utilities'
    $settingsUtilityGroup.Bounds = New-Object System.Drawing.Rectangle(12, 12, 720, 64)
    $settingsOpenLogButton = New-Object System.Windows.Forms.Button
    $settingsOpenLogButton.Text = T 'Helper_VersionManager_Action_OpenLogFolder' 'Open log folder'
    $settingsOpenLogButton.Bounds = New-Object System.Drawing.Rectangle(16, 24, 156, 24)
    $settingsOpenSkinButton = New-Object System.Windows.Forms.Button
    $settingsOpenSkinButton.Text = T 'Helper_VersionManager_Action_OpenCurrentSkinFolder' 'Open current skin folder'
    $settingsOpenSkinButton.Bounds = New-Object System.Drawing.Rectangle(184, 24, 176, 24)
    $settingsUtilityGroup.Controls.AddRange(@($settingsOpenLogButton, $settingsOpenSkinButton))

    $settingsLogGroup = New-Object System.Windows.Forms.GroupBox
    $settingsLogGroup.Text = T 'Helper_VersionManager_Log_Group' 'Skin logs'
    $settingsLogGroup.Bounds = New-Object System.Drawing.Rectangle(12, 84, 720, 190)
    $settingsLogText = New-Object System.Windows.Forms.TextBox
    $settingsLogText.Bounds = New-Object System.Drawing.Rectangle(16, 24, 688, 126)
    $settingsLogText.Multiline = $true
    $settingsLogText.ReadOnly = $true
    $settingsLogText.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $settingsLogText.WordWrap = $false
    $settingsLogCopyButton = New-Object System.Windows.Forms.Button
    $settingsLogCopyButton.Text = T 'Helper_VersionManager_Action_CopyAll' 'Copy all'
    $settingsLogCopyButton.Bounds = New-Object System.Drawing.Rectangle(16, 156, 96, 24)
    $settingsLogClearButton = New-Object System.Windows.Forms.Button
    $settingsLogClearButton.Text = T 'Helper_VersionManager_Action_ClearAll' 'Clear all'
    $settingsLogClearButton.Bounds = New-Object System.Drawing.Rectangle(120, 156, 96, 24)
    $settingsLogGroup.Controls.AddRange(@($settingsLogText, $settingsLogCopyButton, $settingsLogClearButton))
    $settingsTab.Controls.AddRange(@($settingsUtilityGroup, $settingsLogGroup))

    $loadingListItem = {
        param([string]$text)
        $item = New-Object System.Windows.Forms.ListViewItem([string]$text)
        return $item
    }

    $footerRefresh = New-Object System.Windows.Forms.Button
    $footerRefresh.Text = T 'Helper_VersionManager_Action_Refresh' 'Refresh'
    $footerRefresh.Bounds = New-Object System.Drawing.Rectangle(12, 353, 88, 28)
    $footerOpenDownloadPage = New-Object System.Windows.Forms.Button
    $footerOpenDownloadPage.Text = T 'Helper_VersionManager_Action_OpenReleasePage' 'Download page'
    $footerOpenDownloadPage.Bounds = New-Object System.Drawing.Rectangle(108, 353, 148, 28)
    $footerOpenRepositoryPage = New-Object System.Windows.Forms.Button
    $footerOpenRepositoryPage.Text = T 'Helper_VersionManager_Action_OpenRepositoryPage' 'GitHub page'
    $footerOpenRepositoryPage.Bounds = New-Object System.Drawing.Rectangle(264, 353, 148, 28)
    $footerClose = New-Object System.Windows.Forms.Button
    $footerClose.Text = T 'Helper_VersionManager_Common_Close' 'Close'
    $footerClose.Bounds = New-Object System.Drawing.Rectangle(660, 353, 112, 28)
    $footerClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $footerClose.Add_Click({
        $form.Close()
    })

    $busyOverlay = New-Object System.Windows.Forms.Panel
    $busyOverlay.Bounds = New-Object System.Drawing.Rectangle(0, 0, 784, 393)
    $busyOverlay.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $busyOverlay.Visible = $false

    $busyOverlayCard = New-Object System.Windows.Forms.Panel
    $busyOverlayCard.Bounds = New-Object System.Drawing.Rectangle(150, 128, 484, 136)
    $busyOverlayCard.BackColor = [System.Drawing.Color]::White
    $busyOverlayCard.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $busyOverlayTitle = New-Object System.Windows.Forms.Label
    $busyOverlayTitle.Bounds = New-Object System.Drawing.Rectangle(22, 20, 438, 24)
    $busyOverlayTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $busyOverlayTitle.Text = T 'Helper_VersionManager_Busy_Title' 'Update in progress'

    $busyOverlayMessage = New-Object System.Windows.Forms.Label
    $busyOverlayMessage.Bounds = New-Object System.Drawing.Rectangle(22, 50, 438, 38)
    $busyOverlayMessage.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $busyOverlayMessage.Text = T 'Helper_VersionManager_Busy_Default' 'Downloading files and preparing skin data. Please do not close this window.'

    $busyOverlayProgress = New-Object System.Windows.Forms.ProgressBar
    $busyOverlayProgress.Bounds = New-Object System.Drawing.Rectangle(22, 102, 438, 16)
    $busyOverlayProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $busyOverlayProgress.MarqueeAnimationSpeed = 35

    $busyOverlayCard.Controls.AddRange(@($busyOverlayTitle, $busyOverlayMessage, $busyOverlayProgress))
    $busyOverlay.Controls.Add($busyOverlayCard)

    $form.Controls.AddRange(@($tabs, $footerRefresh, $footerOpenDownloadPage, $footerOpenRepositoryPage, $footerClose, $busyOverlay))
    $form.CancelButton = $footerClose
    $busyOverlay.BringToFront()

    $busyOverlayControls = @(
        $tabs,
        $footerRefresh,
        $footerOpenDownloadPage,
        $footerOpenRepositoryPage,
        $footerClose
    )

    $showBusyOverlay = {
        param([AllowNull()][string]$Message)

        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = T 'Helper_VersionManager_Busy_Default' 'Downloading files and preparing skin data. Please do not close this window.'
        }

        $busyOverlayTitle.Text = T 'Helper_VersionManager_Busy_Title' 'Update in progress'
        $busyOverlayMessage.Text = $Message

        if (-not $ui.BusyOverlayVisible) {
            $states = New-Object System.Collections.Generic.List[object]
            foreach ($control in @($busyOverlayControls)) {
                if ($null -ne $control) {
                    [void]$states.Add([PSCustomObject]@{
                        Control = $control
                        Enabled = [bool]$control.Enabled
                    })
                    $control.Enabled = $false
                }
            }
            $ui.BusyOverlayControlStates = @($states.ToArray())
            $ui.BusyOverlayVisible = $true
        }

        $form.UseWaitCursor = $true
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        $busyOverlay.Visible = $true
        $busyOverlay.Enabled = $true
        $busyOverlay.BringToFront()
        $busyOverlay.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }

    $hideBusyOverlay = {
        if ($ui.BusyOverlayVisible) {
            foreach ($entry in @($ui.BusyOverlayControlStates)) {
                $control = $entry.Control
                if ($null -ne $control -and -not $control.IsDisposed) {
                    $control.Enabled = [bool]$entry.Enabled
                }
            }
            $ui.BusyOverlayControlStates = @()
            $ui.BusyOverlayVisible = $false
        }

        $busyOverlay.Visible = $false
        $form.UseWaitCursor = $false
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
        [System.Windows.Forms.Application]::DoEvents()
    }

    $recoverInteractiveStateAfterFailure = {
        try {
            & $hideBusyOverlay
        }
        catch {
        }

        $ui.UpdateCheckInProgress = $false
        $ui.VersionCatalogOperationInProgress = $false
        $ui.InstallationOperationInProgress = $false

        foreach ($control in @($tabs, $footerOpenDownloadPage, $footerOpenRepositoryPage, $footerClose)) {
            if ($null -ne $control -and -not $control.IsDisposed) {
                $control.Enabled = $true
            }
        }
    }

    $setCurrentVersionState = {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('latest', 'unknown', 'error', 'not-latest')][string]$State,
            [Parameter(Mandatory = $true)][string]$StatusText
        )

        $currentVersionStateIcon.Location = New-Object System.Drawing.Point(($currentVersionValue.Left + $currentVersionValue.PreferredWidth + 8), 27)
        $currentVersionStateIcon.Tag = $State
        $currentVersionStateIcon.BringToFront()
        $currentVersionStateIcon.Refresh()
        $currentVersionStatusText.Text = $StatusText
    }

    $handleInitialHydrationStageFailure = {
        param(
            [Parameter(Mandatory = $true)][string]$StageName,
            [Parameter(Mandatory = $true)][System.Exception]$Exception
        )

        & $recoverInteractiveStateAfterFailure

        switch ($StageName) {
            'summary' { [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary') }
            'installations' { [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations') }
            'settingsLog' { [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog') }
        }

        $message = if ([string]::IsNullOrWhiteSpace([string]$Exception.Message)) {
            T 'Helper_VersionManager_Common_LoadFailed' 'The requested data could not be loaded.'
        }
        else {
            [string]$Exception.Message
        }
        Write-Log ("Initial version manager hydration stage failed ({0}): {1}" -f $StageName, $Exception.ToString()) 'ERROR'

        switch ($StageName) {
            'summary' {
                $errorCode = Get-UpdateConfigurationErrorCode -Exception $Exception
                $friendlyStatus = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage $message -Surface 'summary'
                & $setCurrentVersionState 'error' $friendlyStatus
                $footerInstallLatest.Enabled = $false
            }
            'settingsLog' {
                $settingsLogText.Text = $message
                $settingsLogCopyButton.Enabled = $false
                $settingsLogClearButton.Enabled = $false
            }
            default {
                $installResult.Text = $message
            }
        }
    }

    $refreshSummary = {
        [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary')
        $completedRefresh = $false
        try {
            $ui.UpdateConfig = Get-UpdateConfiguration -Root $ui.Root
            $ui.UpdateCache = Get-UpdateCache -Root $ui.Root
            $updateConfigured = Test-UpdateConfigured -Config $ui.UpdateConfig

            if (-not $updateConfigured) {
                & $setCurrentVersionState 'error' (T 'Helper_VersionManager_Summary_UpdateUnconfigured' 'Update status: update source not configured')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            if ($ui.UpdateCheckInProgress -or -not $ui.HasSessionUpdateStatus) {
                & $setCurrentVersionState 'unknown' (T 'Helper_VersionManager_Summary_UpdateChecking' 'Update status: checking latest version...')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$ui.UpdateCache.Error)) {
                $friendlyStatus = Get-UpdateFriendlyMessage -ErrorCode ([string]$ui.UpdateCache.ErrorCode) -DefaultMessage ([string]$ui.UpdateCache.Error) -Surface 'summary'
                & $setCurrentVersionState 'error' $friendlyStatus
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            $latestComparableVersion = Convert-ToVersion -VersionText ([string]$ui.UpdateCache.LatestVersion)
            if ($latestComparableVersion -and $ui.TargetVersion -and ($latestComparableVersion -gt $ui.TargetVersion)) {
                & $setCurrentVersionState 'not-latest' (TF 'Helper_VersionManager_Summary_UpdateAvailable' @([string]$ui.UpdateCache.LatestVersion) 'Update status: update available (%1)')
                $footerInstallLatest.Enabled = -not $ui.UpdateCheckInProgress
                $completedRefresh = $true
                return
            }

            if ($latestComparableVersion -and $ui.TargetVersion -and ($latestComparableVersion -eq $ui.TargetVersion)) {
                & $setCurrentVersionState 'latest' (T 'Helper_VersionManager_Summary_UpdateLatest' 'Update status: current install is latest')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            & $setCurrentVersionState 'unknown' (T 'Helper_VersionManager_Summary_UpdateOlder' 'Update status: current install is newer than the latest release')
            $footerInstallLatest.Enabled = $false
            $completedRefresh = $true
        }
        catch {
            [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary')
            throw
        }
        finally {
            if ($completedRefresh) {
                [void](Complete-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'summary')
            }
        }
    }

    $testVersionCatalogEntryCurrent = {
        param([AllowNull()]$Entry)

        if ($null -eq $Entry) {
            return $false
        }

        $entryVersion = Convert-ToVersion -VersionText ([string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue ''))
        if ($entryVersion -and $ui.TargetVersion -and ($entryVersion -eq $ui.TargetVersion)) {
            $entryVariant = [string](Get-ObjectPropertyValue -Object $Entry -Name 'release_variant' -DefaultValue '')
            $currentVariant = [string](Get-ObjectPropertyValue -Object $ui.UpdateConfig -Name 'ReleaseVariant' -DefaultValue '')
            return (
                [string]::IsNullOrWhiteSpace($entryVariant) -or
                [string]::IsNullOrWhiteSpace($currentVariant) -or
                [string]::Equals($entryVariant, $currentVariant, [System.StringComparison]::OrdinalIgnoreCase)
            )
        }

        $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
        return (-not [string]::IsNullOrWhiteSpace($installedPath) -and [string]::Equals((Resolve-FullPath -Path $installedPath -AllowMissing), (Resolve-FullPath -Path $ui.Root), [System.StringComparison]::OrdinalIgnoreCase))
    }

    $testVersionCatalogEntryActionable = {
        param([AllowNull()]$Entry)

        if ($ui.VersionCatalogOperationInProgress -or $null -eq $Entry) {
            return $false
        }
        if (& $testVersionCatalogEntryCurrent $Entry) {
            return $false
        }
        $entryVersion = Convert-ToVersion -VersionText ([string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue ''))
        $status = [string](Get-ObjectPropertyValue -Object $Entry -Name 'status' -DefaultValue '')
        $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
        $assetUrl = [string](Get-ObjectPropertyValue -Object $Entry -Name 'asset_url' -DefaultValue '')
        $isLatestStable = [bool](Get-ObjectPropertyValue -Object $Entry -Name 'is_latest_stable' -DefaultValue $false)
        if ($isLatestStable) {
            if (-not [string]::IsNullOrWhiteSpace($installedPath)) {
                return $true
            }
            return ($entryVersion -and $ui.TargetVersion -and ($entryVersion -gt $ui.TargetVersion) -and -not [string]::IsNullOrWhiteSpace($assetUrl))
        }

        if ([string]::Equals($status, 'installed', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($installedPath)) {
            return $true
        }

        return ([string]::Equals($status, 'available', [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($assetUrl))
    }

    $formatVersionCatalogStatus = {
        param([AllowNull()]$Entry)

        $parts = New-Object System.Collections.Generic.List[string]
        $isLatestStable = [bool](Get-ObjectPropertyValue -Object $Entry -Name 'is_latest_stable' -DefaultValue $false)
        if ($isLatestStable -and -not (& $testVersionCatalogEntryCurrent $Entry)) {
            [void]$parts.Add((T 'Helper_VersionManager_Update_StatusLatest' (U '\uAC00\uC7A5 \uCD5C\uC2E0 \uBC84\uC804')))
        }
        if (& $testVersionCatalogEntryCurrent $Entry) {
            [void]$parts.Add((T 'Helper_VersionManager_Update_StatusCurrent' 'current'))
        }

        $installedPath = [string](Get-ObjectPropertyValue -Object $Entry -Name 'installed_path' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($installedPath) -and -not (& $testVersionCatalogEntryCurrent $Entry)) {
            [void]$parts.Add((T 'Helper_VersionManager_Update_StatusLocal' 'local install'))
        }

        $status = [string](Get-ObjectPropertyValue -Object $Entry -Name 'status' -DefaultValue '')
        switch -Regex ($status) {
            '^latest_stable$' {
                if (-not (& $testVersionCatalogEntryCurrent $Entry) -and [string]::IsNullOrWhiteSpace($installedPath)) {
                    $assetUrl = [string](Get-ObjectPropertyValue -Object $Entry -Name 'asset_url' -DefaultValue '')
                    if (-not [string]::IsNullOrWhiteSpace($assetUrl)) {
                        [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAvailable' 'available'))
                    } else {
                        [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAssetMissing' 'download asset missing'))
                    }
                }
            }
            '^available$' {
                if (-not (& $testVersionCatalogEntryCurrent $Entry)) {
                    [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAvailable' 'available'))
                }
            }
            '^installed$' {
                if ([string]::IsNullOrWhiteSpace($installedPath)) {
                    [void]$parts.Add((T 'Helper_VersionManager_Update_StatusInstalled' 'installed'))
                }
            }
            '^asset_missing$' { [void]$parts.Add((T 'Helper_VersionManager_Update_StatusAssetMissing' 'download asset missing')) }
            default {
                if (-not [string]::IsNullOrWhiteSpace($status)) {
                    [void]$parts.Add($status)
                }
            }
        }

        if ($parts.Count -eq 0) {
            return (T 'Helper_VersionManager_Update_StatusUnknown' 'unknown')
        }
        return ($parts.ToArray() -join ' / ')
    }

    $syncVersionCatalogSelectionState = {
        $versionCatalogInstallButton.Enabled = (& $testVersionCatalogEntryActionable $ui.SelectedVersionCatalogEntry)
    }

    $syncInstallationSelectionState = {
        $entry = $ui.SelectedInstallation
        $canUseSelected = ($null -ne $entry) -and
            (-not [bool]$entry.IsCurrent) -and
            [bool]$entry.IsValid -and
            (-not $ui.InstallationOperationInProgress)
        $canImportSelected = ($null -ne $entry) -and
            [bool]$entry.ImportAllowed -and
            (-not $ui.InstallationOperationInProgress)
        $canDeleteSelected = ($null -ne $entry) -and
            (-not [bool]$entry.IsCurrent) -and
            ($entry.Source -eq 'manual' -or $entry.Source -eq 'auto') -and
            (-not $ui.InstallationOperationInProgress)

        $installButtons.UseVersion.Enabled = $canUseSelected
        $installButtons.Import.Enabled = $canImportSelected
        $installButtons.Delete.Enabled = $canDeleteSelected
    }

    $refreshVersionCatalog = {
        param([bool]$ForceRefresh = $false)

        if ($ui.VersionCatalogOperationInProgress) {
            return
        }

        $ui.VersionCatalogOperationInProgress = $true
        $ui.VersionCatalog = $null
        $ui.VersionCatalogEntries = @()
        $ui.SelectedVersionCatalogEntry = $null
        $versionCatalogInstallButton.Enabled = $false
        $versionCatalogList.Enabled = $false
        $footerRefresh.Enabled = $false
        $footerCheckLatest.Enabled = $false
        $versionCatalogList.BeginUpdate()
        try {
            $versionCatalogList.Items.Clear()
            [void]$versionCatalogList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
        }
        finally {
            $versionCatalogList.EndUpdate()
        }
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $ui.TargetVersionText = Get-SkinMetadataVersion -Root $ui.Root
            $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
            $ui.UpdateConfig = Get-UpdateConfiguration -Root $ui.Root
            $ui.VersionCatalog = Invoke-VersionReleaseCatalog -Root $ui.Root -ForceRefresh:$ForceRefresh
            $ui.VersionCatalogEntries = @($ui.VersionCatalog.releases)
            $ui.UpdateCache = Get-UpdateCache -Root $ui.Root
            $ui.HasSessionUpdateStatus = $true

            $versionCatalogList.BeginUpdate()
            $versionCatalogList.Items.Clear()
            foreach ($entry in $ui.VersionCatalogEntries) {
                $versionText = [string](Get-ObjectPropertyValue -Object $entry -Name 'version' -DefaultValue '')
                $releaseName = [string](Get-ObjectPropertyValue -Object $entry -Name 'release_name' -DefaultValue '')
                if ([string]::IsNullOrWhiteSpace($releaseName)) {
                    $releaseName = [string](Get-ObjectPropertyValue -Object $entry -Name 'tag' -DefaultValue '')
                }
                $item = New-Object System.Windows.Forms.ListViewItem($versionText)
                [void]$item.SubItems.Add($releaseName)
                [void]$item.SubItems.Add((& $formatVersionCatalogStatus $entry))
                $item.Tag = $entry
                [void]$versionCatalogList.Items.Add($item)
            }

            if ($versionCatalogList.Items.Count -eq 0) {
                $emptyItem = New-Object System.Windows.Forms.ListViewItem('')
                [void]$emptyItem.SubItems.Add('')
                [void]$emptyItem.SubItems.Add((T 'Helper_VersionManager_Update_VersionCatalogEmpty' 'No releases were found.'))
                [void]$versionCatalogList.Items.Add($emptyItem)
            }
        }
        catch {
            Write-Log ("Version catalog load failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            $versionCatalogList.BeginUpdate()
            $versionCatalogList.Items.Clear()
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            $friendlyMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
            $errorItem = New-Object System.Windows.Forms.ListViewItem('')
            [void]$errorItem.SubItems.Add('')
            [void]$errorItem.SubItems.Add($friendlyMessage)
            [void]$versionCatalogList.Items.Add($errorItem)
        }
        finally {
            $versionCatalogList.EndUpdate()
            $ui.VersionCatalogOperationInProgress = $false
            $ui.HasSessionUpdateStatus = $true
            $versionCatalogList.Enabled = $true
            $footerRefresh.Enabled = $true
            $footerCheckLatest.Enabled = $true
            try {
                $ui.UpdateCache = Get-UpdateCache -Root $ui.Root
                & $refreshSummary
            }
            catch {
                Write-Log ("Could not refresh summary after version catalog completion: {0}" -f $_.Exception.Message) 'WARN'
            }
            if ($versionCatalogList.Items.Count -gt 0 -and $null -ne $versionCatalogList.Items[0].Tag) {
                $versionCatalogList.Items[0].Selected = $true
                $versionCatalogList.Items[0].Focused = $true
            }
            & $syncVersionCatalogSelectionState
        }
    }

    $selectVersionCatalogEntry = {
        param([AllowNull()]$Entry)

        $ui.SelectedVersionCatalogEntry = $Entry
        foreach ($item in @($versionCatalogList.Items)) {
            $item.Selected = $false
            $item.Focused = $false
        }

        if ($null -eq $Entry) {
            & $syncVersionCatalogSelectionState
            return
        }

        $entryVersion = [string](Get-ObjectPropertyValue -Object $Entry -Name 'version' -DefaultValue '')
        $entryTag = [string](Get-ObjectPropertyValue -Object $Entry -Name 'tag' -DefaultValue '')
        foreach ($item in @($versionCatalogList.Items)) {
            $candidate = $item.Tag
            if ($null -eq $candidate) {
                continue
            }

            $candidateVersion = [string](Get-ObjectPropertyValue -Object $candidate -Name 'version' -DefaultValue '')
            $candidateTag = [string](Get-ObjectPropertyValue -Object $candidate -Name 'tag' -DefaultValue '')
            if ([string]::Equals($candidateVersion, $entryVersion, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals($candidateTag, $entryTag, [System.StringComparison]::OrdinalIgnoreCase)) {
                $item.Selected = $true
                $item.Focused = $true
                $item.EnsureVisible()
                break
            }
        }

        & $syncVersionCatalogSelectionState
    }

    $getLatestVersionCatalogEntryForInstall = {
        if ($ui.VersionCatalogOperationInProgress) {
            return $null
        }

        & $refreshVersionCatalog

        $latestEntry = $null
        foreach ($entry in @($ui.VersionCatalogEntries)) {
            $isLatestStable = [bool](Get-ObjectPropertyValue -Object $entry -Name 'is_latest_stable' -DefaultValue $false)
            if ($isLatestStable) {
                $latestEntry = $entry
                break
            }
        }

        if ($null -eq $latestEntry -and @($ui.VersionCatalogEntries).Count -gt 0) {
            $latestEntry = @($ui.VersionCatalogEntries)[0]
        }

        if ($null -eq $latestEntry) {
            throw (T 'Helper_VersionManager_Update_NoStableRelease' 'The latest release is not a stable published release.')
        }

        if (-not (& $testVersionCatalogEntryActionable $latestEntry)) {
            throw (T 'Helper_VersionManager_Update_LatestCatalogInstallUnavailable' 'The latest version is not available for selected-version installation.')
        }

        return $latestEntry
    }

    $refreshInstallations = {
        [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
        $completedRefresh = $false
        try {
            $ui.Installations = @(Get-Installations -Root $ui.Root)
            $ui.CurrentInstallation = $null
            $ui.OtherInstallations = @()
            foreach ($entry in $ui.Installations) {
                if ($entry.IsCurrent -and -not $ui.CurrentInstallation) {
                    $ui.CurrentInstallation = $entry
                }
                elseif (-not $entry.IsCurrent) {
                    $ui.OtherInstallations += ,$entry
                }
            }

            if ($ui.CurrentInstallation) {
                $currentVersionValue.Text = [string]$ui.CurrentInstallation.VersionText
            }
            else {
                $currentVersionValue.Text = ''
            }

            $otherInstallList.BeginUpdate()
            $otherInstallList.Items.Clear()
            foreach ($entry in $ui.OtherInstallations) {
                $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Status)
                [void]$item.SubItems.Add([string]$entry.VersionText)
                [void]$item.SubItems.Add([string]$entry.Label)
                [void]$item.SubItems.Add([string]$entry.Path)
                $item.Tag = $entry
                [void]$otherInstallList.Items.Add($item)
            }
            $otherInstallList.EndUpdate()
            if ($otherInstallList.Items.Count -gt 0) {
                $otherInstallList.Items[0].Selected = $true
                $otherInstallList.Items[0].Focused = $true
                $ui.SelectedInstallation = $otherInstallList.Items[0].Tag
            }
            else {
                $ui.SelectedInstallation = $null
            }
            & $syncInstallationSelectionState
            $completedRefresh = $true
        }
        catch {
            [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
            throw
        }
        finally {
            if ($completedRefresh) {
                [void](Complete-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
            }
        }
    }

    $refreshSettingsTab = {
        [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
        $completedRefresh = $false
        try {
            $logView = Get-VersionManagerLogView -Root $ui.Root -CurrentLogPath $script:LogPath
            $ui.SettingsLogHasContent = [bool]$logView.HasContent
            $settingsLogText.Text = [string]$logView.Text
            $settingsLogCopyButton.Enabled = [bool]$logView.HasContent
            $settingsLogClearButton.Enabled = [bool]$logView.HasContent
            $completedRefresh = $true
        }
        catch {
            [void](Stop-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
            throw
        }
        finally {
            if ($completedRefresh) {
                [void](Complete-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
            }
        }
    }

    $setVersionManagerTabsDirty = {
        param([string[]]$TabNames)

        foreach ($tabName in @($TabNames)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$tabName)) {
                [void](Set-VersionManagerTabDirty -TabStates $ui.TabStates -TabName ([string]$tabName))
            }
        }
    }

    $setVersionManagerTabsDirtyForLatestStateMutation = {
        & $setVersionManagerTabsDirty @('summary', 'settingsLog')
    }

    $setVersionManagerTabsDirtyForInstallationMutation = {
        & $setVersionManagerTabsDirty @('installations')
    }

    $setVersionManagerTabsDirtyForGlobalMutation = {
        [void](Set-VersionManagerAllTabsDirty -TabStates $ui.TabStates)
    }

    $refreshAll = {
        & $setVersionManagerTabsDirtyForGlobalMutation
        $ui.TargetVersionText = Get-SkinMetadataVersion -Root $ui.Root
        $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
        & $refreshSummary
        & $refreshVersionCatalog
        & $refreshInstallations
        & $refreshSettingsTab
    }

    $runLatestCheck = {
        param([bool]$Silent)

        if ($ui.UpdateCheckInProgress -or $ui.VersionCatalogOperationInProgress) {
            return
        }

        try {
            $ui.UpdateCheckInProgress = $true
            & $refreshSummary
            [System.Windows.Forms.Application]::DoEvents()
            & $refreshVersionCatalog $true
            $ui.UpdateCache = Get-UpdateCache -Root $ui.Root
            $ui.HasSessionUpdateStatus = $true
            & $setVersionManagerTabsDirtyForLatestStateMutation
            & $refreshSummary
            & $refreshSettingsTab
        }
        catch {
            Write-Log ("Latest version refresh failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            if (-not $Silent -and -not $script:VersionManagerWindowClosing) {
                $dialogMessage = Get-UpdateFriendlyMessage -ErrorCode (Get-UpdateConfigurationErrorCode -Exception $_.Exception) -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
                Show-VersionManagerMessageBox -Owner $form -Message $dialogMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
        finally {
            $ui.UpdateCheckInProgress = $false
        }
    }

    $installLatestVersion = {
        if ($ui.UpdateCheckInProgress -or $ui.VersionCatalogOperationInProgress) {
            return
        }

        try {
            $config = Get-UpdateConfiguration -Root $ui.Root
            if (-not (Test-UpdateConfigured -Config $config)) {
                throw (T 'Helper_VersionManager_Update_SourceUnconfigured' 'The update source is not configured yet.')
            }

            $latestEntry = & $getLatestVersionCatalogEntryForInstall
            if ($null -eq $latestEntry) {
                return
            }

            $latestComparableVersion = Convert-ToVersion -VersionText ([string](Get-ObjectPropertyValue -Object $latestEntry -Name 'version' -DefaultValue ''))
            if (-not $latestComparableVersion -or -not $ui.TargetVersion -or ($latestComparableVersion -le $ui.TargetVersion)) {
                return
            }

            & $selectVersionCatalogEntry $latestEntry
            & $installVersionCatalogEntry $latestEntry $true
        }
        catch {
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            Write-Log ("Latest version update failed ({0}): {1}" -f $errorCode, $_.Exception.ToString()) 'ERROR'
            $ui.UpdateCheckInProgress = $false
            & $refreshSummary
            $dialogMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
            Show-VersionManagerMessageBox -Owner $form -Message $dialogMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }

    $otherInstallList.Add_SelectedIndexChanged({
        $ui.SelectedInstallation = if ($otherInstallList.SelectedItems.Count -gt 0) { $otherInstallList.SelectedItems[0].Tag } else { $null }
        & $syncInstallationSelectionState
    })

    $versionCatalogList.Add_SelectedIndexChanged({
        $ui.SelectedVersionCatalogEntry = if ($versionCatalogList.SelectedItems.Count -gt 0) { $versionCatalogList.SelectedItems[0].Tag } else { $null }
        & $syncVersionCatalogSelectionState
    })

    $installButtons.UseVersion.Add_Click({
        if ($ui.InstallationOperationInProgress) {
            return
        }

        $entry = $ui.SelectedInstallation
        if ($null -eq $entry -or [bool]$entry.IsCurrent -or -not [bool]$entry.IsValid) {
            return
        }

        try {
            $confirmLines = @(
                (T 'Helper_VersionManager_Install_UseSelectedConfirm' (U '\uC120\uD0DD\uD55C \uC2A4\uD0A8\uC744 \uC0AC\uC6A9\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?')),
                '',
                (TF 'Helper_VersionManager_Install_UseSelectedSource' @([string]$entry.Path) 'Target: %1')
            )
            if (Test-VersionManagerUnsupportedVersionText -VersionText ([string]$entry.VersionText)) {
                $confirmLines += ''
                $confirmLines += (Get-Pre12VersionManagerNotice)
            }
            if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", $confirmLines)))) {
                return
            }

            $ui.InstallationOperationInProgress = $true
            & $syncInstallationSelectionState
            & $showBusyOverlay (T 'Helper_VersionManager_Busy_Switching' 'Switching to the selected installation. Please do not close this window.')
            try {
                $result = Invoke-VersionReleaseInstall -Root $ui.Root -SelectedTargetRoot ([string]$entry.Path)
            }
            finally {
                & $hideBusyOverlay
            }

            if ([string]::Equals([string]$result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$result.Status, 'NOOP', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $result.SourcePath
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $result.LogPath
                }
                & $setVersionManagerTabsDirtyForGlobalMutation
                [void](Start-VersionManagerLauncherForSupportedRoot -ResolvedTargetRoot ([string]$result.SourcePath))
                Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$result.Status)
                $ui.CloseAfterSwitch = $true
                $form.Close()
                return
            }

            $switchFailureMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                (T 'Helper_VersionManager_Install_UseSelectedFailed' 'The selected skin could not be activated. Check the log file for details.')
            }
            else {
                [string]$result.Message
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                $switchFailureMessage += "`r`n`r`n" + [string]$result.LogPath
            }
            Show-VersionManagerMessageBox -Owner $form -Message $switchFailureMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        catch {
            Write-Log ("Installed skin switch failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Install_UseSelectedFailed' 'The selected skin could not be activated. Check the log file for details.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        finally {
            & $hideBusyOverlay
            $ui.InstallationOperationInProgress = $false
            & $syncInstallationSelectionState
        }
    })

    $installVersionCatalogEntry = {
        param(
            [AllowNull()]$entry,
            [bool]$SkipInitialConfirm = $false
        )

        if ($ui.VersionCatalogOperationInProgress) {
            return
        }

        if (-not (& $testVersionCatalogEntryActionable $entry)) {
            return
        }

        $versionText = [string](Get-ObjectPropertyValue -Object $entry -Name 'version' -DefaultValue '')
        $tagText = [string](Get-ObjectPropertyValue -Object $entry -Name 'tag' -DefaultValue '')
        $expectedVersion = if ([string]::IsNullOrWhiteSpace($tagText)) { $versionText } else { $tagText }
        $assetUrl = [string](Get-ObjectPropertyValue -Object $entry -Name 'asset_url' -DefaultValue '')
        $installedPath = [string](Get-ObjectPropertyValue -Object $entry -Name 'installed_path' -DefaultValue '')
        $releaseVariant = [string](Get-ObjectPropertyValue -Object $entry -Name 'release_variant' -DefaultValue '')
        $isInstalled = -not [string]::IsNullOrWhiteSpace($installedPath)
        $isPre12Target = Test-VersionManagerUnsupportedVersionText -VersionText $versionText

        try {
            $confirmMessage = if ($isInstalled) {
                $confirmLines = @(
                    (TF 'Helper_VersionManager_Update_VersionAlreadyInstalledConfirm' @($expectedVersion) (U '\uC774 \uBC84\uC804\uC758 \uC2A4\uD0A8\uC774 \uC774\uBBF8 \uCEF4\uD4E8\uD130\uC5D0 \uC124\uCE58\uB3FC \uC788\uC2B5\uB2C8\uB2E4.')),
                    '',
                    (T 'Helper_VersionManager_Update_VersionUseInstalledConfirm' (U '\uC774 \uBC84\uC804\uC744 \uC0AC\uC6A9\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?'))
                )
                if ($isPre12Target) {
                    $confirmLines += ''
                    $confirmLines += (Get-Pre12VersionManagerNotice)
                }
                [string]::Join("`r`n", $confirmLines)
            }
            else {
                $confirmLines = @(
                    (TF 'Helper_VersionManager_Update_VersionInstallConfirm' @($expectedVersion) (U '\uC774 \uBC84\uC804\uC744 \uC124\uCE58\uD560\uAE4C\uC694?')),
                    '',
                    (T 'Helper_VersionManager_Update_VersionInstallDataNotice' (U '\uC124\uCE58 \uC804 \uD604\uC7AC \uB370\uC774\uD130 \uC5F0\uB3D9 \uD638\uD658\uC131\uC744 \uD655\uC778\uD569\uB2C8\uB2E4.'))
                )
                if ($isPre12Target) {
                    $confirmLines += ''
                    $confirmLines += (Get-Pre12VersionManagerNotice)
                }
                [string]::Join("`r`n", $confirmLines)
            }
            if (-not $SkipInitialConfirm) {
                if (-not (Confirm-Dialog -Owner $form -Message $confirmMessage)) {
                    return
                }
            }

            $ui.VersionCatalogOperationInProgress = $true
            & $syncVersionCatalogSelectionState
            $busyMessage = if ($isInstalled) {
                T 'Helper_VersionManager_Busy_Switching' 'Switching to the selected installation. Please do not close this window.'
            }
            else {
                T 'Helper_VersionManager_Busy_InstallingSelected' 'Installing the selected version. Please do not close this window.'
            }
            & $showBusyOverlay $busyMessage
            try {
                $result = if ($isInstalled) {
                    Invoke-VersionReleaseInstall -Root $ui.Root -SelectedTargetRoot $installedPath -ExpectedReleaseVariant $releaseVariant
                }
                else {
                    Invoke-VersionReleaseInstall -Root $ui.Root -PackageUrl $assetUrl -ExpectedVersion $expectedVersion -ExpectedReleaseVariant $releaseVariant
                }
            }
            finally {
                & $hideBusyOverlay
            }
            if ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase) -and -not $isInstalled) {
                $warningMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                    (T 'Helper_VersionManager_Update_CompatibilityWarn' (U '\uD604\uC7AC \uB370\uC774\uD130\uC640 \uC120\uD0DD\uD55C \uBC84\uC804\uC758 \uC5F0\uB3D9\uC774 \uC644\uC804\uD788 \uD638\uD658\uB418\uC9C0 \uC54A\uC744 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uB370\uC774\uD130 \uC190\uC2E4\uC774 \uBC1C\uC0DD\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.'))
                }
                else {
                    [string]$result.Message
                }
                if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", @(
                    $warningMessage,
                    '',
                    (T 'Helper_VersionManager_Update_CompatibilityWarnProceed' (U '\uADF8\uB798\uB3C4 \uC124\uCE58\uB97C \uACC4\uC18D\uD560\uAE4C\uC694?'))
                ))))) {
                    return
                }
                & $showBusyOverlay (T 'Helper_VersionManager_Busy_InstallingSelected' 'Installing the selected version. Please do not close this window.')
                try {
                    $result = Invoke-VersionReleaseInstall -Root $ui.Root -PackageUrl $assetUrl -ExpectedVersion $expectedVersion -ExpectedReleaseVariant $releaseVariant -AllowCompatibilityWarning
                }
                finally {
                    & $hideBusyOverlay
                }
            }
            if ([string]::Equals([string]$result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$result.Status, 'NOOP', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $result.SourcePath
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $result.LogPath
                }
                & $setVersionManagerTabsDirtyForGlobalMutation
                [void](Start-VersionManagerLauncherForSupportedRoot -ResolvedTargetRoot ([string]$result.SourcePath))
                Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$result.Status)
                $ui.CloseAfterSwitch = $true
                $form.Close()
                return
            }

            $dialogIcon = [System.Windows.Forms.MessageBoxIcon]::Error
            $dialogMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                (T 'Helper_VersionManager_Update_ApplyFailed' 'The update could not be applied. Check the log file for details.')
            }
            else {
                [string]$result.Message
            }
            if ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase)) {
                $dialogIcon = [System.Windows.Forms.MessageBoxIcon]::Warning
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                $dialogMessage += "`r`n`r`n" + [string]$result.LogPath
            }
            Show-VersionManagerMessageBox -Owner $form -Message $dialogMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon $dialogIcon | Out-Null
        }
        catch {
            Write-Log ("Version catalog install failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Update_ApplyFailed' 'The update could not be applied. Check the log file for details.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        finally {
            & $hideBusyOverlay
            $ui.VersionCatalogOperationInProgress = $false
            & $syncVersionCatalogSelectionState
            if (-not $ui.CloseAfterSwitch) {
                & $refreshVersionCatalog
                & $refreshSettingsTab
            }
        }
    }

    $versionCatalogInstallButton.Add_Click({
        & $installVersionCatalogEntry $ui.SelectedVersionCatalogEntry
    })

    $installButtons.Import.Add_Click({
        try {
            $entry = $ui.SelectedInstallation
            if ($null -eq $entry -or -not $entry.ImportAllowed) {
                return
            }
            if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", @(
                (T 'Helper_VersionManager_Import_ConfirmIntro' 'Import the selected installation data into the current version.'),
                '',
                (TF 'Helper_VersionManager_Import_ConfirmSource' @([string]$entry.Path) 'Source: %1')
            ))))) {
                return
            }

            $result = Invoke-ImportFromInstallation -Root $ui.Root -SourcePath ([string]$entry.Path)
            $installResult.Text = [string]$result.Message
            if ($result.Status -eq 'OK') {
                if (-not [string]::IsNullOrWhiteSpace($result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $result.SourcePath
                }
                if (-not [string]::IsNullOrWhiteSpace($result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $result.LogPath
                }
                Invoke-RainmeterBang -Bang '!RefreshGroup' -Arguments @('DMeloper')
                Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Import_Success' 'Old-data import completed.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            elseif ($result.Status -eq 'CANCEL') {
                Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Import_Canceled' 'Old-data import was canceled.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            else {
                Show-VersionManagerMessageBox -Owner $form -Message ([string]$result.Message + "`r`n`r`n" + [string]$result.LogPath) -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            & $setVersionManagerTabsDirtyForGlobalMutation
            & $refreshAll
        }
        catch {
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Import_Failed' 'Old-data import failed. Check the log file for details.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $installButtons.Delete.Add_Click({
        try {
            $entry = $ui.SelectedInstallation
            if ($null -eq $entry -or [bool]$entry.IsCurrent) {
                return
            }
            $confirmMessage = if ($entry.Source -eq 'manual') {
                T 'Helper_VersionManager_SourceDialog_DeleteConfirm' 'Remove this item from the manual source list. The actual folder is not deleted.'
            }
            else {
                [string]::Join("`r`n", @(
                    (T 'Helper_VersionManager_Install_DeleteInstalledConfirm' (U '\uC120\uD0DD\uD55C \uC2A4\uD0A8 \uD3F4\uB354\uB97C \uD734\uC9C0\uD1B5\uC73C\uB85C \uBCF4\uB0BC\uAE4C\uC694?')),
                    '',
                    (TF 'Helper_VersionManager_Install_DeleteInstalledSource' @([string]$entry.Path) 'Folder: %1')
                ))
            }
            if (-not (Confirm-Dialog -Owner $form -Message $confirmMessage)) {
                return
            }

            if ($entry.Source -eq 'manual') {
                $next = foreach ($item in @(Read-SourceRegistry -Root $ui.Root)) {
                    if (-not [string]::Equals([string]$item.Path, [string]$entry.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $item
                    }
                }
                Write-SourceRegistry -Root $ui.Root -Entries @($next)
            }
            else {
                Remove-InstalledSkinFolder -Path ([string]$entry.Path) -CurrentRoot $ui.Root
            }
            & $setVersionManagerTabsDirtyForInstallationMutation
            & $refreshInstallations
        }
        catch {
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Install_DeleteFailed' 'The selected skin could not be removed. Check the log file for details.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $footerRefresh.Add_Click({
        & $refreshAll
    })
    $footerCheckLatest.Add_Click({
        & $runLatestCheck $false
    })
    $footerInstallLatest.Add_Click({
        & $installLatestVersion
    })
    $settingsOpenLogButton.Add_Click({
        $logFolder = Split-Path -Parent (Get-LatestHelperLogPath -Root $ui.Root)
        if ([string]::IsNullOrWhiteSpace($logFolder)) {
            $logFolder = Get-VersionManagerLogsRoot -Root $ui.Root
        }
        Open-FolderPath -Path $logFolder
    })
    $footerOpenDownloadPage.Add_Click({
        Start-Process -FilePath (Get-VersionManagerDownloadPageUrl)
    })
    $footerOpenRepositoryPage.Add_Click({
        Start-Process -FilePath (Get-VersionManagerRepositoryUrl -Root $ui.Root)
    })
    $settingsOpenSkinButton.Add_Click({
        Open-FolderPath -Path $ui.Root
    })
    $settingsLogCopyButton.Add_Click({
        if (-not $ui.SettingsLogHasContent) {
            return
        }

        try {
            [System.Windows.Forms.Clipboard]::SetText([string]$settingsLogText.Text)
        }
        catch {
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Log_CopyFailed' 'Could not copy the log text.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })
    $settingsLogClearButton.Add_Click({
        if (-not $ui.SettingsLogHasContent) {
            return
        }

        if (-not (Confirm-Dialog -Owner $form -Message (T 'Helper_VersionManager_Log_ClearConfirm' 'Delete the skin log file contents and clear the current session log view?'))) {
            return
        }

        try {
            Clear-VersionManagerLogs -Root $ui.Root -CurrentLogPath $script:LogPath
            & $setVersionManagerTabsDirty 'settingsLog'
            & $refreshSettingsTab
        }
        catch {
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Log_ClearFailed' 'The logs could not be cleared. Check the log file for details.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $currentVersionValue.Text = [string]$ui.TargetVersionText
    & $setCurrentVersionState 'unknown' (T 'Helper_VersionManager_Summary_UpdateChecking' 'Update status: checking latest version...')
    $footerRefresh.Enabled = $false
    $footerCheckLatest.Enabled = $false
    $footerInstallLatest.Enabled = $false
    $versionCatalogInstallButton.Enabled = $false
    $installButtons.UseVersion.Enabled = $false
    $installButtons.Import.Enabled = $false
    $installButtons.Delete.Enabled = $false
    $settingsLogCopyButton.Enabled = $false
    $settingsLogClearButton.Enabled = $false
    [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
    [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
    [void]$otherInstallList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
    [void]$versionCatalogList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
    $settingsLogText.Text = T 'Helper_VersionManager_Common_Loading' 'Loading...'

    $autoCheckTimer = New-Object System.Windows.Forms.Timer
    $autoCheckTimer.Interval = 200
    $autoCheckTimer.Add_Tick({
        $autoCheckTimer.Stop()
        & $runLatestCheck $true
    })

    $startAutoCheck = {
        if (-not $ui.HasSessionUpdateStatus -and -not $ui.UpdateCheckInProgress) {
            $autoCheckTimer.Start()
        }
    }

    $initialHydrationStages = @(
        [PSCustomObject]@{
            Name = 'summary'
            Action = {
                & $refreshSummary
            }
        },
        [PSCustomObject]@{
            Name = 'finalize'
            Action = {
                $ui.InitialHydrationCompleted = $true
                $footerRefresh.Enabled = $true
                $footerCheckLatest.Enabled = $true
                if ($deferredHydrationStages.Count -gt 0) {
                    $deferredHydrationTimer.Start()
                }
                else {
                    & $startAutoCheck
                }
            }
        }
    )

    $deferredHydrationStages = @(
        [PSCustomObject]@{
            Name = 'versionCatalog'
            Action = {
                & $refreshVersionCatalog
            }
        },
        [PSCustomObject]@{
            Name = 'installations'
            Action = {
                & $refreshInstallations
            }
        },
        [PSCustomObject]@{
            Name = 'settingsLog'
            Action = {
                & $refreshSettingsTab
            }
        }
    )

    $initialHydrationTimer = New-Object System.Windows.Forms.Timer
    $initialHydrationTimer.Interval = 1
    $initialHydrationTimer.Add_Tick({
        $initialHydrationTimer.Stop()
        if ($ui.InitialHydrationCompleted) {
            return
        }
        if ($ui.InitialHydrationStageIndex -ge $initialHydrationStages.Count) {
            return
        }

        $stage = $initialHydrationStages[$ui.InitialHydrationStageIndex]
        try {
            & $stage.Action
        }
        catch {
            & $handleInitialHydrationStageFailure ([string]$stage.Name) $_.Exception
        }
        finally {
            $ui.InitialHydrationStageIndex += 1
            if ($ui.InitialHydrationStageIndex -lt $initialHydrationStages.Count) {
                $initialHydrationTimer.Start()
            }
        }
    })

    $deferredHydrationTimer = New-Object System.Windows.Forms.Timer
    $deferredHydrationTimer.Interval = 25
    $deferredHydrationTimer.Add_Tick({
        $deferredHydrationTimer.Stop()
        if ($ui.DeferredHydrationStageIndex -ge $deferredHydrationStages.Count) {
            return
        }

        $stage = $deferredHydrationStages[$ui.DeferredHydrationStageIndex]
        try {
            & $stage.Action
        }
        catch {
            & $handleInitialHydrationStageFailure ([string]$stage.Name) $_.Exception
        }
        finally {
            $ui.DeferredHydrationStageIndex += 1
            if ($ui.DeferredHydrationStageIndex -lt $deferredHydrationStages.Count) {
                $deferredHydrationTimer.Start()
            }
            else {
                & $startAutoCheck
            }
        }
    })

    $form.Add_Shown({
        Save-VersionManagerLaunchState -Root $ui.Root -Status 'shown' -LaunchTokenValue $LaunchToken
        $initialHydrationTimer.Start()
    })
    $ui.FirstPaintRecorded = $false
    $form.Add_Paint({
        if (-not $ui.FirstPaintRecorded) {
            $ui.FirstPaintRecorded = $true
        }
    })
    $form.Add_FormClosing({
        param($sender, [System.Windows.Forms.FormClosingEventArgs]$eventArgs)

        if ($ui.InstallationOperationInProgress -and -not $ui.CloseAfterSwitch) {
            $eventArgs.Cancel = $true
            $script:VersionManagerWindowClosing = $false
            return
        }

        $script:VersionManagerWindowClosing = $true
        foreach ($timer in @($initialHydrationTimer, $deferredHydrationTimer, $autoCheckTimer)) {
            try {
                if ($null -ne $timer) {
                    $timer.Stop()
                }
            }
            catch {
            }
        }
        try {
            & $hideBusyOverlay
        }
        catch {
        }
    })
    [void]$form.ShowDialog()
}
