-- Split from ExtraContent\Jukebox\Jukebox.lua lines 3023-4111.
function Initialize(allowCrossConfig)
    local allowExternal = allowCrossConfigValue(allowCrossConfig)
    initialized = true
    discSlotVisible = false
    pendingDiscSlotPlayback = nil
    discSlotSwitchState.pending = nil
    discSlotSwitchState.token = 0
    discSlotLoaded = false
    animationEngine = nil
    jukeboxAnimator = nil
    jukeboxAnimatorPhase = 'hidden'
    jukeboxAnimatorKind = ''
    jukeboxAnimatorPlaybackActive = false
    jukeboxAnimatorElapsedMs = 0
    jukeboxAnimatorWaitMs = 0
    jukeboxAnimatorCurrentFrameCount = 0
    jukeboxAnimatorCurrentFrameMs = ANIMATOR_FRAME_MS
    jukeboxAnimatorLastPlayingIndex = 0
    jukeboxAnimatorRandomSeeded = false
    jukeboxAnimatorTransitionCallbackToken = ''
    minimizedAnimator = nil
    minimizedAnimatorPhase = 'hidden'
    minimizedAnimatorKind = ''
    minimizedAnimatorPlaybackActive = false
    minimizedAnimatorElapsedMs = 0
    minimizedAnimatorWaitMs = 0
    minimizedAnimatorCurrentFrameCount = 0
    minimizedAnimatorCurrentFrameMs = ANIMATOR_FRAME_MS
    minimizedAnimatorLastPlayingIndex = 0
    minimizedAnimatorRandomSeeded = false
    minimizedDragging = false
    minimizedDragAllowedAtDown = false
    minimizedDragMoved = false
    minimizedLastWindowY = nil
    JukeboxScheduler.eventPolling = false
    JukeboxScheduler.eventPollRuntimeTicks = 0
    JukeboxScheduler.minimizedIdle = false
    JukeboxScheduler.responsive = false
    syncJukeboxModeImages()
    syncMinimizedModeImages()
    setJukeboxMinimizedMouseEnabled(JukeboxIsMinimizedForm())
    setJukeboxAnimatorHidden(true)
    setJukeboxMinimizedAnimatorHidden(true)
    setJukeboxDraggable(true)
    local configuredSourceMode = trim(SKIN:GetVariable('JukeboxPlaybackSourceMode', ''))
    local sourceMode = normalizedPlaybackSourceMode(configuredSourceMode)
    setVariable('JukeboxPlaybackSourceMode', sourceMode)
    if allowExternal then
        setVariableForActiveConfig('JukeboxPlaybackSourceMode', sourceMode, diagnosticsConfigName())
    end
    if configuredSourceMode == '' or configuredSourceMode:lower() ~= sourceMode then
        writeGeneralSettingValue('JukeboxPlaybackSourceMode', sourceMode)
    end
    syncPlaybackModeState(true, true)
    syncHelperVariables()

    if sourceMode == PLAYBACK_SOURCE_EXTERNAL then
        quarantineExternalBridgeForStartup(not allowExternal)
        if commandRunning.playback then
            commandRunning.stopPendingAfterExternalSwitch = true
        end
        stopLocalPlayback()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        if allowExternal then
            deactivateDiscSlotSkin()
        end
        setJukeboxAnimatorPlaybackActive(false, allowCrossConfig)
        webNowPlayingInstallState.start('Check', PLAYBACK_SOURCE_LOCAL)
    elseif allowExternal then
        syncExternalBridgeForMode()
    end
    if allowExternal and isDiscSlotCommandTargetActive() then
        scheduleDiscSlotDeferredSync()
    end
end

function PreloadJukeboxAnimator(allowCrossConfig)
    return safeCall(function()
        syncJukeboxModeImages()
        syncMinimizedModeImages()
        hideJukeboxAnimatorVisual(allowCrossConfig)
        HideJukeboxMinimizedAnimation()
        return true
    end)
end

function RestorePlaybackAnimation(allowCrossConfig)
    return safeCall(function()
        local allowExternal = allowCrossConfigValue(allowCrossConfig)
        if not initialized then
            Initialize(allowCrossConfig)
        end
        if isExternalPlaybackSourceMode() then
            if allowExternal then
                syncExternalBridgeForMode()
            end
            if externalPlaybackState.bridgeActive and externalPlaybackConnected() and trim(externalPlaybackState.state) == '1' then
                setJukeboxAnimatorPlaybackActive(true, allowCrossConfig)
                return true
            end
            hideJukeboxAnimatorVisual(allowCrossConfig)
            return false
        end

        local selection = currentPlaybackSelection()
        if selection.active and trim(selection.path) ~= '' then
            setJukeboxAnimatorPlaybackActive(true, allowCrossConfig)
            StartJukeboxEventPolling()
            return true
        end
        hideJukeboxAnimatorVisual(allowCrossConfig)
        return false
    end)
end
function StartJukeboxResponsiveLayoutTimer()
    JukeboxScheduler.responsive = true
    syncJukeboxRuntimeDriver()
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    return 0
end

