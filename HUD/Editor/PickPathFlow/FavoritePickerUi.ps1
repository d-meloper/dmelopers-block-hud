# Editor PickPathFlow helpers - Image import and favorite picker UI

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

$script:AppPickerShellApplication = $null
$script:AppPickerShellFolder = $null
$script:AppPickerIconSourceCache = @{}

function Close-AppPickerIconResolver {
    $script:AppPickerIconSourceCache = @{}

    foreach ($comObject in @($script:AppPickerShellFolder, $script:AppPickerShellApplication)) {
        if ($null -ne $comObject -and [System.Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
            try {
                [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
            catch {
            }
        }
    }

    $script:AppPickerShellFolder = $null
    $script:AppPickerShellApplication = $null
}

function Get-AppPickerShellFolder {
    if ($null -ne $script:AppPickerShellFolder) {
        return $script:AppPickerShellFolder
    }

    try {
        $script:AppPickerShellApplication = New-Object -ComObject Shell.Application
        $script:AppPickerShellFolder = $script:AppPickerShellApplication.NameSpace('shell:AppsFolder')
        return $script:AppPickerShellFolder
    }
    catch {
        Close-AppPickerIconResolver
        return $null
    }
}

function Get-AppPickerPackageLogoDescriptor {
    param(
        [string]$AppID,
        [string]$PackageInstallPath
    )

    if ([string]::IsNullOrWhiteSpace($AppID) -or
        [string]::IsNullOrWhiteSpace($PackageInstallPath) -or
        -not [System.IO.Directory]::Exists($PackageInstallPath)) {
        return $null
    }

    $separatorIndex = $AppID.IndexOf('!')
    if ($separatorIndex -lt 0 -or $separatorIndex -ge ($AppID.Length - 1)) {
        return $null
    }

    $manifestPath = [System.IO.Path]::Combine($PackageInstallPath, 'AppxManifest.xml')
    if (-not [System.IO.File]::Exists($manifestPath)) {
        return $null
    }

    try {
        [xml]$manifest = [System.IO.File]::ReadAllText($manifestPath)
        $applicationId = $AppID.Substring($separatorIndex + 1)
        $application = @(
            $manifest.SelectNodes(
                "/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']"
            )
        ) | Where-Object {
            [string]::Equals(
                [string]$_.GetAttribute('Id'),
                $applicationId,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        } | Select-Object -First 1

        if ($null -eq $application) {
            return $null
        }

        $visualElements = @($application.ChildNodes) | Where-Object {
            $_.LocalName -eq 'VisualElements'
        } | Select-Object -First 1

        $logoContracts = @(
            [PSCustomObject]@{ Name = 'Square44x44Logo'; NominalSize = 44 },
            [PSCustomObject]@{ Name = 'Square30x30Logo'; NominalSize = 30 },
            [PSCustomObject]@{ Name = 'SmallLogo'; NominalSize = 30 },
            [PSCustomObject]@{ Name = 'Logo'; NominalSize = 150 },
            [PSCustomObject]@{ Name = 'Square150x150Logo'; NominalSize = 150 }
        )
        foreach ($contract in $logoContracts) {
            foreach ($node in @($visualElements, $application)) {
                if ($null -eq $node -or $null -eq $node.Attributes) {
                    continue
                }
                $attribute = @($node.Attributes) | Where-Object {
                    $_.LocalName -eq $contract.Name
                } | Select-Object -First 1
                $reference = if ($null -ne $attribute) { [string]$attribute.Value } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($reference) -and
                    -not $reference.StartsWith('ms-resource:', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [PSCustomObject]@{
                        PackageInstallPath = [System.IO.Path]::GetFullPath($PackageInstallPath)
                        LogoReference = $reference
                        NominalSize = [int]$contract.NominalSize
                    }
                }
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-AppPickerIconSource([string]$AppID) {
    if ([string]::IsNullOrWhiteSpace($AppID)) {
        return $null
    }

    if ($script:AppPickerIconSourceCache.ContainsKey($AppID)) {
        $cachedSource = $script:AppPickerIconSourceCache[$AppID]
        if ($null -ne $cachedSource -and $cachedSource.Kind -ne 'Unavailable') {
            return $cachedSource
        }
        return $null
    }

    $expandedAppId = [Environment]::ExpandEnvironmentVariables($AppID)
    if ([System.IO.File]::Exists($expandedAppId)) {
        $source = [PSCustomObject]@{
            Kind = 'File'
            Path = [System.IO.Path]::GetFullPath($expandedAppId)
        }
        $script:AppPickerIconSourceCache[$AppID] = $source
        return $source
    }

    $shellFolder = Get-AppPickerShellFolder
    $shellItem = $null
    try {
        if ($null -ne $shellFolder) {
            $shellItem = $shellFolder.ParseName($AppID)
        }
        if ($null -ne $shellItem) {
            $targetPath = [string]$shellItem.ExtendedProperty('System.Link.TargetParsingPath')
            $targetPath = [Environment]::ExpandEnvironmentVariables($targetPath)
            if ([System.IO.File]::Exists($targetPath)) {
                $source = [PSCustomObject]@{
                    Kind = 'File'
                    Path = [System.IO.Path]::GetFullPath($targetPath)
                }
                $script:AppPickerIconSourceCache[$AppID] = $source
                return $source
            }

            $packageInstallPath = [string]$shellItem.ExtendedProperty(
                'System.AppUserModel.PackageInstallPath'
            )
            $packageDescriptor = Get-AppPickerPackageLogoDescriptor `
                -AppID $AppID `
                -PackageInstallPath $packageInstallPath
            if ($null -ne $packageDescriptor) {
                $source = [PSCustomObject]@{
                    Kind = 'Package'
                    PackageInstallPath = [string]$packageDescriptor.PackageInstallPath
                    LogoReference = [string]$packageDescriptor.LogoReference
                    NominalSize = [int]$packageDescriptor.NominalSize
                }
                $script:AppPickerIconSourceCache[$AppID] = $source
                return $source
            }
        }
    }
    catch {
    }
    finally {
        if ($null -ne $shellItem -and [System.Runtime.InteropServices.Marshal]::IsComObject($shellItem)) {
            try {
                [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shellItem)
            }
            catch {
            }
        }
    }

    $script:AppPickerIconSourceCache[$AppID] = [PSCustomObject]@{ Kind = 'Unavailable' }
    return $null
}

function Get-AppPickerPackageLogoPath {
    param(
        $Source,
        [int]$Size
    )

    if ($null -eq $Source -or $Source.Kind -ne 'Package') {
        return $null
    }

    try {
        $packageRoot = [System.IO.Path]::GetFullPath([string]$Source.PackageInstallPath)
        $relativeLogoPath = ([string]$Source.LogoReference).Replace('/', '\').TrimStart('\')
        $unqualifiedPath = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine($packageRoot, $relativeLogoPath)
        )
        $rootPrefix = $packageRoot.TrimEnd('\') + '\'
        if (-not $unqualifiedPath.StartsWith(
            $rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $null
        }

        $assetDirectory = [System.IO.Path]::GetDirectoryName($unqualifiedPath)
        if (-not [System.IO.Directory]::Exists($assetDirectory)) {
            return $null
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($unqualifiedPath)
        $extension = [System.IO.Path]::GetExtension($unqualifiedPath)
        if ([string]::IsNullOrWhiteSpace($baseName) -or
            [string]::IsNullOrWhiteSpace($extension)) {
            return $null
        }

        $escapedBaseName = [System.Text.RegularExpressions.Regex]::Escape($baseName)
        $escapedExtension = [System.Text.RegularExpressions.Regex]::Escape($extension)
        $assetNamePattern = '^' + $escapedBaseName +
            '(?:\.(?:targetsize|scale)-[^.]*)?' + $escapedExtension + '$'
        $candidates = New-Object System.Collections.Generic.List[object]
        foreach ($asset in @(Get-ChildItem -LiteralPath $assetDirectory -File -ErrorAction Stop)) {
            if ($asset.Name -notmatch $assetNamePattern) {
                continue
            }

            $qualifierPenalty = 20
            if ($asset.Name -match '_contrast-') {
                $qualifierPenalty = 10000
            }
            elseif ($asset.Name -match '_altform-unplated') {
                $qualifierPenalty = 0
            }
            elseif ($asset.Name -match '_altform-lightunplated') {
                $qualifierPenalty = 2
            }
            elseif ($asset.Name -notmatch '_altform-') {
                $qualifierPenalty = 5
            }

            $score = 5000 + $qualifierPenalty
            if ($asset.Name -match '\.targetsize-(\d+)') {
                $assetSize = [int]$Matches[1]
                $score = ([Math]::Abs($assetSize - $Size) * 10) + $qualifierPenalty
                if ($assetSize -lt $Size) {
                    $score += 1
                }
            }
            elseif ($asset.Name -match '\.scale-(\d+)') {
                $assetSize = [int][Math]::Round(
                    ([int]$Source.NominalSize * [int]$Matches[1]) / 100.0
                )
                $score = 2000 + ([Math]::Abs($assetSize - $Size) * 10) + $qualifierPenalty
                if ($assetSize -lt $Size) {
                    $score += 1
                }
            }
            elseif ([string]::Equals(
                $asset.FullName,
                $unqualifiedPath,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                $score = 4000 + $qualifierPenalty
            }

            $candidates.Add([PSCustomObject]@{
                Path = $asset.FullName
                Score = $score
            })
        }

        $selected = @($candidates | Sort-Object Score, Path | Select-Object -First 1)
        if ($selected.Count -gt 0) {
            return [string]$selected[0].Path
        }
    }
    catch {
        return $null
    }

    return $null
}

function New-AppPickerBitmapFromImagePath {
    param(
        [string]$Path,
        [int]$Size
    )

    $sourceImage = $null
    $bitmap = $null
    $graphics = $null
    try {
        $sourceImage = [System.Drawing.Image]::FromFile($Path)
        $bitmap = New-Object System.Drawing.Bitmap(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $scale = [Math]::Min(
            $Size / [double]$sourceImage.Width,
            $Size / [double]$sourceImage.Height
        )
        $drawWidth = [Math]::Max(1, [int][Math]::Round($sourceImage.Width * $scale))
        $drawHeight = [Math]::Max(1, [int][Math]::Round($sourceImage.Height * $scale))
        $drawX = [int][Math]::Floor(($Size - $drawWidth) / 2.0)
        $drawY = [int][Math]::Floor(($Size - $drawHeight) / 2.0)
        $graphics.DrawImage(
            $sourceImage,
            (New-Object System.Drawing.Rectangle($drawX, $drawY, $drawWidth, $drawHeight))
        )
        return $bitmap
    }
    catch {
        if ($null -ne $bitmap) {
            $bitmap.Dispose()
        }
        return $null
    }
    finally {
        if ($null -ne $graphics) {
            $graphics.Dispose()
        }
        if ($null -ne $sourceImage) {
            $sourceImage.Dispose()
        }
    }
}

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

    $source = Get-AppPickerIconSource -AppID $AppID
    if ($null -eq $source) {
        return $null
    }

    if ($source.Kind -eq 'Package') {
        $logoPath = Get-AppPickerPackageLogoPath -Source $source -Size $Size
        if ([string]::IsNullOrWhiteSpace($logoPath)) {
            return $null
        }
        return New-AppPickerBitmapFromImagePath -Path $logoPath -Size $Size
    }

    $icon = $null
    try {
        $candidate = [string]$source.Path
        if (-not [System.IO.File]::Exists($candidate)) {
            return $null
        }

        if ([string]::Equals(
            [System.IO.Path]::GetExtension($candidate),
            '.ico',
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            $icon = New-Object System.Drawing.Icon($candidate, $Size, $Size)
        }
        else {
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
                [System.IO.Path]::GetFullPath($candidate)
            )
        }
        if ($null -eq $icon) {
            return $null
        }

        $bitmap = $icon.ToBitmap()
        if ($bitmap.Width -eq $Size -and $bitmap.Height -eq $Size) {
            return $bitmap
        }

        try {
            return (New-Object System.Drawing.Bitmap($bitmap, (New-Object System.Drawing.Size($Size, $Size))))
        }
        finally {
            $bitmap.Dispose()
        }
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $icon) {
            $icon.Dispose()
        }
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
    $form.Add_Shown({
        $form.TopMost = $true
        $form.BringToFront()
        $form.Activate()
    })

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
    $form.Add_Shown({
        $form.TopMost = $true
        $form.BringToFront()
        $form.Activate()
    })

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
