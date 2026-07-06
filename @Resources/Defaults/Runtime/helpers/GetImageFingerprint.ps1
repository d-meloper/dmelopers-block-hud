param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [string]$Token = '',
    [int]$Attempts = 4,
    [int]$DelayMilliseconds = 120
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
}
catch {
}
$OutputEncoding = $script:Utf8NoBom

function Write-DmelPair {
    param(
        [string]$Name,
        [AllowNull()]
        [object]$Value
    )

    $text = [string]$Value
    $text = $text -replace "(`r|`n)+", ' '
    Write-Output ('{0}={1}' -f $Name, $text)
}

function Write-DmelResult {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Fingerprint = '',
        [string]$Length = '',
        [string]$Format = '',
        [string]$ErrorCode = ''
    )

    Write-DmelPair -Name 'DMEL_STATUS' -Value $Status
    Write-DmelPair -Name 'DMEL_TOKEN' -Value $Token
    Write-DmelPair -Name 'DMEL_SOURCE_FINGERPRINT' -Value $Fingerprint
    Write-DmelPair -Name 'DMEL_SOURCE_LENGTH' -Value $Length
    Write-DmelPair -Name 'DMEL_SOURCE_FORMAT' -Value $Format
    Write-DmelPair -Name 'DMEL_ERROR_CODE' -Value $ErrorCode
    Write-DmelPair -Name 'DMEL_MESSAGE' -Value $Message
}

function Get-ImageFormatName {
    param(
        [byte[]]$Bytes,
        [int]$Count
    )

    if ($null -eq $Bytes -or $Count -lt 1) {
        return 'EMPTY'
    }

    $ascii = [System.Text.Encoding]::ASCII.GetString($Bytes, 0, $Count)
    if ($Count -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return 'PNG' }
    if ($Count -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return 'JPEG' }
    if ($Count -ge 6 -and ($ascii.StartsWith('GIF87a') -or $ascii.StartsWith('GIF89a'))) { return 'GIF' }
    if ($Count -ge 2 -and $ascii.StartsWith('BM')) { return 'BMP' }
    if ($Count -ge 12 -and $ascii.Substring(0, 4) -eq 'RIFF' -and $ascii.Substring(8, 4) -eq 'WEBP') { return 'WEBP' }
    if ($Count -ge 12 -and $ascii.Substring(4, 4) -eq 'ftyp') {
        $brand = $ascii.Substring(8, 4)
        if ($brand -eq 'avif' -or $brand -eq 'avis') { return 'AVIF' }
        if ($brand -eq 'heic' -or $brand -eq 'heix' -or $brand -eq 'hevc' -or $brand -eq 'hevx' -or $brand -eq 'mif1' -or $brand -eq 'msf1') { return 'HEIF' }
        return 'ISO-BMFF-' + $brand.Trim()
    }
    return 'UNKNOWN'
}

function Get-StreamHash {
    param([System.IO.Stream]$Stream)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        $hash = $sha.ComputeHash($Stream)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
        $Stream.Position = 0
    }
}

function Read-Fingerprint {
    param([string]$Path)

    $stream = $null
    $memory = $null
    try {
        $info = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($info.Length -le 0) {
            throw 'Source image is empty.'
        }

        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $memory = New-Object System.IO.MemoryStream
        $stream.CopyTo($memory)
        if ($memory.Length -le 0) {
            throw 'Source image is empty.'
        }

        $fingerprint = Get-StreamHash -Stream $memory
        $buffer = New-Object byte[] 32
        $memory.Position = 0
        $count = $memory.Read($buffer, 0, $buffer.Length)
        [pscustomobject]@{
            Fingerprint = 'sha256:' + $fingerprint
            Length = [string]$memory.Length
            Format = Get-ImageFormatName -Bytes $buffer -Count $count
        }
    }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

$sourceFullPath = ''
try {
    $Attempts = [Math]::Max(1, [int]$Attempts)
    $DelayMilliseconds = [Math]::Max(0, [int]$DelayMilliseconds)
    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $result = Read-Fingerprint -Path $sourceFullPath
            Write-DmelResult -Status 'OK' -Message 'Source image fingerprint read.' -Fingerprint $result.Fingerprint -Length $result.Length -Format $result.Format
            exit 0
        }
        catch {
            $lastError = $_
            if ($attempt -lt $Attempts) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }
    }

    throw $lastError
}
catch {
    $message = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Source image fingerprint could not be read.' } else { [string]$_.Exception.Message }
    Write-DmelResult -Status 'ERROR' -Message $message -ErrorCode 'FINGERPRINT_FAILED'
    exit 1
}
