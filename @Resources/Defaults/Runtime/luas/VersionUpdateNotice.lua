local M = {}

local RELEASE_NOTES_URL = 'https://github.com/d-meloper/dmelopers-block-hud/releases'
M.SNOOZE_SECONDS = 24 * 60 * 60

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function resolveValue(value, ...)
    if type(value) == 'function' then
        return value(...)
    end
    return value
end

local function asBoolean(value)
    local normalized = trim(value):lower()
    return normalized == '1' or normalized == 'true' or normalized == 'yes' or normalized == 'on'
end

local function luaString(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\')
    value = value:gsub("'", "\\'")
    value = value:gsub('\r', '\\r')
    value = value:gsub('\n', '\\n')
    return "'" .. value .. "'"
end

local function defaultToken()
    local clockPart = tostring(os.clock() or 0):gsub('[^0-9]', '')
    return 'version-update-notice-' .. tostring(os.time() or 0) .. '-' .. clockPart
end

local function modalConfigName(skin)
    local rootConfig = trim(skin:GetVariable('ROOTCONFIG', ''))
    if rootConfig == '' then
        return ''
    end
    return rootConfig .. '\\Utilities\\Modal'
end

local function requestDeferredOpen(skin, variableName, measureName)
    variableName = trim(variableName)
    measureName = trim(measureName)
    if variableName == '' or measureName == '' then
        return false
    end

    skin:Bang('!SetVariable', variableName, '0')
    skin:Bang('!UpdateMeasure', measureName)
    skin:Bang('!SetVariable', variableName, '1')
    skin:Bang('!UpdateMeasure', measureName)
    return true
end

function M.ParseComparableVersion(raw)
    local normalized = trim(raw):gsub('^[vV]', '')
    local core = normalized:match('^(%d[%d%.]*)')
    if not core then
        return nil
    end

    core = core:gsub('%.$', '')
    local suffix = normalized:sub(#core + 1)
    if core == '' or core:find('%.%.', 1, true) then
        return nil
    end
    if suffix ~= '' and not suffix:match('^[-+_ ].*') then
        return nil
    end

    local parts = {}
    for value in core:gmatch('%d+') do
        parts[#parts + 1] = tonumber(value) or 0
    end
    if #parts == 0 then
        return nil
    end
    return parts
end

function M.CompareVersions(leftRaw, rightRaw)
    local left = M.ParseComparableVersion(leftRaw)
    local right = M.ParseComparableVersion(rightRaw)
    if not left or not right then
        return nil
    end

    local limit = math.max(#left, #right)
    for index = 1, limit do
        local leftPart = left[index] or 0
        local rightPart = right[index] or 0
        if leftPart < rightPart then
            return -1
        end
        if leftPart > rightPart then
            return 1
        end
    end

    return 0
end

function M.IsOutdated(currentVersion, latestVersion)
    return M.CompareVersions(currentVersion, latestVersion) == -1
end

function M.EvaluateSnooze(enabled, recordedAt, currentTime)
    if not asBoolean(enabled) then
        return false, false
    end

    local recorded = tonumber(trim(recordedAt))
    local current = tonumber(trim(currentTime)) or tonumber(os.time())
    if not recorded or recorded <= 0 or not current or current < recorded then
        return false, true
    end

    if current - recorded >= M.SNOOZE_SECONDS then
        return false, true
    end

    return true, false
end

function M.ReleaseNotesUrl()
    return RELEASE_NOTES_URL
end

function M.Create(options)
    options = options or {}
    local helper = {
        pendingOpenCommand = '',
    }

    local function skin()
        return options.skin or SKIN
    end

    local function targetConfig()
        return trim(resolveValue(options.targetConfig, helper) or skin():GetVariable('CURRENTCONFIG', ''))
    end

    local function targetMeasure()
        return trim(resolveValue(options.targetMeasure, helper) or '')
    end

    local function modalConfig()
        local resolved = trim(resolveValue(options.modalConfig, helper) or '')
        if resolved ~= '' then
            return resolved
        end
        return modalConfigName(skin())
    end

    local function deferredVariable()
        return trim(resolveValue(options.deferredVariable, helper) or '')
    end

    local function deferredMeasure()
        return trim(resolveValue(options.deferredMeasure, helper) or '')
    end

    local function primaryKey()
        local key = trim(resolveValue(options.primaryKey, helper) or '')
        if key == '' then
            return 'Loc_Hotbar_UpdateNotice_Update'
        end
        return key
    end

    local function primaryCallback()
        local callback = trim(resolveValue(options.primaryCallback, helper) or '')
        if callback ~= '' then
            return callback
        end
        return trim(resolveValue(options.updateCallback, helper) or 'StartLatestVersionUpdate')
    end

    local function secondaryKey()
        local key = trim(resolveValue(options.secondaryKey, helper) or '')
        if key == '' then
            return 'Loc_Common_Close'
        end
        return key
    end

    local function secondaryCallback()
        return trim(resolveValue(options.secondaryCallback, helper) or '')
    end

    local function modalMode()
        local mode = trim(resolveValue(options.modalMode, helper) or '')
        if mode == '' then
            return 'two-top-action'
        end
        return mode
    end

    local function token()
        local factory = options.tokenFactory
        if type(factory) == 'function' then
            return trim(factory())
        end
        return defaultToken()
    end

    local function activateIfNeeded(configName)
        local configState = options.configState
        if configName == '' then
            return
        end
        if configState and type(configState.IsActive) == 'function' then
            if not configState.IsActive(skin(), configName) then
                skin():Bang('!ActivateConfig', configName, 'Modal.ini')
            end
        end
    end

    function helper:QueueOutdated(currentVersion, latestVersion)
        currentVersion = trim(currentVersion)
        latestVersion = trim(latestVersion)
        if not M.IsOutdated(currentVersion, latestVersion) then
            return false
        end

        local configName = modalConfig()
        local ownerConfig = targetConfig()
        local measureName = targetMeasure()
        if configName == '' or ownerConfig == '' or measureName == '' then
            return false
        end

        self.pendingOpenCommand = 'OpenWithTopActionByKeysWithClosePolicy('
            .. luaString(ownerConfig) .. ','
            .. luaString(token()) .. ','
            .. luaString('Loc_Hotbar_UpdateNotice_Title') .. ','
            .. luaString('Loc_Hotbar_UpdateNotice_Message') .. ','
            .. luaString('Loc_Hotbar_UpdateNotice_ReleaseNotes') .. ','
            .. luaString(primaryKey()) .. ','
            .. luaString(secondaryKey()) .. ','
            .. luaString(measureName) .. ','
            .. luaString(trim(resolveValue(options.releaseNotesCallback, helper) or 'OpenUpdateReleaseNotes')) .. ','
            .. luaString(primaryCallback()) .. ','
            .. luaString(secondaryCallback()) .. ','
            .. luaString(modalMode()) .. ','
            .. luaString('true') .. ','
            .. luaString('true') .. ','
            .. luaString('false') .. ','
            .. luaString(latestVersion) .. ','
            .. luaString(currentVersion) .. ')'

        activateIfNeeded(configName)
        return requestDeferredOpen(skin(), deferredVariable(), deferredMeasure())
    end

    function helper:OpenPending()
        if trim(self.pendingOpenCommand) == '' then
            return false
        end

        local configName = modalConfig()
        if configName == '' then
            return false
        end

        local configState = options.configState
        if configState and type(configState.IsActive) == 'function' and not configState.IsActive(skin(), configName) then
            skin():Bang('!ActivateConfig', configName, 'Modal.ini')
            requestDeferredOpen(skin(), deferredVariable(), deferredMeasure())
            return false
        end

        skin():Bang('!CommandMeasure', 'MeasureModal', self.pendingOpenCommand, configName)
        self.pendingOpenCommand = ''
        return true
    end

    return helper
end

return M
