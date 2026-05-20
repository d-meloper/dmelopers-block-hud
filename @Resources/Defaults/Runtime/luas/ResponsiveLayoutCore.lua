local M = {}  local BASE_SCREEN_WIDTH = 1920 local BASE_SCREEN_HEIGHT = 1080 local BASE_WORK_WIDTH = 1920 local BASE_WORK_HEIGHT = 1032 local AUTO_HIDE_BOTTOM_RESERVE = 48 local MIN_SCALE = 0.711 local MAX_SCALE = 1.333  local STATE_PREFIX = 'ResponsiveLayout_' local setVariableForConfig  local SKINS = {     Hotbar = {         id = 'Hotbar',         config = 'Hotbar',         file = 'Hotbar.ini',         anchor = 'BottomCenter',         reference = 'PrimaryWorkArea',         offsetX = -11,         offsetY = -39,         scaleMode = 'uniform',         dependentIds = { 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' },     },     IndicatorHeart = {         id = 'IndicatorHeart',         config = 'Indicators\\Heart',         file = 'Heart.ini',         anchor = 'HotbarVisibleLeftTop',         reference = 'Hotbar',         offsetX = -1,         offsetY = -59,         scaleMode = 'uniform',     },     IndicatorArmor = {         id = 'IndicatorArmor',         config = 'Indicators\\Armor',         file = 'Armor.ini',         anchor = 'HotbarVisibleLeftTop',         reference = 'Hotbar',         offsetX = -1,         offsetY = -93,         scaleMode = 'uniform',     },     IndicatorFood = {         id = 'IndicatorFood',         config = 'Indicators\\Food',         file = 'Food.ini',         anchor = 'HotbarVisibleRightTop',         reference = 'Hotbar',         offsetX = 2,         offsetY = -59,         scaleMode = 'uniform',     },     IndicatorAir = {         id = 'IndicatorAir',         config = 'Indicators\\Air',         file = 'Air.ini',         anchor = 'HotbarVisibleRightTop',         reference = 'Hotbar',         offsetX = 2,         offsetY = -93,         scaleMode = 'uniform',     },     IndicatorExp = {         id = 'IndicatorExp',         config = 'Indicators\\Exp',         file = 'Exp.ini',         anchor = 'HotbarVisibleCenterTop',         reference = 'Hotbar',         offsetX = 1,         offsetY = -63,         scaleMode = 'uniform',     },     Inventory = {         id = 'Inventory',         config = 'Inventory',         file = 'Inventory.ini',         anchor = 'ScreenCenter',         reference = 'PrimaryWorkArea',         offsetX = -354,         offsetY = -310,         scaleMode = 'uniform',         dependentIds = { 'Settings', 'Editor', 'InventoryBG', 'Hotbar' },     },     InventoryBG = {         id = 'InventoryBG',         config = 'InventoryBG',         file = 'InventoryBG.ini',         anchor = 'PrimaryWorkAreaFill',         reference = 'PrimaryWorkArea',         offsetX = 0,         offsetY = 0,         scaleMode = 'uniform',     },     Clock = {
        id = 'Clock',
        config = 'Clock',
        file = 'Clock.ini',
        anchor = 'TopCenter',
        reference = 'PrimaryWorkArea',
        offsetX = 13,
        offsetY = 176,
        scaleMode = 'uniform',
    },
    ClockSprite = {
        id = 'ClockSprite',
        config = 'ClockSprite',
        file = 'ClockSprite.ini',
        anchor = 'TopCenter',
        reference = 'PrimaryWorkArea',
        offsetX = -2,
        offsetY = 62,
        scaleMode = 'uniform',
    },
    Settings = {         id = 'Settings',         config = 'Settings',         file = 'Settings.ini',         anchor = 'InventoryLeftTop',         reference = 'Inventory',         offsetX = -350,         offsetY = 0,         scaleMode = 'uniform',         dependentIds = { 'Inventory' },     },     Editor = {         id = 'Editor',         config = 'Editor',         file = 'Editor.ini',         anchor = 'InventoryRightTop',         reference = 'Inventory',         offsetX = -4,         offsetY = 0,         scaleMode = 'uniform',         dependentIds = { 'Inventory', 'InventoryBG' },     }, }  local TAB_TARGETS = {     hotbar = { 'Hotbar' },     indicators = { 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' },     inventory = { 'Inventory', 'InventoryBG' },     clock = { 'Clock', 'ClockSprite' },     ui = { 'Hotbar', 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp', 'Inventory', 'InventoryBG', 'Clock', 'ClockSprite', 'Settings', 'Editor' }, }  local function trim(value)     local text = tostring(value or '')     text = text:gsub('^%s+', '')     text = text:gsub('%s+$', '')     return text end  local function numberOr(value, fallback)     local parsed = tonumber(value)     if parsed ~= nil then         return parsed     end     return tonumber(fallback) or 0 end  local function round(value)     if value >= 0 then         return math.floor(value + 0.5)     end     return math.ceil(value - 0.5) end  local function normalizeScale(value)     return tonumber(value) or 1 end  local function scaleNumber(value, scale, fallback)     return numberOr(value, fallback) * normalizeScale(scale) end  local function clamp(value, minValue, maxValue)     if value < minValue then         return minValue     end     if value > maxValue then         return maxValue     end     return value end  local function parseStoredNumber(raw, fallback)     local parsed = tonumber(trim(raw))     if parsed ~= nil then         return parsed     end     return tonumber(tostring(fallback or '')) or 0 end  local function liveStateVarName(id, field)     return STATE_PREFIX .. id .. '_Live' .. field end  local function readLiveState(SKIN, id)     if not id or id == '' then         return nil     end     return {         Active = trim(SKIN:GetVariable(liveStateVarName(id, 'Active'), '0')) == '1',         WindowX = tonumber(trim(SKIN:GetVariable(liveStateVarName(id, 'WindowX'), ''))),         WindowY = tonumber(trim(SKIN:GetVariable(liveStateVarName(id, 'WindowY'), ''))),     } end  local function currentConfigWindowPosition(SKIN)     return {         x = round(tonumber(trim(SKIN:GetVariable('CURRENTCONFIGX', '0'))) or 0),         y = round(tonumber(trim(SKIN:GetVariable('CURRENTCONFIGY', '0'))) or 0),     } end  local function sameSkinCurrentWindowPosition(SKIN, id)     if M.CurrentSkinId(SKIN) ~= id then         return nil     end     return currentConfigWindowPosition(SKIN) end  local function getRootConfigFromCurrentConfig(SKIN)
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
    if id ~= 'Inventory' then
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
        or normalizedAnchor == (id .. 'TextTopCenter')
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

local function activePeerTargetIds(SKIN, id)
    local targets = {}
    for _, targetId in ipairs(dependentTargetIds(id)) do
        local liveState = readLiveState(SKIN, targetId)
        if liveState and liveState.Active then
            targets[#targets + 1] = targetId
        end
    end
    return targets
end

local function broadcastLiveState(SKIN, id, active, x, y)
    local rootConfig = getRootConfig(SKIN)
    if rootConfig == '' then
        return
    end

    local values = {
        Active = active and '1' or '0',
        WindowX = tostring(round(tonumber(x) or 0)),
        WindowY = tostring(round(tonumber(y) or 0)),
    }

    for _, targetId in ipairs(activePeerTargetIds(SKIN, id)) do
        local definition = SKINS[targetId]
        local configName = rootConfig .. '\\' .. definition.config
        for field, value in pairs(values) do
            setVariableForConfig(SKIN, liveStateVarName(id, field), value, configName)
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

function M.WriteLiveState(SKIN, id, active, x, y, broadcast)
    if not id or not SKINS[id] then
        return false
    end

    local values = {
        Active = active and '1' or '0',
        WindowX = tostring(round(tonumber(x) or 0)),
        WindowY = tostring(round(tonumber(y) or 0)),
    }

    local path = M.StatePath(SKIN)
    for field, value in pairs(values) do
        local variableName = liveStateVarName(id, field)
        SKIN:Bang('!WriteKeyValue', 'Variables', variableName, tostring(value), path)
        setVariableForConfig(SKIN, variableName, value)
    end

    if id == 'Inventory' then
        syncRainmeterWindowPosition(SKIN, id, values.WindowX, values.WindowY, true)
    end

    if broadcast ~= false then
        broadcastLiveState(SKIN, id, active, x, y)
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
    }

    for _, targetId in ipairs(activePeerTargetIds(SKIN, id)) do
        local definition = SKINS[targetId]
        local configName = rootConfig .. '\\' .. definition.config
        for field, value in pairs(fields) do
            setVariableForConfig(SKIN, localVarName(id, field), value, configName)
        end
    end
end

function M.WriteState(SKIN, id, state, broadcast)
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
    }) do
        local variableName = localVarName(id, field)
        SKIN:Bang('!WriteKeyValue', 'Variables', variableName, tostring(value), path)
        setVariableForConfig(SKIN, variableName, value)
    end

    if id == 'Inventory' and M.ResolveRects then
        local rects = M.ResolveRects(SKIN)
        local inventory = rects and rects.Inventory
        if inventory then
            syncRainmeterWindowPosition(SKIN, id, inventory.x, inventory.y, true)
        end
    end

    if broadcast ~= false then
        M.BroadcastState(SKIN, id, normalizedState)
    end
