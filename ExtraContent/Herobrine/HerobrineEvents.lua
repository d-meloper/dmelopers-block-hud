local M = {}
local INVENTORY_METER = 'MeterHerobrineInventory'
local INVENTORY_IMAGE = 'Defaults\\Runtime\\images\\herobrine\\herobrine_inventory.png'
local APPARITION_IMAGE = 'Defaults\\Runtime\\images\\herobrine\\herobrine_apparition.png'
local STATS_PATH = 'Customs\\Data\\HerobrineStats.inc'
local APPARITION_STATE_PATH = 'Customs\\Data\\HerobrineState.inc'
local INVENTORY_CHANCE_PERCENT = 10
local APPARITION_CHANCE_PERCENT = 5
local DEFAULT_APPARITION_W = 39
local DEFAULT_APPARITION_H = 57
local APPARITION_OWNER = 'HerobrineApparition'
local DRAG_OWNER = 'HerobrineDrag'
local DRAG_THRESHOLD_PX = 4
local APPARITION_CONFIG_SUFFIX = 'ExtraContent\\Herobrine'
local APPARITION_CONFIG_FILE = 'Herobrine.ini'
local HOTBAR_CONFIG_SUFFIX = 'HUD\\Hotbar'
local SETTINGS_CONFIG_SUFFIX = 'HUD\\Settings'
local STAT_KEYS = {
    total = 'HerobrineTotalAppearances',
    visibleSeconds = 'HerobrineVisibleSeconds',
    captures = 'HerobrineCaptures',
}
local APPARITION_STATE_KEYS = {
    active = 'HerobrineApparitionActive',
    x = 'HerobrineApparitionX',
    y = 'HerobrineApparitionY',
    w = 'HerobrineApparitionW',
    h = 'HerobrineApparitionH',
    messageIndex = 'HerobrineApparitionMessageIndex',
}
local INDICATOR_CONFIGS = {
    'HUD\\Indicators\\Heart',
    'HUD\\Indicators\\Armor',
    'HUD\\Indicators\\Food',
    'HUD\\Indicators\\Air',
    'HUD\\Indicators\\Exp',
}
local state = {
    randomSeeded = false,
    inventory = {
        active = false,
        lastTick = 0,
    },
    apparition = {
        active = false,
        lastTick = 0,
        lastWrite = 0,
        messageIndex = 0,
        message = '',
        imagePath = '',
        position = {
            x = 0,
            y = 0,
            w = DEFAULT_APPARITION_W,
            h = DEFAULT_APPARITION_H,
        },
        drag = {
            armed = false,
            active = false,
            startX = 0,
            startY = 0,
            message = '',
        },
    },
}
local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end
local function stripEncodingBytes(text)
    if not text or text == '' then
        return ''
    end
    local first = text:byte(1)
    local second = text:byte(2)
    local third = text:byte(3)
    if first == 255 and second == 254 then
        text = text:sub(3)
    elseif first == 239 and second == 187 and third == 191 then
        text = text:sub(4)
    end
    return text:gsub('%z', '')
end
local function normalizePath(path)
    return trim(path):gsub('/', '\\')
end
local function ensureTrailingSlash(path)
    path = trim(path)
    if path == '' then
        return ''
    end
    local last = path:sub(-1)
    if last ~= '\\' and last ~= '/' then
        path = path .. '\\'
    end
    return path
end
local function resourceRoot(skin)
    return ensureTrailingSlash(skin:GetVariable('@', ''))
end
local function rootConfigName(skin)
    return trim(skin:GetVariable('ROOTCONFIG', ''))
end
local function currentConfigName(skin)
    return trim(skin:GetVariable('CURRENTCONFIG', ''))
end
local function configName(skin, suffix)
    local root = rootConfigName(skin)
    if root == '' then
        return suffix
    end
    return root .. '\\' .. suffix
end
local function statsPath(skin)
    local root = resourceRoot(skin)
    if root == '' then
        return ''
    end
    return root .. STATS_PATH
