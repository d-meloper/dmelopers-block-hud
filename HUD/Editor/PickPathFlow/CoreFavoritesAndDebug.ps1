# Editor PickPathFlow helpers - Localization result paths and favorites

# Dot-sourced by the public entrypoint. Keep public CLI contracts in the entrypoint file.

function Get-PickPathFlowScriptValue([string]$Name) {
    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $variable -or $null -eq $variable.Value) {
        return ''
    }

    return [string]$variable.Value
}

function Get-PickPathFlowSkinRoot() {
    $skinRoot = Get-PickPathFlowScriptValue -Name 'PickPathFlowSkinRoot'
    if (-not [string]::IsNullOrWhiteSpace($skinRoot)) {
        return [System.IO.Path]::GetFullPath($skinRoot)
    }

    $entrypointRoot = Get-PickPathFlowScriptValue -Name 'PickPathFlowEntrypointRoot'
    if (-not [string]::IsNullOrWhiteSpace($entrypointRoot)) {
        if (Get-Command Resolve-BlockHudSkinRoot -ErrorAction SilentlyContinue) {
            return Resolve-BlockHudSkinRoot -StartPath $entrypointRoot
        }
        return [System.IO.Path]::GetFullPath((Join-Path $entrypointRoot '..\..'))
    }

    if (Get-Command Resolve-BlockHudSkinRoot -ErrorAction SilentlyContinue) {
        return Resolve-BlockHudSkinRoot -StartPath $PSScriptRoot
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
}

function Join-PickPathFlowSkinPath([string]$RelativePath) {
    return [System.IO.Path]::GetFullPath((Join-Path (Get-PickPathFlowSkinRoot) $RelativePath))
}

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

function Write-PickerResult([string]$Action, [string]$ImageKey = '', [string]$ItemImageAssets = '', [string]$Label = '', [string]$ActionType = '') {
    if ([string]::IsNullOrEmpty($Action)) {
        return
    }

    $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8NoBom)
    $stdout.AutoFlush = $true

    try {
        $hasImageKey = [string]::IsNullOrEmpty($ImageKey) -eq $false
        $hasItemImageAssets = [string]::IsNullOrEmpty($ItemImageAssets) -eq $false
        $hasLabel = [string]::IsNullOrWhiteSpace($Label) -eq $false

        if ($hasImageKey -or $hasItemImageAssets -or $hasLabel -or [string]::IsNullOrEmpty($ActionType) -eq $false) {
            $stdout.Write('DMEL_ACTION=' + $Action + "`n")
            $stdout.Write('DMEL_ACTIONTYPE=' + $ActionType + "`n")
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
    return Join-PickPathFlowSkinPath -RelativePath '@Resources\Customs\Data\EditorProgramPickerCache.txt'
}

function Get-ProgramActionLabelRegistryPath() {
    return Join-PickPathFlowSkinPath -RelativePath '@Resources\Customs\Data\ProgramActionLabels.txt'
}

function Get-FavoritesCatalogPath() {
    return Join-PickPathFlowSkinPath -RelativePath '@Resources\Customs\Data\EditorFavoritesCatalog.txt'
}

function Get-EditorPickerDebugLogPath() {
    return Get-BlockHudCanonicalLogPath -Root (Get-PickPathFlowSkinRoot)
}

function Get-EditorDraftPath() {
    return Join-PickPathFlowSkinPath -RelativePath '@Resources\Customs\Data\EditorDraft.inc'
}

function Get-EditorItemImageDirectory() {
    return Join-PickPathFlowSkinPath -RelativePath '@Resources\Customs\Images\Items'
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
