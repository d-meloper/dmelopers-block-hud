-- Split from Editor\InputCommit.lua lines 7617-8664.
local function commitCoordinateForLocator(axis, value, locator, lockedPairValue)



    local valueVariable = axis == 'x' and 'EditorLabeledInputValue' or 'EditorLabeledInput2Value'



    local displayVariable = axis == 'x' and 'EditorLabeledInputDisplayText' or 'EditorLabeledInput2DisplayText'



    local placeholderVariable = axis == 'x' and 'EditorLabeledInputPlaceholder' or 'EditorLabeledInput2Placeholder'



    local meterName = axis == 'x' and 'MeterLabeledInputText' or 'MeterLabeledInput2Text'



    local minVariable = axis == 'x' and 'EditorLabeledInputMin' or 'EditorLabeledInput2Min'



    local maxVariable = axis == 'x' and 'EditorLabeledInputMax' or 'EditorLabeledInput2Max'



    local fallbackValue = resolveLocatorCoordinateFallback(locator, axis)



    local resolved = resolveCommittedCoordinateValue(value, fallbackValue, minVariable, maxVariable)



    if shouldMirrorInputToVisibleSelection(locator) then



        setLabeledInput(valueVariable, displayVariable, placeholderVariable, meterName, resolved)



    end



    if resolved == '' then



        return



    end



    local companionAxis = axis == 'x' and 'y' or 'x'



    local companionValue = trim(lockedPairValue)



    if companionValue == '' then



        companionValue = resolveLocatorCoordinateFallback(locator, companionAxis)



    end



    if axis == 'x' then



        updateCoordinatesAtLocator(locator, resolved, companionValue)



    else



        updateCoordinatesAtLocator(locator, companionValue, resolved)



    end



end



function PrepareInputTarget(target)



    playUiClick()



    local normalizedTarget = trim(target)



    local record = getSelectedRecord()



    clearPreparedInputTarget()



    SKIN:Bang('!SetVariable', 'EditorPendingInputTarget', normalizedTarget)



    if record and record.Populated then



        SKIN:Bang('!SetVariable', 'EditorPendingInputSource', record.Source)



        SKIN:Bang('!SetVariable', 'EditorPendingInputX', record.x)



        SKIN:Bang('!SetVariable', 'EditorPendingInputY', record.y)



        SKIN:Bang('!SetVariable', 'EditorPendingInputSection', record.Section)



        SKIN:Bang('!SetVariable', 'EditorPendingInputPairX', tostring(record.x))



        SKIN:Bang('!SetVariable', 'EditorPendingInputPairY', tostring(record.y))



    end



end

function CommitPath(value, displayLabel)



    commitPathForLocator(value, nil, displayLabel)



end



function CommitImageKey(value)



    commitImageKeyForLocator(value, nil)



end



function CommitPickedProgram(pathValue, imageValue, displayLabel)



    commitPickedProgramForLocator(pathValue, imageValue, nil, displayLabel)



end



function CommitPendingInput(target)



    local normalizedTarget = trim(target)



    local value = readPendingInputValue(normalizedTarget)



    local locator = getPreparedInputLocator(normalizedTarget)



    local pairX = readPreparedInputPair('x')



    local pairY = readPreparedInputPair('y')



    clearPendingInputValue()



    clearPreparedInputTarget()



    if normalizedTarget == 'name' then



        commitBasicInputForLocator(value, locator)



    elseif normalizedTarget == 'path' then



        commitPathForLocator(value, locator)



    elseif normalizedTarget == 'x' then



        commitCoordinateForLocator('x', value, locator, pairY)



    elseif normalizedTarget == 'y' then



        commitCoordinateForLocator('y', value, locator, pairX)



    elseif normalizedTarget == 'qty' then



        commitQtyForLocator(value, locator)



    elseif normalizedTarget == 'imageOffsetX' then



        commitImageAdjustForLocator('OffsetX', value, locator)



    elseif normalizedTarget == 'imageOffsetY' then



        commitImageAdjustForLocator('OffsetY', value, locator)



    elseif normalizedTarget == 'imageSizeOffset' then



        commitImageAdjustForLocator('SizeOffset', value, locator)



    else



        logMessage('Warning', 'Unknown editor input target: ' .. normalizedTarget)



    end



