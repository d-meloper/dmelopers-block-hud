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

local function fileSize(path)
    local handle = io.open(path, 'rb')
    if not handle then
        return nil
    end
    local size = handle:seek('end') or 0
    handle:close()
    return size
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

    function monitor:initialize()
        local size = fileSize(self.logPath)
        self.offset = size or 0
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

    function monitor:update()
        local path = self.logPath
        if path == '' then
            return false
        end

        local size = fileSize(path)
        if not size then
            self.offset = 0
            return false
        end

        if self.offset == nil or size < self.offset then
            self.offset = size
            return false
        end

        if size == self.offset then
            return false
        end

        local handle = io.open(path, 'rb')
        if not handle then
            return false
        end

        handle:seek('set', self.offset)
        for line in handle:lines() do
            self:handleEntry(parseLine(line))
        end
        self.offset = handle:seek() or size
        handle:close()
        return true
    end

    return monitor
end

return M
