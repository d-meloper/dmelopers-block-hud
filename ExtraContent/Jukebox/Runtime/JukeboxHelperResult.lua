local M = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function M.parseDmelPairs(output)
    local pairs = {}
    output = tostring(output or '')

    local fields = {}
    for position, key in output:gmatch('()([A-Z][A-Z0-9_]+)=') do
        if key:match('^DMEL_') then
            fields[#fields + 1] = {
                position = position,
                key = key,
            }
        end
    end

    for index, field in ipairs(fields) do
        local valueStart = field.position + #field.key + 1
        local valueEnd = #output
        if fields[index + 1] then
            valueEnd = fields[index + 1].position - 1
        end
        pairs[field.key] = trim(output:sub(valueStart, valueEnd))
    end

    return pairs
end

function M.parseLinePairs(output)
    local pairs = {}
    output = tostring(output or '')
    for line in output:gmatch('[^\r\n]+') do
        local key, value = line:match('^([%w_]+)=(.*)$')
        if key then
            pairs[key] = value or ''
        end
    end
    return pairs
end

function M.outputPreview(output, maxLength)
    maxLength = tonumber(maxLength) or 180
    local preview = trim(tostring(output or ''):gsub('[\r\n]+', ' '))
    if #preview > maxLength then
        preview = preview:sub(1, maxLength) .. '...'
    end
    return preview
end

return M
