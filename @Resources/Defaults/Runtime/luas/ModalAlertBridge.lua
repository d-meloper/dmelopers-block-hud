local M = {}

local pendingAlert = nil
local alertCounter = 0
local recentProgramErrors = {}
local PROGRAM_ERROR_DEDUPE_SECONDS = 30

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function normalizeForDedupe(value)
    local normalized = trim(value)
    normalized = normalized:gsub('%s+', ' ')
    return normalized
end

local function luaString(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\')
    value = value:gsub("'", "\\'")
    value = value:gsub('\r', '\\r')
    value = value:gsub('\n', '\\n')
    return "'" .. value .. "'"
end

local function bracketedRunCommand(command)
    command = trim(command)
    if command == '' or command:find(']', 1, true) then
        return ''
    end
    return '[' .. command .. ']'
end

local function modalConfigPath(skin)
    local rootConfig = trim(skin:GetVariable('ROOTCONFIG', ''))
    if rootConfig == '' then
        return ''
    end
    return rootConfig .. '\\Modal'
end

local function diagnosticsConfigPath(skin)
    local rootConfig = trim(skin:GetVariable('ROOTCONFIG', ''))
    if rootConfig == '' then
        return ''
    end
    return rootConfig .. '\\Diagnostics'
end

local function readFile(path)
    local handle = io.open(path, 'rb')
    if not handle then
        return ''
    end
    local content = handle:read('*a') or ''
    handle:close()
    return content
end

local function normalizeRainmeterSettingsText(content)
    content = tostring(content or '')
    if content:sub(1, 2) == string.char(255, 254) or content:sub(1, 2) == string.char(254, 255) then
        content = content:sub(3)
    elseif content:sub(1, 3) == string.char(239, 187, 191) then
        content = content:sub(4)
    end
    return content:gsub('%z', '')
end

local function joinPath(base, leaf)
    base = tostring(base or '')
    if base == '' then
        return leaf
    end
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then
        return base .. leaf
    end
    return base .. '\\' .. leaf
end

local function rainmeterSettingsIniPath(skin)
    local settingsPath = trim(skin:GetVariable('SETTINGSPATH', ''))
    if settingsPath == '' then
        return ''
    end
    return joinPath(settingsPath, 'Rainmeter.ini')
end

local function isConfigActive(skin, configPath)
    configPath = trim(configPath)
    if configPath == '' then
        return false
    end

    local content = normalizeRainmeterSettingsText(readFile(rainmeterSettingsIniPath(skin)))
    if content == '' then
        return false
    end

    local inTargetSection = false
    for line in content:gmatch('[^\r\n]+') do
        local section = line:match('^%s*%[([^%]]+)%]%s*$')
        if section then
            inTargetSection = trim(section):lower() == configPath:lower()
        elseif inTargetSection then
            local active = line:match('^%s*Active%s*=%s*([^;#%s]+)')
            if active then
                return trim(active) == '1'
            end
        end
    end
    return false
end

local function logPathForHost(host)
    local logPath = trim(host.logPath)
    if logPath ~= '' then
        return logPath
    end

    local skin = host.skin or SKIN
    local rootPath = trim(skin:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    return rootPath .. 'Logs\\DMeloper\'s Block HUD Log.log'
end

local function nextToken(host)
    alertCounter = alertCounter + 1
    local source = trim(host.name)
    if source == '' then
        source = trim((host.skin or SKIN):GetVariable('CURRENTCONFIG', 'ModalAlert'))
    end
    local clockPart = tostring(os.clock() or 0):gsub('[^0-9]', '')
    return source .. '-' .. clockPart .. '-' .. tostring(alertCounter)
end

local function activateModal(host)
    local skin = host.skin or SKIN
    local configPath = modalConfigPath(skin)
    if configPath == '' or isConfigActive(skin, configPath) then
        return ''
    end
    skin:Bang('!ActivateConfig', configPath, 'Modal.ini')
    return configPath
end

local function preloadDiagnostics(host)
    local skin = host.skin or SKIN
    local configPath = diagnosticsConfigPath(skin)
    if configPath == '' or isConfigActive(skin, configPath) then
        return false
    end
    skin:Bang('!ActivateConfig', configPath, 'Diagnostics.ini')
    return true
end

local function forceCloseModal(host, configPath)
    local skin = host.skin or SKIN
    local resolvedConfigPath = trim(configPath)
    if resolvedConfigPath == '' then
        resolvedConfigPath = modalConfigPath(skin)
    end
    if resolvedConfigPath == '' then
        return false
    end
    skin:Bang('!CommandMeasure', 'MeasureModal', 'Close()', resolvedConfigPath)
    return true
end

local function markDiagnosticsSuppress(host, message)
    local skin = host.skin or SKIN
    local configPath = diagnosticsConfigPath(skin)
    if configPath == '' then
        return false
    end

    skin:Bang('!SetVariable', 'BlockHudDiagnosticsSuppressMessage', normalizeForDedupe(message), configPath)
    skin:Bang('!SetVariable', 'BlockHudDiagnosticsSuppressAt', tostring(os.time() or 0), configPath)
    return true
end

local function requestDeferredOpen(host)
    local skin = host.skin or SKIN
    local variableName = trim(host.deferredVariable)
    local measureName = trim(host.deferredMeasure)
    if variableName == '' or measureName == '' then
        return false
    end
    skin:Bang('!SetVariable', variableName, '0')
    skin:Bang('!UpdateMeasure', measureName)
    skin:Bang('!SetVariable', variableName, '1')
    skin:Bang('!UpdateMeasure', measureName)
    return true
end

function M.Preload(host)
    host = host or {}
    activateModal(host)
    preloadDiagnostics(host)
end

function M.ShowAlertByKeys(host, options)
    host = host or {}
    options = options or {}

    local skin = host.skin or SKIN
    local level = trim(options.level):lower()
    local isWarning = level == 'warn' or level == 'warning'
    if level ~= 'error' and not isWarning then
        return false
    end

    local targetConfig = trim(host.targetConfig)
    if targetConfig == '' then
        targetConfig = trim(skin:GetVariable('CURRENTCONFIG', ''))
    end

    local targetMeasure = trim(host.targetMeasure)
    if targetMeasure == '' then
        targetMeasure = 'MeasureSettingsCommit'
    end

    local summaryText = trim(options.summaryText)
    local logPath = logPathForHost({
        skin = skin,
        logPath = options.logPath or host.logPath,
    })

    local titleKey = isWarning and 'Loc_ModalAlert_WarnTitle' or 'Loc_ModalAlert_ErrorTitle'
    local messageKey = 'Loc_ModalAlert_MessageNoLog'
    local primaryKey = 'Loc_ModalAlert_OpenLog'
    local secondaryKey = 'Loc_ModalAlert_Close'
    local primaryCallback = trim(host.openLogCallback)
    if primaryCallback == '' then
        primaryCallback = 'OpenModalAlertLogFolder'
    end

    local token = nextToken(host)
    local openCommand = 'OpenByKeys('
        .. luaString(targetConfig) .. ','
        .. luaString(token) .. ','
        .. luaString(titleKey) .. ','
        .. luaString(messageKey) .. ','
        .. luaString(primaryKey) .. ','
        .. luaString(secondaryKey) .. ','
        .. luaString(targetMeasure) .. ','
        .. luaString(primaryCallback) .. ','
        .. luaString('') .. ','
        .. luaString('two') .. ','
        .. luaString(summaryText) .. ')'

    pendingAlert = {
        token = token,
        logPath = logPath,
        openCommand = openCommand,
    }

    forceCloseModal({ skin = skin })
    requestDeferredOpen(host)
    return true
end

function M.LogErrorAndAlert(host, options)
    host = host or {}
    options = options or {}

    local skin = host.skin or SKIN
    local logMessage = trim(options.logMessage or options.message or options.summaryText)
    if logMessage == '' then
        logMessage = 'Block HUD runtime error.'
    end

    markDiagnosticsSuppress({ skin = skin }, logMessage)
    skin:Bang('!Log', logMessage, 'Error')

    local source = trim(options.source or host.name)
    if source == '' then
        source = trim(skin:GetVariable('CURRENTCONFIG', 'ModalAlert'))
    end

    local dedupeKey = source .. '|' .. normalizeForDedupe(logMessage)
    local now = os.time() or 0
    local dedupeSeconds = tonumber(options.dedupeSeconds) or PROGRAM_ERROR_DEDUPE_SECONDS
    local previous = tonumber(recentProgramErrors[dedupeKey]) or 0
    recentProgramErrors[dedupeKey] = now
    if dedupeSeconds > 0 and previous > 0 and now > 0 and (now - previous) < dedupeSeconds then
        return true
    end

    local summaryText = trim(options.summaryText or options.userMessage)
    if summaryText == '' then
        summaryText = logMessage
    end

    return M.ShowAlertByKeys(host, {
        level = 'error',
        summaryKey = options.summaryKey,
        summaryText = summaryText,
        logPath = options.logPath,
    })
end

function M.OpenPending(host)
    host = host or {}
    if not pendingAlert or trim(pendingAlert.openCommand) == '' then
        return false
    end

    local skin = host.skin or SKIN
    local configPath = modalConfigPath(skin)
    if configPath == '' then
        return false
    end

    skin:Bang('!CommandMeasure', 'MeasureModal', pendingAlert.openCommand, configPath)
    return true
end

function M.OpenLogFolder(host, token)
    host = host or {}
    if not pendingAlert or trim(token) ~= trim(pendingAlert.token) then
        return false
    end

    local logPath = trim(pendingAlert.logPath)
    if logPath == '' then
        return false
    end

    local folder = logPath:match('^(.*)[\\/]') or ''
    folder = trim(folder)
    if folder == '' then
        return false
    end

    local command = bracketedRunCommand('explorer.exe "' .. folder:gsub('"', '\\"') .. '"')
    if command == '' then
        return false
    end

    local skin = host.skin or SKIN
    skin:Bang(command)
    return true
end

return M
