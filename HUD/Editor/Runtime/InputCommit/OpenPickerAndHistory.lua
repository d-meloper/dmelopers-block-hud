-- Split from Editor\InputCommit.lua lines 3983-5262.
local function syncInventoryEditorModeBadge(openValue)



    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))



    if rootConfig == '' then



        return



    end



    local inventoryConfig = rootConfig .. '\\HUD\\Inventory'



    if not EditorIsRainmeterConfigActive(inventoryConfig) then

        return

    end



    local hiddenValue = openValue and '0' or '1'

    SKIN:Bang('!SetVariable', 'EditorDraftMeta_EditorOpen', openValue and '1' or '0', inventoryConfig)



    SKIN:Bang('!SetVariable', 'EditorModeBadgeHidden', hiddenValue, inventoryConfig)



    SKIN:Bang('!UpdateMeter', 'MeterEditorModeBadgeBackground', inventoryConfig)



    SKIN:Bang('!UpdateMeter', 'MeterEditorModeBadgeLabel', inventoryConfig)



    SKIN:Bang('!Redraw', inventoryConfig)



end



local function setEditorOpen(openValue)



    writeDraftMeta('EditorOpen', openValue and '1' or '0')



    syncInventoryEditorModeBadge(openValue)



    if openValue then



        touchDraftSession(true)



    else



        ensureService().ClearProgramPickerCache(editorRoot)



        writeDraftMeta('HeartbeatClockMs', 0)



        sessionHeartbeatClockMs = -1



    end



end



local function setDragState(active, source, x, y)



    dragOutsideClockMs = -1



    local dragActive = active and '1' or '0'

    local dragSource = tostring(source or '')

    local dragX = tostring(x or 0)

    local dragY = tostring(y or 0)



    if trim(SKIN:GetVariable(draftMetaVariableName('DragActive'), '0')) ~= dragActive then

        writeDraftMeta('DragActive', dragActive)

    end



    if trim(SKIN:GetVariable(draftMetaVariableName('DragSource'), '')) ~= dragSource then

        writeDraftMeta('DragSource', dragSource)

    end



    if trim(SKIN:GetVariable(draftMetaVariableName('DragX'), '0')) ~= dragX then

        writeDraftMeta('DragX', dragX)

    end



    if trim(SKIN:GetVariable(draftMetaVariableName('DragY'), '0')) ~= dragY then

        writeDraftMeta('DragY', dragY)

    end



end



local function clearDragState()



    setDragState(false, '', 0, 0)



end



getDraftMeta = function()



    return ensureService().ReadDraftMeta(editorRoot)



end



local function isPickerModalOpen()



    return getDraftMeta().PickerModalOpen == true



end



function SetPickerModalOpen(value)



    local openValue = value == true or value == 'true' or value == 1 or value == '1'



    writeDraftMeta('PickerModalOpen', openValue and '1' or '0')



end



local function resolvePickerRun(kind)



    return PICKER_RUN_BY_KIND[trim(kind or '')]



end



local function clearPickerRunState(kind)



    local pickerRun = resolvePickerRun(kind)



    if not pickerRun then



        return false



    end



    SKIN:Bang('!SetVariable', pickerRun.runningVar, '0')



    SKIN:Bang('!SetVariable', pickerRun.restartVar, '0')



    return true



end



local function startPickerRun(kind)



    local pickerRun = resolvePickerRun(kind)



    if not pickerRun then



        logMessage('Warning', 'Unknown picker run kind: ' .. tostring(kind))



        return



    end



    SKIN:Bang('!SetVariable', pickerRun.runningVar, '1')



    SKIN:Bang('!SetVariable', pickerRun.restartVar, '0')



    SetPickerModalOpen(1)



    SKIN:Bang('!CommandMeasure', pickerRun.measure, 'Run')



end



