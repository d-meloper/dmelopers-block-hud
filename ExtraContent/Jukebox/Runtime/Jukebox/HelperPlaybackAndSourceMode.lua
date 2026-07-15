-- Split from ExtraContent\Jukebox\Jukebox.lua lines 2208-3022.
function fileNameFromPath(path)
    path = trim(path)
    if path == '' then
        return ''
    end
    return path:match('[^\\/]+$') or path
end

function audioFileNameFromValues(values)
    local name = trim(values and values.DMEL_AUDIOFILE or '')
    if name ~= '' then
        return name
    end
    local pending = pendingDiscSlotPlayback
    if pending and trim(pending.path) ~= '' then
        return fileNameFromPath(pending.path)
    end
    return ''
end


function requestEmergencyStop(reason)
    if commandRunning.emergencyStop then
        return false
    end

    local measure = SKIN:GetMeasure('MeasureJukeboxEmergencyStopRun')
    if not measure then
        SKIN:Bang('!Log', 'Jukebox emergency stop could not run: missing emergency stop measure. Reason=' .. tostring(reason or ''), 'Error')
        return false
    end

    syncHelperVariables()
    commandRunning.emergencyStop = true
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxEmergencyStopRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxEmergencyStopRun', 'Run')
    return true
end

function logErrorAndAlert(message)
    forceHideJukeboxAnimator()
    requestEmergencyStop('lua-error')

    local modal = ensureBridge()
    if not modal then
        SKIN:Bang('!Log', tostring(message or 'Jukebox runtime error.'), 'Error')
        return false
    end

    return modal.LogErrorAndAlert(modalAlertHost(), {
        source = 'Jukebox',
        logMessage = tostring(message or 'Jukebox runtime error.'),
        summaryText = localizedSummary('ModalAlert_JukeboxCommandFailed', 'The Jukebox command could not be completed. Refresh the skin and try again.'),
        logPath = modalAlertLogPath(),
        dedupeSeconds = 0,
    })
end

safeCall = function(callback)
    local ok, result = pcall(callback)
    if not ok then
        logErrorAndAlert('Jukebox Lua error: ' .. tostring(result))
        return false
    end
    return result
end

function parsePairs(output)
    return EnsureJukeboxHelperResultModule().parseDmelPairs(output)
end

function outputPreview(output)
    return EnsureJukeboxHelperResultModule().outputPreview(output, 180)
end

function classifyInvalidHelperOutput(kind, output)
    if trim(output) == '' then
        return 'ModalAlert_JukeboxHelperNoOutput', ''
    end

    local preview = outputPreview(output)
    if preview ~= '' then
        local lowerPreview = preview:lower()
        if lowerPreview:find(helperScriptFileName():lower(), 1, true) or lowerPreview:find('jukeboxplayer', 1, true) then
            return 'ModalAlert_JukeboxHelperScriptMissing', helperScriptFileName()
        end
        SKIN:Bang('!Log', 'Jukebox helper returned malformed output for ' .. tostring(kind or 'unknown') .. ': ' .. preview, 'Warning')
    end
    return 'ModalAlert_JukeboxHelperMalformedOutput', ''
end
function measureOutput(measureName)
    local measure = SKIN:GetMeasure(measureName)
    if not measure then
        return ''
    end
    return tostring(measure:GetStringValue() or '')
end

function summaryKeyForCode(code, defaultKey)
    code = upper(code)
    if code == 'AUDIO_MISSING' then
        return 'ModalAlert_JukeboxAudioMissing'
    elseif code == 'HELPER_START_FAILED' then
        return 'ModalAlert_JukeboxHelperStartFailed'
    elseif code == 'OUTPUT_INVALID' then
        return 'ModalAlert_JukeboxHelperMalformedOutput'
    elseif code == 'EVENT_POLL_FAILED' then
        return 'ModalAlert_JukeboxEventPollFailed'
    elseif code == 'PLAYBACK_FAILED' or code == 'MEDIA_FAILED' or code == 'MEDIA_OPEN_FAILED' then
        return 'ModalAlert_JukeboxPlaybackFailed'
    end
    return defaultKey or 'ModalAlert_JukeboxCommandFailed'
end

