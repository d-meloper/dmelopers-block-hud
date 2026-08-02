# Editor PickPathFlow helpers - App picker cache and UI

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-StartAppEntries() {
    $apps = Get-StartApps | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.Name) -eq $false -and
        [string]::IsNullOrWhiteSpace([string]$_.AppID) -eq $false
    } | Sort-Object Name, AppID -Unique

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($app in $apps) {
        $entries.Add([PSCustomObject]@{
            Name = [string]$app.Name
            AppID = [string]$app.AppID
        })
    }

    return $entries
}

function Read-CachedStartAppEntries() {
    $cachePath = Get-ProgramPickerCachePath
    if (-not [System.IO.File]::Exists($cachePath)) {
        return $null
    }

    try {
        $entries = New-Object System.Collections.Generic.List[object]
        foreach ($line in [System.IO.File]::ReadAllLines($cachePath, $utf8NoBom)) {
            $trimmedLine = [string]$line
            if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
                continue
            }

            $parts = $trimmedLine.Split("`t", 2, [System.StringSplitOptions]::None)
            if ($parts.Length -ne 2) {
                continue
            }

            $appId = [string]$parts[0]
            $name = [string]$parts[1]
            if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $entries.Add([PSCustomObject]@{
                Name = $name
                AppID = $appId
            })
        }

        if ($entries.Count -eq 0) {
            return $null
        }

        return $entries
    }
    catch {
        return $null
    }
}

function Write-CachedStartAppEntries($Entries) {
    if ($null -eq $Entries -or $Entries.Count -eq 0) {
        return
    }

    $cachePath = Get-ProgramPickerCachePath
    try {
        $cacheDirectory = [System.IO.Path]::GetDirectoryName($cachePath)
        if (-not [System.IO.Directory]::Exists($cacheDirectory)) {
            [System.IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
        }

        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $Entries) {
            $appId = [string]$entry.AppID
            $name = [string]$entry.Name
            if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $sanitizedName = $name.Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
            $lines.Add($appId + "`t" + $sanitizedName)
        }

        [System.IO.File]::WriteAllLines($cachePath, $lines, $utf8NoBom)
    }
    catch {
        Write-EditorPickerDebugLogBestEffort -Context 'Picker.ProgramCache.Write' -ErrorRecord $_ -State @{
            CachePath = $cachePath
            EntryCount = $Entries.Count
        }
    }
}

function Get-StartAppRefreshResult($CachedEntries) {
    # The cache is only a fast first paint. It cannot be the catalog truth because
    # Lua cache cleanup is intentionally unavailable on non-ASCII installation roots.
    $fallbackEntries = @()
    if ($null -ne $CachedEntries) {
        $fallbackEntries = @($CachedEntries)
    }

    try {
        $liveEntries = @(Get-StartAppEntries)
        if ($liveEntries.Count -gt 0) {
            Write-CachedStartAppEntries -Entries $liveEntries
            return [PSCustomObject]@{
                Entries = $liveEntries
                UsedLiveEntries = $true
                ErrorRecord = $null
            }
        }

        return [PSCustomObject]@{
            Entries = $fallbackEntries
            UsedLiveEntries = $false
            ErrorRecord = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Entries = $fallbackEntries
            UsedLiveEntries = $false
            ErrorRecord = $_
        }
    }
}

