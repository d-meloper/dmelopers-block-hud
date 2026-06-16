return function(app)















    local state = app.state
    local schema = app.schema















    local methods = app.methods















    local trim = app.trim















    local setVariable = app.setVariable

    local function contractVariable(name, fallback)
        return SKIN:GetVariable(name, fallback or '')
    end

    local function dropdownClosedText(rowIndex)
        return contractVariable('SettingsDropdownArrowClosed', contractVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', 'v'))
    end

    local function dropdownOpenText()
        return contractVariable('SettingsDropdownArrowOpen', '^')
    end

    local function pixelValue(value, fallback)
        local numeric = tonumber(value)
        if numeric == nil then
            numeric = tonumber(fallback) or 0
        end
        if numeric < 0 then
            return math.ceil(numeric - 0.5)
        end
        return math.floor(numeric + 0.5)
    end















    function methods.numericVariable(name, fallback)















        local replaced = SKIN:ReplaceVariables('#' .. tostring(name) .. '#')















        local numeric = tonumber(trim(replaced))















        if numeric ~= nil then















            return numeric















        end















        local ok, parsed = pcall(function()















            return SKIN:ParseFormula(replaced)















        end)















        if ok and parsed ~= nil then















            numeric = tonumber(parsed)















            if numeric ~= nil then















                return numeric















            end















        end















        return fallback















    end















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















    local settingsTabLocalizationKeyById = {
        general = 'Settings_Tab_General',
        lowSpec = 'Settings_Tab_LowSpec',
        hotbar = 'Settings_Tab_Hotbar',
        indicators = 'Settings_Tab_Indicators',
        inventory = 'Settings_Tab_Inventory',
        clock = 'Settings_Tab_Clock',
        ui = 'Settings_Tab_UI',
        jukebox = 'Settings_Content_Jukebox',
        herobrine = 'Settings_Content_Herobrine',
    }

    function methods.tabDisplayText(tab)
        local fallback = trim(tab and tab.name or '')
        local labelVariable = trim(tab and tab.labelVariable or '')
        if labelVariable ~= '' then
            return '#' .. labelVariable .. '#'
        end
        local key = settingsTabLocalizationKeyById[trim(tab and tab.id or '')]
        if key == nil or key == '' then
            return fallback
        end
        return trim(methods.localize(key, fallback))
    end

    local function setTabSlotGeometry(index, x, y, w, h, labelPad)
        local prefix = 'SlotSettingsTab' .. tostring(index)
        setVariable(prefix .. '_X', tostring(x))
        setVariable(prefix .. '_Y', tostring(y))
        setVariable(prefix .. '_W', tostring(w))
        setVariable(prefix .. '_H', tostring(h))
        setVariable(prefix .. '_LabelX', tostring(x + (w / 2)))
        setVariable(prefix .. '_LabelY', tostring(y + (h / 2)))
        setVariable(prefix .. '_LabelW', tostring(math.max(0, w - (2 * labelPad))))
    end

    local function restoreNormalTabGeometry()
        local labelPad = methods.numericVariable('SettingsTabLabelPad', 3) or 3
        local tabH = methods.numericVariable('SettingsTabSlotH', methods.numericVariable('SettingsTall1H', 40)) or 40
        local contentX = methods.numericVariable('SettingsContentX', 0) or 0
        local contentW = methods.numericVariable('SettingsContentW', 0) or 0
        local gap = methods.numericVariable('SettingsTabGap', 0) or 0
        local row1Y = methods.numericVariable('SettingsTabStripY', 0) or 0
        local rowGap = methods.numericVariable('SettingsTabRowGap', 0) or 0
        local row2Y = row1Y + tabH + rowGap
        local row1W = math.max(0, (contentW - (3 * gap)) / 4)
        local row2W = math.max(0, (contentW - (2 * gap)) / 3)

        setTabSlotGeometry(1, contentX, row1Y, row1W, tabH, labelPad)
        setTabSlotGeometry(3, contentX + row1W + gap, row1Y, row1W, tabH, labelPad)
        setTabSlotGeometry(6, contentX + ((row1W + gap) * 2), row1Y, row1W, tabH, labelPad)
        setTabSlotGeometry(7, contentX + ((row1W + gap) * 3), row1Y, row1W, tabH, labelPad)
        setTabSlotGeometry(5, contentX, row2Y, row2W, tabH, labelPad)
        setTabSlotGeometry(4, contentX + row2W + gap, row2Y, row2W, tabH, labelPad)
        setTabSlotGeometry(2, contentX + ((row2W + gap) * 2), row2Y, row2W, tabH, labelPad)
    end

    local function applyContentTabGeometry(tabCount)
        local count = math.max(1, tonumber(tabCount) or 1)
        local contentX = methods.numericVariable('SettingsContentX', 0) or 0
        local contentW = methods.numericVariable('SettingsContentW', 0) or 0
        local gap = methods.numericVariable('SettingsTabGap', 0) or 0
        local y = methods.numericVariable('SettingsTabStripY', 0) or 0
        local h = methods.numericVariable('SettingsTabSlotH', methods.numericVariable('SettingsTall1H', 40)) or 40
        local labelPad = methods.numericVariable('SettingsTabLabelPad', 3) or 3
        local w = math.max(0, (contentW - ((count - 1) * gap)) / count)
        for index = 1, 7 do
            if index <= count then
                local x = contentX + ((index - 1) * (w + gap))
                setTabSlotGeometry(index, x, y, w, h, labelPad)
            else
                setTabSlotGeometry(index, contentX, y, 0, h, labelPad)
            end
        end
    end

    local function isHerobrineStatsPage(tab)
        return state.contentMode == true
            and trim(tab and tab.id or '') == 'herobrine'
            and methods.activePageIndex() == 2
    end

    local function applyRowSlotGeometry(contentMode)
        local rowH = methods.numericVariable('SettingsTall1H', 40) or 40
        local rowGap = methods.numericVariable('SettingsRowGap', methods.numericVariable('SettingsSectionGap', 12)) or 12
        local row1Y
        if contentMode then
            row1Y = (methods.numericVariable('SettingsTabStripY', 0) or 0) + (methods.numericVariable('SettingsTabSlotH', rowH) or rowH) + (methods.numericVariable('SettingsTabOptionsGap', 20) or 20)
        else
            row1Y = methods.numericVariable('SettingsRow1Y', 0) or 0
        end
        if contentMode and isHerobrineStatsPage(methods.activeTab and methods.activeTab() or nil) then
            row1Y = row1Y + rowH + rowGap
        end

        local labelX = methods.numericVariable('SettingsRowLabelX', methods.numericVariable('SettingsContentX', 0)) or 0
        local labelW = methods.numericVariable('SettingsRowLabelW', 0) or 0
        local controlX = methods.numericVariable('SettingsRowControlX', 0) or 0
        local controlW = methods.numericVariable('SettingsRowControlW', 0) or 0
        local dropdownW = methods.numericVariable('SettingsDropdownButtonW', 24) or 24

        for index = 1, state.rowsPerPage do
            local y = row1Y + ((index - 1) * (rowH + rowGap))
            setVariable('SlotSettingsRow' .. index .. '_LabelX', tostring(labelX))
            setVariable('SlotSettingsRow' .. index .. '_LabelY', tostring(y))
            setVariable('SlotSettingsRow' .. index .. '_LabelW', tostring(labelW))
            setVariable('SlotSettingsRow' .. index .. '_LabelH', tostring(rowH))
            setVariable('SlotSettingsRow' .. index .. '_LabelTextX', tostring(labelX))
            setVariable('SlotSettingsRow' .. index .. '_LabelTextY', tostring(y + (rowH / 2)))
            setVariable('SlotSettingsRow' .. index .. '_ControlX', tostring(controlX))
            setVariable('SlotSettingsRow' .. index .. '_ControlY', tostring(y))
            setVariable('SlotSettingsRow' .. index .. '_ControlW', tostring(controlW))
            setVariable('SlotSettingsRow' .. index .. '_ControlH', tostring(rowH))
            setVariable('SlotSettingsRow' .. index .. '_DropdownButton_X', tostring(controlX + controlW - dropdownW))
            setVariable('SlotSettingsRow' .. index .. '_DropdownButton_Y', tostring(y))
            setVariable('SlotSettingsRow' .. index .. '_DropdownButton_W', tostring(dropdownW))
            setVariable('SlotSettingsRow' .. index .. '_DropdownButton_H', tostring(rowH))
            setVariable('SlotSettingsRow' .. index .. '_DropdownButton_LabelX', tostring(controlX + controlW - (dropdownW / 2)))
            setVariable('SlotSettingsRow' .. index .. '_DropdownButton_LabelY', tostring(y + (rowH / 2)))
        end
    end

    function methods.applyActiveModeLayout()
        setVariable('SettingsContentMode', state.contentMode == true and '1' or '0')
        local activeTabs = methods.activeTabs and methods.activeTabs() or schema.tabs
        if state.contentMode == true then
            applyContentTabGeometry(#activeTabs)
        else
            restoreNormalTabGeometry()
        end
        applyRowSlotGeometry(state.contentMode == true)
    end

    function methods.fieldLabelText(field)
        local fallback = trim(field and field.label or '')
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return fallback
        end
        return trim(methods.localize('Settings_Field_' .. fieldKey .. '_Label', fallback))
    end

    function methods.fieldActionText(field, fallback)
        local resolvedFallback = trim(fallback == nil and (field and field.defaultActionText or '') or fallback)
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return resolvedFallback
        end

        local localized = trim(methods.localize('Settings_Field_' .. fieldKey .. '_Action', resolvedFallback))
        if localized ~= resolvedFallback then
            return localized
        end

        local genericKeyByFieldKey = {
            resetHotbarSettings = 'Settings_Field_resetTab_Action',
            resetIndicatorsSettings = 'Settings_Field_resetTab_Action',
            resetInventorySettings = 'Settings_Field_resetTab_Action',
            resetClockSettings = 'Settings_Field_resetTab_Action',
            resetHerobrineSettings = 'Settings_Field_resetTab_Action',
            resetHotbarSkinPositions = 'Settings_Field_resetPosition_Action',
            resetIndicatorsSkinPositions = 'Settings_Field_resetPosition_Action',
            resetInventorySkinPositions = 'Settings_Field_resetPosition_Action',
            resetClockSkinPositions = 'Settings_Field_resetPosition_Action',
            resetAllSkinPositions = 'Settings_Field_resetAllSkinPositions_Action',
        }
        local genericKey = genericKeyByFieldKey[fieldKey]
        if genericKey ~= nil and genericKey ~= '' then
            return trim(methods.localize(genericKey, resolvedFallback))
        end

        return localized
    end

    function methods.tooltipTextForField(field)
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return ''
        end

        local localizationKey = 'Settings_Tooltip_' .. fieldKey
        local variableRef = methods.localizationVariableRef and methods.localizationVariableRef(localizationKey) or ''
        if variableRef ~= '' then
            return variableRef
        end

        return methods.localize(localizationKey, '')
    end

    function methods.configureHerobrineStatsHeader(tab)
        local showHeader = state.contentMode == true
            and trim(tab and tab.id or '') == 'herobrine'
            and methods.activePageIndex() == 2

        if not showHeader then
            setVariable('SettingsHerobrineStatsHeaderHidden', '1')
            setVariable('SettingsHerobrineStatsHeaderText', '')
            SKIN:Bang('!HideMeter', 'MeterSettingsHerobrineStatsHeader')
            SKIN:Bang('!UpdateMeter', 'MeterSettingsHerobrineStatsHeader')
            return
        end

        local row1Y = methods.numericVariable('SlotSettingsRow1_LabelY', methods.numericVariable('SettingsRow1Y', 0)) or 0
        local rowH = methods.numericVariable('SlotSettingsRow1_LabelH', methods.numericVariable('SettingsTall1H', 40)) or 40
        local rowGap = methods.numericVariable('SettingsRowGap', methods.numericVariable('SettingsSectionGap', 12)) or 12
        local headerH = math.max(12, methods.numericVariable('SettingsHerobrineStatsHeaderH', 18) or 18)
        local headerSlotY = row1Y - rowH - rowGap
        local contentX = methods.numericVariable('SettingsContentX', 0) or 0
        local contentW = methods.numericVariable('SettingsContentW', 0) or 0
        local titleRef = methods.localizationVariableRef and methods.localizationVariableRef('Settings_HerobrineStats_Title') or ''

        if titleRef == '' then
            titleRef = methods.localize('Settings_HerobrineStats_Title', 'Herobrine stats')
        end

        setVariable('SettingsHerobrineStatsHeaderHidden', '0')
        setVariable('SettingsHerobrineStatsHeaderText', titleRef)
        setVariable('SettingsHerobrineStatsHeaderX', tostring(contentX + (contentW / 2)))
        setVariable('SettingsHerobrineStatsHeaderY', tostring(math.max(0, headerSlotY + (rowH / 2))))
        setVariable('SettingsHerobrineStatsHeaderW', tostring(contentW))
        setVariable('SettingsHerobrineStatsHeaderH', tostring(headerH))
        SKIN:Bang('!ShowMeter', 'MeterSettingsHerobrineStatsHeader')
        SKIN:Bang('!UpdateMeter', 'MeterSettingsHerobrineStatsHeader')
    end







    function methods.isFieldDisabled(field)
        if not field then
            return false
        end

        local disabledWhenFieldOn = trim(field.disabledWhenFieldOn or '')
        if disabledWhenFieldOn ~= '' then
            local dependencyField = methods.getField(disabledWhenFieldOn)
            if dependencyField and methods.toggleSemanticValue(dependencyField, methods.readFieldValue(dependencyField)) then
                return true
            end
        end

        local disabledWhenFieldOff = trim(field.disabledWhenFieldOff or '')
        if disabledWhenFieldOff ~= '' then
            local dependencyField = methods.getField(disabledWhenFieldOff)
            if dependencyField and not methods.toggleSemanticValue(dependencyField, methods.readFieldValue(dependencyField)) then
                return true
            end
        end

        return false
    end

    function methods.applyRowEnabledVisualState(rowIndex, isEnabled)
        local labelTextColor = isEnabled and SKIN:GetVariable('SettingsInputTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', '')
        local toggleBgColor = isEnabled and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', '')

        setVariable('SettingsRow' .. rowIndex .. '_LabelTextColor', labelTextColor)
        setVariable('SettingsRow' .. rowIndex .. '_ToggleBgColor', toggleBgColor)
    end

    function methods.configureTextRow(rowIndex, field)















        local displayValue = methods.displayValueForField(field, methods.readFieldValue(field))















        if displayValue == '' then















            displayValue = methods.localize('Settings_EmptyValue', '빈 값')















        end















        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '0')















        setVariable('SettingsRow' .. rowIndex .. '_FieldText', displayValue)















        setVariable('SettingsRow' .. rowIndex .. '_FieldCommand', '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "PrepareTextField(\'' .. field.key .. '\')"][!CommandMeasure MeasureSettingsCommit "OpenPreparedTextField()"]')















        methods.syncTextFieldGeometry(rowIndex, field)

        local inlineActionFieldKey = trim(field and field.inlineActionFieldKey or '')

        if inlineActionFieldKey ~= '' then

            local inlineActionField = methods.getField(inlineActionFieldKey)

            if inlineActionField then

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

                setVariable('SettingsRow' .. rowIndex .. '_ActionText', methods.fieldActionText(inlineActionField, trim(field.inlineActionText or inlineActionField.defaultActionText or '')))

                setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', string.format("[!CommandMeasure MeasureSettingsCommit \"PlayUiClick()\"][!CommandMeasure MeasureSettingsCommit \"ExecuteFieldAction('%s')\"]", inlineActionField.key))



                state.currentRowActionByIndex[rowIndex] = { kind = 'executeFieldAction', fieldKey = inlineActionField.key }

                setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))

                setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryHidden', '1')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', '')

                setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', '')

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

        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', dropdownClosedText(rowIndex))

    end



    function methods.configureToggleRow(rowIndex, field, isDisabled)















        local semanticOn = methods.toggleSemanticValue(field, methods.readFieldValue(field))















        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')















        setVariable('SettingsRow' .. rowIndex .. '_ToggleHidden', '0')















        setVariable('SettingsRow' .. rowIndex .. '_ToggleFillColor', semanticOn and SKIN:GetVariable('SettingsToggleFillOnColor', '') or SKIN:GetVariable('SettingsToggleFillOffColor', '0,0,0,0'))















        setVariable('SettingsRow' .. rowIndex .. '_ToggleCommand', isDisabled and '' or '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ToggleField(\'' .. field.key .. '\')"]')















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
        setVariable('SettingsRow' .. rowIndex .. '_ActionText', optionLabel(primary))
        setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', '')
        setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', optionBgColor(primarySelected))
        setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', optionTextColor(primarySelected))

        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_X', tostring(secondaryX))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_Y', tostring(controlY))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_W', tostring(secondaryW))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_H', tostring(controlH))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelX', tostring(secondaryX + (secondaryW / 2)))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondary_LabelY', tostring(labelY))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryText', optionLabel(secondary))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', '')
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', optionBgColor(secondarySelected))
        setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', optionTextColor(secondarySelected))

        state.currentRowActionByIndex[rowIndex] = isDisabled and nil or { kind = 'selectSegmentedOption', fieldKey = field.key, value = primaryValue }
        state.currentRowSecondaryActionByIndex[rowIndex] = isDisabled and nil or { kind = 'selectSegmentedOption', fieldKey = field.key, value = secondaryValue }

    end

    function methods.configureStepperRow(rowIndex, field)















        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '1')

        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')















        setVariable('SettingsRow' .. rowIndex .. '_StepperHidden', '0')















        setVariable('SettingsRow' .. rowIndex .. '_StepperFieldText', methods.readFieldValue(field))















        setVariable('SettingsRow' .. rowIndex .. '_StepperFieldCommand', '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "PrepareTextField(\'' .. field.key .. '\')"][!CommandMeasure MeasureSettingsCommit "OpenPreparedTextField()"]')















        setVariable('SettingsRow' .. rowIndex .. '_StepperMinusCommand', '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "StepFieldDown(\'' .. field.key .. '\')"]')















        setVariable('SettingsRow' .. rowIndex .. '_StepperPlusCommand', '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "StepFieldUp(\'' .. field.key .. '\')"]')















    end















    function methods.configureActionRow(rowIndex, field)















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















        local actionButtonW = methods.numericVariable('SlotSettingsRowActionButtonW', methods.numericVariable('SettingsActionButtonW', controlW)) or controlW















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






























        local labelText = methods.fieldLabelText(field)

        local actionText = methods.fieldActionText(field)















        local actionCommand = string.format("[!CommandMeasure MeasureSettingsCommit \"PlayUiClick()\"][!CommandMeasure MeasureSettingsCommit \"ExecuteFieldAction('%s')\"]", field.key)















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















            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryCommand', string.format("[!CommandMeasure MeasureSettingsCommit \"PlayUiClick()\"][!CommandMeasure MeasureSettingsCommit \"ExecuteFieldAction('%s')\"]", field.key))



            state.currentRowSecondaryActionByIndex[rowIndex] = { kind = 'executeFieldAction', fieldKey = field.key }















            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryBgColor', SKIN:GetVariable('SettingsDangerButtonBgColor', ''))















            setVariable('SettingsRow' .. rowIndex .. '_ActionSecondaryTextColor', SKIN:GetVariable('SettingsDangerButtonTextColor', ''))















        end






























        setVariable('SettingsRow' .. rowIndex .. '_ActionText', actionText)















        setVariable('SettingsRow' .. rowIndex .. '_ActionCommand', actionCommand)



        if actionCommand ~= '' and state.currentRowActionByIndex[rowIndex] == nil then



            state.currentRowActionByIndex[rowIndex] = { kind = 'executeFieldAction', fieldKey = field.key }



        end















        setVariable('SettingsRow' .. rowIndex .. '_ActionBgColor', actionBgColor)















        setVariable('SettingsRow' .. rowIndex .. '_ActionTextColor', actionTextColor)















    end















    function methods.renderRows(tab)















        state.currentVisibleRows = {}















        state.currentFieldKeyByRow = {}



        state.currentRowActionByIndex = {}



        state.currentRowSecondaryActionByIndex = {}















        local visibleFields = {}















        local pageIndex = methods.activePageIndex()















        for _, fieldKey in ipairs(tab.fields) do















            local field = methods.getField(fieldKey)















            if field and (field.pageId or 1) == pageIndex then















                visibleFields[#visibleFields + 1] = field















            end















        end















        for rowIndex = 1, state.rowsPerPage do















            local field = visibleFields[rowIndex]















            methods.setRowHidden(rowIndex, field == nil)















            if field then















                local isFieldDisabled = methods.isFieldDisabled(field)

                state.currentVisibleRows[field.key] = rowIndex















                state.currentFieldKeyByRow[rowIndex] = field.key















                setVariable('SettingsRow' .. rowIndex .. '_Hidden', '0')
                methods.applyRowEnabledVisualState(rowIndex, not isFieldDisabled)















                local rowLabelText = methods.fieldLabelText(field)
                setVariable('SettingsRow' .. rowIndex .. '_LabelText', rowLabelText)















                setVariable('SettingsRow' .. rowIndex .. '_Tooltip', methods.tooltipTextForField(field))






























                if field.controlType == 'text' then















                    methods.configureTextRow(rowIndex, field)















                elseif field.controlType == 'readonly' then















                    methods.configureReadonlyRow(rowIndex, field)















                elseif field.controlType == 'toggle' then















                    methods.configureToggleRow(rowIndex, field, isFieldDisabled)










                elseif field.controlType == 'segmented' then










                    methods.configureSegmentedRow(rowIndex, field, isFieldDisabled)















                elseif field.controlType == 'stepper' then















                    methods.configureStepperRow(rowIndex, field)















                elseif field.controlType == 'action' then















                    methods.configureActionRow(rowIndex, field)















                end















            end















        end















    end















    function methods.renderDropdown()















        if not state.activeDropdownFieldKey or state.activeDropdownFieldKey == '' then















            methods.clearDropdownVisualState()















            return















        end















        local field = methods.getField(state.activeDropdownFieldKey)















        local rowIndex = state.currentVisibleRows[state.activeDropdownFieldKey] or state.activeDropdownRowIndex















        if not field or not methods.hasDropdown(field) or not rowIndex or rowIndex < 1 or not state.currentVisibleRows[state.activeDropdownFieldKey] then















            methods.closeDropdownInternal()















            methods.clearDropdownVisualState()















            return















        end















        state.activeDropdownRowIndex = rowIndex















        methods.syncDropdownPageIndex(field)















        local rowX = pixelValue(methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_X', 0), 0)















        local rowY = pixelValue(methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_Y', 0), 0)















        local rowH = pixelValue(methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_H', methods.numericVariable('SettingsTall1H', 40)), 40)















        local rowControlW = pixelValue(methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlW', methods.numericVariable('SettingsRow' .. rowIndex .. '_Field_W', 0)), 0)















        local panelX = pixelValue(methods.numericVariable('SettingsContentX', methods.numericVariable('SettingsPanelX', 0)), 0)















        local panelW = pixelValue(methods.numericVariable('SettingsContentW', methods.numericVariable('SettingsPanelWidth', rowControlW)), rowControlW)















        local panelY = pixelValue(methods.numericVariable('SettingsPanelY', 0), 0)















        local panelH = pixelValue(methods.numericVariable('SettingsPanelHeight', 0), 0)















        local panelRight = panelX + panelW















        local panelBottom = panelY + panelH















        local dropdownH = pixelValue(methods.numericVariable('SettingsDropdownH', 0), 0)















        local anchorGap = pixelValue(methods.numericVariable('SettingsDropdownAnchorGap', 4), 4)















        local desiredW = pixelValue(methods.numericVariable('SettingsDropdownW', rowControlW), rowControlW)















        if desiredW <= 0 then
            desiredW = rowControlW
        end







        local resolvedW = pixelValue(math.min(desiredW, panelW), rowControlW)















        local resolvedX = pixelValue(rowX, 0)















        if resolvedX + resolvedW > panelRight then















            resolvedX = pixelValue(panelRight - resolvedW, 0)















        end















        if resolvedX < panelX then















            resolvedX = panelX















        end















        local downY = pixelValue(rowY + rowH + anchorGap, 0)















        local upY = pixelValue(rowY - anchorGap - dropdownH, 0)















        local resolvedY = downY















        if downY + dropdownH > panelBottom then















            resolvedY = upY















            if resolvedY < panelY then















                resolvedY = panelY















            end















        end















        setVariable('SettingsDropdownHidden', '0')















        setVariable('SettingsDropdown_X', tostring(resolvedX))















        setVariable('SettingsDropdown_Y', tostring(resolvedY))















        setVariable('SettingsDropdown_W', tostring(resolvedW))















        setVariable('SettingsDropdownFieldKey', field.key)















        setVariable('SettingsDropdownRowIndex', tostring(rowIndex))















        local dropdownPadding = methods.numericVariable('SettingsDropdownPadding', 6) or 6















        local optionH = methods.numericVariable('SettingsDropdownOptionH', 28) or 28















        local optionGap = methods.numericVariable('SettingsDropdownOptionGap', 2) or 2















        local pageH = methods.numericVariable('SettingsDropdownPageH', 24) or 24















        local pageButtonW = methods.numericVariable('SettingsDropdownPageButtonW', 24) or 24















        local pageCurrentW = methods.numericVariable('SettingsDropdownPageCurrentW', 56) or 56















        local pageGap = methods.numericVariable('SettingsDropdownPageGap', 4) or 4















        local textPad = methods.numericVariable('SlotSettingsRowText_ContentPad', methods.numericVariable('SettingsInnerPad', 10)) or 10



        local deleteButtonSize = math.max(14, math.min(optionH - 8, 20))



        local deleteButtonGap = 6















        local optionW = math.max(0, resolvedW - (2 * dropdownPadding))















        local optionBaseX = resolvedX + dropdownPadding















        local optionBaseY = resolvedY + dropdownPadding















        local pageY = resolvedY + dropdownPadding + (state.dropdownRowsPerPage * optionH) + ((state.dropdownRowsPerPage - 1) * optionGap) + dropdownPadding















        local pagePrevX = resolvedX + dropdownPadding















        local pageCurrentX = pagePrevX + pageButtonW + pageGap















        local pageNextX = pageCurrentX + pageCurrentW + pageGap















        local options = methods.currentDropdownOptions(field)















        local pageCount = methods.dropdownPageCount(field)















        local pageStart = ((state.activeDropdownPageIndex - 1) * state.dropdownRowsPerPage) + 1















        setVariable('SettingsDropdownPageText', tostring(state.activeDropdownPageIndex) .. '/' .. tostring(pageCount))















        setVariable('SettingsDropdownPagePrevBgColor', pageCount > 1 and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))















        setVariable('SettingsDropdownPagePrevTextColor', pageCount > 1 and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))















        setVariable('SettingsDropdownPageCurrentBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))















        setVariable('SettingsDropdownPageCurrentTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))















        setVariable('SettingsDropdownPageNextBgColor', pageCount > 1 and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))















        setVariable('SettingsDropdownPageNextTextColor', pageCount > 1 and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))















        setVariable('SettingsDropdownPagePrev_X', tostring(pagePrevX))















        setVariable('SettingsDropdownPagePrev_Y', tostring(pageY))















        setVariable('SettingsDropdownPagePrev_W', tostring(pageButtonW))















        setVariable('SettingsDropdownPagePrev_H', tostring(pageH))















        setVariable('SettingsDropdownPagePrev_LabelX', tostring(pagePrevX + (pageButtonW / 2)))















        setVariable('SettingsDropdownPagePrev_LabelY', tostring(pageY + (pageH / 2)))















        setVariable('SettingsDropdownPageCurrent_X', tostring(pageCurrentX))















        setVariable('SettingsDropdownPageCurrent_Y', tostring(pageY))















        setVariable('SettingsDropdownPageCurrent_W', tostring(pageCurrentW))















        setVariable('SettingsDropdownPageCurrent_H', tostring(pageH))















        setVariable('SettingsDropdownPageCurrent_LabelX', tostring(pageCurrentX + (pageCurrentW / 2)))















        setVariable('SettingsDropdownPageCurrent_LabelY', tostring(pageY + (pageH / 2)))















        setVariable('SettingsDropdownPageNext_X', tostring(pageNextX))















        setVariable('SettingsDropdownPageNext_Y', tostring(pageY))















        setVariable('SettingsDropdownPageNext_W', tostring(pageButtonW))















        setVariable('SettingsDropdownPageNext_H', tostring(pageH))















        setVariable('SettingsDropdownPageNext_LabelX', tostring(pageNextX + (pageButtonW / 2)))















        setVariable('SettingsDropdownPageNext_LabelY', tostring(pageY + (pageH / 2)))















        state.currentDropdownOptionBySlot = {}















        for slotIndex = 1, state.dropdownRowsPerPage do















            local option = options[pageStart + slotIndex - 1]















            local optionY = optionBaseY + ((slotIndex - 1) * (optionH + optionGap))















            state.currentDropdownOptionBySlot[slotIndex] = option















            local canDeleteOption = option and field.dropdownId == 'minecraftSkinHistory' and option.canDelete == true



            local deleteX = optionBaseX + optionW - textPad - deleteButtonSize



            local deleteY = optionY + ((optionH - deleteButtonSize) / 2)



            local labelW = optionW - (2 * textPad)



            if canDeleteOption then



                labelW = labelW - deleteButtonSize - deleteButtonGap



            end



            labelW = math.max(0, labelW)



            setVariable('SettingsDropdownOption' .. slotIndex .. '_X', tostring(optionBaseX))















            setVariable('SettingsDropdownOption' .. slotIndex .. '_Y', tostring(optionY))















            setVariable('SettingsDropdownOption' .. slotIndex .. '_W', tostring(optionW))















            setVariable('SettingsDropdownOption' .. slotIndex .. '_H', tostring(optionH))















            setVariable('SettingsDropdownOption' .. slotIndex .. '_LabelX', tostring(optionBaseX + textPad))















            setVariable('SettingsDropdownOption' .. slotIndex .. '_LabelY', tostring(optionY + (optionH / 2)))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_LabelW', tostring(labelW))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteHidden', canDeleteOption and '0' or '1')



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteX', tostring(deleteX))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteY', tostring(deleteY))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteW', tostring(deleteButtonSize))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteH', tostring(deleteButtonSize))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteLabelX', tostring(deleteX + (deleteButtonSize / 2)))



            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteLabelY', tostring(deleteY + (deleteButtonSize / 2)))















            if option then















                setVariable('SettingsDropdownOption' .. slotIndex .. 'Hidden', '0')















                setVariable('SettingsDropdownOption' .. slotIndex .. 'LabelText', option.displayLabel)















                setVariable('SettingsDropdownOption' .. slotIndex .. 'AppliedValue', option.appliedValue)















            else















                setVariable('SettingsDropdownOption' .. slotIndex .. 'Hidden', '1')















                setVariable('SettingsDropdownOption' .. slotIndex .. 'LabelText', '')















                setVariable('SettingsDropdownOption' .. slotIndex .. 'AppliedValue', '')















            end















        end















    end















    local function refreshMeters(meterNames, updateSharedInput)
    for _, meterName in ipairs(meterNames) do
        SKIN:Bang('!UpdateMeter', meterName)
    end

    if updateSharedInput == true then
        SKIN:Bang('!UpdateMeasure', 'MeasureSharedInput')
    end

    SKIN:Bang('!Redraw')
