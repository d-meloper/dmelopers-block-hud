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

    local function settingsVisibleMirrorConfigs()
        methods.ensurePaths()
        local rootConfig = trim(state.rootConfig or '')
        if rootConfig == '' then
            return {}
        end
        return {
            rootConfig .. '\\HUD\\Settings',
            rootConfig .. '\\HUD\\Inventory',
            rootConfig .. '\\HUD\\InventoryBG',
            rootConfig .. '\\HUD\\Hotbar',
        }
    end

    function methods.CreateSettingsSurface()
        methods.ensurePaths()
        local rootConfig = trim(state.rootConfig or '')
        return app.residentSurfaceLifecycle.CreateSurface({
            skin = SKIN,
            surfaceId = 'Settings',
            configPath = rootConfig ~= '' and (rootConfig .. '\\HUD\\Settings') or '',
            entryFile = 'Settings.ini',
            measureName = 'MeasureSettingsCommit',
            visibleVariable = 'BlockHudSettingsVisible',
            visibleMirrorConfigs = settingsVisibleMirrorConfigs,
            internalStatePath = internalStatePath,
            clearVisibleOnRainmeterClose = true,
            preShowLayoutMeasure = 'MeasureResponsiveLayout',
            preShowLayoutCommand = 'ApplyLayout()',
        })
    end

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
        return methods.CreateSettingsSurface():SetVisible(visible)
    end
end
