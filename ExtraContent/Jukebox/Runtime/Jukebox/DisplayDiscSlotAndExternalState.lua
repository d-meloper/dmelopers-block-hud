-- Split from ExtraContent\Jukebox\Jukebox.lua lines 1087-2207.
local function updateDiscSlotMeters(configName)
    if not isRainmeterConfigActive(configName) then
        return false
    end
    SKIN:Bang('!UpdateMeterGroup', 'JukeboxDiscSlot', configName)
    SKIN:Bang('!Redraw', configName)
    return true
end

local function applyDiscSlotLayout(configName, ownerRect)
    ownerRect = ownerRect or {}
    local x = tonumber(ownerRect.x)
    local y = tonumber(ownerRect.y)
    local width = tonumber(ownerRect.width)
    local height = tonumber(ownerRect.height)
    if x == nil or y == nil or width == nil or width <= 0 or height == nil or height <= 0 then
        return false
    end
    local command = string.format(
        'ApplyJukeboxDiscSlotLayout(%d,%d,%d,%d)',
        round(x),
        round(y),
        math.max(1, round(width)),
        math.max(1, round(height))
    )
    return commandMeasureForActiveConfig('MeasureResponsiveLayout', command, configName)
end


local function resetDiscSlotAnchorState()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', "SetPositionModeForIds('JukeboxDiscSlot','auto')")
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', "ClearFixedPositionsForIds('JukeboxDiscSlot')")
end
local function syncDiscSlotVisualState(configName)
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'SyncVisualState()', configName)
    end
end

local function resetDiscSlotRenderStateForClose(configName)
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'ResetRenderStateForClose()', configName)
    end
end

local function refreshDiscSlot(configName)
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'RefreshDiscs()', configName)
    end
end

local function isDiscSlotCommandTargetActive()
    local configName = discSlotConfigName()
    if isRainmeterConfigActive(configName) then
        discSlotLoaded = true
        discSlotActivationRequested = false
        return true
    end
    discSlotLoaded = false
    return false
end
local function clearDiscSlotPlaybackSelection(configName)
    if not isDiscSlotCommandTargetActive() then
        return
    end
    configName = configName or discSlotConfigName()
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'ClearPlaybackSelection()', configName)
end

local function setDiscSlotPlaybackSelection(slotIndex, slotName, configName)
    if not isDiscSlotCommandTargetActive() then
        return
    end
    configName = configName or discSlotConfigName()
    slotIndex = tonumber(slotIndex) or 0
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', string.format('SetPlaybackSelection(%d,%q)', slotIndex, tostring(slotName or '')), configName)
end

local function writePlaybackStateValue(name, value)
    local path = playbackStatePath()
    if path == '' then
        return false
    end
    SKIN:Bang('!WriteKeyValue', 'Variables', name, tostring(value or ''), path)
    return true
end

local function writeJukeboxDisplayMode(mode)
    mode = trim(mode):lower()
    if mode ~= 'minimized' then
        mode = 'main'
    end
    local previous = trim(SKIN:GetVariable('JukeboxDisplayMode', 'main')):lower()
    setVariable('JukeboxDisplayMode', mode)
    if previous ~= mode then
        writePlaybackStateValue('JukeboxDisplayMode', mode)
    end
    return mode
end

function writeJukeboxMainFormY(y)
    local value = tostring(round(tonumber(y) or 0))
    local previous = trim(SKIN:GetVariable('JukeboxMainFormY', ''))
    setVariable('JukeboxMainFormY', value)
    if previous ~= value then
        writePlaybackStateValue('JukeboxMainFormY', value)
    end
    return tonumber(value) or 0
end

function JukeboxFormResetPending()
    return trim(SKIN:GetVariable('ResponsiveLayout_Jukebox_FormResetPending', '0')) == '1'
end

function clearJukeboxFormResetPending()
    if not JukeboxFormResetPending() then
        return false
    end
    local statePath = tostring(SKIN:GetVariable('@') or '') .. 'Customs\\Data\\ResponsiveLayoutState.inc'
    setVariable('ResponsiveLayout_Jukebox_FormResetPending', '0')
    SKIN:Bang('!WriteKeyValue', 'Variables', 'ResponsiveLayout_Jukebox_FormResetPending', '0', statePath)
    return true
end

function storedJukeboxMainY(fallbackY, preferSnapshot)
    if preferSnapshot then
        local saved = tonumber(trim(SKIN:GetVariable('JukeboxMainFormY', '')))
        if saved ~= nil then
            return round(saved)
        end
    end
    local y = tonumber(trim(SKIN:GetVariable('ResponsiveLayout_Jukebox_FixedY', '')))
    if y ~= nil then
        return round(y)
    end
    return round(tonumber(fallbackY) or 0)
end

local function writeGeneralSettingValue(name, value)
    local path = generalSettingsPath()
    if path == '' then
        return false
    end
    SKIN:Bang('!WriteKeyValue', 'Variables', name, tostring(value or ''), path)
    return true
end

local function setExternalPlaybackVariable(name, value)
    setVariable(name, value)
end

function currentPlaybackVolume()
    return clampPlaybackVolume(SKIN:GetVariable('JukeboxPlaybackVolume', tostring(100)))
end

function setLocalPlaybackVolume(value, persist)
    local volume = clampPlaybackVolume(value)
    setVariable('JukeboxPlaybackVolume', tostring(volume))
    if persist then
        writePlaybackStateValue('JukeboxPlaybackVolume', tostring(volume))
    end
    return volume
end

function resetExternalCommandWatch()
    externalPlaybackState.commandWatch.active = false
    externalPlaybackState.commandWatch.command = ''
    externalPlaybackState.commandWatch.valueText = ''
    externalPlaybackState.commandWatch.ticks = 0
    externalPlaybackState.commandWatch.beforeState = ''
    externalPlaybackState.commandWatch.beforeIdentity = ''
    externalPlaybackState.commandWatch.beforePlayer = ''
    externalPlaybackState.commandWatch.supportFlag = ''
    externalPlaybackState.commandWatch.supportValue = ''
    externalPlaybackState.commandWatch.bestEffort = false
    externalPlaybackState.commandWatch.reconnectRetry = false
    externalPlaybackState.commandWatch.waitingForReconnect = false
    externalPlaybackState.commandWatch.toggleFallbackTried = false
    JukeboxScheduler.externalCommandWatchdog = false
    syncJukeboxRuntimeDriver()
end

