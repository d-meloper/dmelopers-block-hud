return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local function clearPendingLanguageSwitchState()
        state.pendingLanguageSwitchValue = nil
        state.pendingLanguageSwitchBeforeSnapshot = nil
        state.pendingLanguageSwitchSubmitActionFieldKey = nil
    end


    methods.CancelPendingLanguageSwitchInternal = function()
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLanguageSwitch', 'Stop 1')
        clearPendingLanguageSwitchState()
    end

    local function queuePendingLanguageSwitch(field, option, beforeSnapshot, submitActionFieldKey)
        if not field or field.key ~= 'language' or not option then
            return false
        end

        local currentLanguage = methods.normalizeLanguageCode(methods.readFieldValue(field), methods.normalizeLanguageCode(nil, nil))
        local targetLanguage = methods.normalizeLanguageCode(option.appliedValue, currentLanguage)

        state.pendingLanguageSwitchValue = targetLanguage
        state.pendingLanguageSwitchBeforeSnapshot = shallowCopy(beforeSnapshot or methods.captureSnapshot())
        state.pendingLanguageSwitchSubmitActionFieldKey = trim(submitActionFieldKey or '')

        methods.closeDropdownInternal()
        methods.setLoadingVisible(true, methods.languageSwitchLoadingText(targetLanguage))
        methods.renderActivePage()
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLanguageSwitch', 'Stop 1')
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLanguageSwitch', 'Execute 1')
        return true
    end

    function methods.RunPendingLanguageSwitch()
        local pendingValue = trim(state.pendingLanguageSwitchValue or '')
        local beforeSnapshot = state.pendingLanguageSwitchBeforeSnapshot
        local submitActionFieldKey = trim(state.pendingLanguageSwitchSubmitActionFieldKey or '')

        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLanguageSwitch', 'Stop 1')
        clearPendingLanguageSwitchState()

        local field = methods.getField('language')
        if not field or pendingValue == '' then
            methods.setLoadingVisible(false)
            methods.renderActivePage()
            return false
        end

        local changed = methods.applyFieldValue(field, pendingValue, {
            suppressRefresh = true,
            refreshAppAfterItemLabels = true,
        })

        if not changed then
            methods.syncActiveLocalization(pendingValue)
            methods.syncItemLabelsForLanguage(pendingValue, {
                refreshAppOnComplete = true,
            })
        end

        if submitActionFieldKey ~= '' then
            methods.ExecuteFieldAction(submitActionFieldKey)
        end

        if changed and beforeSnapshot then
            methods.pushHistory(field.historyLabel, beforeSnapshot)
        end

        if state.pendingDefaultItemLocalizationRunning ~= true then
            SKIN:Bang('!RefreshApp')
        end
        return true
    end

    local JUKEBOX_PLAYBACK_SOURCE_DEFERRED_VARIABLE = 'BlockHudSettingsJukeboxPlaybackSourceModeDeferred'
    local JUKEBOX_PLAYBACK_SOURCE_DEFERRED_MEASURE = 'MeasureSettingsJukeboxPlaybackSourceModeDeferred'

    local function jukeboxConfigName()
        local root = trim(SKIN:GetVariable('ROOTCONFIG', ''))
        if root ~= '' then
            return root .. '\\ExtraContent\\Jukebox'
        end
        return 'ExtraContent\\Jukebox'
    end

    local function activateJukeboxConfig()
        if methods.activateConfigTarget then
            methods.activateConfigTarget('Jukebox')
        else
            SKIN:Bang('!ActivateConfig', jukeboxConfigName(), 'Jukebox.ini')
        end
    end

    local function commandJukeboxPlaybackSourceMode(nextMode)
        if not (methods.isConfigTargetActive and methods.isConfigTargetActive('Jukebox')) then
            return false
        end
        SKIN:Bang(
            '!CommandMeasure',
            'MeasureJukebox',
            string.format('SetPlaybackSourceMode(%q)', nextMode),
            jukeboxConfigName()
        )
        return true
    end

    local function rearmJukeboxPlaybackSourceModeDeferred()
        SKIN:Bang('!SetVariable', JUKEBOX_PLAYBACK_SOURCE_DEFERRED_VARIABLE, '0')
        SKIN:Bang('!UpdateMeasure', JUKEBOX_PLAYBACK_SOURCE_DEFERRED_MEASURE)
        SKIN:Bang('!SetVariable', JUKEBOX_PLAYBACK_SOURCE_DEFERRED_VARIABLE, '1')
        SKIN:Bang('!UpdateMeasure', JUKEBOX_PLAYBACK_SOURCE_DEFERRED_MEASURE)
    end

    function methods.clearPendingJukeboxPlaybackSourceMode()
        state.pendingJukeboxPlaybackSourceMode = nil
        state.pendingJukeboxPlaybackSourceModeBeforeSnapshot = nil
        state.pendingJukeboxPlaybackSourceModeHistoryLabel = nil
        state.pendingJukeboxPlaybackSourceModeRetryCount = nil
        SKIN:Bang('!SetVariable', JUKEBOX_PLAYBACK_SOURCE_DEFERRED_VARIABLE, '0')
    end

    function methods.OpenPendingJukeboxPlaybackSourceMode()
        local pendingMode = trim(state.pendingJukeboxPlaybackSourceMode or '')
        if pendingMode == '' then
            SKIN:Bang('!SetVariable', JUKEBOX_PLAYBACK_SOURCE_DEFERRED_VARIABLE, '0')
            return false
        end

        local field = methods.getField and methods.getField('jukeboxPlaybackSourceMode') or nil
        if field then
            pendingMode = methods.normalizeFieldValue(field, pendingMode, 'local')
        end

        if commandJukeboxPlaybackSourceMode(pendingMode) then
            return true
        end

        state.pendingJukeboxPlaybackSourceModeRetryCount = (tonumber(state.pendingJukeboxPlaybackSourceModeRetryCount) or 0) + 1
        if state.pendingJukeboxPlaybackSourceModeRetryCount <= 5 then
            activateJukeboxConfig()
            rearmJukeboxPlaybackSourceModeDeferred()
            return false
        end

        logNotice('Jukebox playback source mode request could not be delivered because the Jukebox skin did not become active.')
        local field = methods.getField and methods.getField('jukeboxPlaybackSourceMode') or nil
        methods.clearPendingJukeboxPlaybackSourceMode()
        if field then
            methods.applyFieldValue(field, 'local', { suppressRefresh = true })
        end
        methods.renderActivePage()
        return false
    end

    function methods.SyncJukeboxPlaybackSourceMode()
        local storedMode = 'local'
        if methods.syncJukeboxPlaybackSourceModeFromStorage then
            storedMode = methods.syncJukeboxPlaybackSourceModeFromStorage()
        end

        local pendingMode = trim(state.pendingJukeboxPlaybackSourceMode or '')
        if pendingMode ~= '' then
            local field = methods.getField and methods.getField('jukeboxPlaybackSourceMode') or nil
            if field then
                pendingMode = methods.normalizeFieldValue(field, pendingMode, 'local')
            end
            local accepted = storedMode == pendingMode
            local before = state.pendingJukeboxPlaybackSourceModeBeforeSnapshot
            local historyLabel = trim(state.pendingJukeboxPlaybackSourceModeHistoryLabel or 'Jukebox playback source')
            methods.clearPendingJukeboxPlaybackSourceMode()
            if accepted and before then
                methods.pushHistory(historyLabel, before)
            end
        end

        return methods.renderActivePage()
    end

    function methods.requestJukeboxPlaybackSourceMode(field, optionOrValue, beforeSnapshot)
        local appliedValue = optionOrValue
        if type(optionOrValue) == 'table' then
            appliedValue = optionOrValue.appliedValue
        end
        local nextMode = methods.normalizeFieldValue(field, appliedValue, 'local')
        methods.clearPendingJukeboxPlaybackSourceMode()
        methods.closeDropdownInternal()

        if nextMode ~= 'external' then
            local changed = methods.applyFieldValue(field, nextMode, { suppressRefresh = true })
            if methods.syncJukeboxPlaybackSourceModeFromStorage then
                nextMode = methods.syncJukeboxPlaybackSourceModeFromStorage()
            end
            if changed and beforeSnapshot then
                methods.pushHistory(field.historyLabel, beforeSnapshot)
            end
            methods.renderActivePage()
            commandJukeboxPlaybackSourceMode(nextMode)
            return true
        end

        local storedMode = methods.normalizeFieldValue(field, methods.readFieldValue(field), 'local')
        if methods.syncJukeboxPlaybackSourceModeFromStorage then
            storedMode = methods.syncJukeboxPlaybackSourceModeFromStorage()
        end
        state.pendingJukeboxPlaybackSourceMode = nextMode
        state.pendingJukeboxPlaybackSourceModeBeforeSnapshot = storedMode ~= nextMode and beforeSnapshot or nil
        state.pendingJukeboxPlaybackSourceModeHistoryLabel = field.historyLabel
        state.pendingJukeboxPlaybackSourceModeRetryCount = 0
        methods.renderActivePage()
        if commandJukeboxPlaybackSourceMode(nextMode) then
            return true
        end
        activateJukeboxConfig()
        rearmJukeboxPlaybackSourceModeDeferred()
        return true
    end

    function methods.SelectDropdownOption(slotIndex)







        if methods.isLoadingVisible() then







            return







        end







        local numericSlotIndex = tonumber(slotIndex)







        local field = methods.getField(state.activeDropdownFieldKey)







        local option = numericSlotIndex and state.currentDropdownOptionBySlot[numericSlotIndex] or nil







        if not field or not option then







            return







        end







        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        local beforeSnapshot = methods.captureSnapshot()







        local submitActionFieldKey = trim(field.submitActionFieldKey or '')

        if queuePendingLanguageSwitch(field, option, beforeSnapshot, submitActionFieldKey) then
            return
        end

        if field.key == 'jukeboxPlaybackSourceMode' then
            methods.requestJukeboxPlaybackSourceMode(field, option, beforeSnapshot)
            return
        end







        methods.applyFieldValue(field, option.appliedValue, { selectionOption = option })







        methods.closeDropdownInternal()







        if submitActionFieldKey ~= '' then







            methods.ExecuteFieldAction(submitActionFieldKey)







            return







        end







        methods.pushHistory(field.historyLabel, beforeSnapshot)







        methods.renderActivePage()







    end







    function methods.DeleteDropdownOption(slotIndex)







        if methods.isLoadingVisible() then







            return







        end







        local numericSlotIndex = tonumber(slotIndex)







        local field = methods.getField(state.activeDropdownFieldKey)







        local option = numericSlotIndex and state.currentDropdownOptionBySlot[numericSlotIndex] or nil







        if not field or field.dropdownId ~= 'minecraftSkinHistory' or not option or option.canDelete ~= true then







            return







        end







        if methods.removeMinecraftSkinHistoryName(option.appliedValue) then







            methods.syncDropdownPageIndex(field)







        end







        methods.renderActivePage()







    end





    function methods.PrevDropdownOptionPage()







        if methods.isLoadingVisible() then







            return







        end







        local field = methods.getField(state.activeDropdownFieldKey)







        if not field then







            return







        end







        local pageCount = methods.dropdownPageCount(field)







        if pageCount <= 1 then







            return







        end







        state.activeDropdownPageIndex = state.activeDropdownPageIndex - 1







        if state.activeDropdownPageIndex < 1 then







            state.activeDropdownPageIndex = pageCount







        end







        methods.renderActivePage()







    end







    function methods.NextDropdownOptionPage()







        if methods.isLoadingVisible() then







            return







        end







        local field = methods.getField(state.activeDropdownFieldKey)







        if not field then







            return







        end







        local pageCount = methods.dropdownPageCount(field)







        if pageCount <= 1 then







            return







        end







        state.activeDropdownPageIndex = state.activeDropdownPageIndex + 1







        if state.activeDropdownPageIndex > pageCount then







            state.activeDropdownPageIndex = 1







        end







        methods.renderActivePage()







    end
end
