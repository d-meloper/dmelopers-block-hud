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
    local commonFieldLabelKeyByFieldKey = {
        jukeboxDraggable = 'Settings_Field_CommonDraggable_Label',
        hotbarDraggable = 'Settings_Field_CommonDraggable_Label',
        indicatorsDraggable = 'Settings_Field_CommonDraggable_Label',
        inventoryDraggable = 'Settings_Field_CommonDraggable_Label',
        clockDraggable = 'Settings_Field_CommonDraggable_Label',
        jukeboxDragSnap = 'Settings_Field_CommonDragSnap_Label',
        hotbarDragSnap = 'Settings_Field_CommonDragSnap_Label',
        indicatorsDragSnap = 'Settings_Field_CommonDragSnap_Label',
        inventoryDragSnap = 'Settings_Field_CommonDragSnap_Label',
        clockDragSnap = 'Settings_Field_CommonDragSnap_Label',
        resetAllSettings = 'Settings_Field_CommonResetSettings_Label',
        resetHotbarSettings = 'Settings_Field_CommonResetSettings_Label',
        resetIndicatorsSettings = 'Settings_Field_CommonResetSettings_Label',
        resetInventorySettings = 'Settings_Field_CommonResetSettings_Label',
        resetClockSettings = 'Settings_Field_CommonResetSettings_Label',
        resetHotbarSkinPositions = 'Settings_Field_CommonResetSkinPositions_Label',
        resetIndicatorsSkinPositions = 'Settings_Field_CommonResetSkinPositions_Label',
        resetInventorySkinPositions = 'Settings_Field_CommonResetSkinPositions_Label',
        resetClockSkinPositions = 'Settings_Field_CommonResetSkinPositions_Label',
    }
    local commonTooltipKeyByFieldKey = {
        jukeboxDragSnap = 'Settings_Tooltip_CommonDragSnap',
        hotbarDragSnap = 'Settings_Tooltip_CommonDragSnap',
        indicatorsDragSnap = 'Settings_Tooltip_CommonDragSnap',
        inventoryDragSnap = 'Settings_Tooltip_CommonDragSnap',
        clockDragSnap = 'Settings_Tooltip_CommonDragSnap',
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
        if applyTextFit then
            for index, tab in ipairs(activeTabs) do
                local key = settingsTabLocalizationKeyById[trim(tab and tab.id or '')]
                local text = methods.tabDisplayText(tab)
                local width = methods.numericVariable('SlotSettingsTab' .. tostring(index) .. '_LabelW', 0) or 0
                applyTextFit('MeterSettingsTab' .. tostring(index) .. 'Label', key, text, 'SettingsTabFontSize', width, 0.70)
            end
        end
        applyRowSlotGeometry(state.contentMode == true)
    end

    function methods.fieldLabelText(field)
        local fallback = trim(field and field.label or '')
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return fallback
        end
        return trim(methods.localize(methods.fieldLabelLocalizationKey(field), fallback))
    end

    function methods.fieldLabelLocalizationKey(field)
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return ''
        end
        return commonFieldLabelKeyByFieldKey[fieldKey] or ('Settings_Field_' .. fieldKey .. '_Label')
    end

    function methods.fieldActionLocalizationKey(field)
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return ''
        end
        if fieldKey == 'refreshHerobrineStats' then
            return 'Common_Refresh'
        end
        return 'Settings_Field_' .. fieldKey .. '_Action'
    end

    function methods.fieldActionText(field, fallback)
        local resolvedFallback = trim(fallback == nil and (field and field.defaultActionText or '') or fallback)
        local fieldKey = trim(field and field.key or '')
        if fieldKey == '' then
            return resolvedFallback
        end

        local localized = trim(methods.localize(methods.fieldActionLocalizationKey(field), resolvedFallback))
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

        local localizationKey = commonTooltipKeyByFieldKey[fieldKey] or ('Settings_Tooltip_' .. fieldKey)
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
end
