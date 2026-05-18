$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot '..\tools\Localization.Common.ps1')

$flowScriptPath = Join-Path $PSScriptRoot 'PickPathFlow.ps1'
$skinRoot = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$languageCode = Read-LanguageCode -SkinRoot $skinRoot
$locTable = Read-LocaleTable -SkinRoot $skinRoot -LanguageCode $languageCode

function L([string]$Key, [string]$Fallback = '') {
    return Get-LocalizedText -Table $locTable -Key $Key -Fallback $Fallback
}

function Get-PickerUiText() {
    $text = [ordered]@{
        WindowTitle         = L 'Helper_PickPath_DialogTitle' 'Choose a path'
        InstructionText     = L 'Helper_PickPath_DialogPrompt' 'Choose a path type.'
        FileText            = L 'Helper_PickPath_Type_File' 'File'
        FolderText          = L 'Helper_PickPath_Type_Folder' 'Folder'
        AppText             = L 'Helper_PickPath_Type_Program' 'Program'
        FavoriteText        = L 'Helper_PickPath_Type_Favorite' 'Favorite'
        CloseText           = L 'Helper_PickPath_DialogClose' 'Close'
        FileTitle           = L 'Helper_PickPath_FileTitle' 'Select a file'
        FolderTitle         = L 'Helper_PickPath_FolderTitle' 'Select a folder'
        AllFilesFilterLabel = L 'Helper_PickPath_AllFilesFilterLabel' 'All Files'
        ErrorTitle          = L 'Helper_PickPath_ErrorTitle' 'Editor Path Picker Error'
    }

    return $text
}

function Join-ShortcutCommandLine([string]$TargetPath, [string]$Arguments) {
    $target = [string]$TargetPath
    $argumentsText = [string]$Arguments

    if ([string]::IsNullOrWhiteSpace($target)) {
        return $null
    }

    $target = $target.Trim()
    $argumentsText = $argumentsText.Trim()

    if ($target.Contains(' ') -and -not ($target.StartsWith('"') -and $target.EndsWith('"'))) {
        $target = '"' + $target + '"'
    }

    if ([string]::IsNullOrWhiteSpace($argumentsText)) {
        return $target
    }

    return $target + ' ' + $argumentsText
}

function Resolve-ShortcutCommandLine([string]$SelectedPath) {
    $resolvedPath = [string]$SelectedPath
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        return $resolvedPath
    }

    if (-not $resolvedPath.EndsWith('.lnk', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath
    }

    $shell = $null
    $shortcut = $null

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($resolvedPath)
        $targetPath = [string]$shortcut.TargetPath
        $arguments = [string]$shortcut.Arguments
        $commandLine = Join-ShortcutCommandLine -TargetPath $targetPath -Arguments $arguments
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            return $resolvedPath
        }

        return $commandLine
    }
    catch {
        return $resolvedPath
    }
    finally {
        if ($shortcut) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        }
        if ($shell) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

function Write-PathResult([string]$SelectedPath) {
    if ([string]::IsNullOrWhiteSpace($SelectedPath)) {
        return
    }

    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    $stdout.AutoFlush = $true

    try {
        $stdout.Write($SelectedPath)
    }
    finally {
        $stdout.Dispose()
    }
}

function Invoke-DeferredPickerMode([string]$Mode) {
    if (-not [System.IO.File]::Exists($flowScriptPath)) {
        throw ('Deferred picker flow script is missing: ' + $flowScriptPath)
    }

    & $flowScriptPath -Mode $Mode
}

try {
    $uiText = Get-PickerUiText
    $windowTitle = [string]$uiText.WindowTitle
    $instructionText = [string]$uiText.InstructionText
    $fileText = [string]$uiText.FileText
    $folderText = [string]$uiText.FolderText
    $appText = [string]$uiText.AppText
    $favoriteText = [string]$uiText.FavoriteText
    $closeText = [string]$uiText.CloseText
    $fileTitle = [string]$uiText.FileTitle
    $folderTitle = [string]$uiText.FolderTitle
    $allFilesFilterLabel = [string]$uiText.AllFilesFilterLabel

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
        $buttonApp.Focus()
    }.GetNewClosure())

    $buttonFile.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $fileTitle
        $dialog.Filter = $allFilesFilterLabel + '|*.*'
        $dialog.Multiselect = $false
        $dialog.CheckFileExists = $true
        $dialog.RestoreDirectory = $true
        $dialog.DereferenceLinks = $false

        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrEmpty($documentsPath) -eq $false) {
            $dialog.InitialDirectory = $documentsPath
        }

        if ($dialog.ShowDialog($pickerForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $pickerForm.Tag = [PSCustomObject]@{
                Kind  = 'Path'
                Value = Resolve-ShortcutCommandLine ([string]$dialog.FileName)
            }
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
            $pickerForm.Tag = [PSCustomObject]@{
                Kind  = 'Path'
                Value = [string]$dialog.SelectedPath
            }
            $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $pickerForm.Close()
        }
    }.GetNewClosure())

    $buttonApp.Add_Click({
        $pickerForm.Tag = [PSCustomObject]@{
            Kind  = 'Deferred'
            Value = 'App'
        }
        $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerForm.Close()
    }.GetNewClosure())

    $buttonFavorite.Add_Click({
        $pickerForm.Tag = [PSCustomObject]@{
            Kind  = 'Deferred'
            Value = 'Favorite'
        }
        $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerForm.Close()
    }.GetNewClosure())

    if ($pickerForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $null -ne $pickerForm.Tag) {
        $selection = $pickerForm.Tag
        $pickerForm.Dispose()

        if ([string]$selection.Kind -eq 'Path') {
            Write-PathResult ([string]$selection.Value)
            return
        }

        Invoke-DeferredPickerMode ([string]$selection.Value)
        return
    }

    $pickerForm.Dispose()
}
catch {
    $errorTitle = 'Editor Path Picker Error'
    $errorMessage = 'Path picker could not be opened. Check the helper files and try again.'
    try {
        $uiText = Get-PickerUiText
        $errorTitle = [string]$uiText.ErrorTitle
        $errorMessage = [string](L 'Helper_PickPath_WrapperError' 'Path picker could not be opened. Check the helper files and try again.')
    }
    catch {
    }
    [System.Windows.Forms.MessageBox]::Show($errorMessage, $errorTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 0
}