end

function methods.refreshLoadingVisuals()
    refreshMeters({
        'MeterSettingsLoadingCover',
        'MeterSettingsLoadingLabel',
    }, false)
end

function methods.refreshCurrentPageContent()
    local tab = methods.activeTab()
    methods.renderRows(tab)
    if state.activeDropdownFieldKey and not state.currentVisibleRows[state.activeDropdownFieldKey] then
        methods.closeDropdownInternal()
    end
    methods.renderDropdown()
    if methods.renderVersionStatusState then
        methods.renderVersionStatusState()
    end
    methods.updateHistoryButtons()
    methods.refreshVisuals()
end

function methods.refreshRowsAndHistoryVisuals()
    methods.refreshCurrentPageContent()
end

function methods.refreshVisuals()















        local meterNames = {















            'MeterSettingsPanel',















            'MeterSettingsTopUndoBG', 'MeterSettingsTopUndoLabel',















            'MeterSettingsTopRedoBG', 'MeterSettingsTopRedoLabel',















            'MeterSettingsTopResetBG', 'MeterSettingsTopResetLabel',

            'MeterSettingsTopContentBG', 'MeterSettingsTopContentLabel',
            'MeterSettingsTopRefreshBG', 'MeterSettingsTopRefreshLabel',















            'MeterSettingsTopCloseBG', 'MeterSettingsTopCloseLabel',















            'MeterSettingsTab1BG', 'MeterSettingsTab1Label',















            'MeterSettingsTab2BG', 'MeterSettingsTab2Label',















            'MeterSettingsTab3BG', 'MeterSettingsTab3Label',
            'MeterSettingsTab4BG', 'MeterSettingsTab4Label',
            'MeterSettingsTab5BG', 'MeterSettingsTab5Label',
            'MeterSettingsTab6BG', 'MeterSettingsTab6Label',
            'MeterSettingsTab7BG', 'MeterSettingsTab7Label',















            'MeterSettingsFooterPrevBG', 'MeterSettingsFooterPrevLabel',















            'MeterSettingsFooterCurrentBG', 'MeterSettingsFooterCurrentLabel',















            'MeterSettingsFooterNextBG', 'MeterSettingsFooterNextLabel',



            'MeterSettingsNoticeBarBG',



            'MeterSettingsNoticeViewAllBG', 'MeterSettingsNoticeViewAllLabel',



            'MeterSettingsNoticeBodyText',



            'MeterSettingsNoticeDismissBG', 'MeterSettingsNoticeDismissLabel',















            'MeterSettingsDropdownBG',















            'MeterSettingsDropdownPagePrevBG', 'MeterSettingsDropdownPagePrevLabel',















            'MeterSettingsDropdownPageCurrentBG', 'MeterSettingsDropdownPageCurrentLabel',















            'MeterSettingsDropdownPageNextBG', 'MeterSettingsDropdownPageNextLabel',















            'MeterSettingsLoadingCover', 'MeterSettingsLoadingLabel',















        }















        for rowIndex = 1, state.rowsPerPage do















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'Label'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'FieldBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'FieldText'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'DropdownButtonBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'DropdownButtonLabel'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'ToggleBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'ToggleFill'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'StepperFieldBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'StepperFieldText'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'StepperMinusBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'StepperMinusLabel'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'StepperPlusBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'StepperPlusLabel'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'ActionBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'ActionLabel'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'ActionSecondaryBG'















            meterNames[#meterNames + 1] = 'MeterSettingsRow' .. rowIndex .. 'ActionSecondaryLabel'















        end



        for slotIndex = 1, state.dropdownRowsPerPage do















            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'BG'















            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'Label'



            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'DeleteBG'



            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'DeleteLabel'















        end















        for _, meterName in ipairs(meterNames) do















            SKIN:Bang('!UpdateMeter', meterName)















        end















        SKIN:Bang('!UpdateMeasure', 'MeasureSharedInput')















        SKIN:Bang('!Redraw')















    end















    function methods.renderActivePage()















        local tab = methods.activeTab()
        methods.applyActiveModeLayout()

















        methods.updateTopActionColors()















        methods.updatePageButtons(tab)















        methods.configureHerobrineStatsHeader(tab)








        methods.renderRows(tab)















        if state.activeDropdownFieldKey and not state.currentVisibleRows[state.activeDropdownFieldKey] then















            methods.closeDropdownInternal()















        end















        methods.renderDropdown()



        if methods.renderVersionStatusState then



            methods.renderVersionStatusState()



        end





        methods.updateHistoryButtons()















        methods.refreshVisuals()















    end















    function methods.fieldKeyForVisibleRow(rowIndex, expectedControlType)















        local numericRowIndex = tonumber(rowIndex)















        if not numericRowIndex then















            return nil















        end















        local fieldKey = state.currentFieldKeyByRow[numericRowIndex]















        local field = methods.getField(fieldKey)















        if not field then















            return nil















        end















        if expectedControlType and field.controlType ~= expectedControlType then















            return nil















        end















        return fieldKey















    end















end
