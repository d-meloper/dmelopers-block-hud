param(
    [ValidateSet('Auto', 'App', 'Favorite')]
    [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
. (Join-Path $PSScriptRoot '..\tools\Localization.Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$skinRoot = Get-LocalizationSkinRoot -ScriptRoot $PSScriptRoot
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
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName System.Xaml

    if (-not ('ShellAppIconProvider' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
public interface IShellItem
{
}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("BCC18B79-BA16-442F-80C4-8A59C30C463B")]
public interface IShellItemImageFactory
{
    void GetImage(SIZE size, SIIGBF flags, out IntPtr phbm);
}

[StructLayout(LayoutKind.Sequential)]
public struct SIZE
{
    public int cx;
    public int cy;

    public SIZE(int x, int y)
    {
        cx = x;
        cy = y;
    }
}

[Flags]
public enum SIIGBF
{
    ResizeToFit = 0x0,
    BiggerSizeOk = 0x1,
    MemoryOnly = 0x2,
    IconOnly = 0x4,
    ThumbnailOnly = 0x8,
    InCacheOnly = 0x10,
    CropToSquare = 0x20,
    WideGamut = 0x40,
    IconBackground = 0x80,
    ScaleUp = 0x100
}

public static class ShellAppIconProvider
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        string path,
        IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        out IShellItem shellItem);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr hObject);

    private static Bitmap ConvertHBitmapToBitmapPreserveAlpha(IntPtr hBitmap)
    {
        var source = Imaging.CreateBitmapSourceFromHBitmap(
            hBitmap,
            IntPtr.Zero,
            Int32Rect.Empty,
            BitmapSizeOptions.FromEmptyOptions());

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));

        using (var stream = new MemoryStream())
        {
            encoder.Save(stream);
            stream.Position = 0;
            using (var bitmap = new Bitmap(stream))
            {
                return new Bitmap(bitmap);
            }
        }
    }

    public static Bitmap GetBitmap(string path, int size)
    {
        IShellItem shellItem = null;
        IntPtr hBitmap = IntPtr.Zero;

        try
        {
            SHCreateItemFromParsingName(path, IntPtr.Zero, typeof(IShellItem).GUID, out shellItem);
            var factory = (IShellItemImageFactory)shellItem;
            factory.GetImage(new SIZE(size, size), SIIGBF.IconOnly | SIIGBF.BiggerSizeOk, out hBitmap);
            if (hBitmap == IntPtr.Zero)
            {
                throw new InvalidOperationException("Shell icon extraction returned no bitmap.");
            }

            return ConvertHBitmapToBitmapPreserveAlpha(hBitmap);
        }
        finally
        {
            if (hBitmap != IntPtr.Zero)
            {
                DeleteObject(hBitmap);
            }

            if (shellItem != null && Marshal.IsComObject(shellItem))
            {
                Marshal.ReleaseComObject(shellItem);
            }
        }
    }
}
"@ -ReferencedAssemblies 'System.Drawing', 'WindowsBase', 'PresentationCore', 'System.Xaml'
    }

    $script:AppPickerIconSupportLoaded = $true
}.GetNewClosure()

