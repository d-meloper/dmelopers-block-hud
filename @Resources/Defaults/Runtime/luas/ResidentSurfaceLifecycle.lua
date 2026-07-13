local M = {}

local ConfigState = nil

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function resolve(value, surface, ...)
    if type(value) == 'function' then
        return value(surface, ...)
    end
    return value
end

local function skinFor(options)
    return options.skin or SKIN
end

local function configState(skin)
    if not ConfigState then
        ConfigState = dofile((skin:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\RainmeterConfigState.lua')
    end
    return ConfigState
end

local function invoke(callback, surface, ...)
    if type(callback) == 'function' then
        return callback(surface, ...)
    end
    return nil
end

local function resolveList(value, surface)
    local resolved = resolve(value, surface)
    if type(resolved) ~= 'table' then
        return {}
    end
    return resolved
end

local function truthy(value)
    if value == nil then
        return false
    end
    if value == true then
        return true
    end
    local normalized = trim(value):lower()
    return normalized == '1' or normalized == 'true' or normalized == 'yes'
end

local function requireOption(options, name)
    if options[name] == nil then
        error('ResidentSurfaceLifecycle.CreateSurface missing required option: ' .. name, 3)
    end
end

function M.CreateSurface(options)
    options = options or {}
    requireOption(options, 'surfaceId')
    requireOption(options, 'configPath')
    requireOption(options, 'entryFile')
    requireOption(options, 'measureName')

    local surface = {}
    surface.surfaceId = trim(options.surfaceId)
    if surface.surfaceId == '' then
        error('ResidentSurfaceLifecycle.CreateSurface missing required option: surfaceId', 2)
    end
    surface.options = options

    local function skin()
        return skinFor(options)
    end

    function surface:ConfigPath()
        return trim(resolve(options.configPath, self))
    end

    function surface:EntryFile()
        return trim(resolve(options.entryFile, self))
    end

    function surface:MeasureName()
        return trim(resolve(options.measureName, self))
    end

    function surface:VisibleVariable()
        return trim(resolve(options.visibleVariable, self))
    end

    function surface:InternalStatePath()
        return trim(resolve(options.internalStatePath, self))
    end

    function surface:IsFeatureEnabled()
        local value = resolve(options.featureEnabled, self)
        if value == nil then
            return true
        end
        return truthy(value)
    end

    function surface:ShouldClearVisibleOnRainmeterClose()
        return truthy(resolve(options.clearVisibleOnRainmeterClose, self))
    end

    function surface:IsActive()
        local configPath = self:ConfigPath()
        if configPath == '' then
            return false
        end
        return configState(skin()).IsActive(skin(), configPath)
    end

    function surface:ActivateIfInactive()
        local configPath = self:ConfigPath()
        local entryFile = self:EntryFile()
        if configPath == '' or entryFile == '' then
            return false
        end
        if self:IsActive() then
            return false
        end
        invoke(options.beforeActivate, self)
        skin():Bang('!ActivateConfig', configPath, entryFile)
        invoke(options.afterActivate, self)
        return true
    end

    function surface:SetVisible(visible)
        local variableName = self:VisibleVariable()
        if variableName == '' then
            return false
        end
        local value = visible and '1' or '0'
        invoke(options.beforeSetVisible, self, value)
        skin():Bang('!SetVariable', variableName, value)
        for _, configPath in ipairs(resolveList(options.visibleMirrorConfigs, self)) do
            configPath = trim(configPath)
            if configPath ~= '' then
                configState(skin()).SetVariableIfActive(skin(), variableName, value, configPath)
            end
        end
        local internalStatePath = self:InternalStatePath()
        if internalStatePath ~= '' then
            skin():Bang('!WriteKeyValue', 'Variables', variableName, value, internalStatePath)
        end
        invoke(options.afterSetVisible, self, value)
        return true
    end

    function surface:IsVisibleIntent()
        local variableName = self:VisibleVariable()
        if variableName == '' then
            return false
        end
        return trim(skin():GetVariable(variableName, '0')) ~= '0'
    end

    function surface:CommandIfActive(measureName, command)
        measureName = trim(measureName or self:MeasureName())
        command = trim(command)
        local configPath = self:ConfigPath()
        if measureName == '' or command == '' or configPath == '' then
            return false
        end
        return configState(skin()).CommandIfActive(skin(), measureName, command, configPath)
    end

    function surface:SetVariableIfActive(name, value)
        local configPath = self:ConfigPath()
        if trim(name) == '' or configPath == '' then
            return false
        end
        return configState(skin()).SetVariableIfActive(skin(), name, tostring(value or ''), configPath)
    end

    function surface:ShowIfActive()
        local configPath = self:ConfigPath()
        if configPath == '' then
            return false
        end
        return configState(skin()).ShowIfActive(skin(), configPath)
    end

    function surface:HideIfActive()
        local configPath = self:ConfigPath()
        if configPath == '' then
            return false
        end
        return configState(skin()).HideIfActive(skin(), configPath)
    end

    function surface:ShowActiveAfterLayout()
        if not self:IsActive() then
            return false
        end
        invoke(options.beforeShow, self)
        local preShowLayoutCommand = trim(resolve(options.preShowLayoutCommand, self))
        if preShowLayoutCommand ~= '' then
            self:CommandIfActive(trim(resolve(options.preShowLayoutMeasure, self) or 'MeasureResponsiveLayout'), preShowLayoutCommand)
        end
        local shown = self:ShowIfActive()
        invoke(options.afterShow, self, shown)
        return shown
    end

    function surface:SuspendIfActiveThenHide()
        if not self:IsActive() then
            return false
        end
        invoke(options.beforeSuspend, self)
        local suspendCommand = trim(resolve(options.suspendCommand, self))
        if suspendCommand ~= '' then
            self:CommandIfActive(self:MeasureName(), suspendCommand)
        end
        local hidden = self:HideIfActive()
        invoke(options.afterSuspend, self, hidden)
        return hidden
    end

    function surface:Open()
        if not self:IsFeatureEnabled() then
            return false
        end
        self:SetVisible(true)
        if self:ActivateIfInactive() then
            return true
        end
        self:ShowActiveAfterLayout()
        local resumeCommand = trim(resolve(options.resumeCommand, self))
        if resumeCommand ~= '' then
            self:CommandIfActive(self:MeasureName(), resumeCommand)
        end
        return true
    end

    function surface:ClearVisibleOnRainmeterClose()
        if not self:ShouldClearVisibleOnRainmeterClose() then
            return false
        end
        return self:SetVisible(false)
    end

    function surface:Close(reason)
        if trim(reason):lower() == 'rainmeter-close' then
            self:ClearVisibleOnRainmeterClose()
        else
            self:SetVisible(false)
        end
        return self:SuspendIfActiveThenHide()
    end

    function surface:RestoreOnRefresh()
        if self:IsVisibleIntent() and self:IsFeatureEnabled() then
            self:ShowActiveAfterLayout()
            local resumeCommand = trim(resolve(options.resumeCommand, self))
            if resumeCommand ~= '' then
                self:CommandIfActive(self:MeasureName(), resumeCommand)
            end
            return true
        end
        return self:SuspendIfActiveThenHide()
    end

    return surface
end

return M
