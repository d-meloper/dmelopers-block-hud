return function(app)







    local state = app.state







    local schema = app.schema







    local methods = app.methods







    local trim = app.trim







    local shallowCopy = app.shallowCopy







    local logNotice = app.logNotice







    local setVariable = app.setVariable




    local function fileExists(path)



        local handle = io.open(tostring(path or ''), 'rb')



        if handle then



            handle:close()



            return true



        end



        return false



    end



    local function resolvePowerShellProgramPath()



        local systemRoot = os.getenv('SystemRoot') or os.getenv('WINDIR') or 'C:\\Windows'



        local primary = systemRoot .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'



        if fileExists(primary) then



            return primary



        end



        local sysnative = systemRoot .. '\\Sysnative\\WindowsPowerShell\\v1.0\\powershell.exe'



        if fileExists(sysnative) then



            return sysnative



        end



        return 'powershell'



    end



    local function syncPowerShellProgramPath()



        setVariable('SettingsPowerShellProgram', resolvePowerShellProgramPath())



    end







    local FULL_REFRESH_BATCHES = {







        { 'Hotbar' },







        { 'Inventory' },







        { 'InventoryBG', 'Clock' },







        { 'Editor' },







        { 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' },







    }







    local function refreshTarget(targetName, forceRefresh)







        local target = schema.refreshTargetsByName[targetName]







        if not target or state.rootConfig == '' then







            return false







        end







        local configPath = state.rootConfig .. '\\' .. target.config

        if targetName == 'Settings' then
            local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
            local currentFile = trim(SKIN:GetVariable('CURRENTFILE', target.file or 'Settings.ini'))
            if currentConfig == '' then
                return false
            end
            SKIN:Bang('!Refresh', currentConfig, currentFile ~= '' and currentFile or (target.file or 'Settings.ini'))
            return true
        end







        local isActive = methods.isConfigTargetActive(targetName)







        if not isActive and forceRefresh ~= true then







            return false







        end







        if isActive and targetName == 'Inventory' then







            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()', configPath)







        elseif isActive then







            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()', configPath)







        end







        SKIN:Bang('!Refresh', configPath, target.file)







        return true







    end







    local function refreshBatch(batch, options)







        for _, targetName in ipairs(batch or {}) do







            refreshTarget(targetName, options and options.forceRefresh == true)







        end







    end







    local function pendingRefreshTargetSet()

        local seen = {}

        local batches = state.pendingRefreshBatches or {}

        local startIndex = (tonumber(state.pendingRefreshBatchIndex) or 0) + 1

        for index = startIndex, #batches do

            for _, targetName in ipairs(batches[index] or {}) do

                seen[targetName] = true

            end

        end

        return seen

    end

    local function normalizePendingRefreshOptions(options)

        local resolved = options or {}

        return {

            includeSettings = resolved.includeSettings == true,

            loadingText = trim(resolved.loadingText or ''),
            delayTicks = math.max(0, tonumber(resolved.delayTicks) or 0),
            forceRefresh = resolved.forceRefresh == true,

        }

    end







    local function appendRefreshBatches(batches, options)



        options = options or {}



        if options.replace then



            methods.clearPendingRefreshState()



        end



        local pendingBatches = state.pendingRefreshBatches or {}

        local pendingOptions = normalizePendingRefreshOptions(options)

        local existingOptions = state.pendingRefreshOptions or {}

        if existingOptions.includeSettings == true then

            pendingOptions.includeSettings = true

        end

        if existingOptions.forceRefresh == true then

            pendingOptions.forceRefresh = true

        end

        if pendingOptions.loadingText == '' then

            pendingOptions.loadingText = trim(existingOptions.loadingText or '')

        end

        local seen = pendingRefreshTargetSet()



        local added = false



        for _, batch in ipairs(batches or {}) do



            local queuedBatch = {}



            for _, targetName in ipairs(batch or {}) do



                if schema.refreshTargetsByName[targetName] and not seen[targetName] then



                    queuedBatch[#queuedBatch + 1] = targetName



                    seen[targetName] = true



                end



            end



            if #queuedBatch > 0 then



                pendingBatches[#pendingBatches + 1] = queuedBatch



                added = true



            end



        end



        state.pendingRefreshBatches = pendingBatches



        state.pendingRefreshBatchTotal = #pendingBatches

        state.pendingRefreshDelayTicksRemaining = math.max(
            tonumber(state.pendingRefreshDelayTicksRemaining) or 0,
            pendingOptions.delayTicks or 0)

        if #pendingBatches > 0 and (pendingOptions.includeSettings or pendingOptions.loadingText ~= '') then

            state.pendingRefreshOptions = pendingOptions

        else

            state.pendingRefreshOptions = nil

        end

        setVariable('SettingsPendingRefreshBatchIndex', tostring(state.pendingRefreshBatchIndex or 0))



        setVariable('SettingsPendingRefreshBatchTotal', tostring(state.pendingRefreshBatchTotal or 0))



        if added then
            if pendingOptions.loadingText ~= '' then
                methods.setLoadingVisible(true, pendingOptions.loadingText)
            end
            if pendingOptions.includeSettings == true or pendingOptions.loadingText ~= '' then
                methods.renderActivePage()
            end

            SKIN:Bang('!EnableMeasure', 'MeasureSettingsDeferredRefresh')



        end



        return added



    end







    function methods.QueueRefreshBatches(batches, options)



        return appendRefreshBatches(batches, options)



    end







    function methods.QueueRefreshTargets(targetSet, options)



        local batches = {}



        local included = {}



        for _, templateBatch in ipairs(FULL_REFRESH_BATCHES) do



            local batch = {}



            for _, targetName in ipairs(templateBatch or {}) do



                if targetSet and targetSet[targetName] then



                    batch[#batch + 1] = targetName



                    included[targetName] = true



                end



            end



            if #batch > 0 then



                batches[#batches + 1] = batch



            end



        end



        local extras = {}

        local includeSettingsRefresh = options.includeSettings == true and targetSet and targetSet.Settings == true



        for targetName, _ in pairs(targetSet or {}) do



            if targetName ~= 'Settings' and schema.refreshTargetsByName[targetName] and not included[targetName] then



                extras[#extras + 1] = targetName



            end



        end



        table.sort(extras)



        for _, targetName in ipairs(extras) do



            batches[#batches + 1] = { targetName }



        end




        if includeSettingsRefresh then
            batches[#batches + 1] = { 'Settings' }
        end
        local added = appendRefreshBatches(batches, options)
        return added



    end





    local function setSettingsOpenFlag(isOpen)







        local value = isOpen and '1' or '0'







        setVariable('SettingsUIOpen', value)







        methods.ensurePaths()
        local rootConfig = trim(state.rootConfig or '')







        if rootConfig == '' then







            return







        end







        for _, configName in ipairs({ 'Inventory', 'InventoryBG', 'Hotbar' }) do







            SKIN:Bang('!SetVariable', 'SettingsUIOpen', value, rootConfig .. '\\' .. configName)







        end







    end







    local PROTECTED_PENDING_HELPER_LOAD_KINDS = {
        legacyImport = true,
    }
    local function protectedPendingHelperKind()
        if state.pendingLoadHelperRunning == true then
            local loadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or '')
            if loadKind ~= '' and PROTECTED_PENDING_HELPER_LOAD_KINDS[loadKind] then
                return loadKind
            end
        end
        local now = os.time()
        if type(now) ~= 'number' or now <= 0 then
            return nil
        end
        if type(state.ignoredPendingLoadHelpers) == 'table' then
            local legacyEntry = state.ignoredPendingLoadHelpers.legacyImport
            if type(legacyEntry) == 'table' and (tonumber(legacyEntry.protectedUntil) or 0) > now then
                return 'legacyImport'
            end
        end
        return nil
    end
    local function protectedPendingHelperLabel(loadKind)
        if trim(loadKind or '') == 'legacyImport' then
            return methods.localize('Settings_Field_importLegacyData_Label', 'Import old data')
        end
        return methods.localize('Settings_Field_importLegacyData_Label', 'Import old data')
    end
    local function warnProtectedPendingHelperCloseBlocked(loadKind, source)
        logNotice('Blocked Settings close during protected helper run (' .. tostring(source or 'unknown') .. '): ' .. tostring(loadKind or ''))
    end
    local function reactivateSettingsAfterProtectedClose(loadKind)
        local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
        local currentFile = trim(SKIN:GetVariable('CURRENTFILE', 'Settings.ini'))
        warnProtectedPendingHelperCloseBlocked(loadKind, 'HandleClose')
        setSettingsOpenFlag(true)
        if currentConfig ~= '' then
            SKIN:Bang('!ActivateConfig', currentConfig, currentFile ~= '' and currentFile or 'Settings.ini')
        end
    end
    function methods.clearPendingConfirmation()







        state.pendingConfirmActionKey = nil







    end







    function methods.isConfirmActionField(field)







        return field ~= nil and field.requiresConfirmation == true







    end







    function methods.isPendingConfirmAction(fieldKey)







        return fieldKey ~= nil and state.pendingConfirmActionKey == fieldKey







    end







    function methods.PrepareTextField(fieldKey)







        if methods.isLoadingVisible() then







            return







        end







        methods.clearPendingConfirmation()







        local field = methods.getField(fieldKey)







        local rowIndex = state.currentVisibleRows[fieldKey]
        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end







        if not field or not rowIndex then







            return







        end







        if state.activeDropdownFieldKey then







            methods.closeDropdownInternal()







        end







        state.currentInputFieldKey = fieldKey







        setVariable('SharedInput_Target', fieldKey)







        if field.controlType == 'stepper' then







            setVariable('SharedInput_X', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_StepperField_X', '0'))







            setVariable('SharedInput_Y', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_StepperField_Y', '0'))







            setVariable('SharedInput_W', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_StepperField_W', '0'))







            setVariable('SharedInput_H', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_StepperField_H', '0'))







        else







            setVariable('SharedInput_X', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentX', '0'))







            setVariable('SharedInput_Y', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentY', '0'))







            setVariable('SharedInput_W', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentW', '0'))







            setVariable('SharedInput_H', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentH', '0'))







        end







        setVariable('SharedInput_Default', methods.displayValueForField(field, methods.readFieldValue(field)))







        methods.renderActivePage()







    end







    function methods.ActivateVisibleRowInput(rowIndex)







        if methods.isLoadingVisible() then







            return







        end







        local fieldKey = methods.fieldKeyForVisibleRow(rowIndex)







        if not fieldKey then







            return







        end







        methods.PrepareTextField(fieldKey)







    end







    function methods.StepVisibleRowDown(rowIndex)







        if methods.isLoadingVisible() then







            return







        end







        local fieldKey = methods.fieldKeyForVisibleRow(rowIndex, 'stepper')







        if not fieldKey then







            return







        end







        methods.AdjustField(fieldKey, -1)







    end







    function methods.StepVisibleRowUp(rowIndex)







        if methods.isLoadingVisible() then







            return







        end







        local fieldKey = methods.fieldKeyForVisibleRow(rowIndex, 'stepper')







        if not fieldKey then







            return







        end







        methods.AdjustField(fieldKey, 1)







    end







    function methods.ToggleVisibleRowDropdown(rowIndex)







        if methods.isLoadingVisible() then







            return







        end







        methods.clearPendingConfirmation()







        local fieldKey = methods.fieldKeyForVisibleRow(rowIndex, 'text')







        local field = methods.getField(fieldKey)







        if not fieldKey or not methods.hasDropdown(field) then







            return







        end







        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        local numericRowIndex = tonumber(rowIndex) or 0







        if state.activeDropdownFieldKey == fieldKey and state.activeDropdownRowIndex == numericRowIndex then







            methods.closeDropdownInternal()







            methods.renderActivePage()







            return







        end







        local loadState = methods.ensureDropdownDataReady(field, numericRowIndex)







        if loadState ~= 'ready' then







            return







        end







        state.activeDropdownFieldKey = fieldKey







        state.activeDropdownRowIndex = numericRowIndex







        state.activeDropdownPageIndex = methods.optionPageForValue(field, methods.readFieldValue(field))







        methods.renderActivePage()







    end







    local function clearPendingLanguageSwitchState()
        state.pendingLanguageSwitchValue = nil
        state.pendingLanguageSwitchBeforeSnapshot = nil
        state.pendingLanguageSwitchSubmitActionFieldKey = nil
    end


    methods.CancelPendingLanguageSwitchInternal = function()
        SKIN:Bang('!DisableMeasure', 'MeasureSettingsDeferredLanguageSwitch')
        clearPendingLanguageSwitchState()
    end

    local function queuePendingLanguageSwitch(field, option, beforeSnapshot, submitActionFieldKey)
        if not field or field.key ~= 'language' or not option then
            return false
        end

        local currentLanguage = methods.normalizeLanguageCode(methods.readFieldValue(field), 'ko-KR')
        local targetLanguage = methods.normalizeLanguageCode(option.appliedValue, currentLanguage)
        if targetLanguage == currentLanguage then
            return false
        end

        state.pendingLanguageSwitchValue = targetLanguage
        state.pendingLanguageSwitchBeforeSnapshot = shallowCopy(beforeSnapshot or methods.captureSnapshot())
        state.pendingLanguageSwitchSubmitActionFieldKey = trim(submitActionFieldKey or '')

        methods.closeDropdownInternal()
        methods.setLoadingVisible(true, methods.languageSwitchLoadingText(targetLanguage))
        methods.renderActivePage()
        SKIN:Bang('!EnableMeasure', 'MeasureSettingsDeferredLanguageSwitch')
        return true
    end

    function methods.RunPendingLanguageSwitch()
        local pendingValue = trim(state.pendingLanguageSwitchValue or '')
        local beforeSnapshot = state.pendingLanguageSwitchBeforeSnapshot
        local submitActionFieldKey = trim(state.pendingLanguageSwitchSubmitActionFieldKey or '')

        SKIN:Bang('!DisableMeasure', 'MeasureSettingsDeferredLanguageSwitch')
        clearPendingLanguageSwitchState()

        local field = methods.getField('language')
        if not field or pendingValue == '' then
            methods.setLoadingVisible(false)
            methods.renderActivePage()
            return false
        end

        methods.persistPendingLanguageFanoutRequest(pendingValue)
        methods.applyFieldValue(field, pendingValue, { deferLanguageFanout = true })

        if submitActionFieldKey ~= '' then
            methods.ExecuteFieldAction(submitActionFieldKey)
            return true
        end

        if beforeSnapshot then
            methods.pushHistory(field.historyLabel, beforeSnapshot)
        end

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







    function methods.CommitPendingInput()







        if methods.isLoadingVisible() then







            return







        end







        methods.clearPendingConfirmation()







        local fieldKey = state.currentInputFieldKey







        if not fieldKey or fieldKey == '' then







            fieldKey = trim(SKIN:GetVariable('SharedInput_Target', ''))







        end







        local field = methods.getField(fieldKey)







        if not field then







            return







        end







        local beforeSnapshot = methods.captureSnapshot()







        local pendingValue = trim(SKIN:GetVariable('SettingsPendingInputValue', ''))







        setVariable('SettingsPendingInputValue', '')







        setVariable('SharedInput_Target', '')







        state.currentInputFieldKey = nil







        local submitActionFieldKey = trim(field.submitActionFieldKey or '')







        if submitActionFieldKey ~= '' then







            methods.applyFieldValue(field, pendingValue)







            methods.ExecuteFieldAction(submitActionFieldKey)







            return







        end







        methods.applyFieldValue(field, pendingValue)







        methods.pushHistory(field.historyLabel, beforeSnapshot)







        methods.renderActivePage()







    end







    function methods.ToggleField(fieldKey)







        if methods.isLoadingVisible() then







            return







        end







        methods.clearPendingConfirmation()







        local field = methods.getField(fieldKey)







        if not field then







            return







        end







        local beforeSnapshot = methods.captureSnapshot()







        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        if field.key == 'startupAutoRun' then







            methods.ScheduleDropdownDataLoad(field.key, 0, 'startupAutoRunApply', false, {







                pendingValue = methods.nextStoredToggleValue(field),







                beforeSnapshot = beforeSnapshot,







                historyLabel = field.historyLabel,







                loadingText = methods.localize('Settings_Loading_StartupApply', 'Applying startup setting...\\nPlease wait.'),







            })







            return







        end







        methods.applyFieldValue(field, methods.nextStoredToggleValue(field))







        methods.pushHistory(field.historyLabel, beforeSnapshot)







        methods.renderActivePage()







    end







    function methods.AdjustField(fieldKey, direction)







        if methods.isLoadingVisible() then







            return







        end







        methods.clearPendingConfirmation()







        local field = methods.getField(fieldKey)







        if not field then







            return







        end







        local beforeSnapshot = methods.captureSnapshot()







        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        local currentValue = tonumber(methods.readFieldValue(field)) or tonumber(field.min) or 0







        local delta = (field.step or 1) * (tonumber(direction) or 0)







        methods.applyFieldValue(field, tostring(currentValue + delta))







        methods.pushHistory(field.historyLabel, beforeSnapshot)







        methods.renderActivePage()







    end







    function methods.StepFieldDown(fieldKey)







        methods.AdjustField(fieldKey, -1)







    end







    function methods.StepFieldUp(fieldKey)







        methods.AdjustField(fieldKey, 1)







    end







    function methods.CancelPendingConfirmation()







        methods.clearPendingConfirmation()







        methods.renderActivePage()







    end







    function methods.RefreshSkin()
        SKIN:Bang('!RefreshApp')
    end















    function methods.RunPendingRefresh()

        local pendingOptions = state.pendingRefreshOptions or {}

        local batches = state.pendingRefreshBatches or {}







        if (tonumber(state.pendingRefreshDelayTicksRemaining) or 0) > 0 then
            state.pendingRefreshDelayTicksRemaining = (tonumber(state.pendingRefreshDelayTicksRemaining) or 0) - 1
            return true
        end

        local nextIndex = (tonumber(state.pendingRefreshBatchIndex) or 0) + 1







        if nextIndex > #batches then







            methods.clearPendingRefreshState()

            if pendingOptions.loadingText ~= '' then

                methods.setLoadingVisible(false)

            end

            if pendingOptions.includeSettings == true or pendingOptions.loadingText ~= '' then

                methods.renderActivePage()

            end

            return false







        end







        state.pendingRefreshBatchIndex = nextIndex







        state.pendingRefreshBatchTotal = #batches







        setVariable('SettingsPendingRefreshBatchIndex', tostring(nextIndex))







        setVariable('SettingsPendingRefreshBatchTotal', tostring(#batches))







        refreshBatch(batches[nextIndex], pendingOptions)







        if nextIndex >= #batches then

            methods.clearPendingRefreshState()

            if pendingOptions.loadingText ~= '' then

                methods.setLoadingVisible(false)

            end

            if pendingOptions.includeSettings == true or pendingOptions.loadingText ~= '' then

                methods.renderActivePage()

            end

        end







        return true







    end







    local TAB_SETTINGS_RESET_ACTIONS = {







        resetHotbarSettings = true,







        resetIndicatorsSettings = true,







        resetInventorySettings = true,







        resetClockSettings = true,







    }







    local TAB_POSITION_RESET_ACTIONS = {







        resetHotbarSkinPositions = true,







        resetIndicatorsSkinPositions = true,







        resetInventorySkinPositions = true,







        resetClockSkinPositions = true,







    }







    local function clearPendingInputState()







        setVariable('SettingsPendingInputValue', '')







        setVariable('SharedInput_Target', '')







        state.currentInputFieldKey = nil







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

        if field.key == 'refreshComputerInfo' then







            methods.clearMemoryCaches()







            methods.ScheduleDropdownDataLoad(field.key, 0, 'computerInfo', false, {







                loadingText = methods.localize('Settings_Loading_ComputerInfo', 'Loading computer data for option setup.'),







                delayTicks = 0,







            })







            return







        end







        if field.key == 'importLegacyData' then



            methods.ScheduleDropdownDataLoad(field.key, 0, 'legacyImport', false, {



                loadingText = methods.localize('Settings_Loading_LegacyImport', 'Importing data from an older version.\\n\\nWhen the folder picker opens, choose the old skin folder.'),



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



        if field.key == 'applyMinecraftSkin' then





            local pendingMinecraftSkinUsername = trim(SKIN:GetVariable('MinecraftSkinUsernameDraft', ''))





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





            local localMinecraftSkinResult = methods.resolveLocalMinecraftSkinResult and methods.resolveLocalMinecraftSkinResult(pendingMinecraftSkinUsername) or nil





            if localMinecraftSkinResult then





                state.pendingLoadBeforeSnapshot = beforeMinecraftSkinSnapshot





                state.pendingLoadHistoryLabel = field.historyLabel





                methods.applyMinecraftSkinFetchResult(localMinecraftSkinResult)





                state.pendingLoadBeforeSnapshot = nil





                state.pendingLoadHistoryLabel = nil





                methods.renderActivePage()





                return





            end





            methods.ScheduleDropdownDataLoad(field.key, 0, 'minecraftSkinApply', false, {





                pendingValue = pendingMinecraftSkinUsername,





                beforeSnapshot = beforeMinecraftSkinSnapshot,





                historyLabel = field.historyLabel,





                loadingText = methods.localize('Settings_Loading_RefreshSkin', 'Refreshing the skin...\nPlease wait.'),





                delayTicks = 0,





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







                    methods.ResetTabToDefaults(field.tabId, field.historyLabel, { suppressHistory = true })







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







    function methods.PrevTab()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        methods.closeDropdownInternal()







        state.currentTabIndex = state.currentTabIndex - 1







        if state.currentTabIndex < 1 then







            state.currentTabIndex = #schema.tabs







        end







        state.currentPageByTab[state.currentTabIndex] = 1







        methods.renderActivePage()







    end







    function methods.NextTab()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        methods.closeDropdownInternal()







        state.currentTabIndex = state.currentTabIndex + 1







        if state.currentTabIndex > #schema.tabs then







            state.currentTabIndex = 1







        end







        state.currentPageByTab[state.currentTabIndex] = 1







        methods.renderActivePage()







    end







    function methods.PrevPage()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        local pageCount = methods.getTabPageCount(methods.activeTab())







        if pageCount <= 1 then







            return







        end







        methods.closeDropdownInternal()







        local nextPage = methods.activePageIndex() - 1







        if nextPage < 1 then







            nextPage = pageCount







        end







        state.currentPageByTab[state.currentTabIndex] = nextPage







        methods.renderActivePage()







    end







    function methods.NextPage()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        local pageCount = methods.getTabPageCount(methods.activeTab())







        if pageCount <= 1 then







            return







        end







        methods.closeDropdownInternal()







        local nextPage = methods.activePageIndex() + 1







        if nextPage > pageCount then







            nextPage = 1







        end







        state.currentPageByTab[state.currentTabIndex] = nextPage







        methods.renderActivePage()







    end







    local function refreshAfterStateRestore(restoreTargets)
    if restoreTargets and restoreTargets.Settings == true then
        if methods.refreshCurrentPageContent then
            methods.refreshCurrentPageContent()
        else
            methods.renderActivePage()
        end
    else
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
    end
end

function methods.UndoChange()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    local entry = table.remove(state.undoHistory)
    if not entry then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    state.redoHistory[#state.redoHistory + 1] = {
        label = entry.label,
        before = shallowCopy(entry.before),
        after = shallowCopy(entry.after),
        tabId = entry.tabId,
        beforeLayout = methods.copyLayoutSnapshot(entry.beforeLayout),
        afterLayout = methods.copyLayoutSnapshot(entry.afterLayout),
        layoutTargetIds = methods.copyLayoutTargetIds(entry.layoutTargetIds),
    }

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(entry.before, { suppressRender = true, skipFieldKeys = { 'startupAutoRun' } })

    if entry.beforeLayout then
        if entry.layoutTargetIds and #entry.layoutTargetIds > 0 then
            methods.restoreLayoutSnapshot(entry.beforeLayout, entry.layoutTargetIds)
        elseif entry.tabId then
            methods.restoreTabLayoutSnapshot(entry.tabId, entry.beforeLayout)
        end
    end

    refreshAfterStateRestore(restoreTargets)
end

function methods.RedoChange()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    local entry = table.remove(state.redoHistory)
    if not entry then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    state.undoHistory[#state.undoHistory + 1] = {
        label = entry.label,
        before = shallowCopy(entry.before),
        after = shallowCopy(entry.after),
        tabId = entry.tabId,
        beforeLayout = methods.copyLayoutSnapshot(entry.beforeLayout),
        afterLayout = methods.copyLayoutSnapshot(entry.afterLayout),
        layoutTargetIds = methods.copyLayoutTargetIds(entry.layoutTargetIds),
    }

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(entry.after, { suppressRender = true, skipFieldKeys = { 'startupAutoRun' } })

    if entry.afterLayout then
        if entry.layoutTargetIds and #entry.layoutTargetIds > 0 then
            methods.restoreLayoutSnapshot(entry.afterLayout, entry.layoutTargetIds)
        elseif entry.tabId then
            methods.restoreTabLayoutSnapshot(entry.tabId, entry.afterLayout)
        end
    end

    refreshAfterStateRestore(restoreTargets)
end

function methods.ResetSession()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    if not state.baselineSnapshot or not state.baselineLayoutSnapshot then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    local beforeSnapshot = methods.captureSnapshot()
    local layoutTargetIds = state.baselineLayoutTargetIds or methods.allLayoutTargetIds()
    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    if app.snapshotSignature(beforeSnapshot) == app.snapshotSignature(state.baselineSnapshot)
        and methods.layoutSnapshotSignature(beforeLayoutSnapshot) == methods.layoutSnapshotSignature(state.baselineLayoutSnapshot) then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(state.baselineSnapshot, { suppressRender = true, skipFieldKeys = { 'startupAutoRun' } })
    methods.restoreLayoutSnapshot(state.baselineLayoutSnapshot, layoutTargetIds)

    local afterSnapshot = methods.captureSnapshot()
    local afterLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    methods.pushHistory('Session reset', beforeSnapshot, {
        afterSnapshot = afterSnapshot,
        beforeLayout = beforeLayoutSnapshot,
        afterLayout = afterLayoutSnapshot,
        layoutTargetIds = layoutTargetIds,
    })

    refreshAfterStateRestore(restoreTargets)
end

function methods.ResetToDefaults()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    local resetFieldKeys = {}
    for _, fieldKey in ipairs(schema.trackedFieldKeys) do
        if fieldKey ~= 'startupAutoRun' then
            resetFieldKeys[#resetFieldKeys + 1] = fieldKey
        end
    end

    local defaultSnapshot, missingKeys = methods.loadDefaultSnapshot(resetFieldKeys)
    if not defaultSnapshot then
        logNotice('Settings default snapshot is incomplete: ' .. table.concat(missingKeys or {}, ', '))
        methods.renderActivePage()
        return
    end

    local beforeSnapshot = methods.captureSnapshot()
    local layoutTargetIds = methods.allLayoutTargetIds()
    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(defaultSnapshot, { suppressRender = true, fieldKeys = resetFieldKeys, skipFieldKeys = { 'startupAutoRun' } })
    methods.ResetAllSkinPositions()

    local afterSnapshot = methods.captureSnapshot()
    local afterLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    methods.pushHistory('Reset all settings', beforeSnapshot, {
        afterSnapshot = afterSnapshot,
        beforeLayout = beforeLayoutSnapshot,
        afterLayout = afterLayoutSnapshot,
        layoutTargetIds = layoutTargetIds,
    })

    refreshAfterStateRestore(restoreTargets)
end

function methods.CloseSettings()
        local loadKind = protectedPendingHelperKind()
        if loadKind then
            warnProtectedPendingHelperCloseBlocked(loadKind, 'CloseSettings')
            methods.renderActivePage()
            return
        end
        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end
        methods.clearPendingConfirmation()
        setSettingsOpenFlag(false)
        SKIN:Bang('!DeactivateConfig', SKIN:GetVariable('CURRENTCONFIG'))
    end

    function methods.PrepareForVersionSwitch()
        local activeLoadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or '')
        if state.pendingLoadHelperRunning == true and activeLoadKind == 'legacyImport' then
            warnProtectedPendingHelperCloseBlocked('legacyImport', 'PrepareForVersionSwitch')
            methods.renderActivePage()
            return false
        end
        if methods.clearIgnoredPendingLoadHelperCompletion then
            methods.clearIgnoredPendingLoadHelperCompletion('legacyImport')
        end
        if methods.clearVersionManagerLaunchPending then
            methods.clearVersionManagerLaunchPending({ render = false })
        end
        SKIN:Bang('!SetVariable', 'SettingsVersionSwitchClose', '1')
        setSettingsOpenFlag(false)
        SKIN:Bang('!DeactivateConfig', SKIN:GetVariable('CURRENTCONFIG'))
        return true
    end

    function methods.HandleClose()
        local versionSwitchClose = trim(SKIN:GetVariable('SettingsVersionSwitchClose', '0')) == '1'
        if versionSwitchClose then
            SKIN:Bang('!SetVariable', 'SettingsVersionSwitchClose', '0')
            local activeLoadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or '')
            if state.pendingLoadHelperRunning == true and activeLoadKind == 'legacyImport' then
                reactivateSettingsAfterProtectedClose('legacyImport')
                return 0
            end
            if methods.clearIgnoredPendingLoadHelperCompletion then
                methods.clearIgnoredPendingLoadHelperCompletion('legacyImport')
            end
            if methods.clearVersionManagerLaunchPending then
                methods.clearVersionManagerLaunchPending({ render = false })
            end
            methods.clearPendingLoadState()
            methods.clearPendingRefreshState()
            methods.setLoadingVisible(false)
            setSettingsOpenFlag(false)
            return 0
        end
        local loadKind = protectedPendingHelperKind()
        if loadKind then
            reactivateSettingsAfterProtectedClose(loadKind)
            return 0
        end
        methods.clearPendingLoadState()
        methods.clearPendingRefreshState()
        methods.setLoadingVisible(false)
        setSettingsOpenFlag(false)
        return 0
    end

    function methods.Initialize()







        syncPowerShellProgramPath()



        methods.ensurePaths()







        methods.applyTheme(trim(SKIN:GetVariable('SettingsThemeMode', 'light')))







        setSettingsOpenFlag(true)







        state.currentTabIndex = 1







        state.currentPageByTab = {}







        for index = 1, state.tabCount do







            state.currentPageByTab[index] = 1







        end







        state.currentInputFieldKey = nil







        state.currentVisibleRows = {}







        state.currentFieldKeyByRow = {}







        state.activeDropdownFieldKey = nil







        state.activeDropdownRowIndex = 0







        state.activeDropdownPageIndex = 1







        state.currentDropdownOptionBySlot = {}







        state.pendingConfirmActionKey = nil







        state.undoHistory = {}







        methods.syncMinecraftSkinDraftFromCanonical()







        state.redoHistory = {}







        methods.clearMemoryCaches()







        methods.clearPendingLoadState()



        methods.clearPendingRefreshState()



        methods.setLoadingVisible(false)






        local pendingLanguageFanoutCode = methods.consumePendingLanguageFanoutRequest()
        if pendingLanguageFanoutCode ~= '' then
            methods.setLoadingVisible(true, methods.languageSwitchLoadingText(pendingLanguageFanoutCode))
        end

        local computerInfoReady = methods.RestorePersistentCache('computerInfo')







        if computerInfoReady then







            methods.hydrateStartupAutoRunFieldFromCache()







        end







        methods.captureBaselineState()







        methods.clearDropdownVisualState()







        methods.renderActivePage()







        if pendingLanguageFanoutCode ~= '' then
            local languageField = methods.getField('language')
            local targetSet = {}
            if languageField then
                for _, targetName in ipairs(languageField.refreshTargets or {}) do
                    if targetName ~= 'Settings' then
                        targetSet[targetName] = true
                    end
                end
            end
            methods.refreshTargets(targetSet, {
                loadingText = methods.languageSwitchLoadingText(pendingLanguageFanoutCode),
                delayTicks = 0,
                forceRefresh = true,
            })
        elseif not computerInfoReady then







            methods.ScheduleDropdownDataLoad('startupAutoRun', 0, 'computerInfo', false, {



                loadingText = methods.localize('Settings_Loading_ComputerInfo_FirstRun', 'Loading computer data for option setup.\\n(*Runs only once on first use.)'),



                delayTicks = 8,



            })







        end







    end







end
