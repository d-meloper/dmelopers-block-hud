return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local helpers = app.renderHelpers or {}
    local contractVariable = helpers.contractVariable
    local dropdownClosedText = helpers.dropdownClosedText
    local dropdownOpenText = helpers.dropdownOpenText
    local pixelValue = helpers.pixelValue
    function methods.resetRowBaseGeometry(rowIndex)

        setVariable('SettingsRow' .. rowIndex .. '_LabelX', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_LabelTextX', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_LabelY', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_LabelTextY', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_LabelW', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_LabelW', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_LabelH', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_LabelH', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_Field_X', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_ControlX', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_Field_Y', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_Field_W', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_ControlW', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_Field_H', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', '0'))

        local prefix = 'SettingsRow' .. tostring(rowIndex)
        local slotPrefix = 'SlotSettingsRow' .. tostring(rowIndex)
        local labelX = pixelValue(methods.numericVariable(slotPrefix .. '_LabelTextX', 0), 0)
        local labelY = pixelValue(methods.numericVariable(slotPrefix .. '_LabelTextY', 0), 0)
        local labelW = pixelValue(methods.numericVariable(slotPrefix .. '_LabelW', 0), 0)
        local labelH = pixelValue(methods.numericVariable(slotPrefix .. '_LabelH', methods.numericVariable('SettingsTall1H', 40)), 40)
        local controlX = pixelValue(methods.numericVariable(slotPrefix .. '_ControlX', 0), 0)
        local controlY = pixelValue(methods.numericVariable(slotPrefix .. '_ControlY', 0), 0)
        local controlW = pixelValue(methods.numericVariable(slotPrefix .. '_ControlW', 0), 0)
        local controlH = pixelValue(methods.numericVariable(slotPrefix .. '_ControlH', methods.numericVariable('SettingsTall1H', 40)), 40)
        local textPad = pixelValue(methods.numericVariable('SlotSettingsRowText_ContentPad', methods.numericVariable('SettingsInnerPad', 10)), 10)
        local dropdownW = pixelValue(methods.numericVariable('SettingsDropdownButtonW', 24), 24)
        local toggleSize = pixelValue(methods.numericVariable('SlotSettingsRowToggle_Size', methods.numericVariable('SettingsToggleButtonSize', 28)), 28)
        local toggleInset = pixelValue(methods.numericVariable('SlotSettingsRowToggle_FillInset', methods.numericVariable('SettingsToggleFillInset', 7)), 7)
        local stepperFieldW = pixelValue(methods.numericVariable('SlotSettingsRowStepperFieldW', methods.numericVariable('SettingsStepperFieldW', 0)), 0)
        local stepperButtonGap = pixelValue(methods.numericVariable('SlotSettingsRowStepperButtonGap', 4), 4)
        local stepperButtonW = pixelValue(methods.numericVariable('SlotSettingsRowStepperButtonW', methods.numericVariable('SettingsStepperButtonW', 24)), 24)
        local actionButtonW = pixelValue(methods.numericVariable('SlotSettingsRowActionButtonW', methods.numericVariable('SettingsActionButtonW', 110)), 110)

        local dropdownX = controlX + controlW - dropdownW
        local toggleX = controlX + controlW - toggleSize
        local toggleY = controlY + pixelValue((controlH - toggleSize) / 2, 0)
        local stepperMinusX = controlX + stepperFieldW + stepperButtonGap
        local stepperPlusX = stepperMinusX + stepperButtonW + stepperButtonGap
        local actionX = controlX + controlW - actionButtonW

        setVariable(prefix .. '_LabelX', tostring(labelX))
        setVariable(prefix .. '_LabelY', tostring(labelY))
        setVariable(prefix .. '_LabelW', tostring(labelW))
        setVariable(prefix .. '_LabelH', tostring(labelH))
        setVariable(prefix .. '_Field_X', tostring(controlX))
        setVariable(prefix .. '_Field_Y', tostring(controlY))
        setVariable(prefix .. '_Field_W', tostring(controlW))
        setVariable(prefix .. '_Field_H', tostring(controlH))
        setVariable(prefix .. '_FieldContentX', tostring(controlX + textPad))
        setVariable(prefix .. '_FieldContentY', tostring(controlY + textPad))
        setVariable(prefix .. '_FieldContentW', tostring(math.max(0, controlW - (2 * textPad))))
        setVariable(prefix .. '_FieldContentH', tostring(math.max(0, controlH - (2 * textPad))))
        setVariable(prefix .. '_DropdownButton_X', tostring(dropdownX))
        setVariable(prefix .. '_DropdownButton_Y', tostring(controlY))
        setVariable(prefix .. '_DropdownButton_W', tostring(dropdownW))
        setVariable(prefix .. '_DropdownButton_H', tostring(controlH))
        setVariable(prefix .. '_DropdownButton_LabelX', tostring(dropdownX + pixelValue(dropdownW / 2, 0)))
        setVariable(prefix .. '_DropdownButton_LabelY', tostring(controlY + pixelValue(controlH / 2, 0)))
        setVariable(prefix .. '_Toggle_X', tostring(toggleX))
        setVariable(prefix .. '_Toggle_Y', tostring(toggleY))
        setVariable(prefix .. '_Toggle_W', tostring(toggleSize))
        setVariable(prefix .. '_Toggle_H', tostring(toggleSize))
        setVariable(prefix .. '_ToggleFill_X', tostring(toggleX + toggleInset))
        setVariable(prefix .. '_ToggleFill_Y', tostring(toggleY + toggleInset))
        setVariable(prefix .. '_ToggleFill_W', tostring(math.max(0, toggleSize - (2 * toggleInset))))
        setVariable(prefix .. '_ToggleFill_H', tostring(math.max(0, toggleSize - (2 * toggleInset))))
        setVariable(prefix .. '_StepperField_X', tostring(controlX))
        setVariable(prefix .. '_StepperField_Y', tostring(controlY))
        setVariable(prefix .. '_StepperField_W', tostring(stepperFieldW))
        setVariable(prefix .. '_StepperField_H', tostring(controlH))
        setVariable(prefix .. '_StepperMinus_X', tostring(stepperMinusX))
        setVariable(prefix .. '_StepperMinus_Y', tostring(controlY))
        setVariable(prefix .. '_StepperMinus_W', tostring(stepperButtonW))
        setVariable(prefix .. '_StepperMinus_H', tostring(controlH))
        setVariable(prefix .. '_StepperMinus_LabelX', tostring(stepperMinusX + pixelValue(stepperButtonW / 2, 0)))
        setVariable(prefix .. '_StepperMinus_LabelY', tostring(controlY + pixelValue(controlH / 2, 0)))
        setVariable(prefix .. '_StepperPlus_X', tostring(stepperPlusX))
        setVariable(prefix .. '_StepperPlus_Y', tostring(controlY))
        setVariable(prefix .. '_StepperPlus_W', tostring(stepperButtonW))
        setVariable(prefix .. '_StepperPlus_H', tostring(controlH))
        setVariable(prefix .. '_StepperPlus_LabelX', tostring(stepperPlusX + pixelValue(stepperButtonW / 2, 0)))
        setVariable(prefix .. '_StepperPlus_LabelY', tostring(controlY + pixelValue(controlH / 2, 0)))
        setVariable(prefix .. '_Action_X', tostring(actionX))
        setVariable(prefix .. '_Action_Y', tostring(controlY))
        setVariable(prefix .. '_Action_W', tostring(actionButtonW))
        setVariable(prefix .. '_Action_H', tostring(controlH))
        setVariable(prefix .. '_Action_LabelX', tostring(actionX + pixelValue(actionButtonW / 2, 0)))
        setVariable(prefix .. '_Action_LabelY', tostring(controlY + pixelValue(controlH / 2, 0)))
        setVariable(prefix .. '_ActionSecondary_X', tostring(actionX))
        setVariable(prefix .. '_ActionSecondary_Y', tostring(controlY))
        setVariable(prefix .. '_ActionSecondary_W', tostring(actionButtonW))
        setVariable(prefix .. '_ActionSecondary_H', tostring(controlH))
        setVariable(prefix .. '_ActionSecondary_LabelX', tostring(actionX + pixelValue(actionButtonW / 2, 0)))
        setVariable(prefix .. '_ActionSecondary_LabelY', tostring(controlY + pixelValue(controlH / 2, 0)))

    end

    function methods.syncTextFieldGeometry(rowIndex, field)

        methods.resetRowBaseGeometry(rowIndex)

        local contentX = methods.numericVariable('SettingsContentX', methods.numericVariable('SettingsRowLabelX', 0)) or 0

        local contentW = methods.numericVariable('SettingsContentW', 0) or 0

        local controlGap = methods.numericVariable('SettingsRowControlGap', 12) or 12

        local labelW = methods.numericVariable('SettingsRowLabelW', 0) or 0

        if field and field.wideTextField then

            labelW = tonumber(field.wideTextFieldLabelW) or 96

        end

        labelW = pixelValue(labelW, 0)

        local controlX = contentX + labelW + controlGap

        local controlW = math.max(0, contentW - controlGap - labelW)

        local fieldX = controlX

        local fieldRatio = tonumber(field and field.textFieldRatio)

        local fieldY = pixelValue(methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_Y', 0), 0)

        local fieldH = pixelValue(methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_H', methods.numericVariable('SettingsTall1H', 40)), 40)

        local contentPad = pixelValue(methods.numericVariable('SlotSettingsRowText_ContentPad', methods.numericVariable('SettingsInnerPad', 10)), 10)

        local buttonW = pixelValue(methods.numericVariable('SettingsDropdownButtonW', 24), 24)

        local buttonGap = pixelValue(methods.numericVariable('SettingsDropdownButtonGap', 4), 4)

        local dropdownControlW = pixelValue(methods.numericVariable('SettingsDropdownControlW', methods.numericVariable('SettingsRowControlW', 0)), 0)

        local fieldW = controlW

        if fieldRatio ~= nil then

            if fieldRatio < 0 then

                fieldRatio = 0

            elseif fieldRatio > 1 then

                fieldRatio = 1

            end

            fieldW = math.floor((controlW * fieldRatio) + 0.5)

            fieldX = controlX + controlW - fieldW

        end

        setVariable('SettingsRow' .. rowIndex .. '_LabelW', tostring(labelW))

        setVariable('SettingsRow' .. rowIndex .. '_Field_X', tostring(fieldX))

        if methods.hasDropdown(field) then

            dropdownControlW = pixelValue(math.max(0, math.min(controlW, dropdownControlW)), 0)

            fieldX = pixelValue(controlX + controlW - dropdownControlW, 0)

            setVariable('SettingsRow' .. rowIndex .. '_Field_X', tostring(fieldX))

            local buttonX = fieldX + dropdownControlW - buttonW

            fieldW = pixelValue(math.max(0, dropdownControlW - buttonW - buttonGap), 0)

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButton_X', tostring(buttonX))

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButton_Y', tostring(fieldY))

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButton_W', tostring(buttonW))

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButton_H', tostring(fieldH))

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButton_LabelX', tostring(buttonX + (buttonW / 2)))

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButton_LabelY', tostring(fieldY + (fieldH / 2)))

        end

        local contentFieldW = math.max(0, fieldW - (2 * contentPad))

        local contentH = math.max(0, fieldH - (2 * contentPad))

        setVariable('SettingsRow' .. rowIndex .. '_Field_W', tostring(fieldW))

        setVariable('SettingsRow' .. rowIndex .. '_FieldContentX', tostring(fieldX + contentPad))

        setVariable('SettingsRow' .. rowIndex .. '_FieldContentY', tostring(fieldY + contentPad))

        setVariable('SettingsRow' .. rowIndex .. '_FieldContentW', tostring(contentFieldW))

        setVariable('SettingsRow' .. rowIndex .. '_FieldContentH', tostring(contentH))

    end

    function methods.setRowHidden(rowIndex, hidden)

        methods.resetRowBaseGeometry(rowIndex)

        local hiddenValue = hidden and '1' or '0'

        setVariable('SettingsRow' .. rowIndex .. '_Hidden', hiddenValue)

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', hiddenValue)

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', hiddenValue)

        setVariable('SettingsRow' .. rowIndex .. '_FieldText', '')

        setVariable('SettingsRow' .. rowIndex .. '_FieldCommand', '')

        setVariable('SettingsRow' .. rowIndex .. '_Field_W', SKIN:GetVariable('SlotSettingsRow' .. rowIndex .. '_ControlW', '0'))

        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', dropdownClosedText(rowIndex))

        setVariable('SettingsRow' .. rowIndex .. '_ToggleHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_ToggleCommand', '')

        setVariable('SettingsRow' .. rowIndex .. '_ToggleFillColor', SKIN:GetVariable('SettingsToggleFillOffColor', '0,0,0,0'))
        setVariable('SettingsRow' .. rowIndex .. '_ToggleBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))

        setVariable('SettingsRow' .. rowIndex .. '_StepperHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_StepperFieldText', '')

        setVariable('SettingsRow' .. rowIndex .. '_StepperFieldCommand', '')

        setVariable('SettingsRow' .. rowIndex .. '_StepperMinusCommand', '')

        setVariable('SettingsRow' .. rowIndex .. '_StepperPlusCommand', '')

        setVariable('SettingsRow' .. rowIndex .. '_ActionHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_ActionText', '')

        setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', '')

        state.currentRowActionByIndex[rowIndex] = nil

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryHidden', '1')
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', '')
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', '')

        state.currentRowSecondaryActionByIndex[rowIndex] = nil

        setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))

        setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
        setVariable('SettingsRow' .. rowIndex .. '_LabelTextColor', SKIN:GetVariable('SettingsInputTextColor', ''))

        setVariable('SettingsRow' .. rowIndex .. '_LabelText', '')

        setVariable('SettingsRow' .. rowIndex .. '_Tooltip', '')

        state.currentFieldKeyByRow[rowIndex] = nil

    end
end
