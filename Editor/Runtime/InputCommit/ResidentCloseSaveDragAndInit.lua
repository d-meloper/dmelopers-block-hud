-- Split from Editor\InputCommit.lua lines 8665-9686.
local function closeOpenDraftSessionForResidentSuspend()
    local service = ensureService()
    local meta = service.ReadDraftMetaOnly(editorRoot)
    if not meta.EditorOpen then
        return
    end

    if tryCommitClose('Editor draft autosaved on resident suspend.') and closeCommitChanged then
        refreshConsumersAfterEditorClose()
    end
end

function StartEditorResponsiveLayoutTimer()
    if not isEditorVisibleStateEnabled() then
        ensureResidentUpdateController().SetDriver('Editor', 'runtime', false)
        return 0
    end
    ensureResidentUpdateController().SetDriver('Editor', 'runtime', true)
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    return 0
end

function StopEditorResponsiveLayoutTimer()
    ensureResidentUpdateController().SetDriver('Editor', 'runtime', false)
    return 0
end

function ContinueEditorResponsiveLayoutTimer()
    return StartEditorResponsiveLayoutTimer()
end

local function refreshEditorResidentVisualState()
    applyEditorTheme(trim(SKIN:GetVariable('SettingsThemeMode', 'light')))
    updateHistoryButtonState()
    syncItemActionState(currentTarget)
    syncEditorControlGate()
    syncPageDisplay()
    refreshThemeVisuals()
end

function ResumeEditorResident(allowConsumerMirror)
    closeDiscardApplied = false
    closeRequestMode = nil
    closeCommitChanged = false
    ensureResidentUpdateController().ResumeSurface('Editor')
    PreloadModalAlert()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
    StartEditorResponsiveLayoutTimer()
    cancelDeferredInitialize()
    setEditorLoadingVisible(false)
    clearPickerRunState('path')
    clearPickerRunState('image')
    SetPickerModalOpen(0)
    clearDragState()
    local previousMirrorState = consumerMirroringSuspended
    consumerMirroringSuspended = allowConsumerMirror == false
    OpenEditorDraftSession()
    consumerMirroringSuspended = previousMirrorState
    refreshEditorResidentVisualState()
    SKIN:Bang('!Redraw')
end

function SuspendEditorResident()
    cancelDeferredInitialize()
    setEditorLoadingVisible(false)
    clearPickerRunState('path')
    clearPickerRunState('image')
    SetPickerModalOpen(0)
    clearDragState()
    local previousMirrorState = consumerMirroringSuspended
    consumerMirroringSuspended = true
    closeOpenDraftSessionForResidentSuspend()
    consumerMirroringSuspended = previousMirrorState
    StopEditorResponsiveLayoutTimer()
    ensureResidentUpdateController().SuspendSurface('Editor')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
    SKIN:Bang('!Redraw')
end

function RestoreEditorResidentOnRefresh()
    if isEditorVisibleStateEnabled() then
        ResumeEditorResident(false)
        return
    end

    SuspendEditorResident()
end
function HandleClose(reason)






    if closeDiscardApplied then



        return



    end



    if deferredInitRequested then



        cancelDeferredInitialize()



        setEditorLoadingVisible(false)



        discardDraftSession(true)



        return



    end



    local allowConsumerRefresh = trim(reason) ~= 'rainmeter-close'

    local requestedMode = closeRequestMode



    closeRequestMode = nil



    if requestedMode == 'editor' then



        if tryCommitClose('Editor draft autosaved on close.') and closeCommitChanged and allowConsumerRefresh then

            refreshConsumersAfterEditorClose()



        end



        return



    end



    if tryCommitClose('Editor draft autosaved on close.') and closeCommitChanged and allowConsumerRefresh then

            refreshConsumersAfterEditorClose()



    end



end



function CloseEditorDiscardDraft()



    local discarded = discardDraftSession(true)

    if discarded and type(CleanupEditorPixelationImagesForCurrentItems) == 'function' then

        CleanupEditorPixelationImagesForCurrentItems()

    end

    return discarded



end