function RequestPickerRestart(kind)



    local pickerRun = resolvePickerRun(kind)



    if not pickerRun then



        logMessage('Warning', 'Unknown picker restart kind: ' .. tostring(kind))



        return



    end



    local pickerWasModalOpen = isPickerModalOpen()



    SetPickerModalOpen(1)



    if trim(SKIN:GetVariable(pickerRun.runningVar, '0')) == '1' then



        if not pickerWasModalOpen then



            clearPickerRunState(kind)



            logMessage('Warning', 'Recovered stale editor picker state before restart: ' .. tostring(kind))



        else



            SKIN:Bang('!SetVariable', pickerRun.restartVar, '1')



            SKIN:Bang('!CommandMeasure', pickerRun.measure, 'Kill')



            return



        end



    end



    startPickerRun(kind)



end



function HandlePickerFinish(kind)



    local pickerRun = resolvePickerRun(kind)



    if not pickerRun then



        logMessage('Warning', 'Unknown picker finish kind: ' .. tostring(kind))



        return false



    end



    if trim(SKIN:GetVariable(pickerRun.restartVar, '0')) == '1' then



        startPickerRun(kind)



        return true



    end



    SKIN:Bang('!SetVariable', pickerRun.runningVar, '0')



    SKIN:Bang('!SetVariable', pickerRun.restartVar, '0')



    SetPickerModalOpen(0)



    return false



end



local function getSelectedRecord()



    local meta = getDraftMeta()



    if not meta.SelectedSource or meta.SelectedX < 1 or meta.SelectedY < 1 then



        return nil



    end



    return ensureService().GetDraftSlotRecord(editorRoot, meta.SelectedSource, meta.SelectedX, meta.SelectedY)



end

EditorLifecycle.FolderCountState = EditorLifecycle.FolderCountState or { Generation = 0, Expected = nil, Phase = 'idle' }

function EditorLifecycle.SelectedRecordMatchesFolderCountExpected(record)
    local expected = EditorLifecycle.FolderCountState.Expected
    return record and expected
        and record.Source == expected.Source
        and tonumber(record.x) == expected.X
        and tonumber(record.y) == expected.Y
        and trim(record.ExecPath) == expected.Path
        and normalizeActionType(record.ActionType) == 'folder'
        and normalizeFolderCountSync(record.FolderCountSync, record.ActionType) == '1'
end

function EditorLifecycle.SplitFolderParent(path)
    local normalized = trim(path):gsub('/', '\\')
    normalized = normalized:gsub('\\+$', '')
    if normalized:match('^%a:$') then
        return nil, nil, 'root'
    end
    if normalized:sub(1, 2) == '\\\\' then
        local componentCount = 0
        for _ in normalized:sub(3):gmatch('[^\\]+') do
            componentCount = componentCount + 1
        end
        if componentCount == 2 then
            return nil, nil, 'root'
        end
        if componentCount < 2 then
            return nil, nil
        end
    end
    local parent, name = normalized:match('^(.*\\)([^\\]+)$')
    if not parent or not name or name == '' then
        return nil, nil
    end
    return parent, name, 'parent'
end

function EditorLifecycle.NormalizeFolderPathForCompare(path)
    return trim(path):gsub('/', '\\'):gsub('\\+$', ''):lower()
end

function EditorLifecycle.BeginFolderCountRefresh()
    local state = EditorLifecycle.FolderCountState
    local expected = state.Expected
    if not expected or expected.Generation ~= state.Generation then
        return false
    end
    state.Phase = 'reset'
    local callback = string.format('[!CommandMeasure MeasureInputCommit "HandleFolderCountResult(%d, \'reset\')"]', state.Generation)
    SKIN:Bang('!SetOption', 'MeasureEditorFolderFileCount', 'OnUpdateAction', callback)
    SKIN:Bang('!SetOption', 'MeasureEditorFolderFileCount', 'Folder', '')
    SKIN:Bang('!EnableMeasure', 'MeasureEditorFolderFileCount')
    SKIN:Bang('!UpdateMeasure', 'MeasureEditorFolderFileCount')
    return true
end

