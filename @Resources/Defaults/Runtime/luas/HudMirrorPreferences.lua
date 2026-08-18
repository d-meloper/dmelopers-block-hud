local M = {}

local MAX_REPLICAS = 31
local ALL_SELECTIONS = 511

local SELECTION_BITS = {
    Hotbar = 1,
    IndicatorHeart = 2,
    IndicatorArmor = 4,
    IndicatorFood = 8,
    IndicatorAir = 16,
    ExpBar = 32,
    ExpLevel = 64,
    Clock = 128,
    ClockSprite = 256,
}

local TARGET_BITS = {
    Hotbar = SELECTION_BITS.Hotbar,
    IndicatorHeart = SELECTION_BITS.IndicatorHeart,
    IndicatorArmor = SELECTION_BITS.IndicatorArmor,
    IndicatorFood = SELECTION_BITS.IndicatorFood,
    IndicatorAir = SELECTION_BITS.IndicatorAir,
    IndicatorExp = SELECTION_BITS.ExpBar + SELECTION_BITS.ExpLevel,
    Clock = SELECTION_BITS.Clock,
    ClockSprite = SELECTION_BITS.ClockSprite,
}

local POSITION_TARGETS = {
    'Hotbar',
    'IndicatorHeart',
    'IndicatorArmor',
    'IndicatorFood',
    'IndicatorAir',
    'IndicatorExp',
    'Clock',
    'ClockSprite',
}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function boolValue(value)
    local text = trim(value):lower()
    if text == '' then return false end
    local number = tonumber(text)
    if number ~= nil then return number ~= 0 end
    return text ~= 'false' and text ~= 'off' and text ~= 'no'
end

local function normalizedSlot(value)
    local slot = tonumber(value)
    if not slot or slot ~= math.floor(slot) or slot < 1 or slot > MAX_REPLICAS then
        return nil
    end
    return slot
end

local function normalizedMask(value)
    local mask = tonumber(value)
    if not mask then return 0 end
    if mask ~= math.floor(mask) or mask < 0 or mask > ALL_SELECTIONS then return 0 end
    return mask
end

local function hasBit(mask, bit)
    mask = normalizedMask(mask)
    return math.floor(mask / bit) % 2 == 1
end