function StopJukeboxResponsiveLayoutTimer()
    JukeboxScheduler.responsive = false
    syncJukeboxRuntimeDriver()
    return 0
end

function ContinueJukeboxResponsiveLayoutTimer()
    return StartJukeboxResponsiveLayoutTimer()
end
function persistCurrentJukeboxFixedPosition()
    local rect = JukeboxClampRectToWorkArea(currentJukeboxLiveRect())
    writeJukeboxMainFormY(rect.y)
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', string.format('SetFixedPosition(%q,%d,%d)', 'Jukebox', rect.x, rect.y))
    return rect
end

function hideDiscSlotForJukeboxFormSwitch()
    discSlotPendingShow = false
    discSlotPendingShowSkipRefresh = false
    discSlotActivationRequested = false
    if discSlotVisible then
        HideDiscSlot()
    else
        local configName = discSlotConfigName()
        if isRainmeterConfigActive(configName) then
            resetDiscSlotRenderStateForClose(configName)
            setDiscSlotHidden(true)
            syncDiscSlotVisualState(configName)
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'SuspendDiscSlotResident()', configName)
            SKIN:Bang('!Hide', configName)
        end
        discSlotVisible = false
    end
    return true
end

function enterJukeboxMinimizedForm(x)
    local targetX = persistSharedJukeboxX(x or currentWindowX())
    writeJukeboxDisplayMode('minimized')
    hideDiscSlotForJukeboxFormSwitch()
    setJukeboxDraggable(true)
    setJukeboxMinimizedMouseEnabled(true)
    syncMinimizedModeImages()
    setJukeboxAnimatorHidden(true)
    moveJukeboxToMinimizedBottom(targetX)
    setMinimizedPlaybackActiveVariable(jukeboxAnimatorPlaybackActive)
    restoreMinimizedPlaybackVisual()
    StartJukeboxMinimizedIdleTimer()
    redraw()
    return true
end

function enterJukeboxMainForm(x)
    local restoreY = storedJukeboxMainY(SKIN:GetVariable('ResponsiveLayout_Jukebox_FixedY', '0'), JukeboxIsMinimizedForm())
    local targetX = persistSharedJukeboxX(x or currentWindowX(), restoreY)
    local rect = JukeboxClampRectToWorkArea({ x = targetX, y = restoreY, width = tonumber(SKIN:GetVariable('JukeboxW', '80')) or 80, height = tonumber(SKIN:GetVariable('JukeboxH', '101')) or 101 })
    writeJukeboxDisplayMode('main')
    StopJukeboxMinimizedIdleTimer()
    HideJukeboxMinimizedAnimation()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', string.format('SetFixedPosition(%q,%d,%d)', 'Jukebox', rect.x, rect.y))
    SKIN:Bang('!Move', tostring(rect.x), tostring(rect.y))
    setJukeboxDraggable(true)
    setJukeboxMinimizedMouseEnabled(false)
    setJukeboxMinimizedAnimatorHidden(true)
    RestorePlaybackAnimation()
    redraw()
    return true
end

function RestoreJukeboxFormOnRefresh()
    return safeCall(function()
        if JukeboxIsMinimizedForm() then
            return enterJukeboxMinimizedForm(currentWindowX())
        end
        return enterJukeboxMainForm(currentWindowX())
    end)
end

function HandleJukeboxClose()
    return safeCall(function()
        if JukeboxIsMinimizedForm() then
            persistSharedJukeboxX(currentWindowX())
        else
            persistCurrentJukeboxFixedPosition()
        end
        StopPlayback()
        requestEmergencyStop('close')
        StopJukeboxMinimizedIdleTimer()
        StopJukeboxResponsiveLayoutTimer()
        StopJukeboxEventPolling()
        ensureResidentUpdateController().SuspendSurface('Jukebox')
        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
        return true
    end)
end

function MinimizeJukebox()
    return safeCall(function()
        if not isJukeboxFeatureEnabled() then
            return false
        end
        if not initialized then
            Initialize()
        end
        local rect = persistCurrentJukeboxFixedPosition()
        return enterJukeboxMinimizedForm(rect.x)
    end)
end

function RestoreJukeboxFromMinimized(x)
    return safeCall(function()
        return enterJukeboxMainForm(x)
    end)
end

function CleanupJukeboxMinimized()
    return safeCall(function()
        StopJukeboxMinimizedIdleTimer()
        HideJukeboxMinimizedAnimation()
        return true
    end)
end

function StopPlaybackForFeatureDisable()
    return safeCall(function()
        hideDiscSlotForJukeboxFormSwitch()
        StopPlayback()
        requestEmergencyStop('feature-disable')
        return true
    end)
end

function HandleJukeboxRealUnload(allowCrossConfig)
    return safeCall(function()
        ensureResidentUpdateController().SuspendSurface('Jukebox')
        StopJukeboxResponsiveLayoutTimer()
        StopJukeboxEventPolling()
        pendingDiscSlotPlayback = nil
        discSlotSwitchState.pending = nil
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        forceHideJukeboxAnimator(allowCrossConfig)
        requestEmergencyStop('real-unload')
        return true
    end)