function RefreshFolderCountSync()
    local state = EditorLifecycle.FolderCountState
    local record = getSelectedRecord()
    state.Generation = state.Generation + 1
    state.Expected = nil
    state.Phase = 'preflight'
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderPreflight')
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderPreflightName')
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderRootPreflight')
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderRootPreflightPath')
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderFileCount')
    SKIN:Bang('!SetVariable', 'EditorFolderCountGeneration', tostring(state.Generation))
    EditorLifecycle.SetFolderCountUnavailable(false)

    if not record or not record.Populated
        or normalizeActionType(record.ActionType) ~= 'folder'
        or normalizeFolderCountSync(record.FolderCountSync, record.ActionType) ~= '1' then
        return false
    end

    local service = ensureService()
    if service.IsReservedHotbarSlot(record.Source, record.x, record.y) then
        return false
    end

    local path = trim(record.ExecPath)
    local parent, name, preflightMode = EditorLifecycle.SplitFolderParent(path)
    if path == '' or not preflightMode then
        setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', '0')
        EditorLifecycle.SetFolderCountUnavailable(true)
        SKIN:Bang('!Redraw')
        return false
    end

    state.Expected = {
        Generation = state.Generation,
        Source = record.Source,
        X = tonumber(record.x),
        Y = tonumber(record.y),
        Path = path,
        Parent = parent,
        Name = name,
        PreflightMode = preflightMode,
    }
    SKIN:Bang('!SetVariable', 'EditorFolderCountTargetPath', path)
    if preflightMode == 'root' then
        local callback = string.format('[!UpdateMeasure MeasureEditorFolderRootPreflightPath][!CommandMeasure MeasureInputCommit "HandleFolderRootPreflight(%d)"]', state.Generation)
        SKIN:Bang('!SetOption', 'MeasureEditorFolderRootPreflight', 'FinishAction', callback)
        SKIN:Bang('!EnableMeasure', 'MeasureEditorFolderRootPreflight')
        SKIN:Bang('!EnableMeasure', 'MeasureEditorFolderRootPreflightPath')
        SKIN:Bang('!UpdateMeasure', 'MeasureEditorFolderRootPreflight')
    else
        SKIN:Bang('!SetVariable', 'EditorFolderCountParentPath', parent)
        SKIN:Bang('!SetVariable', 'EditorFolderCountFolderName', name)
        local callback = string.format('[!UpdateMeasure MeasureEditorFolderPreflightName][!CommandMeasure MeasureInputCommit "HandleFolderCountPreflight(%d)"]', state.Generation)
        SKIN:Bang('!SetOption', 'MeasureEditorFolderPreflight', 'FinishAction', callback)
        SKIN:Bang('!EnableMeasure', 'MeasureEditorFolderPreflight')
        SKIN:Bang('!EnableMeasure', 'MeasureEditorFolderPreflightName')
        SKIN:Bang('!UpdateMeasure', 'MeasureEditorFolderPreflight')
    end
    return true
end

function HandleFolderCountPreflight(generation)
    local state = EditorLifecycle.FolderCountState
    local expected = state.Expected
    if not expected or tonumber(generation) ~= expected.Generation or expected.Generation ~= state.Generation then
        return false
    end
    local record = getSelectedRecord()
    if not EditorLifecycle.SelectedRecordMatchesFolderCountExpected(record) then
        return false
    end
    local nameMeasure = SKIN:GetMeasure('MeasureEditorFolderPreflightName')
    local actualName = nameMeasure and trim(nameMeasure:GetStringValue()) or ''
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderPreflight')
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderPreflightName')
    if actualName:lower() ~= expected.Name:lower() then
        setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', '0')
        EditorLifecycle.SetFolderCountUnavailable(true)
        SKIN:Bang('!Redraw')
        return false
    end
    EditorLifecycle.SetFolderCountUnavailable(false)
    return EditorLifecycle.BeginFolderCountRefresh()
end