local function resetExternalPlaybackState()
    externalPlaybackState.observed = false
    externalPlaybackState.pendingCommand = nil
    externalPlaybackState.pendingValueText = nil
    externalPlaybackState.pendingCommandReconnectRetry = false
    resetExternalCommandWatch()
    externalPlaybackState.bridgeActive = false
    externalPlaybackState.bridgeActivationRequested = false
    externalPlaybackState.bridgeReconnectRequested = false
    externalPlaybackState.status = '0'
    externalPlaybackState.player = ''
    externalPlaybackState.title = ''
    externalPlaybackState.artist = ''
    externalPlaybackState.album = ''
    externalPlaybackState.cover = ''
    externalPlaybackState:clearCoverFetchFailure()
    externalPlaybackState.coverRetryNonce = 0
    externalPlaybackState.duration = '0'
    externalPlaybackState.volume = '0'
    externalPlaybackState.state = '0'
    externalPlaybackState.repeatMode = '0'
    externalPlaybackState.shuffle = '0'
    externalPlaybackState.supportsPlayPause = '0'
    externalPlaybackState.supportsSkipPrevious = '0'
    externalPlaybackState.supportsSkipNext = '0'
    externalPlaybackState.supportsSetVolume = '0'
    externalPlaybackState.supportsToggleRepeatMode = '0'
    externalPlaybackState.supportsToggleShuffleActive = '0'
    externalPlaybackState.mediaIdentity = ''
    externalPlaybackState.visualSwitch.active = false
    externalPlaybackState.visualSwitch.token = ''
    externalPlaybackState.visualSwitch.playAfterStop = false
    externalPlaybackState.visualSwitch.mediaIdentity = ''
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    setExternalPlaybackVariable('JukeboxExternalStatus', '0')
    setExternalPlaybackVariable('JukeboxExternalPlayer', '')
    setExternalPlaybackVariable('JukeboxExternalTitle', '')
    setExternalPlaybackVariable('JukeboxExternalArtist', '')
    setExternalPlaybackVariable('JukeboxExternalAlbum', '')
    setExternalPlaybackVariable('JukeboxExternalCover', '')
    setExternalPlaybackVariable('JukeboxExternalCoverFetchFailed', '0')
    setExternalPlaybackVariable('JukeboxExternalCoverFailureIdentity', '')
    setExternalPlaybackVariable('JukeboxExternalCoverRetryNonce', '0')
    setExternalPlaybackVariable('JukeboxExternalDuration', '0')
    setExternalPlaybackVariable('JukeboxExternalVolume', '0')
    setExternalPlaybackVariable('JukeboxExternalState', '0')
    setExternalPlaybackVariable('JukeboxExternalRepeat', '0')
    setExternalPlaybackVariable('JukeboxExternalShuffle', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsPlayPause', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsSkipPrevious', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsSkipNext', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsSetVolume', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsToggleRepeatMode', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsToggleShuffleActive', '0')
end

local function isExternalBridgeActive()
    if externalPlaybackState.pluginLoadFailed or trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1' then
        return false
    end
    local configName = webNowPlayingBridgeConfigName()
    if configName == '' or not isRainmeterConfigActive(configName) then
        return false
    end
    return externalPlaybackState.bridgeActive or trim(SKIN:GetVariable('JukeboxExternalBridgeActive', '0')) == '1'
end

local function activateExternalBridge()
    if externalPlaybackState.pluginLoadFailed or trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1' then
        return false
    end
    local configName = webNowPlayingBridgeConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end
    if isExternalBridgeActive() then
        return true
    end
    if isRainmeterConfigActive(configName) then
        externalPlaybackState.bridgeActivationRequested = true
        return true
    end
    if externalPlaybackState.bridgeActivationRequested then
        return true
    end
    externalPlaybackState.bridgeActive = false
    externalPlaybackState.bridgeActivationRequested = true
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    SKIN:Bang('!ActivateConfig', configName, 'WebNowPlayingBridge.ini')
    return true
end

local function deactivateExternalBridge()
    externalPlaybackState.pendingCommand = nil
    externalPlaybackState.pendingValueText = nil
    externalPlaybackState.pendingCommandReconnectRetry = false
    externalPlaybackState.bridgeActivationRequested = false
    externalPlaybackState.bridgeReconnectRequested = false
    local configName = webNowPlayingBridgeConfigName()
    if configName ~= '' and isRainmeterConfigActive(configName) then
        SKIN:Bang('!DeactivateConfig', configName)
    end
    externalPlaybackState.bridgeActive = false
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    return true
end

local function quarantineExternalBridgeForStartup(forceDeactivate)
    externalPlaybackState.pendingCommand = nil
    externalPlaybackState.pendingValueText = nil
    externalPlaybackState.pendingCommandReconnectRetry = false
    externalPlaybackState.bridgeActivationRequested = false
    externalPlaybackState.bridgeReconnectRequested = false
    externalPlaybackState.bridgeActive = false
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')

    local configName = webNowPlayingBridgeConfigName()
    if configName ~= '' and configName:find('[\\/]') and (forceDeactivate or isRainmeterConfigActive(configName)) then
        SKIN:Bang('!DeactivateConfig', configName)
    end
    return true
end

local function syncExternalBridgeForMode()
    if isExternalPlaybackSourceMode() then
        if commandRunning.webNowPlayingInstall or trim(webNowPlayingInstallState.phase) ~= '' then
            return false
        end
        return activateExternalBridge()
    end
    deactivateExternalBridge()
    resetExternalPlaybackState()
    externalPlaybackState.pluginLoadFailed = false
    externalPlaybackState.bridgeFailureAlertShown = false
    setExternalPlaybackVariable('JukeboxExternalBridgePluginFailed', '0')
    return true
end

