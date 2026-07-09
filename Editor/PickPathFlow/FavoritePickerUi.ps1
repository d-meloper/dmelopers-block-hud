# Editor PickPathFlow helpers - Image import and favorite picker UI

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function New-FallbackAppBitmap([int]$Size) {
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawIcon([System.Drawing.SystemIcons]::Application, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)))
        return $bitmap
    }
    catch {
        $bitmap.Dispose()
        throw
    }
    finally {
        $graphics.Dispose()
    }
}

function Get-AppPickerIconBitmap([string]$AppID, [int]$Size) {
    if ([string]::IsNullOrWhiteSpace($AppID)) {
        return $null
    }

    try {
        return [ShellAppIconProvider]::GetBitmap('shell:AppsFolder\' + $AppID, $Size)
    }
    catch {
        return $null
    }
}

function Get-AppPickerImageIndex(
    [System.Windows.Forms.ImageList]$ImageList,
    [hashtable]$ImageIndexCache,
    [string]$AppID,
    [int]$Size,
    [int]$FallbackIndex
) {
    if ([string]::IsNullOrWhiteSpace($AppID)) {
        return $FallbackIndex
    }

    if ($ImageIndexCache.ContainsKey($AppID)) {
        return [int]$ImageIndexCache[$AppID]
    }

    $bitmap = Get-AppPickerIconBitmap -AppID $AppID -Size $Size
    if ($null -eq $bitmap) {
        $ImageIndexCache[$AppID] = $FallbackIndex
        return $FallbackIndex
    }

    $ImageList.Images.Add($AppID, $bitmap)
    $imageIndex = $ImageList.Images.IndexOfKey($AppID)
    if ($imageIndex -lt 0) {
        $imageIndex = $FallbackIndex
    }

    $ImageIndexCache[$AppID] = $imageIndex
    return $imageIndex
}

function Get-ProgramPickerImageBaseName([string]$ProgramName) {
    $name = [string]$ProgramName
    if ([string]::IsNullOrWhiteSpace($name)) {
        return 'program'
    }

    return $name + '-program'
}

function Import-ProgramPickerImage($AppEntry) {
    if ($null -eq $AppEntry) {
        return $null
    }

    $importImageCommand = Get-Command Import-EditorItemImageFromFileDetailed -CommandType Function -ErrorAction SilentlyContinue
    if ($null -eq $importImageCommand) {
        . $script:ImageImportHelpersPath
        $script:ImageImportHelpersLoaded = $true
        $importImageCommand = Get-Command Import-EditorItemImageFromFileDetailed -CommandType Function -ErrorAction SilentlyContinue
    }

    if ($null -eq $importImageCommand) {
        throw "Image import helper was not loaded: Import-EditorItemImageFromFileDetailed"
    }

    $itemImageDirectory = Get-EditorItemImageDirectory
    if (-not [System.IO.Directory]::Exists($itemImageDirectory)) {
        return $null
    }

    $bitmap = Get-AppPickerIconBitmap -AppID ([string]$AppEntry.AppID) -Size 256
    if ($null -eq $bitmap) {
        return $null
    }

    $tempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ([System.Guid]::NewGuid().ToString() + '.png'))
    try {
        $bitmap.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $importResult = & $importImageCommand -SourcePath $tempPath -ItemImageDirectory $itemImageDirectory -PreferredBaseName (Get-ProgramPickerImageBaseName ([string]$AppEntry.Name))
        if ($null -eq $importResult -or [string]::IsNullOrWhiteSpace([string]$importResult.FinalPath)) {
            return $null
        }
        return [PSCustomObject]@{
            ImageKey = [System.IO.Path]::GetFileName([string]$importResult.FinalPath)
            ItemImageAssets = if ([string]::IsNullOrWhiteSpace([string]$importResult.ItemImageAssets)) { Get-ItemImageAssetsValue } else { [string]$importResult.ItemImageAssets }
            ManifestPersisted = [bool]$importResult.ManifestPersisted
            WarningMessage = [string]$importResult.WarningMessage
        }
    }
    finally {
        $bitmap.Dispose()
        if ([System.IO.File]::Exists($tempPath)) {
            [System.IO.File]::Delete($tempPath)
        }
    }
}