end

function M.ResetStateIds(SKIN, ids)
    for _, id in ipairs(ids or {}) do
        local baseline = M.BaselineState(id)
        if baseline then
            M.WriteState(SKIN, id, baseline, true)
        end
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

local function currentWorkArea(SKIN)
    return effectivePrimaryWorkArea(SKIN)
end

function M.GetScale(SKIN)
    local work = effectivePrimaryWorkArea(SKIN)
    local xRatio = work.width / BASE_WORK_WIDTH
    local yRatio = work.height / BASE_WORK_HEIGHT
    return clamp(math.min(xRatio, yRatio), MIN_SCALE, MAX_SCALE)
end

local function usesFixedPosition(state)
    return trim(state and state.PositionMode or 'auto') == 'fixed'
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
local INVENTORY_PLAYER_CUSTOM_WIDTH_BASE = 111
local INVENTORY_PLAYER_CUSTOM_HEIGHT_BASE = 221
local INVENTORY_PLAYER_CUSTOM_BIAS_X_RATIO = 0.03
local function isWorkProgressEnabled(SKIN)     return trim(SKIN:GetVariable('EnableWorkProgress', '1')) ~= '0' end  local function getInventoryMetrics(SKIN, scale)
    local width = round(baseNumber(SKIN, 'InventoryWidth', 708) * scale)
    local height = round(baseNumber(SKIN, 'InventoryHeight', 668) * scale)
    local playerOffsetX = round(INVENTORY_PLAYER_OFFSET_X_BASE * scale)
    local playerOffsetY = round(INVENTORY_PLAYER_OFFSET_Y_BASE * scale)
    local playerWidth = round(INVENTORY_PLAYER_WIDTH_BASE * scale)
    local playerHeight = round(INVENTORY_PLAYER_HEIGHT_BASE * scale)
    local playerCustomWidth = round(INVENTORY_PLAYER_CUSTOM_WIDTH_BASE * scale)
    local playerCustomHeight = round(INVENTORY_PLAYER_CUSTOM_HEIGHT_BASE * scale)
    local playerCustomOffsetX = playerOffsetX + round(((playerWidth - playerCustomWidth) / 2) + (playerWidth * INVENTORY_PLAYER_CUSTOM_BIAS_X_RATIO))
    local playerCustomOffsetY = playerOffsetY + round((playerHeight - playerCustomHeight) / 2)
    local workProgressEnabled = isWorkProgressEnabled(SKIN)
    local normalRefreshButtonX = (width - round(16 * scale) - round(44 * scale)) - round(55 * scale) - round(12 * scale)
    local workProgressButtonBaseX = normalRefreshButtonX - round(55 * scale) - round(10 * scale)
    local workProgressButtonX = workProgressButtonBaseX + toNumber(SKIN, 'WorkProgressButtonOffsetX', 0)
    local refreshButtonBaseX = normalRefreshButtonX
    return {
        width = width,
        height = height,
        slotSize = round(baseNumber(SKIN, 'InventorySlotSize', 72) * scale),
        gridOffsetX = round(baseNumber(SKIN, 'InventoryGridOffsetX', 30) * scale),
        gridOffsetY = round(baseNumber(SKIN, 'InventoryGridOffsetY', 565) * scale),
        itemSize = round(baseNumber(SKIN, 'InventoryItemSize', 60) * scale),
        tooltipFontSize = math.max(8, round(baseNumber(SKIN, 'TooltipTextFontSize', 22) * scale)),
        playerOffsetX = playerOffsetX,
        playerOffsetY = playerOffsetY,
        playerWidth = playerWidth,
        playerHeight = playerHeight,
        playerCustomOffsetX = playerCustomOffsetX,
        playerCustomOffsetY = playerCustomOffsetY,
        playerCustomWidth = playerCustomWidth,
        playerCustomHeight = playerCustomHeight,
        settingsButtonX = round(535 * scale),
        settingsButtonY = round(256 * scale),
        settingsButtonW = round(70 * scale),
        settingsButtonH = round(70 * scale),
        optionY = round(262 * scale),
        usageGuideX = round(325 * scale) + toNumber(SKIN, 'UsageGuideOffsetX', 0),
        usageGuideY = round(262 * scale) - toNumber(SKIN, 'UsageGuideOffsetY', 0),
        usageGuideW = round(55 * scale),
        usageGuideH = round(55 * scale),
        skinFolderX = round(392 * scale) + toNumber(SKIN, 'SkinFolderOffsetX', 0),
        skinFolderY = round(262 * scale) - toNumber(SKIN, 'SkinFolderOffsetY', 0),
        skinFolderW = round(70 * scale),
        skinFolderH = round(70 * scale),
        workProgressButtonW = round(55 * scale),
        workProgressButtonH = round(55 * scale),
        workProgressEnabled = workProgressEnabled,
        workProgressButtonX = workProgressButtonX,
        workProgressButtonY = round(16 * scale) + round((round(44 * scale) - round(55 * scale)) / 2) + toNumber(SKIN, 'WorkProgressButtonOffsetY', 0),
        refreshButtonW = round(55 * scale),
        refreshButtonH = round(55 * scale),
        refreshButtonX = refreshButtonBaseX + toNumber(SKIN, 'RefreshButtonOffsetX', 0),
        refreshButtonY = round(16 * scale) + round((round(44 * scale) - round(55 * scale)) / 2) + toNumber(SKIN, 'RefreshButtonOffsetY', 0),
        editButtonX = round(614 * scale) + toNumber(SKIN, 'EditButtonOffsetX', 0),
        editButtonY = (round(262 * scale) - round(1 * scale)) - toNumber(SKIN, 'EditButtonOffsetY', 0),
        editButtonW = round(60 * scale),
        editButtonH = round(60 * scale),
        inventoryCloseButtonW = round(44 * scale),
        inventoryCloseButtonH = round(44 * scale),
        inventoryCloseButtonX = width - round(16 * scale) - round(44 * scale),
        inventoryCloseButtonY = round(16 * scale),
        badgeW = round(245 * scale),
        badgeH = round(40 * scale),
        badgeY = round(15 * scale),
        badgeFontSize = math.max(10, round(20 * scale)),
        rowExtraGap = round(16 * scale),
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
        local baseLowerRowHeight = 65 * 0.45
        local topGapCompensation = indicatorScale < 1 and math.max(round((1 - indicatorScale) * baseLowerRowHeight), 0) or 0
        local hotbarTopGap = 7 + topGapCompensation
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
    return {
        centerX = round(400 * scale),
        timeSize = math.max(16, round(baseNumber(SKIN, 'ClockTimeTextSize', 90) * scale)),
        dateSize = math.max(8, round(baseNumber(SKIN, 'ClockDateTextSize', 25) * scale)),
        textGap = round(baseNumber(SKIN, 'ClockTextGap', -5) * scale),
        width = round(800 * scale),
        height = round((baseNumber(SKIN, 'ClockTimeTextSize', 90) + baseNumber(SKIN, 'ClockDateTextSize', 25) + 48) * scale),
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

local function getPanelMetrics(id, scale)
    if id == 'Settings' then
        return {
            width = 360,
            height = 336,
        }
    end
    return {
        width = 320,
        height = 680,
    }
end

local function clampWindow(work, x, y, width, height)
    return round(clamp(x, work.x, math.max(work.x, work.right - width))),
        round(clamp(y, work.y, math.max(work.y, work.bottom - height)))
end

local function resolveFixedWindow(SKIN, id, state, work, width, height)
    local rawX = round(parseStoredNumber(state.FixedX, 0))
    local rawY = round(parseStoredNumber(state.FixedY, 0))
    return rawX, rawY
end

function M.ResolveRects(SKIN)
    local work = effectivePrimaryWorkArea(SKIN)
    local scale = normalizeScale(M.GetScale(SKIN))
    local indicatorUserScale = getIndicatorUserScale(SKIN)
    local rects = {}

    do
        local state = M.GetState(SKIN, 'Hotbar')
        local metrics = getHotbarMetrics(SKIN, scale, indicatorUserScale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Hotbar', state, work, metrics.windowWidth, metrics.windowHeight)
        else
            local visibleCenterX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0)
            local visibleBottomY = work.bottom + scaleNumber(state.OffsetYBase, scale, 0)
            rawX = visibleCenterX - (metrics.visibleLeft + (metrics.hotbarWidth / 2))
            rawY = visibleBottomY - (metrics.visibleTop + metrics.hotbarHeight)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.windowWidth, metrics.windowHeight)
        end
        rects.Hotbar = {
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = scale,
            metrics = metrics,
            visibleLeft = rawX + metrics.visibleLeft,
            visibleTop = rawY + metrics.visibleTop,
            visibleRight = rawX + metrics.visibleLeft + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleTop + metrics.visibleHeight,
            visibleCenterX = rawX + metrics.visibleLeft + (metrics.visibleWidth / 2),
            indicatorAnchorLeft = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) - (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorRight = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) + (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorTop = (rawY + metrics.visibleTop + metrics.visibleHeight) - metrics.indicatorAnchorSlotSize,
        }
    end

    do
        local state = M.GetState(SKIN, 'Inventory')
        local metrics = getInventoryMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Inventory', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0)
            rawY = work.centerY + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Inventory = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
            leftTopX = rawX,
            leftTopY = rawY,
            rightTopX = rawX + metrics.width,
            rightTopY = rawY,
        }
    end

    do
        local rawWork = work.raw or rawPrimaryWorkArea(SKIN)
        rects.InventoryBG = {
            x = rawWork.x,
            y = rawWork.y,
            width = rawWork.width,
            height = rawWork.height,
            scale = scale,
        }
    end

    do
        local state = M.GetState(SKIN, 'Clock')
        local metrics = getClockMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Clock', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0) - metrics.centerX
            rawY = work.y + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Clock = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    do
        local state = M.GetState(SKIN, 'ClockSprite')
        local metrics = getClockSpriteMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'ClockSprite', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0) - round(metrics.width / 2)
            rawY = work.y + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.ClockSprite = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    for _, indicatorId in ipairs({ 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' }) do
        local state = M.GetState(SKIN, indicatorId)
        local metrics = getIndicatorMetrics(indicatorId, scale, indicatorUserScale)
        local hotbar = rects.Hotbar
        local indicatorLayoutScale = resolvedIndicatorScale(scale, indicatorUserScale)
        local edgeInset = indicatorLayoutScale < 1 and round((1 - indicatorLayoutScale) * 10) or 0
        local definition = SKINS[indicatorId] or {}
        local offsetXBase = tonumber(state.OffsetXBase) or tonumber(definition.offsetX) or 0
        local offsetYBase = tonumber(state.OffsetYBase) or tonumber(definition.offsetY) or 0
        local commonIndicatorY = hotbar.indicatorAnchorTop + (offsetYBase * indicatorLayoutScale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, indicatorId, state, work, metrics.width, metrics.height + (metrics.gaugeY or 0))
        else
            if state.AnchorKind == 'HotbarVisibleLeftTop' then
                rawX = hotbar.indicatorAnchorLeft + (offsetXBase * indicatorLayoutScale) + edgeInset
                rawY = commonIndicatorY
            elseif state.AnchorKind == 'HotbarVisibleRightTop' then
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
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height + (metrics.gaugeY or 0))
        end
        rects[indicatorId] = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    for _, panelId in ipairs({ 'Settings', 'Editor' }) do
        local state = M.GetState(SKIN, panelId)
        local metrics = getPanelMetrics(panelId, scale)
        local inventory = rects.Inventory
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, panelId, state, work, metrics.width, metrics.height)
        else
            if state.AnchorKind == 'InventoryLeftTop' then
                rawX = inventory.leftTopX + scaleNumber(state.OffsetXBase, scale, 0)
            else
                rawX = inventory.rightTopX + scaleNumber(state.OffsetXBase, scale, 0)
            end
            rawY = inventory.leftTopY + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects[panelId] = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    rects.PrimaryWorkArea = work
    rects.Scale = scale
    return rects
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
end

