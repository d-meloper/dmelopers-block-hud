[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$InitialDirectory = ''
)

try {

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
. (Join-Path $PSScriptRoot 'ImageImportHelpers.ps1')
. (Join-Path $PSScriptRoot '..\..\Utilities\tools\Localization.Common.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$skinRoot = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
$languageCode = Read-LanguageCode -SkinRoot $skinRoot
$locTable = Read-LocaleTable -SkinRoot $skinRoot -LanguageCode $languageCode

function L([string]$Key, [string]$Fallback = '') {
    return Get-LocalizedText -Table $locTable -Key $Key -Fallback $Fallback
}

function LF([string]$Key, [string[]]$Arguments, [string]$Fallback = '') {
    return Format-LocalizedText -Table $locTable -Key $Key -Arguments $Arguments -Fallback $Fallback
}

function New-EditorImagePickerDialogState {
    param(
        [AllowEmptyString()]
        [string]$ResolvedInitialDirectory = ''
    )

    $dialog = $null
    $ownerForm = $null
    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = L 'Helper_PickImage_Title' 'Select an item image'
        $dialog.Filter = (L 'Helper_PickImage_FilterLabel' 'Image Files') + ' (*.png;*.jpg;*.jpeg;*.jpe;*.bmp;*.gif;*.tif;*.tiff;*.ico;*.jxr;*.wdp;*.dds)|*.png;*.jpg;*.jpeg;*.jpe;*.bmp;*.gif;*.tif;*.tiff;*.ico;*.jxr;*.wdp;*.dds'
        $dialog.FilterIndex = 1
        $dialog.Multiselect = $false
        $dialog.CheckFileExists = $true
        $dialog.RestoreDirectory = $true

        if (-not [string]::IsNullOrEmpty($ResolvedInitialDirectory) -and [System.IO.Directory]::Exists($ResolvedInitialDirectory)) {
            $dialog.InitialDirectory = [System.IO.Path]::GetFullPath($ResolvedInitialDirectory)
        }
        else {
            $picturesPath = [Environment]::GetFolderPath('MyPictures')
            if (-not [string]::IsNullOrEmpty($picturesPath) -and [System.IO.Directory]::Exists($picturesPath)) {
                $dialog.InitialDirectory = $picturesPath
            }
        }

        $ownerForm = New-Object System.Windows.Forms.Form
        $ownerForm.ShowInTaskbar = $false
        $ownerForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $ownerForm.Location = New-Object System.Drawing.Point(-32000, -32000)
        $ownerForm.Size = New-Object System.Drawing.Size(1, 1)
        $ownerForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
        $ownerForm.Opacity = 0
        $ownerForm.TopMost = $true
        $ownerForm.Add_Shown({
            $ownerForm.TopMost = $true
            $ownerForm.BringToFront()
            $ownerForm.Activate()
        })
        $ownerForm.Show()
        $ownerForm.BringToFront()
        $ownerForm.Activate()

        return [PSCustomObject]@{
            Dialog = $dialog
            OwnerForm = $ownerForm
        }
    }
    catch {
        if ($null -ne $dialog) {
            $dialog.Dispose()
        }
        if ($null -ne $ownerForm) {
            $ownerForm.Dispose()
        }
        throw
    }
}

$resultPairs = [ordered]@{
    DMEL_STATUS = ''
    DMEL_IMAGEPATH = ''
    DMEL_ITEMIMAGEASSETS = ''
    DMEL_LOGPATH = ''
    DMEL_MESSAGE = ''
    DMEL_ITEMIMAGEATLASPROFILES = ''
}

function Set-ResultPairValue {
    param(
        [string]$Key,
        [AllowNull()][string]$Value
    )

    $resultPairs[$Key] = if ($null -eq $Value) { '' } else { [string]$Value }
}

function Convert-ResultPairValueToSingleLine {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $singleLine = [string]$Value
    $singleLine = $singleLine.Replace("`r", ' ').Replace("`n", ' ')
    while ($singleLine.Contains('  ')) {
        $singleLine = $singleLine.Replace('  ', ' ')
    }

    return $singleLine.Trim()
}

function Emit-ResultPairs {
    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    try {
        $stdout.AutoFlush = $true
        foreach ($key in @('DMEL_STATUS', 'DMEL_IMAGEPATH', 'DMEL_ITEMIMAGEASSETS', 'DMEL_LOGPATH', 'DMEL_MESSAGE', 'DMEL_ITEMIMAGEATLASPROFILES')) {
            $stdout.WriteLine($key + '=' + (Convert-ResultPairValueToSingleLine -Value $resultPairs[$key]))
        }
    }
    finally {
        $stdout.Dispose()
    }
}

function Emit-ErrorResult {
    param(
        [string]$Message,
        [string]$LogPath = ''
    )

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
    Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value $LogPath
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $Message
    Emit-ResultPairs
}

function Get-EditorPickerDebugLogPath {
    return Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
}

function Write-EditorPickerDebugLog(
    [string]$Context,
    [System.Management.Automation.ErrorRecord]$ErrorRecord,
    [hashtable]$State
) {
    $logPath = Get-EditorPickerDebugLogPath
    $logDirectory = [System.IO.Path]::GetDirectoryName($logPath)
    if (-not [System.IO.Directory]::Exists($logDirectory)) {
        [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('=== Editor Picker Debug Entry ===')
    [void]$builder.AppendLine('Timestamp: ' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))
    [void]$builder.AppendLine('Context: ' + [string]$Context)
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception) {
        [void]$builder.AppendLine('ExceptionType: ' + [string]$ErrorRecord.Exception.GetType().FullName)
        [void]$builder.AppendLine('ExceptionMessage: ' + [string]$ErrorRecord.Exception.Message)
        if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.ScriptStackTrace)) {
            [void]$builder.AppendLine('ScriptStackTrace:')
            [void]$builder.AppendLine([string]$ErrorRecord.ScriptStackTrace)
        }
    }
    if ($null -ne $State) {
        [void]$builder.AppendLine('State:')
        foreach ($key in ($State.Keys | Sort-Object)) {
            [void]$builder.AppendLine(('  {0}: {1}' -f [string]$key, [string]$State[$key]))
        }
    }
    [void]$builder.AppendLine()
    [void](Write-BlockHudCanonicalLogBlock -Path $logPath -Type 'EditorPicker' -Lines @($builder.ToString().TrimEnd()) -Encoding $utf8NoBom)
    return $logPath
}