end
local function apparitionStatePath(skin)
    local root = resourceRoot(skin)
    if root == '' then
        return ''
    end
    return root .. APPARITION_STATE_PATH
end
local function imagePath(skin, relativePath)
    local root = resourceRoot(skin)
    if root == '' then
        return ''
    end
    return root .. relativePath
end
local function resolveImagePath(skin, relativePath)
    return trim(imagePath(skin, relativePath))
end
local HerobrineConfigState = nil

local function herobrineConfigState(skin)
    if not HerobrineConfigState then
        HerobrineConfigState = dofile(skin:GetVariable('@', '') .. 'Defaults\\Runtime\\luas\\RainmeterConfigState.lua')
    end
    return HerobrineConfigState
end

local function isRainmeterConfigActive(skin, targetConfig)
    return herobrineConfigState(skin).IsActive(skin, targetConfig)
end
local function seedRandom(skin)
    if state.randomSeeded then
        return
    end
    local config = currentConfigName(skin)
    local hash = 0
    for index = 1, #config do
        hash = (hash + (config:byte(index) or 0) * index) % 100000
    end
    math.randomseed(os.time() + hash)
    math.random()
    math.random()
    math.random()
    state.randomSeeded = true
end
local function chancePassed(skin, percent)
    seedRandom(skin)
    percent = math.floor(tonumber(percent) or 0)
    if percent <= 0 then
        return false
    end
    if percent >= 100 then
        return true
    end
    return math.random(100) <= percent
end
local function boolLiteral(value, fallback)
    local normalized = trim(value)
    if normalized == '1' then
        return '1'
    end
    if normalized == '0' then
        return '0'
    end
    return fallback and '1' or '0'
end
local function isEnabled(skin)
    return trim(skin:GetVariable('EnableHerobrineSkin', '0')) == '1'
end
local function setVariable(skin, name, value, targetConfig)
    if targetConfig and targetConfig ~= '' then
        skin:Bang('!SetVariable', name, tostring(value or ''), targetConfig)
    else
        skin:Bang('!SetVariable', name, tostring(value or ''))
    end
end
local function parserNumber(skin, key)
    local raw = trim(skin:GetVariable(key, ''))
    if raw == '' then
        return 0
    end
    return math.max(0, math.floor(tonumber(raw) or 0))
end
local function parserInteger(skin, key, fallback)
    local raw = trim(skin:GetVariable(key, ''))
    if raw == '' or not raw:match('^-?%d+$') then
        return fallback
    end
    return math.floor(tonumber(raw) or fallback)
end
local function loadStats(skin)
    local stats = {}
    for _, key in pairs(STAT_KEYS) do
        stats[key] = parserNumber(skin, key)
    end
    return stats
end
local function syncStatVariables(skin, stats)
    local current = currentConfigName(skin)
    local targets = {
        current,
        configName(skin, HOTBAR_CONFIG_SUFFIX),
        configName(skin, 'HUD\\Inventory'),
        configName(skin, SETTINGS_CONFIG_SUFFIX),
        configName(skin, APPARITION_CONFIG_SUFFIX),
    }
    local seen = {}
    for _, key in pairs(STAT_KEYS) do
        local value = tostring(math.max(0, math.floor(tonumber(stats[key]) or 0)))
        setVariable(skin, key, value)
        for _, target in ipairs(targets) do
            if target ~= '' and not seen[target .. key] then
                if target == current or isRainmeterConfigActive(skin, target) then
                    setVariable(skin, key, value, target)
                end
                seen[target .. key] = true
            end
        end
    end
end
local function writeStats(skin, stats)
    local path = statsPath(skin)
    syncStatVariables(skin, stats)
    if path == '' then
        return
    end
    for _, key in pairs(STAT_KEYS) do
        local value = tostring(math.max(0, math.floor(tonumber(stats[key]) or 0)))
        skin:Bang('!WriteKeyValue', 'Variables', key, value, path)
    end
