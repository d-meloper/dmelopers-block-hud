return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    function methods.CommitPendingInput()







        if methods.isLoadingVisible() then







            methods.clearSharedInputState()
            return







        end







        methods.clearPendingConfirmation()







        local fieldKey = state.currentInputFieldKey







        if not fieldKey or fieldKey == '' then







            fieldKey = trim(SKIN:GetVariable('SharedInput_Target', ''))







        end







        local field = methods.getField(fieldKey)







        if not field then







            methods.clearSharedInputState()
            return







        end







        local beforeSnapshot = methods.captureSnapshot()







        local pendingValue = trim(SKIN:GetVariable('SettingsPendingInputValue', ''))
        if field.key == 'minecraftSkinUsernameDraft' then
            local inputMeasure = SKIN:GetMeasure('MeasureSharedInput')
            if inputMeasure then
                pendingValue = trim(inputMeasure:GetStringValue() or pendingValue)
            end
        end







        setVariable('SettingsPendingInputValue', '')







        setVariable('SharedInput_Target', '')







        state.currentInputFieldKey = nil
        state.sharedInputActive = false
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

        if fieldKey == 'startupFastAutoRun'
            and methods.isStartupFastAutoRunConfirmationPending
            and methods.isStartupFastAutoRunConfirmationPending() then
            return
        end

        methods.clearPendingConfirmation()

        local field = methods.getField(fieldKey)
        if not field then
            return
        end

        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end

        if field.key == 'startupAutoRun' then
            local nextLiteral = methods.nextStoredToggleValue(field)
            methods.ScheduleStartupAutoRunTransition(
                field.key,
                nextLiteral,
                nextLiteral == '1' and 'shortcut' or 'all')
            return
        end

        if field.key == 'startupFastAutoRun' then
            if methods.normalizeToggleValue(methods.readFieldValue(field)) == '1' then
                methods.ScheduleStartupAutoRunTransition(field.key, '1', 'shortcut')
            else
                methods.RequestStartupFastAutoRunConfirmation()
            end
            return
        end

        local beforeSnapshot = methods.captureSnapshot()
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
end