local function syncDiscSlotPlaybackModeControls(configName)
    configName = configName or discSlotConfigName()
    if not isDiscSlotCommandTargetActive() then
        return false
    end
    local repeatMode = currentRepeatMode()
    local shuffleEnabled = currentShuffleEnabled()
    if isExternalPlaybackSourceMode() then
        repeatMode = externalRepeatMode()
        shuffleEnabled = externalShuffleEnabled()
    end
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackSourceMode', currentPlaybackSourceMode(), configName)
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackRepeatMode', repeatMode, configName)
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackShuffle', shuffleEnabled and '1' or '0', configName)
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackVolume', tostring(currentPlaybackVolume()), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalBridgeActive', isExternalBridgeActive() and '1' or '0', configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalStatus', trim(externalPlaybackState.status), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalPlayer', trim(externalPlaybackState.player), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalTitle', trim(externalPlaybackState.title), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalArtist', trim(externalPlaybackState.artist), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalAlbum', trim(externalPlaybackState.album), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCover', trim(externalPlaybackState.cover), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCoverFetchFailed', externalPlaybackState:coverFailureMatchesCurrent() and '1' or '0', configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCoverFailureIdentity', trim(externalPlaybackState.coverFailureIdentity), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCoverRetryNonce', tostring(tonumber(externalPlaybackState.coverRetryNonce) or 0), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalDuration', trim(externalPlaybackState.duration), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalVolume', trim(externalPlaybackState.volume), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalState', trim(externalPlaybackState.state), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsPlayPause', trim(externalPlaybackState.supportsPlayPause), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsSkipPrevious', trim(externalPlaybackState.supportsSkipPrevious), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsSkipNext', trim(externalPlaybackState.supportsSkipNext), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsSetVolume', trim(externalPlaybackState.supportsSetVolume), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsToggleRepeatMode', trim(externalPlaybackState.supportsToggleRepeatMode), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsToggleShuffleActive', trim(externalPlaybackState.supportsToggleShuffleActive), configName)
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'SyncVisualState()', configName)
    return true
end

local function syncSettingsPlaybackSourceMode()
    local mode = currentPlaybackSourceMode()
    local root = rootConfigName()
    local configName = root == '' and 'HUD\\Settings' or root .. '\\HUD\\Settings'
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!SetVariable', 'JukeboxPlaybackSourceMode', mode, configName)
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsCommit', 'SyncJukeboxPlaybackSourceMode()', configName)
    end
end
local function syncPlaybackModeState(persist, skipDiscSlotSync)
    local mode = currentRepeatMode()
    local shuffle = currentShuffleEnabled()
    setVariable('JukeboxPlaybackRepeatMode', mode)
    setVariable('JukeboxPlaybackShuffle', shuffle and '1' or '0')
    if persist then
        writePlaybackStateValue('JukeboxPlaybackRepeatMode', mode)
        writePlaybackStateValue('JukeboxPlaybackShuffle', shuffle and '1' or '0')
    end
    if not skipDiscSlotSync then
        syncDiscSlotPlaybackModeControls()
    end
    return mode, shuffle
end

local function requestHelperLoopModeSync()
    if isExternalPlaybackSourceMode() then
        return false
    end
    if runMeasure then
        return runMeasure('loop', 'MeasureJukeboxSetLoopRun', 'ModalAlert_JukeboxCommandFailed')
    end
    return false
end

function requestHelperVolumeSync(volume)
    if isExternalPlaybackSourceMode() then
        return false
    end
    if commandRunning.volume then
        commandRunning.volumePending = true
        return true
    end
    setVariable('JukeboxSetVolumeArgs', buildArgs('SetVolume', '', '', isPlaybackLoopEnabled(), clampPlaybackVolume(volume)))
    if runMeasure then
        return runMeasure('volume', 'MeasureJukeboxSetVolumeRun', 'ModalAlert_JukeboxCommandFailed')
    end
    return false
end

local function persistPlaybackSelection(slotIndex, slotName, path)
    slotIndex = tonumber(slotIndex) or 0
    slotName = tostring(slotName or '')
    path = tostring(path or '')
    writePlaybackStateValue('JukeboxPlaybackSelectedActive', '1')
    writePlaybackStateValue('JukeboxPlaybackSelectedSlotIndex', tostring(slotIndex))
    writePlaybackStateValue('JukeboxPlaybackSelectedName', slotName)
    writePlaybackStateValue('JukeboxPlaybackSelectedPath', path)
    setVariable('JukeboxPlaybackSelectedActive', '1')
    setVariable('JukeboxPlaybackSelectedSlotIndex', tostring(slotIndex))
    setVariable('JukeboxPlaybackSelectedName', slotName)
    setVariable('JukeboxPlaybackSelectedPath', path)
end

local function clearPersistedPlaybackSelection()
    writePlaybackStateValue('JukeboxPlaybackSelectedActive', '0')
    writePlaybackStateValue('JukeboxPlaybackSelectedSlotIndex', '0')
    writePlaybackStateValue('JukeboxPlaybackSelectedName', '')
    writePlaybackStateValue('JukeboxPlaybackSelectedPath', '')
    setVariable('JukeboxPlaybackSelectedActive', '0')
    setVariable('JukeboxPlaybackSelectedSlotIndex', '0')
    setVariable('JukeboxPlaybackSelectedName', '')
    setVariable('JukeboxPlaybackSelectedPath', '')
end

local function currentPlaybackSelection()
    return {
        active = trim(SKIN:GetVariable('JukeboxPlaybackSelectedActive', '0')) == '1',
        slotIndex = tonumber(trim(SKIN:GetVariable('JukeboxPlaybackSelectedSlotIndex', '0'))) or 0,
        slotName = trim(SKIN:GetVariable('JukeboxPlaybackSelectedName', '')),
        path = trim(SKIN:GetVariable('JukeboxPlaybackSelectedPath', '')),
    }
end

local function slotMatchesPlaybackSelection(slotIndex, slotName, path, state)
    state = state or currentPlaybackSelection()
    if not state.active then
        return false
    end
    slotIndex = tonumber(slotIndex) or 0
    slotName = trim(slotName)
    path = trim(path)
    if state.slotIndex > 0 and state.slotIndex == slotIndex and state.slotName == slotName then
        return true
    end
    return state.path ~= '' and path ~= '' and state.path == path
end

local function shouldSwitchDiscSlotPlayback(slotIndex, slotName, path)
    local state = currentPlaybackSelection()
    if not state.active then
        return false
    end
    return not slotMatchesPlaybackSelection(slotIndex, slotName, path, state)
end

local function captureJukeboxLiveState()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()')
end

function JukeboxApplyCurrentResponsiveLayout()
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
end

local function currentJukeboxLiveRect()
    local x = round(tonumber(SKIN:GetVariable('CURRENTCONFIGX', '0')) or 0)
    local y = round(tonumber(SKIN:GetVariable('CURRENTCONFIGY', '0')) or 0)
    local minimized = JukeboxIsMinimizedForm and JukeboxIsMinimizedForm()
    local widthVariable = minimized and 'JukeboxMinimizedW' or 'JukeboxW'
    local heightVariable = minimized and 'JukeboxMinimizedH' or 'JukeboxH'
    local width = tonumber(SKIN:GetVariable(widthVariable, ''))
    local height = tonumber(SKIN:GetVariable(heightVariable, ''))
    if not width or width <= 0 then
        width = tonumber(SKIN:GetVariable('CURRENTCONFIGWIDTH', '0'))
    end
    if not height or height <= 0 then
        height = tonumber(SKIN:GetVariable('CURRENTCONFIGHEIGHT', '0'))
    end
    if not width or width <= 0 then
        width = 100
    end
    if not height or height <= 0 then
        height = 126
    end
    return {
        x = x,
        y = y,
        width = round(width),
        height = round(height),
    }