end
local function defaultApparitionState()
    return {
        [APPARITION_STATE_KEYS.active] = '0',
        [APPARITION_STATE_KEYS.x] = '0',
        [APPARITION_STATE_KEYS.y] = '0',
        [APPARITION_STATE_KEYS.w] = tostring(DEFAULT_APPARITION_W),
        [APPARITION_STATE_KEYS.h] = tostring(DEFAULT_APPARITION_H),
        [APPARITION_STATE_KEYS.messageIndex] = '0',
    }
end
local function syncApparitionStateVariables(skin, values)
    values = values or defaultApparitionState()
    local defaults = defaultApparitionState()
    for _, key in pairs(APPARITION_STATE_KEYS) do
        setVariable(skin, key, values[key] or defaults[key])
    end
end
local function writeApparitionState(skin, values)
    local path = apparitionStatePath(skin)
    values = values or defaultApparitionState()
    local defaults = defaultApparitionState()
    syncApparitionStateVariables(skin, values)
    if path == '' then
        return
    end
    for _, key in pairs(APPARITION_STATE_KEYS) do
        skin:Bang('!WriteKeyValue', 'Variables', key, tostring(values[key] or defaults[key]), path)
    end
end
local function clearApparitionState(skin)
    writeApparitionState(skin, defaultApparitionState())
end
local function recordAppearance(skin)
    local stats = loadStats(skin)
    stats[STAT_KEYS.total] = (stats[STAT_KEYS.total] or 0) + 1
    writeStats(skin, stats)
end
local function recordCapture(skin)
    local stats = loadStats(skin)
    stats[STAT_KEYS.captures] = (stats[STAT_KEYS.captures] or 0) + 1
    writeStats(skin, stats)
end
local function addVisibleSeconds(skin, seconds, forceWrite)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds <= 0 then
        return
    end
    local stats = loadStats(skin)
    stats[STAT_KEYS.visibleSeconds] = (stats[STAT_KEYS.visibleSeconds] or 0) + seconds
    syncStatVariables(skin, stats)
    local now = os.time()
    if forceWrite or state.apparition.lastWrite == 0 or now - state.apparition.lastWrite >= 10 then
        state.apparition.lastWrite = now
        writeStats(skin, stats)
    end
end
local function updateInventoryPlayerMeters(skin)
    skin:Bang('!UpdateMeasure', 'MeasurePlayerDefaultHidden')
    skin:Bang('!UpdateMeasure', 'MeasurePlayerCustomHidden')
    skin:Bang('!CommandMeasure', 'MeasureAnimation', 'Sync()')
end
local function hideInventoryReplacement(skin)
    if not state.inventory.active then
        setVariable(skin, 'HerobrineInventoryReplacementActive', '0')
        state.inventory.lastTick = 0
        return
    end
    local now = os.time()
    addVisibleSeconds(skin, math.max(0, now - (state.inventory.lastTick or now)), true)
    state.inventory.active = false
    state.inventory.lastTick = 0
    setVariable(skin, 'HerobrineInventoryReplacementActive', '0')
    skin:Bang('!HideMeter', INVENTORY_METER)
    skin:Bang('!SetOption', INVENTORY_METER, 'ImageName', '')
    updateInventoryPlayerMeters(skin)
    skin:Bang('!UpdateMeter', INVENTORY_METER)
    skin:Bang('!Redraw')
end
local function showInventoryReplacement(skin, path)
    state.inventory.active = true
    state.inventory.lastTick = os.time()
    setVariable(skin, 'HerobrineInventoryReplacementActive', '1')
    skin:Bang('!SetOption', INVENTORY_METER, 'ImageName', path)
    updateInventoryPlayerMeters(skin)
    skin:Bang('!UpdateMeter', INVENTORY_METER)
    skin:Bang('!ShowMeter', INVENTORY_METER)
    skin:Bang('!Redraw')
end
local function numberVariable(skin, name, fallback)
    local raw = trim(skin:GetVariable(name, tostring(fallback or 0)))
    local value = tonumber(raw)
    if value == nil then
        return tonumber(fallback) or 0
    end
    return value