function fallbackForKey(key)
    if key == 'ModalAlert_JukeboxAudioMissing' then
        return 'The Jukebox audio file is missing: %1'
    elseif key == 'ModalAlert_JukeboxHelperStartFailed' then
        return 'The Jukebox player could not be started. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxHelperScriptMissing' then
        return 'The Jukebox player file could not be found: %1'
    elseif key == 'ModalAlert_JukeboxHelperNoOutput' then
        return 'The Jukebox player did not return a result. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxHelperMalformedOutput' then
        return 'The Jukebox player returned an unreadable result. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxHelperOutputInvalid' then
        return 'The Jukebox player returned an invalid result. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxEventPollFailed' then
        return 'The Jukebox player status could not be checked. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxPlaybackFailed' then
        return 'The Jukebox audio could not be played. Check whether Windows can play the audio file.'
    elseif key == 'ModalAlert_JukeboxExternalPlayerUnavailable' then
        return 'The external player status could not be read. Check the WebNowPlaying plugin and browser extension connection.'
    elseif key == 'ModalAlert_JukeboxExternalNoPlayer' then
        return 'No external music app is connected. Open a supported browser player, start playback, and make sure the WebNowPlaying browser extension is enabled for that tab.'
    elseif key == 'ModalAlert_JukeboxExternalNoMedia' then
        return 'The external music app is visible, but no playable media status is available. Start playback in the browser or app, then try again.'
    elseif key == 'ModalAlert_JukeboxExternalBridgeInactive' then
        return 'The external music app bridge is not ready yet. Wait a moment, then try again. If it keeps failing, reselect external music app mode in Jukebox Settings.'
    elseif key == 'ModalAlert_JukeboxExternalCommandUnsupported' then
        return 'The connected external app does not support %1 through WebNowPlaying. Use the player controls directly or try a different supported player.'
    elseif key == 'ModalAlert_JukeboxExternalCommandNoResponse' then
        return 'The %1 command was sent, but the external app did not report any change. Check whether the WebNowPlaying extension can control the current tab.'
    elseif key == 'ModalAlert_WebNowPlayingPluginUnavailable' then
        return 'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.'
    elseif key == 'ModalAlert_WebNowPlayingInitializationFailed' then
        return 'External music app features did not initialize correctly. Related Jukebox external player features may not work correctly. Local Jukebox playback can still be used.'
    elseif key == 'ModalAlert_WebNowPlayingStatusMeasureMissing' then
        return 'WebNowPlaying did not create the status measure. The Rainmeter plugin may be missing, blocked, or still loading. Re-select external music app mode in Jukebox Settings after checking the plugin.'
    elseif key == 'ModalAlert_WebNowPlayingMeasureReadFailed' then
        return 'WebNowPlaying loaded, but Jukebox could not read one of its status values. Refresh the skin, then check the plugin and browser extension if the problem repeats.'
    elseif key == 'ModalAlert_JukeboxUnsupportedAudio' then
        return '"%1" is not a supported file.\n\n<Supported file types>\n %2'
    elseif key == 'ModalAlert_JukeboxDiscSlotScannerMissing' then
        return 'The Jukebox disc scanner is unavailable. Refresh the skin or reinstall Block HUD.'
    elseif key == 'ModalAlert_JukeboxDiscSlotScannerFailed' then
        return 'The Jukebox disc list could not be refreshed. Check the audio folder and refresh the skin.'
    elseif key == 'ModalAlert_JukeboxDiscSlotSettingsRouteFailed' then
        return 'The Jukebox settings page could not be opened. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxDiscSlotVolumeDialogFailed' then
        return 'The Jukebox volume input window could not be completed. Refresh the skin and try again.'
    end
    return 'The Jukebox command could not be completed. Refresh the skin and try again.'
end

local function externalCommandRequiresValue(command)
    return command == 'SetVolume'
end

function externalCommandDisplayName(command)
    command = trim(command)
    if command == 'Previous' then
        return localizedSummary('JukeboxExternal_Previous', 'Previous')
    elseif command == 'Play' or command == 'Pause' or command == 'PlayPause' then
        return localizedSummary('JukeboxExternal_PlayPause', 'Play/Pause')
    elseif command == 'Next' then
        return localizedSummary('JukeboxExternal_Next', 'Next')
    elseif command == 'Repeat' then
        return localizedSummary('JukeboxExternal_Repeat', 'Repeat')
    elseif command == 'Shuffle' then
        return localizedSummary('JukeboxExternal_Shuffle', 'Shuffle')
    elseif command == 'SetVolume' then
        return localizedSummary('JukeboxExternal_Volume', 'Volume')
    end
    return command ~= '' and command or localizedSummary('JukeboxExternal_PlayPause', 'Play/Pause')
end

