-- Split from Editor\InputCommit.lua lines 5263-6493.
local function restoreDraftSnapshot(snapshot)



    if not snapshot then



        return



    end



    for _, source in ipairs({ 'hotbar', 'inventory' }) do



        for _, record in ipairs(snapshot.Records[source] or {}) do



            writeDraftRecord(record)



        end



    end



    draftImageAdjustments = cloneImageAdjustmentState(snapshot.ImageAdjustments or {})



    clearDragState()



    local selection = snapshot.Selection



    if selection then



        local restored = ensureService().GetDraftSlotRecord(editorRoot, selection.Source, selection.X, selection.Y)



        if restored then



            setSelection(restored)



            return



        end



    end



    persistSelection(nil)



    clearEditorUI()



end



local function applySnapshotToDraft()



    writeDraftMeta('SchemaVersion', 3)



    writeDraftMeta('Dirty', 0)



    writeDraftMeta('PageIndex', 1)



    writeDraftMeta('HeartbeatClockMs', 0)



    writeDraftMeta('SelectedSource', '')



    writeDraftMeta('SelectedX', 0)



    writeDraftMeta('SelectedY', 0)



    writeDraftMeta('SelectedSection', '')



    writeDraftMeta('DragSource', '')



    writeDraftMeta('DragX', 0)



    writeDraftMeta('DragY', 0)



    writeDraftMeta('DragActive', 0)



    writeDraftMeta('PickerModalOpen', 0)



    local service = ensureService()



    for _, source in ipairs({ 'hotbar', 'inventory' }) do



        for _, record in ipairs(service.BuildSourceRecords(editorRoot, source, false)) do



            writeDraftRecord(record)



        end



    end



draftImageAdjustments = getPersistedImageAdjustments()



end



local function discardDraftSession(skipRefresh)



    if closeDiscardApplied then



        return false



    end



    closeDiscardApplied = true



    setEditorOpen(false)



    applySnapshotToDraft()



    persistDraftImageAdjustments()



    persistSelection(nil)



    clearDragState()



    currentTarget = nil



    clearSessionHistory()



    if not skipRefresh then



        refreshConsumersAfterEditorClose()



    end



    return true



end



local hasEmptyDraftOverPopulatedPersistedData



local function recordsEquivalent(left, right)



    if #left ~= #right then

        return false

    end

    for index, leftRecord in ipairs(left) do

        local rightRecord = right[index]

        if not rightRecord then

            return false

        end

        if tostring(leftRecord.Section or '') ~= tostring(rightRecord.Section or '') then

            return false

        end

        if tostring(leftRecord.ImageKey or '') ~= tostring(rightRecord.ImageKey or '') then

            return false

        end

        if tostring(leftRecord.ItemName or '') ~= tostring(rightRecord.ItemName or '') then

            return false

        end

        if tostring(leftRecord.ExecPath or '') ~= tostring(rightRecord.ExecPath or '') then

            return false

        end

        if normalizeConfirmBeforeRun(leftRecord.ConfirmBeforeRun) ~= normalizeConfirmBeforeRun(rightRecord.ConfirmBeforeRun) then

            return false

        end

        if tostring(leftRecord.Qty or 0) ~= tostring(rightRecord.Qty or 0) then

            return false

        end

    end

    return true

end

local function draftMatchesPersistedData(service)



    for _, source in ipairs({ 'hotbar', 'inventory' }) do

        local draftRecords = service.BuildSourceRecords(editorRoot, source, true)

        local persistedRecords = service.BuildSourceRecords(editorRoot, source, false)

        if not recordsEquivalent(draftRecords, persistedRecords) then

            return false

        end

    end

    return true

end
local function rebuildEmptyDraftFromPersistedDataIfNeeded(service)



    if not hasEmptyDraftOverPopulatedPersistedData(service) then



        return false



    end



    applySnapshotToDraft()



    clearSessionHistory()



    logMessage('Warning', 'Rebuilt empty editor draft from persisted item data before opening editor.')



    return true



end



local function initializeDraftSessionIfNeeded()



    local service = ensureService()



    if rebuildEmptyDraftFromPersistedDataIfNeeded(service) then



        setEditorOpen(true)



        return



    end



    if not service.IsDraftOpen(editorRoot) then



        if not draftMatchesPersistedData(service) then

            applySnapshotToDraft()

        end



        clearSessionHistory()



        if not draftImageAdjustments then

            draftImageAdjustments = getPersistedImageAdjustments()

        end



        setEditorOpen(true)



    elseif not draftImageAdjustments then



        draftImageAdjustments = getPersistedImageAdjustments()



    end



