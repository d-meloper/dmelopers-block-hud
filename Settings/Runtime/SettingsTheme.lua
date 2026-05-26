return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local snapshotSignature = app.snapshotSignature

    function methods.applyTheme(mode)
        local resolvedMode = mode == 'dark' and 'dark' or 'light'
        local prefix = resolvedMode == 'dark' and 'SettingsThemeDraculaPalette' or 'SettingsThemeLattePalette'

        setVariable('SettingsThemeMode', resolvedMode)
        for index = 1, 6 do
            local paletteValue = SKIN:GetVariable(prefix .. tostring(index), SKIN:GetVariable('SettingsPalette' .. tostring(index), ''))
            setVariable('SettingsPalette' .. tostring(index), paletteValue)
        end

        setVariable('SettingsPanelFillColor', SKIN:GetVariable('SettingsPalette1', ''))
        setVariable('SettingsPanelInsetColor', SKIN:GetVariable('SettingsPalette2', ''))
        setVariable('SettingsPanelStrokeColor', SKIN:GetVariable('SettingsPalette4', ''))
        setVariable('SettingsInputBgColor', SKIN:GetVariable('SettingsPalette2', ''))
        setVariable('SettingsInputStrokeColor', SKIN:GetVariable('SettingsPalette4', ''))
        setVariable('SettingsInputTextColor', SKIN:GetVariable('SettingsPalette5', ''))
        setVariable('SettingsButtonBgColor', SKIN:GetVariable('SettingsPalette3', ''))
        setVariable('SettingsButtonStrokeColor', SKIN:GetVariable('SettingsPalette4', ''))
        setVariable('SettingsButtonTextColor', SKIN:GetVariable('SettingsPalette5', ''))
        setVariable('SettingsButtonDisabledBgColor', SKIN:GetVariable('SettingsPalette2', ''))
        setVariable('SettingsButtonDisabledTextColor', SKIN:GetVariable('SettingsPalette4', ''))
        setVariable('SettingsToggleFillOnColor', SKIN:GetVariable('SettingsPalette6', ''))
        setVariable('SettingsToggleFillOffColor', '0,0,0,0')
        setVariable('SettingsTabActiveTextColor', resolvedMode == 'dark' and SKIN:GetVariable('SettingsPalette2', '') or SKIN:GetVariable('SettingsPalette5', ''))
    end

    function methods.themeDisplayText()
        return trim(SKIN:GetVariable('SettingsThemeMode', 'light')) == 'dark' and methods.localize('Settings_Theme_Dark', '다크') or methods.localize('Settings_Theme_Light', '라이트')
    end

    function methods.updateTopActionColors()
        setVariable('ActionSettingsClose_BgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))
        setVariable('ActionSettingsClose_TextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
        setVariable('ActionSettingsRefresh_BgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))
        setVariable('ActionSettingsRefresh_TextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
        for index = 1, #schema.tabs do
            local active = index == state.currentTabIndex
            setVariable('ActionSettingsTab' .. tostring(index) .. '_BgColor', active and SKIN:GetVariable('SettingsPalette6', '') or SKIN:GetVariable('SettingsButtonBgColor', ''))
            setVariable('ActionSettingsTab' .. tostring(index) .. '_TextColor', active and SKIN:GetVariable('SettingsTabActiveTextColor', '') or SKIN:GetVariable('SettingsButtonTextColor', ''))
        end
        setVariable('ActionSettingsPageCurrent_BgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))
        setVariable('ActionSettingsPageCurrent_TextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
    end

    function methods.updateHistoryButtons()
        local undoEnabled = #state.undoHistory > 0
        local redoEnabled = #state.redoHistory > 0
        local resetEnabled = state.baselineSnapshot and snapshotSignature(methods.captureSnapshot()) ~= snapshotSignature(state.baselineSnapshot)

        setVariable('ActionSettingsUndo_Command', undoEnabled and '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "UndoChange()"]' or '')
        setVariable('ActionSettingsUndo_BgColor', undoEnabled and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('ActionSettingsUndo_TextColor', undoEnabled and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))

        setVariable('ActionSettingsRedo_Command', redoEnabled and '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "RedoChange()"]' or '')
        setVariable('ActionSettingsRedo_BgColor', redoEnabled and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('ActionSettingsRedo_TextColor', redoEnabled and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))

        setVariable('ActionSettingsReset_Command', resetEnabled and '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "ResetSession()"]' or '')
        setVariable('ActionSettingsReset_BgColor', resetEnabled and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('ActionSettingsReset_TextColor', resetEnabled and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))
    end

    function methods.updatePageButtons(tab)
        local pageCount = methods.getTabPageCount(tab)
        local multiPage = pageCount > 1
        local currentPage = methods.activePageIndex()

        setVariable('SettingsPageDisplayText', tostring(currentPage) .. '/' .. tostring(pageCount))
        setVariable('ActionSettingsPageCurrent_LabelText', SKIN:GetVariable('SettingsPageDisplayText', '1/1'))
        setVariable('ActionSettingsPagePrev_Command', multiPage and '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "PrevPage()"]' or '')
        setVariable('ActionSettingsPageNext_Command', multiPage and '[!CommandMeasure MeasureSettingsCommit "PlayUiClick()"][!CommandMeasure MeasureSettingsCommit "NextPage()"]' or '')
        setVariable('ActionSettingsPagePrev_BgColor', multiPage and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('ActionSettingsPagePrev_TextColor', multiPage and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))
        setVariable('ActionSettingsPageNext_BgColor', multiPage and SKIN:GetVariable('SettingsButtonBgColor', '') or SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('ActionSettingsPageNext_TextColor', multiPage and SKIN:GetVariable('SettingsButtonTextColor', '') or SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))
    end
end
