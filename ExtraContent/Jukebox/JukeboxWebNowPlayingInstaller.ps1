param(
    [string]$RequestPath,

    [ValidateSet('', 'Check', 'Install')]
    [string]$Action = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$webNowPlayingPort = 8974

function Write-ResultValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Value
    )

    [Console]::WriteLine(('{0}={1}' -f $Key, [string]$Value))
}

function Write-InstallerResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Version = '',
        [string]$Arch = '',
        [string]$InstallPath = ''
    )

    Write-ResultValue -Key 'DMEL_STATUS' -Value $Status
    Write-ResultValue -Key 'DMEL_CODE' -Value $Code
    Write-ResultValue -Key 'DMEL_MESSAGE' -Value $Message
    Write-ResultValue -Key 'DMEL_VERSION' -Value $Version
    Write-ResultValue -Key 'DMEL_ARCH' -Value $Arch
    Write-ResultValue -Key 'DMEL_INSTALLPATH' -Value $InstallPath
}

function Read-RequestFile {
    param([AllowNull()][string]$Path)

    $values = @{}
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Request file is missing.'
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw 'Request file is missing.'
    }

    foreach ($line in [System.IO.File]::ReadAllLines($fullPath, $utf8NoBom)) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        $separator = $trimmed.IndexOf('=')
        if ($separator -le 0) {
            continue
        }

        $key = $trimmed.Substring(0, $separator).Trim().ToUpperInvariant()
        $value = $trimmed.Substring($separator + 1)
        $values[$key] = $value
    }

    return $values
}

function Get-UserPluginPath {
    $appData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    if ([string]::IsNullOrWhiteSpace($appData)) {
        $appData = [Environment]::GetEnvironmentVariable('APPDATA')
    }
    if ([string]::IsNullOrWhiteSpace($appData)) {
        throw 'User application data folder is unavailable.'
    }

    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($appData, 'Rainmeter', 'Plugins', 'WebNowPlaying.dll'))
}

function Get-InstalledPluginCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    $userPath = Get-UserPluginPath
    $candidates.Add($userPath)

    foreach ($variableName in @('ProgramFiles', 'ProgramFiles(x86)')) {
        $root = [Environment]::GetEnvironmentVariable($variableName)
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, 'Rainmeter', 'Plugins', 'WebNowPlaying.dll'))
        if (-not $candidates.Contains($path)) {
            $candidates.Add($path)
        }
    }

    return $candidates.ToArray()
}

function Get-ExistingPluginPath {
    foreach ($path in Get-InstalledPluginCandidates) {
        if ([System.IO.File]::Exists($path)) {
            return $path
        }
    }
    return ''
}

function Get-ArchitectureFromVersionInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not [System.IO.File]::Exists($Path)) {
            return ''
        }

        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $text = @(
            [string]$version.ProductVersion
            [string]$version.FileDescription
            [string]$version.Comments
        ) -join ' '

        if ($text -match '(?i)(32-bit|\bx86\b)') {
            return 'x86'
        }
        if ($text -match '(?i)(64-bit|\bx64\b)') {
            return 'x64'
        }
    }
    catch {
    }

    return ''
}

function Get-PeFileArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [System.IO.File]::Exists($Path)) {
        return ''
    }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($stream.Length -lt 0x40) {
            return ''
        }
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            return ''
        }

        $stream.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset + 6 -gt $stream.Length) {
            return ''
        }

        $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        if ($reader.ReadUInt32() -ne 0x00004550) {
            return ''
        }

        $machine = $reader.ReadUInt16()
        switch ($machine) {
            0x014C { return 'x86' }
            0x8664 { return 'x64' }
            default { return '' }
        }
    }
    catch {
        return ''
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-BinaryArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    $arch = Get-ArchitectureFromVersionInfo -Path $Path
    if (-not [string]::IsNullOrWhiteSpace($arch)) {
        return $arch
    }

    return Get-PeFileArchitecture -Path $Path
}

