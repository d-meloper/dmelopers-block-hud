local M = {}  local BASE_SCREEN_WIDTH = 1920 local BASE_SCREEN_HEIGHT = 1080 local BASE_WORK_WIDTH = 1920 local BASE_WORK_HEIGHT = 1032 local AUTO_HIDE_BOTTOM_RESERVE = 48 local MIN_SCALE = 0.711 local MAX_SCALE = 1.333  local STATE_PREFIX = 'ResponsiveLayout_' local setVariableForConfig  local SKINS = {     Hotbar = {         id = 'Hotbar',         config = 'HUD\\Hotbar',         file = 'Hotbar.ini',         anchor = 'BottomCenter',         reference = 'PrimaryWorkArea',         offsetX = -11,         offsetY = -39,         scaleMode = 'uniform',     },     IndicatorHeart = {         id = 'IndicatorHeart',         config = 'HUD\\Indicators\\Heart',         file = 'Heart.ini',         anchor = 'IndicatorBaselineLeftTop',         reference = 'PrimaryWorkArea',         offsetX = -1,         offsetY = -59,         scaleMode = 'uniform',     },     IndicatorArmor = {         id = 'IndicatorArmor',         config = 'HUD\\Indicators\\Armor',         file = 'Armor.ini',         anchor = 'IndicatorBaselineLeftTop',         reference = 'PrimaryWorkArea',         offsetX = -1,         offsetY = -93,         scaleMode = 'uniform',     },     IndicatorFood = {         id = 'IndicatorFood',         config = 'HUD\\Indicators\\Food',         file = 'Food.ini',         anchor = 'IndicatorBaselineRightTop',         reference = 'PrimaryWorkArea',         offsetX = 2,         offsetY = -59,         scaleMode = 'uniform',     },     IndicatorAir = {         id = 'IndicatorAir',         config = 'HUD\\Indicators\\Air',         file = 'Air.ini',         anchor = 'IndicatorBaselineRightTop',         reference = 'PrimaryWorkArea',         offsetX = 2,         offsetY = -93,         scaleMode = 'uniform',     },     IndicatorExp = {         id = 'IndicatorExp',         config = 'HUD\\Indicators\\Exp',         file = 'Exp.ini',         anchor = 'IndicatorBaselineCenterTop',         reference = 'PrimaryWorkArea',         offsetX = 1,         offsetY = -63,         scaleMode = 'uniform',     },     Inventory = {         id = 'Inventory',         config = 'HUD\\Inventory',         file = 'Inventory.ini',         anchor = 'ScreenCenter',         reference = 'PrimaryWorkArea',         offsetX = -354,         offsetY = -310,         scaleMode = 'uniform',         dependentIds = { 'Settings', 'Editor', 'InventoryBG', 'Hotbar' },     },     InventoryBG = {         id = 'InventoryBG',         config = 'HUD\\InventoryBG',         file = 'InventoryBG.ini',         anchor = 'PrimaryWorkAreaFill',         reference = 'PrimaryWorkArea',         offsetX = 0,         offsetY = 0,         scaleMode = 'uniform',     },     Clock = {
        id = 'Clock',
        config = 'HUD\\Clock',
        file = 'Clock.ini',
        anchor = 'TopCenter',
        reference = 'PrimaryWorkArea',
        offsetX = 13,
        offsetY = 176,
        scaleMode = 'uniform',
    },
    ClockSprite = {
        id = 'ClockSprite',
        config = 'HUD\\ClockSprite',
        file = 'ClockSprite.ini',
        anchor = 'TopCenter',
        reference = 'PrimaryWorkArea',
        offsetX = -2,
        offsetY = 62,
        scaleMode = 'uniform',
    },
    Jukebox = {
        id = 'Jukebox',
        config = 'ExtraContent\\Jukebox',
        file = 'Jukebox.ini',
        anchor = 'ScreenCenter',
        reference = 'PrimaryWorkArea',
        offsetX = 0,
        offsetY = 0,
        scaleMode = 'uniform',
        dependentIds = { 'JukeboxDiscSlot' },
    },
    JukeboxDiscSlot = {
        id = 'JukeboxDiscSlot',
        config = 'ExtraContent\\Jukebox\\DiscSlot',
        file = 'JukeboxDiscSlot.ini',
        anchor = 'JukeboxTopCenter',
        reference = 'Jukebox',
        offsetX = 0,
        offsetY = 0,
        scaleMode = 'uniform',
    },
    Herobrine = {
        id = 'Herobrine',
        config = 'ExtraContent\\Herobrine',
        file = 'Herobrine.ini',
        anchor = 'ScreenCenter',
        reference = 'PrimaryWorkArea',
        offsetX = 0,
        offsetY = 0,
        scaleMode = 'uniform',
    },
    Settings = {         id = 'Settings',         config = 'HUD\\Settings',         file = 'Settings.ini',         anchor = 'InventoryLeftTop',         reference = 'Inventory',         offsetX = -350,         offsetY = 0,         scaleMode = 'uniform',         dependentIds = { 'Inventory' },     },     Editor = {         id = 'Editor',         config = 'HUD\\Editor',         file = 'Editor.ini',         anchor = 'InventoryRightTop',         reference = 'Inventory',         offsetX = -4,         offsetY = 0,         scaleMode = 'uniform',         dependentIds = { 'Inventory', 'InventoryBG' },     }, }  local TAB_TARGETS = {     hotbar = { 'Hotbar' },     indicators = { 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' },     inventory = { 'Inventory', 'InventoryBG' },     clock = { 'Clock', 'ClockSprite' },     herobrine = { 'Herobrine' },     ui = { 'Hotbar', 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp', 'Inventory', 'InventoryBG', 'Clock', 'ClockSprite', 'Jukebox', 'JukeboxDiscSlot', 'Herobrine', 'Settings', 'Editor' }, }  local function trim(value)     local text = tostring(value or '')     text = text:gsub('^%s+', '')     text = text:gsub('%s+$', '')     return text end  local function numberOr(value, fallback)     local parsed = tonumber(value)     if parsed ~= nil then         return parsed     end     return tonumber(fallback) or 0 end  local function round(value)     if value >= 0 then         return math.floor(value + 0.5)     end     return math.ceil(value - 0.5) end  local function normalizeScale(value)     return tonumber(value) or 1 end  local function scaleNumber(value, scale, fallback)     return numberOr(value, fallback) * normalizeScale(scale) end  local function clamp(value, minValue, maxValue)     if value < minValue then         return minValue     end     if value > maxValue then         return maxValue     end     return value end  local function parseStoredNumber(raw, fallback)     local parsed = tonumber(trim(raw))     if parsed ~= nil then         return parsed     end     return tonumber(tostring(fallback or '')) or 0 end  local function liveStateVarName(id, field)     return STATE_PREFIX .. id .. '_Live' .. field end  local function readLiveState(SKIN, id)     if not id or id == '' then         return nil     end     return {         Active = trim(SKIN:GetVariable(liveStateVarName(id, 'Active'), '0')) == '1',         WindowX = tonumber(trim(SKIN:GetVariable(liveStateVarName(id, 'WindowX'), ''))),         WindowY = tonumber(trim(SKIN:GetVariable(liveStateVarName(id, 'WindowY'), ''))),         Width = tonumber(trim(SKIN:GetVariable(liveStateVarName(id, 'Width'), ''))),         Height = tonumber(trim(SKIN:GetVariable(liveStateVarName(id, 'Height'), ''))),     } end  local function currentConfigWindowPosition(SKIN)     return {         x = round(tonumber(trim(SKIN:GetVariable('CURRENTCONFIGX', '0'))) or 0),         y = round(tonumber(trim(SKIN:GetVariable('CURRENTCONFIGY', '0'))) or 0),     } end  local function sameSkinCurrentWindowPosition(SKIN, id)     if M.CurrentSkinId(SKIN) ~= id then         return nil     end     return currentConfigWindowPosition(SKIN) end  local function getRootConfigFromCurrentConfig(SKIN)
    local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
    if currentConfig == '' then
        return ''
    end
    for _, definition in pairs(SKINS) do
        local suffix = '\\' .. definition.config
        if currentConfig:sub(-#suffix) == suffix then
            return trim(currentConfig:sub(1, #currentConfig - #suffix))
        end
        if currentConfig == definition.config then
            return ''
        end
    end
    return ''
end

local function getRootConfig(SKIN)
    local currentRoot = getRootConfigFromCurrentConfig(SKIN)
    if currentRoot ~= '' then
        return currentRoot
    end
    return trim(SKIN:GetVariable('ROOTCONFIG', ''))
end

local function rainmeterSettingsPath(SKIN)
    local settingsRoot = trim(SKIN:GetVariable('SETTINGSPATH', ''))
    if settingsRoot == '' then
        return nil
    end
    local lastChar = settingsRoot:sub(-1)
    if lastChar ~= '\\' and lastChar ~= '/' then
        settingsRoot = settingsRoot .. '\\'
    end
    return settingsRoot .. 'Rainmeter.ini'
end

local function rainmeterConfigName(SKIN, id)
    local definition = SKINS[id]
    local rootConfig = getRootConfig(SKIN)
    if not definition or rootConfig == '' then
        return nil
    end
    return rootConfig .. '\\' .. definition.config
end

local function syncRainmeterWindowPosition(SKIN, id, x, y, savePosition)
    if id ~= 'Inventory' and id ~= 'Jukebox' and id ~= 'JukeboxDiscSlot' then
        return false
    end
    local settingsPath = rainmeterSettingsPath(SKIN)
    local configName = rainmeterConfigName(SKIN, id)
    if not settingsPath or not configName then
        return false
    end

    local roundedX = tostring(round(tonumber(x) or 0))
    local roundedY = tostring(round(tonumber(y) or 0))
    SKIN:Bang('!WriteKeyValue', configName, 'WindowX', roundedX, settingsPath)
    SKIN:Bang('!WriteKeyValue', configName, 'WindowY', roundedY, settingsPath)
    if savePosition ~= false then
        SKIN:Bang('!WriteKeyValue', configName, 'SavePosition', '1', settingsPath)
    end
    return true
end

function M.SyncRainmeterWindowPosition(SKIN, id, x, y)
    return syncRainmeterWindowPosition(SKIN, id, x, y, true)
end

local function toNumber(SKIN, name, fallback)     local raw = SKIN:GetVariable(name, nil)     if raw == nil then         return fallback     end     if _G.DMeloper and _G.DMeloper.EvalNumber then         local evaluated = _G.DMeloper.EvalNumber(raw)         if evaluated ~= nil then             return evaluated         end     end     return tonumber(raw) or fallback end  local function baseVarName(name)     return 'ResponsiveBase_' .. name end  local function baseNumber(SKIN, name, fallback)     local cached = SKIN:GetVariable(baseVarName(name), nil)     if cached ~= nil then         if _G.DMeloper and _G.DMeloper.EvalNumber then             local evaluated = _G.DMeloper.EvalNumber(cached)             if evaluated ~= nil then                 return evaluated             end         end         return tonumber(cached) or fallback     end      local value = toNumber(SKIN, name, fallback)     setVariableForConfig(SKIN, baseVarName(name), value)     return value end  local function localVarName(id, field)     return STATE_PREFIX .. id .. '_' .. field end  function M.StatePath(SKIN)     return SKIN:GetVariable('@') .. 'Customs\\Data\\ResponsiveLayoutState.inc' end  function M.ManagedSkins()     return SKINS end  function M.AllSkinIds()     local ids = {}     for id, _ in pairs(SKINS) do         ids[#ids + 1] = id     end     table.sort(ids)     return ids end  function M.TargetIdsForTab(tabId)     local result = {}     for _, id in ipairs(TAB_TARGETS[tabId] or {}) do         result[#result + 1] = id     end     return result end  function M.CurrentSkinId(SKIN)     local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))     local rootConfig = getRootConfig(SKIN)     local suffix = currentConfig     if rootConfig ~= '' and suffix:sub(1, #rootConfig) == rootConfig then         suffix = trim(suffix:sub(#rootConfig + 1))         suffix = suffix:gsub('^\\+', '')     end     for id, definition in pairs(SKINS) do         if definition.config == suffix then             return id         end     end     return nil end  function M.BaselineState(id)     local definition = SKINS[id]     if not definition then         return nil     end     return {         AnchorKind = definition.anchor,         ReferenceTarget = definition.reference,         OffsetXBase = tostring(definition.offsetX),         OffsetYBase = tostring(definition.offsetY),         ScaleMode = definition.scaleMode or 'uniform',         PositionMode = 'auto',         FixedX = '0',         FixedY = '0',     } end  local function normalizePositionMode(value)     return trim(value) == 'fixed' and 'fixed' or 'auto' end  local function generatedDefaultVarName(id, field)     return 'ResponsiveLayoutDefault_' .. id .. '_' .. field end  local function resolveGeneratedBaselineValue(SKIN, id, field, fallback, kind)     local raw = trim(SKIN:GetVariable(generatedDefaultVarName(id, field), tostring(fallback or '')))     if raw == '' then         return tostring(fallback or '')     end     if kind == 'number' then         if tonumber(raw) == nil then             return tostring(fallback or '')         end         return tostring(raw)     end     if kind == 'mode' then         return normalizePositionMode(raw)     end     return raw end  local function resolveBaselineState(SKIN, id)     local baseline = M.BaselineState(id)     if not baseline then         return nil     end     return {         AnchorKind = resolveGeneratedBaselineValue(SKIN, id, 'AnchorKind', baseline.AnchorKind, 'text'),         ReferenceTarget = resolveGeneratedBaselineValue(SKIN, id, 'ReferenceTarget', baseline.ReferenceTarget, 'text'),         OffsetXBase = resolveGeneratedBaselineValue(SKIN, id, 'OffsetXBase', baseline.OffsetXBase, 'number'),         OffsetYBase = resolveGeneratedBaselineValue(SKIN, id, 'OffsetYBase', baseline.OffsetYBase, 'number'),         ScaleMode = resolveGeneratedBaselineValue(SKIN, id, 'ScaleMode', baseline.ScaleMode, 'text'),         PositionMode = resolveGeneratedBaselineValue(SKIN, id, 'PositionMode', baseline.PositionMode, 'mode'),         FixedX = tostring(round(parseStoredNumber(resolveGeneratedBaselineValue(SKIN, id, 'FixedX', baseline.FixedX, 'number'), baseline.FixedX))),         FixedY = tostring(round(parseStoredNumber(resolveGeneratedBaselineValue(SKIN, id, 'FixedY', baseline.FixedY, 'number'), baseline.FixedY))),     } end  local function normalizeStateForPrimaryPolicy(SKIN, id, state)     local baseline = resolveBaselineState(SKIN, id)     if not baseline then         return state     end     return {         AnchorKind = baseline.AnchorKind,         ReferenceTarget = baseline.ReferenceTarget,         OffsetXBase = baseline.OffsetXBase,         OffsetYBase = baseline.OffsetYBase,         ScaleMode = baseline.ScaleMode,         PositionMode = normalizePositionMode(state and state.PositionMode or baseline.PositionMode),         FixedX = tostring(round(parseStoredNumber(state and state.FixedX, baseline.FixedX))),         FixedY = tostring(round(parseStoredNumber(state and state.FixedY, baseline.FixedY))),     } end  function M.GetState(SKIN, id)     local baseline = resolveBaselineState(SKIN, id)     if not baseline then         return nil     end     return normalizeStateForPrimaryPolicy(SKIN, id, {         AnchorKind = trim(SKIN:GetVariable(localVarName(id, 'AnchorKind'), baseline.AnchorKind)),         ReferenceTarget = trim(SKIN:GetVariable(localVarName(id, 'ReferenceTarget'), baseline.ReferenceTarget)),         OffsetXBase = SKIN:GetVariable(localVarName(id, 'OffsetXBase'), baseline.OffsetXBase),         OffsetYBase = SKIN:GetVariable(localVarName(id, 'OffsetYBase'), baseline.OffsetYBase),         ScaleMode = trim(SKIN:GetVariable(localVarName(id, 'ScaleMode'), baseline.ScaleMode)),         PositionMode = trim(SKIN:GetVariable(localVarName(id, 'PositionMode'), baseline.PositionMode)),         FixedX = SKIN:GetVariable(localVarName(id, 'FixedX'), baseline.FixedX),         FixedY = SKIN:GetVariable(localVarName(id, 'FixedY'), baseline.FixedY),     }) end  setVariableForConfig = function(SKIN, variableName, value, configName)     if configName and configName ~= '' then         SKIN:Bang('!SetVariable', variableName, tostring(value), configName)         return     end     SKIN:Bang('!SetVariable', variableName, tostring(value)) end  local function anchorReferencesId(anchor, id)
    local normalizedAnchor = trim(anchor or '')
    return normalizedAnchor == (id .. 'LeftTop')
        or normalizedAnchor == (id .. 'RightTop')
        or normalizedAnchor == (id .. 'VisibleLeftTop')
        or normalizedAnchor == (id .. 'VisibleRightTop')
        or normalizedAnchor == (id .. 'VisibleCenterTop')
        or normalizedAnchor == (id .. 'TopCenter')
        or normalizedAnchor == (id .. 'TextTopCenter')
end

local function normalizedAffinityNumber(value)
    local text = trim(value)
    if text == '' or tonumber(text) == nil then
        return ''
    end
    return text
end

-- Extend the legacy state record without changing its existing fields.
function M.BaselineState(id)
    local definition = SKINS[id]
    if not definition then
        return nil
    end
    return {
        AnchorKind = definition.anchor,
        ReferenceTarget = definition.reference,
        OffsetXBase = tostring(definition.offsetX),
        OffsetYBase = tostring(definition.offsetY),
        ScaleMode = definition.scaleMode or 'uniform',
        PositionMode = 'auto',
        FixedX = '0',
        FixedY = '0',
        MonitorFingerprint = '',
        MonitorRelativeX = '',
        MonitorRelativeY = '',
    }
end

resolveBaselineState = function(SKIN, id)
    local baseline = M.BaselineState(id)
    if not baseline then
        return nil
    end
    return {
        AnchorKind = resolveGeneratedBaselineValue(SKIN, id, 'AnchorKind', baseline.AnchorKind, 'text'),
        ReferenceTarget = resolveGeneratedBaselineValue(SKIN, id, 'ReferenceTarget', baseline.ReferenceTarget, 'text'),
        OffsetXBase = resolveGeneratedBaselineValue(SKIN, id, 'OffsetXBase', baseline.OffsetXBase, 'number'),
        OffsetYBase = resolveGeneratedBaselineValue(SKIN, id, 'OffsetYBase', baseline.OffsetYBase, 'number'),
        ScaleMode = resolveGeneratedBaselineValue(SKIN, id, 'ScaleMode', baseline.ScaleMode, 'text'),
        PositionMode = resolveGeneratedBaselineValue(SKIN, id, 'PositionMode', baseline.PositionMode, 'mode'),
        FixedX = tostring(round(parseStoredNumber(resolveGeneratedBaselineValue(SKIN, id, 'FixedX', baseline.FixedX, 'number'), baseline.FixedX))),
        FixedY = tostring(round(parseStoredNumber(resolveGeneratedBaselineValue(SKIN, id, 'FixedY', baseline.FixedY, 'number'), baseline.FixedY))),
        MonitorFingerprint = trim(resolveGeneratedBaselineValue(SKIN, id, 'MonitorFingerprint', '', 'text')),
        MonitorRelativeX = normalizedAffinityNumber(resolveGeneratedBaselineValue(SKIN, id, 'MonitorRelativeX', '', 'text')),
        MonitorRelativeY = normalizedAffinityNumber(resolveGeneratedBaselineValue(SKIN, id, 'MonitorRelativeY', '', 'text')),
    }
end

normalizeStateForPrimaryPolicy = function(SKIN, id, state)
    local baseline = resolveBaselineState(SKIN, id)
    if not baseline then
        return state
    end
    return {
        AnchorKind = baseline.AnchorKind,
        ReferenceTarget = baseline.ReferenceTarget,
        OffsetXBase = baseline.OffsetXBase,
        OffsetYBase = baseline.OffsetYBase,
        ScaleMode = baseline.ScaleMode,
        PositionMode = normalizePositionMode(state and state.PositionMode or baseline.PositionMode),
        FixedX = tostring(round(parseStoredNumber(state and state.FixedX, baseline.FixedX))),
        FixedY = tostring(round(parseStoredNumber(state and state.FixedY, baseline.FixedY))),
        MonitorFingerprint = trim(state and state.MonitorFingerprint or baseline.MonitorFingerprint),
        MonitorRelativeX = normalizedAffinityNumber(state and state.MonitorRelativeX or baseline.MonitorRelativeX),
        MonitorRelativeY = normalizedAffinityNumber(state and state.MonitorRelativeY or baseline.MonitorRelativeY),
    }
end

function M.GetState(SKIN, id)
    local baseline = resolveBaselineState(SKIN, id)
    if not baseline then
        return nil
    end
    return normalizeStateForPrimaryPolicy(SKIN, id, {
        PositionMode = trim(SKIN:GetVariable(localVarName(id, 'PositionMode'), baseline.PositionMode)),
        FixedX = SKIN:GetVariable(localVarName(id, 'FixedX'), baseline.FixedX),
        FixedY = SKIN:GetVariable(localVarName(id, 'FixedY'), baseline.FixedY),
        MonitorFingerprint = SKIN:GetVariable(localVarName(id, 'MonitorFingerprint'), baseline.MonitorFingerprint),
        MonitorRelativeX = SKIN:GetVariable(localVarName(id, 'MonitorRelativeX'), baseline.MonitorRelativeX),
        MonitorRelativeY = SKIN:GetVariable(localVarName(id, 'MonitorRelativeY'), baseline.MonitorRelativeY),
    })
end

local function dependentTargetIds(id)
    local definition = SKINS[id]
    local targets = {}
    local seen = {}
    for _, targetId in ipairs((definition and definition.dependentIds) or {}) do
        if not seen[targetId] and SKINS[targetId] then
            targets[#targets + 1] = targetId
            seen[targetId] = true
        end
    end
    for targetId, targetDefinition in pairs(SKINS) do
        if targetId ~= id then
            local referenceMatches = trim(targetDefinition.reference or '') == id
            local anchorMatches = anchorReferencesId(targetDefinition.anchor, id)
            if (referenceMatches or anchorMatches) and not seen[targetId] then
                targets[#targets + 1] = targetId
                seen[targetId] = true
            end
        end
    end
    table.sort(targets)
    return targets
end

local function positionFollowDependentIds(id)
    local targets = {}
    for targetId, targetDefinition in pairs(SKINS) do
        if targetId ~= id and targetId ~= 'InventoryBG' then
            local referenceMatches = trim(targetDefinition.reference or '') == id
            local anchorMatches = anchorReferencesId(targetDefinition.anchor, id)
            if referenceMatches or anchorMatches then
                targets[#targets + 1] = targetId
            end
        end
    end
    table.sort(targets)
    return targets
end

function M.PositionFollowDependentIds(id)
    local result = {}
    for _, targetId in ipairs(positionFollowDependentIds(id)) do
        result[#result + 1] = targetId
    end
    return result
end

local ACTIVE_PREFIX = 'BlockHudConfigActive_'

local function activeConfigVariableName(configName)
    configName = trim(configName):gsub('/', '\\')
    local id = configName:gsub('[^%w_]', function(char)
        return '_' .. tostring(string.byte(char) or 0)
    end)
    if id == '' then
        id = 'Root'
    end
    return ACTIVE_PREFIX .. id
end

local function isRainmeterConfigActive(SKIN, configName)
    local targetConfig = trim(configName):gsub('/', '\\')
    if targetConfig == '' then
        return false
    end

    local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', '')):gsub('/', '\\')
    if currentConfig ~= '' and currentConfig:lower() == targetConfig:lower() then
        return true
    end

    local raw = trim(SKIN:GetVariable(activeConfigVariableName(targetConfig), '0'))
    local number = tonumber(raw)
    if number ~= nil then
        return number ~= 0
    end
    return raw ~= '' and raw:lower() ~= 'false'
end

local function activePeerTargetIds(SKIN, id)
    local targets = {}
    for _, targetId in ipairs(dependentTargetIds(id)) do
        local liveState = readLiveState(SKIN, targetId)
        local configName = rainmeterConfigName(SKIN, targetId)
        if liveState and liveState.Active and configName and isRainmeterConfigActive(SKIN, configName) then
            targets[#targets + 1] = targetId
        end
    end
    return targets
end

local function broadcastLiveState(SKIN, id, active, x, y, width, height, followTopologySignature)
    local rootConfig = getRootConfig(SKIN)
    if rootConfig == '' then
        return
    end

    local values = {
        Active = active and '1' or '0',
        WindowX = tostring(round(tonumber(x) or 0)),
        WindowY = tostring(round(tonumber(y) or 0)),
        FollowTopologySignature = trim(followTopologySignature or ''),
    }
    if tonumber(width) and tonumber(width) > 0 then
        values.Width = tostring(round(tonumber(width)))
    end
    if tonumber(height) and tonumber(height) > 0 then
        values.Height = tostring(round(tonumber(height)))
    end

    for _, targetId in ipairs(activePeerTargetIds(SKIN, id)) do
        local definition = SKINS[targetId]
        local configName = rootConfig .. '\\' .. definition.config
        for field, value in pairs(values) do
            setVariableForConfig(SKIN, liveStateVarName(id, field), value, configName)
        end
    end
    if id == 'Inventory' then
        local controllerConfig = rootConfig .. '\\HUD\\Mirror\\Controller'
        for field, value in pairs(values) do
            setVariableForConfig(SKIN, liveStateVarName(id, field), value, controllerConfig)
        end
    end
end

function M.GetLiveState(SKIN, id)
    return readLiveState(SKIN, id)
end

function M.IsSkinActive(SKIN, id)
    local liveState = readLiveState(SKIN, id)
    return liveState ~= nil and liveState.Active or false
end

function M.IsRainmeterSkinActive(SKIN, id)
    local configName = rainmeterConfigName(SKIN, id)
    return configName ~= nil and isRainmeterConfigActive(SKIN, configName)
end

local function canFollowLiveOwner(SKIN, id, liveState, snapshot)
    if not liveState or not liveState.Active or liveState.WindowX == nil or liveState.WindowY == nil then
        return false
    end
    if not M.IsRainmeterSkinActive(SKIN, id) then
        return false
    end
    local followSignature = trim(SKIN:GetVariable(liveStateVarName(id, 'FollowTopologySignature'), ''))
    return followSignature ~= ''
        and snapshot ~= nil
        and followSignature == tostring(snapshot.signature or '')
end

function M.WriteLiveState(SKIN, id, active, x, y, broadcast, width, height)
    if not M.PublishLiveState(SKIN, id, active, x, y, broadcast, width, height, '') then
        return false
    end

    local values = {
        Active = active and '1' or '0',
        WindowX = tostring(round(tonumber(x) or 0)),
        WindowY = tostring(round(tonumber(y) or 0)),
    }
    if tonumber(width) and tonumber(width) > 0 then
        values.Width = tostring(round(tonumber(width)))
    end
    if tonumber(height) and tonumber(height) > 0 then
        values.Height = tostring(round(tonumber(height)))
    end

    local path = M.StatePath(SKIN)
    for field, value in pairs(values) do
        SKIN:Bang('!WriteKeyValue', 'Variables', liveStateVarName(id, field), tostring(value), path)
    end

    syncRainmeterWindowPosition(SKIN, id, values.WindowX, values.WindowY, true)
    return true
end

function M.PublishLiveState(SKIN, id, active, x, y, broadcast, width, height, followTopologySignature)
    if not id or not SKINS[id] then
        return false
    end

    local values = {
        Active = active and '1' or '0',
        WindowX = tostring(round(tonumber(x) or 0)),
        WindowY = tostring(round(tonumber(y) or 0)),
        FollowTopologySignature = trim(followTopologySignature or ''),
    }
    if tonumber(width) and tonumber(width) > 0 then
        values.Width = tostring(round(tonumber(width)))
    end
    if tonumber(height) and tonumber(height) > 0 then
        values.Height = tostring(round(tonumber(height)))
    end

    for field, value in pairs(values) do
        local variableName = liveStateVarName(id, field)
        setVariableForConfig(SKIN, variableName, value)
    end

    if broadcast ~= false then
        broadcastLiveState(SKIN, id, active, x, y, width, height, followTopologySignature)
    end
    return true
end

function M.BroadcastState(SKIN, id, state)
    local rootConfig = getRootConfig(SKIN)
    if rootConfig == '' then
        return
    end

    local fields = {
        AnchorKind = state.AnchorKind,
        ReferenceTarget = state.ReferenceTarget,
        OffsetXBase = tostring(state.OffsetXBase),
        OffsetYBase = tostring(state.OffsetYBase),
        ScaleMode = state.ScaleMode,
        PositionMode = state.PositionMode,
        FixedX = tostring(state.FixedX),
        FixedY = tostring(state.FixedY),
        MonitorFingerprint = tostring(state.MonitorFingerprint or ''),
        MonitorRelativeX = tostring(state.MonitorRelativeX or ''),
        MonitorRelativeY = tostring(state.MonitorRelativeY or ''),
    }

    for _, targetId in ipairs(activePeerTargetIds(SKIN, id)) do
        local definition = SKINS[targetId]
        local configName = rootConfig .. '\\' .. definition.config
        for field, value in pairs(fields) do
            setVariableForConfig(SKIN, localVarName(id, field), value, configName)
        end
    end

    local mirrorControllerConfig = rootConfig .. '\\HUD\\Mirror\\Controller'
    for field, value in pairs(fields) do
        setVariableForConfig(SKIN, localVarName(id, field), value, mirrorControllerConfig)
    end
end

function M.WriteState(SKIN, id, state, broadcast, options)
    local normalizedState = normalizeStateForPrimaryPolicy(SKIN, id, state)
    local path = M.StatePath(SKIN)
    for field, value in pairs({
        AnchorKind = normalizedState.AnchorKind,
        ReferenceTarget = normalizedState.ReferenceTarget,
        OffsetXBase = tostring(normalizedState.OffsetXBase),
        OffsetYBase = tostring(normalizedState.OffsetYBase),
        ScaleMode = normalizedState.ScaleMode,
        PositionMode = normalizedState.PositionMode,
        FixedX = tostring(normalizedState.FixedX),
        FixedY = tostring(normalizedState.FixedY),
        MonitorFingerprint = tostring(normalizedState.MonitorFingerprint or ''),
        MonitorRelativeX = tostring(normalizedState.MonitorRelativeX or ''),
        MonitorRelativeY = tostring(normalizedState.MonitorRelativeY or ''),
    }) do
        local variableName = localVarName(id, field)
        SKIN:Bang('!WriteKeyValue', 'Variables', variableName, tostring(value), path)
        setVariableForConfig(SKIN, variableName, value)
    end

    local syncManagedWindowPosition = not (type(options) == 'table' and options.syncRainmeterPosition == false)
    if syncManagedWindowPosition and id == 'Inventory' and M.ResolveRects then
        local rects = M.ResolveRects(SKIN)
        local inventory = rects and rects.Inventory
        if inventory and not inventory.fallbackActive then
            syncRainmeterWindowPosition(SKIN, id, inventory.x, inventory.y, true)
        end
    end

    if broadcast ~= false then
        M.BroadcastState(SKIN, id, normalizedState)
    end
end

function M.PrepareInventoryRefreshPosition(SKIN, preserveCurrentPosition)
    if preserveCurrentPosition == false then
        local baseline = resolveBaselineState(SKIN, 'Inventory')
        if baseline then
            M.WriteState(SKIN, 'Inventory', baseline, true)
        end
    end

    local rects = M.ResolveRects(SKIN)
    local inventory = rects and rects.Inventory
    if not inventory then
        return false
    end

    if inventory.fallbackActive then
        M.PublishLiveState(SKIN, 'Inventory', true, inventory.x, inventory.y, false, inventory.width, inventory.height)
    else
        M.WriteLiveState(SKIN, 'Inventory', true, inventory.x, inventory.y, false, inventory.width, inventory.height)
    end
    return true
end

function M.ResetStateIds(SKIN, ids)
    local resetJukeboxForm = false
    for _, id in ipairs(ids or {}) do
        local baseline = resolveBaselineState(SKIN, id)
        if baseline then
            M.WriteState(SKIN, id, baseline, true)
            if id == 'Jukebox' then
                resetJukeboxForm = true
            end
        end
    end
    if resetJukeboxForm then
        local name = 'ResponsiveLayout_Jukebox_FormResetPending'
        SKIN:Bang('!WriteKeyValue', 'Variables', name, '1', M.StatePath(SKIN))
        setVariableForConfig(SKIN, name, '1')
    end
end

local function buildRect(x, y, width, height)
    local resolvedWidth = math.max(1, tonumber(width) or 1)
    local resolvedHeight = math.max(1, tonumber(height) or 1)
    local resolvedX = tonumber(x) or 0
    local resolvedY = tonumber(y) or 0
    return {
        x = resolvedX,
        y = resolvedY,
        width = resolvedWidth,
        height = resolvedHeight,
        right = resolvedX + resolvedWidth,
        bottom = resolvedY + resolvedHeight,
        centerX = resolvedX + (resolvedWidth / 2),
        centerY = resolvedY + (resolvedHeight / 2),
    }
end

local function rawPrimaryWorkArea(SKIN)
    return buildRect(
        toNumber(SKIN, 'PWORKAREAX', 0),
        toNumber(SKIN, 'PWORKAREAY', 0),
        toNumber(SKIN, 'PWORKAREAWIDTH', BASE_WORK_WIDTH),
        toNumber(SKIN, 'PWORKAREAHEIGHT', BASE_WORK_HEIGHT)
    )
end

local function primaryScreenArea(SKIN)
    return buildRect(
        toNumber(SKIN, 'PSCREENAREAX', 0),
        toNumber(SKIN, 'PSCREENAREAY', 0),
        toNumber(SKIN, 'PSCREENAREAWIDTH', BASE_SCREEN_WIDTH),
        toNumber(SKIN, 'PSCREENAREAHEIGHT', BASE_SCREEN_HEIGHT)
    )
end

local function rectsEffectivelyMatch(left, right)
    if not left or not right then
        return false
    end

    local tolerance = 1
    return math.abs((left.x or 0) - (right.x or 0)) <= tolerance
        and math.abs((left.y or 0) - (right.y or 0)) <= tolerance
        and math.abs((left.width or 0) - (right.width or 0)) <= tolerance
        and math.abs((left.height or 0) - (right.height or 0)) <= tolerance
end

local function effectivePrimaryWorkArea(SKIN)
    local raw = rawPrimaryWorkArea(SKIN)
    local screen = primaryScreenArea(SKIN)
    local reserve = 0

    if rectsEffectivelyMatch(raw, screen) then
        reserve = math.max(round(screen.height * AUTO_HIDE_BOTTOM_RESERVE / BASE_SCREEN_HEIGHT), 0)
    end

    local effective = buildRect(raw.x, raw.y, raw.width, math.max(1, raw.height - reserve))
    effective.raw = raw
    effective.screen = screen
    effective.bottomReserve = reserve
    effective.wasFullScreen = reserve > 0
    return effective
end

local function rectOverlapArea(left, right)
    if not left or not right then
        return 0
    end

    local leftRight = left.right or (left.x + left.width)
    local leftBottom = left.bottom or (left.y + left.height)
    local rightRight = right.right or (right.x + right.width)
    local rightBottom = right.bottom or (right.y + right.height)
    local overlapWidth = math.max(0, math.min(leftRight, rightRight) - math.max(left.x, right.x))
    local overlapHeight = math.max(0, math.min(leftBottom, rightBottom) - math.max(left.y, right.y))
    return overlapWidth * overlapHeight
end

local function rectDistanceSquared(left, right)
    if not left or not right then
        return math.huge
    end
    local dx = 0
    local dy = 0
    if left.right < right.x then
        dx = right.x - left.right
    elseif right.right < left.x then
        dx = left.x - right.right
    end
    if left.bottom < right.y then
        dy = right.y - left.bottom
    elseif right.bottom < left.y then
        dy = left.y - right.bottom
    end
    return (dx * dx) + (dy * dy)
end

local function rectIdentity(rect)
    return table.concat({
        round(rect.x), round(rect.y), round(rect.width), round(rect.height),
    }, ',')
end

local function monitorFingerprint(screen, work)
    return rectIdentity(screen) .. '|' .. rectIdentity(work)
end

function M.ScaleForWorkArea(work)
    work = work or buildRect(0, 0, BASE_WORK_WIDTH, BASE_WORK_HEIGHT)
    local xRatio = work.width / BASE_WORK_WIDTH
    local yRatio = work.height / BASE_WORK_HEIGHT
    return clamp(math.min(xRatio, yRatio), MIN_SCALE, MAX_SCALE)
end

local function effectiveMonitorWorkArea(raw, screen, isPrimary)
    local reserve = 0
    if isPrimary and rectsEffectivelyMatch(raw, screen) then
        reserve = math.max(round(screen.height * AUTO_HIDE_BOTTOM_RESERVE / BASE_SCREEN_HEIGHT), 0)
    end
    local effective = buildRect(raw.x, raw.y, raw.width, math.max(1, raw.height - reserve))
    effective.raw = raw
    effective.screen = screen
    effective.bottomReserve = reserve
    effective.wasFullScreen = reserve > 0
    return effective
end

local function unionScreens(monitors, fallback)
    if not monitors or #monitors == 0 then
        return fallback
    end
    local left = monitors[1].screen.x
    local top = monitors[1].screen.y
    local right = monitors[1].screen.right
    local bottom = monitors[1].screen.bottom
    for index = 2, #monitors do
        local screen = monitors[index].screen
        left = math.min(left, screen.x)
        top = math.min(top, screen.y)
        right = math.max(right, screen.right)
        bottom = math.max(bottom, screen.bottom)
    end
    return buildRect(left, top, math.max(1, right - left), math.max(1, bottom - top))
end

local function readVirtualScreen(SKIN, fallback)
    local x = toNumber(SKIN, 'VSCREENAREAX', nil)
    local y = toNumber(SKIN, 'VSCREENAREAY', nil)
    local width = toNumber(SKIN, 'VSCREENAREAWIDTH', nil)
    local height = toNumber(SKIN, 'VSCREENAREAHEIGHT', nil)
    if x ~= nil and y ~= nil and width and height and width > 0 and height > 0 then
        return buildRect(x, y, width, height)
    end
    return fallback
end

function M.SnapshotMonitors(SKIN)
    local primaryScreen = primaryScreenArea(SKIN)
    local primaryRawWork = rawPrimaryWorkArea(SKIN)
    local monitors = {}
    local seen = {}

    for index = 1, 32 do
        local sx = toNumber(SKIN, 'SCREENAREAX@' .. index, nil)
        local sy = toNumber(SKIN, 'SCREENAREAY@' .. index, nil)
        local sw = toNumber(SKIN, 'SCREENAREAWIDTH@' .. index, nil)
        local sh = toNumber(SKIN, 'SCREENAREAHEIGHT@' .. index, nil)
        local wx = toNumber(SKIN, 'WORKAREAX@' .. index, nil)
        local wy = toNumber(SKIN, 'WORKAREAY@' .. index, nil)
        local ww = toNumber(SKIN, 'WORKAREAWIDTH@' .. index, nil)
        local wh = toNumber(SKIN, 'WORKAREAHEIGHT@' .. index, nil)
        if sx ~= nil and sy ~= nil and sw and sh and wx ~= nil and wy ~= nil and ww and wh
            and sw > 0 and sh > 0 and ww > 0 and wh > 0 then
            local screen = buildRect(sx, sy, sw, sh)
            local rawWork = buildRect(wx, wy, ww, wh)
            local fingerprint = monitorFingerprint(screen, rawWork)
            if not seen[fingerprint] then
                local isPrimary = rectsEffectivelyMatch(screen, primaryScreen)
                local work = effectiveMonitorWorkArea(rawWork, screen, isPrimary)
                local monitor = {
                    index = index,
                    screen = screen,
                    rawWork = rawWork,
                    work = work,
                    fingerprint = fingerprint,
                    isPrimary = isPrimary,
                    scale = M.ScaleForWorkArea(work),
                }
                monitors[#monitors + 1] = monitor
                seen[fingerprint] = monitor
            end
        end
    end

    local primary = nil
    for _, monitor in ipairs(monitors) do
        if monitor.isPrimary then
            primary = monitor
            break
        end
    end
    if not primary then
        local fingerprint = monitorFingerprint(primaryScreen, primaryRawWork)
        primary = seen[fingerprint]
        if not primary then
            local work = effectiveMonitorWorkArea(primaryRawWork, primaryScreen, true)
            primary = {
                index = 1,
                screen = primaryScreen,
                rawWork = primaryRawWork,
                work = work,
                fingerprint = fingerprint,
                isPrimary = true,
                isSynthetic = true,
                scale = M.ScaleForWorkArea(work),
            }
            monitors[#monitors + 1] = primary
        else
            primary.isPrimary = true
        end
    end

    table.sort(monitors, function(left, right)
        if left.index == right.index then
            return left.fingerprint < right.fingerprint
        end
        return left.index < right.index
    end)

    local virtualFallback = unionScreens(monitors, primaryScreen)
    local virtualScreen = readVirtualScreen(SKIN, virtualFallback)
    local fingerprints = {}
    for _, monitor in ipairs(monitors) do
        fingerprints[#fingerprints + 1] = monitor.fingerprint
    end
    table.sort(fingerprints)
    local signature = table.concat({
        'V=' .. rectIdentity(virtualScreen),
        'P=' .. primary.fingerprint,
        'M=' .. table.concat(fingerprints, ';'),
    }, '|')

    return {
        monitors = monitors,
        primary = primary,
        virtualScreen = virtualScreen,
        signature = signature,
    }
end

local MIRROR_TARGET_IDS = {
    'Hotbar',
    'IndicatorHeart',
    'IndicatorArmor',
    'IndicatorFood',
    'IndicatorAir',
    'IndicatorExp',
    'Clock',
    'ClockSprite',
}

local MIRROR_TARGET_SET = {}
for _, mirrorTargetId in ipairs(MIRROR_TARGET_IDS) do
    MIRROR_TARGET_SET[mirrorTargetId] = true
end

function M.MirrorTargetIds()
    local result = {}
    for _, id in ipairs(MIRROR_TARGET_IDS) do
        result[#result + 1] = id
    end
    return result
end

function M.IsMirrorTarget(id)
    return MIRROR_TARGET_SET[tostring(id or '')] == true
end

function M.FindMonitor(snapshotOrSkin, fingerprint, index)
    local snapshot = snapshotOrSkin
    if not snapshot or not snapshot.monitors then
        snapshot = M.SnapshotMonitors(snapshotOrSkin)
    end
    local expectedFingerprint = trim(fingerprint or '')
    local expectedIndex = tonumber(index)
    for _, monitor in ipairs(snapshot.monitors or {}) do
        if expectedFingerprint ~= '' and monitor.fingerprint == expectedFingerprint then
            return monitor
        end
    end
    if expectedIndex ~= nil then
        for _, monitor in ipairs(snapshot.monitors or {}) do
            if tonumber(monitor.index) == expectedIndex then
                return monitor
            end
        end
    end
    return nil
end

function M.TopologySignature(SKIN, snapshot)
    snapshot = snapshot or M.SnapshotMonitors(SKIN)
    return tostring(snapshot.signature or '')
end

function M.SelectMonitorForRect(snapshotOrSkin, rect, fallbackMonitor)
    local snapshot = snapshotOrSkin
    if not snapshot or not snapshot.monitors then
        snapshot = M.SnapshotMonitors(snapshotOrSkin)
    end
    fallbackMonitor = fallbackMonitor or snapshot.primary
    if not rect or #snapshot.monitors == 0 then
        return fallbackMonitor, 0
    end

    local best = nil
    local bestOverlap = -1
    local bestDistance = math.huge
    for _, monitor in ipairs(snapshot.monitors) do
        local overlap = rectOverlapArea(rect, monitor.screen)
        local distance = rectDistanceSquared(rect, monitor.screen)
        local take = false
        if overlap > bestOverlap then
            take = true
        elseif overlap == bestOverlap and overlap > 0 then
            local isFallback = monitor == fallbackMonitor
            local bestIsFallback = best == fallbackMonitor
            if isFallback ~= bestIsFallback then
                take = isFallback
            elseif monitor.isPrimary ~= (best and best.isPrimary or false) then
                take = monitor.isPrimary
            elseif best and monitor.fingerprint < best.fingerprint then
                take = true
            end
        elseif bestOverlap <= 0 and overlap == 0 then
            if distance < bestDistance then
                take = true
            elseif distance == bestDistance then
                local isFallback = monitor == fallbackMonitor
                local bestIsFallback = best == fallbackMonitor
                if isFallback ~= bestIsFallback then
                    take = isFallback
                elseif monitor.isPrimary ~= (best and best.isPrimary or false) then
                    take = monitor.isPrimary
                elseif best and monitor.fingerprint < best.fingerprint then
                    take = true
                end
            end
        end
        if take then
            best = monitor
            bestOverlap = overlap
            bestDistance = distance
        end
    end
    return best or fallbackMonitor, math.max(0, bestOverlap)
end

local function currentWorkArea(SKIN)
    return effectivePrimaryWorkArea(SKIN)
end

function M.GetScale(SKIN)
    return M.ScaleForWorkArea(effectivePrimaryWorkArea(SKIN))
end

local function usesFixedPosition(state)
    return trim(state and state.PositionMode or 'auto') == 'fixed'
end

local AUTO_MONITOR_OWNER = {
    InventoryBG = 'Inventory',
    Settings = 'Inventory',
    Editor = 'Inventory',
    JukeboxDiscSlot = 'Jukebox',
}

local function parseRectIdentity(text)
    local values = {}
    for token in tostring(text or ''):gmatch('[^,]+') do
        values[#values + 1] = tonumber(trim(token))
    end
    if #values ~= 4 or not values[1] or not values[2] or not values[3] or not values[4]
        or values[3] <= 0 or values[4] <= 0 then
        return nil
    end
    return buildRect(values[1], values[2], values[3], values[4])
end

local function parseMonitorFingerprint(value)
    local screenText, workText = tostring(value or ''):match('^([^|]+)|([^|]+)$')
    local screen = parseRectIdentity(screenText)
    local work = parseRectIdentity(workText)
    if not screen or not work then
        return nil
    end
    return { screen = screen, work = work }
end

local function closestMonitor(monitors, sourceScreen, predicate)
    local best = nil
    local bestDistance = nil
    local probe = sourceScreen or buildRect(0, 0, 1, 1)
    for _, monitor in ipairs(monitors or {}) do
        if not predicate or predicate(monitor) then
            local dx = monitor.screen.centerX - probe.centerX
            local dy = monitor.screen.centerY - probe.centerY
            local distance = (dx * dx) + (dy * dy)
            if best == nil or distance < bestDistance
                or (distance == bestDistance and monitor.isPrimary and not best.isPrimary)
                or (distance == bestDistance and monitor.isPrimary == best.isPrimary and monitor.index < best.index) then
                best = monitor
                bestDistance = distance
            end
        end
    end
    return best
end

local function affinityMonitor(snapshot, state)
    local fingerprint = trim(state and state.MonitorFingerprint or '')
    if fingerprint == '' then
        return nil, 'legacy', false, nil
    end
    for _, monitor in ipairs(snapshot.monitors) do
        if monitor.fingerprint == fingerprint then
            return monitor, 'exact', false, parseMonitorFingerprint(fingerprint)
        end
    end

    local saved = parseMonitorFingerprint(fingerprint)
    if not saved then
        return snapshot.primary, 'fallback', true, nil
    end
    for _, monitor in ipairs(snapshot.monitors) do
        if rectsEffectivelyMatch(monitor.screen, saved.screen) then
            return monitor, 'relative', false, saved
        end
    end

    local sameOrigin = closestMonitor(snapshot.monitors, saved.screen, function(monitor)
        return math.abs(monitor.screen.x - saved.screen.x) <= 1
            and math.abs(monitor.screen.y - saved.screen.y) <= 1
    end)
    if sameOrigin then
        return sameOrigin, 'relative', false, saved
    end

    if #snapshot.monitors > 1 then
        local sameResolution = closestMonitor(snapshot.monitors, saved.screen, function(monitor)
            return math.abs(monitor.screen.width - saved.screen.width) <= 1
                and math.abs(monitor.screen.height - saved.screen.height) <= 1
        end)
        if sameResolution then
            return sameResolution, 'relative', false, saved
        end
    end
    return snapshot.primary, 'fallback', true, saved
end

function M.IsMonitorFallback(SKIN, id, snapshot)
    if not id or not SKINS[id] then
        return false
    end
    local state = M.GetState(SKIN, id)
    if not state then
        return false
    end
    local _, _, fallbackActive = affinityMonitor(snapshot or M.SnapshotMonitors(SKIN), state)
    return fallbackActive == true
end

local function getIndicatorUserScale(SKIN)
    local percent = clamp(toNumber(SKIN, 'IndicatorBarScalePercent', 100), 50, 200)
    return percent / 100
end

local function resolvedIndicatorScale(scale, indicatorUserScale)
    local combined = normalizeScale(scale) * (tonumber(indicatorUserScale) or 1)
    if combined ~= combined or combined <= 0 then
        return 1
    end
    return combined
end

local function getHotbarMetrics(SKIN, scale, indicatorUserScale)
    local inventoryEnabled = trim(SKIN:GetVariable('EnableInventorySkin', '1')) ~= '0'
    local baseSlotSize = baseNumber(SKIN, 'HotbarSlotSize', 60)
    local baseTextYOffset = baseNumber(SKIN, 'HotbarTextYOffset', 70)
    local baseItemOffset = baseNumber(SKIN, 'HotbarItemSizeOffset', -12)
    local baseTextFontSize = baseNumber(SKIN, 'HotbarTextFontSize', 18)
    local indicatorScale = resolvedIndicatorScale(scale, indicatorUserScale)
    local slotSize = round(baseSlotSize * scale)
    local textYOffset = round(baseTextYOffset * scale)
    local itemOffset = round(baseItemOffset * scale)
    local textFontSize = math.max(8, round(baseTextFontSize * scale))
    local normalSlotColumns = 10
    local slotColumns = inventoryEnabled and normalSlotColumns or 9
    local hotbarWidth = slotSize * slotColumns
    local hotbarHeight = slotSize
    local centerOffset = ((normalSlotColumns - slotColumns) * slotSize) / 2
    local visibleLeft = slotSize + centerOffset
    local visibleTop = slotSize + textYOffset
    local indicatorAnchorSlotSize = math.max(round(60 * indicatorScale), 1)
    local indicatorAnchorWidth = indicatorAnchorSlotSize * normalSlotColumns
    return {
        slotSize = slotSize,
        textYOffset = textYOffset,
        itemOffset = itemOffset,
        textFontSize = textFontSize,
        normalSlotColumns = normalSlotColumns,
        slotColumns = slotColumns,
        hotbarWidth = hotbarWidth,
        hotbarHeight = hotbarHeight,
        visibleLeft = visibleLeft,
        visibleTop = visibleTop,
        visibleWidth = hotbarWidth,
        visibleHeight = hotbarHeight,
        indicatorAnchorSlotSize = indicatorAnchorSlotSize,
        indicatorAnchorWidth = indicatorAnchorWidth,
        windowWidth = visibleLeft + hotbarWidth,
        windowHeight = visibleTop + hotbarHeight,
        imageName = inventoryEnabled and 'hotbar.png' or 'hotbar9.png',
    }
end

local INVENTORY_PLAYER_OFFSET_X_BASE = 106
local INVENTORY_PLAYER_OFFSET_Y_BASE = 50
local INVENTORY_PLAYER_WIDTH_BASE = 176
local INVENTORY_PLAYER_HEIGHT_BASE = 260
local INVENTORY_PLAYER_CUSTOM_WIDTH_BASE = 122
local INVENTORY_PLAYER_CUSTOM_HEIGHT_BASE = 244
local INVENTORY_PLAYER_CUSTOM_BIAS_X_RATIO = 0.03
local INVENTORY_PLAYER_CUSTOM_RAISE_RATIO = 0.15
local INVENTORY_DESIGN_WIDTH = 708
local INVENTORY_DESIGN_HEIGHT = 668
local INVENTORY_DESIGN_SLOT_SIZE = 72
local INVENTORY_DESIGN_GRID_OFFSET_X = 30
local INVENTORY_DESIGN_GRID_OFFSET_Y = 565
local function isWorkProgressEnabled(SKIN)     return trim(SKIN:GetVariable('EnableWorkProgress', '1')) ~= '0' end  local function getInventoryMetrics(SKIN, scale)
    local width = round(INVENTORY_DESIGN_WIDTH * scale)
    -- Keep the logical grid on the exact transform used by the rendered bitmap.
    -- Independent rounding of width, slot size, and offsets accumulates horizontal
    -- drift toward the last inventory column at fractional responsive scales.
    local inventoryScale = width / INVENTORY_DESIGN_WIDTH
    local height = INVENTORY_DESIGN_HEIGHT * inventoryScale
    local playerOffsetX = round(INVENTORY_PLAYER_OFFSET_X_BASE * inventoryScale)
    local playerOffsetY = round(INVENTORY_PLAYER_OFFSET_Y_BASE * inventoryScale)
    local playerWidth = round(INVENTORY_PLAYER_WIDTH_BASE * inventoryScale)
    local playerHeight = round(INVENTORY_PLAYER_HEIGHT_BASE * inventoryScale)
    local playerCustomWidth = round(INVENTORY_PLAYER_CUSTOM_WIDTH_BASE * inventoryScale)
    local playerCustomHeight = round(INVENTORY_PLAYER_CUSTOM_HEIGHT_BASE * inventoryScale)
    local playerCustomOffsetX = playerOffsetX + round(((playerWidth - playerCustomWidth) / 2) + (playerWidth * INVENTORY_PLAYER_CUSTOM_BIAS_X_RATIO))
    local playerCustomOffsetY = playerOffsetY + round((playerHeight - playerCustomHeight) / 2)
    playerCustomOffsetY = math.max(0, round(playerCustomOffsetY * (1 - INVENTORY_PLAYER_CUSTOM_RAISE_RATIO)))
    local workProgressEnabled = isWorkProgressEnabled(SKIN)
    local normalRefreshButtonX = (width - round(16 * inventoryScale) - round(44 * inventoryScale)) - round(55 * inventoryScale) - round(12 * inventoryScale)
    local workProgressButtonBaseX = normalRefreshButtonX - round(55 * inventoryScale) - round(10 * inventoryScale)
    local workProgressButtonX = workProgressButtonBaseX + toNumber(SKIN, 'WorkProgressButtonOffsetX', 0)
    local refreshButtonBaseX = normalRefreshButtonX
    return {
        width = width,
        height = height,
        slotSize = INVENTORY_DESIGN_SLOT_SIZE * inventoryScale,
        gridOffsetX = INVENTORY_DESIGN_GRID_OFFSET_X * inventoryScale,
        gridOffsetY = INVENTORY_DESIGN_GRID_OFFSET_Y * inventoryScale,
        itemSize = round(baseNumber(SKIN, 'InventoryItemSize', 60) * inventoryScale),
        tooltipFontSize = math.max(8, round(baseNumber(SKIN, 'TooltipTextFontSize', 22) * inventoryScale)),
        playerOffsetX = playerOffsetX,
        playerOffsetY = playerOffsetY,
        playerWidth = playerWidth,
        playerHeight = playerHeight,
        playerCustomOffsetX = playerCustomOffsetX,
        playerCustomOffsetY = playerCustomOffsetY,
        playerCustomWidth = playerCustomWidth,
        playerCustomHeight = playerCustomHeight,
        settingsButtonX = round(535 * inventoryScale),
        settingsButtonY = round(256 * inventoryScale),
        settingsButtonW = round(70 * inventoryScale),
        settingsButtonH = round(70 * inventoryScale),
        optionY = round(262 * inventoryScale),
        usageGuideX = round(325 * inventoryScale) + toNumber(SKIN, 'UsageGuideOffsetX', 0),
        usageGuideY = round(262 * inventoryScale) - toNumber(SKIN, 'UsageGuideOffsetY', 0),
        usageGuideW = round(55 * inventoryScale),
        usageGuideH = round(55 * inventoryScale),
        steveSkinEditButtonX = round(270 * inventoryScale) + toNumber(SKIN, 'UsageGuideOffsetX', 0),
        steveSkinEditButtonY = round(42 * inventoryScale),
        steveSkinEditButtonW = round(20 * inventoryScale),
        steveSkinEditButtonH = round(20 * inventoryScale),
        skinFolderX = round(392 * inventoryScale) + toNumber(SKIN, 'SkinFolderOffsetX', 0),
        skinFolderY = round(262 * inventoryScale) - toNumber(SKIN, 'SkinFolderOffsetY', 0),
        skinFolderW = round(70 * inventoryScale),
        skinFolderH = round(70 * inventoryScale),
        workProgressButtonW = round(55 * inventoryScale),
        workProgressButtonH = round(55 * inventoryScale),
        workProgressEnabled = workProgressEnabled,
        workProgressButtonX = workProgressButtonX,
        workProgressButtonY = round(16 * inventoryScale) + round((round(44 * inventoryScale) - round(55 * inventoryScale)) / 2) + toNumber(SKIN, 'WorkProgressButtonOffsetY', 0),
        refreshButtonW = round(55 * inventoryScale),
        refreshButtonH = round(55 * inventoryScale),
        refreshButtonX = refreshButtonBaseX + toNumber(SKIN, 'RefreshButtonOffsetX', 0),
        refreshButtonY = round(16 * inventoryScale) + round((round(44 * inventoryScale) - round(55 * inventoryScale)) / 2) + toNumber(SKIN, 'RefreshButtonOffsetY', 0),
        editButtonX = round(614 * inventoryScale) + toNumber(SKIN, 'EditButtonOffsetX', 0),
        editButtonY = (round(262 * inventoryScale) - round(1 * inventoryScale)) - toNumber(SKIN, 'EditButtonOffsetY', 0),
        editButtonW = round(60 * inventoryScale),
        editButtonH = round(60 * inventoryScale),
        inventoryCloseButtonW = round(44 * inventoryScale),
        inventoryCloseButtonH = round(44 * inventoryScale),
        inventoryCloseButtonX = width - round(16 * inventoryScale) - round(44 * inventoryScale),
        inventoryCloseButtonY = round(16 * inventoryScale),
        badgeW = round(245 * inventoryScale),
        badgeH = round(40 * inventoryScale),
        badgeY = round(15 * inventoryScale),
        badgeFontSize = math.max(10, round(20 * inventoryScale)),
        rowExtraGap = 16 * inventoryScale,
    }
end

local function getIndicatorMetrics(id, scale, indicatorUserScale)
    local indicatorScale = resolvedIndicatorScale(scale, indicatorUserScale)
    if id == 'IndicatorExp' then
        local indicatorAnchorSlotSize = math.max(round(60 * indicatorScale), 1)
        local normalSlotColumns = 10
        local canonicalSpanWidth = indicatorAnchorSlotSize * normalSlotColumns
        local sizeRatio = canonicalSpanWidth / 1500
        local renderedWidth = math.max(round(1500 * sizeRatio), 1)
        local renderedHeight = math.max(round(41 * sizeRatio), 1)
        local textFontSize = math.max(10, round(22 * indicatorScale))
        local attachmentGap = math.max(round(7 * indicatorScale), 1)
        local anchorOffset = math.abs(tonumber((SKINS.IndicatorExp and SKINS.IndicatorExp.offsetY) or 63) or 63)
        local anchorHeight = round(anchorOffset * indicatorScale)
        local hotbarTopGap = attachmentGap
        local gaugeY = math.max(anchorHeight - renderedHeight - attachmentGap, 0)
        local textX = round(renderedWidth / 2) + round(2 * (renderedWidth / 600))
        local textGapAboveGauge = math.max(round(7 * indicatorScale), 1)
        local minTextY = 6
        local textY = math.max(gaugeY - textFontSize - textGapAboveGauge, minTextY)
        return {
            width = renderedWidth,
            height = renderedHeight,
            sizeRatio = sizeRatio,
            gaugeY = gaugeY,
            textX = textX,
            textY = textY,
            textFontSize = textFontSize,
            hotbarTopGap = hotbarTopGap,
        }
    end

    local sizeRatio = 0.45 * indicatorScale
    return {
        width = 586 * sizeRatio,
        height = 65 * sizeRatio,
        sizeRatio = sizeRatio,
    }
end

local function getClockMetrics(SKIN, scale)
    local borderSize = toNumber(SKIN, 'ClockTextBorderSize', 0) > 0 and 1 or 0
    local shadowOpacity = toNumber(SKIN, 'ClockTextShadowOpacity', 50)
    local baseShadowYOffset = baseNumber(SKIN, 'ClockTextShadowYOffset', 0)
    local baseShadowBlur = baseNumber(SKIN, 'ClockTextShadowBlur', 0)
    local timeSize = math.max(16, round(baseNumber(SKIN, 'ClockTimeTextSize', 90) * scale))
    local dateSize = math.max(8, round(baseNumber(SKIN, 'ClockDateTextSize', 25) * scale))
    local shadowYOffset = 0
    local dateShadowYOffset = 0
    local shadowBlur = 0
    if shadowOpacity > 0 then
        shadowYOffset = math.max(0, round(baseShadowYOffset * scale))
        if shadowYOffset > 0 then
            -- Rainmeter uses absolute pixels, while perceived separation also
            -- depends on glyph size. The geometric-mean scale balances those
            -- two spaces without favoring either extreme; one pixel remains
            -- the crisp raster minimum.
            dateShadowYOffset = math.max(1, round(shadowYOffset * math.sqrt(dateSize / timeSize)))
        end
        if shadowYOffset > 0 and baseShadowBlur > 0 then
            shadowBlur = math.max(1, round(baseShadowBlur * scale))
        end
    end
    local shadowBlurRadius = 3 * shadowBlur
    local maxShadowYOffset = math.max(shadowYOffset, dateShadowYOffset)
    local effectTopInset = math.max(borderSize, shadowBlurRadius)
    local effectBottomExtent = math.max(borderSize, maxShadowYOffset + shadowBlurRadius)
    local contentHeight = round((baseNumber(SKIN, 'ClockTimeTextSize', 90) + baseNumber(SKIN, 'ClockDateTextSize', 25) + 48) * scale)
    return {
        centerX = round(400 * scale),
        timeSize = timeSize,
        dateSize = dateSize,
        textGap = round(baseNumber(SKIN, 'ClockTextGap', -5) * scale),
        shadowYOffset = shadowYOffset,
        dateShadowYOffset = dateShadowYOffset,
        shadowBlur = shadowBlur,
        effectTopInset = effectTopInset,
        effectBottomExtent = effectBottomExtent,
        contentHeight = contentHeight,
        width = round(800 * scale),
        height = contentHeight + effectTopInset + effectBottomExtent,
    }
end

local function getClockSpriteMetrics(SKIN, scale)
    local baseSize = baseNumber(SKIN, 'ClockSpriteSize', 128)
    local size = math.max(32, round(baseSize * normalizeScale(scale)))
    return {
        baseSize = baseSize,
        size = size,
        gap = math.max(0, round(12 * normalizeScale(scale))),
        width = size,
        height = size,
    }
end

local function getJukeboxMetrics(SKIN, scale)
    local width = math.max(1, round(baseNumber(SKIN, 'JukeboxW', 100) * normalizeScale(scale)))
    local height = math.max(1, round(baseNumber(SKIN, 'JukeboxH', 100) * normalizeScale(scale)))
    local minimizedWidth = math.max(1, round(baseNumber(SKIN, 'JukeboxMinimizedW', 100) * normalizeScale(scale)))
    local minimizedHeight = math.max(1, round(baseNumber(SKIN, 'JukeboxMinimizedH', 40) * normalizeScale(scale)))
    return {
        width = width,
        height = height,
        minimizedWidth = minimizedWidth,
        minimizedHeight = minimizedHeight,
    }
end

local function getJukeboxDiscSlotMetrics(SKIN, scale)
    local visibleWidth = math.max(1, round(baseNumber(SKIN, 'JukeboxDiscSlotW', 310) * normalizeScale(scale)))
    local visibleHeight = math.max(1, round(baseNumber(SKIN, 'JukeboxDiscSlotH', 310) * normalizeScale(scale)))
    local outline = math.max(0, round(baseNumber(SKIN, 'JukeboxDiscSlotOutline', 5) * normalizeScale(scale)))
    local tooltipLeftGutterMax = math.max(0, round(260 * normalizeScale(scale)))
    local actionGutter = math.max(0, round(52 * normalizeScale(scale)))
    local gap = math.max(0, round(20 * normalizeScale(scale)))
    return {
        width = visibleWidth,
        height = visibleHeight,
        visibleWidth = visibleWidth,
        visibleHeight = visibleHeight,
        tooltipLeftGutter = tooltipLeftGutterMax,
        tooltipLeftGutterMax = tooltipLeftGutterMax,
        actionGutter = actionGutter,
        actionSide = 'right',
        controlRightGutter = actionGutter,
        windowWidth = visibleWidth + tooltipLeftGutterMax + actionGutter,
        windowHeight = visibleHeight,
        contentX = tooltipLeftGutterMax,
        gap = gap,
        outline = outline,
        usableX = outline,
        usableY = outline,
        usableWidth = math.max(0, visibleWidth - (outline * 2)),
        usableHeight = math.max(0, visibleHeight - (outline * 2)),
    }
end

local function getHerobrineMetrics(SKIN, scale)
    local layoutScale = normalizeScale(scale)
    local width = math.max(1, round(baseNumber(SKIN, 'HerobrineApparitionBaseW', 39) * layoutScale))
    local height = math.max(1, round(baseNumber(SKIN, 'HerobrineApparitionBaseH', 57) * layoutScale))
    local margin = math.max(0, round(baseNumber(SKIN, 'HerobrineApparitionBaseMargin', 12) * layoutScale))
    return {
        width = width,
        height = height,
        margin = margin,
    }
end

local function resolveJukeboxDiscSlotMetricsForVisibleLeft(metrics, visibleLeft, work)
    local resolved = {}
    for key, value in pairs(metrics or {}) do
        resolved[key] = value
    end

    local maxGutter = math.max(0, tonumber(resolved.tooltipLeftGutterMax or resolved.tooltipLeftGutter) or 0)
    local visibleWidth = math.max(1, tonumber(resolved.visibleWidth or resolved.width) or 1)
    local actionGutter = math.max(0, tonumber(resolved.actionGutter or resolved.controlRightGutter) or 0)
    local gutter = 0
    local actionSide = 'right'
    if work and maxGutter > 0 then
        local visibleX = round(tonumber(visibleLeft) or 0)
        local workLeft = tonumber(work.x) or 0
        local workRight = tonumber(work.right) or (workLeft + (tonumber(work.width) or 0))
        if actionGutter > 0 and (visibleX + visibleWidth + actionGutter) > workRight then
            actionSide = 'left'
        end
        local defaultCursorOffset = 30
        local tooltipWouldClipRight = (visibleX + visibleWidth + defaultCursorOffset + maxGutter) > workRight
        if tooltipWouldClipRight then
            gutter = math.min(maxGutter, math.max(0, visibleX - workLeft))
        end
    end

    resolved.tooltipLeftGutter = round(gutter)
    resolved.actionSide = actionSide
    resolved.actionGutter = actionGutter
    resolved.controlRightGutter = actionSide == 'right' and actionGutter or 0
    resolved.contentX = round(gutter + (actionSide == 'left' and actionGutter or 0))
    resolved.windowWidth = visibleWidth + round(gutter) + actionGutter
    resolved.windowHeight = math.max(1, tonumber(resolved.visibleHeight or resolved.height) or 1)
    return resolved
end

local function getPanelMetrics(id, scale)
    -- Settings and Editor contain native text-entry and dense mouse-action
    -- geometry. Keep their rendered footprint at 1x; only their monitor
    -- ownership and position participate in responsive layout.
    if id == 'Settings' then
        return {
            width = 468,
            height = 524,
        }
    end
    return {
        width = 320,
        height = 678,
    }
end

local function clampWindow(work, x, y, width, height)
    return round(clamp(x, work.x, math.max(work.x, work.right - width))),
        round(clamp(y, work.y, math.max(work.y, work.bottom - height)))
end

local function clampWindowX(work, x, width)
    return round(clamp(x, work.x, math.max(work.x, work.right - width)))
end

local function fitsWindowY(work, y, height)
    return y >= work.y and (y + height) <= work.bottom
end

local function metricSize(metrics, useVisibleSize)
    if useVisibleSize then
        return metrics.visibleWidth or metrics.width, metrics.visibleHeight or metrics.height
    end
    return metrics.windowWidth or metrics.width, metrics.windowHeight or metrics.height
end

local function contextForMonitor(monitor, affinityMode, fallbackActive, savedAffinity)
    return {
        monitor = monitor,
        work = monitor.work,
        rawWork = monitor.rawWork,
        scale = monitor.scale or M.ScaleForWorkArea(monitor.work),
        affinityMode = affinityMode or 'auto',
        fallbackActive = fallbackActive == true,
        savedAffinity = savedAffinity,
    }
end

-- DMEL_COMPAT:runtime.responsive-layout-legacy-affinity
local function resolveLayoutContext(snapshot, id, state, ownerMonitor, metricsFactory, useVisibleSize, forcedMonitor)
    local provisionalMetrics = metricsFactory(snapshot.primary.scale)
    local provisionalWidth, provisionalHeight = metricSize(provisionalMetrics, useVisibleSize)
    local monitor = nil
    local affinityMode = 'auto'
    local fallbackActive = false
    local savedAffinity = nil

    if forcedMonitor then
        monitor = forcedMonitor
        if usesFixedPosition(state) then
            local sourceMonitor = nil
            sourceMonitor, _, _, savedAffinity = affinityMonitor(snapshot, state)
            if not sourceMonitor then
                local probe = buildRect(
                    parseStoredNumber(state.FixedX, 0),
                    parseStoredNumber(state.FixedY, 0),
                    provisionalWidth,
                    provisionalHeight
                )
                sourceMonitor = M.SelectMonitorForRect(snapshot, probe, snapshot.primary)
            end
            if not savedAffinity and sourceMonitor then
                savedAffinity = { work = sourceMonitor.work }
            end
            affinityMode = 'relative'
        else
            affinityMode = 'mirror'
        end
    elseif usesFixedPosition(state) then
        monitor, affinityMode, fallbackActive, savedAffinity = affinityMonitor(snapshot, state)
        if not monitor then
            local probe = buildRect(
                parseStoredNumber(state.FixedX, 0),
                parseStoredNumber(state.FixedY, 0),
                provisionalWidth,
                provisionalHeight
            )
            monitor = M.SelectMonitorForRect(snapshot, probe, snapshot.primary)
            affinityMode = 'legacy'
        end
    else
        monitor = ownerMonitor or snapshot.primary
    end

    local context = contextForMonitor(monitor or snapshot.primary, affinityMode, fallbackActive, savedAffinity)
    local metrics = metricsFactory(context.scale)
    if not forcedMonitor and usesFixedPosition(state) and affinityMode == 'legacy' then
        local width, height = metricSize(metrics, useVisibleSize)
        local probe = buildRect(
            parseStoredNumber(state.FixedX, 0),
            parseStoredNumber(state.FixedY, 0),
            width,
            height
        )
        local selected = M.SelectMonitorForRect(snapshot, probe, context.monitor)
        if selected and selected ~= context.monitor then
            context = contextForMonitor(selected, affinityMode, false, nil)
            metrics = metricsFactory(context.scale)
        end
    end
    return context, metrics
end

local function contextForLiveRect(snapshot, rect)
    local monitor = M.SelectMonitorForRect(snapshot, rect, snapshot.primary)
    return contextForMonitor(monitor, 'live', false, nil)
end

local function ownerRectOverride(overrides, id)
    if type(overrides) ~= 'table' or type(overrides[id]) ~= 'table' then
        return nil
    end
    local override = overrides[id]
    local x = tonumber(override.x)
    local y = tonumber(override.y)
    local width = tonumber(override.width)
    local height = tonumber(override.height)
    if x == nil or y == nil or width == nil or width <= 0 or height == nil or height <= 0 then
        return nil
    end
    return {
        WindowX = x,
        WindowY = y,
        Width = width,
        Height = height,
    }
end

local function attachMonitorContext(rect, context)
    rect.monitor = context.monitor
    rect.monitorIndex = context.monitor.index
    rect.monitorFingerprint = context.monitor.fingerprint
    rect.workArea = context.work
    rect.rawWorkArea = context.rawWork
    rect.fallbackActive = context.fallbackActive
    rect.affinityMode = context.affinityMode
    return rect
end

local function resolveFixedWindow(SKIN, id, state, work, width, height, context)
    local rawX = round(parseStoredNumber(state.FixedX, 0))
    local rawY = round(parseStoredNumber(state.FixedY, 0))
    if context and context.affinityMode == 'relative' then
        local relativeX = tonumber(state.MonitorRelativeX)
        local relativeY = tonumber(state.MonitorRelativeY)
        if relativeX == nil and context.savedAffinity then
            local savedSpan = context.savedAffinity.work.width - width
            if savedSpan ~= 0 then
                relativeX = (rawX - context.savedAffinity.work.x) / savedSpan
            end
        end
        if relativeY == nil and context.savedAffinity then
            local savedSpan = context.savedAffinity.work.height - height
            if savedSpan ~= 0 then
                relativeY = (rawY - context.savedAffinity.work.y) / savedSpan
            end
        end
        if relativeX ~= nil then
            rawX = round(work.x + (relativeX * (work.width - width)))
        end
        if relativeY ~= nil then
            rawY = round(work.y + (relativeY * (work.height - height)))
        end
    elseif context and context.fallbackActive then
        rawX, rawY = clampWindow(work, rawX, rawY, width, height)
    end
    return rawX, rawY
end

-- Split from @Resources\Defaults\Runtime\luas\ResponsiveLayoutCore.lua lines 907-1748.
local function resolveIndependentIndicatorAnchorHotbar(SKIN, snapshot, indicatorUserScale, forcedMonitor)
    local state = resolveBaselineState(SKIN, 'Hotbar') or M.BaselineState('Hotbar')
    if not state then
        return nil
    end

    -- Indicators share the default HUD alignment, not the canonical Hotbar's
    -- live / fixed position. This keeps their auto placement stable across a
    -- Hotbar drag and the following independent config refresh.
    state.PositionMode = 'auto'
    state.FixedX = '0'
    state.FixedY = '0'
    state.MonitorFingerprint = ''
    state.MonitorRelativeX = ''
    state.MonitorRelativeY = ''

    local context, metrics = resolveLayoutContext(snapshot, 'Hotbar', state, nil, function(targetScale)
        return getHotbarMetrics(SKIN, targetScale, indicatorUserScale)
    end, false, forcedMonitor)
    local targetWork = context.work
    local targetScale = context.scale
    local visibleCenterX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0)
    local visibleBottomY = targetWork.bottom + scaleNumber(state.OffsetYBase, targetScale, 0)
    local rawX = visibleCenterX - (metrics.visibleLeft + (metrics.hotbarWidth / 2))
    local rawY = visibleBottomY - (metrics.visibleTop + metrics.hotbarHeight)
    rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.windowWidth, metrics.windowHeight)

    return attachMonitorContext({
        x = rawX,
        y = rawY,
        width = metrics.windowWidth,
        height = metrics.windowHeight,
        scale = targetScale,
        metrics = metrics,
        visibleLeft = rawX + metrics.visibleLeft,
        visibleTop = rawY + metrics.visibleTop,
        visibleRight = rawX + metrics.visibleLeft + metrics.visibleWidth,
        visibleBottom = rawY + metrics.visibleTop + metrics.visibleHeight,
        visibleCenterX = rawX + metrics.visibleLeft + (metrics.visibleWidth / 2),
        indicatorAnchorLeft = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) - (metrics.indicatorAnchorWidth / 2),
        indicatorAnchorRight = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) + (metrics.indicatorAnchorWidth / 2),
        indicatorAnchorTop = (rawY + metrics.visibleTop + metrics.visibleHeight) - metrics.indicatorAnchorSlotSize,
    }, context)
end

function M.ResolveRects(SKIN, snapshot, ownerRectOverrides, forcedMonitors, stateOverrides)
    snapshot = snapshot or M.SnapshotMonitors(SKIN)
    local work = snapshot.primary.work
    local scale = normalizeScale(snapshot.primary.scale)
    local indicatorUserScale = getIndicatorUserScale(SKIN)
    local rects = {}
    local function forcedMonitor(id)
        if type(forcedMonitors) ~= 'table' then
            return nil
        end
        return forcedMonitors[id]
    end
    local function resolvedState(id)
        local state = M.GetState(SKIN, id)
        local overrides = type(stateOverrides) == 'table' and stateOverrides[id] or nil
        if not state or type(overrides) ~= 'table' then
            return state
        end
        local result = {}
        for key, value in pairs(state) do
            result[key] = value
        end
        for key, value in pairs(overrides) do
            result[key] = value
        end
        return result
    end

    do
        local state = resolvedState('Hotbar')
        local context, metrics = resolveLayoutContext(snapshot, 'Hotbar', state, nil, function(targetScale)
            return getHotbarMetrics(SKIN, targetScale, indicatorUserScale)
        end, false, forcedMonitor('Hotbar'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Hotbar', state, targetWork, metrics.windowWidth, metrics.windowHeight, context)
        else
            local visibleCenterX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0)
            local visibleBottomY = targetWork.bottom + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX = visibleCenterX - (metrics.visibleLeft + (metrics.hotbarWidth / 2))
            rawY = visibleBottomY - (metrics.visibleTop + metrics.hotbarHeight)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.windowWidth, metrics.windowHeight)
        end
        local liveState = not forcedMonitor('Hotbar') and M.CurrentSkinId(SKIN) ~= 'Hotbar' and readLiveState(SKIN, 'Hotbar') or nil
        if canFollowLiveOwner(SKIN, 'Hotbar', liveState, snapshot) then
            local liveFallbackActive = context.fallbackActive
            rawX = round(liveState.WindowX)
            rawY = round(liveState.WindowY)
            context = contextForLiveRect(snapshot, buildRect(
                rawX,
                rawY,
                liveState.Width or metrics.windowWidth,
                liveState.Height or metrics.windowHeight
            ))
            context.fallbackActive = liveFallbackActive
            metrics = getHotbarMetrics(SKIN, context.scale, indicatorUserScale)
            targetScale = context.scale
        end
        rects.Hotbar = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = targetScale,
            metrics = metrics,
            visibleLeft = rawX + metrics.visibleLeft,
            visibleTop = rawY + metrics.visibleTop,
            visibleRight = rawX + metrics.visibleLeft + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleTop + metrics.visibleHeight,
            visibleCenterX = rawX + metrics.visibleLeft + (metrics.visibleWidth / 2),
            indicatorAnchorLeft = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) - (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorRight = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) + (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorTop = (rawY + metrics.visibleTop + metrics.visibleHeight) - metrics.indicatorAnchorSlotSize,
        }, context)
    end

    do
        local state = resolvedState('Inventory')
        local context, metrics = resolveLayoutContext(snapshot, 'Inventory', state, nil, function(targetScale)
            return getInventoryMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Inventory'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Inventory', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0)
            rawY = targetWork.centerY + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        local liveState = not forcedMonitor('Inventory') and M.CurrentSkinId(SKIN) ~= 'Inventory' and readLiveState(SKIN, 'Inventory') or nil
        if canFollowLiveOwner(SKIN, 'Inventory', liveState, snapshot) then
            local liveFallbackActive = context.fallbackActive
            rawX = round(liveState.WindowX)
            rawY = round(liveState.WindowY)
            context = contextForLiveRect(snapshot, buildRect(
                rawX,
                rawY,
                liveState.Width or metrics.width,
                liveState.Height or metrics.height
            ))
            context.fallbackActive = liveFallbackActive
            metrics = getInventoryMetrics(SKIN, context.scale)
            targetScale = context.scale
        end
        rects.Inventory = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
            leftTopX = rawX,
            leftTopY = rawY,
            rightTopX = rawX + metrics.width,
            rightTopY = rawY,
        }, context)
    end

    do
        local inventoryContext = contextForMonitor(rects.Inventory.monitor, 'owner', rects.Inventory.fallbackActive, nil)
        local inventoryWork = inventoryContext.rawWork
        rects.InventoryBG = attachMonitorContext({
            x = inventoryWork.x,
            y = inventoryWork.y,
            width = inventoryWork.width,
            height = inventoryWork.height,
            scale = rects.Inventory.scale,
        }, inventoryContext)
    end

    do
        local state = resolvedState('Clock')
        local context, metrics = resolveLayoutContext(snapshot, 'Clock', state, nil, function(targetScale)
            return getClockMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Clock'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Clock', state, targetWork, metrics.width, metrics.contentHeight, context)
            rawY = rawY - metrics.effectTopInset
            if context.fallbackActive then
                rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
            end
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - metrics.centerX
            rawY = targetWork.y + scaleNumber(state.OffsetYBase, targetScale, 0) - metrics.effectTopInset
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Clock = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    do
        local state = resolvedState('ClockSprite')
        local context, metrics = resolveLayoutContext(snapshot, 'ClockSprite', state, nil, function(targetScale)
            return getClockSpriteMetrics(SKIN, targetScale)
        end, false, forcedMonitor('ClockSprite'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'ClockSprite', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - round(metrics.width / 2)
            rawY = targetWork.y + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects.ClockSprite = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    do
        local state = resolvedState('Jukebox')
        local targetScale = normalizeScale(M.GetScale(SKIN))
        local context, metrics = resolveLayoutContext(snapshot, 'Jukebox', state, nil, function()
            return getJukeboxMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Jukebox'))
        local targetWork = context.work
        local width = metrics.width
        local height = metrics.height
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Jukebox', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - round(metrics.width / 2)
            rawY = targetWork.centerY + scaleNumber(state.OffsetYBase, targetScale, 0) - round(metrics.height / 2)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        local explicitOwnerRect = ownerRectOverride(ownerRectOverrides, 'Jukebox')
        if explicitOwnerRect then
            local liveFallbackActive = context.fallbackActive
            rawX = round(explicitOwnerRect.WindowX)
            rawY = round(explicitOwnerRect.WindowY)
            context = contextForLiveRect(snapshot, buildRect(
                rawX,
                rawY,
                explicitOwnerRect.Width,
                explicitOwnerRect.Height
            ))
            context.fallbackActive = liveFallbackActive
            metrics = getJukeboxMetrics(SKIN, targetScale)
            width = metrics.width
            height = metrics.height
        elseif M.CurrentSkinId(SKIN) ~= 'Jukebox' then
            local liveState = readLiveState(SKIN, 'Jukebox')
            if canFollowLiveOwner(SKIN, 'Jukebox', liveState, snapshot) then
                local liveFallbackActive = context.fallbackActive
                rawX = round(liveState.WindowX)
                rawY = round(liveState.WindowY)
                context = contextForLiveRect(snapshot, buildRect(
                    rawX,
                    rawY,
                    liveState.Width or metrics.width,
                    liveState.Height or metrics.height
                ))
                context.fallbackActive = liveFallbackActive
                metrics = getJukeboxMetrics(SKIN, targetScale)
                width = metrics.width
                height = metrics.height
            end
        end
        rects.Jukebox = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = width,
            height = height,
            scale = targetScale,
            metrics = metrics,
            topCenterX = rawX + (width / 2),
            topY = rawY,
        }, context)
    end
    do
        local state = resolvedState('JukeboxDiscSlot')
        local jukebox = rects.Jukebox
        local targetScale = normalizeScale(M.GetScale(SKIN))
        local context, metrics = resolveLayoutContext(snapshot, 'JukeboxDiscSlot', state, jukebox.monitor, function()
            return getJukeboxDiscSlotMetrics(SKIN, targetScale)
        end, true)
        if not usesFixedPosition(state) and jukebox.fallbackActive then
            context.fallbackActive = true
        end
        local rawX
        local rawY
        if usesFixedPosition(state) then
            local visibleX
            visibleX, rawY = resolveFixedWindow(
                SKIN,
                'JukeboxDiscSlot',
                state,
                context.work,
                metrics.visibleWidth,
                metrics.visibleHeight,
                context
            )
            metrics = resolveJukeboxDiscSlotMetricsForVisibleLeft(metrics, visibleX, context.work)
            rawX = visibleX - metrics.contentX
        else
            local clampWork = context.work
            local offsetX = scaleNumber(state.OffsetXBase, targetScale, 0)
            local offsetY = scaleNumber(state.OffsetYBase, targetScale, 0)
            local topY = jukebox.y - metrics.height - metrics.gap + offsetY
            local bottomY = jukebox.y + jukebox.height + metrics.gap + offsetY
            local jukeboxAnchorX = jukebox.x + (jukebox.width / 2)
            local rightColumnCenterX = metrics.usableX + ((metrics.usableWidth / 3) * 2.5)
            local visibleSlotX = clampWindowX(clampWork, jukeboxAnchorX + offsetX - rightColumnCenterX, metrics.visibleWidth)
            metrics = resolveJukeboxDiscSlotMetricsForVisibleLeft(metrics, visibleSlotX, clampWork)
            rawX = visibleSlotX - metrics.contentX
            if fitsWindowY(clampWork, topY, metrics.windowHeight) then
                rawY = round(topY)
            elseif fitsWindowY(clampWork, bottomY, metrics.windowHeight) then
                rawY = round(bottomY)
            else
                rawY = select(2, clampWindow(clampWork, rawX, topY, metrics.windowWidth, metrics.windowHeight))
            end
        end
        rects.JukeboxDiscSlot = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = targetScale,
            metrics = metrics,
            visibleLeft = rawX + metrics.contentX,
            visibleTop = rawY,
            visibleRight = rawX + metrics.contentX + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleHeight,
        }, context)
    end

    do
        local state = resolvedState('Herobrine')
        local context, metrics = resolveLayoutContext(snapshot, 'Herobrine', state, nil, function(targetScale)
            return getHerobrineMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Herobrine'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Herobrine', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - round(metrics.width / 2)
            rawY = targetWork.centerY + scaleNumber(state.OffsetYBase, targetScale, 0) - round(metrics.height / 2)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Herobrine = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    local indicatorAnchorHotbar = resolveIndependentIndicatorAnchorHotbar(
        SKIN,
        snapshot,
        indicatorUserScale,
        forcedMonitor('Hotbar')
    ) or rects.Hotbar
    for _, indicatorId in ipairs({ 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' }) do
        local state = resolvedState(indicatorId)
        local hotbar = indicatorAnchorHotbar
        local context, metrics = resolveLayoutContext(snapshot, indicatorId, state, hotbar.monitor, function(targetScale)
            return getIndicatorMetrics(indicatorId, targetScale, indicatorUserScale)
        end, false, forcedMonitor(indicatorId))
        if not usesFixedPosition(state) and hotbar.fallbackActive then
            context.fallbackActive = true
        end
        local targetScale = context.scale
        local targetWork = context.work
        local indicatorLayoutScale = resolvedIndicatorScale(targetScale, indicatorUserScale)
        local edgeInset = indicatorLayoutScale < 1 and round((1 - indicatorLayoutScale) * 10) or 0
        local definition = SKINS[indicatorId] or {}
        local offsetXBase = tonumber(state.OffsetXBase) or tonumber(definition.offsetX) or 0
        local offsetYBase = tonumber(state.OffsetYBase) or tonumber(definition.offsetY) or 0
        local commonIndicatorY = hotbar.indicatorAnchorTop + (offsetYBase * indicatorLayoutScale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(
                SKIN,
                indicatorId,
                state,
                targetWork,
                metrics.width,
                metrics.height + (metrics.gaugeY or 0),
                context
            )
        else
            if state.AnchorKind == 'HotbarVisibleLeftTop' or state.AnchorKind == 'IndicatorBaselineLeftTop' then
                rawX = hotbar.indicatorAnchorLeft + (offsetXBase * indicatorLayoutScale) + edgeInset
                rawY = commonIndicatorY
            elseif state.AnchorKind == 'HotbarVisibleRightTop' or state.AnchorKind == 'IndicatorBaselineRightTop' then
                rawX = hotbar.indicatorAnchorRight + (offsetXBase * indicatorLayoutScale) - metrics.width - edgeInset
                rawY = commonIndicatorY
            elseif indicatorId == 'IndicatorExp' then
                local indicatorSpanWidth = hotbar.indicatorAnchorRight - hotbar.indicatorAnchorLeft
                local expBaseline = SKINS.IndicatorExp or {}
                local expBaselineOffsetY = tonumber(expBaseline.offsetY) or -63
                local expGaugeY = tonumber(metrics.gaugeY) or 0
                local expHeight = tonumber(metrics.height) or 1
                local expHotbarTopGap = tonumber(metrics.hotbarTopGap) or 7
                local expYOffsetDelta = (offsetYBase - expBaselineOffsetY) * indicatorLayoutScale
                rawX = hotbar.indicatorAnchorLeft + ((indicatorSpanWidth - metrics.width) / 2) + (offsetXBase * indicatorLayoutScale)
                rawY = hotbar.indicatorAnchorTop - expGaugeY - expHeight - expHotbarTopGap + expYOffsetDelta
            else
                rawX = hotbar.visibleCenterX + (offsetXBase * indicatorLayoutScale) - (metrics.width / 2)
                rawY = commonIndicatorY
            end
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height + (metrics.gaugeY or 0))
        end
        rects[indicatorId] = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    for _, panelId in ipairs({ 'Settings', 'Editor' }) do
        local state = resolvedState(panelId)
        local inventory = rects.Inventory
        local context, metrics = resolveLayoutContext(snapshot, panelId, state, inventory.monitor, function(targetScale)
            return getPanelMetrics(panelId, targetScale)
        end)
        if not usesFixedPosition(state) and inventory.fallbackActive then
            context.fallbackActive = true
        end
        local targetScale = context.scale
        local targetWork = context.work
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, panelId, state, targetWork, metrics.width, metrics.height, context)
        else
            if state.AnchorKind == 'InventoryLeftTop' then
                rawX = inventory.leftTopX + scaleNumber(state.OffsetXBase, targetScale, 0)
            else
                rawX = inventory.rightTopX + scaleNumber(state.OffsetXBase, targetScale, 0)
            end
            rawY = inventory.leftTopY + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects[panelId] = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    rects.PrimaryWorkArea = work
    rects.Scale = scale
    rects.MonitorSnapshot = snapshot
    rects.TopologySignature = snapshot.signature
    return rects
end

local function mirrorForcedMonitors(id, monitor)
    local forcedMonitors = { [id] = monitor }
    if tostring(id):find('^Indicator') then
        forcedMonitors.Hotbar = monitor
    end
    return forcedMonitors
end

local function mirrorBaselineStateOverrides(id)
    local function autoState()
        return {
            PositionMode = 'auto',
            FixedX = '0',
            FixedY = '0',
            MonitorFingerprint = '',
            MonitorRelativeX = '',
            MonitorRelativeY = '',
        }
    end
    local overrides = { [id] = autoState() }
    if tostring(id):find('^Indicator') then
        -- Indicators use the Hotbar's responsive geometry only as a target-
        -- monitor baseline. Canonical Hotbar affinity must never leak into it.
        overrides.Hotbar = autoState()
    end
    return overrides
end

function M.ResolveMirrorRect(SKIN, id, monitorFingerprint, monitorIndex, snapshot)
    if not M.IsMirrorTarget or not M.IsMirrorTarget(id) then
        return nil
    end
    snapshot = snapshot or M.SnapshotMonitors(SKIN)
    local monitor = M.FindMonitor and M.FindMonitor(snapshot, monitorFingerprint, monitorIndex) or nil
    if not monitor then
        return nil
    end
    local rects = M.ResolveRects(
        SKIN,
        snapshot,
        nil,
        mirrorForcedMonitors(id, monitor),
        mirrorBaselineStateOverrides(id)
    )
    local rect = rects and rects[id] or nil
    if not rect then
        return nil
    end
    return rect, rects, monitor
end

function M.ResolveGridLayout(SKIN, source)
    local rects = M.ResolveRects(SKIN)
    if source == 'hotbar' then
        local hotbar = rects.Hotbar
        return {
            source = 'hotbar',
            x = hotbar.visibleLeft,
            y = hotbar.visibleTop,
            slotSize = hotbar.metrics.slotSize,
        }
    end
    if source == 'inventory' then
        local inventory = rects.Inventory
        return {
            source = 'inventory',
            x = inventory.x + inventory.metrics.gridOffsetX,
            y = inventory.y + inventory.metrics.gridOffsetY,
            slotSize = inventory.metrics.slotSize,
        }
    end
    return nil
end

function M.ResolveRelativeGridLayout(SKIN, source)
    local layout = M.ResolveGridLayout(SKIN, source)
    if not layout then
        return nil
    end
    local currentX = toNumber(SKIN, 'CURRENTCONFIGX', 0)
    local currentY = toNumber(SKIN, 'CURRENTCONFIGY', 0)
    return {
        source = layout.source,
        x = layout.x - currentX,
        y = layout.y - currentY,
        slotSize = layout.slotSize,
    }
end

local function applyWindowMove(SKIN, id, rect)
    local definition = SKINS[id]
    if not definition or not rect then
        return
    end
    SKIN:Bang('!Move', tostring(round(rect.x)), tostring(round(rect.y)), getRootConfig(SKIN) .. '\\' .. definition.config)
end

local function applyHotbarVars(SKIN, rect)
    local metrics = rect.metrics
    setVariableForConfig(SKIN, 'HotbarSlotSize', metrics.slotSize)
    setVariableForConfig(SKIN, 'HotbarTextYOffset', metrics.textYOffset)
    setVariableForConfig(SKIN, 'HotbarTextFontSize', metrics.textFontSize)
    setVariableForConfig(SKIN, 'HotbarItemSizeOffset', metrics.itemOffset)
end

local function applyInventoryVars(SKIN, rect)
    local m = rect.metrics
    for name, value in pairs({
        InventoryWidth = m.width,
        InventoryHeight = m.height,
        InventorySlotSize = m.slotSize,
        SlotSize = m.slotSize,
        InventoryGridOffsetX = m.gridOffsetX,
        InventoryGridOffsetY = m.gridOffsetY,
        InvOffsetX = m.gridOffsetX,
        InvOffsetY = m.gridOffsetY,
        InventoryItemSize = m.itemSize,
        TooltipTextFontSize = m.tooltipFontSize,
        PlayerOffsetX = m.playerOffsetX,
        PlayerOffsetY = m.playerOffsetY,
        PlayerWidth = m.playerWidth,
        PlayerHeight = m.playerHeight,
        PlayerCustomOffsetX = m.playerCustomOffsetX,
        PlayerCustomOffsetY = m.playerCustomOffsetY,
        PlayerCustomWidth = m.playerCustomWidth,
        PlayerCustomHeight = m.playerCustomHeight,
        SettingsButtonX = m.settingsButtonX,
        SettingsButtonY = m.settingsButtonY,
        SettingsButtonW = m.settingsButtonW,
        SettingsButtonH = m.settingsButtonH,
        OptionY = m.optionY,
        UsageGuideX = m.usageGuideX,
        UsageGuideY = m.usageGuideY,
        UsageGuideW = m.usageGuideW,
        UsageGuideH = m.usageGuideH,
        SteveSkinEditButtonX = m.steveSkinEditButtonX,
        SteveSkinEditButtonY = m.steveSkinEditButtonY,
        SteveSkinEditButtonW = m.steveSkinEditButtonW,
        SteveSkinEditButtonH = m.steveSkinEditButtonH,
        SkinFolderX = m.skinFolderX,
        SkinFolderY = m.skinFolderY,
        SkinFolderW = m.skinFolderW,
        SkinFolderH = m.skinFolderH,
        WorkProgressButtonX = m.workProgressButtonX,
        WorkProgressButtonY = m.workProgressButtonY,
        WorkProgressButtonW = m.workProgressButtonW,
        WorkProgressButtonH = m.workProgressButtonH,
        WorkProgressHidden = m.workProgressEnabled and 0 or 1,
        RefreshButtonX = m.refreshButtonX,
        RefreshButtonY = m.refreshButtonY,
        RefreshButtonW = m.refreshButtonW,
        RefreshButtonH = m.refreshButtonH,
        EditButtonX = m.editButtonX,
        EditButtonY = m.editButtonY,
        EditButtonW = m.editButtonW,
        EditButtonH = m.editButtonH,
        InventoryCloseButtonX = m.inventoryCloseButtonX,
        InventoryCloseButtonY = m.inventoryCloseButtonY,
        InventoryCloseButtonW = m.inventoryCloseButtonW,
        InventoryCloseButtonH = m.inventoryCloseButtonH,
        EditorModeBadgeW = m.badgeW,
        EditorModeBadgeH = m.badgeH,
        EditorModeBadgeY = m.badgeY,
        EditorModeBadgeFontSize = m.badgeFontSize,
        EditorModeBadgeX = round((m.width - m.badgeW) / 2),
        EditorModeBadgeLabelX = round((m.width - m.badgeW) / 2) + round(m.badgeW / 2),
        EditorModeBadgeLabelY = m.badgeY + round(m.badgeH / 2),
        InventoryRowExtraGap = m.rowExtraGap,
    }) do
        setVariableForConfig(SKIN, name, value)
    end
end

local function setMeterOption(SKIN, meterName, optionName, value)
    SKIN:Bang('!SetOption', meterName, optionName, tostring(value))
end

local function syncSelectedHighlight(SKIN)
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()')
end

local function applyClockVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'ClockCenterX', m.centerX)
    setVariableForConfig(SKIN, 'ClockTimeTextSize', m.timeSize)
    setVariableForConfig(SKIN, 'ClockDateTextSize', m.dateSize)
    setVariableForConfig(SKIN, 'ClockTextGap', m.textGap)
    setVariableForConfig(SKIN, 'ClockTextShadowYOffset', m.shadowYOffset)
    setVariableForConfig(SKIN, 'ClockDateTextShadowYOffset', m.dateShadowYOffset)
    setVariableForConfig(SKIN, 'ClockTextShadowBlur', m.shadowBlur)
    setVariableForConfig(SKIN, 'ClockTextEffectTopInset', m.effectTopInset)
    setVariableForConfig(SKIN, 'ClockTextEffectBottomExtent', m.effectBottomExtent)
end

local function applyClockSpriteVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'ClockSpriteRenderSize', m.size)
    SKIN:Bang('!UpdateMeter', 'MeterClockSprite')
end

local function applyJukeboxVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'JukeboxW', m.width)
    setVariableForConfig(SKIN, 'JukeboxH', m.height)
    setVariableForConfig(SKIN, 'JukeboxMinimizedW', m.minimizedWidth)
    setVariableForConfig(SKIN, 'JukeboxMinimizedH', m.minimizedHeight)
    setVariableForConfig(SKIN, 'JukeboxMainFormY', round(rect.y))
    setMeterOption(SKIN, 'MeterJukebox', 'W', m.width)
    setMeterOption(SKIN, 'MeterJukebox', 'H', m.height)
    setMeterOption(SKIN, 'MeterJukeboxAnimator', 'W', m.width)
    setMeterOption(SKIN, 'MeterJukeboxAnimator', 'H', m.height)
    setMeterOption(SKIN, 'MeterJukeboxMinimized', 'W', m.minimizedWidth)
    setMeterOption(SKIN, 'MeterJukeboxMinimized', 'H', m.minimizedHeight)
    setMeterOption(SKIN, 'MeterJukeboxMinimizedAnimator', 'W', m.minimizedWidth)
    setMeterOption(SKIN, 'MeterJukeboxMinimizedAnimator', 'H', m.minimizedHeight)
    SKIN:Bang('!UpdateMeter', 'MeterJukebox')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxAnimator')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxMinimized')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxMinimizedAnimator')
end
local function applyJukeboxDiscSlotVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'JukeboxDiscSlotW', m.visibleWidth)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotH', m.visibleHeight)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotContentX', m.contentX)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotOutline', m.outline)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableX', m.usableX)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableY', m.usableY)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableW', m.usableWidth)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableH', m.usableHeight)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotGap', m.gap)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotActionSide', m.actionSide)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotActionGutter', m.actionGutter)
    setMeterOption(SKIN, 'MeterJukeboxDiscSlot', 'W', m.visibleWidth)
    setMeterOption(SKIN, 'MeterJukeboxDiscSlot', 'H', m.visibleHeight)
    SKIN:Bang('!UpdateMeterGroup', 'JukeboxDiscSlot')
