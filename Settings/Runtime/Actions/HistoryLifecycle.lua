return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local function refreshAfterStateRestore(restoreTargets)
    if restoreTargets and restoreTargets.Settings == true then
        if methods.refreshCurrentPageContent then
            methods.refreshCurrentPageContent()
        else
            methods.renderActivePage()
        end
    else
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
    end
end

function methods.UndoChange()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    local entry = table.remove(state.undoHistory)
    if not entry then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    state.redoHistory[#state.redoHistory + 1] = {
        label = entry.label,
        before = shallowCopy(entry.before),
        after = shallowCopy(entry.after),
        tabId = entry.tabId,
        beforeLayout = methods.copyLayoutSnapshot(entry.beforeLayout),
        afterLayout = methods.copyLayoutSnapshot(entry.afterLayout),
        layoutTargetIds = methods.copyLayoutTargetIds(entry.layoutTargetIds),
    }

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(entry.before, { suppressRender = true, skipFieldKeys = { 'startupAutoRun' } })

    if entry.beforeLayout then
        if entry.layoutTargetIds and #entry.layoutTargetIds > 0 then
            methods.restoreLayoutSnapshot(entry.beforeLayout, entry.layoutTargetIds)
        elseif entry.tabId then
            methods.restoreTabLayoutSnapshot(entry.tabId, entry.beforeLayout)
        end
    end

    refreshAfterStateRestore(restoreTargets)
end

function methods.RedoChange()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    local entry = table.remove(state.redoHistory)
    if not entry then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    state.undoHistory[#state.undoHistory + 1] = {
        label = entry.label,
        before = shallowCopy(entry.before),
        after = shallowCopy(entry.after),
        tabId = entry.tabId,
        beforeLayout = methods.copyLayoutSnapshot(entry.beforeLayout),
        afterLayout = methods.copyLayoutSnapshot(entry.afterLayout),
        layoutTargetIds = methods.copyLayoutTargetIds(entry.layoutTargetIds),
    }

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(entry.after, { suppressRender = true, skipFieldKeys = { 'startupAutoRun' } })

    if entry.afterLayout then
        if entry.layoutTargetIds and #entry.layoutTargetIds > 0 then
            methods.restoreLayoutSnapshot(entry.afterLayout, entry.layoutTargetIds)
        elseif entry.tabId then
            methods.restoreTabLayoutSnapshot(entry.tabId, entry.afterLayout)
        end
    end

    refreshAfterStateRestore(restoreTargets)
end

function methods.ResetSession()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    if not state.baselineSnapshot or not state.baselineLayoutSnapshot then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    local beforeSnapshot = methods.captureSnapshot()
    local layoutTargetIds = state.baselineLayoutTargetIds or methods.allLayoutTargetIds()
    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    if app.snapshotSignature(beforeSnapshot) == app.snapshotSignature(state.baselineSnapshot)
        and methods.layoutSnapshotSignature(beforeLayoutSnapshot) == methods.layoutSnapshotSignature(state.baselineLayoutSnapshot) then
        if methods.refreshRowsAndHistoryVisuals then
            methods.refreshRowsAndHistoryVisuals()
        else
            methods.renderActivePage()
        end
        return
    end

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(state.baselineSnapshot, { suppressRender = true, skipFieldKeys = { 'startupAutoRun' } })
    methods.restoreLayoutSnapshot(state.baselineLayoutSnapshot, layoutTargetIds)

    local afterSnapshot = methods.captureSnapshot()
    local afterLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    methods.pushHistory('Session reset', beforeSnapshot, {
        afterSnapshot = afterSnapshot,
        beforeLayout = beforeLayoutSnapshot,
        afterLayout = afterLayoutSnapshot,
        layoutTargetIds = layoutTargetIds,
    })

    refreshAfterStateRestore(restoreTargets)
end