end



local function moveDraftRecord(sourceRecord, destinationSource, destinationX, destinationY)



    local service = ensureService()



    local destinationRecord = service.GetDraftSlotRecord(editorRoot, destinationSource, destinationX, destinationY)



    local moved = cloneRecord(sourceRecord)



    moved.Source = destinationSource



    moved.Section = service.GetSectionName(destinationSource, destinationX, destinationY)



    moved.x = destinationX



    moved.y = destinationY



    moved.Populated = true



    writeDraftRecord(moved)



    if destinationRecord and destinationRecord.Populated then



        local swapped = cloneRecord(destinationRecord)



        swapped.Source = sourceRecord.Source



        swapped.Section = sourceRecord.Section



        swapped.x = sourceRecord.x



        swapped.y = sourceRecord.y



        writeDraftRecord(swapped)



    else



        writeDraftRecord(emptyRecord(sourceRecord.Source, sourceRecord.x, sourceRecord.y))



    end



    return moved



end



local function getRecordByLocator(locator)



    if locator then



        return ensureService().GetDraftSlotRecord(editorRoot, locator.Source, locator.X, locator.Y)



    end



    return getSelectedRecord()



end



local function isLocatorCurrentSelection(locator)



    if not locator then



        return true



    end



    local meta = getDraftMeta()



    return meta.SelectedSource == locator.Source and meta.SelectedX == locator.X and meta.SelectedY == locator.Y



end



ensureSelectedDraftItemForEdit = function(locator)



    if locator and not isLocatorCurrentSelection(locator) then



        return false



    end



    if type(AddSelectedDraftItem) ~= 'function' then



        return false



    end



    AddSelectedDraftItem()

    return true



end



local function updateFieldAtLocator(locator, fieldName, value)



    local record = getRecordByLocator(locator)



    if not record then



        logMessage('Warning', 'No draft item is selected.')



        return



    end



    if not record.Populated then



        ensureSelectedDraftItemForEdit(locator)

        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local historyLabel = nil



    if fieldName == 'Image' then



        local resolvedImage = normalizeImageAsset(value)



        if record.ImageKey == resolvedImage then



            return



        end



        record.ImageKey = resolvedImage



        historyLabel = L('Editor_History_ImageChange', '이미지 변경')



    elseif fieldName == 'Label' then



        local resolvedLabel = trim(value)



        if record.ItemName == resolvedLabel then



            return



        end



        record.ItemName = resolvedLabel



        historyLabel = L('Editor_History_NameChange', '아이템 이름 변경')



    elseif fieldName == 'Action' then



        local resolvedPath = trim(value)



        if record.ExecPath == resolvedPath then



            return



        end



        record.ExecPath = resolvedPath



        historyLabel = L('Editor_History_PathChange', '실행 경로 변경')



    elseif fieldName == 'Qty' then



        local resolvedQty = tonumber(resolveCommittedQtyValue(value, tostring(record.Qty or 0))) or 0



        if (record.Qty or 0) == resolvedQty then



            return



        end



        record.Qty = resolvedQty



        historyLabel = L('Editor_History_QtyChange', '아이템 개수 변경')



    else



        return



    end



    writeDraftRecord(record)



    if isLocatorCurrentSelection(locator) then



        setSelection(record)



    end



    if rememberDraftChange(historyLabel, beforeSnapshot) then



        refreshDraftItemConsumersLite()



    end



end

applyRunConfirmToggleChange = function(enabled)

    local record = getSelectedRecord()

    if not record or not record.Populated then

        return

    end

    local service = ensureService()

    if service.IsReservedHotbarSlot(record.Source, record.x, record.y) then

        setRunConfirmToggleUi(false)

        return

    end

    local value = enabled and '1' or '0'

    if normalizeConfirmBeforeRun(record.ConfirmBeforeRun) == value then

        return

    end

    local beforeSnapshot = captureDraftSnapshot()

    record.ConfirmBeforeRun = value

    writeDraftRecord(record)

    setSelection(record)

    if rememberDraftChange(L('Editor_History_RunConfirmToggle', '실행 전 확인창 표시 변경'), beforeSnapshot) then

        refreshDraftItemConsumersLite()

    end

end