end

function JukeboxCurrentWorkArea()
    local x = round(tonumber(SKIN:GetVariable('PWORKAREAX', '0')) or 0)
    local y = round(tonumber(SKIN:GetVariable('PWORKAREAY', '0')) or 0)
    local width = math.max(1, round(tonumber(SKIN:GetVariable('PWORKAREAWIDTH', '1920')) or 1920))
    local height = math.max(1, round(tonumber(SKIN:GetVariable('PWORKAREAHEIGHT', '1032')) or 1032))
    return {
        x = x,
        y = y,
        width = width,
        height = height,
        right = x + width,
        bottom = y + height,
    }
end

function JukeboxMonitorFallbackActive()
    return trim(SKIN:GetVariable('ResponsiveLayoutCurrentFallbackActive', '0')) == '1'
end

function JukeboxWorkAreaRect(x, y, width, height)
    x = round(tonumber(x) or 0)
    y = round(tonumber(y) or 0)
    width = math.max(1, round(tonumber(width) or 1))
    height = math.max(1, round(tonumber(height) or 1))
    return {
        x = x,
        y = y,
        width = width,
        height = height,
        right = x + width,
        bottom = y + height,
        centerX = x + (width / 2),
        centerY = y + (height / 2),
    }
end

function JukeboxMonitorWorkAreas()
    local result = {}
    local seen = {}
    for index = 1, 16 do
        local x = tonumber(SKIN:GetVariable('WORKAREAX@' .. tostring(index), ''))
        local y = tonumber(SKIN:GetVariable('WORKAREAY@' .. tostring(index), ''))
        local width = tonumber(SKIN:GetVariable('WORKAREAWIDTH@' .. tostring(index), ''))
        local height = tonumber(SKIN:GetVariable('WORKAREAHEIGHT@' .. tostring(index), ''))
        if x and y and width and height and width > 0 and height > 0 then
            local rect = JukeboxWorkAreaRect(x, y, width, height)
            local key = table.concat({ rect.x, rect.y, rect.width, rect.height }, ':')
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = rect
            end
        end
    end
    return result
end

function JukeboxRectContainsPoint(rect, x, y)
    return rect and x >= rect.x and x < rect.right and y >= rect.y and y < rect.bottom
end

function JukeboxDistanceSquaredToRectCenter(rect, x, y)
    local dx = (rect.centerX or 0) - x
    local dy = (rect.centerY or 0) - y
    return (dx * dx) + (dy * dy)
end

function JukeboxWorkAreaForPoint(x, y, fallback)
    x = round(tonumber(x) or 0)
    y = round(tonumber(y) or 0)
    local areas = JukeboxMonitorWorkAreas()
    local best = nil
    local bestDistance = nil
    for _, area in ipairs(areas) do
        if JukeboxRectContainsPoint(area, x, y) then
            return area
        end
        local distance = JukeboxDistanceSquaredToRectCenter(area, x, y)
        if best == nil or distance < bestDistance then
            best = area
            bestDistance = distance
        end
    end
    return best or fallback
end

function JukeboxWorkAreaForRect(rect, fallback)
    rect = rect or currentJukeboxLiveRect()
    local width = math.max(1, round(tonumber(rect.width) or 100))
    local height = math.max(1, round(tonumber(rect.height) or 126))
    local x = round((tonumber(rect.x) or 0) + (width / 2))
    local y = round((tonumber(rect.y) or 0) + (height / 2))
    return JukeboxWorkAreaForPoint(x, y, fallback)
end

function JukeboxClampToRange(value, minValue, maxValue)
    value = tonumber(value) or 0
    if maxValue < minValue then
        maxValue = minValue
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function JukeboxClampRectToWorkArea(rect)
    rect = rect or currentJukeboxLiveRect()
    local width = math.max(1, round(tonumber(rect.width) or 100))
    local height = math.max(1, round(tonumber(rect.height) or 126))
    local work = JukeboxWorkAreaForRect(rect, JukeboxCurrentWorkArea())
    return {
        x = round(JukeboxClampToRange(rect.x, work.x, work.right - width)),
        y = round(JukeboxClampToRange(rect.y, work.y, work.bottom - height)),
        width = width,
        height = height,
    }
end

local function syncJukeboxLiveStateToDiscSlot(configName, rect)
    configName = configName or discSlotConfigName()
    rect = rect or currentJukeboxLiveRect()
    if not isRainmeterConfigActive(configName) then
        return false
    end
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveActive', '1', configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveWindowX', tostring(rect.x), configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveWindowY', tostring(rect.y), configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveWidth', tostring(rect.width), configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveHeight', tostring(rect.height), configName)
    return true
end

local function isDiscSlotActive()
    return trim(SKIN:GetVariable('ResponsiveLayout_JukeboxDiscSlot_LiveActive', '0')) == '1'
end

local function scheduleDiscSlotDeferredSync()
    discSlotDeferredAttempts = 0
    discSlotRefreshRecoveryRequested = false
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Execute 1')
end

local function isJukeboxDragAllowed()
    return trim(SKIN:GetVariable('AllowJukeboxDrag', '1')) == '1'
end

local function isJukeboxSnapAllowed()
    return trim(SKIN:GetVariable('AllowJukeboxSnapEdges', '0')) == '1'
end

local function setJukeboxDraggable(enabled)
    SKIN:Bang('!Draggable', enabled and isJukeboxDragAllowed() and '1' or '0')
    SKIN:Bang('!SnapEdges', isJukeboxSnapAllowed() and '1' or '0')
end

local function setDiscSlotHidden(hidden)
    local configName = discSlotConfigName()
    if setVariableForActiveConfig('JukeboxDiscSlotHidden', hidden and '1' or '0', configName) then
        updateDiscSlotMeters(configName)
        if hidden then
            JukeboxDiscSlotLifecycleSurface():CommandIfActive('MeasureJukeboxDiscSlot', 'SuspendDiscSlotResident()')
        end
    end
    return configName
end

