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
    local applyTextFit = helpers.applyTextFit

    local function applyRowLabelFit(rowIndex, field, text)
        if not applyTextFit then
            return
        end
        local width = methods.numericVariable('SettingsRow' .. rowIndex .. '_LabelW', methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_LabelW', 0)) or 0
        local height = methods.numericVariable('SettingsRow' .. rowIndex .. '_LabelH', methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_LabelH', 0)) or 0
        applyTextFit('MeterSettingsRow' .. tostring(rowIndex) .. 'Label', text, 'SettingsLabelFontSize', math.max(0, width - 4), height, 'wrap4')
    end

    local function applyRowFieldFit(rowIndex, text)
        if not applyTextFit then
            return
        end
        local width = methods.numericVariable('SettingsRow' .. rowIndex .. '_FieldContentW', methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_W', 0)) or 0
        local height = methods.numericVariable('SettingsRow' .. rowIndex .. '_FieldContentH', methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_H', 0)) or 0
        applyTextFit('MeterSettingsRow' .. tostring(rowIndex) .. 'FieldText', text, 'SettingsUIFontSize', width, height, 'single-line')
    end

    local function applyRowActionFit(rowIndex, field, text, secondary)
        if not applyTextFit then
            return
        end
        local suffix = secondary and 'ActionSecondary' or 'Action'
        local meterSuffix = secondary and 'ActionSecondaryLabel' or 'ActionLabel'
        local width = methods.numericVariable('SettingsRow' .. rowIndex .. '_' .. suffix .. '_W', 0) or 0
        local height = methods.numericVariable('SettingsRow' .. rowIndex .. '_' .. suffix .. '_H', 0) or 0
        local pad = methods.numericVariable('SlotSettingsRowText_ContentPad', methods.numericVariable('SettingsInnerPad', 10)) or 10
        applyTextFit('MeterSettingsRow' .. tostring(rowIndex) .. meterSuffix, text, 'SettingsUIFontSize', math.max(0, width - (2 * pad)), height, 'wrap4')
    end

    function methods.configureTextRow(rowIndex, field, isDisabled)

        local displayValue = methods.displayValueForField(field, methods.readFieldValue(field))

        if displayValue == '' then

            displayValue = methods.localize('Settings_EmptyValue', '빈 값')

        end

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '0')

        setVariable('SettingsRow' .. rowIndex .. '_FieldText', displayValue)

        local fieldCommand = '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "PrepareTextField(\'' .. field.key .. '\')"][!CommandMeasure MeasureSettingsCommit "OpenPreparedTextField()"]'
        if field.controlType == 'multiDropdown' then
            fieldCommand = '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ToggleVisibleRowDropdown(' .. tostring(rowIndex) .. ')"]'
        end
        setVariable('SettingsRow' .. rowIndex .. '_FieldCommand', isDisabled and '' or fieldCommand)

        local dropdownCommand = ''
        if methods.hasDropdown(field) and not isDisabled then
            dropdownCommand = '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ToggleVisibleRowDropdown(' .. tostring(rowIndex) .. ')"]'
        end
        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonCommand', dropdownCommand)

        methods.syncTextFieldGeometry(rowIndex, field)
        applyRowFieldFit(rowIndex, displayValue)

        local inlineActionFieldKey = trim(field and field.inlineActionFieldKey or '')

        if inlineActionFieldKey ~= '' then

            local inlineActionField = methods.getField(inlineActionFieldKey)

            if inlineActionField then

                local inlineDisabled = isDisabled or (methods.isFieldDisabled and methods.isFieldDisabled(inlineActionField))

                local contentX = methods.numericVariable('SettingsContentX', methods.numericVariable('SettingsRowLabelX', 0)) or 0

                local contentW = methods.numericVariable('SettingsContentW', 0) or 0

                local controlGap = methods.numericVariable('SettingsRowControlGap', 12) or 12

                local baseLabelW = methods.numericVariable('SettingsRowBaseLabelW', methods.numericVariable('SettingsRowLabelW', 0)) or 0

                local labelW = methods.numericVariable('SettingsRow' .. rowIndex .. '_LabelW', baseLabelW) or baseLabelW

                local controlX = contentX + labelW + controlGap

                local controlY = methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_Y', methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', 0)) or 0

                local controlW = math.max(0, contentW - controlGap - labelW)

                local controlH = methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_H', methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', methods.numericVariable('SettingsTall1H', 40))) or 40

                local contentPad = methods.numericVariable('SlotSettingsRowText_ContentPad', methods.numericVariable('SettingsInnerPad', 10)) or 10

                local actionGap = methods.numericVariable('SettingsDropdownButtonGap', 4) or 4

                local dropdownButtonW = methods.numericVariable('SettingsDropdownButtonW', 24) or 24

                local dropdownButtonGap = methods.numericVariable('SettingsDropdownButtonGap', 4) or 4

                local actionW = tonumber(field.inlineActionButtonW) or 0

                local defaultActionW = math.floor(((methods.numericVariable('SettingsActionButtonW', 110) or 110) / 2) + 0.5)

                local fieldRatio = tonumber(field.inlineTextFieldRatio) or 0.7

                if actionW <= 0 then

                    actionW = defaultActionW

                end

                actionW = math.max(48, math.min(controlW, actionW))

                if fieldRatio < 0 then

                    fieldRatio = 0

                elseif fieldRatio > 1 then

                    fieldRatio = 1

                end

                local fontLikeFieldW = math.max(0, controlW - dropdownButtonW - dropdownButtonGap)

                local requestedFieldW = math.floor((fontLikeFieldW * fieldRatio) + 0.5)

                local maxFieldW = math.max(0, controlW - actionW - actionGap)

                local inlineFieldW = math.max(0, math.min(maxFieldW, requestedFieldW))

                local actionX = controlX + controlW - actionW

                local fieldX = actionX - actionGap - inlineFieldW

                setVariable('SettingsRow' .. rowIndex .. '_LabelW', tostring(labelW))

                setVariable('SettingsRow' .. rowIndex .. '_Field_X', tostring(fieldX))

                setVariable('SettingsRow' .. rowIndex .. '_Field_W', tostring(inlineFieldW))

                setVariable('SettingsRow' .. rowIndex .. '_FieldContentX', tostring(fieldX + contentPad))

                setVariable('SettingsRow' .. rowIndex .. '_FieldContentW', tostring(math.max(0, inlineFieldW - (2 * contentPad))))

                setVariable('SettingsRow' .. rowIndex .. '_ActionHidden', actionW > 0 and '0' or '1')

                setVariable('SettingsRow' .. rowIndex .. '_Action_X', tostring(actionX))

                setVariable('SettingsRow' .. rowIndex .. '_Action_Y', tostring(controlY))

                setVariable('SettingsRow' .. rowIndex .. '_Action_W', tostring(actionW))

                setVariable('SettingsRow' .. rowIndex .. '_Action_H', tostring(controlH))

                setVariable('SettingsRow' .. rowIndex .. '_Action_LabelX', tostring(actionX + (actionW / 2)))

                setVariable('SettingsRow' .. rowIndex .. '_Action_LabelY', tostring(controlY + (controlH / 2)))

                local inlineActionText = methods.fieldActionText(inlineActionField, trim(field.inlineActionText or inlineActionField.defaultActionText or ''))
                setVariable('SettingsRow' .. rowIndex .. '_ActionText', inlineActionText)
                applyRowActionFit(rowIndex, inlineActionField, inlineActionText, false)

                setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', inlineDisabled and '' or string.format("[!CommandMeasure MeasureSettingsCommit \"PlayUiClick()\"][!CommandMeasure MeasureSettingsCommit \"ExecuteFieldAction('%s')\"]", inlineActionField.key))

                state.currentRowActionByIndex[rowIndex] = inlineDisabled and nil or { kind = 'executeFieldAction', fieldKey = inlineActionField.key }

                setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', inlineDisabled and SKIN:GetVariable('SettingsButtonDisabledBgColor', '') or SKIN:GetVariable('SettingsButtonBgColor', ''))

                setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', inlineDisabled and SKIN:GetVariable('SettingsButtonDisabledTextColor', '') or SKIN:GetVariable('SettingsButtonTextColor', ''))

                setVariable('SettingsRow' .. rowIndex .. '_ActionCursor', inlineDisabled and '0' or '1')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryHidden', '1')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', '')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', '')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCursor', '0')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))

            end

        end

        if methods.hasDropdown(field) then

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '0')

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', state.activeDropdownFieldKey == field.key and dropdownOpenText() or dropdownClosedText(rowIndex))

        else

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '1')

            setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', dropdownClosedText(rowIndex))

        end

    end
    function methods.formatDurationSeconds(value)
        local totalSeconds = math.max(0, math.floor(tonumber(value) or 0))
        local hours = math.floor(totalSeconds / 3600)
        local minutes = math.floor((totalSeconds % 3600) / 60)
        local seconds = totalSeconds % 60
        local template = trim(methods.localize('Settings_DurationFormat', '%1 h %2 min %3 sec'))
        if template == '' then
            template = '%1 h %2 min %3 sec'
        end
        template = template:gsub('%%1', tostring(hours))
        template = template:gsub('%%2', tostring(minutes))
        template = template:gsub('%%3', tostring(seconds))
        return template
    end

    function methods.configureReadonlyRow(rowIndex, field)

        local displayValue = ''
        local displayVariable = trim(field and field.displayVariable or '')

        if displayVariable ~= '' then

            displayValue = trim(SKIN:GetVariable(displayVariable, field.displayFallback or ''))

        elseif field and field.key == 'appVersion' then

            displayValue = methods.appVersionDisplayValue()

        end

        if displayValue == '' then

            displayValue = trim(field and field.displayFallback or '')

        end

        if displayValue == '' and field and field.key == 'appVersion' then

            displayValue = 'v?'

        end

        if trim(field and field.displayFormatter or '') == 'durationSeconds' then
            displayValue = methods.formatDurationSeconds(displayValue)
        end

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '0')

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_FieldText', displayValue)

        setVariable('SettingsRow' .. rowIndex .. '_FieldCommand', '')

        methods.syncTextFieldGeometry(rowIndex, field)
        applyRowFieldFit(rowIndex, displayValue)

        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', dropdownClosedText(rowIndex))

    end

    function methods.configureToggleRow(rowIndex, field, isDisabled)

        local semanticOn = methods.toggleSemanticValue(field, methods.readFieldValue(field))

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_ToggleHidden', '0')

        local toggleFillColor = SKIN:GetVariable('SettingsToggleFillOffColor', '0,0,0,0')
        if semanticOn then
            toggleFillColor = isDisabled and SKIN:GetVariable('SettingsButtonDisabledTextColor', '') or SKIN:GetVariable('SettingsToggleFillOnColor', '')
        end
        setVariable('SettingsRow' .. rowIndex .. '_ToggleFillColor', toggleFillColor)

        setVariable('SettingsRow' .. rowIndex .. '_ToggleCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ToggleField(\'' .. field.key .. '\')"]')

        local inlineFieldKey = trim(field.inlineToggleFieldKey or '')
        local inlineField = inlineFieldKey ~= '' and methods.getField(inlineFieldKey) or nil
        if inlineField then
            local toggleX = methods.numericVariable('SettingsRow' .. rowIndex .. '_Toggle_X', 0) or 0
            local controlY = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', 0) or 0
            local controlH = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', methods.numericVariable('SettingsTall1H', 40)) or 40
            local actionW = pixelValue(tonumber(field.inlineToggleButtonWidth or 120) or 120, 120)
            local actionGap = pixelValue(methods.numericVariable('SettingsDropdownButtonGap', 4), 4)
            local actionX = toggleX - actionGap - actionW
            local inlineDisabled = isDisabled or (methods.isFieldDisabled and methods.isFieldDisabled(inlineField))
            local inlineOn = not inlineDisabled and methods.toggleSemanticValue(inlineField, methods.readFieldValue(inlineField))
            local actionText = methods.fieldActionText(inlineField, trim(inlineField.defaultActionText or inlineField.label or ''))

            setVariable('SettingsRow' .. rowIndex .. '_ActionHidden', '0')
            setVariable('SettingsRow' .. rowIndex .. '_Action_X', tostring(actionX))
            setVariable('SettingsRow' .. rowIndex .. '_Action_Y', tostring(controlY))
            setVariable('SettingsRow' .. rowIndex .. '_Action_W', tostring(actionW))
            setVariable('SettingsRow' .. rowIndex .. '_Action_H', tostring(controlH))
            setVariable('SettingsRow' .. rowIndex .. '_Action_LabelX', tostring(actionX + (actionW / 2)))
            setVariable('SettingsRow' .. rowIndex .. '_Action_LabelY', tostring(controlY + (controlH / 2)))
            setVariable('SettingsRow' .. rowIndex .. '_ActionText', actionText)
            setVariable('SettingsRow' .. rowIndex .. '_ActionTooltip', methods.tooltipTextForField(inlineField))
            setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', inlineDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ExecuteVisibleRowAction(' .. tostring(rowIndex) .. ')"]')
            setVariable('SettingsRow' .. rowIndex .. '_ActionCursor', inlineDisabled and '0' or '1')
            setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', inlineDisabled
                and SKIN:GetVariable('SettingsButtonDisabledBgColor', '')
                or (inlineOn and SKIN:GetVariable('SettingsPalette6', SKIN:GetVariable('SettingsButtonBgColor', ''))
                    or SKIN:GetVariable('SettingsButtonBgColor', '')))
            setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', inlineDisabled
                and SKIN:GetVariable('SettingsButtonDisabledTextColor', '')
                or (inlineOn and SKIN:GetVariable('SettingsTabActiveTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
                    or SKIN:GetVariable('SettingsButtonTextColor', '')))
            applyRowActionFit(rowIndex, inlineField, actionText, false)
            state.currentRowActionByIndex[rowIndex] = inlineDisabled and nil or { kind = 'toggleField', fieldKey = inlineField.key }
        end

    end

    function methods.configureSegmentedRow(rowIndex, field, isDisabled)

        local options = field.segmentedOptions or {}
        local primary = options[1] or { value = '', fallback = '' }
        local secondary = options[2] or { value = '', fallback = '' }
        local currentValue = methods.normalizeFieldValue(field, methods.readFieldValue(field), 'wide')
        local primaryValue = methods.normalizeFieldValue(field, primary.value or '', 'wide')
        local secondaryValue = methods.normalizeFieldValue(field, secondary.value or '', 'wide')
        local primarySelected = currentValue == primaryValue
        local secondarySelected = currentValue == secondaryValue

        local controlX = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlX', 0) or 0
        local controlY = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', 0) or 0
        local controlW = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlW', 0) or 0
        local controlH = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', methods.numericVariable('SettingsTall1H', 40)) or 40
        local controlScale = tonumber(field.segmentedControlScale or 1) or 1
        if controlScale > 1 and controlW > 0 then
            local contentX = pixelValue(methods.numericVariable('SettingsContentX', methods.numericVariable('SettingsRowLabelX', 0)), 0)
            local contentW = pixelValue(methods.numericVariable('SettingsContentW', 0), 0)
            local contentRight = contentW > 0 and (contentX + contentW) or (controlX + controlW)
            local controlRight = math.min(controlX + controlW, contentRight)
            local desiredW = pixelValue(controlW * controlScale, controlW)
            controlW = math.min(math.max(controlW, desiredW), math.max(controlW, contentRight - contentX))
            controlX = pixelValue(math.max(contentX, controlRight - controlW), 0)

            local labelGap = pixelValue(methods.numericVariable('SettingsRowControlGap', 12), 12)
            local labelX = pixelValue(methods.numericVariable('SettingsRowLabelX', contentX), contentX)
            setVariable('SettingsRow' .. rowIndex .. '_LabelW', tostring(math.max(0, controlX - labelGap - labelX)))
        end
        local splitGap = pixelValue(methods.numericVariable('SettingsDropdownButtonGap', 4), 4)
        local primaryW = math.max(0, pixelValue((controlW - splitGap) / 2, 0))
        local secondaryW = math.max(0, controlW - splitGap - primaryW)
        local secondaryX = controlX + primaryW + splitGap
        local labelY = controlY + (controlH / 2)

        local function optionLabel(option)
            local key = trim(option and option.labelKey or '')
            local fallback = trim(option and (option.fallback or option.label or option.value) or '')
            if key ~= '' then
                return trim(methods.localize(key, fallback))
            end
            return fallback
        end

        local function optionBgColor(selected)
            if isDisabled then
                return SKIN:GetVariable('SettingsButtonDisabledBgColor', '')
            end
            if selected then
                return SKIN:GetVariable('SettingsPalette6', SKIN:GetVariable('SettingsButtonBgColor', ''))
            end
            return SKIN:GetVariable('SettingsButtonBgColor', '')
        end

        local function optionTextColor(selected)
            if isDisabled then
                return SKIN:GetVariable('SettingsButtonDisabledTextColor', '')
            end
            if selected then
                return SKIN:GetVariable('SettingsTabActiveTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
            end
            return SKIN:GetVariable('SettingsButtonTextColor', '')
        end

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '1')
        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')
        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '1')
        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', dropdownClosedText(rowIndex))
        setVariable('SettingsRow' .. rowIndex .. '_ActionHidden', '0')
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryHidden', '0')

        setVariable('SettingsRow' .. rowIndex .. '_Action_X', tostring(controlX))
        setVariable('SettingsRow' .. rowIndex .. '_Action_Y', tostring(controlY))
        setVariable('SettingsRow' .. rowIndex .. '_Action_W', tostring(primaryW))
        setVariable('SettingsRow' .. rowIndex .. '_Action_H', tostring(controlH))
        setVariable('SettingsRow' .. rowIndex .. '_Action_LabelX', tostring(controlX + (primaryW / 2)))
        setVariable('SettingsRow' .. rowIndex .. '_Action_LabelY', tostring(labelY))
        local primaryText = optionLabel(primary)
        setVariable('SettingsRow' .. rowIndex .. '_ActionText', primaryText)
        setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ExecuteVisibleRowAction(' .. tostring(rowIndex) .. ')"]')
        setVariable('SettingsRow' .. rowIndex .. '_ActionCursor', isDisabled and '0' or '1')
        setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', optionBgColor(primarySelected))
        setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', optionTextColor(primarySelected))
        applyRowActionFit(rowIndex, field, primaryText, false)

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_X', tostring(secondaryX))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_Y', tostring(controlY))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_W', tostring(secondaryW))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_H', tostring(controlH))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelX', tostring(secondaryX + (secondaryW / 2)))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelY', tostring(labelY))
        local secondaryText = optionLabel(secondary)
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', secondaryText)
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ExecuteVisibleRowSecondaryAction(' .. tostring(rowIndex) .. ')"]')
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCursor', isDisabled and '0' or '1')
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', optionBgColor(secondarySelected))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', optionTextColor(secondarySelected))
        applyRowActionFit(rowIndex, field, secondaryText, true)

        state.currentRowActionByIndex[rowIndex] = isDisabled and nil or { kind = 'selectSegmentedOption', fieldKey = field.key, value = primaryValue }
        state.currentRowSecondaryActionByIndex[rowIndex] = isDisabled and nil or { kind = 'selectSegmentedOption', fieldKey = field.key, value = secondaryValue }

    end

    function methods.configureStepperRow(rowIndex, field, isDisabled)

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_StepperHidden', '0')

        setVariable('SettingsRow' .. rowIndex .. '_StepperFieldText', methods.readFieldValue(field))

        setVariable('SettingsRow' .. rowIndex .. '_StepperFieldCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "PrepareTextField(\'' .. field.key .. '\')"][!CommandMeasure MeasureSettingsCommit "OpenPreparedTextField()"]')

        setVariable('SettingsRow' .. rowIndex .. '_StepperMinusCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "StepFieldDown(\'' .. field.key .. '\')"]')

        setVariable('SettingsRow' .. rowIndex .. '_StepperPlusCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "StepFieldUp(\'' .. field.key .. '\')"]')

    end

    function methods.configureActionRow(rowIndex, field, isDisabled)

        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_ActionHidden', '0')

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', '')

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', '')

        state.currentRowSecondaryActionByIndex[rowIndex] = nil

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))

        local controlX = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlX', 0) or 0

        local controlY = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', 0) or 0

        local controlW = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlW', 0) or 0

        local controlH = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', methods.numericVariable('SettingsTall1H', 40)) or 40

        local actionStatusKind = trim(field and field.actionStatusKind or '')
        if actionStatusKind ~= '' then
            local contentX = methods.numericVariable('SettingsContentX', 0) or 0
            local contentW = methods.numericVariable('SettingsContentW', 0) or 0
            local baseLabelW = methods.numericVariable('SettingsRowBaseLabelW', methods.numericVariable('SettingsRowLabelW', 0)) or 0
            local controlGap = methods.numericVariable('SettingsRowControlGap', 12) or 12
            controlX = contentX + baseLabelW + controlGap
            controlW = math.max(0, contentW - baseLabelW - controlGap)
            setVariable('SettingsRow' .. rowIndex .. '_LabelW', tostring(baseLabelW))
        end

        local actionButtonW = methods.numericVariable('SlotSettingsRowActionButtonW', methods.numericVariable('SettingsActionButtonW', controlW)) or controlW
        local actionButtonWidthScale = tonumber(field and field.actionButtonWidthScale or 1) or 1
        actionButtonW = math.max(0, actionButtonW * actionButtonWidthScale)

        local actionX = controlX + controlW - actionButtonW

        local actionLabelX = actionX + (actionButtonW / 2)

        local actionLabelY = controlY + (controlH / 2)

        setVariable('SettingsRow' .. rowIndex .. '_Action_X', tostring(actionX))

        setVariable('SettingsRow' .. rowIndex .. '_Action_Y', tostring(controlY))

        setVariable('SettingsRow' .. rowIndex .. '_Action_W', tostring(actionButtonW))

        setVariable('SettingsRow' .. rowIndex .. '_Action_H', tostring(controlH))

        setVariable('SettingsRow' .. rowIndex .. '_Action_LabelX', tostring(actionLabelX))

        setVariable('SettingsRow' .. rowIndex .. '_Action_LabelY', tostring(actionLabelY))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_X', tostring(actionX))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_Y', tostring(controlY))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_W', tostring(actionButtonW))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_H', tostring(controlH))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelX', tostring(actionLabelX))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelY', tostring(actionLabelY))

        if actionStatusKind == 'minecraftSkinPlayerFolderSize' then
            local statusGap = 5
            local statusW = math.max(0, actionX - statusGap - controlX)
            local statusText = methods.minecraftSkinPlayerFolderSizeDisplayText
                and methods.minecraftSkinPlayerFolderSizeDisplayText()
                or 'Occupied space: 0.0MB'
            local statusTooltip = methods.minecraftSkinPlayerFolderSizeTooltipText
                and methods.minecraftSkinPlayerFolderSizeTooltipText()
                or ''
            setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', statusW > 0 and '0' or '1')
            setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')
            setVariable('SettingsRow' .. rowIndex .. '_Field_X', tostring(controlX))
            setVariable('SettingsRow' .. rowIndex .. '_Field_Y', tostring(controlY))
            setVariable('SettingsRow' .. rowIndex .. '_Field_W', tostring(statusW))
            setVariable('SettingsRow' .. rowIndex .. '_Field_H', tostring(controlH))
            setVariable('SettingsRow' .. rowIndex .. '_FieldContentX', tostring(actionX - statusGap))
            setVariable('SettingsRow' .. rowIndex .. '_FieldContentY', tostring(controlY))
            setVariable('SettingsRow' .. rowIndex .. '_FieldContentW', tostring(statusW))
            setVariable('SettingsRow' .. rowIndex .. '_FieldContentH', tostring(controlH))
            setVariable('SettingsRow' .. rowIndex .. '_FieldText', statusText)
            setVariable('SettingsRow' .. rowIndex .. '_FieldTextAlign', 'RightCenter')
            setVariable('SettingsRow' .. rowIndex .. '_FieldCommand', '')
            setVariable('SettingsRow' .. rowIndex .. '_Tooltip', statusTooltip)
            applyRowFieldFit(rowIndex, statusText)
        end

        local labelText = methods.fieldLabelText(field)

        local actionText = methods.fieldActionText(field)

        local actionCommand = string.format("[!CommandMeasure MeasureSettingsCommit \"PlayUiClick()\"][!CommandMeasure MeasureSettingsCommit \"ExecuteFieldAction('%s')\"]", field.key)

        local secondaryActionEnabled = false

        local actionBgColor = SKIN:GetVariable('SettingsButtonBgColor', '')

        local actionTextColor = SKIN:GetVariable('SettingsButtonTextColor', '')

        if field.actionStyle == 'danger' then

            actionBgColor = SKIN:GetVariable('SettingsDangerButtonBgColor', '')

            actionTextColor = SKIN:GetVariable('SettingsDangerButtonTextColor', '')

        end

        if field.key == 'settingsTheme' then

            actionText = methods.themeDisplayText()

        elseif methods.isPendingConfirmAction(field.key) then

            local confirmControlX = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlX', methods.numericVariable('SettingsRow' .. rowIndex .. '_Action_X', 0)) or 0

            local confirmControlY = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', methods.numericVariable('SettingsRow' .. rowIndex .. '_Action_Y', 0)) or 0

            local confirmControlW = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlW', methods.numericVariable('SettingsRow' .. rowIndex .. '_Action_W', 0)) or 0

            local confirmControlH = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', methods.numericVariable('SettingsRow' .. rowIndex .. '_Action_H', 0)) or 0

            local splitGap = methods.numericVariable('SettingsGridGap', 8) or 8

            local splitW = math.max(0, (confirmControlW - splitGap) / 2)

            local secondaryX = confirmControlX + splitW + splitGap

            actionText = methods.localize('Settings_Confirm_Cancel', methods.localize('Common_Cancel', '취소'))

            actionCommand = '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "CancelPendingConfirmation()"]'

            state.currentRowActionByIndex[rowIndex] = { kind = 'cancelPendingConfirmation' }

            actionBgColor = SKIN:GetVariable('SettingsButtonBgColor', '')

            actionTextColor = SKIN:GetVariable('SettingsButtonTextColor', '')

            setVariable('SettingsRow' .. rowIndex .. '_Action_X', tostring(confirmControlX))

            setVariable('SettingsRow' .. rowIndex .. '_Action_Y', tostring(confirmControlY))

            setVariable('SettingsRow' .. rowIndex .. '_Action_W', tostring(splitW))

            setVariable('SettingsRow' .. rowIndex .. '_Action_H', tostring(confirmControlH))

            setVariable('SettingsRow' .. rowIndex .. '_Action_LabelX', tostring(confirmControlX + (splitW / 2)))

            setVariable('SettingsRow' .. rowIndex .. '_Action_LabelY', tostring(confirmControlY + (confirmControlH / 2)))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryHidden', '0')

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_X', tostring(secondaryX))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_Y', tostring(confirmControlY))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_W', tostring(splitW))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_H', tostring(confirmControlH))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelX', tostring(secondaryX + (splitW / 2)))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelY', tostring(confirmControlY + (confirmControlH / 2)))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', methods.localize('Settings_Confirm_Confirm', methods.localize('Common_Confirm', '확정')))

            applyRowActionFit(rowIndex, field, SKIN:GetVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', ''), true)

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', string.format("[!CommandMeasure MeasureSettingsCommit \"PlayUiClick()\"][!CommandMeasure MeasureSettingsCommit \"ExecuteFieldAction('%s')\"]", field.key))

            secondaryActionEnabled = true

            state.currentRowSecondaryActionByIndex[rowIndex] = { kind = 'executeFieldAction', fieldKey = field.key }

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', SKIN:GetVariable('SettingsDangerButtonBgColor', ''))

            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', SKIN:GetVariable('SettingsDangerButtonTextColor', ''))

        end

        if isDisabled then
            actionCommand = ''
            actionBgColor = SKIN:GetVariable('SettingsButtonDisabledBgColor', '')
            actionTextColor = SKIN:GetVariable('SettingsButtonDisabledTextColor', '')
            state.currentRowActionByIndex[rowIndex] = nil
            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', '')
            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))
            state.currentRowSecondaryActionByIndex[rowIndex] = nil
            secondaryActionEnabled = false
        end

        setVariable('SettingsRow' .. rowIndex .. '_ActionText', actionText)
        applyRowActionFit(rowIndex, field, actionText, false)

        setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', actionCommand)

        setVariable('SettingsRow' .. rowIndex .. '_ActionCursor', actionCommand ~= '' and '1' or '0')

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCursor', secondaryActionEnabled and '1' or '0')

        if actionCommand ~= '' and state.currentRowActionByIndex[rowIndex] == nil then

            state.currentRowActionByIndex[rowIndex] = { kind = 'executeFieldAction', fieldKey = field.key }

        end

        setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', actionBgColor)

        setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', actionTextColor)

    end

    function methods.applyRowLabelTextFit(rowIndex, field, text)
        applyRowLabelFit(rowIndex, field, text)
    end
end
