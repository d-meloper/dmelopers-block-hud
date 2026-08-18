local M = {}

M.REPOSITORY_SLUG = 'd-meloper/dmelopers-block-hud'
M.TEST_REPOSITORY_SLUG = 'oup030416/dmelopers-block-hud-test'
M.UTILITY_SUFFIX = '\\Utilities\\LatestUpdate'

local REPOSITORY_PROFILES = {
    [M.REPOSITORY_SLUG] = {
        owner = 'd-meloper',
        repo = 'dmelopers-block-hud',
    },
    [M.TEST_REPOSITORY_SLUG] = {
        owner = 'oup030416',
        repo = 'dmelopers-block-hud-test',
    },
}

local VARIANTS = {
    Korea = 'DMelopers-Block-HUD_Korea.zip',
    Global = 'DMelopers-Block-HUD_Global.zip',
}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function normalizeVariant(raw)
    local normalized = trim(raw):lower()
    if normalized == 'korea' then
        return 'Korea'
    end
    if normalized == 'global' then
        return 'Global'
    end
    return nil
end

local function normalizeSha256(raw)
    local normalized = trim(raw)
    if #normalized ~= 64 or not normalized:match('^[0-9A-Fa-f]+$') then
        return nil
    end
    return normalized:upper()
end

M.NormalizeSha256 = normalizeSha256

local function validVersionPart(value)
    return value == '0' or value:match('^[1-9]%d*$') ~= nil
end

function M.ParseStableVersion(raw)
    local normalized = trim(raw)
    local major, minor, patch = normalized:match('^[vV]?(%d+)%.(%d+)%.(%d+)$')
    if not major or not validVersionPart(major) or not validVersionPart(minor) or not validVersionPart(patch) then
        return nil
    end
    return {
        tonumber(major), tonumber(minor), tonumber(patch),
        tag = 'v' .. major .. '.' .. minor .. '.' .. patch,
    }
end

function M.CompareStableVersions(leftRaw, rightRaw)
    local left = M.ParseStableVersion(leftRaw)
    local right = M.ParseStableVersion(rightRaw)
    if not left or not right then
        return nil
    end
    for index = 1, 3 do
        if left[index] < right[index] then
            return -1
        elseif left[index] > right[index] then
            return 1
        end
    end
    return 0
end

function M.AssetName(variant)
    return VARIANTS[normalizeVariant(variant)]
end

function M.NormalizeVariant(variant)
    return normalizeVariant(variant)
end

function M.ResolveRepository(owner, repo)
    owner = trim(owner):lower()
    repo = trim(repo):lower()
    if owner == '' or repo == '' then
        return nil
    end
    local slug = owner .. '/' .. repo
    local profile = REPOSITORY_PROFILES[slug]
    if not profile then
        return nil
    end
    return {
        owner = profile.owner,
        repo = profile.repo,
        slug = slug,
    }
end

function M.CacheProvenanceMatches(cache, variant, expectedRepositorySlug)
    cache = cache or {}
    local normalizedVariant = normalizeVariant(variant)
    local assetName = M.AssetName(normalizedVariant)
    local repositorySlug = trim(expectedRepositorySlug):lower()
    return normalizedVariant ~= nil
        and assetName ~= nil
        and REPOSITORY_PROFILES[repositorySlug] ~= nil
        and trim(cache.repositorySlug):lower() == repositorySlug
        and normalizeVariant(cache.releaseVariant) == normalizedVariant
        and trim(cache.assetName) == assetName
        and normalizeSha256(cache.assetSha256) ~= nil
end

function M.BuildDownloadUrl(latestVersion, variant, repositoryOwner, repositoryName)
    local parsed = M.ParseStableVersion(latestVersion)
    local assetName = M.AssetName(variant)
    local repository
    if repositoryOwner == nil and repositoryName == nil then
        repository = REPOSITORY_PROFILES[M.REPOSITORY_SLUG]
    else
        repository = M.ResolveRepository(repositoryOwner, repositoryName)
    end
    if not parsed or not assetName or not repository then
        return nil
    end
    return 'https://github.com/' .. repository.owner .. '/' .. repository.repo
        .. '/releases/download/' .. parsed.tag .. '/' .. assetName
end