function Show-FavoriteEditDialog(
    [System.Windows.Forms.IWin32Window]$Owner,
    [string]$Title,
    [string]$InitialLabel,
    [string]$InitialAction,
    [string]$CurrentItemAction
) {
    $nameLabelText = Get-LocText 'Helper_PickPath_FavoriteNameLabel' 'Display name'
    $pathLabelText = Get-LocText 'Helper_PickPath_FavoritePathLabel' 'Run path'
    $useCurrentActionText = Get-LocText 'Helper_PickPath_FavoriteUseCurrentAction' 'Use the current item run path'
    $saveText = Get-LocText 'Common_Save' 'Save'
    $cancelText = Get-LocText 'Common_Cancel' 'Cancel'
    $emptyNameText = Get-LocText 'Helper_PickPath_FavoriteEmptyName' 'Enter a display name.'
    $emptyPathText = Get-LocText 'Helper_PickPath_FavoriteEmptyPath' 'Enter a run path.'
    $currentPathMissingText = Get-LocText 'Helper_PickPath_FavoriteCurrentPathMissing' 'The current item does not have a run path.'

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(500, 218)

    $labelName = New-Object System.Windows.Forms.Label
    $labelName.Text = $nameLabelText
    $labelName.AutoSize = $true
    $labelName.Location = New-Object System.Drawing.Point(12, 16)

    $textName = New-Object System.Windows.Forms.TextBox
    $textName.Bounds = New-Object System.Drawing.Rectangle(12, 38, 476, 24)
    $textName.Text = [string]$InitialLabel

    $labelPath = New-Object System.Windows.Forms.Label
    $labelPath.Text = $pathLabelText
    $labelPath.AutoSize = $true
    $labelPath.Location = New-Object System.Drawing.Point(12, 74)

    $textPath = New-Object System.Windows.Forms.TextBox
    $textPath.Bounds = New-Object System.Drawing.Rectangle(12, 96, 476, 24)
    $textPath.Text = [string]$InitialAction

    $buttonUseCurrent = New-Object System.Windows.Forms.Button
    $buttonUseCurrent.Text = $useCurrentActionText
    $buttonUseCurrent.Bounds = New-Object System.Drawing.Rectangle(12, 128, 476, 28)

    $buttonSave = New-Object System.Windows.Forms.Button
    $buttonSave.Text = $saveText
    $buttonSave.Bounds = New-Object System.Drawing.Rectangle(292, 168, 94, 28)

    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Text = $cancelText
    $buttonCancel.Bounds = New-Object System.Drawing.Rectangle(394, 168, 94, 28)
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialogState = [pscustomobject]@{
        Result = $null
        Title = [string]$Title
        CurrentItemAction = [string]$CurrentItemAction
        CurrentPathMissingText = $currentPathMissingText
        EmptyNameText = $emptyNameText
        EmptyPathText = $emptyPathText
        Form = $form
        TextName = $textName
        TextPath = $textPath
    }

    $buttonUseCurrent.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace([string]$dialogState.CurrentItemAction)) {
                [System.Windows.Forms.MessageBox]::Show($dialogState.Form, [string]$dialogState.CurrentPathMissingText, [string]$dialogState.Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                return
            }

            $dialogState.TextPath.Text = [string]$dialogState.CurrentItemAction
        }
        catch {
            $logPath = Write-EditorPickerDebugLog -Context 'Show-FavoriteEditDialog.UseCurrent' -ErrorRecord $_ -State @{
                CurrentItemAction = [string]$dialogState.CurrentItemAction
                DialogTitle = [string]$dialogState.Title
                PathText = [string]$dialogState.TextPath.Text
                NameText = [string]$dialogState.TextName.Text
            }
            Show-EditorPickerDebugError -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $buttonSave.Add_Click({
        try {
            $resolvedLabel = ([string]$dialogState.TextName.Text).Trim()
            $resolvedAction = ([string]$dialogState.TextPath.Text).Trim()

            if ([string]::IsNullOrWhiteSpace($resolvedLabel)) {
                [System.Windows.Forms.MessageBox]::Show($dialogState.Form, [string]$dialogState.EmptyNameText, [string]$dialogState.Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                $dialogState.TextName.Focus()
                return
            }

            if ([string]::IsNullOrWhiteSpace($resolvedAction)) {
                [System.Windows.Forms.MessageBox]::Show($dialogState.Form, [string]$dialogState.EmptyPathText, [string]$dialogState.Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                $dialogState.TextPath.Focus()
                return
            }

            $dialogState.Result = [PSCustomObject]@{
                Label = $resolvedLabel
                Action = $resolvedAction
            }
            $dialogState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialogState.Form.Close()
        }
        catch {
            $logPath = Write-EditorPickerDebugLog -Context 'Show-FavoriteEditDialog.Save' -ErrorRecord $_ -State @{
                CurrentItemAction = [string]$dialogState.CurrentItemAction
                DialogTitle = [string]$dialogState.Title
                NameText = [string]$dialogState.TextName.Text
                PathText = [string]$dialogState.TextPath.Text
            }
            Show-EditorPickerDebugError -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $form.Controls.Add($labelName)
    $form.Controls.Add($textName)
    $form.Controls.Add($buttonUseCurrent)
    $form.Controls.Add($labelPath)
    $form.Controls.Add($textPath)
    $form.Controls.Add($buttonSave)
    $form.Controls.Add($buttonCancel)
    $form.AcceptButton = $buttonSave
    $form.CancelButton = $buttonCancel

    [void]$form.ShowDialog($Owner)
    $form.Dispose()
    return $dialogState.Result
}

function Show-FavoriteDialog([System.Windows.Forms.IWin32Window]$Owner) {
    $favoriteTitle = Get-LocText 'Helper_PickPath_FavoritesTitle' 'Choose a favorite'
    $addText = Get-LocText 'Common_Add' 'Add'
    $editText = Get-LocText 'Helper_PickPath_FavoritesEdit' 'Edit'
    $deleteText = Get-LocText 'Helper_PickPath_FavoritesDelete' 'Delete'
    $okText = Get-LocText 'Common_Select' 'Select'
    $closeText = Get-LocText 'Common_Close' 'Close'
    $readOnlyText = Get-LocText 'Helper_PickPath_FavoritesReadOnly' 'Built-in favorites cannot be edited or deleted.'
    $addTitle = Get-LocText 'Helper_PickPath_FavoritesAddTitle' 'Add favorite'
    $editTitle = Get-LocText 'Helper_PickPath_FavoritesEditTitle' 'Edit favorite'
    $deleteMessageFormat = Get-LocText 'Helper_PickPath_FavoritesDeleteConfirm' "Delete the favorite '%1'?"

    $getUnifiedFavoritesInvoker = ${function:Get-UnifiedFavorites}
    $readUserFavoritesInvoker = ${function:Read-UserFavorites}
    $writeUserFavoritesInvoker = ${function:Write-UserFavorites}
    $newFavoriteEntryInvoker = ${function:New-FavoriteEntry}
    $showFavoriteEditDialogInvoker = ${function:Show-FavoriteEditDialog}
    $getCurrentSelectedItemActionInvoker = ${function:Get-CurrentSelectedItemAction}
    $writeEditorPickerDebugLogInvoker = ${function:Write-EditorPickerDebugLog}
    $showEditorPickerDebugErrorInvoker = ${function:Show-EditorPickerDebugError}
    $getUserFavoritesCountForDebug = {
        try {
            return @(& $readUserFavoritesInvoker).Count
        }
        catch {
            return $null
        }
    }.GetNewClosure()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $favoriteTitle
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(452, 326)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.DisplayMember = 'Label'
    $listBox.ValueMember = 'Action'
    $listBox.Bounds = New-Object System.Drawing.Rectangle(12, 12, 428, 224)
    $listBox.IntegralHeight = $false

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.AutoSize = $false
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $statusLabel.Bounds = New-Object System.Drawing.Rectangle(12, 242, 428, 18)

    $buttonAdd = New-Object System.Windows.Forms.Button
    $buttonAdd.Text = $addText
    $buttonAdd.Bounds = New-Object System.Drawing.Rectangle(12, 274, 74, 28)

    $buttonEdit = New-Object System.Windows.Forms.Button
    $buttonEdit.Text = $editText
    $buttonEdit.Bounds = New-Object System.Drawing.Rectangle(94, 274, 74, 28)

    $buttonDelete = New-Object System.Windows.Forms.Button
    $buttonDelete.Text = $deleteText
    $buttonDelete.Bounds = New-Object System.Drawing.Rectangle(176, 274, 74, 28)

    $buttonOk = New-Object System.Windows.Forms.Button
    $buttonOk.Text = $okText
    $buttonOk.Bounds = New-Object System.Drawing.Rectangle(284, 274, 74, 28)
    $buttonOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = $closeText
    $buttonClose.Bounds = New-Object System.Drawing.Rectangle(366, 274, 74, 28)
    $buttonClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialogState = [pscustomobject]@{
        FavoriteTitle = $favoriteTitle
        ReadOnlyText = $readOnlyText
        AddTitle = $addTitle
        EditTitle = $editTitle
        DeleteMessageFormat = $deleteMessageFormat
        Form = $form
        ListBox = $listBox
        StatusLabel = $statusLabel
        ButtonOk = $buttonOk
        ButtonEdit = $buttonEdit
        ButtonDelete = $buttonDelete
        RefreshList = $null
        UpdateButtons = $null
    }

    $dialogState.UpdateButtons = {
        $selected = $dialogState.ListBox.SelectedItem
        $hasSelection = $null -ne $selected
        $dialogState.ButtonOk.Enabled = $hasSelection
        $canEdit = $hasSelection -and (-not [bool]$selected.IsBuiltIn)
        $dialogState.ButtonEdit.Enabled = $canEdit
        $dialogState.ButtonDelete.Enabled = $canEdit

        if (-not $hasSelection) {
            $dialogState.StatusLabel.Text = ''
        }
        elseif ([bool]$selected.IsBuiltIn) {
            $dialogState.StatusLabel.Text = [string]$dialogState.ReadOnlyText
        }
        else {
            $dialogState.StatusLabel.Text = ''
        }
    }.GetNewClosure()

    $dialogState.RefreshList = {
        param($SelectionHint)

        $dialogState.ListBox.BeginUpdate()
        $dialogState.ListBox.Items.Clear()

        foreach ($favorite in @(& $getUnifiedFavoritesInvoker)) {
            [void]$dialogState.ListBox.Items.Add($favorite)
        }

        $selectedIndex = -1
        if ($null -ne $SelectionHint) {
            for ($index = 0; $index -lt $dialogState.ListBox.Items.Count; $index++) {
                $candidate = $dialogState.ListBox.Items[$index]
                if ([bool]$SelectionHint.IsBuiltIn -eq [bool]$candidate.IsBuiltIn) {
                    if ([bool]$candidate.IsBuiltIn) {
                        if ([string]$candidate.Action -eq [string]$SelectionHint.Action -and [string]$candidate.Label -eq [string]$SelectionHint.Label) {
                            $selectedIndex = $index
                            break
                        }
                    }
                    elseif ([int]$candidate.UserIndex -eq [int]$SelectionHint.UserIndex) {
                        $selectedIndex = $index
                        break
                    }
                }
            }
        }

        if ($selectedIndex -lt 0 -and $dialogState.ListBox.Items.Count -gt 0) {
            $selectedIndex = 0
        }

        if ($selectedIndex -ge 0) {
            $dialogState.ListBox.SelectedIndex = $selectedIndex
        }

        $dialogState.ListBox.EndUpdate()
        & $dialogState.UpdateButtons
    }.GetNewClosure()

    $buttonAdd.Add_Click({
        try {
            $currentItemAction = & $getCurrentSelectedItemActionInvoker
            $editResult = & $showFavoriteEditDialogInvoker -Owner $dialogState.Form -Title ([string]$dialogState.AddTitle) -InitialLabel '' -InitialAction '' -CurrentItemAction $currentItemAction
            if ($null -eq $editResult) {
                return
            }

            $userFavorites = New-Object System.Collections.Generic.List[object]
            foreach ($entry in @(& $readUserFavoritesInvoker)) {
                $userFavorites.Add($entry)
            }
            $newEntry = & $newFavoriteEntryInvoker -Label $editResult.Label -Action $editResult.Action -IsBuiltIn $false -UserIndex $userFavorites.Count
            $userFavorites.Add($newEntry)
            & $writeUserFavoritesInvoker $userFavorites
            & $dialogState.RefreshList $newEntry
        }
        catch {
            $selected = $dialogState.ListBox.SelectedItem
            $logPath = & $writeEditorPickerDebugLogInvoker -Context 'Show-FavoriteDialog.Add' -ErrorRecord $_ -State @{
                CurrentItemAction = & $getCurrentSelectedItemActionInvoker
                ListCount = $dialogState.ListBox.Items.Count
                SelectedAction = if ($null -ne $selected) { [string]$selected.Action } else { $null }
                SelectedIndex = $dialogState.ListBox.SelectedIndex
                SelectedIsBuiltIn = if ($null -ne $selected) { [bool]$selected.IsBuiltIn } else { $null }
                SelectedLabel = if ($null -ne $selected) { [string]$selected.Label } else { $null }
                UserFavoritesCount = & $getUserFavoritesCountForDebug
            }
            & $showEditorPickerDebugErrorInvoker -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $buttonEdit.Add_Click({
        try {
            $selected = $dialogState.ListBox.SelectedItem
            if ($null -eq $selected -or [bool]$selected.IsBuiltIn) {
                return
            }

            $currentItemAction = & $getCurrentSelectedItemActionInvoker
            $editResult = & $showFavoriteEditDialogInvoker -Owner $dialogState.Form -Title ([string]$dialogState.EditTitle) -InitialLabel ([string]$selected.Label) -InitialAction ([string]$selected.Action) -CurrentItemAction $currentItemAction
            if ($null -eq $editResult) {
                return
            }

            $userFavorites = New-Object System.Collections.Generic.List[object]
            foreach ($entry in @(& $readUserFavoritesInvoker)) {
                $userFavorites.Add($entry)
            }
            $userIndex = [int]$selected.UserIndex
            if ($userIndex -lt 0 -or $userIndex -ge $userFavorites.Count) {
                return
            }

            $updatedEntry = & $newFavoriteEntryInvoker -Label $editResult.Label -Action $editResult.Action -IsBuiltIn $false -UserIndex $userIndex
            $userFavorites[$userIndex] = $updatedEntry
            & $writeUserFavoritesInvoker $userFavorites
            & $dialogState.RefreshList $updatedEntry
        }
        catch {
            $selected = $dialogState.ListBox.SelectedItem
            $logPath = & $writeEditorPickerDebugLogInvoker -Context 'Show-FavoriteDialog.Edit' -ErrorRecord $_ -State @{
                CurrentItemAction = & $getCurrentSelectedItemActionInvoker
                ListCount = $dialogState.ListBox.Items.Count
                SelectedAction = if ($null -ne $selected) { [string]$selected.Action } else { $null }
                SelectedIndex = $dialogState.ListBox.SelectedIndex
                SelectedIsBuiltIn = if ($null -ne $selected) { [bool]$selected.IsBuiltIn } else { $null }
                SelectedLabel = if ($null -ne $selected) { [string]$selected.Label } else { $null }
                SelectedUserIndex = if ($null -ne $selected) { [int]$selected.UserIndex } else { $null }
                UserFavoritesCount = & $getUserFavoritesCountForDebug
            }
            & $showEditorPickerDebugErrorInvoker -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $buttonDelete.Add_Click({
        try {
            $selected = $dialogState.ListBox.SelectedItem
            if ($null -eq $selected -or [bool]$selected.IsBuiltIn) {
                return
            }

            $deleteMessage = ([string]$dialogState.DeleteMessageFormat).Replace('%1', [string]$selected.Label)
            $confirmed = [System.Windows.Forms.MessageBox]::Show($dialogState.Form, $deleteMessage, [string]$dialogState.FavoriteTitle, [System.Windows.Forms.MessageBoxButtons]::OKCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($confirmed -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            $userFavorites = New-Object System.Collections.Generic.List[object]
            foreach ($entry in @(& $readUserFavoritesInvoker)) {
                $userFavorites.Add($entry)
            }
            $userIndex = [int]$selected.UserIndex
            if ($userIndex -lt 0 -or $userIndex -ge $userFavorites.Count) {
                return
            }

            $userFavorites.RemoveAt($userIndex)
            & $writeUserFavoritesInvoker $userFavorites

            $nextIndex = [Math]::Min($userIndex, $userFavorites.Count - 1)
            if ($nextIndex -lt 0) {
                & $dialogState.RefreshList $null
            }
            else {
                & $dialogState.RefreshList (& $newFavoriteEntryInvoker -Label $userFavorites[$nextIndex].Label -Action $userFavorites[$nextIndex].Action -IsBuiltIn $false -UserIndex $nextIndex)
            }
        }
        catch {
            $selected = $dialogState.ListBox.SelectedItem
            $logPath = & $writeEditorPickerDebugLogInvoker -Context 'Show-FavoriteDialog.Delete' -ErrorRecord $_ -State @{
                CurrentItemAction = & $getCurrentSelectedItemActionInvoker
                ListCount = $dialogState.ListBox.Items.Count
                SelectedAction = if ($null -ne $selected) { [string]$selected.Action } else { $null }
                SelectedIndex = $dialogState.ListBox.SelectedIndex
                SelectedIsBuiltIn = if ($null -ne $selected) { [bool]$selected.IsBuiltIn } else { $null }
                SelectedLabel = if ($null -ne $selected) { [string]$selected.Label } else { $null }
                SelectedUserIndex = if ($null -ne $selected) { [int]$selected.UserIndex } else { $null }
                UserFavoritesCount = & $getUserFavoritesCountForDebug
            }
            & $showEditorPickerDebugErrorInvoker -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $listBox.Add_SelectedIndexChanged({
        try {
            & $dialogState.UpdateButtons
        }
        catch {
            $selected = $dialogState.ListBox.SelectedItem
            $logPath = & $writeEditorPickerDebugLogInvoker -Context 'Show-FavoriteDialog.SelectionChanged' -ErrorRecord $_ -State @{
                ListCount = $dialogState.ListBox.Items.Count
                SelectedAction = if ($null -ne $selected) { [string]$selected.Action } else { $null }
                SelectedIndex = $dialogState.ListBox.SelectedIndex
                SelectedIsBuiltIn = if ($null -ne $selected) { [bool]$selected.IsBuiltIn } else { $null }
                SelectedLabel = if ($null -ne $selected) { [string]$selected.Label } else { $null }
            }
            & $showEditorPickerDebugErrorInvoker -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $listBox.Add_DoubleClick({
        try {
            if ($null -ne $dialogState.ListBox.SelectedItem) {
                $dialogState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $dialogState.Form.Close()
            }
        }
        catch {
            $selected = $dialogState.ListBox.SelectedItem
            $logPath = & $writeEditorPickerDebugLogInvoker -Context 'Show-FavoriteDialog.DoubleClick' -ErrorRecord $_ -State @{
                ListCount = $dialogState.ListBox.Items.Count
                SelectedAction = if ($null -ne $selected) { [string]$selected.Action } else { $null }
                SelectedIndex = $dialogState.ListBox.SelectedIndex
                SelectedIsBuiltIn = if ($null -ne $selected) { [bool]$selected.IsBuiltIn } else { $null }
                SelectedLabel = if ($null -ne $selected) { [string]$selected.Label } else { $null }
            }
            & $showEditorPickerDebugErrorInvoker -Owner $dialogState.Form -LogPath $logPath
        }
    }.GetNewClosure())

    $form.Controls.Add($listBox)
    $form.Controls.Add($statusLabel)
    $form.Controls.Add($buttonAdd)
    $form.Controls.Add($buttonEdit)
    $form.Controls.Add($buttonDelete)
    $form.Controls.Add($buttonOk)
    $form.Controls.Add($buttonClose)
    $form.AcceptButton = $buttonOk
    $form.CancelButton = $buttonClose

    & $dialogState.RefreshList $null

    if ($form.ShowDialog($Owner) -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedItem) {
        $selected = $listBox.SelectedItem
        $resultLabel = [string](Get-ObjectPropertyValue $selected 'ResultLabel')
        if ([string]::IsNullOrWhiteSpace($resultLabel)) {
            $resultLabel = [string]$selected.Label
        }
        Write-ProgramActionLabel -Action ([string]$selected.Action) -Label $resultLabel
        $form.Dispose()
        return [PSCustomObject]@{
            Action = [string]$selected.Action
            Label = [string]$selected.Label
            ResultLabel = $resultLabel
        }
    }

    $form.Dispose()
    return $null
}