end


local function applyHerobrineVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'HerobrineApparitionRenderW', m.width)
    setVariableForConfig(SKIN, 'HerobrineApparitionRenderH', m.height)
    setVariableForConfig(SKIN, 'HerobrineApparitionMargin', m.margin)
    SKIN:Bang('!SetOption', 'MeterHerobrineApparition', 'W', tostring(m.width))
    SKIN:Bang('!SetOption', 'MeterHerobrineApparition', 'H', tostring(m.height))
    SKIN:Bang('!UpdateMeter', 'MeterHerobrineApparition')
    SKIN:Bang('!CommandMeasure', 'MeasureHerobrine', 'ReflowApparition()')
end

local INDICATOR_RENDER_MEASURES = {
    'MeasureGaugeRatio',
    'MeasureGaugeRenderedWidth',
    'MeasureGaugeRenderedHeight',
    'MeasureGaugeImageOffset',
    'MeasureGaugeFillWidth',
    'MeasureGaugeTopCropWidth',
    'MeasureGaugeX',
}

local EXP_TEXT_METERS = {
    'MeterTexto',
    'MeterTexto2',
    'MeterTexto3',
    'MeterTexto4',
    'MeterText',
}

local function updateIndicatorRenderConsumers(SKIN, id)
    for _, measureName in ipairs(INDICATOR_RENDER_MEASURES) do
        SKIN:Bang('!UpdateMeasure', measureName)
    end
    if id == 'IndicatorExp' then
        SKIN:Bang('!UpdateMeasure', 'MeasureExp')
    end
    SKIN:Bang('!UpdateMeter', 'MeterGaugeBottom')
    SKIN:Bang('!UpdateMeter', 'MeterGaugeTop')
    if id == 'IndicatorExp' then
        for _, meterName in ipairs(EXP_TEXT_METERS) do
            SKIN:Bang('!UpdateMeter', meterName)
        end
    end
    SKIN:Bang('!Redraw')
