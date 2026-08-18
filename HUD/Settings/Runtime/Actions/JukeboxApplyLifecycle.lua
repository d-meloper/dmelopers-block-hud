return function(app)
    local state = app.state
    local methods = app.methods
    local trim = app.trim
    local logNotice = app.logNotice

    local APPLY_TIMEOUT_TICKS = 15
    local LOADING_FALLBACK = 'Applying Jukebox changes...'
    local FAILURE_FALLBACK = 'The Jukebox change was saved, but completion could not be confirmed in the running Jukebox. Reopen the Jukebox to apply the saved setting.'

    local function loadingText()
        return methods.localize('Settings_Loading_JukeboxApply', LOADING_FALLBACK)
    end

    local function pendingApply()
        return type(state.pendingJukeboxSettingsApply) == 'table' and state.pendingJukeboxSettingsApply or nil
    end

    local function hasFutureJukeboxRefresh()
        local batches = state.pendingRefreshBatches or {}
        local currentIndex = tonumber(state.pendingRefreshBatchIndex) or 0
        for index = currentIndex + 1, #batches do
            for _, targetName in ipairs(batches[index] or {}) do
                if targetName == 'Jukebox' then
                    return true
                end
            end
        end
        return false
    end

    local function clearPendingApply(hideLoading)
        state.pendingJukeboxSettingsApply = nil
        methods.SetUpdateJob('jukeboxApply', false)
        if hideLoading ~= false then
            methods.setLoadingVisible(false)
            methods.renderActivePage()
        end
    end

    local function tryFinishApply()
        local pending = pendingApply()
        if not pending then
            return false
        end
        if pending.expectReady or pending.expectInactive or pending.sourcePending or hasFutureJukeboxRefresh() then
            return false
        end
        clearPendingApply(true)
        return true
    end

    local function failPendingApply(reason)
        logNotice('Jukebox Settings apply completion was not confirmed: ' .. trim(reason or 'timeout'))
        clearPendingApply(true)
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_JukeboxSettingsApplyUnconfirmed',
                FAILURE_FALLBACK
            )
        end
        return false
    end

    function methods.IsJukeboxSettingsApplyPending()
        return pendingApply() ~= nil
    end

    function methods.BeginJukeboxSettingsApply(expectation)
        local pending = pendingApply()
        if not pending then
            state.jukeboxSettingsApplyRequestCounter = (tonumber(state.jukeboxSettingsApplyRequestCounter) or 0) + 1
            local sessionStamp = tostring(os.time()) .. '-' .. tostring(math.floor(os.clock() * 1000))
            pending = {
                token = 'jukebox-settings-' .. sessionStamp .. '-' .. tostring(state.jukeboxSettingsApplyRequestCounter),
                ticks = 0,
                expectReady = false,
                expectInactive = false,
                sourcePending = false,
                ackSent = false,
            }
            state.pendingJukeboxSettingsApply = pending
        end

        local kind = trim(expectation or '')
        if kind == 'ready' then
            pending.expectReady = true
            pending.ackSent = false
        elseif kind == 'inactive' then
            pending.expectInactive = true
        elseif kind == 'source' then
            pending.sourcePending = true
        end
        pending.ticks = 0
        methods.setLoadingVisible(true, loadingText())
        methods.renderActivePage()
        methods.SetUpdateJob('jukeboxApply', true)
        return pending.token
    end

    function methods.RequestJukeboxSettingsApplyAck()
        local pending = pendingApply()
        if not pending or pending.ackSent then
            return false
        end
        local configPath = methods.configPathForRefreshTarget('Jukebox')
        if configPath == '' or not methods.isConfigTargetActive('Jukebox') then
            return false
        end
        pending.ackSent = true
        SKIN:Bang(
            '!CommandMeasure',
            'MeasureJukebox',
            string.format('AcknowledgeSettingsApply(%q)', pending.token),
            configPath
        )
        return true
    end

    function methods.NotifyJukeboxRuntimeReady()
        local pending = pendingApply()
        if not pending or not pending.expectReady then
            return false
        end
        return methods.RequestJukeboxSettingsApplyAck()
    end

    function methods.CompleteJukeboxSettingsApply(requestToken)
        local pending = pendingApply()
        if not pending or trim(requestToken or '') ~= trim(pending.token or '') then
            return false
        end
        pending.expectReady = false
        pending.ackSent = false
        pending.ticks = 0
        return tryFinishApply()
    end

    function methods.CompleteJukeboxPlaybackSourceApply(success)
        local pending = pendingApply()
        if not pending or not pending.sourcePending then
            return false
        end
        pending.sourcePending = false
        pending.ticks = 0
        if success == false then
            return failPendingApply('playback source apply failed')
        end
        return tryFinishApply()
    end

    function methods.PollJukeboxSettingsApply()
        local pending = pendingApply()
        if not pending then
            methods.SetUpdateJob('jukeboxApply', false)
            return false
        end

        if pending.expectInactive then
            local mainActive = methods.isConfigTargetActive('Jukebox')
            local discSlotActive = methods.isConfigTargetActive('JukeboxDiscSlot')
            if not mainActive and not discSlotActive then
                pending.expectInactive = false
                pending.ticks = 0
                if tryFinishApply() then
                    return true
                end
            end
        end

        pending.ticks = (tonumber(pending.ticks) or 0) + 1
        if pending.ticks >= APPLY_TIMEOUT_TICKS then
            return failPendingApply('timeout')
        end
        return true
    end
end