function webNowPlayingInitializationAlertKey(reason)
    reason = trim(reason):lower()
    if reason == 'status_measure_missing' then
        return 'ModalAlert_WebNowPlayingStatusMeasureMissing'
    elseif reason:find('read_failed:', 1, true) == 1 then
        return 'ModalAlert_WebNowPlayingMeasureReadFailed'
    end
    return 'ModalAlert_WebNowPlayingInitializationFailed'
end

function externalUnavailableAlertKey(reason, command)
    reason = trim(reason):lower()
    if reason:find('unsupported:', 1, true) == 1 then
        return 'ModalAlert_JukeboxExternalCommandUnsupported'
    elseif reason == 'no-observable-change' then
        return 'ModalAlert_JukeboxExternalCommandNoResponse'
    elseif reason == 'inactive-bridge' or reason == 'pending-bridge-inactive' then
        return 'ModalAlert_JukeboxExternalBridgeInactive'
    elseif trim(externalPlaybackState.player) ~= '' or externalPlaybackState:hasTrackIdentity() then
        return 'ModalAlert_JukeboxExternalNoMedia'
    end
    return 'ModalAlert_JukeboxExternalNoPlayer'
end

showExternalPlayerUnavailable = function(reason, command)
    reason = trim(reason)
    command = trim(command)
    if reason:lower() == 'no-observable-change' then
        return false
    end
    local key = externalUnavailableAlertKey(reason, command)
    local placeholders = nil
    if key == 'ModalAlert_JukeboxExternalCommandUnsupported'
        or key == 'ModalAlert_JukeboxExternalCommandNoResponse' then
        placeholders = { externalCommandDisplayName(command) }
    end
    return showAlert(
        'warn',
        key,
        fallbackForKey(key),
        modalAlertLogPath(),
        placeholders)
end

local function showWebNowPlayingPluginUnavailable()
    setVariableForActiveConfig('BlockHudDiagnosticsSuppressWebNowPlayingPluginAt', tostring(os.time() or 0), diagnosticsConfigName())
    return showAlert(
        'warn',
        'ModalAlert_WebNowPlayingPluginUnavailable',
        fallbackForKey('ModalAlert_WebNowPlayingPluginUnavailable'),
        modalAlertLogPath())
end

function webNowPlayingInstallState.initializationFailedMessage(key)
    key = trim(key)
    if key == '' then
        key = 'ModalAlert_WebNowPlayingInitializationFailed'
    end
    return localizedSummary(key, fallbackForKey(key))
end

function webNowPlayingInstallState.showInitializationFailed(force)
    if not force and externalPlaybackState.bridgeFailureAlertShown then
        return false
    end
    externalPlaybackState.bridgeFailureAlertShown = true
    local reason = trim(SKIN:GetVariable('JukeboxExternalBridgeFailureReason', ''))
    if reason ~= '' then
        SKIN:Bang('!Log', 'Jukebox WebNowPlaying bridge initialization failed: ' .. reason, 'Warning')
    end
    local key = webNowPlayingInitializationAlertKey(reason)
    return showAlert(
        'error',
        key,
        webNowPlayingInstallState.initializationFailedMessage(key),
        modalAlertLogPath())
end
function dispatchExternalCommand(command, valueText, context)
    local supportFlag, supportValue, supported, bestEffort = externalCommandSupportState(command)
    if not supported then
        logExternalCommandThrottled(
            externalCommandLogKey('unsupported', command, trim(externalPlaybackState.player)),
            'Jukebox WebNowPlaying command blocked because the player reports no support: command=' .. command
                .. ' player=' .. trim(externalPlaybackState.player)
                .. ' support=' .. supportFlag .. '=' .. supportValue,
            'Warning')
        return showExternalPlayerUnavailable('unsupported:' .. supportFlag .. '=' .. supportValue, command)
    end
    if bestEffort then
        logExternalCommandThrottled(
            externalCommandLogKey('best-effort', command, trim(externalPlaybackState.player)),
            'Jukebox WebNowPlaying command is being sent despite a disabled support flag: command=' .. command
                .. ' player=' .. trim(externalPlaybackState.player)
                .. ' support=' .. supportFlag .. '=' .. supportValue,
            'Warning')
    end
    local sent = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', string.format('SendCommand(%q,%q)', command, valueText), webNowPlayingBridgeConfigName())
    if sent then
        logExternalCommand('Jukebox WebNowPlaying command sent: command=' .. command .. ' player=' .. trim(externalPlaybackState.player) .. ' context=' .. tostring(context or 'direct'), 'Notice')
        beginExternalCommandWatch(command, valueText, supportFlag, supportValue, bestEffort, tostring(context or '') == 'reconnect-retry')
        return true
    end
    logExternalCommandThrottled(
        externalCommandLogKey('inactive-bridge', command, trim(externalPlaybackState.player)),
        'Jukebox WebNowPlaying command could not be sent because the bridge config is inactive: command=' .. command,
        'Warning')
    return showExternalPlayerUnavailable('inactive-bridge', command)