end
local function round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end
local function randomBetween(minValue, maxValue)
    minValue = math.floor(tonumber(minValue) or 0)
    maxValue = math.floor(tonumber(maxValue) or minValue)
    if maxValue <= minValue then
        return minValue
    end
    return minValue + math.random(maxValue - minValue + 1) - 1
end
local function currentApparitionMetrics(skin)
    local w = math.max(1, math.floor(numberVariable(skin, 'HerobrineApparitionRenderW', DEFAULT_APPARITION_W)))
    local h = math.max(1, math.floor(numberVariable(skin, 'HerobrineApparitionRenderH', DEFAULT_APPARITION_H)))
    return { w = w, h = h }
end

local function apparitionBounds(skin, w, h)
    local screenX = numberVariable(skin, 'PSCREENAREAX', numberVariable(skin, 'SCREENAREAX', 0))
    local screenY = numberVariable(skin, 'PSCREENAREAY', numberVariable(skin, 'SCREENAREAY', 0))
    local screenWidth = math.max(1, numberVariable(skin, 'PSCREENAREAWIDTH', numberVariable(skin, 'SCREENAREAWIDTH', 1920)))
    local screenHeight = math.max(1, numberVariable(skin, 'PSCREENAREAHEIGHT', numberVariable(skin, 'SCREENAREAHEIGHT', 1080)))
    local workX = numberVariable(skin, 'PWORKAREAX', screenX)
    local workY = numberVariable(skin, 'PWORKAREAY', screenY)
    local workWidth = math.max(1, numberVariable(skin, 'PWORKAREAWIDTH', screenWidth))
    local workHeight = math.max(1, numberVariable(skin, 'PWORKAREAHEIGHT', screenHeight))
    w = math.min(workWidth, math.max(1, math.floor(tonumber(w) or DEFAULT_APPARITION_W)))
    h = math.min(workHeight, math.max(1, math.floor(tonumber(h) or DEFAULT_APPARITION_H)))
    local margin = math.max(0, numberVariable(skin, 'HerobrineApparitionMargin', 12))
    local marginX = math.min(margin, math.floor(math.max(0, workWidth - w) / 2))
    local marginY = math.min(margin, math.floor(math.max(0, workHeight - h) / 2))
    local minX = workX + marginX
    local minY = workY + marginY
    local maxX = math.max(minX, workX + workWidth - w - marginX)
    local maxY = math.max(minY, workY + workHeight - h - marginY)
    return { minX = minX, minY = minY, maxX = maxX, maxY = maxY, w = round(w), h = round(h) }
end
local function clampApparitionPosition(skin, position)
    position = position or {}
    local metrics = currentApparitionMetrics(skin)
    local bounds = apparitionBounds(skin, metrics.w, metrics.h)
    local x = round(tonumber(position.x) or bounds.minX)
    local y = round(tonumber(position.y) or bounds.minY)
    x = math.max(bounds.minX, math.min(bounds.maxX, x))
    y = math.max(bounds.minY, math.min(bounds.maxY, y))
    return { x = round(x), y = round(y), w = bounds.w, h = bounds.h }
end
local function apparitionPosition(skin)
    seedRandom(skin)
    local metrics = currentApparitionMetrics(skin)
    local bounds = apparitionBounds(skin, metrics.w, metrics.h)
    return {
        x = round(randomBetween(bounds.minX, bounds.maxX)),
        y = round(randomBetween(bounds.minY, bounds.maxY)),
        w = bounds.w,
        h = bounds.h,
    }
end
local function messageForIndex(skin, index)
    index = ((math.floor(tonumber(index) or 1) - 1) % 4) + 1
    local key = 'Loc_Herobrine_ApparitionMessage' .. tostring(index)
    local fallbacks = {
        "You're not the only one here",
        'I am watching you',
        'Where am I?',
        'Do not leave me alone',
    }
    return trim(skin:GetVariable(key, fallbacks[index] or "You're not the only one here"))
