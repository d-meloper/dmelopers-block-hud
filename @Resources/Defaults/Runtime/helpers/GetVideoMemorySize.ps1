$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Convert-QwordValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return [uint64]0
    }
    if ($Value -is [byte[]]) {
        if ($Value.Length -ge 8) {
            return [BitConverter]::ToUInt64($Value, 0)
        }
        if ($Value.Length -ge 4) {
            return [uint64][BitConverter]::ToUInt32($Value, 0)
        }
        return [uint64]0
    }
    try {
        return [uint64]$Value
    } catch {
        return [uint64]0
    }
}

function Convert-DwordValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return [uint64]0
    }
    if ($Value -is [byte[]]) {
        if ($Value.Length -ge 4) {
            return [uint64][BitConverter]::ToUInt32($Value, 0)
        }
        return [uint64]0
    }
    try {
        return [uint64]$Value
    } catch {
        return [uint64]0
    }
}

try {
    $videoRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Video'
    $perAdapter = @{}
    if (Test-Path -LiteralPath $videoRoot) {
        Get-ChildItem -LiteralPath $videoRoot -ErrorAction SilentlyContinue | ForEach-Object {
            $adapterKey = $_.PSChildName
            $maxForAdapter = [uint64]0
            Get-ChildItem -LiteralPath $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                $candidate = Convert-QwordValue $props.'HardwareInformation.qwMemorySize'
                if ($candidate -le 0) {
                    $candidate = Convert-DwordValue $props.'HardwareInformation.MemorySize'
                }
                if ($candidate -gt $maxForAdapter) {
                    $maxForAdapter = $candidate
                }
            }
            if ($maxForAdapter -gt 0) {
                $perAdapter[$adapterKey] = $maxForAdapter
            }
        }
    }

    $total = [uint64]0
    foreach ($value in $perAdapter.Values) {
        $total += [uint64]$value
    }

    [Console]::Out.WriteLine([string]$total)
} catch {
    [Console]::Out.WriteLine('0')
}
