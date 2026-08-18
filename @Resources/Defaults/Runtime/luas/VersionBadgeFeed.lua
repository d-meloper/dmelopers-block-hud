local M = {}

M.SCHEMA_VERSION = 3
M.REPOSITORY_SLUG = 'd-meloper/dmelopers-block-hud'
M.TEST_REPOSITORY_SLUG = 'oup030416/dmelopers-block-hud-test'

local FEED_URLS = {
    [M.REPOSITORY_SLUG] = 'https://raw.githubusercontent.com/d-meloper/dmelopers-block-hud/badges/badge-data.json',
    [M.TEST_REPOSITORY_SLUG] = 'https://raw.githubusercontent.com/oup030416/dmelopers-block-hud-test/badges/badge-data.json',
}

local VARIANTS = {
    Korea = {
        releaseKey = 'LatestReleaseKorea',
        releaseNameKey = 'LatestReleaseNameKorea',
        assetKey = 'LatestAssetNameKorea',
        sha256Key = 'LatestAssetSha256Korea',
        publishedKey = 'LatestPublishedAtUtcKorea',
        assetName = 'DMelopers-Block-HUD_Korea.zip',
    },
    Global = {
        releaseKey = 'LatestReleaseGlobal',
        releaseNameKey = 'LatestReleaseNameGlobal',
        assetKey = 'LatestAssetNameGlobal',
        sha256Key = 'LatestAssetSha256Global',
        publishedKey = 'LatestPublishedAtUtcGlobal',
        assetName = 'DMelopers-Block-HUD_Global.zip',
    },
}

local CACHE_KEYS = {
    'VersionManagerCacheLatestVersion',
    'VersionManagerCacheRepositorySlug',
    'VersionManagerCacheReleaseVariant',
    'VersionManagerCacheAssetName',
    'VersionManagerCacheAssetSha256',
    'VersionManagerCacheStatus',
    'VersionManagerCacheErrorCode',
    'VersionManagerCacheFailureHint',
    'VersionManagerCacheLastCheckedAtUtc',
    'VersionManagerCacheLastAttemptAtUtc',
    'VersionManagerCacheLastNoticeAtUtc',
    'VersionManagerCacheLastNoticeVersion',
}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function skipWhitespace(text, index)
    while index <= #text and text:sub(index, index):match('%s') do
        index = index + 1
    end
    return index
end

