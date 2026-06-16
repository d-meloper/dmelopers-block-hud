local M = {}

local ACTIVE_PREFIX = 'BlockHudConfigActive_'
local GROUP_NAME = 'DMeloper'
local STATE_RELATIVE_PATH = 'Defaults\\Runtime\\incs\\RainmeterConfigStateMeasure.inc'
local STATE_SECTION = 'Variables'

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function normalizeConfigName(value)
    return trim(value):gsub('/', '\\')
end

local function isRootQualified(configName)
    return configName ~= '' and configName:find('[\\/]') ~= nil
end

local function activeValue(value)
    local text = trim(value)
    local number = tonumber(text)
    if number ~= nil then
        return number ~= 0
    end
    return text ~= '' and text:lower() ~= 'false'
end

local function statePath(skin)
    return tostring(skin and skin:GetVariable('@', '') or '') .. STATE_RELATIVE_PATH
end

local function setActiveValue(skin, variableName, value)
    skin:Bang('!SetVariable', variableName, value)
    skin:Bang('!SetVariableGroup', variableName, value, GROUP_NAME)
    skin:Bang('!WriteKeyValue', STATE_SECTION, variableName, value, statePath(skin))
end

function M.ConfigId(_, configName)
    configName = normalizeConfigName(configName)
    local id = configName:gsub('[^%w_]', function(char)
        return '_' .. tostring(string.byte(char) or 0)
    end)
    if id == '' then
        id = 'Root'
    end
    return id
end

function M.VariableName(skin, configName)
    return ACTIVE_PREFIX .. M.ConfigId(skin, configName)
end

function M.Register(skin, configName)
    if not skin then
        return false
    end
    configName = normalizeConfigName(configName)
    if configName == '' then
        configName = normalizeConfigName(skin:GetVariable('CURRENTCONFIG', ''))
    end
    if not isRootQualified(configName) then
        return false
    end

    local variableName = M.VariableName(skin, configName)
    setActiveValue(skin, variableName, '1')
    return true
end

function M.Unregister(skin, configName)
    if not skin then
        return false
    end
    configName = normalizeConfigName(configName)
    if configName == '' then
        configName = normalizeConfigName(skin:GetVariable('CURRENTCONFIG', ''))
    end
    if not isRootQualified(configName) then
        return false
    end

    local variableName = M.VariableName(skin, configName)
    setActiveValue(skin, variableName, '0')
    return true
end

function M.IsActive(skin, configName)
    configName = normalizeConfigName(configName)
    if not isRootQualified(configName) then
        return false
    end

    local current = normalizeConfigName(skin and skin:GetVariable('CURRENTCONFIG', '') or '')
    if current ~= '' and current:lower() == configName:lower() then
        return true
    end

    return activeValue(skin:GetVariable(M.VariableName(skin, configName), '0'))
end

function M.SetVariableIfActive(skin, name, value, configName)
    configName = normalizeConfigName(configName)
    if not M.IsActive(skin, configName) then
        return false
    end
    skin:Bang('!SetVariable', name, tostring(value or ''), configName)
    return true
end

function M.CommandIfActive(skin, measureName, command, configName)
    configName = normalizeConfigName(configName)
    if not M.IsActive(skin, configName) then
        return false
    end
    skin:Bang('!CommandMeasure', measureName, command, configName)
    return true
end

function M.ShowIfActive(skin, configName)
    configName = normalizeConfigName(configName)
    if not M.IsActive(skin, configName) then
        return false
    end
    skin:Bang('!Show', configName)
    return true
end

function M.HideIfActive(skin, configName)
    configName = normalizeConfigName(configName)
    if not M.IsActive(skin, configName) then
        return false
    end
    skin:Bang('!Hide', configName)
    return true
end

return M
