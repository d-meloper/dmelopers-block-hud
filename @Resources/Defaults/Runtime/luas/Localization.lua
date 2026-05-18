local M = {}

local function normalizeKey(key)
    key = tostring(key or '')
    if key == '' then
        return ''
    end
    if key:match('^Loc_') then
        return key
    end
    return 'Loc_' .. key
end

local function decodeEscapes(value)
    value = tostring(value or '')
    value = value:gsub('\\r\\n', '\r\n')
    value = value:gsub('\\n', '\n')
    value = value:gsub('\\r', '\r')
    value = value:gsub('\\t', '\t')
    return value
end

function M.Get(skin, key, fallback)
    local resolvedKey = normalizeKey(key)
    if resolvedKey == '' then
        return decodeEscapes(fallback)
    end
    local value = skin:GetVariable(resolvedKey, '')
    if value == nil or value == '' then
        return decodeEscapes(fallback)
    end
    return decodeEscapes(value)
end

function M.Format(skin, key, args, fallback)
    local value = M.Get(skin, key, fallback)
    for index, argument in ipairs(args or {}) do
        local replacement = tostring(argument or '')
        value = value:gsub('%%' .. tostring(index), function()
            return replacement
        end)
    end
    return value
end

return M
