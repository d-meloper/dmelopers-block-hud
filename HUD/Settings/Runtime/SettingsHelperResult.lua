local M = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function normalizeToggleValue(raw)
    return trim(raw) == '1' and '1' or '0'
end

function M.normalizeStartupAutoRunOutput(raw)
    local normalized = tostring(raw or ''):gsub('%z', '')
    normalized = normalized:gsub('^\239\187\191', '')
    return normalized
end

function M.parseCommandCaptureVariables(raw)
    local values = {}

    for line in tostring(raw or ''):gmatch('[^\r\n]+') do
        local normalizedLine = tostring(line or '')
        normalizedLine = normalizedLine:gsub('^\239\187\191', '')
        normalizedLine = normalizedLine:match('^%s*(.-)%s*$') or ''

        local key, value = normalizedLine:match('^([A-Z_]+)=(.*)$')
        if key then
            values[key] = trim(value)
        end
    end

    return values
end

function M.parseStartupAutoRunResult(raw, fallback, normalizeToggle)
    local normalized = M.normalizeStartupAutoRunOutput(raw)
    local values = M.parseCommandCaptureVariables(normalized)
    local fallbackValue = type(fallback) == 'table' and fallback.value or fallback
    local fallbackFastValue = type(fallback) == 'table' and fallback.fastValue or '0'
    local literal = trim(values.DMEL_VALUE or '')
    if literal ~= '0' and literal ~= '1' then
        literal = ''
        for line in normalized:gmatch('[^\r\n]+') do
            local candidate = trim(line):gsub('^\239\187\191', '')
            if candidate == '0' or candidate == '1' then
                literal = candidate
            end
        end
    end

    local status = string.upper(trim(values.DMEL_STATUS or ''))
    if status == '' and literal ~= '' then
        status = 'OK'
    end

    local fastLiteral = trim(values.DMEL_FAST_VALUE or '')
    local shortcutLiteral = trim(values.DMEL_SHORTCUT_VALUE or '')
    local method = trim(values.DMEL_METHOD or ''):lower()
    local taskState = trim(values.DMEL_TASK_STATE or ''):lower()
    local recovery = trim(values.DMEL_RECOVERY or ''):lower()
    local validMethods = { none = true, shortcut = true, task = true, conflict = true, invalid = true }
    local validTaskStates = { absent = true, valid = true, disabled = true, invalid = true, foreign = true }
    local validRecoveries = { none = true, shortcut = true, partial = true, failed = true }
    local normalize = normalizeToggle or normalizeToggleValue
    return {
        status = status,
        literal = literal ~= '' and literal or normalize(fallbackValue),
        hasLiteral = literal == '0' or literal == '1',
        fastLiteral = (fastLiteral == '0' or fastLiteral == '1') and fastLiteral or normalize(fallbackFastValue),
        hasFastLiteral = fastLiteral == '0' or fastLiteral == '1',
        shortcutLiteral = (shortcutLiteral == '0' or shortcutLiteral == '1') and shortcutLiteral or '0',
        hasShortcutLiteral = shortcutLiteral == '0' or shortcutLiteral == '1',
        method = validMethods[method] and method or '',
        taskState = validTaskStates[taskState] and taskState or '',
        recovery = validRecoveries[recovery] and recovery or '',
        recoveryCode = trim(values.DMEL_RECOVERY_CODE or ''),
        requestToken = trim(values.DMEL_REQUEST_TOKEN or ''),
        code = trim(values.DMEL_CODE or ''),
        message = trim(values.DMEL_MESSAGE or ''),
        normalizedOutput = normalized,
    }
end

return M