local function deactivateDiscSlotSkin()
    discSlotPendingShow = false
    discSlotPendingShowSkipRefresh = false
    local configName = discSlotConfigName()
    local surface = JukeboxDiscSlotLifecycleSurface()
    if isRainmeterConfigActive(configName) then
        resetDiscSlotRenderStateForClose(configName)
        setDiscSlotHidden(true)
        syncDiscSlotVisualState(configName)
        surface:HideIfActive()
        discSlotLoaded = true
    else
        discSlotLoaded = false
    end
    discSlotActivationRequested = false
    setJukeboxDraggable(true)
    discSlotVisible = false
    return true
end
local function activateDiscSlot()
    local configName = discSlotConfigName()
    if isRainmeterConfigActive(configName) then
        discSlotLoaded = true
        discSlotActivationRequested = false
        discSlotRefreshRecoveryRequested = false
        return configName, false
    end
    if discSlotActivationRequested then
        return configName, true
    end
    discSlotLoaded = false
    JukeboxDiscSlotLifecycleSurface():ActivateIfInactive()
    discSlotActivationRequested = true
    discSlotLoaded = true
    return configName, true
end
local showDiscSlotNow = nil
function PreloadDiscSlotSkin()
    local configName = discSlotConfigName()
    if discSlotPendingShow then
        return false
    end
    if discSlotVisible and isDiscSlotCommandTargetActive() then
        return showDiscSlotNow(configName, true)
    end
    if isDiscSlotCommandTargetActive() then
        setVariableForActiveConfig('JukeboxDiscSlotHidden', '1', configName)
    end
    discSlotVisible = false
    return true
end

showDiscSlotNow = function(configName, skipRefresh)
    configName = configName or discSlotConfigName()
    local surface = JukeboxDiscSlotLifecycleSurface()
    if not surface:SetVariableIfActive('JukeboxDiscSlotHidden', '0') then
        discSlotLoaded = false
        discSlotActivationRequested = false
        discSlotRefreshRecoveryRequested = false
        return false
    end
    local ownerRect = currentJukeboxLiveRect()
    surface:CommandIfActive('MeasureJukeboxDiscSlot', 'ResumeDiscSlotResident()')
    syncJukeboxLiveStateToDiscSlot(configName, ownerRect)
    applyDiscSlotLayout(configName, ownerRect)
    surface:ShowIfActive()
    syncDiscSlotPlaybackModeControls(configName)
    updateDiscSlotMeters(configName)
    setJukeboxDraggable(false)
    discSlotVisible = true
    discSlotPendingShow = false
    discSlotPendingShowSkipRefresh = false
    discSlotActivationRequested = false
    discSlotRefreshRecoveryRequested = false
    discSlotDeferredAttempts = 0
    if not skipRefresh then
        refreshDiscSlot(configName)
    end
    return true
end
local function formatSummary(summary, placeholders)
    summary = tostring(summary or '')
    if type(placeholders) ~= 'table' then
        placeholders = { placeholders }
    end
    for index, placeholder in ipairs(placeholders) do
        local replacement = trim(placeholder):gsub('%%', '%%%%')
        summary = summary:gsub('%%' .. tostring(index), replacement)
    end
    return summary
end

local function decodeCatalogEscapes(value)
    return tostring(value or '')
        :gsub('\\n', '\n')
        :gsub('\\r', '\r')
        :gsub('\\t', '\t')
end

local function localizedSummary(key, fallback, placeholders)
    key = trim(key)
    local summary = ''
    if key ~= '' then
        summary = trim(SKIN:GetVariable('Loc_' .. key, fallback or ''))
    end
    if summary == '' then
        summary = trim(fallback or '')
    end
    return formatSummary(decodeCatalogEscapes(summary), placeholders)
end

local function showAlert(level, summaryKey, fallback, logPath, placeholder, options)
    local modal = ensureBridge()
    if not modal then
        SKIN:Bang('!Log', trim(fallback or 'Jukebox alert could not be shown.'), 'Error')
        return false
    end

    options = options or {}
    return modal.ShowAlertByKeys(modalAlertHost(), {
        level = level,
        summaryKey = summaryKey,
        summaryText = localizedSummary(summaryKey, fallback, placeholder),
        logPath = logPath or modalAlertLogPath(),
        primaryKey = options.primaryKey,
        openFolderPath = options.openFolderPath,
    })
end

function webNowPlayingInstallState.luaString(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\')
    value = value:gsub("'", "\\'")
    value = value:gsub('\r', '\\r')
    value = value:gsub('\n', '\\n')
    return "'" .. value .. "'"
end

function webNowPlayingInstallState.localized(key, englishFallback, koreanFallback)
    local languageCode = trim(SKIN:GetVariable('LanguageCode', '')):lower()
    local fallback = englishFallback
    if languageCode:find('ko', 1, true) == 1 then
        fallback = koreanFallback or englishFallback
    end
    return localizedSummary(key, fallback)
end

function webNowPlayingInstallState.localizedWithPlaceholder(key, englishFallback, koreanFallback, placeholder)
    local languageCode = trim(SKIN:GetVariable('LanguageCode', '')):lower()
    local fallback = englishFallback
    if languageCode:find('ko', 1, true) == 1 then
        fallback = koreanFallback or englishFallback
    end
    return localizedSummary(key, fallback, placeholder)
end

function webNowPlayingInstallState.modalConfigName()
    local root = rootConfigName()
    if root == '' then
        return 'Utilities\\Modal'
    end
    return root .. '\\Utilities\\Modal'
end

function webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.token = webNowPlayingInstallState.token + 1
    if webNowPlayingInstallState.token > 1000000 then
        webNowPlayingInstallState.token = 1
    end
    return 'web-now-playing-install-' .. tostring(webNowPlayingInstallState.token)
end

function webNowPlayingInstallState.requestDeferredOpen()
    SKIN:Bang('!SetVariable', 'BlockHudJukeboxWebNowPlayingInstallDeferredOpen', '0')
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxWebNowPlayingInstallDeferredOpen')
    SKIN:Bang('!SetVariable', 'BlockHudJukeboxWebNowPlayingInstallDeferredOpen', '1')
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxWebNowPlayingInstallDeferredOpen')
end

function webNowPlayingInstallState.openInstallConfirm()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenConfirm('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingInstallTitle', 'Plugin installation', '플러그인 설치')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingInstallMessage', 'Install the WebNowPlaying plugin for external music app integration. (Size: 52.5KB)', '외부 뮤직 앱 연동을 위해 WebNowPlaying 플러그인을 설치합니다. (용량: 52.5KB)')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingInstallButton', 'Install', '설치')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('Common_Cancel', 'Cancel', '취소')) .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('ConfirmWebNowPlayingInstall') .. ','
        .. webNowPlayingInstallState.luaString('CancelWebNowPlayingInstall') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end

