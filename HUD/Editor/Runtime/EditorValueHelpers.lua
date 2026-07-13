local M = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function M.normalizeConfirmBeforeRun(value)
    return trim(value) == '1' and '1' or '0'
end

function M.clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function M.wrapStepValue(value, minValue, maxValue)
    if value > maxValue then
        return minValue
    end
    if value < minValue then
        return maxValue
    end
    return value
end

function M.toUserFacingImageOffsetY(value)
    local numeric = -1 * (tonumber(value) or 0)
    if numeric == 0 then
        return 0
    end
    return numeric
end

function M.toPersistedImageOffsetY(value)
    local numeric = -1 * (tonumber(value) or 0)
    if numeric == 0 then
        return 0
    end
    return numeric
end

return M