function methods.ResetToDefaults()
    if methods.isLoadingVisible() then
        if methods.CancelPendingLoad() == false then
            return
        end
        methods.clearPendingRefreshState()
    end

    methods.clearPendingConfirmation()

    local resetFieldKeys = {}
    for _, fieldKey in ipairs(schema.trackedFieldKeys) do
        if fieldKey ~= 'startupAutoRun' then
            resetFieldKeys[#resetFieldKeys + 1] = fieldKey
        end
    end

    local defaultSnapshot, missingKeys = methods.loadDefaultSnapshot(resetFieldKeys)
    if not defaultSnapshot then
        logNotice('Settings default snapshot is incomplete: ' .. table.concat(missingKeys or {}, ', '))
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_SettingsDefaultsUnavailable',
                'Reset to defaults was canceled because the default data could not be read.'
            )
        end
        methods.renderActivePage()
        return
    end

    local beforeSnapshot = methods.captureSnapshot()
    local layoutTargetIds = methods.allLayoutTargetIds()
    local beforeLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    methods.closeDropdownInternal()

    local restoreTargets = methods.restoreSnapshot(defaultSnapshot, { suppressRender = true, fieldKeys = resetFieldKeys, skipFieldKeys = { 'startupAutoRun' } })
    methods.ResetAllSkinPositions()

    local afterSnapshot = methods.captureSnapshot()
    local afterLayoutSnapshot = methods.captureLayoutSnapshot(layoutTargetIds)

    methods.pushHistory('Reset all settings', beforeSnapshot, {
        afterSnapshot = afterSnapshot,
        beforeLayout = beforeLayoutSnapshot,
        afterLayout = afterLayoutSnapshot,
        layoutTargetIds = layoutTargetIds,
    })

    refreshAfterStateRestore(restoreTargets)
end

function methods.StartSettingsResponsiveLayoutTimer()
    if trim(SKIN:GetVariable('BlockHudSettingsVisible', '0')) ~= '1' then
        app.residentUpdate.SetDriver('Settings', 'runtime', false)
        return 0
    end
    app.residentUpdate.SetDriver('Settings', 'runtime', true)
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    return 0
end

function methods.StopSettingsResponsiveLayoutTimer()
    app.residentUpdate.SetDriver('Settings', 'runtime', false)
    return 0
end

function methods.ContinueSettingsResponsiveLayoutTimer()
    return methods.StartSettingsResponsiveLayoutTimer()
end
local function cleanupHiddenResidentUiState()
    methods.clearPendingConfirmation()
    if methods.closeDropdownInternal then
        methods.closeDropdownInternal()
    end
    if methods.clearDropdownVisualState then
        methods.clearDropdownVisualState()
    end
    if methods.clearPendingLoadState then
        methods.clearPendingLoadState()
    end
    if methods.clearPendingRefreshState then
        methods.clearPendingRefreshState()
    end
    if methods.clearVersionManagerLaunchPending then
        methods.clearVersionManagerLaunchPending({ render = false })
    end
    if methods.setLoadingVisible then
        methods.setLoadingVisible(false)

    end
    methods.StopSettingsResponsiveLayoutTimer()
    SKIN:Bang('!SetVariable', 'BlockHudSettingsModalAlertDeferredOpen', '0')
    methods.clearPendingJukeboxPlaybackSourceMode()
    methods.ResetUpdateJobs()
    SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLanguageSwitch', 'Stop 1')
end

function methods.ResumeSettingsResident()
    methods.setSettingsVisibleState(true)
    app.residentUpdate.ResumeSurface('Settings')
    methods.PreloadModalAlert()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
    methods.StartSettingsResponsiveLayoutTimer()
    methods.renderActivePage()
    SKIN:Bang('!Show', SKIN:GetVariable('CURRENTCONFIG'))
    SKIN:Bang('!Redraw')
    return 0
end

function methods.SuspendSettingsResident()
    methods.setSettingsVisibleState(false)
    cleanupHiddenResidentUiState()
    app.residentUpdate.SuspendSurface('Settings')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
    SKIN:Bang('!Redraw')
    return 0
end

function methods.RestoreSettingsResidentOnRefresh()
    if trim(SKIN:GetVariable('BlockHudSettingsVisible', '0')) == '1' then
        return methods.ResumeSettingsResident()
    end
    return methods.SuspendSettingsResident()