end
local function messageForNextAppearance(skin)
    state.apparition.messageIndex = (state.apparition.messageIndex % 4) + 1
    return messageForIndex(skin, state.apparition.messageIndex)
end
local function randomDragMessage(skin)
    seedRandom(skin)
    local index = randomBetween(1, 6)
    local key = 'Loc_Herobrine_DragMessage' .. tostring(index)
    local fallbacks = {
        'Let go of me. I said let go.',
        "What are you doing? You'll regret this.",
        'Aah! Let me go already!',
        "Don't touch me!",
        "Stop messing around. You'll regret this.",
        'You think dragging me changes anything?',
    }
    return trim(skin:GetVariable(key, fallbacks[index] or fallbacks[1]))
end
local function sendHotbarBackgroundText(skin, text, owner)
    text = trim(text)
    owner = trim(owner)
    if owner == '' then
        owner = APPARITION_OWNER
    end
    if text == '' then
        return
    end
    local hotbarConfig = configName(skin, HOTBAR_CONFIG_SUFFIX)
    if not isRainmeterConfigActive(skin, hotbarConfig) then
        return
    end
    skin:Bang('!CommandMeasure', 'MeasureHighlight', string.format('ShowBackgroundHotbarText(%q,%q,%q)', owner, text, 'static'), hotbarConfig)
end
local function clearHotbarBackgroundText(skin, owner)
    owner = trim(owner)
    if owner == '' then
        owner = APPARITION_OWNER
    end
    local hotbarConfig = configName(skin, HOTBAR_CONFIG_SUFFIX)
    if not isRainmeterConfigActive(skin, hotbarConfig) then
        return
    end
    skin:Bang('!CommandMeasure', 'MeasureHighlight', string.format('ClearBackgroundHotbarText(%q)', owner), hotbarConfig)
end
local function clearDragHotbarText(skin, restoreApparitionText)
    local drag = state.apparition.drag
    drag.armed = false
    drag.active = false
    drag.startX = 0
    drag.startY = 0
    drag.message = ''
    clearHotbarBackgroundText(skin, DRAG_OWNER)
    if restoreApparitionText and state.apparition.active and state.apparition.message ~= '' then
        sendHotbarBackgroundText(skin, state.apparition.message, APPARITION_OWNER)
    end
end
local function setIndicatorForceZero(skin, enabled)
    local value = enabled and '1' or '0'
    for _, suffix in ipairs(INDICATOR_CONFIGS) do
        local target = configName(skin, suffix)
        if isRainmeterConfigActive(skin, target) then
            skin:Bang('!SetVariable', 'HerobrineIndicatorForceZero', value, target)
            skin:Bang('!Update', target)
            skin:Bang('!Redraw', target)
        end
    end
end
local function persistActiveApparitionState(skin, position)
    position = clampApparitionPosition(skin, position or state.apparition.position)
    state.apparition.position = position
    writeApparitionState(skin, {
        [APPARITION_STATE_KEYS.active] = '1',
        [APPARITION_STATE_KEYS.x] = tostring(position.x),
        [APPARITION_STATE_KEYS.y] = tostring(position.y),
        [APPARITION_STATE_KEYS.w] = tostring(position.w),
        [APPARITION_STATE_KEYS.h] = tostring(position.h),
        [APPARITION_STATE_KEYS.messageIndex] = tostring(state.apparition.messageIndex),
    })
end
local function applyApparitionVisual(skin, path, position)
    path = normalizePath(path)
    position = clampApparitionPosition(skin, position or state.apparition.position)
    state.apparition.position = position
    state.apparition.imagePath = path
    setVariable(skin, 'HerobrineApparitionImageName', path)
    setVariable(skin, 'HerobrineApparitionRenderW', position.w)
    setVariable(skin, 'HerobrineApparitionRenderH', position.h)
    skin:Bang('!Move', tostring(position.x), tostring(position.y))
    skin:Bang('!SetOption', 'MeterHerobrineApparition', 'ImageName', path)
    skin:Bang('!SetOption', 'MeterHerobrineApparition', 'W', tostring(position.w))
    skin:Bang('!SetOption', 'MeterHerobrineApparition', 'H', tostring(position.h))
    skin:Bang('!UpdateMeter', 'MeterHerobrineApparition')
    skin:Bang('!ShowMeter', 'MeterHerobrineApparition')