function Get-ExistingPluginState {
    param([string]$ExpectedArch = '')

    foreach ($path in Get-InstalledPluginCandidates) {
        if (-not [System.IO.File]::Exists($path)) {
            continue
        }

        $arch = Get-BinaryArchitecture -Path $path
        $compatible = $true
        if (-not [string]::IsNullOrWhiteSpace($ExpectedArch)) {
            $compatible = -not [string]::IsNullOrWhiteSpace($arch) -and [string]::Equals($arch, $ExpectedArch, [System.StringComparison]::OrdinalIgnoreCase)
        }

        return [PSCustomObject]@{
            Path = $path
            Arch = $arch
            Compatible = $compatible
        }
    }

    return [PSCustomObject]@{
        Path = ''
        Arch = ''
        Compatible = $false
    }
}

function Get-RainmeterProcessPathById {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    if ($ProcessId -le 0) {
        return ''
    }

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $process -and -not [string]::IsNullOrWhiteSpace([string]$process.Path)) {
            return [string]$process.Path
        }
    }
    catch {
    }

    try {
        $record = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
        if ($null -ne $record -and -not [string]::IsNullOrWhiteSpace([string]$record.ExecutablePath)) {
            return [string]$record.ExecutablePath
        }
    }
    catch {
    }

    return ''
}

function Get-PluginArchitectureFromPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $arch = Get-BinaryArchitecture -Path $Path
    if (-not [string]::IsNullOrWhiteSpace($arch)) {
        return $arch
    }

    if ($Path.IndexOf('Program Files (x86)', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return 'x86'
    }

    return ''
}