end
function PreloadModalAlert()
    return safeCall(function()
        syncHelperVariables()
        local modal = ensureBridge()
        if modal then
            modal.Preload(modalAlertHost())
        end
        return true
    end)
end

function OpenPendingModalAlert()
    return safeCall(function()
        local modal = ensureBridge()
        if modal then
            return modal.OpenPending(modalAlertHost())
        end
        return false
    end)
end

function OpenPendingWebNowPlayingInstallConfirm()
    return safeCall(function()
        local configName = webNowPlayingInstallState.modalConfigName()
        if configName == '' or trim(webNowPlayingInstallState.openCommand) == '' then
            return false
        end
        SKIN:Bang('!CommandMeasure', 'MeasureModal', webNowPlayingInstallState.openCommand, configName)
        return true
    end)
end

function ConfirmWebNowPlayingInstall(token)
    return safeCall(function()
        if trim(token) == '' or trim(webNowPlayingInstallState.openCommand) == '' then
            return false
        end
        webNowPlayingInstallState.openCommand = ''
        local started = webNowPlayingInstallState.start('Install', webNowPlayingInstallState.previousMode)
        if started then
            webNowPlayingInstallState.openInstallProgress()
        end
        return started
    end)
end

function CancelWebNowPlayingInstall(token)
    return safeCall(function()
        return webNowPlayingInstallState.fallbackToLocal()
    end)
end

function ConfirmWebNowPlayingPortOwnerTerminate(token)
    return safeCall(function()
        if trim(token) == '' or trim(webNowPlayingInstallState.ownerPid) == '' then
            return false
        end
        webNowPlayingInstallState.openCommand = ''
        return webNowPlayingInstallState.openPortOwnerForceConfirm()
    end)
end

function ForceTerminateWebNowPlayingPortOwner(token)
    return safeCall(function()
        if trim(token) == '' or trim(webNowPlayingInstallState.ownerPid) == '' then
            return false
        end
        webNowPlayingInstallState.openCommand = ''
        return webNowPlayingInstallState.start('TerminatePortOwner', webNowPlayingInstallState.previousMode)
    end)
end

function CancelWebNowPlayingPortOwnerTerminate(token)
    return safeCall(function()
        return webNowPlayingInstallState.fallbackToLocal()
    end)
end

function HandleWebNowPlayingInstallComplete()
    return safeCall(function()
        return webNowPlayingInstallState.handleComplete()
    end)
end

function OpenModalAlertLogFolder(token)
    return safeCall(function()
        local modal = ensureBridge()
        if modal then
            return modal.OpenLogFolder(modalAlertHost(), token)
        end
        return false
    end)
end

function SeedDiscSlotLayoutContext()
    return safeCall(function()
        captureJukeboxLiveState()
        syncJukeboxLiveStateToDiscSlot(discSlotConfigName())
        return true
    end)
end

function ShowDiscSlot()
    return safeCall(function()
        captureJukeboxLiveState()
        resetDiscSlotAnchorState()
        local configName, activatedNow = activateDiscSlot()
        if activatedNow then
            discSlotPendingShow = true
            discSlotPendingShowSkipRefresh = false
            discSlotVisible = true
            setJukeboxDraggable(false)
            scheduleDiscSlotDeferredSync()
            return true
        end
        return showDiscSlotNow(configName)
    end)
end

function HideDiscSlot()
    return safeCall(function()
        discSlotPendingShow = false
        discSlotPendingShowSkipRefresh = false
        local configName = discSlotConfigName()
        if isRainmeterConfigActive(configName) then
            resetDiscSlotRenderStateForClose(configName)
            setDiscSlotHidden(true)
            syncDiscSlotVisualState(configName)
            SKIN:Bang('!Hide', configName)
        end
        setJukeboxDraggable(true)
        discSlotVisible = false
        return true
    end)
end

function ToggleDiscSlot()
    return safeCall(function()
        local result = false
        if discSlotVisible and not discSlotPendingShow then
            result = HideDiscSlot()
        else
            result = ShowDiscSlot()
        end
        return playClickSoundForResult(result)
    end)
end

function TryCompleteDiscSlotDeferredSync()
    return safeCall(function()
        if not discSlotPendingShow then
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
            return false
        end
        local configName = discSlotConfigName()
        if isRainmeterConfigActive(configName) then
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
            return showDiscSlotNow(configName, discSlotPendingShowSkipRefresh)
        end
        discSlotDeferredAttempts = discSlotDeferredAttempts + 1
        if discSlotActivationRequested and not discSlotRefreshRecoveryRequested and discSlotDeferredAttempts >= 3 then
            discSlotRefreshRecoveryRequested = true
            SKIN:Bang('!Refresh', configName)
            return true
        end
        if discSlotDeferredAttempts >= DISC_SLOT_DEFERRED_MAX_ATTEMPTS then
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
            discSlotPendingShow = false
            discSlotPendingShowSkipRefresh = false
            discSlotActivationRequested = false
            discSlotRefreshRecoveryRequested = false
            discSlotLoaded = false
            discSlotVisible = false
            setJukeboxDraggable(true)
            return false
        end
        return true
    end)