end

local function applyIndicatorVars(SKIN, id, rect)
    local m = rect.metrics
    if id == 'IndicatorExp' then
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
        setVariableForConfig(SKIN, 'GaugeY', m.gaugeY)
        setVariableForConfig(SKIN, 'ExpGaugeY', m.gaugeY)
        setVariableForConfig(SKIN, 'ExpTextX', m.textX)
        setVariableForConfig(SKIN, 'ExpTextY', m.textY)
        setVariableForConfig(SKIN, 'ExpTextFontSize', m.textFontSize)
    else
        setVariableForConfig(SKIN, 'DEFAULT_SIZE_RATIO', m.sizeRatio)
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
    end
    updateIndicatorRenderConsumers(SKIN, id)
end

local function setMirrorTargetVariable(SKIN, targetConfig, name, value)
    setVariableForConfig(SKIN, name, value, targetConfig)
end

function M.ApplyMirrorTarget(SKIN, id, rect, targetConfig)
    targetConfig = trim(targetConfig or '')
    if targetConfig == '' or not rect or not M.IsMirrorTarget or not M.IsMirrorTarget(id) then
        return nil
    end

    local monitor = rect.monitor
    local work = rect.workArea or (monitor and monitor.work) or nil
    local rawWork = rect.rawWorkArea or (monitor and monitor.rawWork) or work
    if not monitor or not work or not rawWork then
        return nil
    end

    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedMonitorFingerprint', monitor.fingerprint)
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedMonitorIndex', monitor.index)
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkX', round(work.x))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkY', round(work.y))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkWidth', round(work.width))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkHeight', round(work.height))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedX', round(rect.x))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedY', round(rect.y))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedWidth', round(rect.width))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedHeight', round(rect.height))

    local metrics = rect.metrics or {}
    if id == 'Hotbar' then
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarSlotSize', metrics.slotSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarTextYOffset', metrics.textYOffset)
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarTextFontSize', metrics.textFontSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarItemSizeOffset', metrics.itemOffset)
    elseif id == 'Clock' then
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockCenterX', metrics.centerX)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTimeTextSize', metrics.timeSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockDateTextSize', metrics.dateSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextGap', metrics.textGap)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextShadowYOffset', metrics.shadowYOffset)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockDateTextShadowYOffset', metrics.dateShadowYOffset)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextShadowBlur', metrics.shadowBlur)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextEffectTopInset', metrics.effectTopInset)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextEffectBottomExtent', metrics.effectBottomExtent)
    elseif id == 'ClockSprite' then
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockSpriteRenderSize', metrics.size)
    elseif tostring(id):find('^Indicator') then
        setMirrorTargetVariable(SKIN, targetConfig, 'SizeRatio', metrics.sizeRatio)
        if id == 'IndicatorExp' then
            setMirrorTargetVariable(SKIN, targetConfig, 'GaugeY', metrics.gaugeY)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpGaugeY', metrics.gaugeY)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpTextX', metrics.textX)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpTextY', metrics.textY)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpTextFontSize', metrics.textFontSize)
        else
            setMirrorTargetVariable(SKIN, targetConfig, 'DEFAULT_SIZE_RATIO', metrics.sizeRatio)
        end
    end

    SKIN:Bang('!Move', tostring(round(rect.x)), tostring(round(rect.y)), targetConfig)
    return {
        id = id,
        config = targetConfig,
        x = round(rect.x),
        y = round(rect.y),
        width = round(rect.width),
        height = round(rect.height),
        monitorFingerprint = monitor.fingerprint,
        monitorIndex = monitor.index,
    }