$dialogState = New-EditorImagePickerDialogState -ResolvedInitialDirectory $InitialDirectory
$dialog = $dialogState.Dialog
$ownerForm = $dialogState.OwnerForm

try {
if ($dialog.ShowDialog($ownerForm) -eq [System.Windows.Forms.DialogResult]::OK) {
    $resolvedItemImageDirectory = $dialog.InitialDirectory
    if ([string]::IsNullOrEmpty($resolvedItemImageDirectory)) {
        $resolvedItemImageDirectory = $InitialDirectory
    }

    if ([string]::IsNullOrEmpty($resolvedItemImageDirectory) -or -not [System.IO.Directory]::Exists($resolvedItemImageDirectory)) {
        Emit-ErrorResult -Message (L 'Helper_PickImage_InvalidDirectory' 'Image picker could not resolve a valid item image directory.')
        return
    }

    $itemImageDirectory = [System.IO.Path]::GetFullPath($resolvedItemImageDirectory)
    $selectedPath = [System.IO.Path]::GetFullPath($dialog.FileName)

    if (-not (Test-SupportedImageExtension $selectedPath)) {
        Emit-ErrorResult -Message (LF 'Helper_PickImage_UnsupportedType' @([string]$selectedPath) 'Selected file is not a supported image type: %1')
        return
    }

    try {
        $importResult = Import-EditorItemImageFromFileDetailed -SourcePath $selectedPath -ItemImageDirectory $itemImageDirectory
    }
    catch {
        $logPath = Write-EditorPickerDebugLog -Context 'PickImage.Import' -ErrorRecord $_ -State @{
            InitialDirectory = $InitialDirectory
            ItemImageDirectory = $itemImageDirectory
            SelectedPath = $selectedPath
            ScriptPath = $PSCommandPath
        }
        $failureReason = Get-EditorImageImportFailureMessage `
            -Operation 'processing the selected image' `
            -TargetPath $selectedPath `
            -Exception $_.Exception
        Emit-ErrorResult `
            -Message (LF 'Helper_PickImage_ImportFailed' @([string]$failureReason) 'Selected image could not be imported: %1') `
            -LogPath ([string]$logPath)
        return
    }
    if ($null -eq $importResult -or [string]::IsNullOrWhiteSpace([string]$importResult.FinalPath)) {
        Emit-ErrorResult -Message (LF 'Helper_PickImage_ImportFailed' @([string]$selectedPath) 'Selected image could not be imported: %1')
        return
    }

    Set-ResultPairValue -Key 'DMEL_STATUS' -Value ([string]$importResult.Status)
    Set-ResultPairValue -Key 'DMEL_IMAGEPATH' -Value ([string]$importResult.FinalPath)
    Set-ResultPairValue -Key 'DMEL_ITEMIMAGEASSETS' -Value ([string]$importResult.ItemImageAssets)
    Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value ([string]$importResult.WarningMessage)
    Set-ResultPairValue -Key 'DMEL_ITEMIMAGEATLASPROFILES' -Value ([string]$importResult.ItemImageAtlasProfiles)
    Emit-ResultPairs
}
}
finally {
    $dialog.Dispose()
    $ownerForm.Dispose()
}
}
catch {
    $reportedToRainmeter = $false
    try {
        $logPath = Write-EditorPickerDebugLog -Context 'PickImage.TopLevel' -ErrorRecord $_ -State @{
            InitialDirectory = $InitialDirectory
            ScriptPath = $PSCommandPath
        }
        $failureMessage = L 'Helper_PickImage_UnexpectedResult' 'Image picker failed. Check the helper log for details.'
        if ($null -ne $_.Exception -and -not [string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) {
            $failureMessage = $failureMessage + ' ' + ([string]$_.Exception.Message).Trim()
        }
        Set-ResultPairValue -Key 'DMEL_STATUS' -Value 'ERROR'
        Set-ResultPairValue -Key 'DMEL_LOGPATH' -Value ([string]$logPath)
        Set-ResultPairValue -Key 'DMEL_MESSAGE' -Value $failureMessage
        Emit-ResultPairs
        $reportedToRainmeter = $true
    }
    catch {
    }
    if (-not $reportedToRainmeter) {
        try {
            $message = LF 'Helper_PickImage_ErrorMessage' @([string]$logPath) ('Image picker failed. A debug log was written to:' + [Environment]::NewLine + $logPath)
            $title = L 'Helper_PickImage_ErrorTitle' 'Editor Image Picker Error'
            [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        catch {
        }
    }
    exit 0
}