end

function SetPlaybackSourceMode(mode)
    return safeCall(function()
        return setPlaybackSourceModeInternal(mode)
    end)
end

function ExternalPlayPause()
    return safeCall(function()
        local command = trim(externalPlaybackState.state) == '1' and 'Pause' or 'Play'
        return requestExternalCommand(command)
    end)
end

function ExternalNext()
    return safeCall(function()
        return requestExternalCommand('Next')
    end)
end

function ExternalPrevious()
    return safeCall(function()
        return requestExternalCommand('Previous')
    end)
end

function ExternalRepeat()
    return safeCall(function()
        return requestExternalCommand('Repeat')
    end)
end

function ExternalShuffle()
    return safeCall(function()
        return requestExternalCommand('Shuffle')
    end)
end

function SetPlaybackVolume(value)
    return safeCall(function()
        local volume = clampPlaybackVolume(value)
        if isExternalPlaybackSourceMode() then
            return requestExternalCommand('SetVolume', tostring(volume))
        end
        setLocalPlaybackVolume(volume, true)
        requestHelperVolumeSync(volume)
        syncDiscSlotPlaybackModeControls()
        return true
    end)
end

function TogglePlaybackRepeatMode()
    return safeCall(function()
        if isExternalPlaybackSourceMode() then
            return requestExternalCommand('Repeat')
        end
        local mode = currentRepeatMode()
        if mode == 'all' then
            mode = 'one'
        elseif mode == 'one' then
            mode = 'off'
        else
            mode = 'all'
        end
        setVariable('JukeboxPlaybackRepeatMode', mode)
        syncPlaybackModeState(true)
        requestHelperLoopModeSync()
        return true
    end)
end

function TogglePlaybackShuffle()
    return safeCall(function()
        if isExternalPlaybackSourceMode() then
            return requestExternalCommand('Shuffle')
        end
        setVariable('JukeboxPlaybackShuffle', currentShuffleEnabled() and '0' or '1')
        syncPlaybackModeState(true)
        return true
    end)
end

function CleanupDiscSlot()
    return safeCall(function()
        return deactivateDiscSlotSkin()
    end)
end

function CleanupJukeboxAnimator()
    return safeCall(function()
        forceHideJukeboxAnimator()
        return true
    end)
end

function ContinueJukeboxAnimationAfterDelay()
    return safeCall(function()
        if isJukeboxNoteAnimationDisabled() then
            hideJukeboxAnimatorVisual()
            return false
        end
        if jukeboxAnimatorPhase ~= 'waiting' then
            return false
        end
        if not jukeboxAnimatorPlaybackActive then
            hideJukeboxAnimatorVisual()
            return false
        end
        startJukeboxPlayingSheet()
        return true
    end)
end

function UpdateJukeboxAnimation()
    return safeCall(function()
        if isJukeboxNoteAnimationDisabled() then
            if jukeboxAnimatorPhase ~= 'hidden' then
                local finishedKind = jukeboxAnimatorKind
                local callbackToken = jukeboxAnimatorTransitionCallbackToken
                hideJukeboxAnimatorVisual()
                notifyJukeboxAnimationComplete(finishedKind, callbackToken)
            end
            return false
        end

        if jukeboxAnimatorPhase == 'hidden' then
            return false
        end

        if jukeboxAnimatorPhase == 'waiting' then
            if not jukeboxAnimatorPlaybackActive then
                hideJukeboxAnimatorVisual()
                return false
            end
            jukeboxAnimatorWaitMs = jukeboxAnimatorWaitMs + ANIMATOR_TICK_MS
            if jukeboxAnimatorWaitMs >= ANIMATOR_PLAYING_DELAY_MS then
                startJukeboxPlayingSheet()
            end
            return true
        end

        if jukeboxAnimator == nil then
            hideJukeboxAnimatorVisual()
            return false
        end

        jukeboxAnimator:Update()
        jukeboxAnimatorElapsedMs = jukeboxAnimatorElapsedMs + ANIMATOR_TICK_MS
        if jukeboxAnimatorElapsedMs < (jukeboxAnimatorCurrentFrameMs * math.max(1, jukeboxAnimatorCurrentFrameCount)) then
            return true
        end

        if jukeboxAnimatorPhase == 'transition' then
            local finishedKind = jukeboxAnimatorKind
            local callbackToken = jukeboxAnimatorTransitionCallbackToken
            jukeboxAnimatorTransitionCallbackToken = ''
            if finishedKind == 'play' and jukeboxAnimatorPlaybackActive then
                enterJukeboxPlayingDelay()
            else
                hideJukeboxAnimatorVisual()
            end
            notifyJukeboxAnimationComplete(finishedKind, callbackToken)
        elseif jukeboxAnimatorPhase == 'playing' then
            if jukeboxAnimatorPlaybackActive then
                enterJukeboxPlayingDelay()
            else
                hideJukeboxAnimatorVisual()
            end
        else
            hideJukeboxAnimatorVisual()
        end
        return true
    end)
end

