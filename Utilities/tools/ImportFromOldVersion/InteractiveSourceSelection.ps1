# ImportFromOldVersion interactive source-selection helpers.
# Loaded only when the caller allows UI and did not provide SourceRoot.

function Select-SourceRootWithDialog {
    param([Parameter(Mandatory = $true)][string]$InitialPath)

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = T 'Helper_Import_FolderPrompt' "Select the older (v1.1.0+) DMeloper's Block HUD folder."
    $dialog.ShowNewFolderButton = $false
    if (Test-Path -LiteralPath $InitialPath -PathType Container) {
        $dialog.SelectedPath = $InitialPath
    }

    $ownerForm = New-Object System.Windows.Forms.Form
    $ownerForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $ownerForm.ShowInTaskbar = $false
    $ownerForm.Size = New-Object System.Drawing.Size(1, 1)
    $ownerForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $ownerForm.Opacity = 0
    $ownerForm.TopMost = $true
    $ownerForm.Add_Shown({
        $ownerForm.TopMost = $true
        $ownerForm.BringToFront()
        $ownerForm.Activate()
    })
    try {
        $ownerForm.Show()
        $ownerForm.BringToFront()
        $ownerForm.Activate()
        $result = $dialog.ShowDialog($ownerForm)
    }
    finally {
        $ownerForm.Close()
        $ownerForm.Dispose()
    }
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        throw (New-Object System.OperationCanceledException (T 'Helper_Import_SelectCanceled' 'The user canceled old-data import.'))
    }

    $selectedDirectory = $dialog.SelectedPath
    if ($null -eq $selectedDirectory) {
        $selectedDirectory = ''
    }
    $selectedDirectory = $selectedDirectory.Trim()
    $selected = Resolve-SourceRootCandidate -Candidate $selectedDirectory
    if (-not $selected) {
        $message = T 'Helper_Import_InvalidFolder' 'The selected folder is not a valid v1.1.0+ skin folder:'
        throw ($message + ' ' + $selectedDirectory)
    }

    return $selected
}

function Confirm-DetectedSourceSelection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DetectedSource,
        [Parameter(Mandatory = $true)]
        [string]$BrowseRoot
    )

    Add-Type -AssemblyName System.Windows.Forms
    $messageLines = @(
        (T 'Helper_Import_ConfirmFound' 'An older (v1.1.0+) skin folder to import was found.'),
        '',
        $DetectedSource,
        '',
        (T 'Helper_Import_ConfirmYes' 'Yes: use this folder'),
        (T 'Helper_Import_ConfirmNo' 'No: choose a different folder'),
        (T 'Helper_Import_ConfirmCancel' 'Cancel: exit without changes')
    )
    $message = [string]::Join([Environment]::NewLine, $messageLines)
    $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        (T 'Helper_Import_ConfirmTitle' 'Old-data import'),
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1
    )

    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "Auto-detected source confirmed: $DetectedSource"
            return [pscustomobject]@{
                Path = $DetectedSource
                Detection = 'auto'
            }
        }
        ([System.Windows.Forms.DialogResult]::No) {
            $selectedSource = Select-SourceRootWithDialog -InitialPath $BrowseRoot
            Write-Log "Source selected after declining auto-detected source: $selectedSource"
            return [pscustomobject]@{
                Path = $selectedSource
                Detection = 'manual'
            }
        }
        default {
            Set-ResultPairValue -Key 'DMEL_SOURCEPATH' -Value $DetectedSource
            throw (New-Object System.OperationCanceledException (T 'Helper_Import_SelectCanceled' 'The user canceled old-data import.'))
        }
    }
}