end

local function flushVisibleRuntimeEffects(skin)
    if state.apparition.active then
        local now = os.time()
        addVisibleSeconds(skin, math.max(0, now - (state.apparition.lastTick or now)), true)
        state.apparition.lastTick = now
    end
    clearDragHotbarText(skin, false)
    clearHotbarBackgroundText(skin, APPARITION_OWNER)
    setIndicatorForceZero(skin, false)
end
local function hideApparition(skin, captured)
    if not state.apparition.active then
        clearDragHotbarText(skin, false)
        clearHotbarBackgroundText(skin, APPARITION_OWNER)
        setIndicatorForceZero(skin, false)
        skin:Bang('!Hide')
        return false
    end
    local now = os.time()
    addVisibleSeconds(skin, math.max(0, now - (state.apparition.lastTick or now)), true)
    state.apparition.active = false
    state.apparition.lastTick = 0
    state.apparition.lastWrite = 0
    state.apparition.message = ''
    state.apparition.imagePath = ''
    local metrics = currentApparitionMetrics(skin)
    state.apparition.position = { x = 0, y = 0, w = metrics.w, h = metrics.h }
    clearApparitionState(skin)
    clearDragHotbarText(skin, false)
    clearHotbarBackgroundText(skin, APPARITION_OWNER)
    setIndicatorForceZero(skin, false)
    skin:Bang('!SetOption', 'MeterHerobrineApparition', 'ImageName', '')
    skin:Bang('!HideMeter', 'MeterHerobrineApparition')
    skin:Bang('!UpdateMeter', 'MeterHerobrineApparition')
    skin:Bang('!Hide')
    skin:Bang('!Redraw')
    if captured then
        recordCapture(skin)
    end
    return true
end
local function showApparition(skin, path)
    local position = apparitionPosition(skin)
    local message = messageForNextAppearance(skin)
    state.apparition.active = true
    state.apparition.lastTick = os.time()
    state.apparition.lastWrite = state.apparition.lastTick
    state.apparition.message = message
    state.apparition.position = position
    persistActiveApparitionState(skin, position)
    clearDragHotbarText(skin, false)
    applyApparitionVisual(skin, path, position)
    skin:Bang('!ClickThrough', '0')
    skin:Bang('!Show')
    skin:Bang('!Redraw')
    sendHotbarBackgroundText(skin, message, APPARITION_OWNER)
    setIndicatorForceZero(skin, true)
    recordAppearance(skin)
end
local function loadPersistedApparitionState(skin)
    local active = trim(skin:GetVariable(APPARITION_STATE_KEYS.active, '0'))
    if active ~= '1' then
        return nil
    end
    local x = parserInteger(skin, APPARITION_STATE_KEYS.x, nil)
    local y = parserInteger(skin, APPARITION_STATE_KEYS.y, nil)
    local w = parserInteger(skin, APPARITION_STATE_KEYS.w, nil)
    local h = parserInteger(skin, APPARITION_STATE_KEYS.h, nil)
    local messageIndex = parserInteger(skin, APPARITION_STATE_KEYS.messageIndex, nil)
    if x == nil or y == nil or w == nil or h == nil or messageIndex == nil or w <= 0 or h <= 0 then
        clearApparitionState(skin)
        return nil
    end
    return {
        position = clampApparitionPosition(skin, { x = x, y = y, w = w, h = h }),
        messageIndex = ((messageIndex - 1) % 4) + 1,
    }
