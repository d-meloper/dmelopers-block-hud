# OpenVersionManager helpers - Main WinForms UI

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Start-VersionManager {
    $root = Get-TargetRoot
    if (-not (Test-SkinRoot -Root $root)) {
        throw 'TargetRoot is not a valid Block HUD skin root.'
    }
    $normalizedInitialAction = [string]$InitialAction
    if ([string]::IsNullOrWhiteSpace($normalizedInitialAction)) {
        $normalizedInitialAction = ''
    }
    elseif ([string]::Equals($normalizedInitialAction, 'InstallLatest', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedInitialAction = 'InstallLatest'
    }
    else {
        throw "Unsupported InitialAction '$normalizedInitialAction'."
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
    $ui.VerifiedBadge = $null
    $ui.BadgeRequestSucceeded = $false
    $ui.LatestInstallInProgress = $false
    $ui.InstallationOperationInProgress = $false
    $ui.UpdateCheckInProgress = $false
    $ui.BusyOverlayVisible = $false
    $ui.BusyOverlayControlStates = @()
    $ui.BusyOverlayStartedAtUtc = [datetime]::MinValue
    $ui.BusyOverlayBaseMessage = ''
    $ui.BusyOverlayProgressToken = ''
    $ui.BusyOverlayProgressPath = ''
    $ui.BusyOverlayProgressSignature = ''
    $ui.HasSessionUpdateStatus = $false
    $ui.InitialAction = $normalizedInitialAction
    $ui.InitialActionStarted = $false
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
    $latestVersionValue = New-Object System.Windows.Forms.Label
    $latestVersionValue.Location = New-Object System.Drawing.Point(180, 32)
    $latestVersionValue.Size = New-Object System.Drawing.Size(310, 20)
    $latestVersionValue.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $latestVersionValue.Text = (T 'Helper_VersionManager_Update_StatusLatest' 'Latest') + ': -'
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
        $latestVersionValue,
        $currentVersionStateIcon,
        $currentVersionStatusText,
        $footerCheckLatest,
        $footerInstallLatest
    ))

    $currentSkinResetGroup = New-Object System.Windows.Forms.GroupBox
    $currentSkinResetGroup.Text = T 'Helper_VersionManager_Reset_CurrentGroup' (U '\uD604\uC7AC \uC2A4\uD0A8 \uCD08\uAE30\uD654')
    $currentSkinResetGroup.Bounds = New-Object System.Drawing.Rectangle(12, 140, 720, 75)

    $currentSkinResetDescription = New-Object System.Windows.Forms.Label
    $currentSkinResetDescription.Bounds = New-Object System.Drawing.Rectangle(18, 24, 500, 32)
    $currentSkinResetDescription.Text = T 'Helper_VersionManager_Reset_CurrentDescription' (U '\uD604\uC7AC \uC2A4\uD0A8\uC758 \uBAA8\uB4E0 \uC124\uC815\uACFC \uC0AC\uC6A9\uC790 \uB370\uC774\uD130\uB97C \uCD08\uAE30 \uC0C1\uD0DC\uB85C \uB418\uB3CC\uB9BD\uB2C8\uB2E4.')
    [void](Set-VersionManagerControlTextFit `
        -Control $currentSkinResetDescription `
        -BaseFontSize ([single]$currentSkinResetDescription.Font.SizeInPoints) `
        -MinimumScale 0.70 `
        -Multiline)

    $currentSkinResetButton = New-Object System.Windows.Forms.Button
    $currentSkinResetButton.Bounds = New-Object System.Drawing.Rectangle(536, 20, 176, 26)
    $currentSkinResetButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $currentSkinResetButton.Text = T 'Helper_VersionManager_Reset_CurrentAction' (U '\uC2A4\uD0A8 \uCD08\uAE30\uD654')
    $currentSkinResetButton.AutoEllipsis = $true
    [void](Set-VersionManagerControlTextFit `
        -Control $currentSkinResetButton `
        -BaseFontSize ([single]$currentSkinResetButton.Font.SizeInPoints) `
        -MinimumScale 0.70 `
        -HorizontalPadding 16 `
        -VerticalPadding 6)
    $currentSkinResetButton.ForeColor = [System.Drawing.Color]::Red
    $currentSkinResetButton.Enabled = $false

    $currentSkinResetGroup.Controls.AddRange(@($currentSkinResetDescription, $currentSkinResetButton))

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
    $installTab.Controls.AddRange(@($currentInstallGroup, $currentSkinResetGroup))

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
    $footerRefresh.Text = T 'Common_Refresh' 'Refresh'
    $footerRefresh.Bounds = New-Object System.Drawing.Rectangle(12, 353, 88, 28)
    $footerOpenDownloadPage = New-Object System.Windows.Forms.Button
    $footerOpenDownloadPage.Text = T 'Helper_VersionManager_Action_OpenReleasePage' 'Download page'
    $footerOpenDownloadPage.Bounds = New-Object System.Drawing.Rectangle(108, 353, 148, 28)
    $footerOpenRepositoryPage = New-Object System.Windows.Forms.Button
    $footerOpenRepositoryPage.Text = T 'Helper_VersionManager_Action_OpenRepositoryPage' 'GitHub page'
    $footerOpenRepositoryPage.Bounds = New-Object System.Drawing.Rectangle(264, 353, 148, 28)
    $footerClose = New-Object System.Windows.Forms.Button
    $footerClose.Text = T 'Common_Close' 'Close'
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
    $busyOverlayCard.Bounds = New-Object System.Drawing.Rectangle(150, 108, 484, 176)
    $busyOverlayCard.BackColor = [System.Drawing.Color]::White
    $busyOverlayCard.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $busyOverlayTitle = New-Object System.Windows.Forms.Label
    $busyOverlayTitle.Bounds = New-Object System.Drawing.Rectangle(22, 20, 438, 24)
    $busyOverlayTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $busyOverlayTitle.Text = ''

    $busyOverlayMessage = New-Object System.Windows.Forms.Label
    $busyOverlayMessage.Bounds = New-Object System.Drawing.Rectangle(22, 50, 438, 42)
    $busyOverlayMessage.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $busyOverlayMessage.Text = ''

    $busyOverlayTitleBaseFontSize = [single]$busyOverlayTitle.Font.SizeInPoints
    $busyOverlayMessageBaseFontSize = [single]$busyOverlayMessage.Font.SizeInPoints
    $setBusyOverlayTitle = {
        param([AllowNull()][string]$Text)

        $busyOverlayTitle.Text = [string]$Text
        [void](Set-VersionManagerControlTextFit `
            -Control $busyOverlayTitle `
            -BaseFontSize $busyOverlayTitleBaseFontSize `
            -MinimumScale 0.70)
    }.GetNewClosure()
    $setBusyOverlayMessage = {
        param([AllowNull()][string]$Text)

        $busyOverlayMessage.Text = [string]$Text
        [void](Set-VersionManagerControlTextFit `
            -Control $busyOverlayMessage `
            -BaseFontSize $busyOverlayMessageBaseFontSize `
            -MinimumScale 0.70 `
            -Multiline)
    }.GetNewClosure()
    & $setBusyOverlayTitle (T 'Helper_VersionManager_Busy_Title' 'Skin manager task in progress')
    & $setBusyOverlayMessage (T 'Helper_VersionManager_Busy_Default' 'Downloading files and preparing skin data. Please do not close this window.')

    $busyOverlayElapsed = New-Object System.Windows.Forms.Label
    $busyOverlayElapsed.Bounds = New-Object System.Drawing.Rectangle(22, 104, 438, 18)
    $busyOverlayElapsed.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $busyOverlayElapsed.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $busyOverlayElapsed.Text = TF 'Helper_VersionManager_Busy_Elapsed' @('0') 'Elapsed time: %1 seconds'

    $busyOverlayProgress = New-Object System.Windows.Forms.ProgressBar
    $busyOverlayProgress.Bounds = New-Object System.Drawing.Rectangle(22, 134, 438, 16)
    $busyOverlayProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $busyOverlayProgress.MarqueeAnimationSpeed = 35

    $busyOverlayCard.Controls.AddRange(@($busyOverlayTitle, $busyOverlayMessage, $busyOverlayElapsed, $busyOverlayProgress))
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

    $newVersionImportProgressToken = {
        param([string]$Prefix = 'version-manager-import')

        $normalizedPrefix = ([string]$Prefix).Trim().ToLowerInvariant()
        if ($normalizedPrefix -notmatch '^[a-z0-9][a-z0-9._-]*$') {
            $normalizedPrefix = 'version-manager-import'
        }
        return ('{0}-{1}' -f $normalizedPrefix, [guid]::NewGuid().ToString('N'))
    }

    $resetBusyOverlayProgress = {
        & $setBusyOverlayMessage ([string]$ui.BusyOverlayBaseMessage)
        $busyOverlayProgress.MarqueeAnimationSpeed = 35
        $busyOverlayProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $busyOverlayProgress.Value = 0
        $ui.BusyOverlayProgressSignature = ''
    }

    $formatProgressBytes = {
        param([long]$ByteCount)

        $safeBytes = [Math]::Max([long]0, $ByteCount)
        if ($safeBytes -ge 1073741824) {
            return ('{0:N2} GiB' -f ($safeBytes / 1073741824.0))
        }
        return ('{0:N1} MiB' -f ($safeBytes / 1048576.0))
    }

    $readVersionImportProgress = {
        if ([string]::IsNullOrWhiteSpace([string]$ui.BusyOverlayProgressToken) -or
            [string]::IsNullOrWhiteSpace([string]$ui.BusyOverlayProgressPath) -or
            -not (Test-Path -LiteralPath $ui.BusyOverlayProgressPath -PathType Leaf)) {
            return $null
        }

        try {
            $progress = [System.IO.File]::ReadAllText($ui.BusyOverlayProgressPath, (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
            $schemaVersion = Get-ObjectPropertyValue -Object $progress -Name 'SchemaVersion' -DefaultValue $null
            $token = [string](Get-ObjectPropertyValue -Object $progress -Name 'Token' -DefaultValue '')
            $stage = [string](Get-ObjectPropertyValue -Object $progress -Name 'Stage' -DefaultValue '')
            $detailVisible = Get-ObjectPropertyValue -Object $progress -Name 'DetailVisible' -DefaultValue $null
            $updatedAtUtc = [string](Get-ObjectPropertyValue -Object $progress -Name 'UpdatedAtUtc' -DefaultValue '')
            if ($schemaVersion -isnot [int] -or $schemaVersion -ne 1 -or
                -not [string]::Equals($token, [string]$ui.BusyOverlayProgressToken, [System.StringComparison]::Ordinal) -or
                $stage -notin @('backup', 'audio-copy', 'jukebox-state', 'validating') -or
                $detailVisible -isnot [bool] -or
                $updatedAtUtc -notmatch '^\d{4}-\d{2}-\d{2}T.+Z$') {
                return $null
            }

            $values = [ordered]@{}
            foreach ($name in @('CompletedBytes', 'TotalBytes', 'CompletedFiles', 'TotalFiles')) {
                $rawValue = Get-ObjectPropertyValue -Object $progress -Name $name -DefaultValue $null
                if ($null -eq $rawValue -or $rawValue -is [bool] -or $rawValue -is [string]) {
                    return $null
                }
                $decimalValue = [decimal]$rawValue
                if ($decimalValue -lt 0 -or $decimalValue -ne [decimal]::Truncate($decimalValue) -or
                    $decimalValue -gt [long]::MaxValue) {
                    return $null
                }
                $values[$name] = [long]$decimalValue
            }
            if ($values.CompletedBytes -gt $values.TotalBytes -or $values.CompletedFiles -gt $values.TotalFiles) {
                return $null
            }

            return [PSCustomObject]@{
                Stage = $stage
                DetailVisible = [bool]$detailVisible
                CompletedBytes = [long]$values.CompletedBytes
                TotalBytes = [long]$values.TotalBytes
                CompletedFiles = [long]$values.CompletedFiles
                TotalFiles = [long]$values.TotalFiles
                UpdatedAtUtc = $updatedAtUtc
            }
        }
        catch {
            return $null
        }
    }

    $updateBusyOverlayProgress = {
        if (-not $ui.BusyOverlayVisible -or [string]::IsNullOrWhiteSpace([string]$ui.BusyOverlayProgressToken)) {
            return
        }

        $progress = & $readVersionImportProgress
        if ($null -eq $progress -or -not [bool]$progress.DetailVisible) {
            if (-not [string]::IsNullOrEmpty([string]$ui.BusyOverlayProgressSignature)) {
                & $resetBusyOverlayProgress
            }
            return
        }

        $signature = '{0}|{1}|{2}|{3}|{4}|{5}' -f $progress.Stage, $progress.CompletedBytes, $progress.TotalBytes, $progress.CompletedFiles, $progress.TotalFiles, $progress.UpdatedAtUtc
        if ([string]::Equals($signature, [string]$ui.BusyOverlayProgressSignature, [System.StringComparison]::Ordinal)) {
            return
        }

        $percent = if ($progress.TotalBytes -gt 0) {
            [Math]::Floor(($progress.CompletedBytes * 100.0) / $progress.TotalBytes)
        }
        elseif ($progress.TotalFiles -gt 0) {
            [Math]::Floor(($progress.CompletedFiles * 100.0) / $progress.TotalFiles)
        }
        else {
            0
        }
        $percent = [int][Math]::Max(0, [Math]::Min(100, $percent))
        $stageMessage = switch ($progress.Stage) {
            'backup' { T 'Helper_VersionManager_Busy_BackingUpLocalData' 'Backing up local data.' }
            'audio-copy' { T 'Helper_VersionManager_Busy_CopyingLocalAudio' 'Copying local audio files.' }
            default { [string]$ui.BusyOverlayBaseMessage }
        }
        $detail = [string]$percent + '%'
        if ($progress.Stage -in @('backup', 'audio-copy')) {
            $detail = TF 'Helper_VersionManager_Busy_MigrationProgress' @(
                [string]$percent,
                (& $formatProgressBytes $progress.CompletedBytes),
                (& $formatProgressBytes $progress.TotalBytes)
            ) '%1% · %2 / %3'
        }
        & $setBusyOverlayMessage ([string]::Join("`r`n", @($stageMessage, $detail)))
        $busyOverlayProgress.MarqueeAnimationSpeed = 0
        $busyOverlayProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $busyOverlayProgress.Value = $percent
        $ui.BusyOverlayProgressSignature = $signature
    }

    $updateBusyOverlayElapsed = {
        $elapsedSeconds = if ($ui.BusyOverlayStartedAtUtc -ne [datetime]::MinValue) {
            [Math]::Max(0, [Math]::Floor(([datetime]::UtcNow - $ui.BusyOverlayStartedAtUtc).TotalSeconds))
        }
        else {
            0
        }
        $busyOverlayElapsed.Text = TF 'Helper_VersionManager_Busy_Elapsed' @([string]$elapsedSeconds) 'Elapsed time: %1 seconds'
    }

    $busyOverlayTimer = New-Object System.Windows.Forms.Timer
    $busyOverlayTimer.Interval = 250
    $busyOverlayTimer.Add_Tick({
        & $updateBusyOverlayElapsed
        & $updateBusyOverlayProgress
    })

    $showBusyOverlay = {
        param(
            [AllowNull()][string]$Message,
            [AllowNull()][string]$Title = '',
            [string]$ProgressToken = '',
            [datetime]$StartedAtUtc = [datetime]::MinValue
        )

        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = T 'Helper_VersionManager_Busy_Default' 'Downloading files and preparing skin data. Please do not close this window.'
        }

        if ([string]::IsNullOrWhiteSpace($Title)) {
            $Title = T 'Helper_VersionManager_Busy_Title' 'Skin manager task in progress'
        }

        & $setBusyOverlayTitle $Title
        $ui.BusyOverlayBaseMessage = $Message
        $ui.BusyOverlayProgressToken = ''
        $ui.BusyOverlayProgressPath = ''
        if ($ProgressToken -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$') {
            $ui.BusyOverlayProgressToken = $ProgressToken
            $ui.BusyOverlayProgressPath = Join-Path (Join-Path $ui.Root '@Resources\Customs\Data') ('VersionImportProgress_{0}.json' -f $ProgressToken)
        }
        & $resetBusyOverlayProgress

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
            $busyOverlayTimer.Start()
        }

        $ui.BusyOverlayStartedAtUtc = if ($StartedAtUtc -ne [datetime]::MinValue) {
            $StartedAtUtc.ToUniversalTime()
        }
        else {
            [datetime]::UtcNow
        }

        & $updateBusyOverlayElapsed
        & $updateBusyOverlayProgress
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
        $busyOverlayTimer.Stop()
        $ui.BusyOverlayStartedAtUtc = [datetime]::MinValue
        $ui.BusyOverlayBaseMessage = ''
        $ui.BusyOverlayProgressToken = ''
        $ui.BusyOverlayProgressPath = ''
        & $resetBusyOverlayProgress
        $form.UseWaitCursor = $false
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
        [System.Windows.Forms.Application]::DoEvents()
    }

    $ensureInteractiveModules = {
        if (Test-VersionManagerInteractiveModulesLoaded) {
            return
        }

        & $showBusyOverlay `
            (T 'Helper_VersionManager_Busy_PreparingFeatures' 'Preparing Skin manager features.') `
            (T 'Helper_VersionManager_WindowTitle' 'Skin manager')
        try {
            [void](Ensure-VersionManagerInteractiveModules)
        }
        finally {
            & $hideBusyOverlay
        }
    }

    $recoverInteractiveStateAfterFailure = {
        try {
            & $hideBusyOverlay
        }
        catch {
        }

        $ui.UpdateCheckInProgress = $false
        $ui.LatestInstallInProgress = $false
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
            $latestDisplayText = if ($ui.BadgeRequestSucceeded -and $null -ne $ui.VerifiedBadge) {
                [string]$ui.VerifiedBadge.Tag
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$ui.UpdateCache.LatestVersion)) {
                [string]$ui.UpdateCache.LatestVersion
            }
            else {
                '-'
            }
            $latestVersionValue.Text = (T 'Helper_VersionManager_Update_StatusLatest' 'Latest') + ': ' + $latestDisplayText

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

            if (-not $ui.BadgeRequestSucceeded -or $null -eq $ui.VerifiedBadge) {
                $friendlyStatus = Get-UpdateFriendlyMessage -ErrorCode ([string]$ui.UpdateCache.ErrorCode) -DefaultMessage ([string]$ui.UpdateCache.Error) -Surface 'summary'
                & $setCurrentVersionState 'error' $friendlyStatus
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }

            $latestComparableVersion = $ui.VerifiedBadge.Version
            if (-not $latestComparableVersion) {
                $unknownText = T 'Helper_VersionManager_Update_StatusUnknown' 'Unknown'
                & $setCurrentVersionState 'unknown' (TF 'Helper_VersionManager_Summary_UpdateErrorFormat' @($unknownText) 'Update status: %1')
                $footerInstallLatest.Enabled = $false
                $completedRefresh = $true
                return
            }
            if ($latestComparableVersion -and $ui.TargetVersion -and ($latestComparableVersion -gt $ui.TargetVersion)) {
                & $setCurrentVersionState 'not-latest' (TF 'Helper_VersionManager_Summary_UpdateAvailable' @([string]$ui.VerifiedBadge.Tag) 'Update status: update available (%1)')
                $footerInstallLatest.Enabled = (-not $ui.UpdateCheckInProgress -and -not $ui.LatestInstallInProgress)
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

    $syncInstallationSelectionState = {
        $entry = $ui.SelectedInstallation
        $canUseSelected = ($null -ne $entry) -and
            (-not [bool]$entry.IsCurrent) -and
            [bool]$entry.IsValid -and
            (-not $ui.InstallationOperationInProgress) -and
            (-not $ui.LatestInstallInProgress) -and
            (-not $ui.UpdateCheckInProgress)
        $canImportSelected = ($null -ne $entry) -and
            [bool]$entry.ImportAllowed -and
            (-not $ui.InstallationOperationInProgress) -and
            (-not $ui.LatestInstallInProgress) -and
            (-not $ui.UpdateCheckInProgress)
        $canDeleteSelected = ($null -ne $entry) -and
            (-not [bool]$entry.IsCurrent) -and
            ($entry.Source -eq 'manual' -or $entry.Source -eq 'auto') -and
            (-not $ui.InstallationOperationInProgress) -and
            (-not $ui.LatestInstallInProgress) -and
            (-not $ui.UpdateCheckInProgress)

        $installButtons.UseVersion.Enabled = $canUseSelected
        $installButtons.Import.Enabled = $canImportSelected
        $installButtons.Delete.Enabled = $canDeleteSelected
    }

    $syncCurrentSkinResetState = {
        $configured = $false
        try {
            $ui.UpdateConfig = Get-UpdateConfiguration -Root $ui.Root
            [void](Get-VersionManagerBadgeProfile -Config $ui.UpdateConfig)
            $configured = Test-UpdateConfigured -Config $ui.UpdateConfig
        }
        catch {
            $configured = $false
        }
        $currentSkinResetButton.Enabled = (
            $configured -and
            $null -ne $ui.TargetVersion -and
            -not $ui.UpdateCheckInProgress -and
            -not $ui.LatestInstallInProgress -and
            -not $ui.InstallationOperationInProgress)
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

    $installVerifiedBadgeEntry = $null

    $refreshAll = {
        & $setVersionManagerTabsDirtyForGlobalMutation
        $ui.TargetVersionText = Get-SkinMetadataVersion -Root $ui.Root
        $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
        & $refreshInstallations
        & $runLatestCheck $true
        & $refreshSettingsTab
        & $syncCurrentSkinResetState
    }

    $runLatestCheck = {
        param([bool]$Silent)

        if ($ui.UpdateCheckInProgress) {
            return $false
        }

        try {
            $ui.UpdateCheckInProgress = $true
            $ui.BadgeRequestSucceeded = $false
            $ui.VerifiedBadge = $null
            $footerRefresh.Enabled = $false
            $footerCheckLatest.Enabled = $false
            $footerInstallLatest.Enabled = $false
            & $syncInstallationSelectionState
            & $syncCurrentSkinResetState
            & $refreshSummary
            [System.Windows.Forms.Application]::DoEvents()

            $ui.UpdateConfig = Get-UpdateConfiguration -Root $ui.Root
            if (-not (Test-UpdateConfigured -Config $ui.UpdateConfig)) {
                throw (New-UpdateOperationException -ErrorCode 'update-source-unconfigured' -Message (T 'Helper_VersionManager_Update_SourceUnconfigured' 'The update source is not configured yet.'))
            }
            $badge = Invoke-VersionManagerBadgeRequest -Config $ui.UpdateConfig -TimeoutSeconds 15
            $ui.VerifiedBadge = $badge
            $ui.BadgeRequestSucceeded = $true
            $ui.UpdateCache = Update-UpdateCache -Root $ui.Root -Patch ([PSCustomObject]@{
                LastCheckedAtUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                LatestVersion = [string]$badge.Tag
                RepositorySlug = [string]$badge.RepositorySlug
                ReleaseName = [string]$badge.ReleaseName
                ReleaseUrl = [string]$badge.ReleaseUrl
                AssetName = [string]$badge.AssetName
                AssetUrl = [string]$badge.AssetUrl
                PublishedAtUtc = [string]$badge.PublishedAtUtc
                Status = 'ready'
                Error = ''
                ErrorCode = ''
                FailureHint = ''
                ReleaseVariant = [string]$badge.ReleaseVariant
                ActiveAssetPattern = [string]$badge.AssetName
            })
            $ui.HasSessionUpdateStatus = $true
            & $setVersionManagerTabsDirtyForLatestStateMutation
            & $refreshSummary
            & $refreshSettingsTab
            return $true
        }
        catch {
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            if ([string]::IsNullOrWhiteSpace($errorCode) -or [string]::Equals($errorCode, 'update-unexpected', [System.StringComparison]::OrdinalIgnoreCase)) {
                try {
                    if ($_.Exception.Data.Contains('DMEL_ERROR_CODE')) {
                        $errorCode = [string]$_.Exception.Data['DMEL_ERROR_CODE']
                    }
                }
                catch {
                }
            }
            $ui.BadgeRequestSucceeded = $false
            $ui.VerifiedBadge = $null
            $ui.HasSessionUpdateStatus = $true
            $previousCache = Get-UpdateCache -Root $ui.Root
            $previousVersion = ConvertTo-VersionManagerStableComparableVersion -VersionText ([string]$previousCache.LatestVersion)
            $previousProvenanceValid = ($null -ne $previousVersion -and
                [string]::Equals([string]$previousCache.RepositorySlug, ('{0}/{1}' -f $ui.UpdateConfig.Owner, $ui.UpdateConfig.Repo), [System.StringComparison]::Ordinal) -and
                [string]::Equals([string]$previousCache.ReleaseVariant, [string]$ui.UpdateConfig.ReleaseVariant, [System.StringComparison]::Ordinal) -and
                [string]::Equals([string]$previousCache.AssetName, [string]$ui.UpdateConfig.ActiveAssetPattern, [System.StringComparison]::Ordinal))
            $ui.UpdateCache = Update-UpdateCache -Root $ui.Root -Patch ([PSCustomObject]@{
                Status = $(if ($previousProvenanceValid) { 'ready' } else { 'error' })
                Error = [string]$_.Exception.Message
                ErrorCode = $errorCode
                FailureHint = 'badge-feed'
            })
            Write-Log ("Latest badge refresh failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            & $refreshSummary
            if (-not $Silent -and -not $script:VersionManagerWindowClosing) {
                $dialogMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
                Show-VersionManagerMessageBox -Owner $form -Message $dialogMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            return $false
        }
        finally {
            $ui.UpdateCheckInProgress = $false
            $footerRefresh.Enabled = $true
            $footerCheckLatest.Enabled = $true
            & $syncInstallationSelectionState
            & $syncCurrentSkinResetState
            try { & $refreshSummary } catch {}
        }
    }

    $installLatestVersion = {
        if ($ui.UpdateCheckInProgress -or $ui.LatestInstallInProgress) {
            return
        }

        & $ensureInteractiveModules

        try {
            $config = Get-UpdateConfiguration -Root $ui.Root
            if (-not (Test-UpdateConfigured -Config $config)) {
                throw (New-UpdateOperationException -ErrorCode 'update-source-unconfigured' -Message (T 'Helper_VersionManager_Update_SourceUnconfigured' 'The update source is not configured yet.'))
            }

            if (-not $ui.BadgeRequestSucceeded -or $null -eq $ui.VerifiedBadge) {
                throw (New-UpdateOperationException -ErrorCode 'badge-feed-unverified' -Message 'A verified latest-version badge is required before updating.')
            }
            $latestComparableVersion = $ui.VerifiedBadge.Version
            if (-not $latestComparableVersion -or -not $ui.TargetVersion -or ($latestComparableVersion -le $ui.TargetVersion)) {
                return
            }

            $installedPath = ''
            foreach ($installation in @($ui.OtherInstallations)) {
                $installedVersion = ConvertTo-VersionManagerStableComparableVersion -VersionText ([string]$installation.VersionText)
                if ($null -eq $installedVersion -or $installedVersion -ne $latestComparableVersion -or -not [bool]$installation.IsValid) {
                    continue
                }
                try {
                    $installedConfig = Get-UpdateConfiguration -Root ([string]$installation.Path)
                    if ([string]::Equals([string]$installedConfig.ReleaseVariant, [string]$ui.VerifiedBadge.ReleaseVariant, [System.StringComparison]::Ordinal)) {
                        $installedPath = [string]$installation.Path
                        break
                    }
                }
                catch {
                }
            }

            $latestEntry = [PSCustomObject]@{
                Version = [string]$ui.VerifiedBadge.VersionText
                Tag = [string]$ui.VerifiedBadge.Tag
                AssetUrl = [string]$ui.VerifiedBadge.AssetUrl
                InstalledPath = $installedPath
                ReleaseVariant = [string]$ui.VerifiedBadge.ReleaseVariant
            }
            & $installVerifiedBadgeEntry $latestEntry $true
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

    $runInitialAction = {
        $action = [string]$ui.InitialAction
        if ([string]::IsNullOrWhiteSpace($action) -or $ui.InitialActionStarted) {
            return $false
        }

        $ui.InitialActionStarted = $true
        Write-Log ("Running initial Skin manager action: {0}" -f $action) 'INFO'
        if ([string]::Equals($action, 'InstallLatest', [System.StringComparison]::OrdinalIgnoreCase)) {
            & $installLatestVersion
            return $true
        }

        Write-Log ("Unsupported initial Skin manager action skipped: {0}" -f $action) 'ERROR'
        return $false
    }

    $otherInstallList.Add_SelectedIndexChanged({
        $ui.SelectedInstallation = if ($otherInstallList.SelectedItems.Count -gt 0) { $otherInstallList.SelectedItems[0].Tag } else { $null }
        & $syncInstallationSelectionState
    })

    $installButtons.UseVersion.Add_Click({
        if ($ui.InstallationOperationInProgress) {
            return
        }

        & $ensureInteractiveModules

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
            & $showBusyOverlay `
                (T 'Helper_VersionManager_Busy_Switching' 'Switching to the selected installation. Please do not close this window.') `
                (T 'Helper_VersionManager_Action_UseVersion' 'Use this skin')
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

    $installVerifiedBadgeEntry = {
        param(
            [AllowNull()]$entry,
            [bool]$SkipInitialConfirm = $false
        )

        if ($ui.LatestInstallInProgress) {
            return
        }

        & $ensureInteractiveModules

        if ($null -eq $entry) {
            return
        }

        $versionText = [string](Get-ObjectPropertyValue -Object $entry -Name 'Version' -DefaultValue '')
        $tagText = [string](Get-ObjectPropertyValue -Object $entry -Name 'Tag' -DefaultValue '')
        $expectedVersion = if ([string]::IsNullOrWhiteSpace($tagText)) { $versionText } else { $tagText }
        $assetUrl = [string](Get-ObjectPropertyValue -Object $entry -Name 'AssetUrl' -DefaultValue '')
        $installedPath = [string](Get-ObjectPropertyValue -Object $entry -Name 'InstalledPath' -DefaultValue '')
        $releaseVariant = [string](Get-ObjectPropertyValue -Object $entry -Name 'ReleaseVariant' -DefaultValue '')
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

            $ui.LatestInstallInProgress = $true
            & $syncInstallationSelectionState
            & $syncCurrentSkinResetState
            $busyMessage = if ($isInstalled) {
                T 'Helper_VersionManager_Busy_Switching' 'Switching to the selected installation. Please do not close this window.'
            }
            elseif ($SkipInitialConfirm) {
                T 'Helper_VersionManager_Busy_Applying' 'Updating... Please do not close this window.'
            }
            else {
                T 'Helper_VersionManager_Busy_InstallingSelected' 'Installing the selected version. Please do not close this window.'
            }
            $operationStartedAtUtc = [datetime]::UtcNow
            $progressToken = if ($isInstalled) { '' } else { & $newVersionImportProgressToken 'version-manager-install' }
            $busyTitle = if ($isInstalled) {
                T 'Helper_VersionManager_Action_UseVersion' 'Use this skin'
            }
            elseif ($SkipInitialConfirm) {
                T 'Helper_VersionManager_Action_ApplyUpdate' 'Apply update'
            }
            else {
                T 'Helper_VersionManager_Action_InstallVersion' 'Install this version'
            }
            & $showBusyOverlay $busyMessage $busyTitle $progressToken $operationStartedAtUtc
            try {
                $result = if ($isInstalled) {
                    Invoke-VersionReleaseInstall -Root $ui.Root -SelectedTargetRoot $installedPath -ExpectedReleaseVariant $releaseVariant
                }
                else {
                    Invoke-VersionReleaseInstall -Root $ui.Root -PackageUrl $assetUrl -ExpectedVersion $expectedVersion -ExpectedReleaseVariant $releaseVariant -ProgressOwnerRoot $ui.Root -ProgressToken $progressToken
                }
            }
            finally {
                & $hideBusyOverlay
            }
            $repairPlanId = ([string]$result.RepairPlanId).Trim()
            $isRepairableWarning = ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$result.Compatibility, 'REPAIRABLE', [System.StringComparison]::OrdinalIgnoreCase) -and
                $repairPlanId -match '^[0-9A-Fa-f]{64}$')
            if ($isRepairableWarning -and -not $isInstalled) {
                $warningMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                    $fallbackSummary = ([string]$result.RepairSummary).Trim()
                    if ($fallbackSummary.Length -gt 480) {
                        $fallbackSummary = $fallbackSummary.Substring(0, 480).Trim() + '...'
                    }
                    (TF 'Helper_VersionManager_Update_CompatibilityRepairWarning' @([string]$result.RepairCount, $fallbackSummary) 'Some item image references cannot be imported. Only those image fields will be cleared; all other current data will be imported. Repair count: %1. %2')
                }
                else {
                    [string]$result.Message
                }
                if (-not (Confirm-Dialog -Owner $form -Message ([string]::Join("`r`n", @(
                    $warningMessage,
                    '',
                    (T 'Helper_VersionManager_Update_CompatibilityRepairProceed' 'Clear only the unusable image fields listed above, import all other current data, and continue installing?')
                ))))) {
                    return
                }
                & $showBusyOverlay `
                    $busyMessage `
                    $busyTitle `
                    $progressToken `
                    $operationStartedAtUtc
                try {
                    $result = Invoke-VersionReleaseInstall -Root $ui.Root -PackageUrl $assetUrl -ExpectedVersion $expectedVersion -ExpectedReleaseVariant $releaseVariant -AllowCompatibilityWarning -ExpectedRepairPlanId $repairPlanId -ProgressOwnerRoot $ui.Root -ProgressToken $progressToken
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
            Write-Log ("Verified latest-version install failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            $errorCode = Get-UpdateConfigurationErrorCode -Exception $_.Exception
            $dialogMessage = Get-UpdateFriendlyMessage -ErrorCode $errorCode -DefaultMessage ([string]$_.Exception.Message) -Surface 'dialog'
            Show-VersionManagerMessageBox -Owner $form -Message $dialogMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        finally {
            & $hideBusyOverlay
            $ui.LatestInstallInProgress = $false
            & $syncInstallationSelectionState
            & $syncCurrentSkinResetState
            if (-not $ui.CloseAfterSwitch) {
                & $refreshInstallations
                & $refreshSummary
                & $refreshSettingsTab
            }
        }
    }

    $installButtons.Import.Add_Click({
        & $ensureInteractiveModules
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

            $progressToken = & $newVersionImportProgressToken 'version-manager-import'
            $operationStartedAtUtc = [datetime]::UtcNow
            $ui.InstallationOperationInProgress = $true
            & $syncInstallationSelectionState
            & $showBusyOverlay `
                (T 'Helper_VersionManager_Busy_BackingUpLocalData' 'Backing up local data.') `
                (T 'Helper_VersionManager_Action_ImportData' 'Import data') `
                $progressToken `
                $operationStartedAtUtc
            try {
                $result = Invoke-ImportFromInstallation -Root $ui.Root -SourcePath ([string]$entry.Path) -ProgressOwnerRoot $ui.Root -ProgressToken $progressToken
            }
            finally {
                & $hideBusyOverlay
                $ui.InstallationOperationInProgress = $false
                & $syncInstallationSelectionState
            }
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
        & $ensureInteractiveModules
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

    $currentSkinResetButton.Add_Click({
        if ($ui.UpdateCheckInProgress -or $ui.LatestInstallInProgress -or $ui.InstallationOperationInProgress) {
            return
        }

        & $ensureInteractiveModules
        try {
            $ui.TargetVersionText = Get-SkinMetadataVersion -Root $ui.Root
            $ui.TargetVersion = Convert-ToVersion -VersionText $ui.TargetVersionText
            if ($null -eq $ui.TargetVersion) {
                throw (New-UpdateOperationException -ErrorCode 'reset-current-version-invalid' -Message 'The current skin version could not be validated.')
            }
            $ui.UpdateConfig = Get-UpdateConfiguration -Root $ui.Root
            $profile = Get-VersionManagerBadgeProfile -Config $ui.UpdateConfig
            $variant = [string]$ui.UpdateConfig.ReleaseVariant
            $assetName = Get-BlockHudFixedUpdateZipAssetName -ReleaseVariant $variant -LanguageCode $script:LanguageCode
            $currentTag = ([string]$ui.TargetVersionText).Trim()
            if (-not $currentTag.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
                $currentTag = 'v' + $currentTag
            }
            if ($null -eq (ConvertTo-VersionManagerStableComparableVersion -VersionText $currentTag)) {
                throw (New-UpdateOperationException -ErrorCode 'reset-current-version-invalid' -Message 'The current skin version is not a stable semantic version.')
            }

            $confirmMessage = [string]::Join("`r`n", @(
                (TF 'Helper_VersionManager_Reset_ConfirmIntro' @($currentTag) (U '\uD604\uC7AC \uC124\uCE58\uB41C %1 \uBC84\uC804\uC744 \uC0C8\uB85C \uB0B4\uB824\uBC1B\uC544 \uD604\uC7AC \uC2A4\uD0A8\uC744 \uC644\uC804\uD788 \uCD08\uAE30\uD654\uD569\uB2C8\uB2E4.')),
                '',
                (T 'Helper_VersionManager_Reset_ConfirmDataLoss' (U '\uC124\uC815, \uC0AC\uC6A9\uC790 \uC774\uBBF8\uC9C0\u00B7\uC74C\uC6D0, \uC544\uC774\uD15C, \uD3B8\uC9D1 \uB370\uC774\uD130, \uC7AC\uC0DD \uC124\uC815, \uB85C\uADF8\uC640 \uCE90\uC2DC\uB97C \uD3EC\uD568\uD55C \uD604\uC7AC \uC2A4\uD0A8\uC758 \uBAA8\uB4E0 \uB370\uC774\uD130\uAC00 \uC601\uAD6C\uC801\uC73C\uB85C \uC0AD\uC81C\uB418\uBA70 \uBCF5\uAD6C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.')),
                '',
                (T 'Helper_VersionManager_Reset_ConfirmOtherInstallations' (U '\uB2E4\uB978 \uC124\uCE58\uB41C \uC2A4\uD0A8\uC740 \uBCC0\uACBD\uB418\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4. \uACC4\uC18D\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?'))
            ))
            $confirmation = Show-VersionManagerMessageBox `
                -Owner $form `
                -Message $confirmMessage `
                -Title (T 'Helper_VersionManager_Reset_CurrentGroup' (U '\uD604\uC7AC \uC2A4\uD0A8 \uCD08\uAE30\uD654')) `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            $packageUrl = 'https://github.com/{0}/releases/download/{1}/{2}' -f `
                [string]$profile.RepositorySlug,
                [uri]::EscapeDataString($currentTag),
                [uri]::EscapeDataString($assetName)
            $ui.InstallationOperationInProgress = $true
            & $syncInstallationSelectionState
            & $syncCurrentSkinResetState
            & $showBusyOverlay `
                (T 'Helper_VersionManager_Reset_BusyDownload' (U '\uB3D9\uC77C\uD55C \uBC84\uC804\uC744 \uC0C8\uB85C \uB0B4\uB824\uBC1B\uB294 \uC911\uC785\uB2C8\uB2E4... \uCC3D\uC744 \uB2EB\uC9C0 \uB9C8\uC138\uC694.')) `
                (T 'Helper_VersionManager_Reset_CurrentGroup' (U '\uD604\uC7AC \uC2A4\uD0A8 \uCD08\uAE30\uD654'))
            $resetStageChanged = {
                param([string]$Stage)

                switch ($Stage) {
                    'validating' {
                        & $setBusyOverlayMessage (T 'Helper_VersionManager_Reset_BusyValidate' (U '\uB2E4\uC6B4\uB85C\uB4DC\uD55C \uC2A4\uD0A8\uC744 \uAC80\uC99D\uD558\uB294 \uC911\uC785\uB2C8\uB2E4... \uCC3D\uC744 \uB2EB\uC9C0 \uB9C8\uC138\uC694.'))
                    }
                    'applying' {
                        & $setBusyOverlayMessage (T 'Helper_VersionManager_Reset_BusyApply' (U '\uD604\uC7AC \uC2A4\uD0A8\uC744 \uCD08\uAE30\uD654\uD558\uB294 \uC911\uC785\uB2C8\uB2E4... \uCC3D\uC744 \uB2EB\uC9C0 \uB9C8\uC138\uC694.'))
                    }
                    default {
                        & $setBusyOverlayMessage (T 'Helper_VersionManager_Reset_BusyDownload' (U '\uB3D9\uC77C\uD55C \uBC84\uC804\uC744 \uC0C8\uB85C \uB0B4\uB824\uBC1B\uB294 \uC911\uC785\uB2C8\uB2E4... \uCC3D\uC744 \uB2EB\uC9C0 \uB9C8\uC138\uC694.'))
                    }
                }
                $busyOverlayMessage.Refresh()
            }.GetNewClosure()
            $result = Invoke-CurrentSkinReset `
                -Root $ui.Root `
                -PackageUrl $packageUrl `
                -ExpectedVersion $currentTag `
                -ExpectedReleaseVariant $variant `
                -OnStageChanged $resetStageChanged
            $successLikeReset = (
                [string]::Equals([string]$result.Status, 'OK', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$result.Status, 'NOOP', [System.StringComparison]::OrdinalIgnoreCase) -or
                ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase) -and
                 -not [string]::IsNullOrWhiteSpace([string]$result.SourcePath)))
            if ($successLikeReset) {
                if (-not [string]::IsNullOrWhiteSpace([string]$result.SourcePath)) {
                    Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value ([string]$result.SourcePath)
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value ([string]$result.LogPath)
                }
                Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$result.Status)
                if ([string]::Equals([string]$result.Status, 'WARN', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $warningMessage = [string]$result.Message
                    if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                        $warningMessage += "`r`n`r`n" + [string]$result.LogPath
                    }
                    Show-VersionManagerMessageBox -Owner $form -Message $warningMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                }
                $ui.CloseAfterSwitch = $true
                $form.Close()
                return
            }

            $failureMessage = if ([string]::IsNullOrWhiteSpace([string]$result.Message)) {
                T 'Helper_VersionManager_Reset_Failed' (U '\uD604\uC7AC \uC2A4\uD0A8\uC744 \uCD08\uAE30\uD654\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. \uB85C\uADF8 \uD30C\uC77C\uC744 \uD655\uC778\uD558\uC138\uC694.')
            }
            else {
                [string]$result.Message
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.LogPath)) {
                $failureMessage += "`r`n`r`n" + [string]$result.LogPath
            }
            Show-VersionManagerMessageBox -Owner $form -Message $failureMessage -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        catch {
            Write-Log ("Current skin reset failed: {0}" -f $_.Exception.ToString()) 'ERROR'
            Show-VersionManagerMessageBox -Owner $form -Message ([string]$_.Exception.Message) -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        finally {
            & $hideBusyOverlay
            $ui.InstallationOperationInProgress = $false
            & $syncInstallationSelectionState
            & $syncCurrentSkinResetState
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
        & $ensureInteractiveModules
        $logFolder = Split-Path -Parent (Get-LatestHelperLogPath -Root $ui.Root)
        if ([string]::IsNullOrWhiteSpace($logFolder)) {
            $logFolder = Get-VersionManagerLogsRoot -Root $ui.Root
        }
        Open-FolderPath -Path $logFolder
    })
    $footerOpenDownloadPage.Add_Click({
        & $ensureInteractiveModules
        Start-Process -FilePath (Get-VersionManagerDownloadPageUrl)
    })
    $footerOpenRepositoryPage.Add_Click({
        & $ensureInteractiveModules
        Start-Process -FilePath (Get-VersionManagerRepositoryUrl -Root $ui.Root)
    })
    $settingsOpenSkinButton.Add_Click({
        & $ensureInteractiveModules
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
            & $ensureInteractiveModules
            Show-VersionManagerMessageBox -Owner $form -Message (T 'Helper_VersionManager_Log_CopyFailed' 'Could not copy the log text.') -Title $form.Text -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })
    $settingsLogClearButton.Add_Click({
        if (-not $ui.SettingsLogHasContent) {
            return
        }

        & $ensureInteractiveModules

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
    $currentSkinResetButton.Enabled = $false
    $installButtons.UseVersion.Enabled = $false
    $installButtons.Import.Enabled = $false
    $installButtons.Delete.Enabled = $false
    $settingsLogCopyButton.Enabled = $false
    $settingsLogClearButton.Enabled = $false
    [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'installations')
    [void](Start-VersionManagerTabLoad -TabStates $ui.TabStates -TabName 'settingsLog')
    [void]$otherInstallList.Items.Add((& $loadingListItem (T 'Helper_VersionManager_Common_Loading' 'Loading...')))
    $settingsLogText.Text = T 'Helper_VersionManager_Common_Loading' 'Loading...'

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
                if ($deferredHydrationStages.Count -gt 0) {
                    $deferredHydrationTimer.Start()
                }
                else {
                    [void](& $runInitialAction)
                }
            }
        }
    )

    $deferredHydrationStages = @(
        [PSCustomObject]@{
            Name = 'installations'
            Action = {
                & $refreshInstallations
            }
        },
        [PSCustomObject]@{
            Name = 'badge'
            Action = {
                [void](& $runLatestCheck $true)
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
                [void](& $runInitialAction)
            }
        }
    })

    $form.Add_Shown({
        $form.TopMost = $true
        $form.BringToFront()
        $form.Activate()
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

        if (($ui.InstallationOperationInProgress -or $ui.LatestInstallInProgress) -and -not $ui.CloseAfterSwitch) {
            $eventArgs.Cancel = $true
            $script:VersionManagerWindowClosing = $false
            return
        }

        $script:VersionManagerWindowClosing = $true
        foreach ($timer in @($initialHydrationTimer, $deferredHydrationTimer, $busyOverlayTimer)) {
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
        try { Save-VersionManagerLaunchState -Root $ui.Root -Status 'closed' -LaunchTokenValue $LaunchToken } catch {}
    })
    [void]$form.ShowDialog()
}
