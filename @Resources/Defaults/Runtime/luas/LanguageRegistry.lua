local LanguageRegistry = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function lower(value)
    return string.lower(trim(value))
end

local function skinValue(skin, name, fallback)
    if skin and skin.GetVariable then
        return trim(skin:GetVariable(name, fallback or ''))
    end
    return trim(fallback)
end

local function readEntries(skin)
    local count = tonumber(skinValue(skin, 'LanguageCount', '0')) or 0
    local entries = {}
    local byCode = {}
    local byAlias = {}
    local byDisplay = {}

    for index = 1, count do
        local prefix = 'Language_' .. tostring(index) .. '_'
        local code = skinValue(skin, prefix .. 'Code', '')
        if code ~= '' then
            local displayName = skinValue(skin, prefix .. 'DisplayName', code)
            local entry = {
                code = code,
                englishName = skinValue(skin, prefix .. 'EnglishName', displayName),
                displayName = displayName,
                inventoryLabel = skinValue(skin, prefix .. 'InventoryLabel', ''),
            }
            entries[#entries + 1] = entry
            byCode[lower(code)] = entry
            byDisplay[lower(entry.displayName)] = entry

            local baseAlias = code:match('^([^%-_]+)')
            if baseAlias and baseAlias ~= '' and byAlias[lower(baseAlias)] == nil then
                byAlias[lower(baseAlias)] = entry
            end
        end
    end

    return entries, byCode, byAlias, byDisplay
end

function LanguageRegistry.DefaultFallbackLanguageCode(skin)
    local fallback = skinValue(skin, 'DefaultFallbackLanguageCode', 'en-US')
    if fallback == '' then
        return 'en-US'
    end
    return fallback
end

function LanguageRegistry.NormalizeLanguageCode(skin, raw, fallback)
    local entries, byCode, byAlias = readEntries(skin)
    local resolvedFallback = trim(fallback)
    if resolvedFallback == '' then
        resolvedFallback = LanguageRegistry.DefaultFallbackLanguageCode(skin)
    end

    local candidate = lower(raw)
    if candidate == '' then
        candidate = lower(resolvedFallback)
    end

    local entry = byCode[candidate] or byAlias[candidate]
    if entry then
        return entry.code
    end

    local fallbackEntry = byCode[lower(resolvedFallback)] or byAlias[lower(resolvedFallback)]
    if fallbackEntry then
        return fallbackEntry.code
    end

    if entries[1] then
        return entries[1].code
    end

    return 'en-US'
end

function LanguageRegistry.ResolveLanguageInput(skin, raw, fallback)
    local _, byCode, byAlias, byDisplay = readEntries(skin)
    local candidate = lower(raw)
    local entry = byCode[candidate] or byAlias[candidate] or byDisplay[candidate]
    if entry then
        return entry.code
    end
    return LanguageRegistry.NormalizeLanguageCode(skin, raw, fallback)
end

function LanguageRegistry.GetDisplayName(skin, languageCode)
    local entries, byCode, byAlias = readEntries(skin)
    local entry = byCode[lower(languageCode)] or byAlias[lower(languageCode)]
    if entry then
        return entry.displayName
    end

    local fallback = LanguageRegistry.NormalizeLanguageCode(skin, '', nil)
    entry = byCode[lower(fallback)]
    if entry then
        return entry.displayName
    end

    return entries[1] and entries[1].displayName or 'English'
end

function LanguageRegistry.GetInventoryLabel(skin, languageCode)
    local entries, byCode, byAlias = readEntries(skin)
    local resolved = LanguageRegistry.NormalizeLanguageCode(skin, languageCode, nil)
    local entry = byCode[lower(resolved)] or byAlias[lower(resolved)]
    if entry and entry.inventoryLabel ~= '' then
        return entry.inventoryLabel
    end

    local fallbackEntry = byCode[lower(LanguageRegistry.DefaultFallbackLanguageCode(skin))]
    if fallbackEntry and fallbackEntry.inventoryLabel ~= '' then
        return fallbackEntry.inventoryLabel
    end

    return entries[1] and entries[1].inventoryLabel or 'Inventory'
end

function LanguageRegistry.GetDropdownOptions(skin)
    local entries = readEntries(skin)
    table.sort(entries, function(left, right)
        local leftName = lower(left.englishName)
        local rightName = lower(right.englishName)
        if leftName == rightName then
            return lower(left.code) < lower(right.code)
        end
        return leftName < rightName
    end)
    local options = {}
    for _, entry in ipairs(entries) do
        options[#options + 1] = {
            displayLabel = entry.displayName,
            appliedValue = entry.code,
        }
    end
    return options
end

return LanguageRegistry