end
local function restoreApparition(skin, path, persisted)
    local position = persisted.position
    state.apparition.active = true
    state.apparition.lastTick = os.time()
    state.apparition.lastWrite = state.apparition.lastTick
    state.apparition.messageIndex = persisted.messageIndex
    state.apparition.message = messageForIndex(skin, persisted.messageIndex)
    state.apparition.position = position
    persistActiveApparitionState(skin, position)
    clearDragHotbarText(skin, false)
    applyApparitionVisual(skin, path, position)
    skin:Bang('!ClickThrough', '0')
    skin:Bang('!Show')
    skin:Bang('!Redraw')
    sendHotbarBackgroundText(skin, state.apparition.message, APPARITION_OWNER)
    setIndicatorForceZero(skin, true)
    return true
end

local function setHerobrineEnabledVariables(skin, value)
    local targets = {
        currentConfigName(skin),
        configName(skin, HOTBAR_CONFIG_SUFFIX),
        configName(skin, 'HUD\\Inventory'),
        configName(skin, SETTINGS_CONFIG_SUFFIX),
        configName(skin, APPARITION_CONFIG_SUFFIX),
    }
    local seen = {}
    setVariable(skin, 'EnableHerobrineSkin', value)
    for _, target in ipairs(targets) do
        if target ~= '' and not seen[target] then
            if target == currentConfigName(skin) or isRainmeterConfigActive(skin, target) then
                setVariable(skin, 'EnableHerobrineSkin', value, target)
            end
            seen[target] = true
        end
    end
end
function M.RollInventoryReplacement(skin)
    if state.inventory.active or not isEnabled(skin) then
        return false
    end
    if trim(skin:GetVariable('HideSteve', '0')) == '1' then
        return false
    end
    local path = resolveImagePath(skin, INVENTORY_IMAGE)
    if path == '' or not chancePassed(skin, INVENTORY_CHANCE_PERCENT) then
        return false
    end
    showInventoryReplacement(skin, normalizePath(path))
    recordAppearance(skin)
    return true
end
function M.CaptureInventoryReplacement(skin)
    if not state.inventory.active then
        return false
    end
    hideInventoryReplacement(skin)
    recordCapture(skin)
    return true
end
function M.CloseInventory(skin)
    hideInventoryReplacement(skin)
    return true
end
function M.InitializeApparition(skin)
    state.apparition.active = false
    state.apparition.lastTick = 0
    state.apparition.lastWrite = 0
    state.apparition.message = ''
    state.apparition.imagePath = ''
    local metrics = currentApparitionMetrics(skin)
    state.apparition.position = { x = 0, y = 0, w = metrics.w, h = metrics.h }
    clearDragHotbarText(skin, false)
    clearHotbarBackgroundText(skin, APPARITION_OWNER)
    setIndicatorForceZero(skin, false)
    if not isEnabled(skin) then
        clearApparitionState(skin)
        hideApparition(skin, false)
        return 0
    end
    local persisted = loadPersistedApparitionState(skin)
    local path = resolveImagePath(skin, APPARITION_IMAGE)
    if persisted and path ~= '' then
        restoreApparition(skin, normalizePath(path), persisted)
        return 0
    end
    if persisted then
        clearApparitionState(skin)
    end
    skin:Bang('!HideMeter', 'MeterHerobrineApparition')
    skin:Bang('!SetOption', 'MeterHerobrineApparition', 'ImageName', '')
    skin:Bang('!Hide')
    return 0
end
function M.RollApparition(skin)
    if state.apparition.active or not isEnabled(skin) then
        return false
    end
    local path = resolveImagePath(skin, APPARITION_IMAGE)
    if path == '' or not chancePassed(skin, APPARITION_CHANCE_PERCENT) then
        return false
    end
    showApparition(skin, normalizePath(path))
    return true
end
function M.ReflowApparition(skin)
    if not state.apparition.active then
        return false
    end
    local path = trim(state.apparition.imagePath)
    if path == '' then
        path = trim(skin:GetVariable('HerobrineApparitionImageName', ''))
    end
    if path == '' then
        path = resolveImagePath(skin, APPARITION_IMAGE)
    end
    local position = clampApparitionPosition(skin, state.apparition.position)
    state.apparition.position = position
    persistActiveApparitionState(skin, position)
    if path ~= '' then
        applyApparitionVisual(skin, path, position)
    else
        skin:Bang('!Move', tostring(position.x), tostring(position.y))
    end
    skin:Bang('!Redraw')
    return true