end

local function requestExternalCommand(command, value)
    command = trim(command)
    local lowerCommand = command:lower()
    if lowerCommand == 'playpause' then
        command = 'PlayPause'
    elseif lowerCommand == 'play' then
        command = 'Play'
    elseif lowerCommand == 'pause' then
        command = 'Pause'
    elseif lowerCommand == 'next' then
        command = 'Next'
    elseif lowerCommand == 'previous' then
        command = 'Previous'
    elseif lowerCommand == 'repeat' or lowerCommand == 'repeatmode' then
        command = 'Repeat'
    elseif lowerCommand == 'shuffle' then
        command = 'Shuffle'
    elseif lowerCommand == 'setvolume' then
        command = 'SetVolume'
    end
    if command == '' or not isExternalPlaybackSourceMode() then
        return false
    end

    local valueText = ''
    if value ~= nil then
        valueText = trim(value)
    end
    if externalCommandRequiresValue(command) and valueText == '' then
        return false
    end

    if externalPlaybackState.pluginLoadFailed or trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1' then
        return webNowPlayingInstallState.showInitializationFailed(true)
    end

    if not isExternalBridgeActive() then
        externalPlaybackState.pendingCommand = command
        externalPlaybackState.pendingValueText = valueText
        externalPlaybackState.pendingCommandReconnectRetry = false
        logExternalCommandThrottled(
            externalCommandLogKey('queued-activation', command, ''),
            'Jukebox WebNowPlaying command queued while bridge activates: command=' .. command,
            'Notice')
        activateExternalBridge()
        return true
    end
    if not externalPlaybackConnected() then
        logExternalCommandThrottled(
            externalCommandLogKey('unavailable', command, trim(externalPlaybackState.player)),
            'Jukebox WebNowPlaying command blocked because no external player is connected: command=' .. command,
            'Warning')
        return showExternalPlayerUnavailable('command-blocked-unavailable', command)
    end

    return dispatchExternalCommand(command, valueText, 'direct')
end

local function completePendingDiscSlotPlayback()
    local pending = pendingDiscSlotPlayback
    pendingDiscSlotPlayback = nil
    if not pending then
        return
    end

    if pending.action == 'pause' then
        StopJukeboxEventPolling()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
    elseif pending.action == 'switch-pause' then
        StopJukeboxEventPolling()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        local pendingSwitch = discSlotSwitchState.pending
        if pendingSwitch and pendingSwitch.token == trim(pending.switchToken) then
            pendingSwitch.pauseOk = true
            if discSlotSwitchState.tryStartPlay then
                discSlotSwitchState.tryStartPlay()
            end
        end
    else
        persistPlaybackSelection(pending.slotIndex, pending.slotName, pending.path)
        setDiscSlotPlaybackSelection(pending.slotIndex, pending.slotName)
        showCurrentPlaybackHotbarTextForSelection(currentPlaybackSelection())
        if pending.switchToken and discSlotSwitchState.pending and discSlotSwitchState.pending.token == trim(pending.switchToken) then
            discSlotSwitchState.pending = nil
        end
        setJukeboxAnimatorPlaybackActive(true)
        StartJukeboxEventPolling()
    end
end

local function discardPendingDiscSlotPlayback()
    pendingDiscSlotPlayback = nil
    forceHideJukeboxAnimator()
end

local function requestDiscSlotAutoAdvance(shuffleEnabled)
    if not isDiscSlotCommandTargetActive() then
        return false
    end
    local configName = discSlotConfigName()
    syncDiscSlotPlaybackModeControls(configName)
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', string.format('PlayNextFromPlaybackSelection(%q,%q)', shuffleEnabled and '1' or '0', '1'), configName)
    return true
end

local function clearEndedDiscSlotPlayback()
    StopJukeboxEventPolling()
    clearPersistedPlaybackSelection()
    clearDiscSlotPlaybackSelection()
    startJukeboxAnimation('stop')
    return true
end

local function handleTrackEndedEvent()
    if currentRepeatMode() == 'all' then
        if requestDiscSlotAutoAdvance(currentShuffleEnabled()) then
            return true
        end
    end
    return clearEndedDiscSlotPlayback()
