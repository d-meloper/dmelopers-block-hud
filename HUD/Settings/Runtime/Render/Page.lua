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

                local rowTooltip = methods.tooltipTextForField(field)
                setVariable('SettingsRow' .. rowIndex .. '_Tooltip', rowTooltip)
                setVariable('SettingsRow' .. rowIndex .. '_ActionTooltip', rowTooltip)

                if field.controlType == 'text' or field.controlType == 'multiDropdown' then

                    methods.configureTextRow(rowIndex, field, isFieldDisabled)

                elseif field.controlType == 'hudMirrorStatus' and methods.configureHudMirrorStatusRow then

                    methods.configureHudMirrorStatusRow(rowIndex, field)

                elseif field.controlType == 'readonly' then

                    methods.configureReadonlyRow(rowIndex, field)

                elseif field.controlType == 'toggle' then

                    methods.configureToggleRow(rowIndex, field, isFieldDisabled)

                elseif field.controlType == 'segmented' then

                    methods.configureSegmentedRow(rowIndex, field, isFieldDisabled)

                elseif field.controlType == 'stepper' then

                    methods.configureStepperRow(rowIndex, field, isFieldDisabled)

                elseif field.controlType == 'action' then

                    methods.configureActionRow(rowIndex, field, isFieldDisabled)

                end

                if methods.applyRowLabelTextFit then
                    methods.applyRowLabelTextFit(rowIndex, field, rowLabelText)
                end

            end

        end

    end
    function methods.renderActivePage()

        local tab = methods.activeTab()
        local isHudMirrorTab = state.contentMode ~= true and tab and tab.id == 'hudMirror'
        if isHudMirrorTab and state.hudMirrorTabEntered ~= true and methods.PrepareHudMirrorTab then
            state.hudMirrorTabEntered = true
            methods.PrepareHudMirrorTab()
            tab = methods.activeTab()
        elseif not isHudMirrorTab then
            state.hudMirrorTabEntered = false
        end
        methods.applyActiveModeLayout()

        methods.updateTopActionColors()

        methods.updatePageButtons(tab)

        methods.configureHerobrineStatsHeader(tab)

        methods.renderRows(tab)

        if methods.syncMinecraftSkinPlayerFolderSizeView then
            methods.syncMinecraftSkinPlayerFolderSizeView()
        end

        local activeDropdownField = methods.getField(state.activeDropdownFieldKey)
        if state.activeDropdownFieldKey
            and (not state.currentVisibleRows[state.activeDropdownFieldKey]
                or (activeDropdownField and methods.isFieldDisabled(activeDropdownField))) then

            methods.closeDropdownInternal()

        end

        methods.renderDropdown()

        if methods.renderVersionStatusState then

            methods.renderVersionStatusState()

        end

        methods.updateHistoryButtons({ skipTopActionTextFit = true })

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