end

function M.TickApparition(skin)
    if not state.apparition.active then
        return 0
    end
    if not isEnabled(skin) then
        hideApparition(skin, false)
        return 0
    end
    local now = os.time()
    local last = state.apparition.lastTick > 0 and state.apparition.lastTick or now
    local delta = math.max(0, now - last)
    if delta > 0 then
        state.apparition.lastTick = now
        addVisibleSeconds(skin, delta, false)
    end
    if state.apparition.drag.active then
        sendHotbarBackgroundText(skin, state.apparition.drag.message, DRAG_OWNER)
    else
        sendHotbarBackgroundText(skin, state.apparition.message, APPARITION_OWNER)
    end
    setIndicatorForceZero(skin, true)
    return 0
end
function M.HandleApparitionMouseDown(skin, x, y)
    if not state.apparition.active then
        return false
    end
    local drag = state.apparition.drag
    drag.armed = true
    drag.active = false
    drag.startX = tonumber(x) or 0
    drag.startY = tonumber(y) or 0
    drag.message = ''
    clearHotbarBackgroundText(skin, DRAG_OWNER)
    return true
end
function M.HandleApparitionMouseMove(skin, x, y)
    if not state.apparition.active then
        return false
    end
    local drag = state.apparition.drag
    if not drag.armed then
        return false
    end
    if drag.active then
        sendHotbarBackgroundText(skin, drag.message, DRAG_OWNER)
        return true
    end
    local currentX = tonumber(x) or drag.startX
    local currentY = tonumber(y) or drag.startY
    local dx = currentX - drag.startX
    local dy = currentY - drag.startY
    if dx * dx + dy * dy < DRAG_THRESHOLD_PX * DRAG_THRESHOLD_PX then
        return false
    end
    drag.active = true
    drag.message = randomDragMessage(skin)
    sendHotbarBackgroundText(skin, drag.message, DRAG_OWNER)
    return true
end
function M.HandleApparitionMouseUp(skin, x, y)
    if not state.apparition.active then
        clearDragHotbarText(skin, false)
        return false
    end
    local drag = state.apparition.drag
    if drag.armed and not drag.active then
        clearDragHotbarText(skin, false)
        return hideApparition(skin, true)
    end
    if drag.active then
        clearDragHotbarText(skin, true)
        return true
    end
    return false
end
function M.HandleApparitionMouseLeave(skin)
    if not state.apparition.active then
        clearDragHotbarText(skin, false)
        return false
    end
    if state.apparition.drag.armed or state.apparition.drag.active then
        clearDragHotbarText(skin, true)
        return true
    end
    return false
end
function M.DisableApparition(skin)
    hideApparition(skin, false)
    clearApparitionState(skin)
    return 0
end
function M.HandleApparitionClose(skin)
    flushVisibleRuntimeEffects(skin)
    skin:Bang('!Hide')
    return 0
end
function M.SyncSettings(skin, enabled)
    local enabledValue = boolLiteral(enabled, isEnabled(skin))
    local herobrineConfig = configName(skin, APPARITION_CONFIG_SUFFIX)
    setHerobrineEnabledVariables(skin, enabledValue)
    if enabledValue == '1' then
        if not isRainmeterConfigActive(skin, herobrineConfig) then
            skin:Bang('!ActivateConfig', herobrineConfig, APPARITION_CONFIG_FILE)
        end
        return true
    end
    hideInventoryReplacement(skin)
    if isRainmeterConfigActive(skin, herobrineConfig) then
        skin:Bang('!CommandMeasure', 'MeasureHerobrine', 'Disable()', herobrineConfig)
        skin:Bang('!DeactivateConfig', herobrineConfig)
    end
    return true
end
return M
