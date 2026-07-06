return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local function fileExists(path)



        local handle = io.open(tostring(path or ''), 'rb')



        if handle then



            handle:close()



            return true



        end



        return false



    end



    local function resolvePowerShellProgramPath()



        local systemRoot = os.getenv('SystemRoot') or os.getenv('WINDIR') or 'C:\\Windows'



        local primary = systemRoot .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'



        if fileExists(primary) then



            return primary



        end



        local sysnative = systemRoot .. '\\Sysnative\\WindowsPowerShell\\v1.0\\powershell.exe'



        if fileExists(sysnative) then



            return sysnative



        end



        return 'powershell'



    end



    function methods.syncPowerShellProgramPath()



        setVariable('SettingsPowerShellProgram', resolvePowerShellProgramPath())

    end

    local function internalStatePath()
        methods.ensurePaths()
        return (state.resourcesRoot or '') .. 'Defaults\\Runtime\\incs\\InternalState.inc'
    end

    local function writeInternalStateVariable(variableName, value)
        local path = internalStatePath()
        if path == '' then
            return
        end
        SKIN:Bang('!WriteKeyValue', 'Variables', variableName, value, path)
    end
    methods.writeInternalStateVariable = writeInternalStateVariable

    local ConfigState = nil

    local function configState()
        if not ConfigState then
            ConfigState = app.loadSharedLuaModule('RainmeterConfigState.lua')
        end
        return ConfigState
    end

    local function isRainmeterConfigActive(configPath)
        return configState().IsActive(SKIN, configPath)
    end

    local function setVariableForActiveConfig(name, value, configPath)
        local targetConfig = trim(configPath)
        if targetConfig == '' or not isRainmeterConfigActive(targetConfig) then
            return false
        end
        SKIN:Bang('!SetVariable', name, value, targetConfig)
        return true
    end

    function methods.setSettingsVisibleState(visible)
        local value = visible and '1' or '0'
        setVariable('BlockHudSettingsVisible', value)
        writeInternalStateVariable('BlockHudSettingsVisible', value)

        methods.ensurePaths()
        local rootConfig = trim(state.rootConfig or '')
        if rootConfig == '' then
            return
        end
        for _, configName in ipairs({ 'Settings', 'Inventory', 'InventoryBG', 'Hotbar' }) do
            setVariableForActiveConfig('BlockHudSettingsVisible', value, rootConfig .. '\\' .. configName)
        end
    end
end