function webNowPlayingInstallState.portOwnerFallbackLabel()
    return webNowPlayingInstallState.localized(
        'ModalAlert_WebNowPlayingUnknownOwner',
        'another Windows local account',
        'another Windows local account')
end

function webNowPlayingInstallState.setPortOwner(values)
    values = values or {}
    webNowPlayingInstallState.ownerPid = trim(values.DMEL_OWNER_PID or '')
    webNowPlayingInstallState.ownerUser = trim(values.DMEL_OWNER_USER or '')
    webNowPlayingInstallState.ownerDomain = trim(values.DMEL_OWNER_DOMAIN or '')
    if webNowPlayingInstallState.ownerUser ~= '' and webNowPlayingInstallState.ownerDomain ~= '' then
        webNowPlayingInstallState.ownerLabel = webNowPlayingInstallState.ownerDomain .. '\\' .. webNowPlayingInstallState.ownerUser
    elseif webNowPlayingInstallState.ownerUser ~= '' then
        webNowPlayingInstallState.ownerLabel = webNowPlayingInstallState.ownerUser
    else
        webNowPlayingInstallState.ownerLabel = webNowPlayingInstallState.portOwnerFallbackLabel()
    end
end

function webNowPlayingInstallState.openPortOwnerTerminateConfirm()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenConfirm('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingConflictTitle', 'Music app conflict', 'Music app conflict')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingPortInUseOtherUser', 'Rainmeter is running in another Windows local account and is connected to the WebNowPlaying port, causing a conflict.\\nTo use an external music app in the current local account, the process in the other local account must be terminated.\\nTerminate that Rainmeter process now?', 'Rainmeter is running in another Windows local account and is connected to the WebNowPlaying port, causing a conflict.\\nTo use an external music app in the current local account, the process in the other local account must be terminated.\\nTerminate that Rainmeter process now?')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingTerminateOtherProcess', 'Terminate process', 'Terminate process')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('Common_Close', 'Close', 'Close')) .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('ConfirmWebNowPlayingPortOwnerTerminate') .. ','
        .. webNowPlayingInstallState.luaString('CancelWebNowPlayingPortOwnerTerminate') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end

function webNowPlayingInstallState.openPortOwnerForceConfirm()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenConfirm('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingConflictTitle', 'Music app conflict', 'Music app conflict')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingTerminateConfirm', 'Force termination can cause unexpected problems. We recommend logging into that Windows account and closing Rainmeter manually. Force terminate now?', 'Force termination can cause unexpected problems. We recommend logging into that Windows account and closing Rainmeter manually. Force terminate now?')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingForceTerminate', 'Force terminate', 'Force terminate')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('Common_Close', 'Close', 'Close')) .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('ForceTerminateWebNowPlayingPortOwner') .. ','
        .. webNowPlayingInstallState.luaString('CancelWebNowPlayingPortOwnerTerminate') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end