function Get-RainmeterPluginArchitecture {
    $currentRainmeterId = Get-CurrentRainmeterProcessId
    if ($currentRainmeterId -gt 0) {
        $currentPath = Get-RainmeterProcessPathById -ProcessId $currentRainmeterId
        $currentArch = Get-PluginArchitectureFromPath -Path $currentPath
        if (-not [string]::IsNullOrWhiteSpace($currentArch)) {
            return $currentArch
        }
    }

    $rainmeterPaths = @()
    try {
        $rainmeterPaths = @(Get-Process -Name 'Rainmeter' -ErrorAction SilentlyContinue | ForEach-Object { $_.Path } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    catch {
        $rainmeterPaths = @()
    }

    foreach ($path in $rainmeterPaths) {
        $arch = Get-PluginArchitectureFromPath -Path $path
        if (-not [string]::IsNullOrWhiteSpace($arch)) {
            return $arch
        }
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'x64'
    }
    return 'x86'
}

function Get-CurrentRainmeterProcessId {
    $candidateId = [int]$PID
    for ($depth = 0; $depth -lt 8 -and $candidateId -gt 0; $depth++) {
        $record = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$candidateId" -ErrorAction SilentlyContinue
        if ($null -eq $record) {
            break
        }
        if ([string]::Equals([string]$record.Name, 'Rainmeter.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $candidateId
        }
        $candidateId = [int]$record.ParentProcessId
    }
    return 0
}

function Get-HttpServiceRainmeterOwnerIds {
    param([Parameter(Mandatory = $true)][int]$Port)

    $netshPath = [System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows), 'System32', 'netsh.exe')
    if (-not [System.IO.File]::Exists($netshPath)) {
        return @()
    }

    $lines = @(& $netshPath http show servicestate view=requestq verbose=yes 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    $ownerIds = New-Object System.Collections.Generic.HashSet[int]
    $urlPattern = '(?i)127\.0\.0\.1:{0}(?:[:/]|$)' -f $Port
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ([string]$lines[$index] -notmatch $urlPattern) {
            continue
        }

        for ($scan = $index; $scan -ge 0; $scan--) {
            $line = [string]$lines[$scan]
            if ($scan -lt $index -and $line.Trim().Length -gt 0 -and $line -notmatch '^\s') {
                break
            }
            if ($line -match '(?i)Rainmeter\.exe' -and $line -match '(?<ProcessId>\d+)') {
                [void]$ownerIds.Add([int]$Matches.ProcessId)
            }
        }
    }

    return @($ownerIds | ForEach-Object { [int]$_ })
}

function Test-LoopbackPortAvailable {
    param([Parameter(Mandatory = $true)][int]$Port)

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try {
        $listener.Start()
        return $true
    }
    catch [System.Net.Sockets.SocketException] {
        return $false
    }
    finally {
        try {
            $listener.Stop()
        }
        catch {
        }
    }
}

function Test-WebNowPlayingPortConflict {
    if (Test-LoopbackPortAvailable -Port $webNowPlayingPort) {
        return $false
    }

    $currentRainmeterId = Get-CurrentRainmeterProcessId
    if ($currentRainmeterId -gt 0) {
        $ownerIds = @(Get-HttpServiceRainmeterOwnerIds -Port $webNowPlayingPort)
        if ($ownerIds -contains $currentRainmeterId) {
            return $false
        }
    }

    return $true
}

function Get-LatestStableRelease {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $uri = 'https://api.github.com/repos/{0}/releases/latest' -f $Repository
    try {
        return Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'DMelopers-Block-HUD-Jukebox' } -UseBasicParsing
    }
    catch {
        throw 'Latest release metadata could not be downloaded.'
    }
}

function Find-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Arch
    )

    if ($null -eq $Release -or $Release.prerelease -eq $true) {
        throw 'Latest stable release metadata is unavailable.'
    }

    $expectedName = 'WebNowPlaying-{0}.dll' -f $Arch
    foreach ($asset in @($Release.assets)) {
        if ([string]::Equals([string]$asset.name, $expectedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $url = [string]$asset.browser_download_url
            if ([string]::IsNullOrWhiteSpace($url) -or -not $url.StartsWith('https://github.com/', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Release asset download URL is invalid.'
            }
            return $asset
        }
    }

    throw 'Required release asset is unavailable.'
}

function Assert-DllLooksValid {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedArch = ''
    )

    if (-not [System.IO.File]::Exists($Path)) {
        throw 'Downloaded DLL is missing.'
    }

    $fileInfo = [System.IO.FileInfo]::new($Path)
    if ($fileInfo.Length -lt 4096) {
        throw 'Downloaded DLL is too small.'
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $first = $stream.ReadByte()
        $second = $stream.ReadByte()
        if ($first -ne 0x4D -or $second -ne 0x5A) {
            throw 'Downloaded DLL header is invalid.'
        }
    }
    finally {
        $stream.Dispose()
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedArch)) {
        $arch = Get-BinaryArchitecture -Path $Path
        if ([string]::IsNullOrWhiteSpace($arch) -or -not [string]::Equals($arch, $ExpectedArch, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('Downloaded DLL architecture is invalid. expected={0}; actual={1}' -f $ExpectedArch, $arch)
        }
    }
}

