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
                if applyTextFit then
                    applyTextFit('MeterSettingsDropdownOption' .. tostring(slotIndex) .. 'Label', '', option.displayLabel, 'SettingsUIFontSize', labelW, 0.70)
                end

                setVariable('SettingsDropdownOption' .. slotIndex .. 'AppliedValue', option.appliedValue)

            else

                setVariable('SettingsDropdownOption' .. slotIndex .. 'Hidden', '1')

                setVariable('SettingsDropdownOption' .. slotIndex .. 'LabelText', '')
                if applyTextFit then
                    applyTextFit('MeterSettingsDropdownOption' .. tostring(slotIndex) .. 'Label', '', '', 'SettingsUIFontSize', labelW, 0.70)
                end

                setVariable('SettingsDropdownOption' .. slotIndex .. 'AppliedValue', '')

            end

        end

    end
end