function New-UiText([int[]]$CodePoints) {
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-LocText([string]$Key, [string]$Fallback = '') {
    return Get-LocalizedText -Table $locTable -Key $Key -Fallback $Fallback
}

function Format-LocText([string]$Key, [string[]]$Arguments, [string]$Fallback = '') {
    return Format-LocalizedText -Table $locTable -Key $Key -Arguments $Arguments -Fallback $Fallback
}

function Convert-PickerMetadataValue([string]$Value) {
    return ([string]$Value).Replace("`r", ' ').Replace("`n", ' ')
}

function Write-PickerResult([string]$Action, [string]$ImageKey = '', [string]$ItemImageAssets = '', [string]$Label = '') {
    if ([string]::IsNullOrEmpty($Action)) {
        return
    }

    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    $stdout.AutoFlush = $true

    try {
        $hasImageKey = [string]::IsNullOrEmpty($ImageKey) -eq $false
        $hasItemImageAssets = [string]::IsNullOrEmpty($ItemImageAssets) -eq $false
        $hasLabel = [string]::IsNullOrWhiteSpace($Label) -eq $false

        if ($hasImageKey -or $hasItemImageAssets -or $hasLabel) {
            $stdout.Write('DMEL_ACTION=' + $Action + "`n")
            if ($hasLabel) {
                $stdout.Write('DMEL_LABEL=' + (Convert-PickerMetadataValue $Label) + "`n")
            }
            if ($hasImageKey) {
                $stdout.Write('DMEL_IMAGEKEY=' + $ImageKey + "`n")
            }
            if ($hasItemImageAssets) {
                $stdout.Write('DMEL_ITEMIMAGEASSETS=' + $ItemImageAssets + "`n")
            }
        }
        else {
            $stdout.Write($Action)
        }
    }
    finally {
        $stdout.Dispose()
    }
}

function Get-ProgramPickerCachePath() {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\@Resources\Customs\Data\EditorProgramPickerCache.txt'))
}

function Get-ProgramActionLabelRegistryPath() {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\@Resources\Customs\Data\ProgramActionLabels.txt'))
}

function Get-FavoritesCatalogPath() {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\@Resources\Customs\Data\EditorFavoritesCatalog.txt'))
}

function Get-EditorPickerDebugLogPath() {
    return Get-BlockHudCanonicalLogPath -ScriptRoot $PSScriptRoot
}

function Get-EditorDraftPath() {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\@Resources\Customs\Data\EditorDraft.inc'))
}

function Get-EditorItemImageDirectory() {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\@Resources\Customs\Images\Items'))
}

function Get-ItemImageAssetsValue() {
    $itemImageDirectory = Get-EditorItemImageDirectory
    if (-not [System.IO.Directory]::Exists($itemImageDirectory)) {
        return ''
    }

    $assets = Get-ChildItem -LiteralPath $itemImageDirectory |
        Where-Object { -not $_.PSIsContainer } |
        Where-Object { Test-SupportedImageExtension $_.FullName } |
        Where-Object { -not [string]::Equals($_.Name, $ReservedRuntimeAssetName, [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object Name |
        ForEach-Object { $_.Name }

    return ($assets -join '|')
}

function Read-TextSmart([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) {
        return ''
    }

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    try {
        return $strictUtf8.GetString($bytes)
    }
    catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Read-TextLinesSmart([string]$Path) {
    $text = Read-TextSmart -Path $Path
    if ([string]::IsNullOrEmpty($text)) {
        return @()
    }

    return @($text -split "`r?`n")
}

function Write-ProgramActionLabel([string]$Action, [string]$Label) {
    $normalizedAction = [string]$Action
    $normalizedLabel = [string]$Label
    if ([string]::IsNullOrWhiteSpace($normalizedAction) -or [string]::IsNullOrWhiteSpace($normalizedLabel)) {
        return
    }

    $registryPath = Get-ProgramActionLabelRegistryPath
    try {
        $registryDirectory = [System.IO.Path]::GetDirectoryName($registryPath)
        if (-not [System.IO.Directory]::Exists($registryDirectory)) {
            [System.IO.Directory]::CreateDirectory($registryDirectory) | Out-Null
        }

        $entries = [ordered]@{}
        if ([System.IO.File]::Exists($registryPath)) {
            foreach ($line in (Read-TextLinesSmart -Path $registryPath)) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                $parts = [string]$line -split "`t", 2
                if ($parts.Length -ne 2) {
                    continue
                }

                $storedAction = [string]$parts[0]
                $storedLabel = [string]$parts[1]
                if ([string]::IsNullOrWhiteSpace($storedAction) -or [string]::IsNullOrWhiteSpace($storedLabel)) {
                    continue
                }

                $entries[$storedAction] = $storedLabel
            }
        }

        $entries[$normalizedAction] = $normalizedLabel.Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($key in $entries.Keys) {
            $lines.Add($key + "`t" + [string]$entries[$key])
        }

        [System.IO.File]::WriteAllLines($registryPath, $lines, $utf8NoBom)
    }
    catch {
        Write-EditorPickerDebugLogBestEffort -Context 'Picker.ProgramActionLabel.Write' -ErrorRecord $_ -State @{
            Action = $normalizedAction
            Label = $normalizedLabel
            RegistryPath = $registryPath
        }
    }
}

function New-FavoriteEntry(
    [string]$Label,
    [string]$Action,
    [bool]$IsBuiltIn,
    [int]$UserIndex,
    [string]$ResultLabel = ''
) {
    $resolvedResultLabel = if ([string]::IsNullOrWhiteSpace($ResultLabel)) { [string]$Label } else { [string]$ResultLabel }
    return [PSCustomObject]@{
        Label = [string]$Label
        Action = [string]$Action
        IsBuiltIn = $IsBuiltIn
        UserIndex = $UserIndex
        ResultLabel = $resolvedResultLabel
    }
}

function Get-BuiltInFavorites() {
    return @(
        (New-FavoriteEntry -Label (Get-LocText 'Editor_Favorite_ThisPC' '내 컴퓨터') -Action 'explorer.exe shell:::{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -IsBuiltIn $true -UserIndex (-1) -ResultLabel '#Loc_Editor_Favorite_ThisPC#'),
        (New-FavoriteEntry -Label (Get-LocText 'Editor_Favorite_RecycleBin' '휴지통') -Action 'explorer.exe shell:::{645FF040-5081-101B-9F08-00AA002F954E}' -IsBuiltIn $true -UserIndex (-1) -ResultLabel '#Loc_Editor_Favorite_RecycleBin#'),
        (New-FavoriteEntry -Label (Get-LocText 'Editor_Favorite_Shutdown' 'Shut down computer') -Action 'shutdown -s -t 0' -IsBuiltIn $true -UserIndex (-1) -ResultLabel '#Loc_Editor_Favorite_Shutdown#'),
        (New-FavoriteEntry -Label (Get-LocText 'Editor_Favorite_Restart' 'Restart computer') -Action 'shutdown -r -t 0' -IsBuiltIn $true -UserIndex (-1) -ResultLabel '#Loc_Editor_Favorite_Restart#'),
        (New-FavoriteEntry -Label (Get-LocText 'Editor_Favorite_Desktop' '바탕화면') -Action 'explorer.exe shell:::{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' -IsBuiltIn $true -UserIndex (-1) -ResultLabel '#Loc_Editor_Favorite_Desktop#'),
        (New-FavoriteEntry -Label (Get-LocText 'Editor_Favorite_Downloads' '다운로드') -Action 'explorer.exe shell:::{374DE290-123F-4565-9164-39C4925E467B}' -IsBuiltIn $true -UserIndex (-1) -ResultLabel '#Loc_Editor_Favorite_Downloads#')
    )
}

function Read-UserFavorites() {
    $catalogPath = Get-FavoritesCatalogPath
    $entries = New-Object System.Collections.Generic.List[object]
    if (-not [System.IO.File]::Exists($catalogPath)) {
        return @()
    }

    try {
        foreach ($line in (Read-TextLinesSmart -Path $catalogPath)) {
            $trimmedLine = [string]$line
            if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
                continue
            }

            if ($trimmedLine.TrimStart().StartsWith('#')) {
                continue
            }

            $parts = $trimmedLine.Split("`t", 2, [System.StringSplitOptions]::None)
            if ($parts.Length -ne 2) {
                continue
            }

            $label = [string]$parts[0]
            $action = [string]$parts[1]
            if ([string]::IsNullOrWhiteSpace($label) -or [string]::IsNullOrWhiteSpace($action)) {
                continue
            }

            $entries.Add((New-FavoriteEntry -Label $label -Action $action -IsBuiltIn $false -UserIndex $entries.Count))
        }
    }
    catch {
        return @()
    }

    return @($entries.ToArray())
}

function Write-UserFavorites($Entries) {
    $catalogPath = Get-FavoritesCatalogPath
    $catalogDirectory = [System.IO.Path]::GetDirectoryName($catalogPath)
    if (-not [System.IO.Directory]::Exists($catalogDirectory)) {
        [System.IO.Directory]::CreateDirectory($catalogDirectory) | Out-Null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# DisplayName<TAB>Action')

    foreach ($entry in $Entries) {
        if ($null -eq $entry) {
            continue
        }

        $label = ([string]$entry.Label).Trim()
        $action = ([string]$entry.Action).Trim()
        if ([string]::IsNullOrWhiteSpace($label) -or [string]::IsNullOrWhiteSpace($action)) {
            continue
        }

        $sanitizedLabel = $label.Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
        $sanitizedAction = $action.Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
        $lines.Add($sanitizedLabel + "`t" + $sanitizedAction)
    }

    [System.IO.File]::WriteAllLines($catalogPath, $lines, $utf8NoBom)
}

function Get-UnifiedFavorites() {
    $favorites = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-BuiltInFavorites)) {
        $favorites.Add($entry)
    }

    foreach ($entry in @(Read-UserFavorites)) {
        $favorites.Add($entry)
    }

    return @($favorites.ToArray())
}

function Get-CurrentSelectedItemAction() {
    $draftPath = Get-EditorDraftPath
    if (-not [System.IO.File]::Exists($draftPath)) {
        return ''
    }

    try {
        $content = [System.IO.File]::ReadAllText($draftPath, [System.Text.Encoding]::Unicode)
        $selectedMatch = [System.Text.RegularExpressions.Regex]::Match($content, '(?m)^EditorDraftMeta_SelectedSection=(.+?)\r?$')
        if (-not $selectedMatch.Success) {
            return ''
        }

        $selectedSection = ([string]$selectedMatch.Groups[1].Value).Trim()
        if ([string]::IsNullOrWhiteSpace($selectedSection)) {
            return ''
        }

        $pattern = '(?m)^EditorDraftItem_' + [System.Text.RegularExpressions.Regex]::Escape($selectedSection) + '_Action=(.*)$'
        $actionMatch = [System.Text.RegularExpressions.Regex]::Match($content, $pattern)
        if (-not $actionMatch.Success) {
            return ''
        }

        return ([string]$actionMatch.Groups[1].Value).Trim()
    }
    catch {
        return ''
    }
}

function Convert-EditorPickerDebugValue($Value) {
    if ($null -eq $Value) {
        return '<null>'
    }

    if ($Value -is [string]) {
        return ([string]$Value).Replace("`r", '\r').Replace("`n", '\n')
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = New-Object System.Collections.Generic.List[string]
        foreach ($key in $Value.Keys) {
            $pairs.Add(([string]$key) + '=' + (Convert-EditorPickerDebugValue $Value[$key]))
        }
        return '{' + ($pairs -join '; ') + '}'
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[string]
        foreach ($item in $Value) {
            $items.Add((Convert-EditorPickerDebugValue $item))
        }
        return '[' + ($items -join ', ') + ']'
    }

    try {
        return [string]$Value
    }
    catch {
        return '<unprintable>'
    }
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
    [void]$builder.AppendLine('=== Favorite Debug Entry ===')
    [void]$builder.AppendLine('Timestamp: ' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))
    [void]$builder.AppendLine('Context: ' + [string]$Context)

    if ($null -ne $ErrorRecord) {
        if ($null -ne $ErrorRecord.Exception) {
            [void]$builder.AppendLine('ExceptionType: ' + [string]$ErrorRecord.Exception.GetType().FullName)
            [void]$builder.AppendLine('ExceptionMessage: ' + [string]$ErrorRecord.Exception.Message)
            if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.Exception.StackTrace)) {
                [void]$builder.AppendLine('ExceptionStackTrace:')
                [void]$builder.AppendLine([string]$ErrorRecord.Exception.StackTrace)
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.ScriptStackTrace)) {
            [void]$builder.AppendLine('ScriptStackTrace:')
            [void]$builder.AppendLine([string]$ErrorRecord.ScriptStackTrace)
        }

        if ($null -ne $ErrorRecord.InvocationInfo) {
            if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.InvocationInfo.InvocationName)) {
                [void]$builder.AppendLine('InvocationName: ' + [string]$ErrorRecord.InvocationInfo.InvocationName)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.InvocationInfo.MyCommand)) {
                [void]$builder.AppendLine('InvocationCommand: ' + [string]$ErrorRecord.InvocationInfo.MyCommand)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.InvocationInfo.ScriptName)) {
                [void]$builder.AppendLine('InvocationScript: ' + [string]$ErrorRecord.InvocationInfo.ScriptName)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.InvocationInfo.PositionMessage)) {
                [void]$builder.AppendLine('InvocationPosition:')
                [void]$builder.AppendLine([string]$ErrorRecord.InvocationInfo.PositionMessage)
            }
        }
    }

    if ($null -ne $State -and $State.Count -gt 0) {
        [void]$builder.AppendLine('State:')
        foreach ($key in ($State.Keys | Sort-Object)) {
            [void]$builder.AppendLine(('  {0}: {1}' -f [string]$key, (Convert-EditorPickerDebugValue $State[$key])))
        }
    }

    [void]$builder.AppendLine()
    [void](Write-BlockHudCanonicalLogBlock -Path $logPath -Type 'EditorPicker' -Lines @($builder.ToString().TrimEnd()) -Encoding $utf8NoBom)
    return $logPath
}