local function applyClockSpriteVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'ClockSpriteSize', m.size)
    SKIN:Bang('!UpdateMeter', 'MeterClockSprite')
end


local function applyIndicatorVars(SKIN, id, rect)
    local m = rect.metrics
    if id == 'IndicatorExp' then
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
        setVariableForConfig(SKIN, 'ExpGaugeY', m.gaugeY)
        setVariableForConfig(SKIN, 'ExpTextX', m.textX)
        setVariableForConfig(SKIN, 'ExpTextY', m.textY)
        setVariableForConfig(SKIN, 'ExpTextFontSize', m.textFontSize)
    else
        setVariableForConfig(SKIN, 'DEFAULT_SIZE_RATIO', m.sizeRatio)
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
    end
end

function M.ApplyCurrentSkin(SKIN)
    local id = M.CurrentSkinId(SKIN)
    if not id then
        return nil
    end
    local rects = M.ResolveRects(SKIN)
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
        for _, meterName in ipairs({
            'MeterInventory',
            'MeterPlayerDefault',
            'MeterPlayerCustom',
            'MeterSettingsUIButton',
            'MeterRefreshUIButton',
            'MeterOpenInfo',
            'MeterOpenSkinFolder',
            'MeterEdit',
            'MeterInventoryClose',
            'MeterEditorModeBadgeBackground',
            'MeterEditorModeBadgeLabel',
        }) do
            SKIN:Bang('!UpdateMeter', meterName)
        end
        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()')
        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()')
        syncSelectedHighlight(SKIN)
    elseif id == 'Clock' then
        applyClockVars(SKIN, rect)
    elseif id == 'ClockSprite' then
        applyClockSpriteVars(SKIN, rect)
    elseif id:find('^Indicator') then
        applyIndicatorVars(SKIN, id, rect)
    elseif id == 'InventoryBG' then
        setVariableForConfig(SKIN, 'InventoryBGWidth', rect.width)
        setVariableForConfig(SKIN, 'InventoryBGHeight', rect.height)
    end

    applyWindowMove(SKIN, id, rect)
    if id == 'Inventory' then
        syncRainmeterWindowPosition(SKIN, id, rect.x, rect.y, true)
    end

    return {
        id = id,
        x = round(rect.x),
        y = round(rect.y),
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
        if state then
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
            M.WriteState(SKIN, id, state, true)
        end
    end
end

function M.CaptureFixedPositionsForIds(SKIN, ids, positionsById)
    positionsById = positionsById or {}
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        local position = positionsById[id]
        if state and position then
            state.FixedX = tostring(round(tonumber(position.x) or 0))
            state.FixedY = tostring(round(tonumber(position.y) or 0))
            state.PositionMode = 'fixed'
            M.WriteState(SKIN, id, state, true)
        end
    end
end

function M.ResolveInventoryLiveWindowPosition(SKIN)     local rects = M.ResolveRects(SKIN)     local inventory = rects and rects.Inventory     if not inventory then         return nil     end     return { x = round(inventory.x), y = round(inventory.y) } end  function M.LiveWindowPositionForId(SKIN, id, fallbackRects)
    if not SKINS[id] then
        return nil
    end
    local sameSkinPosition = sameSkinCurrentWindowPosition(SKIN, id)
    if sameSkinPosition then
        return sameSkinPosition
    end
    local liveState = readLiveState(SKIN, id)
    if liveState and liveState.Active then
        if liveState.WindowX ~= nil and liveState.WindowY ~= nil then
            return { x = liveState.WindowX, y = liveState.WindowY }
        end
        return nil
    end
    local fallback = fallbackRects and fallbackRects[id]
    if fallback then
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

    local roundedX = tostring(position.x)
    local roundedY = tostring(position.y)
    if mode == 'fixed' and tostring(state.FixedX or '') == roundedX and tostring(state.FixedY or '') == roundedY then
        return false
    end

    state.PositionMode = 'fixed'
    state.FixedX = roundedX
    state.FixedY = roundedY
    M.WriteState(SKIN, id, state, true)
    return true
end

function M.CaptureCurrentSkinState(SKIN)     local id = M.CurrentSkinId(SKIN)     if not id then         return nil     end     return M.GetState(SKIN, id) end  return M