end

function M.ApplyCurrentSkin(SKIN, options, snapshot)
    local id = M.CurrentSkinId(SKIN)
    if not id then
        return nil
    end
    if type(options) == 'table' and options.snapshot then
        snapshot = options.snapshot
    end
    local ownerRectOverrides = type(options) == 'table' and options.ownerRectOverrides or nil
    local forcedMonitors = type(options) == 'table' and options.forcedMonitors or nil
    local rects = M.ResolveRects(SKIN, snapshot, ownerRectOverrides, forcedMonitors)
    local rect = rects[id]
    if not rect then
        return nil
    end

    if id == 'Hotbar' then
        applyHotbarVars(SKIN, rect)
        SKIN:Bang('!CommandMeasure', 'MeasureHotbarLayout', 'ApplyLayout()')
        syncSelectedHighlight(SKIN)
    elseif id == 'Inventory' then
        applyInventoryVars(SKIN, rect)
        setMeterOption(SKIN, 'MeterInventory', 'W', rect.metrics.width)
        setMeterOption(SKIN, 'MeterInventory', 'H', rect.metrics.height)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'X', rect.metrics.settingsButtonX)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'Y', rect.metrics.settingsButtonY)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'W', rect.metrics.settingsButtonW)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'H', rect.metrics.settingsButtonH)
        setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'Hidden', rect.metrics.workProgressEnabled and 0 or 1)
        if rect.metrics.workProgressEnabled then
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'X', rect.metrics.workProgressButtonX)
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'Y', rect.metrics.workProgressButtonY)
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'W', rect.metrics.workProgressButtonW)
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'H', rect.metrics.workProgressButtonH)
        end
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'X', rect.metrics.refreshButtonX)
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'Y', rect.metrics.refreshButtonY)
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'W', rect.metrics.refreshButtonW)
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'H', rect.metrics.refreshButtonH)
        setMeterOption(SKIN, 'MeterOpenInfo', 'X', rect.metrics.usageGuideX)
        setMeterOption(SKIN, 'MeterOpenInfo', 'Y', rect.metrics.usageGuideY)
        setMeterOption(SKIN, 'MeterOpenInfo', 'W', rect.metrics.usageGuideW)
        setMeterOption(SKIN, 'MeterOpenInfo', 'H', rect.metrics.usageGuideH)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'X', rect.metrics.steveSkinEditButtonX)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'Y', rect.metrics.steveSkinEditButtonY)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'W', rect.metrics.steveSkinEditButtonW)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'H', rect.metrics.steveSkinEditButtonH)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'X', rect.metrics.skinFolderX)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'Y', rect.metrics.skinFolderY)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'W', rect.metrics.skinFolderW)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'H', rect.metrics.skinFolderH)
        setMeterOption(SKIN, 'MeterEdit', 'X', rect.metrics.editButtonX)
        setMeterOption(SKIN, 'MeterEdit', 'Y', rect.metrics.editButtonY)
        setMeterOption(SKIN, 'MeterEdit', 'W', rect.metrics.editButtonW)
        setMeterOption(SKIN, 'MeterEdit', 'H', rect.metrics.editButtonH)
        setMeterOption(SKIN, 'MeterInventoryClose', 'X', rect.metrics.inventoryCloseButtonX)
        setMeterOption(SKIN, 'MeterInventoryClose', 'Y', rect.metrics.inventoryCloseButtonY)
        setMeterOption(SKIN, 'MeterInventoryClose', 'W', rect.metrics.inventoryCloseButtonW)
        setMeterOption(SKIN, 'MeterInventoryClose', 'H', rect.metrics.inventoryCloseButtonH)
        setMeterOption(SKIN, 'MeterEditorModeBadgeBackground', 'X', round((rect.metrics.width - rect.metrics.badgeW) / 2))
        setMeterOption(SKIN, 'MeterEditorModeBadgeBackground', 'Y', rect.metrics.badgeY)
        setMeterOption(SKIN, 'MeterEditorModeBadgeLabel', 'X', round((rect.metrics.width - rect.metrics.badgeW) / 2) + round(rect.metrics.badgeW / 2))
        setMeterOption(SKIN, 'MeterEditorModeBadgeLabel', 'Y', rect.metrics.badgeY + round(rect.metrics.badgeH / 2))
        setMeterOption(SKIN, 'MeterEditorModeBadgeLabel', 'FontSize', rect.metrics.badgeFontSize)
        SKIN:Bang('!UpdateMeterGroup', 'ResidentUpdateInventory')
        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()')
        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()')
        syncSelectedHighlight(SKIN)
        SKIN:Bang('!Redraw')
    elseif id == 'Clock' then
        applyClockVars(SKIN, rect)
    elseif id == 'ClockSprite' then
        applyClockSpriteVars(SKIN, rect)
    elseif id == 'Jukebox' then
        applyJukeboxVars(SKIN, rect)
    elseif id == 'JukeboxDiscSlot' then
        applyJukeboxDiscSlotVars(SKIN, rect)
    elseif id == 'Herobrine' then
        applyHerobrineVars(SKIN, rect)
    elseif id:find('^Indicator') then
        applyIndicatorVars(SKIN, id, rect)
    elseif id == 'InventoryBG' then
        setVariableForConfig(SKIN, 'InventoryBGWidth', rect.width)
        setVariableForConfig(SKIN, 'InventoryBGHeight', rect.height)
        SKIN:Bang('!UpdateMeter', 'MeterBackground')
        SKIN:Bang('!Redraw')
    end

    if id ~= 'Herobrine' then
        applyWindowMove(SKIN, id, rect)
        local persistWindowPosition = options ~= false and options ~= 0
        if type(options) == 'table' and options.persistWindowPosition == false then
            persistWindowPosition = false
        end
        if persistWindowPosition and not rect.fallbackActive then
            syncRainmeterWindowPosition(SKIN, id, rect.x, rect.y, true)
        end
    end

    return {
        id = id,
        x = round(rect.x),
        y = round(rect.y),
        width = round(rect.width),
        height = round(rect.height),
        rects = rects,
    }