function Write-EditorPickerDebugLogBestEffort(
    [string]$Context,
    [System.Management.Automation.ErrorRecord]$ErrorRecord,
    [hashtable]$State
) {
    try {
        [void](Write-EditorPickerDebugLog -Context $Context -ErrorRecord $ErrorRecord -State $State)
    }
    catch {
    }
}

function Show-EditorPickerDebugError(
    [System.Windows.Forms.IWin32Window]$Owner,
    [string]$LogPath
) {
    $message = Format-LocText 'Helper_PickPath_FavoritesErrorMessage' @([string]$LogPath) ('Favorites action failed. A debug log was written to:' + [Environment]::NewLine + [string]$LogPath)
    [System.Windows.Forms.MessageBox]::Show($Owner, $message, (Get-LocText 'Helper_PickPath_FavoritesErrorTitle' 'Editor Favorites Error'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
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

function Get-ObjectPropertyValue($Value, [string]$Name) {
    if ($null -eq $Value) {
        return $null
    }

    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Resolve-FavoriteSelectionAction($FavoriteSelection) {
    $action = [string](Get-ObjectPropertyValue $FavoriteSelection 'Action')
    if ([string]::IsNullOrWhiteSpace($action) -and $FavoriteSelection -is [string]) {
        $action = [string]$FavoriteSelection
    }

    if ([string]::IsNullOrWhiteSpace($action)) {
        return ''
    }

    $label = [string](Get-ObjectPropertyValue $FavoriteSelection 'ResultLabel')
    if ([string]::IsNullOrWhiteSpace($label)) {
        $label = [string](Get-ObjectPropertyValue $FavoriteSelection 'Label')
    }
    $resolvedAction = Resolve-ShortcutCommandLine $action

    if (-not [string]::IsNullOrWhiteSpace($label)) {
        Write-ProgramActionLabel -Action $action -Label $label
        if (-not [string]::Equals($resolvedAction, $action, [System.StringComparison]::Ordinal)) {
            Write-ProgramActionLabel -Action $resolvedAction -Label $label
        }
    }

    return $resolvedAction
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
    $saveText = Get-LocText 'Helper_PickPath_FavoriteSave' 'Save'
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
    $addText = Get-LocText 'Helper_PickPath_FavoritesAdd' 'Add'
    $editText = Get-LocText 'Helper_PickPath_FavoritesEdit' 'Edit'
    $deleteText = Get-LocText 'Helper_PickPath_FavoritesDelete' 'Delete'
    $okText = Get-LocText 'Helper_PickPath_FavoritesSelect' 'Select'
    $closeText = Get-LocText 'Helper_PickPath_DialogClose' 'Close'
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

function Show-AppDialog([System.Windows.Forms.IWin32Window]$Owner) {
    if (-not $script:AppPickerIconSupportLoaded) {
        . $script:LoadAppPickerIconSupport
    }

    $appTitle = Get-LocText 'Helper_PickPath_AppTitle' 'Choose a program'
    $searchLabelText = Get-LocText 'Helper_PickPath_AppSearch' 'Search'
    $okText = Get-LocText 'Helper_PickPath_AppSelect' 'Select'
    $closeText = Get-LocText 'Helper_PickPath_DialogClose' 'Close'
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
    $loadTimer = New-Object System.Windows.Forms.Timer
    $loadTimer.Interval = 10
    $searchTimer = New-Object System.Windows.Forms.Timer
    $searchTimer.Interval = 100
    $iconTimer = New-Object System.Windows.Forms.Timer
    $iconTimer.Interval = 15
    $cachedEntries = Read-CachedStartAppEntries
    $searchBox.Enabled = $false
    $listView.Enabled = $false
    $getStartAppEntriesInvoker = ${function:Get-StartAppEntries}
    $writeCachedStartAppEntriesInvoker = ${function:Write-CachedStartAppEntries}
    $getAppPickerImageIndexInvoker = ${function:Get-AppPickerImageIndex}
    $dialogState = [pscustomobject]@{
        EnumerationComplete = $false
        EnumerationStarted = $false
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
            $iconTimer.Stop()
            $iconState.DisplayedItemsByAppId = @{}
            $iconState.PendingIconAppIds = New-Object System.Collections.Generic.Queue[string]
            $listView.BeginUpdate()
            $listView.Items.Clear()
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
                $iconState.DisplayedItemsByAppId[$appId] = $item
                if ($imageIndex -eq $fallbackImageIndex) {
                    $iconState.PendingIconAppIds.Enqueue($appId)
                }
            }
            $listView.EndUpdate()
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
            if ($dialogState.EnumerationStarted) {
                return
            }
            $dialogState.EnumerationStarted = $true
            & $updateStatus
            $allApps.Clear()
            $loadedApps = & $getStartAppEntriesInvoker
            & $writeCachedStartAppEntriesInvoker $loadedApps
            foreach ($app in @($loadedApps)) {
                $allApps.Add($app)
            }
            $dialogState.EnumerationComplete = $true
            $searchBox.Enabled = $true
            $listView.Enabled = $true
            & $populateVisibleList
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
    }
}

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
    $closeText = Get-LocText 'Helper_PickPath_DialogClose' 'Close'
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
