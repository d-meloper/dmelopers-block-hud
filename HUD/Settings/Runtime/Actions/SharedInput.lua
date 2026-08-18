return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    function methods.clearPendingConfirmation()







        state.pendingConfirmActionKey = nil

        if methods.clearPendingStartupFastAutoRunConfirmation then

            methods.clearPendingStartupFastAutoRunConfirmation()

        end







    end







    function methods.isConfirmActionField(field)







        return field ~= nil and field.requiresConfirmation == true







    end







    function methods.isPendingConfirmAction(fieldKey)







        return fieldKey ~= nil and state.pendingConfirmActionKey == fieldKey







    end







    local function clearSharedInputState()
        setVariable('SettingsPendingInputValue', '')
        setVariable('SharedInput_Target', '')
        state.currentInputFieldKey = nil
        state.sharedInputActive = false
    end
    methods.clearSharedInputState = clearSharedInputState

    function methods.PrepareTextField(fieldKey)







        if methods.isLoadingVisible() or state.sharedInputActive then







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
            local stepperPrefix = 'SettingsRow' .. rowIndex .. '_StepperField_'
            local stepperX = tonumber(SKIN:GetVariable(stepperPrefix .. 'X', '0')) or 0
            local stepperY = tonumber(SKIN:GetVariable(stepperPrefix .. 'Y', '0')) or 0
            local stepperW = tonumber(SKIN:GetVariable(stepperPrefix .. 'W', '0')) or 0
            local stepperH = tonumber(SKIN:GetVariable(stepperPrefix .. 'H', '0')) or 0
            local stepperPad = tonumber(SKIN:ReplaceVariables('#SlotSettingsRowText_ContentPad#')) or tonumber(SKIN:ReplaceVariables('#SettingsInnerPad#')) or 0
            setVariable('SharedInput_X', tostring(stepperX + stepperPad))
            setVariable('SharedInput_Y', tostring(stepperY + stepperPad))
            setVariable('SharedInput_W', tostring(math.max(0, stepperW - (2 * stepperPad))))
            setVariable('SharedInput_H', tostring(math.max(0, stepperH - (2 * stepperPad))))
        else







            setVariable('SharedInput_X', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentX', '0'))







            setVariable('SharedInput_Y', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentY', '0'))







            setVariable('SharedInput_W', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentW', '0'))







            setVariable('SharedInput_H', SKIN:GetVariable('SettingsRow' .. rowIndex .. '_FieldContentH', '0'))







        end







        setVariable('SharedInput_Default', methods.displayValueForField(field, methods.readFieldValue(field)))







        methods.renderActivePage()







    end







    function methods.OpenPreparedTextField()
        if state.sharedInputActive then
            return 0
        end

        local fieldKey = state.currentInputFieldKey
        if not fieldKey or fieldKey == '' then
            fieldKey = trim(SKIN:GetVariable('SharedInput_Target', ''))
        end

        local field = methods.getField(fieldKey)
        local rowIndex = state.currentVisibleRows[fieldKey]
        if not field or not rowIndex or (methods.isFieldDisabled and methods.isFieldDisabled(field)) then
            clearSharedInputState()
            return 0
        end

        state.sharedInputActive = true
        SKIN:Bang('!UpdateMeasure', 'MeasureSharedInput')
        SKIN:Bang('!CommandMeasure', 'MeasureSharedInput', 'ExecuteBatch 1-2')


        return 0
    end

    function methods.DismissPreparedTextField()
        clearSharedInputState()
        return 0
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
        methods.OpenPreparedTextField()







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







        local fieldKey = methods.fieldKeyForVisibleRow(rowIndex)







        local field = methods.getField(fieldKey)







        if not fieldKey or (field.controlType ~= 'text' and field.controlType ~= 'multiDropdown') or not methods.hasDropdown(field) then







            return







        end







        local numericRowIndex = tonumber(rowIndex) or 0

        if field.dropdownId == 'hudMirrorSelection'
            and methods.ValidateHudMirrorDropdownMonitor
            and not methods.ValidateHudMirrorDropdownMonitor(field, numericRowIndex) then
            return
        end

        if methods.isFieldDisabled and methods.isFieldDisabled(field) then
            return
        end







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
end