function HandleFolderRootPreflight(generation)
    local state = EditorLifecycle.FolderCountState
    local expected = state.Expected
    if not expected or expected.PreflightMode ~= 'root'
        or tonumber(generation) ~= expected.Generation or expected.Generation ~= state.Generation then
        return false
    end
    local record = getSelectedRecord()
    if not EditorLifecycle.SelectedRecordMatchesFolderCountExpected(record) then
        return false
    end
    local pathMeasure = SKIN:GetMeasure('MeasureEditorFolderRootPreflightPath')
    local actualPath = pathMeasure and pathMeasure:GetStringValue() or ''
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderRootPreflight')
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderRootPreflightPath')
    if EditorLifecycle.NormalizeFolderPathForCompare(actualPath) ~= EditorLifecycle.NormalizeFolderPathForCompare(expected.Path) then
        setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', '0')
        EditorLifecycle.SetFolderCountUnavailable(true)
        SKIN:Bang('!Redraw')
        return false
    end
    EditorLifecycle.SetFolderCountUnavailable(false)
    return EditorLifecycle.BeginFolderCountRefresh()
end

function HandleFolderCountResult(generation, phase)
    local state = EditorLifecycle.FolderCountState
    local expected = state.Expected
    if not expected or tonumber(generation) ~= expected.Generation or expected.Generation ~= state.Generation then
        return false
    end
    local record = getSelectedRecord()
    if not EditorLifecycle.SelectedRecordMatchesFolderCountExpected(record) then
        return false
    end
    local callbackPhase = trim(phase)
    if callbackPhase ~= state.Phase then
        return false
    end
    if callbackPhase == 'reset' then
        state.Phase = 'count'
        local callback = string.format('[!CommandMeasure MeasureInputCommit "HandleFolderCountResult(%d, \'count\')"]', state.Generation)
        SKIN:Bang('!SetOption', 'MeasureEditorFolderFileCount', 'OnUpdateAction', callback)
        SKIN:Bang('!SetOption', 'MeasureEditorFolderFileCount', 'Folder', expected.Path)
        SKIN:Bang('!UpdateMeasure', 'MeasureEditorFolderFileCount')
        return true
    end
    if callbackPhase ~= 'count' then
        return false
    end
    local measure = SKIN:GetMeasure('MeasureEditorFolderFileCount')
    local count = measure and tonumber(measure:GetValue()) or 0
    SKIN:Bang('!DisableMeasure', 'MeasureEditorFolderFileCount')
    count = math.max(0, math.floor(count or 0))
    setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', tostring(count))
    EditorLifecycle.SetFolderCountUnavailable(false)
    SKIN:Bang('!Redraw')
    return true
end

local function clearPreparedInputTarget()



    SKIN:Bang('!SetVariable', 'EditorPendingInputTarget', '')



    SKIN:Bang('!SetVariable', 'EditorPendingInputSource', '')



    SKIN:Bang('!SetVariable', 'EditorPendingInputX', 0)



    SKIN:Bang('!SetVariable', 'EditorPendingInputY', 0)



    SKIN:Bang('!SetVariable', 'EditorPendingInputSection', '')



    SKIN:Bang('!SetVariable', 'EditorPendingInputPairX', '')



    SKIN:Bang('!SetVariable', 'EditorPendingInputPairY', '')



end



local function getPreparedInputLocator(target)



    local normalizedTarget = trim(target)



    local preparedTarget = trim(SKIN:GetVariable('EditorPendingInputTarget', ''))



    if normalizedTarget ~= '' and preparedTarget ~= '' and preparedTarget ~= normalizedTarget then



        return nil



    end



    local source = trim(SKIN:GetVariable('EditorPendingInputSource', ''))



    local x = tonumber(trim(SKIN:GetVariable('EditorPendingInputX', '0')))



    local y = tonumber(trim(SKIN:GetVariable('EditorPendingInputY', '0')))



    if source == '' or not x or not y or x < 1 or y < 1 then



        return nil



    end



    return {



        Source = source,



        X = math.floor(x),



        Y = math.floor(y),



        Section = trim(SKIN:GetVariable('EditorPendingInputSection', '')),



    }