function Install-WebNowPlayingPlugin {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $targetPath = Get-UserPluginPath
    $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
    if ([string]::IsNullOrWhiteSpace($targetDirectory)) {
        throw 'Install folder is unavailable.'
    }

    [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null

    $arch = Get-RainmeterPluginArchitecture
    $existingState = Get-ExistingPluginState -ExpectedArch $arch
    if (-not [string]::IsNullOrWhiteSpace($existingState.Path) -and $existingState.Compatible) {
        Write-InstallerResult -Status 'NOOP' -Code 'ALREADY_INSTALLED' -Message 'WebNowPlaying is already installed.' -Arch $arch -InstallPath $existingState.Path
        return
    }

    $release = Get-LatestStableRelease -Repository $Repository
    $asset = Find-ReleaseAsset -Release $release -Arch $arch
    $version = [string]$release.tag_name
    if ([string]::IsNullOrWhiteSpace($version)) {
        $version = [string]$release.name
    }

    $tempPath = [System.IO.Path]::Combine($targetDirectory, ('WebNowPlaying.{0}.{1}.tmp' -f $arch, [guid]::NewGuid().ToString('N')))
    try {
        Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -Headers @{ 'User-Agent' = 'DMelopers-Block-HUD-Jukebox' } -UseBasicParsing -OutFile $tempPath
        Assert-DllLooksValid -Path $tempPath -ExpectedArch $arch

        if ([System.IO.File]::Exists($targetPath)) {
            $targetArch = Get-BinaryArchitecture -Path $targetPath
            if (-not [string]::IsNullOrWhiteSpace($targetArch) -and [string]::Equals($targetArch, $arch, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                Write-InstallerResult -Status 'NOOP' -Code 'ALREADY_INSTALLED' -Message 'WebNowPlaying is already installed.' -Version $version -Arch $arch -InstallPath $targetPath
                return
            }

            Remove-Item -LiteralPath $targetPath -Force
        }

        [System.IO.File]::Move($tempPath, $targetPath)
        Write-InstallerResult -Status 'OK' -Code 'INSTALLED' -Message 'WebNowPlaying plugin was installed.' -Version $version -Arch $arch -InstallPath $targetPath
    }
    catch {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

try {
    $repository = 'keifufu/WebNowPlaying-Rainmeter'
    if ([string]::IsNullOrWhiteSpace($Action)) {
        $request = Read-RequestFile -Path $RequestPath
        $action = ([string]$request['ACTION']).Trim().ToUpperInvariant()
        $requestedRepository = ([string]$request['REPOSITORY']).Trim()
        if (-not [string]::IsNullOrWhiteSpace($requestedRepository)) {
            $repository = $requestedRepository
        }
    }
    else {
        $action = ([string]$Action).Trim().ToUpperInvariant()
    }
    if (($action -eq 'CHECK' -or $action -eq 'INSTALL') -and (Test-WebNowPlayingPortConflict)) {
        Write-InstallerResult -Status 'NOOP' -Code 'PORT_IN_USE' -Message ('WebNowPlaying port {0} is already owned by another process.' -f $webNowPlayingPort) -InstallPath (Get-UserPluginPath)
        return
    }

    $expectedArch = Get-RainmeterPluginArchitecture
    $existingState = Get-ExistingPluginState -ExpectedArch $expectedArch
    if ($action -eq 'CHECK') {
        if (-not [string]::IsNullOrWhiteSpace($existingState.Path)) {
            if ($existingState.Compatible) {
                Write-InstallerResult -Status 'OK' -Code 'INSTALLED' -Message 'WebNowPlaying is already installed.' -Arch $expectedArch -InstallPath $existingState.Path
            }
            else {
                Write-InstallerResult -Status 'NOOP' -Code 'INCOMPATIBLE_ARCH' -Message ('Installed WebNowPlaying plugin architecture does not match Rainmeter. expected={0}; actual={1}' -f $expectedArch, $existingState.Arch) -Arch $expectedArch -InstallPath $existingState.Path
            }
        }
        else {
            Write-InstallerResult -Status 'NOOP' -Code 'MISSING' -Message 'WebNowPlaying plugin is not installed.' -InstallPath (Get-UserPluginPath)
        }
    }
    elseif ($action -eq 'INSTALL') {
        Install-WebNowPlayingPlugin -Repository $repository
    }
    else {
        Write-InstallerResult -Status 'ERROR' -Code 'REQUEST_INVALID' -Message 'Installer request is invalid.' -InstallPath (Get-UserPluginPath)
    }
}
catch {
    $installPath = ''
    try {
        $installPath = Get-UserPluginPath
    }
    catch {
        $installPath = ''
    }
    Write-InstallerResult -Status 'ERROR' -Code 'INSTALL_FAILED' -Message 'WebNowPlaying plugin could not be installed.' -InstallPath $installPath
}