end

local function handlePlayerEvent(values)
    local code = upper(values and values.DMEL_CODE or '')
    if code == 'TRACK_ENDED' then
        return handleTrackEndedEvent()
    end
    return true
end

local function handleResult(kind, output, defaultKey)
    local values = parsePairs(output)
    local status = upper(values.DMEL_STATUS)
    local logPath = trim(values.DMEL_LOGPATH)
    if logPath == '' then
        logPath = modalAlertLogPath()
    end

    if status == '' then
        local key, placeholder = classifyInvalidHelperOutput(kind, output)
        pollSuspendedAfterError = true
        StopJukeboxEventPolling()
        discardPendingDiscSlotPlayback()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        requestEmergencyStop('missing-helper-status')
        forceHideJukeboxAnimator()
        showAlert('error', key, fallbackForKey(key), logPath, placeholder)
        return false
    end

    if status == 'OK' then
        if kind == 'playback' then
            completePendingDiscSlotPlayback()
        elseif kind == 'stop' then
            StopJukeboxEventPolling()
            setJukeboxAnimatorPlaybackActive(false)
            clearPersistedPlaybackSelection()
            clearDiscSlotPlaybackSelection()
        elseif kind == 'poll' and trim(values.DMEL_EVENT) == '1' then
            handlePlayerEvent(values)
        end
        return true
    end

    if upper(values.DMEL_CODE) == 'HELPER_BUSY' then
        if kind == 'poll' then
            return true
        end
        if kind == 'stop' and isExternalPlaybackSourceMode() then
            requestEmergencyStop('external-stop-helper-busy')
            setJukeboxAnimatorPlaybackActive(false)
            clearPersistedPlaybackSelection()
            clearDiscSlotPlaybackSelection()
        end
        return false
    end

    local key = summaryKeyForCode(values.DMEL_CODE, defaultKey)
    local level = status == 'WARN' and 'warn' or 'error'
    if kind == 'playback' then
        discardPendingDiscSlotPlayback()
    end
    local placeholder = ''
    if key == 'ModalAlert_JukeboxAudioMissing' then
        placeholder = audioFileNameFromValues(values)
    end
    if level == 'error' and (kind ~= 'stop' or isExternalPlaybackSourceMode()) then
        pollSuspendedAfterError = true
        StopJukeboxEventPolling()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        requestEmergencyStop('helper-error-' .. trim(values.DMEL_CODE))
        forceHideJukeboxAnimator()
    end
    showAlert(level, key, fallbackForKey(key), logPath, placeholder)
    return false
end

runMeasure = function(kind, measureName, missingKey)
    syncHelperVariables()

    if commandRunning[kind] then
        return false
    end

    if not SKIN:GetMeasure(measureName) then
        showAlert('error', missingKey, fallbackForKey(missingKey), modalAlertLogPath())
        return false
    end

    commandRunning[kind] = true
    SKIN:Bang('!UpdateMeasure', measureName)
    SKIN:Bang('!CommandMeasure', measureName, 'Run')
    return true
end
function webNowPlayingInstallState.reset()
    webNowPlayingInstallState.phase = ''
    webNowPlayingInstallState.requestedMode = ''
    webNowPlayingInstallState.previousMode = ''
    webNowPlayingInstallState.openCommand = ''
    webNowPlayingInstallState.ownerPid = ''
    webNowPlayingInstallState.ownerUser = ''
    webNowPlayingInstallState.ownerDomain = ''
    webNowPlayingInstallState.ownerLabel = ''
end

function webNowPlayingInstallState.fallbackToLocal()
    webNowPlayingInstallState.openCommand = ''
    local ok = setPlaybackSourceModeInternal(PLAYBACK_SOURCE_LOCAL)
    webNowPlayingInstallState.reset()
    return ok
end

function webNowPlayingInstallState.applyExternalModeAfterReady()
    externalPlaybackState.pluginLoadFailed = false
    externalPlaybackState.bridgeFailureAlertShown = false
    setExternalPlaybackVariable('JukeboxExternalBridgePluginFailed', '0')
    webNowPlayingInstallState.phase = ''
    webNowPlayingInstallState.bypassPreflight = true
    local ok = setPlaybackSourceModeInternal(PLAYBACK_SOURCE_EXTERNAL)
    webNowPlayingInstallState.bypassPreflight = false
    webNowPlayingInstallState.reset()
    return ok
end

