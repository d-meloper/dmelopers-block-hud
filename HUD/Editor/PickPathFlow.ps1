param(
    [ValidateSet('Auto', 'App', 'Favorite')]
    [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
. (Join-Path $PSScriptRoot '..\..\Utilities\tools\Localization.Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:PickPathFlowEntrypointRoot = $PSScriptRoot
$skinRoot = Get-LocalizationSkinRoot -ScriptRoot $script:PickPathFlowEntrypointRoot
$script:PickPathFlowSkinRoot = $skinRoot
$languageCode = Read-LanguageCode -SkinRoot $skinRoot
$locTable = Read-LocaleTable -SkinRoot $skinRoot -LanguageCode $languageCode

${script:ImageImportHelpersLoaded} = $false
${script:AppPickerIconSupportLoaded} = $false
$script:ImageImportHelpersPath = Join-Path $PSScriptRoot 'ImageImportHelpers.ps1'
$script:LoadImageImportHelpers = {
    . $script:ImageImportHelpersPath
    $script:ImageImportHelpersLoaded = $true
}.GetNewClosure()
$script:LoadAppPickerIconSupport = {
    Add-Type -AssemblyName System.Drawing
    $script:AppPickerIconSupportLoaded = $true
}.GetNewClosure()

$script:ModuleRoot = Join-Path $PSScriptRoot 'PickPathFlow'
. (Join-Path $script:ModuleRoot 'CoreFavoritesAndDebug.ps1')
. (Join-Path $script:ModuleRoot 'FavoritePickerUi.ps1')
. (Join-Path $script:ModuleRoot 'AppPickerUi.ps1')










































try {
    if ($Mode -eq 'App') {
        $appSelection = Show-AppDialog $null
        if ($null -ne $appSelection) {
            Write-PickerResult -Action ([string]$appSelection.Action) -ImageKey ([string]$appSelection.ImageKey) -ItemImageAssets ([string]$appSelection.ItemImageAssets) -Label ([string]$appSelection.ProgramLabel)
        }
        exit 0
    }

    if ($Mode -eq 'Favorite') {
        $favoriteSelection = Show-FavoriteDialog $null
        $favoriteAction = Resolve-FavoriteSelectionAction $favoriteSelection
        if ([string]::IsNullOrEmpty($favoriteAction) -eq $false) {
            $favoriteResultLabel = [string](Get-ObjectPropertyValue $favoriteSelection 'ResultLabel')
            if ([string]::IsNullOrWhiteSpace($favoriteResultLabel)) {
                $favoriteResultLabel = [string](Get-ObjectPropertyValue $favoriteSelection 'Label')
            }
            Write-PickerResult -Action $favoriteAction -Label $favoriteResultLabel
        }
        exit 0
    }

    $selectedPath = $null
    $selectedImageKey = $null
    $selectedItemImageAssets = $null
    $selectedLabel = $null
    $windowTitle = Get-LocText 'Helper_PickPath_DialogTitle' 'Choose a path'
    $instructionText = Get-LocText 'Helper_PickPath_DialogPrompt' 'Choose a path type.'
    $fileText = Get-LocText 'Helper_PickPath_Type_File' 'File'
    $folderText = Get-LocText 'Helper_PickPath_Type_Folder' 'Folder'
    $appText = Get-LocText 'Helper_PickPath_Type_Program' 'Program'
    $favoriteText = Get-LocText 'Helper_PickPath_Type_Favorite' 'Favorite'
    $closeText = Get-LocText 'Common_Close' 'Close'
    $fileTitle = Get-LocText 'Helper_PickPath_FileTitle' 'Select a file'
    $folderTitle = Get-LocText 'Helper_PickPath_FolderTitle' 'Select a folder'

    $pickerForm = New-Object System.Windows.Forms.Form
    $pickerForm.Text = $windowTitle
    $pickerForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $pickerForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $pickerForm.MinimizeBox = $false
    $pickerForm.MaximizeBox = $false
    $pickerForm.ShowInTaskbar = $false
    $pickerForm.TopMost = $true
    $pickerForm.ClientSize = New-Object System.Drawing.Size(452, 110)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $instructionText
    $label.AutoSize = $false
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.Bounds = New-Object System.Drawing.Rectangle(12, 12, 428, 26)

    $buttonApp = New-Object System.Windows.Forms.Button
    $buttonApp.Text = $appText
    $buttonApp.Bounds = New-Object System.Drawing.Rectangle(12, 56, 80, 28)
    $buttonApp.TabIndex = 0

    $buttonFile = New-Object System.Windows.Forms.Button
    $buttonFile.Text = $fileText
    $buttonFile.Bounds = New-Object System.Drawing.Rectangle(100, 56, 80, 28)
    $buttonFile.TabIndex = 1

    $buttonFolder = New-Object System.Windows.Forms.Button
    $buttonFolder.Text = $folderText
    $buttonFolder.Bounds = New-Object System.Drawing.Rectangle(188, 56, 80, 28)
    $buttonFolder.TabIndex = 2

    $buttonFavorite = New-Object System.Windows.Forms.Button
    $buttonFavorite.Text = $favoriteText
    $buttonFavorite.Bounds = New-Object System.Drawing.Rectangle(276, 56, 80, 28)
    $buttonFavorite.TabIndex = 3

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = $closeText
    $buttonClose.Bounds = New-Object System.Drawing.Rectangle(364, 56, 72, 28)
    $buttonClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttonClose.TabIndex = 4

    $pickerForm.Controls.Add($label)
    $pickerForm.Controls.Add($buttonApp)
    $pickerForm.Controls.Add($buttonFile)
    $pickerForm.Controls.Add($buttonFolder)
    $pickerForm.Controls.Add($buttonFavorite)
    $pickerForm.Controls.Add($buttonClose)
    $pickerForm.AcceptButton = $buttonApp
    $pickerForm.CancelButton = $buttonClose
    $pickerForm.Add_Shown({
        $pickerForm.TopMost = $true
        $pickerForm.BringToFront()
        $pickerForm.Activate()
        $buttonApp.Focus()
    }.GetNewClosure())

    $buttonFile.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $fileTitle
        $dialog.Filter = (Get-LocText 'Helper_PickPath_AllFilesFilterLabel' 'All Files') + '|*.*'
        $dialog.Multiselect = $false
        $dialog.CheckFileExists = $true
        $dialog.RestoreDirectory = $true
        $dialog.DereferenceLinks = $false

        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrEmpty($documentsPath) -eq $false) {
            $dialog.InitialDirectory = $documentsPath
        }

        if ($dialog.ShowDialog($pickerForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $pickerForm.Tag = $dialog.FileName
            $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $pickerForm.Close()
        }
    }.GetNewClosure())

    $buttonFolder.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $folderTitle
        $dialog.ShowNewFolderButton = $false

        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrEmpty($documentsPath) -eq $false) {
            $dialog.SelectedPath = $documentsPath
        }

        if ($dialog.ShowDialog($pickerForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $pickerForm.Tag = $dialog.SelectedPath
            $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $pickerForm.Close()
        }
    }.GetNewClosure())

    $buttonApp.Add_Click({
        $appSelection = Show-AppDialog $pickerForm
        if ($null -ne $appSelection) {
            $pickerForm.Tag = $appSelection
            $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $pickerForm.Close()
        }
    }.GetNewClosure())

    $buttonFavorite.Add_Click({
        try {
            $favoriteSelection = Show-FavoriteDialog $pickerForm
            if ($null -ne $favoriteSelection -and [string]::IsNullOrEmpty([string](Get-ObjectPropertyValue $favoriteSelection 'Action')) -eq $false) {
                $pickerForm.Tag = $favoriteSelection
                $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $pickerForm.Close()
            }
        }
        catch {
            $logPath = Write-EditorPickerDebugLog -Context 'Picker.FavoriteButton' -ErrorRecord $_ -State @{
                CurrentTag = if ($null -ne $pickerForm.Tag) { [string]$pickerForm.Tag } else { $null }
                FavoriteCatalogPath = Get-FavoritesCatalogPath
                FormDialogResult = [string]$pickerForm.DialogResult
            }
            Show-EditorPickerDebugError -Owner $pickerForm -LogPath $logPath
        }
    }.GetNewClosure())

    if ($pickerForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($pickerForm.Tag -is [string]) {
            $selectedPath = Resolve-ShortcutCommandLine ([string]$pickerForm.Tag)
        }
        elseif ($null -ne $pickerForm.Tag) {
            if ($null -ne (Get-ObjectPropertyValue $pickerForm.Tag 'Label')) {
                $selectedPath = Resolve-FavoriteSelectionAction $pickerForm.Tag
                $selectedLabel = [string](Get-ObjectPropertyValue $pickerForm.Tag 'Label')
            }
            else {
                $selectedPath = [string]$pickerForm.Tag.Action
                $selectedImageKey = [string]$pickerForm.Tag.ImageKey
                $selectedItemImageAssets = [string]$pickerForm.Tag.ItemImageAssets
                $selectedLabel = [string]$pickerForm.Tag.ProgramLabel
            }
        }
    }

    $pickerForm.Dispose()

    if ([string]::IsNullOrEmpty($selectedPath) -eq $false) {
        Write-PickerResult -Action $selectedPath -ImageKey $selectedImageKey -ItemImageAssets $selectedItemImageAssets -Label $selectedLabel
    }
}
catch {
    try {
        $logPath = Write-EditorPickerDebugLog -Context 'PickPath.TopLevel' -ErrorRecord $_ -State @{
            InitialDirectory = $InitialDirectory
            ScriptPath = $PSCommandPath
        }
        [System.Windows.Forms.MessageBox]::Show((Format-LocText 'Helper_PickPath_ErrorMessage' @([string]$logPath) ('Path picker failed. A debug log was written to:' + [Environment]::NewLine + $logPath)), (Get-LocText 'Helper_PickPath_ErrorTitle' 'Editor Path Picker Error'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    catch {
    }
    exit 0
}