end
function methods.CloseSettings()
        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end
        methods.clearPendingConfirmation()
        methods.SuspendSettingsResident()
        SKIN:Bang('!Hide', SKIN:GetVariable('CURRENTCONFIG'))
    end

    function methods.PrepareForVersionSwitch()
        if methods.clearVersionManagerLaunchPending then
            methods.clearVersionManagerLaunchPending({ render = false })
        end
        SKIN:Bang('!SetVariable', 'SettingsVersionSwitchClose', '1')
        methods.setSettingsVisibleState(false)
        SKIN:Bang('!DeactivateConfig', SKIN:GetVariable('CURRENTCONFIG'))
        return true
    end

    function methods.HandleClose()
        app.residentUpdate.SuspendSurface('Settings')
        local versionSwitchClose = trim(SKIN:GetVariable('SettingsVersionSwitchClose', '0')) == '1'
        if versionSwitchClose then
            SKIN:Bang('!SetVariable', 'SettingsVersionSwitchClose', '0')
            if methods.clearVersionManagerLaunchPending then
                methods.clearVersionManagerLaunchPending({ render = false })
            end
            methods.clearPendingLoadState()
            methods.clearPendingRefreshState()
            methods.setLoadingVisible(false)
            methods.setSettingsVisibleState(false)
            return 0
        end
        methods.clearPendingLoadState()
        methods.clearPendingRefreshState()
        methods.setLoadingVisible(false)
        methods.setSettingsVisibleState(false)
        return 0
    end

    function methods.Initialize()
        methods.ResetUpdateJobs()







        methods.syncPowerShellProgramPath()



        methods.ensurePaths()







        methods.applyTheme(trim(SKIN:GetVariable('SettingsThemeMode', 'light')))







        local settingsVisibleOnInitialize = trim(SKIN:GetVariable('BlockHudSettingsVisible', '0')) == '1'
        state.contentMode = trim(SKIN:GetVariable('SettingsContentMode', '0')) == '1'

        setVariable('SettingsContentMode', state.contentMode and '1' or '0')

        state.currentTabIndex = state.contentMode and state.contentTabIndex or state.normalTabIndex







        state.currentPageByTab = {}







        for index = 1, math.max(state.tabCount or 1, state.contentTabCount or 1) do







            state.currentPageByTab['normal:' .. tostring(index)] = 1
            state.currentPageByTab['content:' .. tostring(index)] = 1







        end







        state.currentInputFieldKey = nil
        state.sharedInputActive = false
        state.currentVisibleRows = {}







        state.currentFieldKeyByRow = {}







        state.activeDropdownFieldKey = nil







        state.activeDropdownRowIndex = 0







        state.activeDropdownPageIndex = 1







        state.currentDropdownOptionBySlot = {}







        state.pendingConfirmActionKey = nil







        state.undoHistory = {}







        methods.syncMinecraftSkinDraftFromCanonical()







        state.redoHistory = {}







        methods.clearMemoryCaches()







        methods.clearPendingLoadState()



        methods.clearPendingRefreshState()



        methods.setLoadingVisible(false)

        local pendingSettingsRouteApplied = methods.consumePendingSettingsRoute()
        if pendingSettingsRouteApplied then
            settingsVisibleOnInitialize = true
        end

        if not settingsVisibleOnInitialize then
            methods.SuspendSettingsResident()
            return 0
        end






        local computerInfoReady = methods.RestorePersistentCache('computerInfo')







        if computerInfoReady then







            methods.hydrateStartupAutoRunFieldFromCache()







        end







        methods.captureBaselineState()







        methods.clearDropdownVisualState()







        methods.renderActivePage()







        if not computerInfoReady then







            methods.ScheduleDropdownDataLoad('startupAutoRun', 0, 'computerInfo', false, {



                loadingText = methods.localize('Settings_Loading_ComputerInfo_FirstRun', 'Loading computer data\\nfor option setup.\\n(*May take about 1-2 minutes.)'),



                delayTicks = 8,



            })







        end







    end
end