function webNowPlayingInstallState.start(action, previousMode)
    if commandRunning.webNowPlayingInstall then
        return true
    end

    if not SKIN:GetMeasure('MeasureJukeboxWebNowPlayingInstallRun') then
        webNowPlayingInstallState.fallbackToLocal()
        webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingInstallFailed',
            'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.\n\nThe plugin could not be installed. Check your internet connection and try again.',
            '외부 뮤직 앱 연동을 위한 플러그인을 불러오지 못했습니다. 주크박스 설정에서 재생 소스의 \'외부 뮤직 앱\'을 클릭해 다시 시도해보세요.\n\n플러그인을 설치하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.')
        return false
    end

    local normalizedAction = trim(action)
    if normalizedAction == '' then
        normalizedAction = 'Check'
    end

    webNowPlayingInstallState.phase = normalizedAction:lower()
    webNowPlayingInstallState.requestedMode = PLAYBACK_SOURCE_EXTERNAL
    webNowPlayingInstallState.previousMode = normalizedPlaybackSourceMode(previousMode)
    webNowPlayingInstallState.openCommand = ''
    setVariable('JukeboxWebNowPlayingInstallerArgs', webNowPlayingInstallState.buildArgs(normalizedAction))
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxWebNowPlayingInstallRun')
    commandRunning.webNowPlayingInstall = true
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxWebNowPlayingInstallRun', 'Run')
    return true
end

function webNowPlayingInstallState.handleComplete()
    commandRunning.webNowPlayingInstall = false
    local output = measureOutput('MeasureJukeboxWebNowPlayingInstallRun')
    webNowPlayingInstallState.openCommand = ''
    local values = parsePairs(output)
    local status = upper(values.DMEL_STATUS)
    local code = upper(values.DMEL_CODE)
    local phase = trim(webNowPlayingInstallState.phase)

    if status == '' then
        local preview = outputPreview(output)
        if preview ~= '' then
            SKIN:Bang('!Log', 'Jukebox WebNowPlaying installer returned no DMEL_STATUS: ' .. preview, 'Warning')
        end
        webNowPlayingInstallState.fallbackToLocal()
        return webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingInstallFailed',
            'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.\n\nThe plugin could not be installed. Check your internet connection and try again.',
            '외부 뮤직 앱 연동을 위한 플러그인을 불러오지 못했습니다. 주크박스 설정에서 재생 소스의 \'외부 뮤직 앱\'을 클릭해 다시 시도해보세요.\n\n플러그인을 설치하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.')
    end

    if phase == 'check' then
        if status == 'NOOP' and code == 'PORT_IN_USE_OTHER_USER' then
            webNowPlayingInstallState.fallbackToLocal()
            webNowPlayingInstallState.setPortOwner(values)
            webNowPlayingInstallState.previousMode = PLAYBACK_SOURCE_LOCAL
            return webNowPlayingInstallState.openPortOwnerTerminateConfirm()
        end
        if status == 'NOOP' and code == 'PORT_IN_USE' then
            webNowPlayingInstallState.fallbackToLocal()
            return webNowPlayingInstallState.showInstallAlert(
                'error',
                'ModalAlert_WebNowPlayingPortInUse',
                'More than one Rainmeter process is currently running.\nThe external music app feature may not work correctly.\nPlease restart your computer and try again.',
                '현재 레인미터 프로세스가 두 개 이상 켜져 있습니다.\n외부 뮤직 앱 기능이 정상 작동하지 않을 수 있으니,\n컴퓨터를 재부팅 후 다시 이용해 주세요.')
        end
        if (status == 'OK' and code == 'INSTALLED') or (status == 'NOOP' and code == 'ALREADY_INSTALLED') then
            return webNowPlayingInstallState.applyExternalModeAfterReady()
        end
        if status == 'NOOP' and (code == 'MISSING' or code == 'INCOMPATIBLE_ARCH') then
            return webNowPlayingInstallState.openInstallConfirm()
        end
        local detail = 'status=' .. status .. '; code=' .. code
        local message = outputPreview(values.DMEL_MESSAGE or '')
        if message ~= '' then
            detail = detail .. '; message=' .. message
        end
        SKIN:Bang('!Log', 'Jukebox WebNowPlaying check returned unexpected result: ' .. detail, 'Warning')
        webNowPlayingInstallState.fallbackToLocal()
        return webNowPlayingInstallState.showInstallAlert(
            'warn',
            'ModalAlert_WebNowPlayingInstallUnavailable',
            'WebNowPlaying installation could not be checked. Install the WebNowPlaying Rainmeter plugin manually, then try external player mode again.',
            'WebNowPlaying 설치 상태를 확인하지 못했습니다. WebNowPlaying Rainmeter 플러그인을 수동으로 설치한 뒤 외부 플레이어 모드를 다시 시도하세요.')
    end

    if phase == 'install' then
        if (status == 'OK' and code == 'INSTALLED') or (status == 'NOOP' and code == 'ALREADY_INSTALLED') then
            webNowPlayingInstallState.showInstallAlert(
                'warn',
                'ModalAlert_WebNowPlayingInstallSucceeded',
                'Plugin installation is complete. Refresh the skin if it does not connect to the external music app immediately.',
                '플러그인 설치가 완료됐습니다. 외부 뮤직 앱에 바로 연결되지 않으면 스킨을 새로고침하세요.')
            return webNowPlayingInstallState.applyExternalModeAfterReady()
        end
        webNowPlayingInstallState.fallbackToLocal()
        return webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingInstallFailed',
            'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.\n\nThe plugin could not be installed. Check your internet connection and try again.',
            '외부 뮤직 앱 연동을 위한 플러그인을 불러오지 못했습니다. 주크박스 설정에서 재생 소스의 \'외부 뮤직 앱\'을 클릭해 다시 시도해보세요.\n\n플러그인을 설치하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.')
    end

    if phase == 'terminateportowner' then
        if status == 'OK' and code == 'TERMINATED' then
            webNowPlayingInstallState.showInstallAlert(
                'warn',
                'ModalAlert_WebNowPlayingTerminateSucceeded',
                'The other account Rainmeter process was terminated. Jukebox will check WebNowPlaying again.',
                'The other account Rainmeter process was terminated. Jukebox will check WebNowPlaying again.')
            return webNowPlayingInstallState.start('Check', PLAYBACK_SOURCE_LOCAL)
        end

        webNowPlayingInstallState.fallbackToLocal()
        if code == 'ACCESS_DENIED' then
            return webNowPlayingInstallState.showInstallAlert(
                'error',
                'ModalAlert_WebNowPlayingTerminateAccessDenied',
                'The other account Rainmeter process could not be terminated because access was denied. Log into that Windows account and close Rainmeter manually.',
                'The other account Rainmeter process could not be terminated because access was denied. Log into that Windows account and close Rainmeter manually.')
        end
        if code == 'OWNER_CHANGED' or code == 'ALREADY_STOPPED' or code == 'OWNER_IS_CURRENT' then
            return webNowPlayingInstallState.showInstallAlert(
                'warn',
                'ModalAlert_WebNowPlayingTerminateOwnerChanged',
                'The WebNowPlaying port owner changed before termination. Try external player mode again after checking Rainmeter in the other Windows account.',
                'The WebNowPlaying port owner changed before termination. Try external player mode again after checking Rainmeter in the other Windows account.')
        end
        return webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingTerminateFailed',
            'The other account Rainmeter process could not be terminated. Log into that Windows account and close Rainmeter manually.',
            'The other account Rainmeter process could not be terminated. Log into that Windows account and close Rainmeter manually.')
    end

    webNowPlayingInstallState.fallbackToLocal()
    return false
