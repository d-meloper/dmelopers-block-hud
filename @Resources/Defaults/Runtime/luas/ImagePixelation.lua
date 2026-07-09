local M = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function upper(value)
    return string.upper(trim(value))
end

local function joinPath(base, leaf)
    base = tostring(base or '')
    leaf = tostring(leaf or '')
    if base == '' then
        return leaf
    end
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then
        return base .. leaf
    end
    return base .. '\\' .. leaf
end

local function quotePowerShellArgument(value)
    value = tostring(value or '')
    value = value:gsub('`', '``')
    value = value:gsub('"', '`"')
    return '"' .. value .. '"'
end

local base64Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64Encode(value)
    value = tostring(value or '')
    local result = {}
    for index = 1, #value, 3 do
        local byte1 = value:byte(index) or 0
        local byte2 = value:byte(index + 1) or 0
        local byte3 = value:byte(index + 2) or 0
        local triple = (byte1 * 65536) + (byte2 * 256) + byte3
        local remaining = #value - index + 1
        local char1 = math.floor(triple / 262144) % 64
        local char2 = math.floor(triple / 4096) % 64
        local char3 = math.floor(triple / 64) % 64
        local char4 = triple % 64
        result[#result + 1] = base64Alphabet:sub(char1 + 1, char1 + 1)
        result[#result + 1] = base64Alphabet:sub(char2 + 1, char2 + 1)
        result[#result + 1] = remaining >= 2 and base64Alphabet:sub(char3 + 1, char3 + 1) or '='
        result[#result + 1] = remaining >= 3 and base64Alphabet:sub(char4 + 1, char4 + 1) or '='
    end
    return table.concat(result)
end

local function jsonString(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\')
    value = value:gsub('"', '\\"')
    value = value:gsub('\b', '\\b')
    value = value:gsub('\f', '\\f')
    value = value:gsub('\n', '\\n')
    value = value:gsub('\r', '\\r')
    value = value:gsub('\t', '\\t')
    value = value:gsub('[%z\1-\31]', function(char)
        return string.format('\\u%04x', char:byte())
    end)
    return '"' .. value .. '"'
end

local function rollingHash(value)
    value = tostring(value or '')
    local hash = 5381
    for index = 1, #value do
        hash = ((hash * 33) + value:byte(index)) % 4294967296
    end
    return string.format('%08x', hash)
end

local function safeInt(value, fallback, minimum)
    local parsed = math.floor(tonumber(value) or tonumber(fallback) or 0)
    minimum = tonumber(minimum) or 1
    if parsed < minimum then
        return minimum
    end
    return parsed
end

local function normalizedChoice(value, allowed, fallback)
    local candidate = trim(value)
    for _, entry in ipairs(allowed) do
        if candidate:lower() == entry:lower() then
            return entry
        end
    end
    return fallback
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

local function outputPreview(output, limit)
    output = tostring(output or '')
    limit = tonumber(limit) or 240
    output = output:gsub('[\r\n]+', ' | ')
    if #output > limit then
        return output:sub(1, limit) .. '...'
    end
    return output
end

local function describeValue(value, fallback)
    value = trim(value)
    if value == '' then
        return fallback or '<empty>'
    end
    return value
end

local function outputFileName(signature, width, height, blockSize, fitMode, sampleMode)
    local key = table.concat({
        tostring(signature or ''),
        tostring(width or ''),
        tostring(height or ''),
        tostring(blockSize or ''),
        tostring(fitMode or ''),
        tostring(sampleMode or ''),
    }, '|')
    return rollingHash(key) .. '-' .. tostring(width) .. 'x' .. tostring(height) .. '-b' .. tostring(blockSize) .. '.png'
end

local Pixelator = {}
Pixelator.__index = Pixelator

function Pixelator:buildRequest(params)
    params = params or {}
    local sourcePath = trim(params.sourcePath)
    if sourcePath == '' then
        return nil, 'SourcePath is empty.'
    end

    local width = safeInt(params.width, self.defaultWidth, 1)
    local height = safeInt(params.height, self.defaultHeight, 1)
    local blockSize = safeInt(params.blockSize, self.defaultBlockSize, 1)
    local fitMode = normalizedChoice(params.fitMode or self.fitMode, { 'Cover', 'Contain', 'Stretch' }, 'Cover')
    local sampleMode = normalizedChoice(params.sampleMode or self.sampleMode, { 'Average', 'Nearest' }, 'Average')
    local preserveSourceSize = params.preserveSourceSize == true
        or trim(params.preserveSourceSize):lower() == 'true'
        or trim(params.preserveSourceSize) == '1'
    local itemImageDirectory = trim(params.itemImageDirectory)
    local cacheRoot = trim(params.cacheRoot or self.cacheRoot)
    local cacheNamespace = trim(params.cacheNamespace or self.cacheNamespace)
    if cacheNamespace == '' then
        cacheNamespace = 'default'
    end
    local signature = trim(params.signature)
    if signature == '' then
        signature = table.concat({ sourcePath, width, height, blockSize, fitMode, sampleMode, tostring(preserveSourceSize), itemImageDirectory }, '|')
    end

    local outputName = outputFileName(signature, width, height, blockSize, fitMode, sampleMode)
    local outputPath = trim(params.outputPath)
    if outputPath == '' and cacheRoot ~= '' then
        outputPath = joinPath(cacheRoot, outputName)
    end
    local tokenSeed = table.concat({ signature, tostring(os.time()), tostring(self.sequence + 1) }, '|')
    return {
        sourcePath = sourcePath,
        outputPath = outputPath,
        outputName = outputName,
        cacheNamespace = cacheNamespace,
        width = width,
        height = height,
        blockSize = blockSize,
        fitMode = fitMode,
        sampleMode = sampleMode,
        preserveSourceSize = preserveSourceSize,
        itemImageDirectory = itemImageDirectory,
        signature = signature,
        token = rollingHash(tokenSeed),
        fallbackPath = trim(params.fallbackPath),
    }
end

function Pixelator:buildRequestPayload(request)
    local pairs = {
        { 'SourcePath', request.sourcePath },
        { 'OutputPath', request.outputPath },
        { 'CacheRoot', self.cacheRoot },
        { 'CacheNamespace', request.cacheNamespace },
        { 'OutputName', request.outputName },
        { 'Width', request.width },
        { 'Height', request.height },
        { 'BlockSize', request.blockSize },
        { 'FitMode', request.fitMode },
        { 'SampleMode', request.sampleMode },
        { 'PreserveSourceSize', request.preserveSourceSize and true or false },
        { 'ItemImageDirectory', request.itemImageDirectory },
        { 'Token', request.token },
    }
    local json = {}
    for _, pair in ipairs(pairs) do
        local key = pair[1]
        local value = pair[2]
        if type(value) == 'number' then
            json[#json + 1] = jsonString(key) .. ':' .. tostring(value)
        elseif type(value) == 'boolean' then
            json[#json + 1] = jsonString(key) .. ':' .. (value and 'true' or 'false')
        else
            json[#json + 1] = jsonString(key) .. ':' .. jsonString(value)
        end
    end
    return base64Encode('{' .. table.concat(json, ',') .. '}')
end

function Pixelator:buildArgs(request)
    local args = {
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(self.helperPath),
        '-RequestJsonBase64', quotePowerShellArgument(self:buildRequestPayload(request)),
    }
    return table.concat(args, ' ')
end

function Pixelator:start(request)
    if trim(self.helperPath) == '' then
        return false, 'Pixelation helper path is empty.'
    end
    if trim(self.argsVariable) == '' or trim(self.runMeasure) == '' then
        return false, 'Pixelation RunCommand configuration is incomplete.'
    end
    if not self.skin:GetMeasure(self.runMeasure) then
        return false, 'Pixelation RunCommand measure is missing: ' .. self.runMeasure
    end

    self.sequence = self.sequence + 1
    self.pendingToken = request.token
    self.pendingSignature = request.signature
    self.pendingOutputPath = request.outputPath
    self.pendingSourcePath = request.sourcePath
    self.skin:Bang('!SetVariable', self.argsVariable, self:buildArgs(request))
    self.skin:Bang('!UpdateMeasure', self.runMeasure)
    self.skin:Bang('!CommandMeasure', self.runMeasure, 'Run')
    return true, ''
end

function Pixelator:startQueued()
    local queued = self.queuedRequest
    self.queuedRequest = nil
    if not queued then
        return nil
    end

    local ok, message = self:start(queued)
    if not ok then
        self.failedSignature = queued.signature
        self.failedMessage = message
        return {
            started = false,
            failed = true,
            newFailure = true,
            phase = 'start-queued',
            message = message,
            sourcePath = queued.sourcePath,
            outputPath = queued.outputPath,
        }
    end

    return {
        started = true,
        pending = true,
        sourcePath = queued.sourcePath,
        outputPath = queued.outputPath,
    }
end

function Pixelator:requestImage(params)
    local request, message = self:buildRequest(params)
    if not request then
        return {
            displayPath = trim(params and params.sourcePath or ''),
            failed = true,
            newFailure = false,
            phase = 'build-request',
            message = message,
        }
    end

    if self.pendingSignature == request.signature then
        return {
            displayPath = request.sourcePath,
            sourcePath = request.sourcePath,
            outputPath = request.outputPath,
            started = false,
            pending = true,
        }
    end

    if self.pendingToken ~= '' then
        self.queuedRequest = request
        return {
            displayPath = request.sourcePath,
            sourcePath = request.sourcePath,
            outputPath = request.outputPath,
            started = false,
            pending = true,
            queued = true,
        }
    end

    if self.lastSignature == request.signature and self.lastOutputPath ~= '' then
        return {
            displayPath = self.lastOutputPath,
            sourcePath = request.sourcePath,
            outputPath = self.lastOutputPath,
            started = false,
            ready = true,
        }
    end

    if self.failedSignature == request.signature then
        return {
            displayPath = request.sourcePath,
            sourcePath = request.sourcePath,
            failed = true,
            newFailure = false,
            phase = 'cached-failure',
            message = self.failedMessage,
            outputPath = request.outputPath,
        }
    end

    local ok, startMessage = self:start(request)
    if not ok then
        self.failedSignature = request.signature
        self.failedMessage = startMessage
        return {
            displayPath = request.sourcePath,
            sourcePath = request.sourcePath,
            failed = true,
            newFailure = true,
            phase = 'start',
            message = startMessage,
            outputPath = request.outputPath,
        }
    end

    return {
        displayPath = request.sourcePath,
        sourcePath = request.sourcePath,
        outputPath = request.outputPath,
        started = true,
        pending = true,
    }
end

function Pixelator:handleComplete(output)
    local values = parsePairs(output)
    local token = trim(values.DMEL_TOKEN)
    local expectedToken = self.pendingToken
    if token == '' or token ~= self.pendingToken then
        local sourcePath = self.pendingSourcePath
        local outputPath = self.pendingOutputPath
        local status = upper(values.DMEL_STATUS)
        local message = trim(values.DMEL_MESSAGE)
        local errorCode = trim(values.DMEL_ERROR_CODE)
        local errorDetail = trim(values.DMEL_ERROR_DETAIL)
        local detail = table.concat({
            'Pixelation helper returned a stale or missing token.',
            'expected=' .. describeValue(expectedToken),
            'received=' .. describeValue(token),
            'status=' .. describeValue(status),
            'message=' .. describeValue(message),
            'errorCode=' .. describeValue(errorCode),
            'errorDetail=' .. describeValue(errorDetail),
            'source=' .. describeValue(sourcePath),
            'output=' .. describeValue(outputPath),
            'outputChars=' .. tostring(#tostring(output or '')),
            'outputPreview=' .. describeValue(outputPreview(output)),
        }, ' ')
        self.pendingToken = ''
        self.pendingSignature = ''
        self.pendingOutputPath = ''
        self.pendingSourcePath = ''
        local queued = self:startQueued()
        return {
            accepted = false,
            ok = false,
            phase = 'complete-token',
            message = detail,
            helperStatus = status,
            errorCode = errorCode,
            errorDetail = errorDetail,
            receivedToken = token,
            expectedToken = expectedToken,
            outputPreview = outputPreview(output),
            sourcePath = sourcePath,
            outputPath = outputPath,
            queued = queued,
        }
    end

    local signature = self.pendingSignature
    local sourcePath = self.pendingSourcePath
    local pendingOutputPath = self.pendingOutputPath
    local outputPath = trim(values.DMEL_OUTPUTPATH)
    local status = upper(values.DMEL_STATUS)
    local message = trim(values.DMEL_MESSAGE)
    local errorCode = trim(values.DMEL_ERROR_CODE)
    local errorDetail = trim(values.DMEL_ERROR_DETAIL)
    local sourceLength = trim(values.DMEL_SOURCE_LENGTH)
    local sourceFormat = trim(values.DMEL_SOURCE_FORMAT)
    local decodeMethod = trim(values.DMEL_DECODE_METHOD)
    local itemImageAssets = trim(values.DMEL_ITEMIMAGEASSETS)

    self.pendingToken = ''
    self.pendingSignature = ''
    self.pendingOutputPath = ''
    self.pendingSourcePath = ''

    if (status == 'OK' or status == 'WARN') and outputPath ~= '' then
        self.lastSignature = signature
        self.lastOutputPath = outputPath
        self.failedSignature = ''
        self.failedMessage = ''
        return {
            accepted = true,
            ok = true,
            warning = status == 'WARN',
            phase = 'complete',
            outputPath = outputPath,
            sourcePath = sourcePath,
            helperStatus = status,
            message = message,
            errorCode = errorCode,
            errorDetail = errorDetail,
            sourceLength = sourceLength,
            sourceFormat = sourceFormat,
            decodeMethod = decodeMethod,
            itemImageAssets = itemImageAssets,
            queued = self:startQueued(),
        }
    end

    self.failedSignature = signature
    self.failedMessage = message ~= '' and message or 'Pixelation helper failed.'
    return {
        accepted = true,
        ok = false,
        newFailure = true,
        phase = 'complete',
        message = self.failedMessage,
        sourcePath = sourcePath,
        outputPath = outputPath ~= '' and outputPath or pendingOutputPath,
        helperStatus = status,
        errorCode = errorCode,
        errorDetail = errorDetail,
        sourceLength = sourceLength,
        sourceFormat = sourceFormat,
        decodeMethod = decodeMethod,
        itemImageAssets = itemImageAssets,
        queued = self:startQueued(),
    }
end

function M.create(skin, options)
    options = options or {}
    return setmetatable({
        skin = skin,
        helperPath = trim(options.helperPath),
        argsVariable = trim(options.argsVariable),
        runMeasure = trim(options.runMeasure),
        cacheRoot = trim(options.cacheRoot),
        cacheNamespace = trim(options.cacheNamespace),
        defaultWidth = safeInt(options.defaultWidth, 280, 1),
        defaultHeight = safeInt(options.defaultHeight, 280, 1),
        defaultBlockSize = safeInt(options.defaultBlockSize, 16, 1),
        fitMode = normalizedChoice(options.fitMode, { 'Cover', 'Contain', 'Stretch' }, 'Cover'),
        sampleMode = normalizedChoice(options.sampleMode, { 'Average', 'Nearest' }, 'Average'),
        sequence = 0,
        pendingToken = '',
        pendingSignature = '',
        pendingOutputPath = '',
        pendingSourcePath = '',
        queuedRequest = nil,
        lastSignature = '',
        lastOutputPath = '',
        failedSignature = '',
        failedMessage = '',
    }, Pixelator)
end

M.parsePairs = parsePairs
M.hash = rollingHash
M.base64Encode = base64Encode
M.jsonString = jsonString
M.quotePowerShellArgument = quotePowerShellArgument

return M