local function finiteNumber(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function formatNumber(value)
    local number = finiteNumber(value)
    if number == nil then return '' end
    if number == 0 then number = 0 end
    local text = string.format('%.12f', number):gsub('0+$', ''):gsub('%.$', '')
    if text == '' or text == '-0' then return '0' end
    return text
end

function M.MaxReplicas()
    return MAX_REPLICAS
end

function M.AllSelections()
    return ALL_SELECTIONS
end

function M.TargetBits()
    local result = {}
    for id, mask in pairs(TARGET_BITS) do result[id] = mask end
    return result
end

function M.SelectionBits()
    local result = {}
    for id, bit in pairs(SELECTION_BITS) do result[id] = bit end
    return result
end

function M.PositionTargets()
    local result = {}
    for index, id in ipairs(POSITION_TARGETS) do result[index] = id end
    return result
end

function M.SlotPrefix(rawSlot)
    local slot = normalizedSlot(rawSlot)
    if not slot then return nil end
    return string.format('HudMirrorSlot%02d', slot)
end

function M.FingerprintVariable(rawSlot)
    local prefix = M.SlotPrefix(rawSlot)
    return prefix and (prefix .. 'Fingerprint') or nil
end

function M.SelectionVariable(rawSlot)
    local prefix = M.SlotPrefix(rawSlot)
    return prefix and (prefix .. 'Selection') or nil
end

function M.PositionVariable(rawSlot, targetId)
    local prefix = M.SlotPrefix(rawSlot)
    targetId = trim(targetId)
    if not prefix or not TARGET_BITS[targetId] then return nil end
    return prefix .. targetId .. 'Position'
end

function M.NormalizeMask(value)
    return normalizedMask(value)
end

function M.HasBit(mask, bit)
    return hasBit(mask, bit)
end

function M.IsTargetSelected(mask, targetId)
    targetId = trim(targetId)
    local bits = TARGET_BITS[targetId]
    if not bits then return false end
    if targetId == 'IndicatorExp' then
        return hasBit(mask, 32) or hasBit(mask, 64)
    end
    return hasBit(mask, bits)
end

function M.ExpComponents(mask)
    return {
        bar = hasBit(mask, 32),
        level = hasBit(mask, 64),
        mask = (hasBit(mask, 32) and 32 or 0) + (hasBit(mask, 64) and 64 or 0),
    }
end

function M.ParsePosition(value)
    local text = trim(value)
    if text == '' then return nil end
    local rawX, rawY = text:match('^([^,]+),([^,]+)$')
    rawX = trim(rawX)
    rawY = trim(rawY)
    local function isDecimal(numberText)
        return numberText:match('^[+-]?%d+%.?%d*$') ~= nil
            or numberText:match('^[+-]?%.%d+$') ~= nil
    end
    if not isDecimal(rawX) or not isDecimal(rawY) then return nil end
    local x = finiteNumber(rawX)
    local y = finiteNumber(rawY)
    if x == nil or y == nil then return nil end
    return { x = x, y = y }
end

function M.FormatPosition(x, y)
    local formattedX = formatNumber(x)
    local formattedY = formatNumber(y)
    if formattedX == '' or formattedY == '' then return '' end
    return formattedX .. ',' .. formattedY
end

function M.Read(SKIN)
    local result = {
        dragEnabled = boolValue(SKIN:GetVariable('AllowHudMirrorReplicaDrag', '0')),
        snapEnabled = boolValue(SKIN:GetVariable('AllowHudMirrorReplicaSnapEdges', '0')),
        slots = {},
        byFingerprint = {},
        anySelected = false,
    }
    for slot = 1, MAX_REPLICAS do
        local fingerprint = trim(SKIN:GetVariable(M.FingerprintVariable(slot), ''))
        local selection = normalizedMask(SKIN:GetVariable(M.SelectionVariable(slot), '0'))
        local entry = {
            slot = slot,
            fingerprint = fingerprint,
            selection = selection,
            positions = {},
        }
        for _, targetId in ipairs(POSITION_TARGETS) do
            local position = M.ParsePosition(SKIN:GetVariable(M.PositionVariable(slot, targetId), ''))
            if position then entry.positions[targetId] = position end
        end
        result.slots[slot] = entry
        if fingerprint ~= '' and not result.byFingerprint[fingerprint] then
            result.byFingerprint[fingerprint] = entry
            if selection ~= 0 then result.anySelected = true end
        end
    end
    return result
end

function M.Signature(preferences)
    preferences = preferences or {}
    local fields = {
        preferences.dragEnabled and 'drag=1' or 'drag=0',
        preferences.snapEnabled and 'snap=1' or 'snap=0',
    }
    for slot = 1, MAX_REPLICAS do
        local entry = preferences.slots and preferences.slots[slot] or nil
        fields[#fields + 1] = table.concat({
            string.format('%02d', slot),
            trim(entry and entry.fingerprint or ''),
            tostring(normalizedMask(entry and entry.selection or 0)),
        }, '=')
        for _, targetId in ipairs(POSITION_TARGETS) do
            local position = entry and entry.positions and entry.positions[targetId] or nil
            if position then
                fields[#fields + 1] = targetId .. ':' .. M.FormatPosition(position.x, position.y)
            end
        end
    end
    return table.concat(fields, '|')
end

function M.ResolvePosition(position, work, width, height)
    if not position or not work then return nil, nil end
    local relativeX = finiteNumber(position.x)
    local relativeY = finiteNumber(position.y)
    local workX = finiteNumber(work.x)
    local workY = finiteNumber(work.y)
    local workWidth = finiteNumber(work.width)
    local workHeight = finiteNumber(work.height)
    width = finiteNumber(width)
    height = finiteNumber(height)
    if relativeX == nil or relativeY == nil or workX == nil or workY == nil
        or workWidth == nil or workHeight == nil or width == nil or height == nil then
        return nil, nil
    end
    return workX + (relativeX * (workWidth - width)), workY + (relativeY * (workHeight - height))
end

function M.RelativePosition(x, y, work, width, height)
    x = finiteNumber(x)
    y = finiteNumber(y)
    width = finiteNumber(width)
    height = finiteNumber(height)
    local workX = finiteNumber(work and work.x)
    local workY = finiteNumber(work and work.y)
    local workWidth = finiteNumber(work and work.width)
    local workHeight = finiteNumber(work and work.height)
    if x == nil or y == nil or width == nil or height == nil
        or workX == nil or workY == nil or workWidth == nil or workHeight == nil then
        return nil
    end
    local spanX = workWidth - width
    local spanY = workHeight - height
    return {
        x = spanX == 0 and 0 or ((x - workX) / spanX),
        y = spanY == 0 and 0 or ((y - workY) / spanY),
    }
end

return M
