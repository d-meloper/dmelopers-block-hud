$script:DefaultItemLocalizationUtf16LeBom = New-Object System.Text.UnicodeEncoding($false, $true)

function Read-DefaultItemLocalizationUtf16Text {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return ''
    }

    [System.IO.File]::ReadAllText($Path, $script:DefaultItemLocalizationUtf16LeBom)
}

function Write-DefaultItemLocalizationUtf16Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not [System.IO.Directory]::Exists($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, ([string]$Content).TrimStart([char]0xfeff), $script:DefaultItemLocalizationUtf16LeBom)
}

function Read-DefaultItemLocalizationVariables {
    param([Parameter(Mandatory = $true)][string]$Path)

    $variables = [ordered]@{}
    $inVariables = $false
    foreach ($line in ((Read-DefaultItemLocalizationUtf16Text -Path $Path) -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
            $inVariables = $trimmed.Equals('[Variables]', [System.StringComparison]::OrdinalIgnoreCase)
            continue
        }
        if (-not $inVariables -or [string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) {
            continue
        }
        $separator = $line.IndexOf('=')
        if ($separator -lt 0) {
            continue
        }
        $variables[$line.Substring(0, $separator).Trim()] = $line.Substring($separator + 1).TrimEnd("`r")
    }

    $variables
}

function ConvertTo-DefaultItemLocalizationRainmeterContent {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Variables)

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('[Variables]')
    foreach ($key in $Variables.Keys) {
        [void]$lines.Add(('{0}={1}' -f $key, $Variables[$key]))
    }
    [string]::Join("`r`n", $lines) + "`r`n"
}

function Write-DefaultItemLocalizationVariables {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Variables
    )

    Write-DefaultItemLocalizationUtf16Text -Path $Path -Content (ConvertTo-DefaultItemLocalizationRainmeterContent -Variables $Variables)
}

function Get-DefaultItemLocalizationRecords {
    @(
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot01'; Image = 'Computer.png'; Qty = '0'; Action = 'explorer.exe "shell:MyComputerFolder"'; LabelKey = 'Loc_Editor_Favorite_ThisPC'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot02'; Image = 'Trash.png'; Qty = '0'; Action = 'explorer.exe "shell:RecycleBinFolder"'; LabelKey = 'Loc_Editor_Favorite_RecycleBin'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot03'; Image = 'chrome.png'; Qty = '0'; Action = 'https://www.google.com'; LabelKey = 'Loc_DefaultItem_Google'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot04'; Image = 'torch.png'; Qty = '8'; Action = 'explorer.exe shell:::{374DE290-123F-4565-9164-39C4925E467B}'; LabelKey = 'Loc_DefaultItem_DownloadsFolder'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot05'; Image = 'Cooked_Beef.png'; Qty = '4'; Action = 'calc.exe'; LabelKey = 'Loc_DefaultItem_Calculator'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot06'; Image = 'Water_Bucket.png'; Qty = '0'; Action = 'mspaint.exe'; LabelKey = 'Loc_DefaultItem_Paint'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot07'; Image = 'Infested_Cobblestone.png'; Qty = '20'; Action = 'explorer.exe'; LabelKey = 'Loc_DefaultItem_FileExplorer'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot08'; Image = 'Compass.png'; Qty = '0'; Action = 'notepad.exe'; LabelKey = 'Loc_DefaultItem_Notepad'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot09'; Image = 'Potion_Water.png'; Qty = '0'; Action = 'https://litt.ly/dmeloper'; LabelKey = 'Loc_DefaultItem_DeveloperLinktree'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Hotbar'; Section = 'Slot10'; Image = 'more.png'; Qty = '0'; Action = '_OPEN_INVENTORY_'; LabelKey = ''; InventoryLabel = $true; AlwaysUpdate = $true }
        [PSCustomObject]@{ DataSet = 'Inventory'; Section = 'SlotX1Y2'; Image = 'Coal.png'; Qty = '6'; Action = 'https://minecraft.wiki/w/Coal'; LabelKey = 'Loc_DefaultItem_Coal'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Inventory'; Section = 'SlotX2Y2'; Image = 'Iron_Ingot.png'; Qty = '32'; Action = 'https://minecraft.wiki/w/Iron_Ingot'; LabelKey = 'Loc_DefaultItem_IronIngot'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Inventory'; Section = 'SlotX3Y2'; Image = 'Gold_Ingot.png'; Qty = '8'; Action = 'https://minecraft.wiki/w/Gold_Ingot'; LabelKey = 'Loc_DefaultItem_GoldIngot'; InventoryLabel = $false; AlwaysUpdate = $false }
        [PSCustomObject]@{ DataSet = 'Inventory'; Section = 'SlotX4Y2'; Image = 'diamond.png'; Qty = '2'; Action = 'https://minecraft.wiki/w/Diamond'; LabelKey = 'Loc_DefaultItem_Diamond'; InventoryLabel = $false; AlwaysUpdate = $false }
    )
}

function Read-DefaultItemLocalizationCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$SkinRoot,
        [Parameter(Mandatory = $true)][string]$LanguageCode
    )

    $path = [System.IO.Path]::Combine($SkinRoot, '@Resources', 'Localization', 'Languages', ($LanguageCode + '.inc'))
    if (-not [System.IO.File]::Exists($path)) {
        throw "Localization catalog is missing: $LanguageCode"
    }

    $strings = [ordered]@{}
    foreach ($line in ((Read-DefaultItemLocalizationUtf16Text -Path $path) -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('[') -or $trimmed.StartsWith(';')) {
            continue
        }
        $parts = $line -split '=', 2
        if ($parts.Length -ne 2) {
            continue
        }
        $key = [string]$parts[0].Trim()
        if ($key.StartsWith('Loc_', [System.StringComparison]::Ordinal)) {
            $strings[$key] = [string]$parts[1]
        }
    }

    $strings
}