end



local function readPreparedInputPair(axis)



    if axis == 'x' then



        return trim(SKIN:GetVariable('EditorPendingInputPairX', ''))



    end



    return trim(SKIN:GetVariable('EditorPendingInputPairY', ''))



end

local function cloneSelectionState(selection)



    if not selection then



        return nil



    end



    return {



        Source = selection.Source,



        X = selection.X,



        Y = selection.Y,



        Section = selection.Section,



    }



end



local function cloneSessionSnapshot(snapshot)



    if not snapshot then



        return nil



    end



    local clonedRecords = {



        hotbar = {},



        inventory = {},



    }



    for _, source in ipairs({ 'hotbar', 'inventory' }) do



        for _, record in ipairs(snapshot.Records[source] or {}) do



            clonedRecords[source][#clonedRecords[source] + 1] = cloneRecord(record)



        end



    end



    return {



        Selection = cloneSelectionState(snapshot.Selection),



        Records = clonedRecords,



        ImageAdjustments = cloneImageAdjustmentState(snapshot.ImageAdjustments or {}),



    }



end



local function getSnapshotSelection(meta)



    if not meta.SelectedSource or meta.SelectedX < 1 or meta.SelectedY < 1 then



        return nil



    end



    return {



        Source = meta.SelectedSource,



        X = meta.SelectedX,



        Y = meta.SelectedY,



        Section = meta.SelectedSection,



    }



end



local function captureDraftSnapshot()



    local service = ensureService()



    local meta = getDraftMeta()



    local snapshot = {



        Selection = getSnapshotSelection(meta),



        Records = {



            hotbar = {},



            inventory = {},



        },



        ImageAdjustments = cloneImageAdjustmentState(ensureDraftImageAdjustments()),



    }



    for _, source in ipairs({ 'hotbar', 'inventory' }) do



        for _, record in ipairs(service.BuildSourceRecords(editorRoot, source, true)) do



            snapshot.Records[source][#snapshot.Records[source] + 1] = cloneRecord(record)



        end



    end



    return snapshot



end



local function buildSnapshotSignature(snapshot)



    local parts = {}



    if snapshot.Selection then



        parts[#parts + 1] = string.format(



            'selection:%s:%d:%d:%q',



            snapshot.Selection.Source or '',



            snapshot.Selection.X or 0,



            snapshot.Selection.Y or 0,



            snapshot.Selection.Section or ''



        )



    else



        parts[#parts + 1] = 'selection:-'



    end



    for _, source in ipairs({ 'hotbar', 'inventory' }) do



        for _, record in ipairs(snapshot.Records[source] or {}) do



            parts[#parts + 1] = string.format(



                '%s:%d:%d:%q:%q:%q:%q:%q:%q:%d:%s',



                source,



                record.x or 0,



                record.y or 0,



                record.ImageKey or '',



                record.ItemName or '',



                record.ExecPath or '',

                normalizeConfirmBeforeRun(record.ConfirmBeforeRun),

                normalizeActionType(record.ActionType),

                normalizeFolderCountSync(record.FolderCountSync, record.ActionType),



                record.Qty or 0,



                record.Populated == true and '1' or '0'



            )



        end



    end



    local imageAdjustments = snapshot.ImageAdjustments or {}



    local imageAdjustKeys = {}



    for imageKey in pairs(imageAdjustments) do



        imageAdjustKeys[#imageAdjustKeys + 1] = imageKey



    end



    table.sort(imageAdjustKeys)



    for _, imageKey in ipairs(imageAdjustKeys) do



        local adjustment = imageAdjustments[imageKey] or {}



        parts[#parts + 1] = string.format(



            'imageAdjust:%q:%d:%d:%d',



            imageKey,



            tonumber(adjustment.OffsetX) or 0,



            tonumber(adjustment.OffsetY) or 0,



            tonumber(adjustment.SizeOffset) or 0



        )



    end



    return table.concat(parts, '|')



end



local function isCurrentSnapshotAtSessionBaseline(snapshot)



    if not sessionBaselineSnapshot then



        return true



    end



    return buildSnapshotSignature(snapshot or captureDraftSnapshot()) == buildSnapshotSignature(sessionBaselineSnapshot)



end



local function updateHistoryButtonState(snapshot)



    local undoEntry = undoHistory[#undoHistory]



    local redoEntry = redoHistory[#redoHistory]



    local canUndo = undoEntry ~= nil



    local canRedo = redoEntry ~= nil



    local canReset = not isCurrentSnapshotAtSessionBaseline(snapshot)



    applyActionContract('ActionUndo', canUndo, '[!CommandMeasure MeasureInputCommit "UndoEditorChange()"]', locRef('Editor_Action_Undo'))



    applyActionContract('ActionRedo', canRedo, '[!CommandMeasure MeasureInputCommit "RedoEditorChange()"]', locRef('Editor_Action_Redo'))



    applyActionContract('ActionReset', canReset, '[!CommandMeasure MeasureInputCommit "ResetEditorSession()"]', locRef('Editor_Action_Reset'))



    ApplyEditorStaticLocalizationTextFits()



    for _, meterName in ipairs({



        'MeterTopBarUndoButtonBackground',



        'MeterTopBarUndoButtonLabel',



        'MeterTopBarRedoButtonBackground',



        'MeterTopBarRedoButtonLabel',



        'MeterTopBarResetButtonBackground',



        'MeterTopBarResetButtonLabel',



    }) do



        SKIN:Bang('!UpdateMeter', meterName)



    end



    SKIN:Bang('!Redraw')



end



local function syncSessionDirtyState(snapshot)



    setDirty(not isCurrentSnapshotAtSessionBaseline(snapshot))



    updateHistoryButtonState(snapshot)



end



local function initializeSessionHistory(force)



    if sessionHistoryInitialized and not force then



        syncSessionDirtyState()



        return



    end



    undoHistory = {}



    redoHistory = {}



    sessionBaselineSnapshot = captureDraftSnapshot()



    sessionHistoryInitialized = true



    syncSessionDirtyState(sessionBaselineSnapshot)



end



local function clearSessionHistory()



    undoHistory = {}



    redoHistory = {}



    sessionBaselineSnapshot = nil



    sessionHistoryInitialized = false



    updateHistoryButtonState()



end



local function rememberDraftChange(label, beforeSnapshot)



    local afterSnapshot = captureDraftSnapshot()



    if buildSnapshotSignature(beforeSnapshot) == buildSnapshotSignature(afterSnapshot) then



        syncSessionDirtyState(afterSnapshot)



        return false



    end



    undoHistory[#undoHistory + 1] = {



        Label = label or L('Editor_History_Default', '변경'),



        Before = cloneSessionSnapshot(beforeSnapshot),



        After = cloneSessionSnapshot(afterSnapshot),



    }



    redoHistory = {}



    syncSessionDirtyState(afterSnapshot)



    return true



end

function ToggleFolderCountSyncUi()
    local record = getSelectedRecord()
    if not record or not record.Populated or normalizeActionType(record.ActionType) ~= 'folder' then
        return false
    end
    local service = ensureService()
    if service.IsReservedHotbarSlot(record.Source, record.x, record.y) then
        return false
    end
    playUiClick()
    local beforeSnapshot = captureDraftSnapshot()
    record.FolderCountSync = normalizeFolderCountSync(record.FolderCountSync, record.ActionType) == '1' and '0' or '1'
    writeDraftRecord(record)
    setSelection(record)
    if rememberDraftChange(L('Editor_History_FolderCountSync', 'Folder file count link changed'), beforeSnapshot) then
        refreshDraftItemConsumersLite()
    end
    return true
end