function CloseEditor()



    if closeDiscardApplied or closeRequestMode or isPickerModalOpen() then



        return



    end



    closeRequestMode = 'editor'



    local committed = tryCommitClose('Editor draft autosaved on close.')



    closeRequestMode = nil



    if not committed then



        return



    end



    if closeCommitChanged then



        refreshConsumersAfterEditorClose()



    end



    setEditorVisibleState(false)



    SuspendEditorResident()



    SKIN:Bang('!Hide', SKIN:GetVariable('CURRENTCONFIG'))



end



function UndoEditorChange()



    playUiClick()



    local entry = table.remove(undoHistory)



    if not entry then



        syncSessionDirtyState()



        return



    end



    redoHistory[#redoHistory + 1] = entry



    restoreDraftSnapshot(entry.Before)



    persistDraftImageAdjustments()



    syncSessionDirtyState()



    refreshDraftItemConsumersLite()



end



function RedoEditorChange()



    playUiClick()



    local entry = table.remove(redoHistory)



    if not entry then



        syncSessionDirtyState()



        return



    end



    undoHistory[#undoHistory + 1] = entry



    restoreDraftSnapshot(entry.After)



    persistDraftImageAdjustments()



    syncSessionDirtyState()



    refreshDraftItemConsumersLite()



end



function ResetEditorSession()



    playUiClick()



    if not sessionBaselineSnapshot then



        syncSessionDirtyState()



        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local targetSnapshot = cloneSessionSnapshot(sessionBaselineSnapshot)



    if buildSnapshotSignature(beforeSnapshot) == buildSnapshotSignature(targetSnapshot) then



        syncSessionDirtyState()



        return



    end



    undoHistory[#undoHistory + 1] = {



        Label = L('Editor_History_SessionReset', '세션 초기화'),



        Before = cloneSessionSnapshot(beforeSnapshot),



        After = cloneSessionSnapshot(targetSnapshot),



    }



    redoHistory = {}



    restoreDraftSnapshot(targetSnapshot)



    persistDraftImageAdjustments()



    syncSessionDirtyState()



    refreshDraftItemConsumersLite()



end



function SaveAllDraftChanges()



    local wasRepaired, repairLogs = normalizeInvalidDraftChanges()



    if wasRepaired then



        for _, repairLog in ipairs(repairLogs) do



            logMessage('Warning', 'Draft auto-repaired before save: ' .. repairLog)



        end



    end



    if not writePersistedFromDraft() then

        return false

    end



    setDirty(false)



    clearDragState()



    applySnapshotToDraft()



    setEditorOpen(true)



    if currentTarget then



        local refreshed = ensureService().GetPersistedSlotRecord(editorRoot, currentTarget.Source, currentTarget.x, currentTarget.y)



        if refreshed and refreshed.Populated then



            writeDraftRecord(refreshed)



            setSelection(refreshed)



        end



    end

    refreshDraftItemConsumersLite()



    logMessage('Notice', 'Editor draft saved.')



    return true



end

function BeginDrag(source, x, y)



    local service = ensureService()



    local record = service.GetDraftSlotRecord(editorRoot, source, x, y)



    if not record or not record.Populated or service.IsReservedHotbarSlot(source, x, y) then



        return



    end



    if not isCurrentTargetSlot(record.Source, record.x, record.y) then



        setSelection(record)



    end



    setDragState(true, source, x, y)



    refreshDragConsumersLite()



end



local function restoreDragSourceSelection(meta)



    local sourceMeta = meta or getDraftMeta()



    if not sourceMeta.DragSource then



        return



    end



    local record = ensureService().GetDraftSlotRecord(editorRoot, sourceMeta.DragSource, sourceMeta.DragX, sourceMeta.DragY)



    if record and record.Populated and not isCurrentTargetSlot(record.Source, record.x, record.y) then



        setSelection(record)



    end



end



function CancelDrag()



    local meta = getDraftMeta()



    restoreDragSourceSelection(meta)



    clearDragState()



    refreshDragConsumersLite()



end



function CommitDragTo(destinationSource, destinationX, destinationY)



    local service = ensureService()



    local meta = getDraftMeta()



    if not meta.DragActive or not meta.DragSource then



        return



    end



    if service.IsReservedHotbarSlot(destinationSource, destinationX, destinationY) then



        restoreDragSourceSelection(meta)



        clearDragState()



        refreshDragConsumersLite()



        return



    end



    if not service.IsValidCoord(destinationSource, destinationX, destinationY, true) then



        restoreDragSourceSelection(meta)



        clearDragState()



        refreshDragConsumersLite()



        return



    end



    local sourceRecord = service.GetDraftSlotRecord(editorRoot, meta.DragSource, meta.DragX, meta.DragY)



    if not sourceRecord or not sourceRecord.Populated then



        restoreDragSourceSelection(meta)



        clearDragState()



        refreshDragConsumersLite()



        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local moved = sourceRecord



    if not (sourceRecord.Source == destinationSource and sourceRecord.x == destinationX and sourceRecord.y == destinationY) then



        moved = moveDraftRecord(sourceRecord, destinationSource, destinationX, destinationY)



    end



    clearDragState()



    setSelection(moved)



    rememberDraftChange(L('Editor_History_ItemMove', '아이템 이동'), beforeSnapshot)



    refreshDragConsumersLite()



end



local function StepEditorPage(delta)



    local pageCount = tonumber(trim(SKIN:GetVariable('EditorPageCount', '2'))) or 2



    if pageCount < 1 then



        pageCount = 1



    end



    local current = tonumber(trim(SKIN:GetVariable('EditorPageIndex', '1'))) or 1



    current = math.floor(current)



    local nextPage = (((current - 1) + tonumber(delta or 0)) % pageCount) + 1



    local nextPageText = tostring(nextPage)



    SKIN:Bang('!SetVariable', 'EditorPageIndex', nextPageText)



    writeDraftMeta('PageIndex', nextPageText)



    syncPageDisplay()



    refreshThemeVisuals()



end



function PrevEditorPage()



    playUiClick()



    StepEditorPage(-1)



end



function NextEditorPage()



    playUiClick()



    StepEditorPage(1)



end

function ConsumeNoSelectionOverlayInput()



    return 0



end




function PreloadModalAlert()
    return ensureModalAlertBridge().Preload(editorModalAlertHost())
end

function OpenPendingModalAlert()
    return ensureModalAlertBridge().OpenPending(editorModalAlertHost())
end

function OpenModalAlertLogFolder(token)
    return ensureModalAlertBridge().OpenLogFolder(editorModalAlertHost(), token)
end

function ShowEditorActionAlert(level, summaryKey, fallback)
    return showEditorModalAlert(level or 'error', summaryKey or 'ModalAlert_EditorActionFailed', fallback or 'The Editor action could not be completed.')
end

function ReportEditorActionError(message, summaryKey, fallback)
    return logEditorErrorAndAlert(message, summaryKey or 'ModalAlert_EditorActionFailed', fallback or 'The Editor action could not be completed.')
end
function Initialize()



    syncReservedSlotLabel()



    syncPowerShellProgramPath()



    local service = ensureService()



    syncReservedSlotPersistence()



    service.ClearProgramPickerCache(editorRoot)



    applyEditorTheme(trim(SKIN:GetVariable('SettingsThemeMode', 'light')))



    ApplyEditorStaticLocalizationTextFits()



    local pageCount = tonumber(trim(SKIN:GetVariable('EditorPageCount', '2'))) or 2



    if pageCount < 1 then



        pageCount = 1



    end



    local pageIndex = 1



    if service.IsDraftOpen(editorRoot) then



        local storedPageIndex = tonumber(trim(SKIN:GetVariable('EditorDraftMeta_PageIndex', '1'))) or 1



        storedPageIndex = math.floor(storedPageIndex)



        pageIndex = ((storedPageIndex - 1) % pageCount) + 1



    end



    SKIN:Bang('!SetVariable', 'EditorPageIndex', tostring(pageIndex))



    syncPageDisplay()



    clearPickerRunState('path')



    clearPickerRunState('image')



    SetPickerModalOpen(0)



    setEditorLoadingVisible(false)



    deferredInitRequested = false



    if isEditorVisibleStateEnabled() then



        ResumeEditorResident(false)



    else



        SuspendEditorResident()



    end



end
