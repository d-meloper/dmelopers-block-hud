return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local languageBranching = app.loadSharedLuaModule('LanguageBranching.lua')
    local TAB_SETTINGS_RESET_ACTIONS = {
        resetHotbarSettings = true,
        resetIndicatorsSettings = true,
        resetInventorySettings = true,
        resetClockSettings = true,
        resetHerobrineSettings = true,
        resetJukeboxSettings = true,
    }
    local TAB_POSITION_RESET_ACTIONS = {
        resetHotbarSkinPositions = true,
        resetIndicatorsSkinPositions = true,
        resetInventorySkinPositions = true,
        resetClockSkinPositions = true,
        resetJukeboxSkinPositions = true,
    }

    local function jukeboxHelpUrl()
        return languageBranching.SelectKoreanElseGlobal(
            languageBranching.CurrentSkinLanguageCode(SKIN, 'en-US'),
            'https://www.notion.so/aismash/37a2dc0bb4ae80cbbd87c22790d66c5e?source=copy_link',
            'https://www.notion.so/aismash/How-to-Use-the-Jukebox-3912dc0bb4ae806ca6d7c74b2667dd75?source=copy_link'
        )
    end

    local function clearPendingInputState()
        methods.clearSharedInputState()
    end







    local function pushTabLayoutHistory(field, beforeSnapshot, layoutTargetIds, beforeLayoutSnapshot)







        local afterSnapshot = methods.captureSnapshot()







        local afterLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)







        methods.pushHistory(field.historyLabel, beforeSnapshot, {







            afterSnapshot = afterSnapshot,







            beforeLayout = beforeLayoutSnapshot,







            afterLayout = afterLayoutSnapshot,







            layoutTargetIds = layoutTargetIds,







            tabId = field.tabId,







        })







    end







    function methods.SelectSegmentedOption(fieldKey, value)

        if methods.isLoadingVisible() then
            return
        end

        methods.clearPendingConfirmation()

        local field = methods.getField(fieldKey)
        if not field or field.controlType ~= 'segmented' then
            return
        end

        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        local beforeSnapshot = methods.captureSnapshot()
        if field.key == 'jukeboxPlaybackSourceMode' then
            methods.requestJukeboxPlaybackSourceMode(field, value, beforeSnapshot)
            return
        end
        if field.key == 'minecraftSkinModel' then
            local requestedModel = methods.normalizeMinecraftSkinModelInput and methods.normalizeMinecraftSkinModelInput(value) or (string.lower(trim(value)) == 'slim' and 'slim' or 'wide')
            local changed = methods.applyFieldValue(field, requestedModel)

            methods.closeDropdownInternal()

            local canonicalField = methods.getField('minecraftSkinUsername')
            local currentUsername = canonicalField and trim(methods.readFieldValue(canonicalField)) or ''
            local currentTexturePath = methods.resolveCurrentMinecraftSkinTexturePath and methods.resolveCurrentMinecraftSkinTexturePath(currentUsername) or ''
            local shouldRender = currentUsername ~= ''

            if changed and not shouldRender then
                methods.pushHistory(field.historyLabel, beforeSnapshot)
            end

            if shouldRender then
                methods.ScheduleDropdownDataLoad(field.key, 0, 'minecraftSkinModelRender', false, {
                    pendingValue = requestedModel,
                    pendingUsername = currentUsername,
                    pendingTexturePath = currentTexturePath,
                    beforeSnapshot = changed and beforeSnapshot or nil,
                    historyLabel = field.historyLabel,
                    delayTicks = 0,
                    loadingText = methods.localize('Settings_Loading_RefreshSkin', 'Refreshing the skin...\nPlease wait.'),
                })
                return
            end

            methods.renderActivePage()
            return
        end

        local changed = methods.applyFieldValue(field, value)

        methods.closeDropdownInternal()

        if changed then
            methods.pushHistory(field.historyLabel, beforeSnapshot)
        end

        methods.renderActivePage()

    end



    function methods.ExecuteVisibleRowAction(rowIndex)



        local resolvedRowIndex = math.floor(tonumber(rowIndex or 0) or 0)



        if resolvedRowIndex < 1 then



            return



        end



        local descriptor = state.currentRowActionByIndex[resolvedRowIndex]



        if type(descriptor) ~= 'table' then



            return



        end



        local kind = trim(descriptor.kind or '')



        if kind == 'cancelPendingConfirmation' then



            methods.CancelPendingConfirmation()



            return



        end

        if kind == 'selectSegmentedOption' then

            methods.SelectSegmentedOption(descriptor.fieldKey, descriptor.value)

            return

        end



        local fieldKey = trim(descriptor.fieldKey or '')



        if fieldKey == '' then



            return



        end



        methods.ExecuteFieldAction(fieldKey)



    end



    function methods.ExecuteVisibleRowSecondaryAction(rowIndex)



        local resolvedRowIndex = math.floor(tonumber(rowIndex or 0) or 0)



        if resolvedRowIndex < 1 then



            return



        end



        local descriptor = state.currentRowSecondaryActionByIndex[resolvedRowIndex]



        if type(descriptor) ~= 'table' then



            return



        end

        local kind = trim(descriptor.kind or '')

        if kind == 'selectSegmentedOption' then

            methods.SelectSegmentedOption(descriptor.fieldKey, descriptor.value)

            return

        end



        local fieldKey = trim(descriptor.fieldKey or '')



        if fieldKey == '' then



            return



        end



        methods.ExecuteFieldAction(fieldKey)



    end



    function methods.ExecuteFieldAction(fieldKey)







        if methods.isLoadingVisible() then







            return







        end







        local field = methods.getField(fieldKey)







        if not field then







            return







        end







        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        if field.key == 'refreshHerobrineStats' then
            methods.clearPendingConfirmation()
            methods.closeDropdownInternal()
            if methods.writePendingSettingsRoute then
                methods.writePendingSettingsRoute('content', 'herobrine', '2')
            end
            methods.QueueRefreshTargets({ Settings = true }, {
                includeSettings = true,
                forceRefresh = true,
            })
            return
        end

        if field.key == 'refreshComputerInfo' then







            methods.clearMemoryCaches()







            methods.ScheduleDropdownDataLoad(field.key, 0, 'computerInfo', false, {







                loadingText = methods.localize('Settings_Loading_ComputerInfo', 'Loading computer data for option setup.'),







                delayTicks = 0,







            })







            return







        end







        if field.key == 'openVersionManager' then



            methods.startOpenVersionManagerHelper()



            return



        end


        if field.key == 'openLogFolder' then



            methods.startOpenLogFolderHelper()



            return



        end

        if field.key == 'jukeboxHelp' then
            methods.clearPendingConfirmation()
            methods.closeDropdownInternal()
            SKIN:Bang('["' .. jukeboxHelpUrl() .. '"]')
            return
        end

        if field.key == 'attachMinecraftSkinFile' then

            local beforeMinecraftSkinSnapshot = methods.captureSnapshot()
            local modelField = methods.getField('minecraftSkinModel')
            local currentModel = modelField and methods.readFieldValue(modelField) or SKIN:GetVariable('MinecraftSkinModel', 'wide')
            local pendingModel = methods.normalizeMinecraftSkinModelInput and methods.normalizeMinecraftSkinModelInput(currentModel) or (string.lower(trim(currentModel)) == 'slim' and 'slim' or 'wide')

            methods.closeDropdownInternal()

            methods.ScheduleDropdownDataLoad(field.key, 0, 'minecraftSkinFileAttach', false, {
                pendingValue = pendingModel,
                beforeSnapshot = beforeMinecraftSkinSnapshot,
                historyLabel = field.historyLabel,
                delayTicks = 0,
                loadingText = methods.localize('Settings_Loading_MinecraftSkinFile', 'Opening the skin file picker...\nPlease wait.'),
            })

            return

        end



        if field.key == 'applyMinecraftSkin' then





            local pendingMinecraftSkinUsername = trim(SKIN:GetVariable('MinecraftSkinUsernameDraft', ''))

            local pendingAttachedSkinCacheExists = string.lower(pendingMinecraftSkinUsername) == 'a'
                and methods.resolveLocalMinecraftSkinResult
                and methods.resolveLocalMinecraftSkinResult(pendingMinecraftSkinUsername) ~= nil

            if methods.isValidMinecraftSkinUsername and not methods.isValidMinecraftSkinUsername(pendingMinecraftSkinUsername) and not pendingAttachedSkinCacheExists then
                methods.syncMinecraftSkinDraftFromCanonical()
                local invalidUsernameMessage = methods.localize('Settings_Notice_MinecraftInvalidUsernameBlocked', 'Minecraft skin apply was blocked because the username is invalid.')
                logNotice(invalidUsernameMessage)
                if methods.ShowModalAlertByKeys then
                    methods.ShowModalAlertByKeys(
                        'error',
                        'Settings_Notice_MinecraftInvalidUsernameBlocked',
                        invalidUsernameMessage
                    )
                end
                methods.renderActivePage()
                return
            end





            local beforeMinecraftSkinSnapshot = methods.captureSnapshot()





            methods.closeDropdownInternal()





            if pendingMinecraftSkinUsername == '' then





                methods.ScheduleDropdownDataLoad(field.key, 0, 'minecraftSkinApply', false, {





                    pendingValue = '',





                    beforeSnapshot = beforeMinecraftSkinSnapshot,





                    historyLabel = field.historyLabel,





                    delayTicks = 0,





                    loadingText = methods.localize('Settings_Loading_RefreshSkin', 'Refreshing the skin...\nPlease wait.'),





                })





                return





            end





            methods.ScheduleDropdownDataLoad(field.key, 0, 'minecraftSkinApply', false, {





                pendingValue = pendingMinecraftSkinUsername,





                beforeSnapshot = beforeMinecraftSkinSnapshot,





                historyLabel = field.historyLabel,





                loadingText = methods.localize('Settings_Loading_RefreshSkin', 'Refreshing the skin...\nPlease wait.'),





                delayTicks = 1,





            })





            return





        end






        if methods.isConfirmActionField(field) then







            if methods.isPendingConfirmAction(field.key) then







                methods.clearPendingConfirmation()







                methods.closeDropdownInternal()







                if field.key == 'resetAllSettings' then







                    methods.ResetToDefaults()







                    return







                end







                if field.key == 'resetAllSkinPositions' then







                    clearPendingInputState()







                    local beforeSnapshot = methods.captureSnapshot()







                    local layoutTargetIds = methods.allLayoutTargetIds()







                    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)







                    methods.ResetAllSkinPositions()







                    local afterSnapshot = methods.captureSnapshot()







                    local afterLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)







                    methods.pushHistory(field.historyLabel, beforeSnapshot, {







                        afterSnapshot = afterSnapshot,







                        beforeLayout = beforeLayoutSnapshot,







                        afterLayout = afterLayoutSnapshot,







                        layoutTargetIds = layoutTargetIds,







                    })







                    if methods.refreshRowsAndHistoryVisuals then
                        methods.refreshRowsAndHistoryVisuals()
                    else
                        methods.renderActivePage()
                    end

                    return







                end







                if TAB_SETTINGS_RESET_ACTIONS[field.key] then







                    local beforeSnapshot = methods.captureSnapshot()







                    local layoutTargetIds = methods.layoutTargetIdsForTab(field.tabId)







                    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)







                    local resetResult = methods.ResetTabToDefaults(field.tabId, field.historyLabel, { suppressHistory = true })
                    if resetResult == nil then
                        if methods.refreshRowsAndHistoryVisuals then
                            methods.refreshRowsAndHistoryVisuals()
                        else
                            methods.renderActivePage()
                        end
                        return
                    end







                    methods.ResetTabPositionsToDefaults(field.tabId)







                    pushTabLayoutHistory(field, beforeSnapshot, layoutTargetIds, beforeLayoutSnapshot)







                    if methods.refreshRowsAndHistoryVisuals then
                        methods.refreshRowsAndHistoryVisuals()
                    else
                        methods.renderActivePage()
                    end

                    return







                end







                if TAB_POSITION_RESET_ACTIONS[field.key] then







                    clearPendingInputState()







                    local beforeSnapshot = methods.captureSnapshot()







                    local layoutTargetIds = methods.layoutTargetIdsForTab(field.tabId)







                    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)







                    methods.ResetTabPositionsToDefaults(field.tabId)







                    pushTabLayoutHistory(field, beforeSnapshot, layoutTargetIds, beforeLayoutSnapshot)







                    if methods.refreshRowsAndHistoryVisuals then
                        methods.refreshRowsAndHistoryVisuals()
                    else
                        methods.renderActivePage()
                    end

                    return







                end







            else







                state.pendingConfirmActionKey = field.key







                methods.renderActivePage()







                return







            end







        end







        methods.clearPendingConfirmation()







        local beforeSnapshot = methods.captureSnapshot()







        if field.key == 'settingsTheme' then







            local nextMode = trim(methods.readFieldValue(field)) == 'dark' and 'light' or 'dark'







            methods.applyFieldValue(field, nextMode)







        end







        methods.pushHistory(field.historyLabel, beforeSnapshot)







        methods.renderActivePage()







    end
end