end
local function runPlaybackCommand(command, audioOverride, missingKey, pendingPlayback)
    syncHelperVariables()

    if commandRunning.playback then
        return false
    end

    local loopEnabled = command == 'Play' and isPlaybackLoopEnabled()
    local volume = currentPlaybackVolume()
    pendingDiscSlotPlayback = pendingPlayback

    if not SKIN:GetMeasure('MeasureJukeboxPlaybackRun') then
        pendingDiscSlotPlayback = nil
        showAlert('error', missingKey, fallbackForKey(missingKey), modalAlertLogPath())
        return false
    end

    setVariable('JukeboxPlaybackArgs', buildArgs(command, audioOverride or '', '', loopEnabled, volume))
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxPlaybackRun')
    commandRunning.playback = true
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxPlaybackRun', 'Run')
    return true
end

local function stopLocalPlayback()
    pendingDiscSlotPlayback = nil
    discSlotSwitchState.pending = nil
    forceHideJukeboxAnimator()
    if commandRunning.stop then
        return true
    end
    if runMeasure and runMeasure('stop', 'MeasureJukeboxStopRun', 'ModalAlert_JukeboxCommandFailed') then
        return true
    end
    setJukeboxAnimatorPlaybackActive(false)
    clearPersistedPlaybackSelection()
    clearDiscSlotPlaybackSelection()
    return true
end