function OnJukeboxMinimizedMouseDown(x, y)
    return safeCall(function()
        if not JukeboxIsMinimizedForm() then
            return false
        end
        minimizedDragging = true
        minimizedDragAllowedAtDown = isJukeboxDragAllowed()
        minimizedDragMoved = false
        minimizedDownX = tonumber(x) or 0
        minimizedDownY = tonumber(y) or 0
        minimizedDownWindowX = currentWindowX()
        minimizedDownWindowY = currentWindowY()
        minimizedLastWindowY = minimizedDownWindowY
        return true
    end)
end

function OnJukeboxMinimizedMouseMove(x, y)
    return safeCall(function()
        if not JukeboxIsMinimizedForm() or not minimizedDragging or not minimizedDragAllowedAtDown then
            return false
        end
        local mouseX = tonumber(x) or minimizedDownX
        local mouseY = tonumber(y) or minimizedDownY
        local dx = mouseX - minimizedDownX
        local dy = mouseY - minimizedDownY
        local windowDx = currentWindowX() - minimizedDownWindowX
        local windowDy = currentWindowY() - minimizedDownWindowY
        if math.abs(dx) >= MINIMIZED_DRAG_THRESHOLD or math.abs(dy) >= MINIMIZED_DRAG_THRESHOLD
            or math.abs(windowDx) >= MINIMIZED_DRAG_THRESHOLD or math.abs(windowDy) >= MINIMIZED_DRAG_THRESHOLD then
            minimizedDragMoved = true
        end
        return true
    end)
end

function OnJukeboxMinimizedMouseUp(x, y)
    return safeCall(function()
        if not JukeboxIsMinimizedForm() then
            minimizedDragging = false
            return false
        end
        local moved = minimizedDragMoved
        if minimizedDragging and not moved then
            local mouseX = tonumber(x) or minimizedDownX
            local mouseY = tonumber(y) or minimizedDownY
            moved = math.abs(mouseX - minimizedDownX) > MINIMIZED_DRAG_THRESHOLD or math.abs(mouseY - minimizedDownY) > MINIMIZED_DRAG_THRESHOLD
        end
        minimizedDragging = false
        minimizedDragAllowedAtDown = false
        minimizedDragMoved = false
        if moved then
            local targetX = persistSharedJukeboxX(currentWindowX())
            moveJukeboxToMinimizedBottom(targetX)
            return true
        end
        return playClickSoundForResult(RestoreJukeboxFromMinimized(currentWindowX()))
    end)
end

function OnJukeboxMinimizedMouseLeave()
    return safeCall(function()
        if not JukeboxIsMinimizedForm() then
            return false
        end
        if minimizedDragging and minimizedDragAllowedAtDown and minimizedDragMoved then
            local targetX = persistSharedJukeboxX(currentWindowX())
            moveJukeboxToMinimizedBottom(targetX)
        end
        minimizedDragging = false
        minimizedDragAllowedAtDown = false
        minimizedDragMoved = false
        return true
    end)
end

function RequestDiscSlotPlayback(slotIndex, slotName, path, action)
    return safeCall(function()
        slotIndex = tonumber(slotIndex) or 0
        slotName = trim(slotName)
        path = trim(path)
        action = trim(action):lower()
        if action ~= 'play' and action ~= 'pause' then
            return false
        end
        if action == 'play' and path == '' then
            return false
        end
        if isExternalPlaybackSourceMode() then
            return false
        end
        if discSlotSwitchState.pending then
            return false
        end

        pollSuspendedAfterError = false
        StartJukeboxEventPolling()
        if action == 'play' and shouldSwitchDiscSlotPlayback(slotIndex, slotName, path) then
            return beginDiscSlotSwitchPlayback(slotIndex, slotName, path)
        end

        local command = action == 'pause' and 'Pause' or 'Play'
        local accepted = runPlaybackCommand(command, path, 'ModalAlert_JukeboxHelperStartFailed', {
            slotIndex = slotIndex,
            slotName = slotName,
            path = path,
            action = action,
        })
        if accepted then
            if action == 'pause' then
                setJukeboxAnimatorPlaybackActive(false)
            end
            startJukeboxAnimation(action == 'pause' and 'stop' or 'play')
        end
        return accepted
    end)
end

function RequestEndedDiscSlotPlayback(slotIndex, slotName, path)
    return safeCall(function()
        slotIndex = tonumber(slotIndex) or 0
        slotName = trim(slotName)
        path = trim(path)
        if slotIndex <= 0 or path == '' then
            return false
        end
        if isExternalPlaybackSourceMode() then
            return false
        end
        if discSlotSwitchState.pending then
            return false
        end

        pollSuspendedAfterError = false
        StartJukeboxEventPolling()
        return beginEndedDiscSlotSwitchPlayback(slotIndex, slotName, path)
    end)
end

function HandleJukeboxAnimationComplete(kind, token)
    return safeCall(function()
        kind = trim(kind):lower()
        token = trim(token)
        if kind ~= 'stop' then
            return false
        end
        local pendingSwitch = discSlotSwitchState.pending
        if pendingSwitch and pendingSwitch.token == token then
            pendingSwitch.stopAnimationDone = true
            if discSlotSwitchState.tryStartPlay then
                return discSlotSwitchState.tryStartPlay()
            end
            return true
        end
        return externalPlaybackState:completeVisualSwitch(token)
    end)