local function parseJsonString(text, index)
    if text:sub(index, index) ~= '"' then
        return nil, index, 'expected JSON string'
    end
    index = index + 1
    local output = {}
    while index <= #text do
        local char = text:sub(index, index)
        if char == '"' then
            return table.concat(output), index + 1
        end
        if char == '\\' then
            local escaped = text:sub(index + 1, index + 1)
            if escaped == '' then
                return nil, index, 'unterminated JSON escape'
            end
            if escaped == 'u' then
                local hex = text:sub(index + 2, index + 5)
                if #hex ~= 4 or not hex:match('^[0-9A-Fa-f]+$') then
                    return nil, index, 'invalid JSON unicode escape'
                end
                output[#output + 1] = '\\u' .. hex
                index = index + 6
            elseif escaped == '"' or escaped == '\\' or escaped == '/' or escaped == 'b'
                or escaped == 'f' or escaped == 'n' or escaped == 'r' or escaped == 't' then
                output[#output + 1] = '\\' .. escaped
                index = index + 2
            else
                return nil, index, 'invalid JSON escape'
            end
        else
            if char:byte() < 32 then
                return nil, index, 'unescaped JSON control character'
            end
            output[#output + 1] = char
            index = index + 1
        end
    end
    return nil, index, 'unterminated JSON string'
end

local function skipJsonComposite(text, index)
    local first = text:sub(index, index)
    if first ~= '{' and first ~= '[' then
        return nil, index, 'expected JSON composite value'
    end

    local stack = { first }
    index = index + 1
    while index <= #text do
        local char = text:sub(index, index)
        if char == '"' then
            local _, nextIndex, stringError = parseJsonString(text, index)
            if not nextIndex or stringError then
                return nil, index, stringError or 'invalid JSON string'
            end
            index = nextIndex
        elseif char == '{' or char == '[' then
            stack[#stack + 1] = char
            index = index + 1
        elseif char == '}' or char == ']' then
            local expected = char == '}' and '{' or '['
            if stack[#stack] ~= expected then
                return nil, index, 'mismatched JSON composite delimiter'
            end
            stack[#stack] = nil
            index = index + 1
            if #stack == 0 then
                return true, index
            end
        else
            if char:byte() < 32 and not char:match('%s') then
                return nil, index, 'unescaped JSON control character'
            end
            index = index + 1
        end
    end
    return nil, index, 'unterminated JSON composite value'
end

local function parseFlatJsonObject(raw)
    local text = tostring(raw or '')
    if text:sub(1, 3) == string.char(239, 187, 191) then
        text = text:sub(4)
    end

    local index = skipWhitespace(text, 1)
    if text:sub(index, index) ~= '{' then
        return nil, 'expected JSON object'
    end
    index = skipWhitespace(text, index + 1)

    local values = {}
    if text:sub(index, index) == '}' then
        index = skipWhitespace(text, index + 1)
        return index > #text and values or nil, index > #text and nil or 'unexpected trailing JSON data'
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

        local first = text:sub(index, index)
        local value
        local valueType
        if first == '"' then
            local valueError
            value, index, valueError = parseJsonString(text, index)
            if not value then
                return nil, valueError
            end
            valueType = 'string'
        elseif first == '{' or first == '[' then
            local compositeOk, nextIndex, compositeError = skipJsonComposite(text, index)
            if not compositeOk then
                return nil, compositeError
            end
            index = nextIndex
            value = ''
            valueType = 'composite'
        else
            local token = text:sub(index):match('^([^,%}%s]+)')
            if not token then
                return nil, 'expected scalar JSON value'
            end
            value = token
            valueType = 'scalar'
            index = index + #token
        end
        values[key] = { value = value, valueType = valueType }

        index = skipWhitespace(text, index)
        local delimiter = text:sub(index, index)
        if delimiter == '}' then
            index = skipWhitespace(text, index + 1)
            if index <= #text then
                return nil, 'unexpected trailing JSON data'
            end
            return values
        end
        if delimiter ~= ',' then
            return nil, 'expected JSON comma or object end'
        end
        index = skipWhitespace(text, index + 1)
    end

    return nil, 'unterminated JSON object'
end

local function requiredString(values, key)
    local entry = values[key]
    if not entry or entry.valueType ~= 'string' or trim(entry.value) == '' then
        return nil, 'missing string field: ' .. key
    end
    if entry.value:find('\\', 1, true) then
        return nil, 'escaped value is not allowed for field: ' .. key
    end
    return entry.value
end

local function requiredInteger(values, key)
    local entry = values[key]
    if not entry or entry.valueType ~= 'scalar' or not entry.value:match('^%d+$') then
        return nil, 'missing integer field: ' .. key
    end
    return tonumber(entry.value)
end

local function parseStableVersion(raw)
    local normalized = trim(raw)
    local major, minor, patch = normalized:match('^[vV]?(%d+)%.(%d+)%.(%d+)$')
    if not major
        or (major ~= '0' and not major:match('^[1-9]%d*$'))
        or (minor ~= '0' and not minor:match('^[1-9]%d*$'))
        or (patch ~= '0' and not patch:match('^[1-9]%d*$')) then
        return nil
    end
    return {
        tonumber(major), tonumber(minor), tonumber(patch),
        tag = 'v' .. major .. '.' .. minor .. '.' .. patch,
    }
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

function M.CompareStableVersions(leftRaw, rightRaw)
    local left = parseStableVersion(leftRaw)
    local right = parseStableVersion(rightRaw)
    if not left or not right then
        return nil
    end
    for index = 1, 3 do
        if left[index] < right[index] then
            return -1
        end
        if left[index] > right[index] then
            return 1
        end
    end
    return 0
end

function M.AssetName(variant)
    local contract = VARIANTS[normalizeVariant(variant)]
    return contract and contract.assetName or nil
end

local function supportedRepositorySlug(raw)
    local slug = trim(raw):lower()
    if slug == M.REPOSITORY_SLUG then
        return M.REPOSITORY_SLUG
    end
    if slug == M.TEST_REPOSITORY_SLUG then
        return M.TEST_REPOSITORY_SLUG
    end
    return nil
end

function M.FeedUrl(repositorySlug)
    return FEED_URLS[supportedRepositorySlug(repositorySlug)]
end

function M.CacheProvenanceMatches(cache, variant, expectedRepositorySlug)
    cache = cache or {}
    local normalizedVariant = normalizeVariant(variant)
    local assetName = M.AssetName(normalizedVariant)
    local repositorySlug = supportedRepositorySlug(
        expectedRepositorySlug == nil and M.REPOSITORY_SLUG or expectedRepositorySlug)
    return assetName ~= nil
        and repositorySlug ~= nil
        and supportedRepositorySlug(cache.repositorySlug) == repositorySlug
        and normalizeVariant(cache.releaseVariant) == normalizedVariant
        and trim(cache.assetName) == assetName
        and normalizeSha256(cache.assetSha256) ~= nil
end

function M.UtcTimestampSeconds(raw)
    local year, month, day, hour, minute, second = trim(raw):match(
        '^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$')
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    hour = tonumber(hour)
    minute = tonumber(minute)
    second = tonumber(second)
    if not year or not month or not day or not hour or not minute or not second
        or month < 1 or month > 12 or day < 1
        or hour > 23 or minute > 59 or second > 59 then
        return nil
    end

    local daysInMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and (year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)) then
        daysInMonth[2] = 29
    end
    if day > daysInMonth[month] then
        return nil
    end

    local adjustedYear = year
    if month <= 2 then
        adjustedYear = adjustedYear - 1
    end
    local era = math.floor(adjustedYear / 400)
    local yearOfEra = adjustedYear - (era * 400)
    local monthPrime = month + (month > 2 and -3 or 9)
    local dayOfYear = math.floor((153 * monthPrime + 2) / 5) + day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4)
        - math.floor(yearOfEra / 100) + dayOfYear
    local daysSinceEpoch = era * 146097 + dayOfEra - 719468
    return daysSinceEpoch * 86400 + hour * 3600 + minute * 60 + second
end

function M.ParsePayload(raw, variant, expectedRepositorySlug)
    local normalizedVariant = normalizeVariant(variant)
    local variantContract = VARIANTS[normalizedVariant]
    if not variantContract then
        return nil, 'unsupported release variant'
    end

    local values, parseError = parseFlatJsonObject(raw)
    if not values then
        return nil, parseError
    end

    local schemaVersion, schemaError = requiredInteger(values, 'SchemaVersion')
    if not schemaVersion then
        return nil, schemaError
    end
    if schemaVersion < M.SCHEMA_VERSION then
        return nil, 'unsupported badge schema version'
    end

    local expectedRepository = supportedRepositorySlug(
        expectedRepositorySlug == nil and M.REPOSITORY_SLUG or expectedRepositorySlug)
    if not expectedRepository then
        return nil, 'unexpected badge repository slug'
    end
    if values.RepoSlug ~= nil then
        local repoSlug, repoError = requiredString(values, 'RepoSlug')
        if not repoSlug then
            return nil, repoError
        end
        if supportedRepositorySlug(repoSlug) ~= expectedRepository then
            return nil, 'unexpected badge repository slug'
        end
    end

    local advertisedVersion, versionError = requiredString(values, variantContract.releaseKey)
    if not advertisedVersion then
        return nil, versionError
    end
    local latestVersion = parseStableVersion(advertisedVersion)
    if not latestVersion then
        return nil, 'variant latest release is not a stable semantic version'
    end

    local assetName = variantContract.assetName
    if values[variantContract.assetKey] ~= nil then
        local advertisedAsset, assetError = requiredString(values, variantContract.assetKey)
        if not advertisedAsset then
            return nil, assetError
        end
        if advertisedAsset ~= assetName then
            return nil, 'variant release asset name mismatch'
        end
    end

    local advertisedSha256, sha256Error = requiredString(values, variantContract.sha256Key)
    if not advertisedSha256 then
        return nil, sha256Error
    end
    local assetSha256 = normalizeSha256(advertisedSha256)
    if not assetSha256 then
        return nil, 'variant release asset SHA-256 is malformed'
    end

    local publishedAtUtc = ''
    local publishedEntry = values[variantContract.publishedKey]
    if publishedEntry and publishedEntry.valueType == 'string'
        and not publishedEntry.value:find('\\', 1, true)
        and M.UtcTimestampSeconds(publishedEntry.value) then
        publishedAtUtc = publishedEntry.value
    end

    return {
        variant = normalizedVariant,
        latestVersion = latestVersion.tag,
        assetName = assetName,
        assetSha256 = assetSha256,
        publishedAtUtc = publishedAtUtc,
    }
end

local function utcNowString()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

function M.Create(options)
    options = options or {}
    local skin = options.skin or SKIN
    local controller = {
        running = false,
        requestKind = '',
    }

    local function readVariable(name)
        return trim(skin:GetVariable(name, ''))
    end

    local function cacheSnapshot()
        return {
            latestVersion = readVariable('VersionManagerCacheLatestVersion'),
            repositorySlug = readVariable('VersionManagerCacheRepositorySlug'),
            releaseVariant = readVariable('VersionManagerCacheReleaseVariant'),
            assetName = readVariable('VersionManagerCacheAssetName'),
            assetSha256 = readVariable('VersionManagerCacheAssetSha256'),
            status = readVariable('VersionManagerCacheStatus'),
            errorCode = readVariable('VersionManagerCacheErrorCode'),
            failureHint = readVariable('VersionManagerCacheFailureHint'),
            lastCheckedAtUtc = readVariable('VersionManagerCacheLastCheckedAtUtc'),
            lastAttemptAtUtc = readVariable('VersionManagerCacheLastAttemptAtUtc'),
            lastNoticeAtUtc = readVariable('VersionManagerCacheLastNoticeAtUtc'),
            lastNoticeVersion = readVariable('VersionManagerCacheLastNoticeVersion'),
        }
    end

    local function cachePath()
        local value = options.cachePath
        if type(value) == 'function' then
            value = value()
        end
        return trim(value)
    end

    local function writeCache(values)
        local path = cachePath()
        local changed = {}
        for _, key in ipairs(CACHE_KEYS) do
            if values[key] ~= nil then
                local value = tostring(values[key] or '')
                skin:Bang('!SetVariable', key, value)
                if path ~= '' then
                    skin:Bang('!WriteKeyValue', 'Variables', key, value, path)
                end
                changed[key] = value
            end
        end
        if type(options.onCacheChanged) == 'function' then
            options.onCacheChanged(changed)
        end
    end

    local function notifyState(stateName, detail)
        if type(options.onStateChanged) == 'function' then
            options.onStateChanged(stateName, detail or '')
        end
    end

    local function currentVersion()
        local value = options.currentVersion
        if type(value) == 'function' then
            value = value()
        end
        return trim(value)
    end

    local function variant()
        local value = options.variant
        if type(value) == 'function' then
            value = value()
        end
        return trim(value)
    end

    local function repositorySlug()
        local value = options.repositorySlug
        if type(value) == 'function' then
            value = value()
        elseif value == nil then
            value = M.REPOSITORY_SLUG
        end
        return supportedRepositorySlug(value)
    end

    local function queueNotice(latestVersion, requestKind)
        local current = currentVersion()
        if M.CompareStableVersions(current, latestVersion) ~= -1 then
            return false
        end
        local cache = cacheSnapshot()
        if not M.CacheProvenanceMatches(cache, variant(), repositorySlug()) then
            return false
        end
        if type(options.onOutdated) ~= 'function'
            or options.onOutdated(current, latestVersion, requestKind) ~= true then
            return false
        end
        writeCache({
            VersionManagerCacheLastNoticeAtUtc = utcNowString(),
            VersionManagerCacheLastNoticeVersion = latestVersion,
        })
        return true
    end

    local function startRequest(requestKind)
        if controller.running then
            return true
        end
        local expectedRepository = repositorySlug()
        local feedUrl = M.FeedUrl(expectedRepository)
        if not feedUrl then
            notifyState('error', 'repository')
            return false
        end
        local webMeasureName = trim(options.webMeasure or 'MeasureVersionBadgeFeed')
        local bodyMeasureName = trim(options.bodyMeasure or 'MeasureVersionBadgeFeedBody')
        if webMeasureName == '' or bodyMeasureName == ''
            or not skin:GetMeasure(webMeasureName) or not skin:GetMeasure(bodyMeasureName) then
            notifyState('error', 'measure')
            return false
        end

        controller.running = true
        controller.requestKind = requestKind
        writeCache({ VersionManagerCacheLastAttemptAtUtc = utcNowString() })
        notifyState('checking', '')
        skin:Bang('!SetOption', webMeasureName, 'URL', feedUrl)
        skin:Bang('!CommandMeasure', webMeasureName, 'Update')
        skin:Bang('!UpdateMeasure', webMeasureName)
        return true
    end

    function controller:StartAutomatic()
        if self.running then
            return false
        end
        return startRequest('automatic')
    end

    function controller:StartManual()
        return startRequest('manual')
    end

    function controller:CompleteSuccess(raw)
        if not self.running then
            return false
        end
        local requestKind = self.requestKind
        self.running = false
        self.requestKind = ''

        local expectedRepository = repositorySlug()
        local payload, payloadError = M.ParsePayload(raw, variant(), expectedRepository)
        if not payload then
            return self:CompleteError('format', payloadError, requestKind)
        end

        local timestamp = utcNowString()
        writeCache({
            VersionManagerCacheLatestVersion = payload.latestVersion,
            VersionManagerCacheRepositorySlug = expectedRepository,
            VersionManagerCacheReleaseVariant = payload.variant,
            VersionManagerCacheAssetName = payload.assetName,
            VersionManagerCacheAssetSha256 = payload.assetSha256,
            VersionManagerCacheStatus = 'ready',
            VersionManagerCacheErrorCode = '',
            VersionManagerCacheFailureHint = '',
            VersionManagerCacheLastCheckedAtUtc = timestamp,
            VersionManagerCacheLastAttemptAtUtc = timestamp,
        })
        notifyState('success', '')
        queueNotice(payload.latestVersion, requestKind)
        return true
    end

    function controller:CompleteError(kind, detail, preservedRequestKind)
        local requestKind = preservedRequestKind or self.requestKind
        if self.running then
            self.running = false
            self.requestKind = ''
        elseif not preservedRequestKind then
            return false
        end

        local cache = cacheSnapshot()
        local validPrevious = parseStableVersion(cache.latestVersion) ~= nil
            and M.CacheProvenanceMatches(cache, variant(), repositorySlug())
            and M.UtcTimestampSeconds(cache.lastCheckedAtUtc) ~= nil
        local errorKind = trim(kind) == 'network' and 'network' or 'format'
        writeCache({
            VersionManagerCacheStatus = validPrevious and 'ready' or 'error',
            VersionManagerCacheErrorCode = errorKind == 'network' and 'badge-feed-network' or 'badge-feed-format',
            VersionManagerCacheFailureHint = errorKind == 'network' and 'offline' or 'invalid-feed',
            VersionManagerCacheLastAttemptAtUtc = utcNowString(),
        })
        notifyState('error', errorKind)
        if trim(detail) ~= '' then
            skin:Bang('!Log', '[VersionBadgeFeed] ' .. trim(detail), 'Warning')
        end
        return requestKind ~= ''
    end

    function controller:CompleteFromMeasure()
        if not self.running then
            return false
        end
        local measure = skin:GetMeasure(trim(options.bodyMeasure or 'MeasureVersionBadgeFeedBody'))
        if not measure then
            return self:CompleteError('format', 'badge feed body measure is missing')
        end
        return self:CompleteSuccess(measure:GetStringValue() or '')
    end

    function controller:IsRunning()
        return self.running == true
    end

    return controller
end

return M
