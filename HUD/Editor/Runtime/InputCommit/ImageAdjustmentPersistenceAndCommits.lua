-- Split from Editor\InputCommit.lua lines 6494-7616.
local function setMirroredImageAdjustmentVariables(state)

    local keys = {}

    for imageKey in pairs(state or {}) do

        keys[#keys + 1] = imageKey

    end

    table.sort(keys)

    local keyList = table.concat(keys, '|')

    SKIN:Bang('!SetVariable', 'ImageAdjustKeys', keyList)

    mirrorConsumerVariable('ImageAdjustKeys', keyList)

    for _, imageKey in ipairs(keys) do

        local adjustment = state[imageKey] or {}

        local offsetX = tostring(tonumber(adjustment.OffsetX) or 0)

        local offsetY = tostring(tonumber(adjustment.OffsetY) or 0)

        local sizeOffset = tostring(tonumber(adjustment.SizeOffset) or 0)

        SKIN:Bang('!SetVariable', 'ImageAdjust_' .. imageKey .. '_OffsetX', offsetX)

        SKIN:Bang('!SetVariable', 'ImageAdjust_' .. imageKey .. '_OffsetY', offsetY)

        SKIN:Bang('!SetVariable', 'ImageAdjust_' .. imageKey .. '_SizeOffset', sizeOffset)

        mirrorConsumerVariable('ImageAdjust_' .. imageKey .. '_OffsetX', offsetX)

        mirrorConsumerVariable('ImageAdjust_' .. imageKey .. '_OffsetY', offsetY)

        mirrorConsumerVariable('ImageAdjust_' .. imageKey .. '_SizeOffset', sizeOffset)

    end

end

local function writeImageAdjustmentsFile(path, state, staleKeys)



    local keys = {}



    for imageKey in pairs(state or {}) do



        keys[#keys + 1] = imageKey



    end



    table.sort(keys)



    SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjustKeys', table.concat(keys, '|'), path)



    local seen = {}



    for _, imageKey in ipairs(keys) do



        seen[imageKey] = true



        local adjustment = state[imageKey] or {}



        SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjust_' .. imageKey .. '_OffsetX', tostring(tonumber(adjustment.OffsetX) or 0), path)



        SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjust_' .. imageKey .. '_OffsetY', tostring(tonumber(adjustment.OffsetY) or 0), path)



        SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjust_' .. imageKey .. '_SizeOffset', tostring(tonumber(adjustment.SizeOffset) or 0), path)



    end



    for _, imageKey in ipairs(staleKeys or {}) do



        if not seen[imageKey] then



            SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjust_' .. imageKey .. '_OffsetX', '', path)



            SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjust_' .. imageKey .. '_OffsetY', '', path)



            SKIN:Bang('!WriteKeyValue', 'Variables', 'ImageAdjust_' .. imageKey .. '_SizeOffset', '', path)



        end



    end



    return true



end



local function persistDraftImageAdjustments()



    local state = cloneImageAdjustmentState(ensureDraftImageAdjustments())



    local path = editorRoot .. 'Customs\\Data\\ImageAdjustments.inc'



    local staleKeys = {}



    for imageKey in trim(SKIN:GetVariable('ImageAdjustKeys', '')):gmatch('[^|]+') do



        staleKeys[#staleKeys + 1] = trim(imageKey)



    end



    setMirroredImageAdjustmentVariables(state)



    if not writeImageAdjustmentsFile(path, state, staleKeys) then



        logMessage('Error', 'Failed to write image adjustments file.')



    end



end



local function countMeaningfulPersistRecords(service, records)

    local count = 0

    for _, record in ipairs(records or {}) do

        if record and record.Populated then

            local isReserved = service.IsReservedHotbarSlot and service.IsReservedHotbarSlot(record.Source, record.x, record.y)

            if not isReserved then

                count = count + 1

            end

        end

    end

    return count

end



hasEmptyDraftOverPopulatedPersistedData = function(service)

    local draftHotbarRecords = service.BuildSourceRecords(editorRoot, 'hotbar', true)

    local draftInventoryRecords = service.BuildSourceRecords(editorRoot, 'inventory', true)

    local persistedHotbarRecords = service.BuildSourceRecords(editorRoot, 'hotbar', false)

    local persistedInventoryRecords = service.BuildSourceRecords(editorRoot, 'inventory', false)

    local draftCount = countMeaningfulPersistRecords(service, draftHotbarRecords) + countMeaningfulPersistRecords(service, draftInventoryRecords)

    local persistedCount = countMeaningfulPersistRecords(service, persistedHotbarRecords) + countMeaningfulPersistRecords(service, persistedInventoryRecords)



    return draftCount == 0 and persistedCount > 0

end



shouldSkipEmptyDraftPersist = function(service, meta)

    if meta and meta.Dirty then

        return false

    end



    return hasEmptyDraftOverPopulatedPersistedData(service)

end

function CleanupEditorPixelationImagesForCurrentItems()

    if type(CleanupEditorPixelationImagesAfterPersist) == 'function' then

        CleanupEditorPixelationImagesAfterPersist()

    end

end



local function writePersistedFromDraft()



    local service = ensureService()



    local paths = service.GetPaths(editorRoot)



    local meta = getDraftMeta()



    if shouldSkipEmptyDraftPersist(service, meta) then

        logMessage('Warning', 'Skipped persisting an empty editor draft over populated item data.')
        showEditorModalAlert('error', 'ModalAlert_EditorSaveFailed', 'The Editor changes could not be saved because the draft state is incomplete. Reopen the Editor and try again.')

        return false

    end



    for _, record in ipairs(service.BuildSourceRecords(editorRoot, 'hotbar', true)) do



        writeRecordToPath(paths.HotbarData, 'HotbarItem', record)



    end



    for _, record in ipairs(service.BuildSourceRecords(editorRoot, 'inventory', true)) do



        writeRecordToPath(paths.InventoryData, 'InventoryItem', record)



    end



    persistDraftImageAdjustments()



    return true



end



local function persistDraftAndResetSessionState()



    closeCommitChanged = false

    local dirty = trim(SKIN:GetVariable(draftMetaVariableName('Dirty'), '0')) == '1'

    if dirty then

        closeCommitChanged = true

        if not writePersistedFromDraft() then

            return false

        end



        setDirty(false)



        applySnapshotToDraft()

    end



    clearDragState()



    persistSelection(nil)



    currentTarget = nil



    clearSessionHistory()



    setEditorOpen(false)



    closeDiscardApplied = true

    CleanupEditorPixelationImagesForCurrentItems()



    return true



end

local function tryCommitClose(logContext)



    local wasRepaired, repairLogs = normalizeInvalidDraftChanges()



    if wasRepaired then



        setDirty(true)

        for _, repairLog in ipairs(repairLogs) do



            logMessage('Warning', 'Draft auto-repaired before close: ' .. repairLog)



        end



    end



    if not persistDraftAndResetSessionState() then

        return false

    end

    closeCommitChanged = closeCommitChanged or wasRepaired



    if logContext and logContext ~= '' then



        logMessage('Notice', logContext)



    end



    return true



end



local function resumeSelection()



    local selected = getSelectedRecord()



    if selected then



        setSelection(selected)



        return



    end



    clearEditorUI()



end



local function resolveCommittedCoordinateValue(value, fallbackValue, minVariable, maxVariable)



    local minValue = numericVariable(minVariable, 1)



    local maxValue = numericVariable(maxVariable, 9)



    local raw = trim(value)



    if raw == '' then



        return ''



    end



    local numeric = tonumber(raw)



    if numeric then



        return tostring(clamp(math.floor(numeric), minValue, maxValue))



    end



    local fallbackNumeric = tonumber(fallbackValue)



    if fallbackNumeric then



        return tostring(clamp(math.floor(fallbackNumeric), minValue, maxValue))



    end



    return tostring(fallbackValue or '')



end



resolveCommittedQtyValue = function(value, fallbackValue)



    local raw = trim(value)



    local fallbackRaw = trim(fallbackValue)



    if raw == '' then



        raw = fallbackRaw



    end



    local numeric = tonumber(raw)



    if not numeric then



        numeric = tonumber(fallbackRaw)



    end



    if not numeric then



        numeric = 0



    end



    return tostring(clamp(math.floor(numeric), 0, 999))



end



local function resolveCommittedSignedValue(value, fallbackValue)



    local raw = trim(value)



    local fallbackRaw = trim(fallbackValue)



    if raw == '' then



        raw = fallbackRaw



    end



    local numeric = tonumber(raw)



    if not numeric then



        numeric = tonumber(fallbackRaw)



    end



    if not numeric then



        numeric = 0



    end



    return tostring(clamp(math.floor(numeric), IMAGE_ADJUSTMENT_MIN, IMAGE_ADJUSTMENT_MAX))



end



local function shouldMirrorInputToVisibleSelection(locator)



    return locator == nil or isLocatorCurrentSelection(locator)



end



local function resolveLocatorCoordinateFallback(locator, axis)



    local record = getRecordByLocator(locator)



    if record and record.Populated then



        if axis == 'x' then



            return tostring(record.x)



        end



        return tostring(record.y)



    end



    if axis == 'x' then



        return trim(SKIN:GetVariable('EditorLabeledInputValue', ''))



    end



    return trim(SKIN:GetVariable('EditorLabeledInput2Value', ''))



end



local function resolveLocatorQtyFallback(locator)



    local record = getRecordByLocator(locator)



    if record and record.Populated then



        return tostring(record.Qty or 0)



    end



    return trim(SKIN:GetVariable('EditorLabeledInput3Value', '0'))



end

local function commitBasicInputForLocator(value, locator)



    local resolved = trim(value)



    if shouldMirrorInputToVisibleSelection(locator) then



        setBasicInput(resolved)



    end



    updateFieldAtLocator(locator, 'Label', resolved)



end



local function commitPathForLocator(value, locator, displayLabel)



    local resolved = trim(value)



    if shouldMirrorInputToVisibleSelection(locator) then



        setPathInput(resolved, displayLabel)



    end



    updateFieldAtLocator(locator, 'Action', resolved)



end



local function commitImageKeyForLocator(value, locator)



    local imageKey = normalizeImageAsset(value)

    local service = ensureService()



    if service.IsReservedRuntimeImageAsset and service.IsReservedRuntimeImageAsset(imageKey) then



        logMessage('Error', 'Reserved runtime asset more.png cannot be assigned as a custom item image.')



        return



    end



    if shouldMirrorInputToVisibleSelection(locator) then



        setImageKey(imageKey)



    end



    updateFieldAtLocator(locator, 'Image', imageKey)



end





function UpdatePickedProgramAtLocator(pathValue, imageValue, locator)
    local record = getRecordByLocator(locator)
    if not record then
        logMessage('Warning', 'No draft item is selected.')
        return
    end
    if not record.Populated then
        ensureSelectedDraftItemForEdit(locator)
        return
    end

    local resolvedPath = trim(pathValue)
    local imageKey = normalizeImageAsset(imageValue)
    local service = ensureService()
    if imageKey ~= "" and service.IsReservedRuntimeImageAsset and service.IsReservedRuntimeImageAsset(imageKey) then
        logMessage('Error', 'Reserved runtime asset more.png cannot be assigned as a custom item image.')
        return
    end

    local pathChanged = record.ExecPath ~= resolvedPath
    local imageChanged = imageKey ~= "" and record.ImageKey ~= imageKey
    if not pathChanged and not imageChanged then
        return
    end

    local beforeSnapshot = captureDraftSnapshot()
    if pathChanged then
        record.ExecPath = resolvedPath
    end
    if imageChanged then
        record.ImageKey = imageKey
    end

    writeDraftRecord(record)
    if isLocatorCurrentSelection(locator) then
        setSelection(record)
    end

    local historyLabel = pathChanged and L('Editor_History_PathChange', 'Path changed') or L('Editor_History_ImageChange', 'Image changed')
    if rememberDraftChange(historyLabel, beforeSnapshot) then
        refreshDraftItemConsumersLite()
    end
end

local function commitPickedProgramForLocator(pathValue, imageValue, locator, displayLabel)



    local resolvedPath = trim(pathValue)



    local imageKey = normalizeImageAsset(imageValue)



    if shouldMirrorInputToVisibleSelection(locator) then



        setPathInput(resolvedPath, displayLabel)



        if imageKey ~= "" then



            setImageKey(imageKey)



        end



    end



    UpdatePickedProgramAtLocator(resolvedPath, imageKey, locator)



end

local function commitQtyForLocator(value, locator)



    local resolved = resolveCommittedQtyValue(value, resolveLocatorQtyFallback(locator))



    if shouldMirrorInputToVisibleSelection(locator) then



        setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', resolved)



    end



    updateFieldAtLocator(locator, 'Qty', resolved)



end



local function updateImageAdjustmentAtLocator(locator, fieldName, value)



    local record = getRecordByLocator(locator)



    if not record then



        logMessage('Warning', 'No draft item is selected.')



        return



    end



    if not record.Populated then



        return



    end



    local imageAdjustKey = getImageAdjustmentKeyForRecord(record)



    if not imageAdjustKey then



        logMessage('Warning', 'Selected item has no image to adjust.')



        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local adjustment = getDraftImageAdjustment(imageAdjustKey)



    local currentValue = tonumber(adjustment[fieldName]) or 0



    local fallbackValue = currentValue



    if fieldName == 'OffsetY' then



        fallbackValue = toUserFacingImageOffsetY(currentValue)



    end



    local resolved = tonumber(resolveCommittedSignedValue(value, tostring(fallbackValue))) or 0



    if fieldName == 'OffsetY' then



        resolved = toPersistedImageOffsetY(resolved)



    end



    if currentValue == resolved then



        if shouldMirrorInputToVisibleSelection(locator) then



            syncImageAdjustmentUI(record)



        end



        return



    end



    adjustment[fieldName] = resolved



    setDraftImageAdjustment(imageAdjustKey, adjustment)



    if shouldMirrorInputToVisibleSelection(locator) then



        syncImageAdjustmentUI(record)



    end



    rememberDraftChange(L('Editor_History_ImageAdjust', '이미지 조정 변경'), beforeSnapshot)



    persistDraftImageAdjustments()



    refreshDraftItemConsumersLite()



end



local function commitImageAdjustForLocator(fieldName, value, locator)



    updateImageAdjustmentAtLocator(locator, fieldName, value)



end