end

function ClearEndedDiscSlotPlayback()
    return safeCall(function()
        return clearEndedDiscSlotPlayback()
    end)
end

function ShowDiscSlotAlert(kind, detail)
    return safeCall(function()
        kind = trim(kind)
        local key = ''
        if kind == 'scanner_missing' then
            key = 'ModalAlert_JukeboxDiscSlotScannerMissing'
        elseif kind == 'scanner_failed' then
            key = 'ModalAlert_JukeboxDiscSlotScannerFailed'
        elseif kind == 'settings_route_failed' then
            key = 'ModalAlert_JukeboxDiscSlotSettingsRouteFailed'
        elseif kind == 'volume_dialog_failed' then
            key = 'ModalAlert_JukeboxDiscSlotVolumeDialogFailed'
        else
            SKIN:Bang('!Log', 'Ignored unknown Jukebox DiscSlot alert kind: ' .. tostring(kind), 'Warning')
            return false
        end
        return showAlert('warn', key, fallbackForKey(key), modalAlertLogPath())
    end)
end

function ShowUnsupportedAudio(fileName, supportedExtensions)
    return safeCall(function()
        fileName = trim(fileName)
        if fileName == '' then
            fileName = '?'
        end
        supportedExtensions = trim(supportedExtensions)
        if supportedExtensions == '' then
            supportedExtensions = SUPPORTED_AUDIO_EXTENSIONS
        end
        return showAlert(
            'warn',
            'ModalAlert_JukeboxUnsupportedAudio',
            fallbackForKey('ModalAlert_JukeboxUnsupportedAudio'),
            modalAlertLogPath(),
            { fileName, supportedExtensions },
            { primaryKey = 'Loc_Common_OpenFolder', openFolderPath = jukeboxDiscAudioDirectoryPath() })
    end)
end
function ShowCurrentPlaybackHotbarText()
    return safeCall(function()
        if isExternalPlaybackSourceMode() then
            return showCurrentExternalPlaybackHotbarText(true)
        end
        return showCurrentPlaybackHotbarTextForSelection(nil, true)
    end)
end

function ReleaseCurrentPlaybackHotbarText()
    return safeCall(function()
        local configName = hotbarConfigName()
        if configName == '' or not configName:find('[\\/]') then
            return false
        end
        commandMeasureForActiveConfig('MeasureHighlight', string.format('ReleasePinnedExternalHotbarText(%q)', 'Jukebox'), configName)
        return true
    end)
end

function HandleExternalCoverFetchFailure(url, statusCode)
    return safeCall(function()
        if not isExternalPlaybackSourceMode() then
            return false
        end
        if not externalPlaybackState:markCoverFetchFailure(url, statusCode) then
            return false
        end
        SKIN:Bang('!Log', 'Jukebox marked external cover fetch failure: status=' .. trim(statusCode), 'Warning')
        syncDiscSlotPlaybackModeControls()
        return true
    end)
end

function RetryExternalCoverFetch()
    return safeCall(function()
        if not isExternalPlaybackSourceMode() then
            return false
        end
        externalPlaybackState:clearCoverFetchFailure()
        externalPlaybackState.coverRetryNonce = (tonumber(externalPlaybackState.coverRetryNonce) or 0) + 1
        if externalPlaybackState.coverRetryNonce > 999999 then
            externalPlaybackState.coverRetryNonce = 1
        end
        syncDiscSlotPlaybackModeControls()
        local bridgeActive = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', 'RefreshCover()', webNowPlayingBridgeConfigName())
        if not bridgeActive then
            SKIN:Bang('!Log', 'Jukebox external cover retry requested while WebNowPlaying bridge is inactive.', 'Warning')
        end
        return bridgeActive
    end)
end