end



function CommitLabeledInput(value)



    commitCoordinateForLocator('x', value, nil, '')



end



function IncrementLabeledInput(delta)



    playUiClick()



    local minValue = numericVariable('EditorLabeledInputMin', 1)



    local maxValue = numericVariable('EditorLabeledInputMax', 9)



    local numeric = currentValueFrom('EditorLabeledInputValue', 'EditorLabeledInputMin', 'EditorLabeledInputMax') or minValue



    local nextValue = wrapStepValue(numeric + tonumber(delta or 0), minValue, maxValue)



    CommitLabeledInput(tostring(nextValue))



end



function CommitLabeledInput2(value)



    commitCoordinateForLocator('y', value, nil, '')



end



function IncrementLabeledInput2(delta)



    playUiClick()



    local minValue = numericVariable('EditorLabeledInput2Min', 1)



    local maxValue = numericVariable('EditorLabeledInput2Max', 9)



    local numeric = currentValueFrom('EditorLabeledInput2Value', 'EditorLabeledInput2Min', 'EditorLabeledInput2Max') or minValue



    local nextValue = wrapStepValue(numeric + tonumber(delta or 0), minValue, maxValue)



    CommitLabeledInput2(tostring(nextValue))



end



function CommitImageAdjustX(value)



    commitImageAdjustForLocator('OffsetX', value, nil)



end



function IncrementImageAdjustX(delta)



    playUiClick()



    local numeric = currentValueFrom('EditorImageAdjustXValue', 'EditorImageAdjustXMin', 'EditorImageAdjustXMax') or 0



    local nextValue = wrapStepValue(numeric + tonumber(delta or 0), IMAGE_ADJUSTMENT_MIN, IMAGE_ADJUSTMENT_MAX)



    CommitImageAdjustX(tostring(nextValue))



end



function CommitImageAdjustY(value)



    commitImageAdjustForLocator('OffsetY', value, nil)



end



function IncrementImageAdjustY(delta)



    playUiClick()



    local numeric = currentValueFrom('EditorImageAdjustYValue', 'EditorImageAdjustYMin', 'EditorImageAdjustYMax') or 0



    local nextValue = wrapStepValue(numeric + tonumber(delta or 0), IMAGE_ADJUSTMENT_MIN, IMAGE_ADJUSTMENT_MAX)



    CommitImageAdjustY(tostring(nextValue))



end



function CommitImageAdjustSize(value)



    commitImageAdjustForLocator('SizeOffset', value, nil)



end



function IncrementImageAdjustSize(delta)



    playUiClick()



    local numeric = currentValueFrom('EditorImageAdjustSizeValue', 'EditorImageAdjustSizeMin', 'EditorImageAdjustSizeMax') or 0



    local nextValue = wrapStepValue(numeric + tonumber(delta or 0), IMAGE_ADJUSTMENT_MIN, IMAGE_ADJUSTMENT_MAX)



    CommitImageAdjustSize(tostring(nextValue))



end



local function getSelectedSlotForAction()



    local record = getSelectedRecord()



    if not record then



        logMessage('Warning', 'No draft slot is selected.')



        return nil



    end



    if ensureService().IsReservedHotbarSlot(record.Source, record.x, record.y) then



        return nil



    end



    return record



end



local function getEditorImageKeyForAdd()



    local imageKey = normalizeImageAsset(trim(SKIN:GetVariable('EditorImageKeyValue', ''))) or ''



    if imageKey == '' then



        imageKey = resolveValidDefaultImageKey(ensureService())



    end



    return imageKey



end