function Read-DefaultItemLocalizationRegistry {
    param([Parameter(Mandatory = $true)][string]$SkinRoot)

    $path = [System.IO.Path]::Combine($SkinRoot, '@Resources', 'Localization', 'LanguageRegistry.inc')
    $variables = Read-DefaultItemLocalizationVariables -Path $path
    $fallback = if ($variables.Contains('DefaultFallbackLanguageCode') -and -not [string]::IsNullOrWhiteSpace([string]$variables['DefaultFallbackLanguageCode'])) {
        [string]$variables['DefaultFallbackLanguageCode']
    } else {
        'en-US'
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $count = 0
    [void][int]::TryParse([string]$variables['LanguageCount'], [ref]$count)
    for ($index = 1; $index -le $count; $index++) {
        $prefix = "Language_${index}_"
        $code = if ($variables.Contains("${prefix}Code")) { ([string]$variables["${prefix}Code"]).Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($code)) {
            continue
        }
        [void]$entries.Add([PSCustomObject]@{
            Code = $code
            DisplayName = if ($variables.Contains("${prefix}DisplayName")) { [string]$variables["${prefix}DisplayName"] } else { $code }
            InventoryLabel = if ($variables.Contains("${prefix}InventoryLabel")) { [string]$variables["${prefix}InventoryLabel"] } else { '' }
        })
    }

    [PSCustomObject]@{
        DefaultFallbackLanguageCode = $fallback
        Entries = @($entries.ToArray())
    }
}

function Resolve-DefaultItemLocalizationLanguageCode {
    param(
        [Parameter(Mandatory = $true)][string]$SkinRoot,
        [AllowNull()][string]$LanguageCode
    )

    $registry = Read-DefaultItemLocalizationRegistry -SkinRoot $SkinRoot
    $candidate = ([string]$LanguageCode).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = ([string]$registry.DefaultFallbackLanguageCode).Trim()
    }
    $candidateLower = $candidate.ToLowerInvariant()
    foreach ($entry in @($registry.Entries)) {
        $code = [string]$entry.Code
        if ($candidateLower -eq $code.ToLowerInvariant()) {
            return $code
        }
        $baseAlias = ($code -split '[-_]', 2)[0]
        if (-not [string]::IsNullOrWhiteSpace($baseAlias) -and $candidateLower -eq $baseAlias.ToLowerInvariant()) {
            return $code
        }
        if ($candidateLower -eq ([string]$entry.DisplayName).Trim().ToLowerInvariant()) {
            return $code
        }
    }

    $fallback = ([string]$registry.DefaultFallbackLanguageCode).Trim()
    foreach ($entry in @($registry.Entries)) {
        if ($fallback.ToLowerInvariant() -eq ([string]$entry.Code).ToLowerInvariant()) {
            return [string]$entry.Code
        }
    }

    if (@($registry.Entries).Count -gt 0) {
        return [string]$registry.Entries[0].Code
    }

    'en-US'
}