function setPlaybackSourceModeInternal(mode)
    local nextMode = normalizedPlaybackSourceMode(mode)
    local previousMode = currentPlaybackSourceMode()
    if nextMode == PLAYBACK_SOURCE_EXTERNAL and not webNowPlayingInstallState.bypassPreflight then
        return webNowPlayingInstallState.start('Check', previousMode)
    end
    if previousMode == nextMode and trim(SKIN:GetVariable('JukeboxPlaybackSourceMode', '')) == nextMode then
        setVariableForActiveConfig('JukeboxPlaybackSourceMode', nextMode, diagnosticsConfigName())
        syncExternalBridgeForMode()
        syncSettingsPlaybackSourceMode()
        syncDiscSlotPlaybackModeControls()
        PreloadDiscSlotSkin()
        return true
    end

    if nextMode == PLAYBACK_SOURCE_EXTERNAL then
        if commandRunning.playback then
            commandRunning.stopPendingAfterExternalSwitch = true
        end
        stopLocalPlayback()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        setJukeboxAnimatorPlaybackActive(false)
    else
        deactivateExternalBridge()
        resetExternalPlaybackState()
        externalPlaybackState.pluginLoadFailed = false
        externalPlaybackState.bridgeFailureAlertShown = false
        setExternalPlaybackVariable('JukeboxExternalBridgePluginFailed', '0')
        setJukeboxAnimatorPlaybackActive(false)
    end

    deactivateDiscSlotSkin()
    setVariable('JukeboxPlaybackSourceMode', nextMode)
    setVariableForActiveConfig('JukeboxPlaybackSourceMode', nextMode, diagnosticsConfigName())
    writeGeneralSettingValue('JukeboxPlaybackSourceMode', nextMode)
    syncExternalBridgeForMode()
    syncSettingsPlaybackSourceMode()
    syncDiscSlotPlaybackModeControls()
    PreloadDiscSlotSkin()
    return true
end

discSlotSwitchState.nextToken = function()
    discSlotSwitchState.token = discSlotSwitchState.token + 1
    if discSlotSwitchState.token > 1000000 then
        discSlotSwitchState.token = 1
    end
    return tostring(discSlotSwitchState.token)
end

discSlotSwitchState.tryStartPlay = function()
    local pendingSwitch = discSlotSwitchState.pending
    if not pendingSwitch or pendingSwitch.playStarted then
        return false
    end
    if not pendingSwitch.pauseOk or not pendingSwitch.stopAnimationDone then
        return false
    end

    pendingSwitch.playStarted = true
    local accepted = runPlaybackCommand('Play', pendingSwitch.targetPath, 'ModalAlert_JukeboxHelperStartFailed', {
        slotIndex = pendingSwitch.targetSlotIndex,
        slotName = pendingSwitch.targetSlotName,
        path = pendingSwitch.targetPath,
        action = 'play',
        switchToken = pendingSwitch.token,
    })
    if accepted then
        startJukeboxAnimation('play')
        return true
    end

    discSlotSwitchState.pending = nil
    forceHideJukeboxAnimator()
    return false
end

local function beginDiscSlotSwitchPlayback(slotIndex, slotName, path)
    local token = discSlotSwitchState.nextToken()
    discSlotSwitchState.pending = {
        token = token,
        targetSlotIndex = tonumber(slotIndex) or 0,
        targetSlotName = trim(slotName),
        targetPath = trim(path),
        pauseOk = false,
        stopAnimationDone = false,
        playStarted = false,
    }

    local accepted = runPlaybackCommand('Pause', '', 'ModalAlert_JukeboxHelperStartFailed', {
        slotIndex = tonumber(slotIndex) or 0,
        slotName = trim(slotName),
        path = trim(path),
        action = 'switch-pause',
        switchToken = token,
    })
    if accepted then
        setJukeboxAnimatorPlaybackActive(false)
        startJukeboxAnimation('stop', token)
    else
        discSlotSwitchState.pending = nil
    end
    return accepted
end

local function beginEndedDiscSlotSwitchPlayback(slotIndex, slotName, path)
    local token = discSlotSwitchState.nextToken()
    discSlotSwitchState.pending = {
        token = token,
        targetSlotIndex = tonumber(slotIndex) or 0,
        targetSlotName = trim(slotName),
        targetPath = trim(path),
        pauseOk = true,
        stopAnimationDone = false,
        playStarted = false,
    }

    pendingDiscSlotPlayback = nil
    clearPersistedPlaybackSelection()
    clearDiscSlotPlaybackSelection()
    startJukeboxAnimation('stop', token)
    return true
end
