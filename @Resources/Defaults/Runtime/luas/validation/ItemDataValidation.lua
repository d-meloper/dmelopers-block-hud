local ItemDataValidation = {}

local function logMessage(message)
    SKIN:Bang(string.format('!Log "%s"', tostring(message):gsub('"', "'")))
end

local function toNumber(value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    return n
end

local function slotKey(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function isEmptyItem(item)
    if not item then
        return true
    end

    local execPath = tostring(item.ExecPath or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local imageName = tostring(item.Image or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local itemName = tostring(item.ItemName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local qty = toNumber(item.qty)

    return execPath == ""
        and imageName == ""
        and itemName == ""
        and (qty == nil or qty == 0)
end

local function isWithinBounds(x, y, xMin, xMax, yMin, yMax)
    return x ~= nil and y ~= nil and x >= xMin and x <= xMax and y >= yMin and y <= yMax
end

local function validateBounds(item, sourceName, xMin, xMax, yMin, yMax)
    local x = toNumber(item.x)
    local y = toNumber(item.y)
    if not isWithinBounds(x, y, xMin, xMax, yMin, yMax) then
        logMessage(string.format('[ItemDataValidation] out-of-range coord in %s: x=%s y=%s', sourceName, tostring(item.x), tostring(item.y)))
        return false
    end

    return true
end

local function validateSource(items, sourceName, xMin, xMax, yMin, yMax, seenSlots)
    local localSeen = {}

    for i = 1, #items do
        local item = items[i]
        local x = toNumber(item and item.x)
        local y = toNumber(item and item.y)

        if item and not isEmptyItem(item) then
            local hasValidBounds = validateBounds(item, sourceName, xMin, xMax, yMin, yMax)

            local execPath = tostring(item.ExecPath or "")
            if execPath:gsub("^%s+", ""):gsub("%s+$", "") == "" then
                logMessage(string.format('[ItemDataValidation] empty exec in %s: x=%s y=%s', sourceName, tostring(item.x), tostring(item.y)))
            end

            if hasValidBounds and x and y then
                local key = slotKey(x, y)
                if localSeen[key] then
                    logMessage(string.format('[ItemDataValidation] duplicate slot in %s: x=%s y=%s', sourceName, tostring(item.x), tostring(item.y)))
                else
                    localSeen[key] = true
                end

                if seenSlots then
                    if seenSlots[key] then
                        logMessage(string.format('[ItemDataValidation] bottom-row merge conflict at x=%s y=%s', tostring(item.x), tostring(item.y)))
                    else
                        seenSlots[key] = sourceName
                    end
                end
            end
        end
    end
end

function ItemDataValidation.Validate(context)
    local hotbarInfos = (context and context.hotbar) or {}
    local inventoryInfos = (context and context.inventory) or {}
    local useBottomSlot = context and context.useBottomSlot == true

    validateSource(hotbarInfos, 'hotbar', 1, 10, 1, 1)
    validateSource(inventoryInfos, 'inventory', 1, 9, 1, 4)

    if not useBottomSlot then
        local mergedSlots = {}

        for i = 1, #hotbarInfos do
            local item = hotbarInfos[i]
            local x = toNumber(item and item.x)
            local y = toNumber(item and item.y)
            if item and isWithinBounds(x, y, 1, 10, 1, 1) and x < 10 then
                mergedSlots[slotKey(x, y)] = 'hotbar'
            end
        end

        for i = 1, #inventoryInfos do
            local item = inventoryInfos[i]
            local x = toNumber(item and item.x)
            local y = toNumber(item and item.y)
            if item and isWithinBounds(x, y, 1, 9, 1, 4) and y ~= 1 then
                local key = slotKey(x, y)
                if mergedSlots[key] then
                    logMessage(string.format('[ItemDataValidation] bottom-row merge conflict at x=%s y=%s', tostring(item.x), tostring(item.y)))
                else
                    mergedSlots[key] = 'inventory'
                end
            end
        end
    end
end

return ItemDataValidation
