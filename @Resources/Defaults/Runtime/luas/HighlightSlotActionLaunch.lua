local M = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function M.isUrl(value)
    return tostring(value or ''):match('^https?://') ~= nil
end

function M.isUriScheme(value)
    local text = tostring(value or '')
    if text:match('^[A-Za-z]:[\\/]') then
        return false
    end
    return text:match('^[A-Za-z][A-Za-z0-9+%.%-]*:') ~= nil
end

function M.looksLikePlainPath(value)
    local text = tostring(value or '')
    return text:match('^[A-Za-z]:\\') or text:match('^\\\\') or text:match('^shell:')
end

function M.isBracketedBang(value)
    local text = tostring(value or '')
    local cursor = 1
    while cursor <= #text do
        local startPos = text:find('%S', cursor)
        if not startPos then
            return true
        end
        if text:sub(startPos, startPos) ~= '[' then
            return false
        end

        local chunk = text:match('%b[]', startPos)
        if not chunk then
            return false
        end

        cursor = startPos + #chunk
    end

    return false
end

function M.luaStringLiteral(value)
    return string.format('%q', tostring(value or ''))
end

function M.powerShellSingleQuoted(value)
    return "'" .. tostring(value or ''):gsub("'", "''") .. "'"
end

function M.quoteActionArg(value)
    return '"' .. tostring(value or ''):gsub('"', [[\"]]) .. '"'
end

function M.splitExecutablePath(exec)
    exec = tostring(exec or '')
    local lower = exec:lower()
    for _, marker in ipairs({ '.exe ', '.bat ', '.cmd ', '.com ', '.ps1 ', '.vbs ', '.lnk ', '.msc ', '.msi ' }) do
        local startPos = lower:find(marker, 1, true)
        if startPos then
            local endPos = startPos + #marker - 2
            return exec:sub(1, endPos), exec:sub(endPos + 1)
        end
    end

    return exec, ''
end

function M.buildBang(exec, onUnsafeDelimiter)
    exec = trim(exec)
    if exec == '' then return nil end

    if M.isBracketedBang(exec) then
        return exec
    end

    if exec:find(']', 1, true) then
        if onUnsafeDelimiter then
            onUnsafeDelimiter(exec)
        end
        return nil
    end

    if exec:sub(1, 1) == '!' then
        return '[' .. exec .. ']'
    end

    if M.isUrl(exec) then
        return '[' .. M.quoteActionArg(exec) .. ']'
    end

    if M.isUriScheme(exec) then
        return '[' .. M.quoteActionArg(exec) .. ']'
    end

    if M.looksLikePlainPath(exec) then
        if exec:sub(1, 1) == '"' then
            return '[' .. exec .. ']'
        end

        local executable, args = M.splitExecutablePath(exec)
        return '[' .. M.quoteActionArg(executable) .. args .. ']'
    end

    return '[' .. exec .. ']'
end

return M