function Show-AppDialog {
    param(
        [System.Windows.Forms.IWin32Window]$Owner
    )

    if (-not $script:AppPickerIconSupportLoaded) {
        . $script:LoadAppPickerIconSupport
    }

    $appTitle = Get-LocText 'Helper_PickPath_AppTitle' 'Choose a program'
    $searchLabelText = Get-LocText 'Helper_PickPath_AppSearch' 'Search'
    $okText = Get-LocText 'Common_Select' 'Select'
    $closeText = Get-LocText 'Common_Close' 'Close'
    $loadingAppsText = Get-LocText 'Helper_PickPath_AppLoading' 'Loading program list...'
    $noAppsText = Get-LocText 'Helper_PickPath_AppNoItems' 'Could not load the installed Start program list.'
    $nameHeader = Get-LocText 'Helper_PickPath_AppNameHeader' 'Program name'
    $iconSize = 16

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $appTitle
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(760, 520)

    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = $searchLabelText
    $searchLabel.AutoSize = $true
    $searchLabel.Location = New-Object System.Drawing.Point(12, 16)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Bounds = New-Object System.Drawing.Rectangle(60, 12, 688, 24)

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Bounds = New-Object System.Drawing.Rectangle(12, 48, 736, 420)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true
    $listView.HideSelection = $false
    $listView.MultiSelect = $false
    $listView.GridLines = $true
    [void]$listView.Columns.Add($nameHeader, 712)

    $smallImageList = New-Object System.Windows.Forms.ImageList
    $smallImageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
    $smallImageList.ImageSize = New-Object System.Drawing.Size($iconSize, $iconSize)
    $fallbackBitmap = New-FallbackAppBitmap -Size $iconSize
    $smallImageList.Images.Add('fallback', $fallbackBitmap)
    $fallbackImageIndex = $smallImageList.Images.IndexOfKey('fallback')
    $appImageIndexCache = @{}
    $listView.SmallImageList = $smallImageList
    $allApps = New-Object System.Collections.Generic.List[object]
    $iconState = [pscustomobject]@{
        DisplayedItemsByAppId = @{}
        PendingIconAppIds = New-Object System.Collections.Generic.Queue[string]
    }
    $cachedEntries = Read-CachedStartAppEntries
    $loadTimer = New-Object System.Windows.Forms.Timer
    $loadTimer.Interval = if ($null -ne $cachedEntries) { 100 } else { 10 }
    $searchTimer = New-Object System.Windows.Forms.Timer
    $searchTimer.Interval = 100
    $iconTimer = New-Object System.Windows.Forms.Timer
    $iconTimer.Interval = 15
    $searchBox.Enabled = $false
    $listView.Enabled = $false
    $getStartAppEntriesInvoker = ${function:Get-StartAppEntries}
    $getStartAppRefreshResultInvoker = ${function:Get-StartAppRefreshResult}
    $writeEditorPickerDebugLogInvoker = ${function:Write-EditorPickerDebugLogBestEffort}
    $getAppPickerImageIndexInvoker = ${function:Get-AppPickerImageIndex}
    $dialogState = [pscustomobject]@{
        EnumerationComplete = $false
        EnumerationStarted = $false
        LiveRefreshStarted = $false
        PendingSearchRefresh = $false
        LastSearchInputAt = [DateTime]::MinValue
        LastAppliedFilterText = $null
        CacheHit = ($null -ne $cachedEntries)
    }

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.AutoSize = $false
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $statusLabel.Bounds = New-Object System.Drawing.Rectangle(12, 474, 500, 20)
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $statusLabel.Text = $loadingAppsText

    $buttonOk = New-Object System.Windows.Forms.Button
    $buttonOk.Text = $okText
    $buttonOk.Bounds = New-Object System.Drawing.Rectangle(520, 488, 108, 28)
    $buttonOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $buttonOk.Enabled = $false

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = $closeText
    $buttonClose.Bounds = New-Object System.Drawing.Rectangle(640, 488, 108, 28)
    $buttonClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.Add($searchLabel)
    $form.Controls.Add($searchBox)
    $form.Controls.Add($listView)
    $form.Controls.Add($statusLabel)
    $form.Controls.Add($buttonOk)
    $form.Controls.Add($buttonClose)
    $form.CancelButton = $buttonClose

    try {
        $updateButtonState = {
            $buttonOk.Enabled = $listView.SelectedItems.Count -gt 0
        }

        $updateStatus = {
            $visibleCount = $listView.Items.Count
            $totalCount = $allApps.Count
            if (-not $dialogState.EnumerationStarted) {
                $statusLabel.Text = $loadingAppsText
                return
            }
            if (-not $dialogState.EnumerationComplete) {
                $statusLabel.Text = $loadingAppsText
                return
            }
            if ($totalCount -eq 0) {
                $statusLabel.Text = $noAppsText
                return
            }
            $statusLabel.Text = '{0} / {1}' -f $visibleCount, $totalCount
        }

        $ensureSelection = {
            if ($listView.SelectedItems.Count -gt 0) {
                & $updateButtonState
                return
            }
            if ($listView.Items.Count -gt 0) {
                $listView.Items[0].Selected = $true
                $listView.Items[0].Focused = $true
            }
            & $updateButtonState
        }

        $populateVisibleList = {
            param([string]$PreferredAppID = '')

            $iconTimer.Stop()
            $iconState.DisplayedItemsByAppId = @{}
            $iconState.PendingIconAppIds = New-Object System.Collections.Generic.Queue[string]
            $listView.BeginUpdate()
            $listView.Items.Clear()
            $preferredItem = $null
            $filterText = ([string]$searchBox.Text).Trim().ToLowerInvariant()
            foreach ($app in $allApps) {
                if ([string]::IsNullOrEmpty($filterText) -eq $false) {
                    $nameText = ([string]$app.Name).ToLowerInvariant()
                    $appIdText = ([string]$app.AppID).ToLowerInvariant()
                    if ($nameText.Contains($filterText) -eq $false -and $appIdText.Contains($filterText) -eq $false) {
                        continue
                    }
                }
                $appId = [string]$app.AppID
                $imageIndex = $fallbackImageIndex
                if ($appImageIndexCache.ContainsKey($appId)) {
                    $imageIndex = [int]$appImageIndexCache[$appId]
                }
                $item = New-Object System.Windows.Forms.ListViewItem(([string]$app.Name), $imageIndex)
                $item.Tag = $app
                [void]$listView.Items.Add($item)
                if (
                    $null -eq $preferredItem -and
                    [string]::IsNullOrWhiteSpace($PreferredAppID) -eq $false -and
                    [string]::Equals($appId, $PreferredAppID, [System.StringComparison]::OrdinalIgnoreCase)
                ) {
                    $preferredItem = $item
                }
                $iconState.DisplayedItemsByAppId[$appId] = $item
                if ($imageIndex -eq $fallbackImageIndex) {
                    $iconState.PendingIconAppIds.Enqueue($appId)
                }
            }
            $listView.EndUpdate()
            if ($null -ne $preferredItem) {
                $preferredItem.Selected = $true
                $preferredItem.Focused = $true
            }
            & $ensureSelection
            & $updateStatus
            & $updateButtonState
            $listView.Refresh()
            $statusLabel.Refresh()
            $dialogState.LastAppliedFilterText = $filterText
            if ($iconState.PendingIconAppIds.Count -gt 0) {
                $iconTimer.Start()
            }
        }

        $beginLoad = {
            if ($dialogState.LiveRefreshStarted) {
                return
            }
            $dialogState.LiveRefreshStarted = $true

            $preferredAppID = ''
            if ($listView.SelectedItems.Count -gt 0) {
                $selectedApp = $listView.SelectedItems[0].Tag
                if ($null -ne $selectedApp) {
                    $preferredAppID = [string]$selectedApp.AppID
                }
            }

            if (-not $dialogState.CacheHit) {
                $dialogState.EnumerationStarted = $true
                & $updateStatus
            }

            $refreshResult = & $getStartAppRefreshResultInvoker $cachedEntries
            if ($null -ne $refreshResult.ErrorRecord) {
                & $writeEditorPickerDebugLogInvoker -Context 'Picker.ProgramCache.Refresh' -ErrorRecord $refreshResult.ErrorRecord -State @{
                    CacheHit = $dialogState.CacheHit
                }
            }

            if ($refreshResult.UsedLiveEntries -or -not $dialogState.CacheHit) {
                $allApps.Clear()
                foreach ($app in @($refreshResult.Entries)) {
                    $allApps.Add($app)
                }
                $dialogState.EnumerationStarted = $true
                $dialogState.EnumerationComplete = $true
                & $populateVisibleList $preferredAppID
            }

            $searchBox.Enabled = $true
            $listView.Enabled = $true
            $searchTimer.Start()
            $searchBox.Focus()
        }

        $searchBox.Add_TextChanged({
            if (-not $dialogState.EnumerationComplete) {
                return
            }
            $dialogState.LastSearchInputAt = [DateTime]::UtcNow
            $dialogState.PendingSearchRefresh = $true
        }.GetNewClosure())
        $searchTimer.Add_Tick({
            if (-not $dialogState.EnumerationComplete) {
                return
            }
            if (-not $dialogState.PendingSearchRefresh) {
                return
            }
            $elapsed = ([DateTime]::UtcNow - $dialogState.LastSearchInputAt).TotalMilliseconds
            if ($elapsed -lt 500) {
                return
            }
            $filterText = ([string]$searchBox.Text).Trim().ToLowerInvariant()
            $dialogState.PendingSearchRefresh = $false
            if ($filterText -eq $dialogState.LastAppliedFilterText) {
                return
            }
            & $populateVisibleList
        }.GetNewClosure())
        $searchBox.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                $dialogState.LastSearchInputAt = [DateTime]::UtcNow.AddMilliseconds(-500)
                $dialogState.PendingSearchRefresh = $true
                $eventArgs.SuppressKeyPress = $true
                $eventArgs.Handled = $true
            }
        }.GetNewClosure())
        $iconTimer.Add_Tick({
            $iconTimer.Stop()
            $processed = 0
            while ($iconState.PendingIconAppIds.Count -gt 0 -and $processed -lt 8) {
                $appId = $iconState.PendingIconAppIds.Dequeue()
                if ($appImageIndexCache.ContainsKey($appId)) {
                    $processed++
                    continue
                }

                $item = $iconState.DisplayedItemsByAppId[$appId]
                if ($null -eq $item) {
                    $processed++
                    continue
                }

                $imageIndex = & $getAppPickerImageIndexInvoker -ImageList $smallImageList -ImageIndexCache $appImageIndexCache -AppID $appId -Size $iconSize -FallbackIndex $fallbackImageIndex
                if ($item.ImageIndex -ne $imageIndex) {
                    $item.ImageIndex = $imageIndex
                }
                $processed++
            }
            if ($iconState.PendingIconAppIds.Count -gt 0) {
                $iconTimer.Start()
            }
        }.GetNewClosure())
        $listView.Add_SelectedIndexChanged({
            & $updateButtonState
        }.GetNewClosure())
        $listView.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $listView.SelectedItems.Count -gt 0) {
                $eventArgs.SuppressKeyPress = $true
                $eventArgs.Handled = $true
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.Close()
            }
        }.GetNewClosure())
        $listView.Add_DoubleClick({
            if ($listView.SelectedItems.Count -gt 0) {
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.Close()
            }
        }.GetNewClosure())
        $form.Add_Shown({
            $form.TopMost = $true
            $form.BringToFront()
            $form.Activate()
            $searchBox.Focus()
            if ($dialogState.CacheHit) {
                $allApps.Clear()
                foreach ($app in @($cachedEntries)) {
                    $allApps.Add($app)
                }
                $dialogState.EnumerationStarted = $true
                $dialogState.EnumerationComplete = $true
                $searchBox.Enabled = $true
                $listView.Enabled = $true
                & $populateVisibleList
                $searchTimer.Start()
                $loadTimer.Start()
            }
            else {
                $loadTimer.Start()
            }
        }.GetNewClosure())
        $loadTimer.Add_Tick({
            $loadTimer.Stop()
            & $beginLoad
        }.GetNewClosure())

        $searchBox.Text = ''

        if ($form.ShowDialog($Owner) -eq [System.Windows.Forms.DialogResult]::OK -and $listView.SelectedItems.Count -gt 0) {
            $selectedApp = $listView.SelectedItems[0].Tag
            $selectedAction = 'explorer.exe shell:AppsFolder\' + [string]$selectedApp.AppID
            $importResult = $null
            try {
                if (-not $script:ImageImportHelpersLoaded) {
                    . $script:LoadImageImportHelpers
                }
                $importResult = Import-ProgramPickerImage $selectedApp
                if ($null -ne $importResult -and (-not [bool]$importResult.ManifestPersisted) -and -not [string]::IsNullOrWhiteSpace([string]$importResult.WarningMessage)) {
                    [System.Windows.Forms.MessageBox]::Show($form, [string]$importResult.WarningMessage, $appTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                }
            }
            catch {
                Write-EditorPickerDebugLogBestEffort -Context 'Picker.ProgramImage.Import' -ErrorRecord $_ -State @{
                    Action = $selectedAction
                    AppID = [string]$selectedApp.AppID
                    ProgramName = [string]$selectedApp.Name
                }
            }
            Write-ProgramActionLabel -Action $selectedAction -Label ([string]$selectedApp.Name)
            return [PSCustomObject]@{
                Action = $selectedAction
                ImageKey = if ($null -ne $importResult) { [string]$importResult.ImageKey } else { $null }
                ItemImageAssets = if ($null -ne $importResult) { [string]$importResult.ItemImageAssets } else { $null }
                ProgramLabel = [string]$selectedApp.Name
            }
        }

        return $null
    }
    finally {
        $iconTimer.Stop()
        $iconTimer.Dispose()
        $searchTimer.Stop()
        $searchTimer.Dispose()
        $loadTimer.Stop()
        $loadTimer.Dispose()
        $smallImageList.Dispose()
        $form.Dispose()
        Close-AppPickerIconResolver
    }
}
