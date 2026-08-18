local M = {}

local MAX_MONITORS = 32
local MAX_REPLICAS = MAX_MONITORS - 1
local REPLICA_FILE = 'Replica.ini'

local TARGET_IDS = {
    'Hotbar',
    'IndicatorHeart',
    'IndicatorArmor',
    'IndicatorFood',
    'IndicatorAir',
    'IndicatorExp',
    'Clock',
    'ClockSprite',
}

local TARGET_SET = {}
for _, id in ipairs(TARGET_IDS) do
    TARGET_SET[id] = true
end

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

local function normalizedRootConfig(value)
    return trim(value):gsub('/', '\\'):gsub('\\+$', '')
end

local function normalizedSlot(value)
    local slot = tonumber(value)
    if not slot or slot ~= math.floor(slot) or slot < 1 or slot > MAX_REPLICAS then
        return nil
    end
    return slot
end

local function slotName(slot)
    return string.format('Slot%02d', slot)
end

local function monitorSort(left, right)
    local leftIndex = tonumber(left and left.index) or (MAX_MONITORS + 1)
    local rightIndex = tonumber(right and right.index) or (MAX_MONITORS + 1)
    if leftIndex ~= rightIndex then
        return leftIndex < rightIndex
    end
    return tostring(left and left.fingerprint or '') < tostring(right and right.fingerprint or '')
end

local function normalizedMonitors(snapshot)
    local monitors = {}
    local seen = {}
    for _, monitor in ipairs(snapshot and snapshot.monitors or {}) do
        local fingerprint = trim(monitor and monitor.fingerprint)
        if fingerprint ~= '' and not seen[fingerprint] and #monitors < MAX_MONITORS then
            monitors[#monitors + 1] = monitor
            seen[fingerprint] = true
        end
    end
    table.sort(monitors, monitorSort)
    return monitors
end

local function primaryFingerprint(snapshot, monitors)
    local primaryFingerprint = snapshot and snapshot.primary and snapshot.primary.fingerprint or ''
    primaryFingerprint = trim(primaryFingerprint)
    if primaryFingerprint ~= '' then
        for _, monitor in ipairs(monitors or {}) do
            if trim(monitor.fingerprint) == primaryFingerprint then
                return primaryFingerprint
            end
        end
    end
    return trim(monitors[1] and monitors[1].fingerprint or '')
end

local TARGET_BITS = {
    Hotbar = 1,
    IndicatorHeart = 2,
    IndicatorArmor = 4,
    IndicatorFood = 8,
    IndicatorAir = 16,
    IndicatorExp = 32 + 64,
    Clock = 128,
    ClockSprite = 256,
}

local function normalizedMask(value)
    local mask = tonumber(value)
    if not mask then return 0 end
    if mask ~= math.floor(mask) or mask < 0 or mask > 511 then return 0 end
    return mask
end

local function hasBit(mask, bit)
    return math.floor(normalizedMask(mask) / bit) % 2 == 1
end

local function selectedForTarget(mask, targetId)
    if targetId == 'IndicatorExp' then
        return hasBit(mask, 32) or hasBit(mask, 64)
    end
    local bit = TARGET_BITS[targetId]
    return bit and hasBit(mask, bit) or false
end

local function normalizedPreferences(preferences)
    local result = {
        dragEnabled = type(preferences) == 'table' and preferences.dragEnabled == true,
        snapEnabled = type(preferences) == 'table' and preferences.snapEnabled == true,
        anySelected = type(preferences) == 'table' and preferences.anySelected == true,
        byFingerprint = {},
    }
    for fingerprint, entry in pairs(type(preferences) == 'table' and preferences.byFingerprint or {}) do
        local slot = normalizedSlot(entry and entry.slot)
        local normalizedFingerprint = trim(fingerprint)
        if slot and normalizedFingerprint ~= '' and not result.byFingerprint[normalizedFingerprint] then
            result.byFingerprint[normalizedFingerprint] = {
                slot = slot,
                fingerprint = normalizedFingerprint,
                selection = normalizedMask(entry.selection),
                positions = type(entry.positions) == 'table' and entry.positions or {},
            }
        end
    end
    return result
end

local function planTarget(rootConfig, targetId, monitors, excludedFingerprint, preferences, canonicalActive)
    local target = {
        id = targetId,
        active = false,
        replicas = {},
        bySlot = {},
        byFingerprint = {},
    }
    if canonicalActive ~= true or excludedFingerprint == '' then
        return target
    end
    for _, monitor in ipairs(monitors) do
        local fingerprint = trim(monitor.fingerprint)
        local preference = preferences.byFingerprint[fingerprint]
        local selection = normalizedMask(preference and preference.selection or 0)
        if fingerprint ~= '' and fingerprint ~= excludedFingerprint
            and preference and selectedForTarget(selection, targetId) then
            local slot = preference.slot
            local componentMask = targetId == 'IndicatorExp'
                and ((hasBit(selection, 32) and 32 or 0) + (hasBit(selection, 64) and 64 or 0))
                or TARGET_BITS[targetId]
            local assignment = {
                targetId = targetId,
                slot = slot,
                monitor = monitor,
                fingerprint = fingerprint,
                config = M.ReplicaConfig(rootConfig, targetId, slot),
                file = REPLICA_FILE,
                selectionMask = selection,
                componentMask = componentMask,
                position = preference.positions and preference.positions[targetId] or nil,
                dragEnabled = preferences.dragEnabled,
                snapEnabled = preferences.snapEnabled,
            }
            target.replicas[#target.replicas + 1] = assignment
            target.bySlot[slot] = assignment
            target.byFingerprint[fingerprint] = assignment
            target.active = true
        end
    end
    return target
end

function M.MaxMonitors()
    return MAX_MONITORS
end

function M.MaxReplicas()
    return MAX_REPLICAS
end

function M.TargetIds()
    return copyArray(TARGET_IDS)
end

function M.IsTargetId(value)
    return TARGET_SET[trim(value)] == true
end

function M.NormalizeSlot(value)
    return normalizedSlot(value)
end

function M.ReplicaFile()
    return REPLICA_FILE
end

function M.ReplicaConfig(rootConfig, targetId, slot)
    local root = normalizedRootConfig(rootConfig)
    targetId = trim(targetId)
    slot = normalizedSlot(slot)
    if root == '' or not TARGET_SET[targetId] or not slot then
        return nil
    end
    return table.concat({
        root,
        'HUD',
        'Mirror',
        'Replicas',
        targetId,
        slotName(slot),
    }, '\\')
end

function M.Plan(snapshot, surfaceStates, rootConfig, preferences)
    local monitors = normalizedMonitors(snapshot)
    local excludedFingerprint = primaryFingerprint(snapshot, monitors)
    preferences = normalizedPreferences(preferences)
    local plan = {
        enabled = preferences.anySelected == true,
        dragEnabled = preferences.dragEnabled,
        snapEnabled = preferences.snapEnabled,
        rootConfig = normalizedRootConfig(rootConfig),
        topologySignature = tostring(snapshot and snapshot.signature or ''),
        monitors = monitors,
        targets = {},
        desiredConfigs = {},
    }

    for _, targetId in ipairs(TARGET_IDS) do
        local target = planTarget(
            plan.rootConfig,
            targetId,
            monitors,
            excludedFingerprint,
            preferences,
            plan.enabled and surfaceStates and surfaceStates[targetId] == true
        )
        plan.targets[targetId] = target
        for _, assignment in ipairs(target.replicas) do
            if assignment.config then
                plan.desiredConfigs[assignment.config] = assignment
            end
        end
    end
    return plan
end

return M