function Get-DefaultItemLocalizationLabel {
    param(
        [Parameter(Mandatory = $true)][string]$SkinRoot,
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [Parameter(Mandatory = $true)]$Record
    )

    $registry = Read-DefaultItemLocalizationRegistry -SkinRoot $SkinRoot
    if ($Record.InventoryLabel) {
        foreach ($entry in @($registry.Entries)) {
            if ([string]::Equals([string]$entry.Code, $LanguageCode, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [string]$entry.InventoryLabel
            }
        }
        return ''
    }

    $catalog = Read-DefaultItemLocalizationCatalog -SkinRoot $SkinRoot -LanguageCode $LanguageCode
    $key = [string]$Record.LabelKey
    if (-not $catalog.Contains($key)) {
        throw "Localization catalog $LanguageCode is missing default item key '$key'."
    }

    [string]$catalog[$key]
}

function Get-DefaultItemLocalizationAcceptedLabels {
    param(
        [Parameter(Mandatory = $true)][string]$SkinRoot,
        [Parameter(Mandatory = $true)]$Record
    )

    $accepted = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::Ordinal)
    $registry = Read-DefaultItemLocalizationRegistry -SkinRoot $SkinRoot
    foreach ($entry in @($registry.Entries)) {
        $label = ''
        if ($Record.InventoryLabel) {
            $label = [string]$entry.InventoryLabel
        } else {
            $catalog = Read-DefaultItemLocalizationCatalog -SkinRoot $SkinRoot -LanguageCode ([string]$entry.Code)
            $key = [string]$Record.LabelKey
            if ($catalog.Contains($key)) {
                $label = [string]$catalog[$key]
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($label)) {
            $accepted[$label] = $true
        }
    }

    $accepted
}

function Test-DefaultItemLocalizationIdentity {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Variables,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)]$Record
    )

    $base = '{0}_{1}_' -f $Prefix, ([string]$Record.Section)
    foreach ($field in @('Image', 'Action', 'Qty')) {
        $key = $base + $field
        if (-not $Variables.Contains($key)) {
            return $false
        }
    }

    ([string]$Variables[$base + 'Image'] -ceq [string]$Record.Image) -and
    ([string]$Variables[$base + 'Action'] -ceq [string]$Record.Action) -and
    ([string]$Variables[$base + 'Qty'] -ceq [string]$Record.Qty)
}

function Update-DefaultItemLocalizationVariables {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Variables,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][string]$SkinRoot,
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [Parameter(Mandatory = $true)][object[]]$Records,
        [switch]$Force
    )

    $changed = 0
    foreach ($record in @($Records)) {
        if (-not (Test-DefaultItemLocalizationIdentity -Variables $Variables -Prefix $Prefix -Record $record)) {
            continue
        }

        $labelKey = '{0}_{1}_Label' -f $Prefix, ([string]$record.Section)
        if (-not $Variables.Contains($labelKey)) {
            continue
        }

        $targetLabel = Get-DefaultItemLocalizationLabel -SkinRoot $SkinRoot -LanguageCode $LanguageCode -Record $record
        if ([string]::IsNullOrWhiteSpace($targetLabel)) {
            continue
        }

        $currentLabel = [string]$Variables[$labelKey]
        $canReplace = $Force.IsPresent -or $record.AlwaysUpdate
        if (-not $canReplace) {
            $acceptedLabels = Get-DefaultItemLocalizationAcceptedLabels -SkinRoot $SkinRoot -Record $record
            $canReplace = $acceptedLabels.ContainsKey($currentLabel)
        }
        if (-not $canReplace -or $currentLabel -ceq $targetLabel) {
            continue
        }

        $Variables[$labelKey] = $targetLabel
        $changed++
    }

    $changed
}

function Invoke-DefaultItemLabelLocalization {
    param(
        [Parameter(Mandatory = $true)][string]$SkinRoot,
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [switch]$Force
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($SkinRoot)
    $resolvedLanguage = Resolve-DefaultItemLocalizationLanguageCode -SkinRoot $resolvedRoot -LanguageCode $LanguageCode
    $records = @(Get-DefaultItemLocalizationRecords)
    $targets = @(
        [PSCustomObject]@{
            Path = [System.IO.Path]::Combine($resolvedRoot, '@Resources', 'Customs', 'Data', 'HotbarItems.inc')
            Prefix = 'HotbarItem'
            Records = @($records | Where-Object { $_.DataSet -eq 'Hotbar' })
        }
        [PSCustomObject]@{
            Path = [System.IO.Path]::Combine($resolvedRoot, '@Resources', 'Customs', 'Data', 'InventoryItems.inc')
            Prefix = 'InventoryItem'
            Records = @($records | Where-Object { $_.DataSet -eq 'Inventory' })
        }
        [PSCustomObject]@{
            Path = [System.IO.Path]::Combine($resolvedRoot, '@Resources', 'Customs', 'Data', 'EditorDraft.inc')
            Prefix = 'EditorDraftItem'
            Records = $records
        }
    )

    $changedFiles = New-Object System.Collections.Generic.List[string]
    $changedLabels = 0
    foreach ($target in $targets) {
        if (-not [System.IO.File]::Exists($target.Path)) {
            continue
        }
        $variables = Read-DefaultItemLocalizationVariables -Path $target.Path
        $changed = Update-DefaultItemLocalizationVariables `
            -Variables $variables `
            -Prefix $target.Prefix `
            -SkinRoot $resolvedRoot `
            -LanguageCode $resolvedLanguage `
            -Records $target.Records `
            -Force:$Force.IsPresent
        if ($changed -le 0) {
            continue
        }

        Write-DefaultItemLocalizationVariables -Path $target.Path -Variables $variables
        [void]$changedFiles.Add($target.Path)
        $changedLabels += $changed
    }

    [PSCustomObject]@{
        LanguageCode = $resolvedLanguage
        ChangedLabelCount = $changedLabels
        ChangedFiles = @($changedFiles.ToArray())
    }
}
