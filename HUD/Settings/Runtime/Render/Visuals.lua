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
            'MeterSettingsTab8BG', 'MeterSettingsTab8Label',

            'MeterSettingsFooterPrevBG', 'MeterSettingsFooterPrevLabel',

            'MeterSettingsFooterCurrentBG', 'MeterSettingsFooterCurrentLabel',

            'MeterSettingsFooterNextBG', 'MeterSettingsFooterNextLabel',

            'MeterSettingsNoticeBarBG',

            'MeterSettingsNoticeViewAllBG', 'MeterSettingsNoticeViewAllLabel',

            'MeterSettingsNoticeBodyText',

            'MeterSettingsNoticeDismissBG', 'MeterSettingsNoticeDismissLabel',

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

        meterNames[#meterNames + 1] = 'MeterSettingsDropdownBG'
        meterNames[#meterNames + 1] = 'MeterSettingsDropdownPagePrevBG'
        meterNames[#meterNames + 1] = 'MeterSettingsDropdownPagePrevLabel'
        meterNames[#meterNames + 1] = 'MeterSettingsDropdownPageCurrentBG'
        meterNames[#meterNames + 1] = 'MeterSettingsDropdownPageCurrentLabel'
        meterNames[#meterNames + 1] = 'MeterSettingsDropdownPageNextBG'
        meterNames[#meterNames + 1] = 'MeterSettingsDropdownPageNextLabel'

        for slotIndex = 1, state.dropdownRowsPerPage do

            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'BG'

            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'Label'

            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'DeleteBG'

            meterNames[#meterNames + 1] = 'MeterSettingsDropdownOption' .. slotIndex .. 'DeleteLabel'

        end

        meterNames[#meterNames + 1] = 'MeterSettingsLoadingCover'
        meterNames[#meterNames + 1] = 'MeterSettingsLoadingLabel'

        for _, meterName in ipairs(meterNames) do

            SKIN:Bang('!UpdateMeter', meterName)

        end

        SKIN:Bang('!UpdateMeasure', 'MeasureSharedInput')

        SKIN:Bang('!Redraw')

    end
end
