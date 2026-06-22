param(
    [string]$AudioDirectory,
    [string]$StatePath,
    [string]$SupportedExtensions = '.m4a,.mp3,.wav,.wma,.aac'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}

function Write-OutputPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    [Console]::WriteLine($Key + '=' + [string]$Value)
}

function Resolve-FullPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
}

function Get-SupportedExtensionSet {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in ([string]$SupportedExtensions -split ',')) {
        $value = ([string]$extension).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        if (-not $value.StartsWith('.')) {
            $value = '.' + $value
        }
        [void]$set.Add($value)
    }
    return $set
}

function Read-ExistingAssignments {
    param([string]$Path)

    $assignments = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) {
        return $assignments
    }

    try {
        $raw = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $assignments
        }
        $json = $raw | ConvertFrom-Json
        foreach ($entry in @($json.Assignments)) {
            $name = [string]$entry.Name
            $slot = [int]$entry.Slot
            if (-not [string]::IsNullOrWhiteSpace($name) -and $slot -ge 1) {
                $assignments[$name] = $slot
            }
        }
    }
    catch {
        return @{}
    }

    return $assignments
}

function Write-Assignments {
    param(
        [string]$Path,
        [hashtable]$Slots
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not [System.IO.Directory]::Exists($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $entries = @()
    foreach ($slot in @($Slots.Keys | Sort-Object {[int]$_})) {
        if ($Slots.ContainsKey($slot)) {
            $file = $Slots[$slot]
            $entries += [ordered]@{
                Slot = $slot
                Name = [string]$file.Name
            }
        }
    }

    $payload = [ordered]@{
        Version = 1
        UpdatedAt = [DateTime]::UtcNow.ToString('o')
        Assignments = $entries
    }
    $json = ($payload | ConvertTo-Json -Depth 5)
    $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $tmp = $Path + ('.{0}.tmp' -f $processId)
    $backup = $Path + ('.{0}.bak.tmp' -f $processId)
    try {
        [System.IO.File]::WriteAllText($tmp, $json + [Environment]::NewLine, $script:Utf8NoBom)
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($tmp, $Path, $backup, $true)
        }
        else {
            [System.IO.File]::Move($tmp, $Path)
        }
    }
    finally {
        if ([System.IO.File]::Exists($tmp)) {
            [System.IO.File]::Delete($tmp)
        }
        if ([System.IO.File]::Exists($backup)) {
            [System.IO.File]::Delete($backup)
        }
    }
}

function Get-AudioFiles {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Directory]::Exists($Path)) {
        return @()
    }
    return @(
        [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::TopDirectoryOnly) |
            ForEach-Object { [System.IO.FileInfo]::new($_) }
    )
}

try {
    $audioRoot = Resolve-FullPath -Path $AudioDirectory
    $stateFile = Resolve-FullPath -Path $StatePath
    $supportedSet = Get-SupportedExtensionSet
    $files = @(Get-AudioFiles -Path $audioRoot)
    $filesByName = @{}
    foreach ($file in $files) {
        $filesByName[[string]$file.Name] = $file
    }

    $existing = Read-ExistingAssignments -Path $stateFile
    $slots = @{}
    $usedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $nextSlot = 1
    $retainedAssignments = @()
    foreach ($name in @($existing.Keys)) {
        if (-not $filesByName.ContainsKey($name)) {
            continue
        }
        $slot = [int]$existing[$name]
        if ($slot -lt 1) {
            continue
        }
        $retainedAssignments += [pscustomobject]@{
            Slot = $slot
            Name = [string]$name
            File = $filesByName[$name]
        }
    }

    foreach ($assignment in @($retainedAssignments | Sort-Object @{ Expression = 'Slot'; Ascending = $true }, @{ Expression = 'Name'; Ascending = $true })) {
        if ($usedNames.Contains([string]$assignment.Name)) {
            continue
        }
        $slots[$nextSlot] = $assignment.File
        [void]$usedNames.Add([string]$assignment.Name)
        $nextSlot++
    }

    $newFiles = @($files | Where-Object { -not $usedNames.Contains([string]$_.Name) } |
        Sort-Object @{ Expression = 'Name'; Descending = $true })
    foreach ($file in $newFiles) {
        $slots[$nextSlot] = $file
        [void]$usedNames.Add([string]$file.Name)
        $nextSlot++
    }

    Write-Assignments -Path $stateFile -Slots $slots

    $highestSlot = 0
    foreach ($slot in @($slots.Keys)) {
        if ([int]$slot -gt $highestSlot) {
            $highestSlot = [int]$slot
        }
    }

    Write-OutputPair -Key 'DMEL_STATUS' -Value 'OK'
    Write-OutputPair -Key 'DMEL_CODE' -Value 'SCAN_OK'
    Write-OutputPair -Key 'DMEL_MESSAGE' -Value 'Jukebox disc slots were scanned.'
    Write-OutputPair -Key 'DMEL_SUPPORTED_EXTENSIONS' -Value (($supportedSet | Sort-Object) -join ', ')
    Write-OutputPair -Key 'DMEL_HIGHEST_SLOT' -Value ([string]$highestSlot)
    if ($highestSlot -le 0) {
        return
    }
    foreach ($slot in 1..$highestSlot) {
        if (-not $slots.ContainsKey($slot)) {
            Write-OutputPair -Key ("DMEL_SLOT{0}_PRESENT" -f $slot) -Value '0'
            continue
        }
        $file = $slots[$slot]
        $extension = [string]$file.Extension
        $supported = if ($supportedSet.Contains($extension)) { '1' } else { '0' }
        Write-OutputPair -Key ("DMEL_SLOT{0}_PRESENT" -f $slot) -Value '1'
        Write-OutputPair -Key ("DMEL_SLOT{0}_NAME" -f $slot) -Value ([string]$file.Name)
        Write-OutputPair -Key ("DMEL_SLOT{0}_STEM" -f $slot) -Value ([System.IO.Path]::GetFileNameWithoutExtension([string]$file.Name))
        Write-OutputPair -Key ("DMEL_SLOT{0}_EXT" -f $slot) -Value $extension
        Write-OutputPair -Key ("DMEL_SLOT{0}_PATH" -f $slot) -Value ([string]$file.FullName)
        Write-OutputPair -Key ("DMEL_SLOT{0}_SUPPORTED" -f $slot) -Value $supported
    }
}
catch {
    Write-OutputPair -Key 'DMEL_STATUS' -Value 'ERROR'
    Write-OutputPair -Key 'DMEL_CODE' -Value 'SCAN_FAILED'
    Write-OutputPair -Key 'DMEL_MESSAGE' -Value $_.Exception.Message
}