function SyncExternalPlaybackState()
    return safeCall(function()
        local hadExternalObservation = externalPlaybackState.observed
        local wasExternalPlaying = hadExternalObservation and externalPlaybackState.bridgeActive and externalPlaybackConnected() and trim(externalPlaybackState.state) == '1'
        local previousMediaIdentity = hadExternalObservation and trim(externalPlaybackState.mediaIdentity) or ''
        externalPlaybackState.pluginLoadFailed = trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1'
        if not externalPlaybackState.pluginLoadFailed then
            externalPlaybackState.bridgeFailureAlertShown = false
        end
        externalPlaybackState.bridgeActive = not externalPlaybackState.pluginLoadFailed and trim(SKIN:GetVariable('JukeboxExternalBridgeActive', '0')) == '1'
        externalPlaybackState.bridgeActivationRequested = false
        externalPlaybackState.status = trim(SKIN:GetVariable('JukeboxExternalStatus', '0'))
        externalPlaybackState.player = trim(SKIN:GetVariable('JukeboxExternalPlayer', ''))
        externalPlaybackState.title = trim(SKIN:GetVariable('JukeboxExternalTitle', ''))
        externalPlaybackState.artist = trim(SKIN:GetVariable('JukeboxExternalArtist', ''))
        externalPlaybackState.album = trim(SKIN:GetVariable('JukeboxExternalAlbum', ''))
        externalPlaybackState.cover = trim(SKIN:GetVariable('JukeboxExternalCover', ''))
        externalPlaybackState.duration = trim(SKIN:GetVariable('JukeboxExternalDuration', '0'))
        externalPlaybackState.volume = trim(SKIN:GetVariable('JukeboxExternalVolume', '0'))
        externalPlaybackState.state = trim(SKIN:GetVariable('JukeboxExternalState', '0'))
        externalPlaybackState.repeatMode = trim(SKIN:GetVariable('JukeboxExternalRepeat', '0'))
        externalPlaybackState.shuffle = trim(SKIN:GetVariable('JukeboxExternalShuffle', '0'))
        externalPlaybackState.supportsPlayPause = trim(SKIN:GetVariable('JukeboxExternalSupportsPlayPause', '0'))
        externalPlaybackState.supportsSkipPrevious = trim(SKIN:GetVariable('JukeboxExternalSupportsSkipPrevious', '0'))
        externalPlaybackState.supportsSkipNext = trim(SKIN:GetVariable('JukeboxExternalSupportsSkipNext', '0'))
        externalPlaybackState.supportsSetVolume = trim(SKIN:GetVariable('JukeboxExternalSupportsSetVolume', '0'))
        externalPlaybackState.supportsToggleRepeatMode = trim(SKIN:GetVariable('JukeboxExternalSupportsToggleRepeatMode', '0'))
        externalPlaybackState.supportsToggleShuffleActive = trim(SKIN:GetVariable('JukeboxExternalSupportsToggleShuffleActive', '0'))
        if externalPlaybackState.pluginLoadFailed then
            externalPlaybackState.bridgeReconnectRequested = false
        elseif externalPlaybackState.bridgeActive and externalPlaybackConnected() then
            externalPlaybackState.bridgeReconnectRequested = false
        end
        if isExternalPlaybackSourceMode() then
            if externalPlaybackState.pluginLoadFailed then
                externalPlaybackState.pendingCommand = nil
                externalPlaybackState.pendingValueText = nil
                externalPlaybackState.pendingCommandReconnectRetry = false
                externalPlaybackState:clearVisualSwitch()
                externalPlaybackState:clearCoverFetchFailure()
                setJukeboxAnimatorPlaybackActive(false)
                syncDiscSlotPlaybackModeControls()
                webNowPlayingInstallState.showInitializationFailed(false)
                return true
            end
            local externalPlaying = externalPlaybackState.bridgeActive and externalPlaybackConnected() and externalPlaybackState.state == '1'
            local currentMediaIdentity = externalPlaybackState:trackIdentity()
            if hadExternalObservation and previousMediaIdentity ~= '' and currentMediaIdentity ~= '' and previousMediaIdentity ~= currentMediaIdentity then
                externalPlaybackState:clearCoverFetchFailure()
            elseif externalPlaybackState.coverFetchFailed and not externalPlaybackState:coverFailureMatchesCurrent() then
                externalPlaybackState:clearCoverFetchFailure()
            end
            local mediaChanged = hadExternalObservation
                and previousMediaIdentity ~= ''
                and currentMediaIdentity ~= ''
                and previousMediaIdentity ~= currentMediaIdentity
                and externalPlaybackState:hasTrackIdentity()
            externalPlaybackState.mediaIdentity = currentMediaIdentity
            externalPlaybackState:applyVisualTransition(hadExternalObservation, wasExternalPlaying, externalPlaying, mediaChanged)
            externalPlaybackState.observed = true
            syncDiscSlotPlaybackModeControls()
            if externalPlaybackState.pendingCommand then
                if externalPlaybackState.pluginLoadFailed then
                    externalPlaybackState.pendingCommand = nil
                    externalPlaybackState.pendingValueText = nil
                    externalPlaybackState.pendingCommandReconnectRetry = false
                    webNowPlayingInstallState.showInitializationFailed(false)
                elseif not externalPlaybackState.bridgeActive then
                    if not externalPlaybackState.bridgeReconnectRequested then
                        externalPlaybackState.pendingCommand = nil
                        externalPlaybackState.pendingValueText = nil
                        externalPlaybackState.pendingCommandReconnectRetry = false
                        webNowPlayingInstallState.showInitializationFailed(false)
                    end
                elseif not externalPlaybackConnected() then
                    if not externalPlaybackState.bridgeReconnectRequested then
                        local pendingCommand = externalPlaybackState.pendingCommand
                        externalPlaybackState.pendingCommand = nil
                        externalPlaybackState.pendingValueText = nil
                        externalPlaybackState.pendingCommandReconnectRetry = false
                        showExternalPlayerUnavailable('pending-command-unavailable', pendingCommand)
                    end
                else
                    local command = externalPlaybackState.pendingCommand
                    local valueText = externalPlaybackState.pendingValueText or ''
                    local retryAfterReconnect = externalPlaybackState.pendingCommandReconnectRetry
                    externalPlaybackState.pendingCommand = nil
                    externalPlaybackState.pendingValueText = nil
                    externalPlaybackState.pendingCommandReconnectRetry = false
                    dispatchExternalCommand(command, valueText, retryAfterReconnect and 'reconnect-retry' or 'pending')
                end
            end
            finishExternalCommandWatchIfObserved()
        else
            externalPlaybackState.observed = false
            externalPlaybackState.mediaIdentity = ''
            externalPlaybackState:clearVisualSwitch()
        end
        return true
    end)