local function parseJsonString(text, index)
    if text:sub(index, index) ~= '"' then
        return nil, index, 'expected JSON string'
    end
    index = index + 1
    local result = {}
    while index <= #text do
        local char = text:sub(index, index)
        if char == '"' then
            return table.concat(result), index + 1
        elseif char == '\\' then
            local escaped = text:sub(index + 1, index + 1)
            local replacements = {
                ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
            }
            if replacements[escaped] then
                result[#result + 1] = replacements[escaped]
                index = index + 2
            elseif escaped == 'u' then
                local hex = text:sub(index + 2, index + 5)
                if not hex:match('^%x%x%x%x$') then
                    return nil, index, 'invalid JSON unicode escape'
                end
                local code = tonumber(hex, 16)
                result[#result + 1] = code and code < 128 and string.char(code) or '?'
                index = index + 6
            else
                return nil, index, 'invalid JSON escape'
            end
        else
            if char:byte() and char:byte() < 32 then
                return nil, index, 'unescaped JSON control character'
            end
            result[#result + 1] = char
            index = index + 1
        end
    end
    return nil, index, 'unterminated JSON string'
end

local function skipWhitespace(text, index)
    while index <= #text and text:sub(index, index):match('%s') do
        index = index + 1
    end
    return index
end

function M.ParseFlatJsonObject(raw)
    local text = trim(tostring(raw or ''):gsub('^\239\187\191', ''))
    local index = skipWhitespace(text, 1)
    if text:sub(index, index) ~= '{' then
        return nil, 'expected JSON object'
    end
    index = skipWhitespace(text, index + 1)
    local values = {}
    if text:sub(index, index) == '}' then
        return values
    end
    while index <= #text do
        local key, nextIndex, keyError = parseJsonString(text, index)
        if not key then
            return nil, keyError
        end
        if values[key] ~= nil then
            return nil, 'duplicate JSON field: ' .. key
        end
        index = skipWhitespace(text, nextIndex)
        if text:sub(index, index) ~= ':' then
            return nil, 'expected JSON colon'
        end
        index = skipWhitespace(text, index + 1)
        local value
        if text:sub(index, index) == '"' then
            value, index, keyError = parseJsonString(text, index)
            if value == nil then
                return nil, keyError
            end
        else
            local startIndex = index
            while index <= #text and not text:sub(index, index):match('[,%}]') do
                index = index + 1
            end
            local scalar = trim(text:sub(startIndex, index - 1))
            if scalar == 'true' then
                value = true
            elseif scalar == 'false' then
                value = false
            elseif scalar == 'null' then
                value = false
            elseif scalar:match('^-?%d+$') then
                value = tonumber(scalar)
            else
                return nil, 'expected scalar JSON value'
            end
        end
        values[key] = value
        index = skipWhitespace(text, index)
        local separator = text:sub(index, index)
        if separator == '}' then
            index = skipWhitespace(text, index + 1)
            if index <= #text then
                return nil, 'unexpected trailing JSON data'
            end
            return values
        elseif separator ~= ',' then
            return nil, 'expected JSON comma or object end'
        end
        index = skipWhitespace(text, index + 1)
    end
    return nil, 'unterminated JSON object'
end

function M.ParseResultPairs(raw)
    local values = {}
    for line in tostring(raw or ''):gmatch('[^\r\n]+') do
        local normalized = trim(line:gsub('^\239\187\191', ''))
        local key, value = normalized:match('^([A-Z_]+)=(.*)$')
        if key then
            values[key] = trim(value)
        end
    end
    return values
end

local function luaString(value)
    return string.format('%q', tostring(value or ''))
end

local function validToken(value)
    local token = trim(value)
    return #token >= 1 and #token <= 120
        and token:match('^[A-Za-z0-9][A-Za-z0-9._-]*$') ~= nil
end

local function generatedToken()
    local clock = tostring(os.clock() or 0):gsub('[^0-9]', '')
    return 'latest-update-' .. tostring(os.time() or 0) .. '-' .. clock
end

function M.Create(options)
    options = options or {}
    local skin = options.skin or SKIN
    local client = { pending = nil, dispatchAttempts = 0 }

    local function valueOf(value)
        if type(value) == 'function' then
            return value()
        end
        return value
    end

    local function utilityConfig()
        local rootConfig = trim(skin:GetVariable('ROOTCONFIG', ''))
        return rootConfig ~= '' and (rootConfig .. M.UTILITY_SUFFIX) or ''
    end

    local function isUtilityActive(configName)
        local configState = options.configState
        return configState and type(configState.IsActive) == 'function'
            and configState.IsActive(skin, configName) == true
    end

    local function requestDispatch()
        local variableName = trim(valueOf(options.deferredVariable))
        local measureName = trim(valueOf(options.deferredMeasure))
        if variableName == '' or measureName == '' then
            return false
        end
        skin:Bang('!SetVariable', variableName, '0')
        skin:Bang('!UpdateMeasure', measureName)
        skin:Bang('!SetVariable', variableName, '1')
        skin:Bang('!UpdateMeasure', measureName)
        return true
    end

    function client:Request(
        requestToken,
        currentVersion,
        latestVersion,
        variant,
        repositoryOwner,
        repositoryName,
        cacheRepositorySlug,
        cacheReleaseVariant,
        cacheAssetName,
        cacheAssetSha256)
        local comparison = M.CompareStableVersions(currentVersion, latestVersion)
        local normalizedVariant = normalizeVariant(variant)
        local assetName = M.AssetName(normalizedVariant)
        local repository = M.ResolveRepository(repositoryOwner, repositoryName)
        local downloadUrl = M.BuildDownloadUrl(
            latestVersion, normalizedVariant, repositoryOwner, repositoryName)
        local parsedLatest = M.ParseStableVersion(latestVersion)
        local assetSha256 = normalizeSha256(cacheAssetSha256)
        if trim(cacheAssetSha256) == '' then
            assetSha256 = normalizeSha256(skin:GetVariable('VersionManagerCacheAssetSha256', ''))
        end
        local provenanceMatches = repository
            and M.CacheProvenanceMatches({
                repositorySlug = cacheRepositorySlug,
                releaseVariant = cacheReleaseVariant,
                assetName = cacheAssetName,
                assetSha256 = assetSha256,
            }, normalizedVariant, repository.slug)
        if comparison ~= -1 or not assetName or not downloadUrl or not parsedLatest
            or not provenanceMatches then
            skin:Bang(
                '!Log',
                '[LatestUpdateClient] rejected invalid, stale, or unproven latest-update request.',
                'Warning')
            return false
        end

        if self.pending == nil then
            local token = validToken(requestToken) and trim(requestToken) or generatedToken()
            self.pending = {
                token = token,
                currentVersion = trim(currentVersion),
                latestVersion = parsedLatest.tag,
                variant = normalizedVariant,
                assetName = assetName,
                assetSha256 = assetSha256,
                downloadUrl = downloadUrl,
                repositoryOwner = repository.owner,
                repositoryName = repository.repo,
                startedAt = math.max(0, math.floor(tonumber(os.time() or 0) or 0)),
            }
        end

        local configName = utilityConfig()
        if configName == '' then
            self.pending = nil
            return false
        end
        if not isUtilityActive(configName) then
            skin:Bang('!ActivateConfig', configName, 'LatestUpdate.ini')
        end
        self.dispatchAttempts = 0
        return requestDispatch()
    end

    function client:DispatchPending()
        local pending = self.pending
        if not pending then
            return false
        end
        local configName = utilityConfig()
        if configName == '' then
            self.pending = nil
            return false
        end
        if not isUtilityActive(configName) then
            self.dispatchAttempts = self.dispatchAttempts + 1
            if self.dispatchAttempts <= 20 then
                skin:Bang('!ActivateConfig', configName, 'LatestUpdate.ini')
                return requestDispatch()
            end
            skin:Bang('!Log', '[LatestUpdateClient] LatestUpdate utility did not become active.', 'Error')
            self.pending = nil
            return false
        end

        local command = 'Begin(' .. table.concat({
            luaString(pending.token),
            luaString(pending.currentVersion),
            luaString(pending.latestVersion),
            luaString(pending.variant),
            luaString(pending.assetName),
            luaString(pending.assetSha256),
            luaString(pending.downloadUrl),
            tostring(pending.startedAt),
            luaString(pending.repositoryOwner),
            luaString(pending.repositoryName),
        }, ',') .. ')'
        skin:Bang('!CommandMeasure', 'MeasureLatestUpdate', command, configName)
        self.pending = nil
        self.dispatchAttempts = 0
        return true
    end

    return client
end

return M
