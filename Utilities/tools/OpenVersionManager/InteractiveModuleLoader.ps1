# OpenVersionManager helpers - on-demand function promotion boundary

# Dot-sourced by the public entrypoint. Deferred scripts are loaded inside the
# function call, so every declared function must be promoted to the facade's
# script scope before the temporary call scope ends.

function Get-VersionManagerTopLevelScriptFunctionNames {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Version manager module was not found: $resolvedPath"
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $resolvedPath,
        [ref]$tokens,
        [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Version manager module could not be parsed: $resolvedPath; $([string]::Join(' | ', @($parseErrors)))"
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($definition in @($ast.FindAll({
        param($node)
        return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst])
    }, $false))) {
        if (-not $names.Contains([string]$definition.Name)) {
            [void]$names.Add([string]$definition.Name)
        }
    }
    return @($names.ToArray())
}

function Import-VersionManagerScriptFunctionsToFacadeScope {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $functionNames = @(Get-VersionManagerTopLevelScriptFunctionNames -Path $resolvedPath)
    . $resolvedPath

    foreach ($functionName in $functionNames) {
        $localFunctionPath = 'Function:\' + $functionName
        $localFunction = Get-Item -LiteralPath $localFunctionPath -ErrorAction Stop
        Set-Item -LiteralPath ('Function:\script:' + $functionName) -Value $localFunction.ScriptBlock
    }

    return $functionNames
}

function Test-VersionManagerInteractiveModulesLoaded {
    return ($script:VersionManagerInteractiveModulesLoaded -eq $true)
}

function Ensure-VersionManagerInteractiveModules {
    if (Test-VersionManagerInteractiveModulesLoaded) {
        return $false
    }

    $dialogFunctions = @(Import-VersionManagerScriptFunctionsToFacadeScope -Path (
        Join-Path $script:ModuleRoot 'DialogsActionsAndHelpers.ps1'))

    foreach ($functionName in @($dialogFunctions)) {
        if ($null -eq (Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Version manager deferred function was not promoted: $functionName"
        }
    }

    $script:VersionManagerInteractiveModulesLoaded = $true
    Write-Log 'Loaded on-demand Skin manager interaction modules.'
    return $true
}