function webNowPlayingInstallState.openInstallProgress()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenByKeys('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString('Loc_ModalAlert_WebNowPlayingInstallTitle') .. ','
        .. webNowPlayingInstallState.luaString('Loc_ModalAlert_WebNowPlayingInstallProgress') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('none') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end
function webNowPlayingInstallState.showInstallAlert(level, key, englishFallback, koreanFallback)
    local languageCode = trim(SKIN:GetVariable('LanguageCode', '')):lower()
    local fallback = englishFallback
    if languageCode:find('ko', 1, true) == 1 then
        fallback = koreanFallback or englishFallback
    end
    return showAlert(level, key, fallback, modalAlertLogPath())
end
local function hotbarConfigName()
    local root = trim(SKIN:GetVariable('ROOTCONFIG', ''))
    if root == '' then
        return ''
    end
    return root .. '\\HUD\\Hotbar'
end

local function currentPlaybackHotbarText(trackName)
    return localizedSummary('Jukebox_NowPlayingFormat', 'Now playing: %1', trackName)
end

local function showHotbarText(text, pinned)
    text = trim(text)
    if text == '' then
        return false
    end

    local configName = hotbarConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local command = pinned
        and string.format('ShowPinnedExternalHotbarText(%q,%q,%q)', 'Jukebox', text, 'scroll')
        or string.format('ShowExternalHotbarText(%q,%q)', text, 'scroll')
    commandMeasureForActiveConfig('MeasureHighlight', command, configName)
    return true
end

local function showCurrentPlaybackHotbarTextForSelection(selection, pinned)
    selection = selection or currentPlaybackSelection()
    if not selection.active then
        return false
    end

    local trackName = trim(selection.slotName)
    if trackName == '' then
        return false
    end

    return showHotbarText(currentPlaybackHotbarText(trackName), pinned)
end

local function externalPlaybackDisplayName()
    local title = trim(externalPlaybackState.title)
    local artist = trim(externalPlaybackState.artist)
    if title ~= '' and artist ~= '' then
        return title .. ' - ' .. artist
    elseif title ~= '' then
        return title
    elseif artist ~= '' then
        return artist
    end
    return ''
end

local function externalPlaybackConnected()
    if externalPlaybackState.pluginLoadFailed or not externalPlaybackState.bridgeActive then
        return false
    end
    -- WebNowPlaying Status is the connection signal; Player is display metadata and may be blank for some native/desktop sources.
    return trim(externalPlaybackState.status) == '1'
end

function externalCommandSupportFlag(command)
    if command == 'PlayPause' or command == 'Play' or command == 'Pause' then
        return 'supportsPlayPause'
    elseif command == 'Next' then
        return 'supportsSkipNext'
    elseif command == 'Previous' then
        return 'supportsSkipPrevious'
    elseif command == 'Repeat' then
        return 'supportsToggleRepeatMode'
    elseif command == 'Shuffle' then
        return 'supportsToggleShuffleActive'
    elseif command == 'SetVolume' then
        return 'supportsSetVolume'
    end
    return ''
end

function externalCommandCanRunBestEffort(command)
    return command == 'PlayPause' or command == 'Play' or command == 'Pause' or command == 'Next' or command == 'Previous'
end

function externalCommandLogKey(reason, command, suffix)
    return tostring(reason or '') .. ':' .. tostring(command or '') .. ':' .. tostring(suffix or '')
end

function logExternalCommand(message, level)
    SKIN:Bang('!Log', tostring(message or ''), level or 'Notice')
end

function logExternalCommandThrottled(key, message, level, throttleSeconds)
    key = tostring(key or '')
    local now = os.time() or 0
    local throttle = tonumber(throttleSeconds) or EXTERNAL_COMMAND_LOG_THROTTLE_SECONDS
    local previous = externalPlaybackState.commandLogTimes[key] or 0
    if previous > 0 and now < previous + throttle then
        return false
    end
    externalPlaybackState.commandLogTimes[key] = now
    logExternalCommand(message, level)
    return true
end

function externalCommandSupportState(command)
    local supportFlag = externalCommandSupportFlag(command)
    if supportFlag == '' then
        return '', '', true, false
    end
    local supportValue = trim(externalPlaybackState[supportFlag]):lower()
    local supported = supportValue == '1' or supportValue == 'true'
    local bestEffort = false
    if not supported and externalCommandCanRunBestEffort(command) and externalPlaybackConnected() then
        bestEffort = true
        supported = true
    end
    return supportFlag, supportValue, supported, bestEffort
end

local showCurrentExternalPlaybackHotbarText
showExternalPlayerUnavailable = nil

function beginExternalCommandWatch(command, valueText, supportFlag, supportValue, bestEffort, reconnectRetry, toggleFallbackTried)
    externalPlaybackState.commandWatch.active = true
    externalPlaybackState.commandWatch.command = trim(command)
    externalPlaybackState.commandWatch.valueText = trim(valueText)
    externalPlaybackState.commandWatch.ticks = 0
    externalPlaybackState.commandWatch.beforeState = trim(externalPlaybackState.state)
    externalPlaybackState.commandWatch.beforeIdentity = externalPlaybackState:trackIdentity()
    externalPlaybackState.commandWatch.beforePlayer = trim(externalPlaybackState.player)
    externalPlaybackState.commandWatch.supportFlag = trim(supportFlag)
    externalPlaybackState.commandWatch.supportValue = trim(supportValue)
    externalPlaybackState.commandWatch.bestEffort = bestEffort and true or false
    externalPlaybackState.commandWatch.reconnectRetry = reconnectRetry and true or false
    externalPlaybackState.commandWatch.waitingForReconnect = false
    externalPlaybackState.commandWatch.toggleFallbackTried = toggleFallbackTried and true or false
    JukeboxScheduler.externalCommandWatchdog = true
    syncJukeboxRuntimeDriver()
end

function externalCommandObservedResult()
    if not externalPlaybackState.commandWatch.active then
        return true
    end
    if externalPlaybackState.pluginLoadFailed or not externalPlaybackConnected() then
        return false
    end
    local command = externalPlaybackState.commandWatch.command
    local currentState = trim(externalPlaybackState.state)
    if command == 'Play' then
        return currentState == '1'
    elseif command == 'Pause' then
        return currentState ~= '1'
    elseif command == 'PlayPause' then
        return currentState ~= '' and currentState ~= externalPlaybackState.commandWatch.beforeState
    elseif command == 'Next' or command == 'Previous' then
        local beforeIdentity = trim(externalPlaybackState.commandWatch.beforeIdentity)
        local currentIdentity = externalPlaybackState:trackIdentity()
        return beforeIdentity ~= '' and currentIdentity ~= '' and currentIdentity ~= beforeIdentity
    elseif command == 'Repeat' then
        return trim(externalPlaybackState.repeatMode) ~= ''
    elseif command == 'Shuffle' then
        return trim(externalPlaybackState.shuffle) ~= ''
    elseif command == 'SetVolume' then
        return trim(externalPlaybackState.volume) == trim(externalPlaybackState.commandWatch.valueText)
    end
    return true
end

function finishExternalCommandWatchIfObserved()
    if externalPlaybackState.commandWatch.active and externalCommandObservedResult() then
        resetExternalCommandWatch()
        return true
    end
    return false
end

function requestExternalBridgeReconnect(command, valueText)
    command = trim(command)
    if command == '' or externalPlaybackState.bridgeReconnectRequested then
        return false
    end
    local configName = webNowPlayingBridgeConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end
    local requested = false
    if isRainmeterConfigActive(configName) then
        requested = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', 'Reconnect()', configName)
    else
        externalPlaybackState.bridgeActivationRequested = false
        requested = activateExternalBridge()
    end
    if not requested then
        return false
    end
    externalPlaybackState.bridgeReconnectRequested = true
    externalPlaybackState.pendingCommand = command
    externalPlaybackState.pendingValueText = trim(valueText)
    externalPlaybackState.pendingCommandReconnectRetry = true
    externalPlaybackState.bridgeActive = false
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    logExternalCommandThrottled(
        externalCommandLogKey('bridge-reconnect', command, trim(externalPlaybackState.player)),
        'Jukebox WebNowPlaying reconnect requested after command produced no observable state change: command=' .. command .. ' player=' .. trim(externalPlaybackState.player),
        'Warning',
        5)
    return true
end

local function requestExternalPlayPauseFallback(previousCommand)
    previousCommand = trim(previousCommand)
    if previousCommand ~= 'Play' and previousCommand ~= 'Pause' then
        return false
    end
    if externalPlaybackState.commandWatch.toggleFallbackTried then
        return false
    end
    if not externalPlaybackConnected() then
        return false
    end

    local fallbackCommand = 'PlayPause'
    local supportFlag, supportValue, supported, bestEffort = externalCommandSupportState(fallbackCommand)
    if not supported then
        return false
    end

    local sent = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', string.format('SendCommand(%q,%q)', fallbackCommand, ''), webNowPlayingBridgeConfigName())
    if not sent then
        return false
    end

    logExternalCommandThrottled(
        externalCommandLogKey('toggle-fallback', previousCommand, trim(externalPlaybackState.player)),
        'Jukebox WebNowPlaying command fallback sent after no observable state change: original=' .. previousCommand
            .. ' fallback=' .. fallbackCommand
            .. ' player=' .. trim(externalPlaybackState.player)
            .. ' support=' .. trim(supportFlag) .. '=' .. trim(supportValue)
            .. ' bestEffort=' .. (bestEffort and '1' or '0'),
        'Warning',
        5)
    beginExternalCommandWatch(fallbackCommand, '', supportFlag, supportValue, bestEffort, externalPlaybackState.commandWatch.reconnectRetry, true)
    return true
end

function tickExternalCommandWatchdog()
    if not externalPlaybackState.commandWatch.active then
        JukeboxScheduler.externalCommandWatchdog = false
        return false
    end
    if finishExternalCommandWatchIfObserved() then
        return true
    end
    externalPlaybackState.commandWatch.ticks = externalPlaybackState.commandWatch.ticks + 1
    if externalPlaybackState.commandWatch.ticks < EXTERNAL_COMMAND_WATCHDOG_TIMEOUT_TICKS then
        return true
    end
    local message = 'Jukebox WebNowPlaying command had no observable state change: command=' .. externalPlaybackState.commandWatch.command
        .. ' player=' .. trim(externalPlaybackState.player)
        .. ' state=' .. trim(externalPlaybackState.state)
        .. ' support=' .. trim(externalPlaybackState.commandWatch.supportFlag) .. '=' .. trim(externalPlaybackState.commandWatch.supportValue)
        .. ' bestEffort=' .. (externalPlaybackState.commandWatch.bestEffort and '1' or '0')
    local command = externalPlaybackState.commandWatch.command
    if requestExternalPlayPauseFallback(command) then
        return true
    end
    if not externalPlaybackState.commandWatch.reconnectRetry and requestExternalBridgeReconnect(command, externalPlaybackState.commandWatch.valueText) then
        externalPlaybackState.commandWatch.ticks = 0
        externalPlaybackState.commandWatch.reconnectRetry = true
        externalPlaybackState.commandWatch.waitingForReconnect = true
        return true
    end
    logExternalCommandThrottled(externalCommandLogKey('no-state-change', command, externalPlaybackState.commandWatch.beforePlayer), message, 'Warning')
    resetExternalCommandWatch()
    setJukeboxAnimatorPlaybackActive(externalPlaybackConnected() and trim(externalPlaybackState.state) == '1')
    syncDiscSlotPlaybackModeControls()
    showExternalPlayerUnavailable('no-observable-change', command)
    return false
end

function externalPlaybackState:trackIdentity()
    local player = trim(self.player)
    local title = trim(self.title)
    local artist = trim(self.artist)
    local album = trim(self.album)
    if title ~= '' or artist ~= '' or album ~= '' then
        return table.concat({ player, title, artist, album }, '\31')
    end
    return table.concat({ player, trim(self.cover), trim(self.duration) }, '\31')
end

function externalPlaybackState:hasTrackIdentity()
    return trim(self.title) ~= '' or trim(self.artist) ~= '' or trim(self.album) ~= '' or trim(self.cover) ~= ''
end

function externalPlaybackState:currentCoverFailureIdentity()
    return trim(self:trackIdentity())
end

function externalPlaybackState:clearCoverFetchFailure()
    self.coverFetchFailed = false
    self.coverFailureIdentity = ''
    self.coverFailureUrl = ''
    self.coverFailureStatus = ''
end

function externalPlaybackState:markCoverFetchFailure(url, statusCode)
    local identity = self:currentCoverFailureIdentity()
    if identity == '' or not self:hasTrackIdentity() then
        return false
    end
    self.coverFetchFailed = true
    self.coverFailureIdentity = identity
    self.coverFailureUrl = trim(url)
    self.coverFailureStatus = trim(statusCode)
    return true
end

function externalPlaybackState:coverFailureMatchesCurrent()
    return self.coverFetchFailed
        and trim(self.coverFailureIdentity) ~= ''
        and trim(self.coverFailureIdentity) == self:currentCoverFailureIdentity()
end

function externalPlaybackState:nextVisualSwitchToken()
    self.visualSwitch.counter = (tonumber(self.visualSwitch.counter) or 0) + 1
    if self.visualSwitch.counter > 999999 then
        self.visualSwitch.counter = 1
    end
    return 'external-switch-' .. tostring(self.visualSwitch.counter)
end

function externalPlaybackState:clearVisualSwitch()
    self.visualSwitch.active = false
    self.visualSwitch.token = ''
    self.visualSwitch.playAfterStop = false
    self.visualSwitch.mediaIdentity = ''
end

function externalPlaybackState:startVisualSwitch(playAfterStop)
    self.visualSwitch.active = true
    self.visualSwitch.token = self:nextVisualSwitchToken()
    self.visualSwitch.playAfterStop = playAfterStop and true or false
    self.visualSwitch.mediaIdentity = self.mediaIdentity
    setJukeboxAnimatorPlaybackActive(false)
    startJukeboxAnimation('stop', self.visualSwitch.token)
    return true
end

function externalPlaybackState:playVisual()
    self:clearVisualSwitch()
    setJukeboxAnimatorPlaybackActive(true)
    showCurrentExternalPlaybackHotbarText(false)
    startJukeboxAnimation('play')
    return true
end

function externalPlaybackState:stopVisual()
    self:clearVisualSwitch()
    setJukeboxAnimatorPlaybackActive(false)
    startJukeboxAnimation('stop')
    return true
end

function externalPlaybackState:applyVisualTransition(hadObservation, wasPlaying, isPlaying, mediaChanged)
    if self.visualSwitch.active then
        self.visualSwitch.playAfterStop = self.visualSwitch.playAfterStop or isPlaying
        if mediaChanged then
            self.visualSwitch.mediaIdentity = self.mediaIdentity
        end
        return true
    end

    if not hadObservation then
        setJukeboxAnimatorPlaybackActive(isPlaying)
        return false
    end

    if mediaChanged and wasPlaying and isPlaying then
        return self:startVisualSwitch(true)
    end

    if mediaChanged or wasPlaying ~= isPlaying then
        if isPlaying then
            return self:playVisual()
        elseif wasPlaying then
            return self:stopVisual()
        end
    end

    setJukeboxAnimatorPlaybackActive(isPlaying)
    return false
end

function externalPlaybackState:completeVisualSwitch(token)
    if not self.visualSwitch.active or trim(self.visualSwitch.token) ~= trim(token) then
        return false
    end
    local shouldPlay = self.visualSwitch.playAfterStop and isExternalPlaybackSourceMode() and self.bridgeActive and externalPlaybackConnected() and trim(self.state) == '1'
    self:clearVisualSwitch()
    if shouldPlay then
        return self:playVisual()
    end
    setJukeboxAnimatorPlaybackActive(false)
    return true
end
showCurrentExternalPlaybackHotbarText = function(pinned)
    if not externalPlaybackConnected() or trim(externalPlaybackState.state) == '0' then
        return false
    end
    local trackName = externalPlaybackDisplayName()
    if trackName == '' then
        return false
    end
    return showHotbarText(currentPlaybackHotbarText(trackName), pinned)
end