local function updateCoordinatesAtLocator(locator, nextX, nextY)



    local service = ensureService()



    local record = getRecordByLocator(locator)



    if not record then



        logMessage('Warning', 'No draft item is selected.')



        return



    end



    nextX = tonumber(nextX)



    nextY = tonumber(nextY)



    if not nextX or not nextY then



        return



    end



    nextX = math.floor(nextX)



    nextY = math.floor(nextY)



    if not isValidLogicalCoordinate(record.Source, nextX, nextY) then



        logMessage('Warning', 'Coordinates are invalid for the selected item.')



        return



    end



    local destinationSource, destinationX, destinationY = resolveCoordinateDestination(record.Source, nextX, nextY)



    if service.IsReservedHotbarSlot(destinationSource, destinationX, destinationY) then



        return



    end



    if not record.Populated then



        local destinationRecord = service.GetDraftSlotRecord(editorRoot, destinationSource, destinationX, destinationY)



        if destinationRecord then



            setSelection(destinationRecord)



        end



        return



    end



    local beforeSnapshot = captureDraftSnapshot()



    local destinationRecord = service.GetDraftSlotRecord(editorRoot, destinationSource, destinationX, destinationY)



    if destinationRecord and destinationRecord.Populated and service.IsReservedHotbarSlot(destinationRecord.Source, destinationRecord.x, destinationRecord.y) then



        logMessage('Warning', 'Reserved hotbar slot cannot be overwritten.')



        return



    end



    if record.Source == destinationSource and record.x == destinationX and record.y == destinationY then



        setSelection(record)



        return



    end



    local moved = moveDraftRecord(record, destinationSource, destinationX, destinationY)



    setSelection(moved)



    if rememberDraftChange(L('Editor_History_ItemMove', '아이템 이동'), beforeSnapshot) then



        refreshDraftItemConsumersLite()



    end



end



local function appendRepairLog(logs, source, x, y, message)



    logs[#logs + 1] = string.format('%s (%d,%d): %s', source, x, y, message)



end



local function resolveValidDefaultImageKey(service)



    local defaultImageKey = normalizeImageAsset(trim(SKIN:GetVariable('EditorDefaultImageKey', DEFAULT_NEW_ITEM_IMAGE)))



    if defaultImageKey ~= '' then



        return defaultImageKey



    end



    return DEFAULT_NEW_ITEM_IMAGE



end



local function normalizeInvalidDraftChanges()



    local service = ensureService()



    local meta = getDraftMeta()



    local repairLogs = {}



    local repaired = false



    local defaultImageKey = resolveValidDefaultImageKey(service)



    for _, source in ipairs({ 'hotbar', 'inventory' }) do



        for _, original in ipairs(service.BuildSourceRecords(editorRoot, source, true)) do



            local record = cloneRecord(original)



            if source == 'hotbar' and record.x == 10 then



                if record.ImageKey ~= RESERVED_SLOT.ImageKey



                    or not isReservedInventoryLabelValue(record.ItemName)



                    or record.ExecPath ~= RESERVED_SLOT.ExecPath



                    or record.Qty ~= RESERVED_SLOT.Qty

                    or normalizeConfirmBeforeRun(record.ConfirmBeforeRun) ~= '0' then



                    writeDraftRecord({



                        Source = 'hotbar',



                        Section = 'Slot10',



                        x = 10,



                        y = 1,



                        ImageKey = RESERVED_SLOT.ImageKey,



                        ItemName = RESERVED_SLOT.ItemName,



                        ExecPath = RESERVED_SLOT.ExecPath,



                        Qty = RESERVED_SLOT.Qty,

                        ConfirmBeforeRun = '0',



                        Populated = true,



                    })



                    appendRepairLog(repairLogs, source, record.x, record.y, 'reserved slot restored to inventory shortcut')



                    repaired = true



                end



            elseif record.Populated then



                local recordChanged = false



                local normalizedImageKey = normalizeImageAsset(record.ImageKey) or ''



                if normalizedImageKey == '' then



                    record.ImageKey = defaultImageKey



                    appendRepairLog(repairLogs, source, record.x, record.y, 'empty image repaired to default image')



                    recordChanged = true



                elseif record.ImageKey ~= normalizedImageKey then



                    record.ImageKey = normalizedImageKey



                    recordChanged = true



                end



                if recordChanged then



                    writeDraftRecord(record)



                    repaired = true



                end



            end



        end



    end



    return repaired, repairLogs



end