end

function StopPlayback()
    return safeCall(function()
        if not initialized then
            Initialize()
        end
        if isExternalPlaybackSourceMode() then
            pendingDiscSlotPlayback = nil
            discSlotSwitchState.pending = nil
            externalPlaybackState.pendingCommand = nil
            externalPlaybackState.pendingValueText = nil
            forceHideJukeboxAnimator()
            setJukeboxAnimatorPlaybackActive(false)
            deactivateExternalBridge()
            resetExternalPlaybackState()
            return true
        end
        return stopLocalPlayback()
    end)
end

function PollPlayerEvent()
    return safeCall(function()
        if pollSuspendedAfterError then
            StopJukeboxEventPolling()
            return false
        end
        if not initialized then
            Initialize()
        end
        if discSlotPendingShow then
            TryCompleteDiscSlotDeferredSync()
        end
        if isExternalPlaybackSourceMode() then
            return true
        end

        if runMeasure and runMeasure('poll', 'MeasureJukeboxPollEventRun', 'ModalAlert_JukeboxEventPollFailed') then
            return true
        end
        return false
    end)
end

function UpdateJukeboxAnimationDriver()
    if not initialized then
        return 0
    end

    if jukeboxAnimatorPhase ~= 'hidden' then
        UpdateJukeboxAnimation()
    end
    if minimizedAnimatorPhase ~= 'hidden' then
        UpdateJukeboxMinimizedAnimation()
    end

    syncJukeboxAnimationDriver()
    return 0
end

function UpdateJukeboxRuntime()
    if not initialized then
        return 0
    end
    if JukeboxScheduler.responsive then
        SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    end
    if JukeboxScheduler.minimizedIdle then
        PollJukeboxMinimizedIdle()
    end
    if JukeboxScheduler.eventPolling then
        JukeboxScheduler.eventPollRuntimeTicks = JukeboxScheduler.eventPollRuntimeTicks + 1
        if JukeboxScheduler.eventPollRuntimeTicks >= JUKEBOX_EVENT_POLL_RUNTIME_TICKS then
            JukeboxScheduler.eventPollRuntimeTicks = 0
            PollPlayerEvent()
        end
    end
    if JukeboxScheduler.externalCommandWatchdog then
        tickExternalCommandWatchdog()
    end
    syncJukeboxRuntimeDriver()
    return 0
end

function Update()
    return 0
end

function HandleCommandComplete(kind)
    return safeCall(function()
        kind = trim(kind)
        local measureName = 'MeasureJukeboxPlaybackRun'
        if kind == 'stop' then
            measureName = 'MeasureJukeboxStopRun'
        elseif kind == 'loop' then
            measureName = 'MeasureJukeboxSetLoopRun'
        elseif kind == 'volume' then
            measureName = 'MeasureJukeboxSetVolumeRun'
        elseif kind == 'poll' then
            measureName = 'MeasureJukeboxPollEventRun'
        end
        if commandRunning[kind] ~= nil then
            commandRunning[kind] = false
        end
        if kind == 'playback' and commandRunning.stopPendingAfterExternalSwitch then
            commandRunning.stopPendingAfterExternalSwitch = false
            stopLocalPlayback()
            return true
        end
        if isExternalPlaybackSourceMode() and (kind == 'playback' or kind == 'stop' or kind == 'loop' or kind == 'volume') then
            if kind == 'playback' then
                stopLocalPlayback()
            elseif kind == 'stop' then
                return handleResult(kind, measureOutput(measureName), 'ModalAlert_JukeboxCommandFailed')
            elseif kind == 'volume' then
                commandRunning.volumePending = false
            end
            return true
        end
        local defaultKey = kind == 'poll' and 'ModalAlert_JukeboxEventPollFailed' or 'ModalAlert_JukeboxCommandFailed'
        local result = handleResult(kind, measureOutput(measureName), defaultKey)
        if kind == 'volume' and commandRunning.volumePending then
            commandRunning.volumePending = false
            requestHelperVolumeSync(currentPlaybackVolume())
        end
        return result
    end)
end


function HandleEmergencyStopComplete()
    return safeCall(function()
        commandRunning.emergencyStop = false
        local values = parsePairs(measureOutput('MeasureJukeboxEmergencyStopRun'))
        local status = upper(values.DMEL_STATUS)
        if status == '' then
            SKIN:Bang('!Log', 'Jukebox emergency stop returned no DMEL_STATUS.', 'Warning')
        elseif status == 'ERROR' then
            SKIN:Bang('!Log', 'Jukebox emergency stop failed: ' .. trim(values.DMEL_MESSAGE), 'Error')
        end
        return true
    end)
end