function AddSelectedDraftItem()



    playUiClick()



    local selected = getSelectedSlotForAction()



    if not selected then



        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local record = cloneRecord(selected)



    record.ImageKey = getEditorImageKeyForAdd()



    record.ItemName = trim(SKIN:GetVariable('EditorInputValue', ''))



    record.ExecPath = trim(SKIN:GetVariable('EditorInputValue2', ''))



    record.Qty = tonumber(resolveCommittedQtyValue(trim(SKIN:GetVariable('EditorLabeledInput3Value', '0')), '0')) or 0

    record.ConfirmBeforeRun = normalizeConfirmBeforeRun(SKIN:GetVariable('EditorRunConfirmToggleValue', '0'))



    record.Populated = true



    writeDraftRecord(record)



    setSelection(record)



    if rememberDraftChange(L('Editor_History_ItemAdd', '아이템 추가'), beforeSnapshot) then



        refreshDraftItemConsumersLite()



    end



end



function RequestDeleteSelectedItem()



    playUiClick()



    local selected = getSelectedSlotForAction()



    if not selected or not selected.Populated then



        return



    end



    syncItemActionState(selected, 'confirmDelete')



end



function CancelDeleteSelectedItem()



    playUiClick()



    local selected = getSelectedSlotForAction()



    if not selected then



        syncItemActionState(nil)



        return



    end



    syncItemActionState(selected)



end



function ConfirmDeleteSelectedItem()



    playUiClick()



    local selected = getSelectedSlotForAction()



    if not selected or not selected.Populated then



        syncItemActionState(selected)



        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local emptied = emptyRecord(selected.Source, selected.x, selected.y)



    writeDraftRecord(emptied)



    setSelection(emptied)



    if rememberDraftChange(L('Editor_History_ItemDelete', '아이템 삭제'), beforeSnapshot) then



        refreshDraftItemConsumersLite()



    end



end



function SelectDraftTarget(source, x, y)



    local service = ensureService()



    local record = service.GetDraftSlotRecord(editorRoot, source, x, y)



    if not record then



        return



    end



    if service.IsReservedHotbarSlot(record.Source, record.x, record.y) then



        return



    end



    local previous = currentTarget



    local selectionChanged = not previous or previous.Source ~= record.Source or previous.x ~= record.x or previous.y ~= record.y



    if selectionChanged then



        SKIN:Bang('!SetVariable', 'EditorPageIndex', '1')



        writeDraftMeta('PageIndex', 1)



        syncPageDisplay()



    end



    setSelection(record)



    logMessage('Notice', string.format('Editor target loaded: %s (%d,%d)', record.Source, record.x, record.y))



end

function OpenEditorDraftSession()



    if closeDiscardApplied then



        return



    end



    initializeDraftSessionIfNeeded()



    setEditorOpen(true)



    resumeSelection()



    if not sessionHistoryInitialized then



        initializeSessionHistory()



    else



        updateHistoryButtonState()



    end



end

function RunDeferredInitialize()



    if closeDiscardApplied or not deferredInitRequested then



        return



    end



    deferredInitRequested = false



    if not isEditorVisibleStateEnabled() then



        setEditorLoadingVisible(false)



        return



    end



    OpenEditorDraftSession()



    setEditorLoadingVisible(false)



end



function Update()



    if closeDiscardApplied then



        return 0



    end



    if not isEditorVisibleStateEnabled() then



        return 0



    end



    local service = ensureService()



    local meta = service.ReadDraftMetaOnly(editorRoot)



    if meta.EditorOpen then



        touchDraftSession(false)



    end



    if meta.DragActive and dragOutsideClockMs >= 0 then



        local now = service.GetCurrentSessionClockMs()



        if (now - dragOutsideClockMs) >= DRAG_OUTSIDE_CANCEL_TIMEOUT_MS then



            dragOutsideClockMs = -1



            CancelDrag()



        end



    elseif not meta.DragActive then



        dragOutsideClockMs = -1



    end



    return 0



end
