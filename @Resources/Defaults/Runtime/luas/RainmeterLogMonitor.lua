local M = {}

local ERROR_LEVEL = 'ERRO'
local DEFAULT_DEDUPE_SECONDS = 30
local DEFAULT_SUPPRESS_SECONDS = 5

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function normalize(value)
    local text = trim(value)
    text = text:gsub('%s+', ' ')
    return text
end

local function lower(value)
    return tostring(value or ''):lower()
end

local function upper(value)
    return tostring(value or ''):upper()
end

local function parseLine(line)
    local level, timeText, source, message = tostring(line or ''):match('^(%u+)%s+%((.-)%)%s*(.-):%s*(.*)$')
    if not level then
        return nil
    end
    return {
        level = level,
        timeText = timeText or '',
        source = trim(source),
        message = trim(message),
    }
end

local function parsePairs(output)
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

local function parseEntries(values)
    local entries = {}
    local count = tonumber(values.DMEL_ENTRY_COUNT or '0') or 0
    for index = 1, count do
        local prefix = 'DMEL_ENTRY_' .. tostring(index) .. '_'
        entries[#entries + 1] = {
            level = trim(values[prefix .. 'LEVEL']),
            timeText = trim(values[prefix .. 'TIME']),
            source = trim(values[prefix .. 'SOURCE']),
            message = trim(values[prefix .. 'MESSAGE']),
        }
    end
    return entries
end

function M.New(options)
    options = options or {}
    local monitor = {
        logPath = trim(options.logPath),
        rootConfig = lower(options.rootConfig),
        dedupeSeconds = tonumber(options.dedupeSeconds) or DEFAULT_DEDUPE_SECONDS,
        suppressSeconds = tonumber(options.suppressSeconds) or DEFAULT_SUPPRESS_SECONDS,
        offset = nil,
        recent = {},
        onError = options.onError,
        skin = options.skin or SKIN,
    }

    function monitor:initialize(offset)
        self.offset = tonumber(offset) or 0
        return true
    end

    function monitor:matchesBlockHud(entry)
        local needle = self.rootConfig
        if needle == '' then
            needle = 'dmeloper' .. string.char(39) .. 's block hud'
        end
        local combined = lower((entry.source or '') .. ' ' .. (entry.message or ''))
        return combined:find(needle, 1, true) ~= nil
    end

    function monitor:isSuppressed(entry, now)
        local suppressMessage = normalize(self.skin:GetVariable('BlockHudDiagnosticsSuppressMessage', ''))
        if suppressMessage == '' then
            return false
        end
        local suppressAt = tonumber(self.skin:GetVariable('BlockHudDiagnosticsSuppressAt', '0')) or 0
        if suppressAt <= 0 or now <= 0 or (now - suppressAt) > self.suppressSeconds then
            return false
        end
        return normalize(entry.message) == suppressMessage
    end

    function monitor:isDeduped(entry, now)
        local key = normalize((entry.source or '') .. '|' .. (entry.message or ''))
        local previous = tonumber(self.recent[key]) or 0
        self.recent[key] = now
        return previous > 0 and now > 0 and (now - previous) < self.dedupeSeconds
    end

    function monitor:handleEntry(entry)
        if not entry or entry.level ~= ERROR_LEVEL then
            return false
        end
        if not self:matchesBlockHud(entry) then
            return false
        end

        local now = os.time() or 0
        if self:isSuppressed(entry, now) or self:isDeduped(entry, now) then
            return false
        end

        if type(self.onError) == 'function' then
            self.onError(entry)
            return true
        end
        return false
    end

    function monitor:handleOutput(output)
        local values = parsePairs(output)
        if upper(values.DMEL_STATUS) ~= 'OK' then
            return false
        end

        local handled = false
        for _, entry in ipairs(parseEntries(values)) do
            if self:handleEntry(entry) then
                handled = true
            end
        end
        self.offset = tonumber(values.DMEL_OFFSET) or self.offset or 0
        return handled
    end

    return monitor
end

M.parsePairs = parsePairs
M.parseLine = parseLine

return M