end

function M.ReflowTargets(SKIN, ids, options)
    local rootConfig = getRootConfig(SKIN)
    if rootConfig == '' then
        return
    end
    local currentId = M.CurrentSkinId(SKIN)
    local forceRefresh = options == true or (type(options) == 'table' and options.forceRefresh == true)
    for _, id in ipairs(ids or {}) do
        local definition = SKINS[id]
        if definition and (forceRefresh or id == currentId or M.IsSkinActive(SKIN, id)) then
            SKIN:Bang('!Refresh', rootConfig .. '\\' .. definition.config, definition.file)
        end
    end
end  local function normalizedStateTargetIds(ids)
    local targets = {}
    local seen = {}
    for _, id in ipairs(ids or {}) do
        if id ~= 'InventoryBG' and SKINS[id] and not seen[id] then
            targets[#targets + 1] = id
            seen[id] = true
        end
    end
    return targets
end

function M.SetPositionModeForIds(SKIN, ids, mode)
    local resolvedMode = normalizePositionMode(mode)
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        local fallbackBlocked = resolvedMode == 'fixed' and M.IsMonitorFallback(SKIN, id)
        if state and not fallbackBlocked and normalizePositionMode(state.PositionMode) ~= resolvedMode then
            state.PositionMode = resolvedMode
            M.WriteState(SKIN, id, state, true)
        end
    end
end

function M.ClearFixedPositionsForIds(SKIN, ids)
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        if state then
            state.FixedX = '0'
            state.FixedY = '0'
            state.MonitorFingerprint = ''
            state.MonitorRelativeX = ''
            state.MonitorRelativeY = ''
            M.WriteState(SKIN, id, state, true)
        end
    end
end

local function formatRelative(value)
    return string.format('%.12g', tonumber(value) or 0)
end

local function relativeCoordinate(position, workStart, workSize, windowSize)
    local span = (tonumber(workSize) or 0) - (tonumber(windowSize) or 0)
    if span == 0 then
        return 0
    end
    return ((tonumber(position) or 0) - (tonumber(workStart) or 0)) / span
end

local function logicalRectGeometry(id, rect)
    if not rect then
        return nil
    end
    if id == 'JukeboxDiscSlot' then
        return {
            x = rect.visibleLeft or rect.x,
            y = rect.visibleTop or rect.y,
            width = rect.metrics and rect.metrics.visibleWidth or rect.width,
            height = rect.metrics and rect.metrics.visibleHeight or rect.height,
            probeX = rect.x,
            probeY = rect.y,
            probeWidth = rect.width,
            probeHeight = rect.height,
        }
    end
    return {
        x = rect.x,
        y = rect.y,
        width = rect.width,
        height = rect.height,
        probeX = rect.x,
        probeY = rect.y,
        probeWidth = rect.width,
        probeHeight = rect.height,
    }
end

local function logicalSizeForMonitor(SKIN, id, monitor)
    local targetScale = monitor and monitor.scale or M.GetScale(SKIN)
    local metrics = nil
    if id == 'Hotbar' then
        metrics = getHotbarMetrics(SKIN, targetScale, getIndicatorUserScale(SKIN))
        return metrics.windowWidth, metrics.windowHeight, metrics
    elseif id == 'Inventory' then
        metrics = getInventoryMetrics(SKIN, targetScale)
    elseif id == 'Clock' then
        metrics = getClockMetrics(SKIN, targetScale)
    elseif id == 'ClockSprite' then
        metrics = getClockSpriteMetrics(SKIN, targetScale)
    elseif id == 'Jukebox' then
        metrics = getJukeboxMetrics(SKIN, M.GetScale(SKIN))
    elseif id == 'JukeboxDiscSlot' then
        metrics = getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
        return metrics.visibleWidth, metrics.visibleHeight, metrics
    elseif id == 'Herobrine' then
        metrics = getHerobrineMetrics(SKIN, targetScale)
    elseif id == 'Settings' or id == 'Editor' then
        metrics = getPanelMetrics(id, targetScale)
    elseif id:find('^Indicator') then
        metrics = getIndicatorMetrics(id, targetScale, getIndicatorUserScale(SKIN))
    end
    if metrics then
        return metrics.width, metrics.height, metrics
    end
    return nil, nil, nil
end

function M.CommitFixedPosition(SKIN, id, desiredX, desiredY, probeX, probeY, probeWidth, probeHeight, logicalWidth, logicalHeight, snapshot)
    if not id or id == 'InventoryBG' or not SKINS[id] then
        return false, nil
    end
    local x = tonumber(desiredX)
    local y = tonumber(desiredY)
    if x == nil or y == nil then
        return false, nil
    end

    local state = M.GetState(SKIN, id)
    if not state then
        return false, nil
    end
    local rects = nil
    local geometry = nil
    if tonumber(probeWidth) == nil or tonumber(probeHeight) == nil
        or tonumber(logicalWidth) == nil or tonumber(logicalHeight) == nil then
        rects = M.ResolveRects(SKIN, snapshot)
        geometry = logicalRectGeometry(id, rects and rects[id])
    end

    local provisionalLogicalWidth = math.max(1, tonumber(logicalWidth) or (geometry and geometry.width) or tonumber(probeWidth) or 1)
    local provisionalLogicalHeight = math.max(1, tonumber(logicalHeight) or (geometry and geometry.height) or tonumber(probeHeight) or 1)
    local resolvedProbeX = tonumber(probeX)
    local resolvedProbeY = tonumber(probeY)
    local resolvedProbeWidth = math.max(1, tonumber(probeWidth) or (geometry and geometry.probeWidth) or provisionalLogicalWidth)
    local resolvedProbeHeight = math.max(1, tonumber(probeHeight) or (geometry and geometry.probeHeight) or provisionalLogicalHeight)
    if resolvedProbeX == nil then
        if id == 'JukeboxDiscSlot' and geometry then
            resolvedProbeX = x - ((geometry.x or 0) - (geometry.probeX or 0))
        else
            resolvedProbeX = x
        end
    end
    if resolvedProbeY == nil then
        resolvedProbeY = y
    end

    local monitorSnapshot = rects and rects.MonitorSnapshot or snapshot or M.SnapshotMonitors(SKIN)
    local probe = buildRect(resolvedProbeX, resolvedProbeY, resolvedProbeWidth, resolvedProbeHeight)
    local affinityFallback, _, affinityIsFallback = affinityMonitor(monitorSnapshot, state)
    if affinityIsFallback then
        return false, nil
    end
    local monitor = M.SelectMonitorForRect(monitorSnapshot, probe, affinityFallback or monitorSnapshot.primary)
    local targetLogicalWidth, targetLogicalHeight, targetMetrics = logicalSizeForMonitor(SKIN, id, monitor)
    local storedX = x
    local storedY = y
    if id == 'Clock' and targetMetrics then
        storedY = y + (tonumber(targetMetrics.effectTopInset) or 0)
        targetLogicalHeight = targetMetrics.contentHeight or targetLogicalHeight
    end
    local resolvedLogicalWidth = math.max(1, tonumber(targetLogicalWidth) or tonumber(logicalWidth) or (geometry and geometry.width) or resolvedProbeWidth)
    local resolvedLogicalHeight = math.max(1, tonumber(targetLogicalHeight) or tonumber(logicalHeight) or (geometry and geometry.height) or resolvedProbeHeight)
    local relativeX = relativeCoordinate(storedX, monitor.work.x, monitor.work.width, resolvedLogicalWidth)
    local relativeY = relativeCoordinate(storedY, monitor.work.y, monitor.work.height, resolvedLogicalHeight)
    local fixedX = tostring(round(storedX))
    local fixedY = tostring(round(storedY))
    local affinity = {
        MonitorFingerprint = monitor.fingerprint,
        MonitorRelativeX = formatRelative(relativeX),
        MonitorRelativeY = formatRelative(relativeY),
        monitor = monitor,
    }

    local changed = normalizePositionMode(state.PositionMode) ~= 'fixed'
        or tostring(state.FixedX or '') ~= fixedX
        or tostring(state.FixedY or '') ~= fixedY
        or tostring(state.MonitorFingerprint or '') ~= affinity.MonitorFingerprint
        or tostring(state.MonitorRelativeX or '') ~= affinity.MonitorRelativeX
        or tostring(state.MonitorRelativeY or '') ~= affinity.MonitorRelativeY
    if not changed then
        return false, affinity
    end

    state.PositionMode = 'fixed'
    state.FixedX = fixedX
    state.FixedY = fixedY
    state.MonitorFingerprint = affinity.MonitorFingerprint
    state.MonitorRelativeX = affinity.MonitorRelativeX
    state.MonitorRelativeY = affinity.MonitorRelativeY
    M.WriteState(SKIN, id, state, true, { syncRainmeterPosition = false })
    return true, affinity
end

function M.SetFixedPosition(SKIN, id, x, y)
    return M.CommitFixedPosition(SKIN, id, x, y)
end

function M.CaptureFixedPositionsForIds(SKIN, ids, positionsById)
    positionsById = positionsById or {}
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        local position = positionsById[id]
        if state and position then
            M.CommitFixedPosition(SKIN, id, position.x, position.y)
        end
    end
end

function M.AutoMonitorOwner(id)
    return AUTO_MONITOR_OWNER[id]
end

local function exportedMonitorContext(monitor, fallbackActive)
    local work = monitor.work
    local rawWork = monitor.rawWork
    return {
        Fingerprint = monitor.fingerprint,
        MonitorIndex = monitor.index,
        WorkX = round(work.x),
        WorkY = round(work.y),
        WorkWidth = round(work.width),
        WorkHeight = round(work.height),
        RawWorkX = round(rawWork.x),
        RawWorkY = round(rawWork.y),
        RawWorkWidth = round(rawWork.width),
        RawWorkHeight = round(rawWork.height),
        Scale = monitor.scale or M.ScaleForWorkArea(work),
        FallbackActive = fallbackActive == true,
    }
end

function M.CurrentMonitorContext(SKIN, id, x, y, width, height, snapshot)
    if tonumber(x) ~= nil and tonumber(y) ~= nil and tonumber(width) ~= nil and tonumber(height) ~= nil then
        snapshot = snapshot or M.SnapshotMonitors(SKIN)
        local fallback = snapshot.primary
        if id and SKINS[id] then
            local state = M.GetState(SKIN, id)
            local affinityFallback, _, affinityIsFallback = affinityMonitor(snapshot, state)
            if affinityFallback and not affinityIsFallback then
                fallback = affinityFallback
            end
        end
        local monitor = M.SelectMonitorForRect(snapshot, buildRect(x, y, width, height), fallback)
        local exported = exportedMonitorContext(monitor, false)
        if id == 'Jukebox' or id == 'JukeboxDiscSlot' then
            exported.Scale = M.GetScale(SKIN)
        end
        return exported
    end
    id = id or M.CurrentSkinId(SKIN)
    local rects = M.ResolveRects(SKIN, snapshot)
    local rect = rects and rects[id]
    if not rect or not rect.monitor then
        return exportedMonitorContext(rects.MonitorSnapshot.primary, false)
    end
    local exported = exportedMonitorContext(rect.monitor, rect.fallbackActive)
    if id == 'Jukebox' or id == 'JukeboxDiscSlot' then
        exported.Scale = M.GetScale(SKIN)
    end
    return exported
end

function M.ResolveInventoryLiveWindowPosition(SKIN)     local rects = M.ResolveRects(SKIN)     local inventory = rects and rects.Inventory     if not inventory then         return nil     end     return { x = round(inventory.x), y = round(inventory.y) } end  function M.LiveWindowPositionForId(SKIN, id, fallbackRects)
    if not SKINS[id] then
        return nil
    end
    local fallback = fallbackRects and fallbackRects[id]
    local function visiblePosition(position)
        if id ~= 'JukeboxDiscSlot' or not position then
            return position
        end
        local metrics = fallback and fallback.metrics or nil
        local work = fallback and fallback.workArea or nil
        local width = tonumber(position.width)
        local height = tonumber(position.height)
        if width and height then
            local snapshot = fallbackRects and fallbackRects.MonitorSnapshot or M.SnapshotMonitors(SKIN)
            local monitor = M.SelectMonitorForRect(snapshot, buildRect(position.x, position.y, width, height), snapshot.primary)
            metrics = getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
            work = monitor.work
        end
        metrics = metrics or getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
        local contentX = tonumber(metrics.contentX) or 0
        if width then
            local visibleWidth = tonumber(metrics.visibleWidth) or tonumber(metrics.width) or 1
            local actionGutter = tonumber(metrics.actionGutter or metrics.controlRightGutter) or 0
            local extraWidth = math.max(0, round(width - visibleWidth))
            local rightContentX = math.max(0, extraWidth - actionGutter)
            local rightVisibleX = (tonumber(position.x) or 0) + rightContentX
            if work and (rightVisibleX + visibleWidth + actionGutter) <= (work.right + 0.5) then
                contentX = rightContentX
            else
                contentX = extraWidth
            end
        end
        return {
            x = round((tonumber(position.x) or 0) + contentX),
            y = round(tonumber(position.y) or 0),
        }
    end
    local sameSkinPosition = sameSkinCurrentWindowPosition(SKIN, id)
    if sameSkinPosition then
        sameSkinPosition.width = tonumber(trim(SKIN:GetVariable('CURRENTCONFIGWIDTH', '')))
        sameSkinPosition.height = tonumber(trim(SKIN:GetVariable('CURRENTCONFIGHEIGHT', '')))
        return visiblePosition(sameSkinPosition)
    end
    local liveState = readLiveState(SKIN, id)
    if liveState and liveState.Active then
        if liveState.WindowX ~= nil and liveState.WindowY ~= nil then
            return visiblePosition({ x = liveState.WindowX, y = liveState.WindowY, width = liveState.Width, height = liveState.Height })
        end
        return nil
    end
    if fallback then
        if id == 'JukeboxDiscSlot' and fallback.visibleLeft ~= nil then
            return { x = fallback.visibleLeft, y = fallback.y }
        end
        return { x = fallback.x, y = fallback.y }
    end
    return nil
end

local function roundedWindowPosition(x, y)
    local numericX = tonumber(x)
    local numericY = tonumber(y)
    if numericX == nil or numericY == nil then
        return nil
    end
    return {
        x = round(numericX),
        y = round(numericY),
    }
end

local function resolvePositionForPersistence(SKIN, id, x, y, fallbackRects)
    local livePosition = M.LiveWindowPositionForId(SKIN, id, nil)
    if livePosition then
        return {
            x = round(tonumber(livePosition.x) or 0),
            y = round(tonumber(livePosition.y) or 0),
        }
    end
    local explicitPosition = roundedWindowPosition(x, y)
    if explicitPosition then
        return explicitPosition
    end
    local fallback = fallbackRects and fallbackRects[id]
    if fallback then
        return {
            x = round(tonumber(fallback.x) or 0),
            y = round(tonumber(fallback.y) or 0),
        }
    end
    return nil
end

local function sameRoundedPosition(left, right)
    if not left or not right then
        return false
    end
    return round(tonumber(left.x) or 0) == round(tonumber(right.x) or 0)
        and round(tonumber(left.y) or 0) == round(tonumber(right.y) or 0)
end

function M.ApplyPositionFixedState(SKIN, ids, isFixed)
    local targetIds = normalizedStateTargetIds(ids)
    if #targetIds == 0 then
        return
    end
    if not isFixed then
        M.SetPositionModeForIds(SKIN, targetIds, 'auto')
        M.ClearFixedPositionsForIds(SKIN, targetIds)
        M.ReflowTargets(SKIN, targetIds)
        return
    end

    local rects = M.ResolveRects(SKIN)
    local positionsById = {}
    for _, id in ipairs(targetIds) do
        local position = M.LiveWindowPositionForId(SKIN, id, rects)
        if position then
            positionsById[id] = position
        end
    end
    M.CaptureFixedPositionsForIds(SKIN, targetIds, positionsById)
    M.SetPositionModeForIds(SKIN, targetIds, 'fixed')
    M.ReflowTargets(SKIN, targetIds)
end

function M.PersistCurrentFixedPosition(SKIN, id, x, y)
    if not id or id == 'InventoryBG' or not SKINS[id] then
        return false
    end
    local state = M.GetState(SKIN, id)
    if not state then
        return false
    end

    local mode = normalizePositionMode(state.PositionMode)
    local fallbackRects = nil
    local position = resolvePositionForPersistence(SKIN, id, x, y, nil)
    if not position or mode ~= 'fixed' then
        fallbackRects = M.ResolveRects(SKIN)
        if not position then
            position = resolvePositionForPersistence(SKIN, id, x, y, fallbackRects)
        end
    end
    if not position then
        return false
    end

    if mode ~= 'fixed' then
        local fallback = fallbackRects and fallbackRects[id]
        if sameRoundedPosition(position, fallback) then
            return false
        end
    end

    fallbackRects = fallbackRects or M.ResolveRects(SKIN)
    local geometry = logicalRectGeometry(id, fallbackRects and fallbackRects[id])
    local probeX = position.x
    local probeY = position.y
    if id == 'JukeboxDiscSlot' and geometry then
        probeX = position.x - ((geometry.x or 0) - (geometry.probeX or 0))
    end
    return M.CommitFixedPosition(
        SKIN,
        id,
        position.x,
        position.y,
        probeX,
        probeY,
        geometry and geometry.probeWidth,
        geometry and geometry.probeHeight,
        geometry and geometry.width,
        geometry and geometry.height
    )
end

function M.CaptureCurrentSkinState(SKIN)     local id = M.CurrentSkinId(SKIN)     if not id then         return nil     end     return M.GetState(SKIN, id) end

TAB_TARGETS.jukebox = { 'Jukebox', 'JukeboxDiscSlot' }

return M
