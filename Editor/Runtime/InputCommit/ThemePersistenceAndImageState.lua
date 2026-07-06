-- Split from Editor\InputCommit.lua lines 1436-2661.
local function applyEditorTheme(mode)



    local prefix = 'EditorThemeDraculaPalette'



    if mode == 'light' then



        prefix = 'EditorThemeLattePalette'



    else



        mode = 'dark'



    end



    local palette = {}



    for index = 1, 6 do



        local paletteName = prefix .. tostring(index)



        local fallback = SKIN:GetVariable('EditorPalette' .. tostring(index), '')



        local paletteValue = SKIN:GetVariable(paletteName, fallback)



        palette[index] = paletteValue



        SKIN:Bang('!SetVariable', 'EditorPalette' .. tostring(index), paletteValue)



    end



    SKIN:Bang('!SetVariable', 'PanelFillColor', palette[1])



    SKIN:Bang('!SetVariable', 'PanelInsetColor', palette[2])



    SKIN:Bang('!SetVariable', 'PanelStrokeColor', palette[4])



    SKIN:Bang('!SetVariable', 'RailBaseColor', palette[3])



    SKIN:Bang('!SetVariable', 'RailEdgeSoftColor', palette[4])



    SKIN:Bang('!SetVariable', 'HeaderBaseColor', palette[3])



    SKIN:Bang('!SetVariable', 'HeaderStrongColor', palette[4])



    SKIN:Bang('!SetVariable', 'HeaderAltColor', palette[5])



    SKIN:Bang('!SetVariable', 'HeaderInsetColor', palette[1])



    SKIN:Bang('!SetVariable', 'HeaderEdgeColor', palette[5])



    SKIN:Bang('!SetVariable', 'HeaderEdgeSoftColor', palette[4])



    SKIN:Bang('!SetVariable', 'CoreStrongColor', palette[3])



    SKIN:Bang('!SetVariable', 'CoreAltColor', palette[4])



    SKIN:Bang('!SetVariable', 'CoreInsetColor', palette[3])



    SKIN:Bang('!SetVariable', 'CoreEdgeColor', palette[4])



    SKIN:Bang('!SetVariable', 'EditorInputBgColor', palette[2])



    SKIN:Bang('!SetVariable', 'EditorInputStrokeColor', palette[4])



    SKIN:Bang('!SetVariable', 'EditorInputTextColor', palette[5])



    SKIN:Bang('!SetVariable', 'EditorButtonBgColor', palette[3])



    SKIN:Bang('!SetVariable', 'EditorButtonStrokeColor', palette[4])



    SKIN:Bang('!SetVariable', 'EditorButtonTextColor', palette[5])



    SKIN:Bang('!SetVariable', 'EditorButtonDisabledBgColor', palette[2])



    SKIN:Bang('!SetVariable', 'EditorButtonDisabledTextColor', palette[4])



    SKIN:Bang('!SetVariable', 'EditorViewerInnerBgColor', palette[2])



end



local function writeVariableValue(path, variableName, value)



    local resolved = tostring(value or '')



    SKIN:Bang('!SetVariable', variableName, resolved)



    SKIN:Bang('!WriteKeyValue', 'Variables', variableName, resolved, path)



end

function EditorIsRainmeterConfigActive(configName)
    local configState = dofile(SKIN:GetVariable('@', '') .. 'Defaults\\Runtime\\luas\\RainmeterConfigState.lua')
    return configState.IsActive(SKIN, configName)
end

local function isInventoryConsumerActive()

    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))

    if rootConfig == '' or not EditorIsRainmeterConfigActive(rootConfig .. '\\Inventory') then

        return false

    end

    return trim(SKIN:GetVariable('BlockHudInventoryVisible', '0')) == '1'
        or trim(SKIN:GetVariable('ResponsiveLayout_Inventory_LiveActive', '0')) == '1'

end



local function mirrorConsumerVariable(variableName, value)

    if consumerMirroringSuspended then

        return

    end

    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))

    local resolved = tostring(value or '')

    if rootConfig == '' then

        return

    end

    for _, consumer in ipairs({ 'Hotbar', 'Inventory', 'InventoryBG' }) do

        local configPath = rootConfig .. '\\' .. consumer

        if EditorIsRainmeterConfigActive(configPath) then

            SKIN:Bang('!SetVariable', variableName, resolved, configPath)

        end

    end

end



local function syncReservedSlotPersistence()

    local existingHotbarLabel = trim(SKIN:GetVariable('HotbarItem_Slot10_Label', ''))
    local existingDraftLabel = trim(SKIN:GetVariable('EditorDraftItem_Slot10_Label', ''))
    local resolvedLabel = existingDraftLabel ~= '' and existingDraftLabel or existingHotbarLabel
    resolvedLabel = canonicalReservedInventoryLabel(resolvedLabel)

    local reservedValues = {

        Image = RESERVED_SLOT.ImageKey,

        Label = resolvedLabel,

        Action = RESERVED_SLOT.ExecPath,

        Qty = tostring(RESERVED_SLOT.Qty),

    }

    local paths = ensureService().GetPaths(editorRoot)



    for key, value in pairs(reservedValues) do

        local persistedVariable = 'HotbarItem_Slot10_' .. key

        if trim(SKIN:GetVariable(persistedVariable, '')) ~= value then

            writeVariableValue(paths.HotbarData, persistedVariable, value)

            mirrorConsumerVariable(persistedVariable, value)

        end

    end



    for key, value in pairs(reservedValues) do

        local draftVariable = 'EditorDraftItem_Slot10_' .. key

        if trim(SKIN:GetVariable(draftVariable, '')) ~= value then

            writeVariableValue(paths.Draft, draftVariable, value)

            mirrorConsumerVariable(draftVariable, value)

        end

    end

end



local function mirrorDraftMetaVariable(variableName, value)

    mirrorConsumerVariable(variableName, value)

end

local function draftMetaVariableName(key)



    return 'EditorDraftMeta_' .. tostring(key or '')



end



local function writeDraftMeta(key, value)



    local variableName = draftMetaVariableName(key)

    local resolved = tostring(value or '')

    if trim(SKIN:GetVariable(variableName, '')) == resolved then

        return

    end

    writeVariableValue(ensureService().GetPaths(editorRoot).Draft, variableName, resolved)



    mirrorDraftMetaVariable(variableName, resolved)



end

local function touchDraftSession(force)



    local service = ensureService()



    local now = service.GetCurrentSessionClockMs()



    local interval = service.GetDraftSessionHeartbeatIntervalMs()



    if not force and sessionHeartbeatClockMs >= 0 and (now - sessionHeartbeatClockMs) < interval then



        return



    end



    writeDraftMeta('HeartbeatClockMs', now)



    sessionHeartbeatClockMs = now



end



function NotifyDragInside()



    dragOutsideClockMs = -1



end



function NotifyDragOutside()



    local service = ensureService()



    local meta = getDraftMeta()



    if shouldSkipEmptyDraftPersist(service, meta) then

        logMessage('Warning', 'Skipped persisting an empty editor draft over populated item data.')
        showEditorModalAlert('error', 'ModalAlert_EditorSaveFailed', 'The Editor changes could not be saved because the draft state is incomplete. Reopen the Editor and try again.')

        return false

    end



    if meta.DragActive then



        dragOutsideClockMs = service.GetCurrentSessionClockMs()



    end



end



local function writeItemField(path, prefix, section, key, value)



    writeVariableValue(path, prefix .. '_' .. section .. '_' .. key, value)



end



local function cloneImageAdjustmentState(state)



    local cloned = {}



    for imageKey, adjustment in pairs(state or {}) do



        cloned[imageKey] = {



            OffsetX = tonumber(adjustment.OffsetX) or 0,



            OffsetY = tonumber(adjustment.OffsetY) or 0,



            SizeOffset = tonumber(adjustment.SizeOffset) or 0,



        }



    end



    return cloned



end



local function getPersistedImageAdjustments()



    local sections = ensureService().ReadImageAdjustmentSections(editorRoot) or {}



    local normalized = {}



    for imageKey, section in pairs(sections) do



        normalized[trim(imageKey)] = {



            OffsetX = tonumber(section.OffsetX) or 0,



            OffsetY = tonumber(section.OffsetY) or 0,



            SizeOffset = tonumber(section.SizeOffset) or 0,



        }



    end



    return normalized



end



local function ensureDraftImageAdjustments()



    if not draftImageAdjustments then



        draftImageAdjustments = getPersistedImageAdjustments()



    end



    return draftImageAdjustments



end



local function getImageAdjustmentKeyForRecord(record)



    if not record or not record.Populated then



        return nil



    end



    local imageKey = trim(record.ImageKey or '')



    if imageKey == '' then



        return nil



    end



    local key = ensureService().GetImageAdjustmentKey(imageKey)



    key = trim(key or '')



    if key == '' then



        return nil



    end



    return key



end



local function getDraftImageAdjustment(imageKey)



    local key = trim(imageKey or '')



    if key == '' then



        return { OffsetX = 0, OffsetY = 0, SizeOffset = 0 }



    end



    local adjustment = ensureDraftImageAdjustments()[key]



    if not adjustment then



        return { OffsetX = 0, OffsetY = 0, SizeOffset = 0 }



    end



    return {



        OffsetX = tonumber(adjustment.OffsetX) or 0,



        OffsetY = tonumber(adjustment.OffsetY) or 0,



        SizeOffset = tonumber(adjustment.SizeOffset) or 0,



    }



end



local function isZeroImageAdjustment(adjustment)



    return (tonumber(adjustment.OffsetX) or 0) == 0



        and (tonumber(adjustment.OffsetY) or 0) == 0



        and (tonumber(adjustment.SizeOffset) or 0) == 0



end



local function setDraftImageAdjustment(imageKey, adjustment)



    local draft = ensureDraftImageAdjustments()



    if isZeroImageAdjustment(adjustment) then



        draft[imageKey] = nil



        return



    end



    draft[imageKey] = {



        OffsetX = tonumber(adjustment.OffsetX) or 0,



        OffsetY = tonumber(adjustment.OffsetY) or 0,



        SizeOffset = tonumber(adjustment.SizeOffset) or 0,



    }



end



local function setImageAdjustInput(valueVariable, displayVariable, placeholderVariable, meterName, value)



    setLabeledInput(valueVariable, displayVariable, placeholderVariable, meterName, tostring(tonumber(value) or 0))



end



local function toUserFacingImageOffsetY(value)
    return EnsureEditorValueHelpers().toUserFacingImageOffsetY(value)
end



local function toPersistedImageOffsetY(value)
    return EnsureEditorValueHelpers().toPersistedImageOffsetY(value)
end



local function syncPreviewImageGeometry(adjustment)



    SKIN:Bang('!UpdateMeasure', 'MeasureViewerPreviewBaseImageX')



    SKIN:Bang('!UpdateMeasure', 'MeasureViewerPreviewBaseImageY')



    SKIN:Bang('!UpdateMeasure', 'MeasureViewerPreviewBaseImageW')



    SKIN:Bang('!UpdateMeasure', 'MeasureViewerPreviewBaseImageH')



    local baseX = measureNumericValue('MeasureViewerPreviewBaseImageX', 0)



    local baseY = measureNumericValue('MeasureViewerPreviewBaseImageY', 0)



    local baseW = measureNumericValue('MeasureViewerPreviewBaseImageW', 1)



    local baseH = measureNumericValue('MeasureViewerPreviewBaseImageH', 1)



    local offsetX = tonumber(adjustment.OffsetX) or 0



    local offsetY = tonumber(adjustment.OffsetY) or 0



    local sizeOffset = tonumber(adjustment.SizeOffset) or 0



    local adjustedW = math.max(1, baseW + sizeOffset)



    local adjustedH = math.max(1, baseH + sizeOffset)



    local centerX = baseX + (baseW / 2)



    local centerY = baseY + (baseH / 2)



    local previewX = math.floor(centerX - (adjustedW / 2) + offsetX)



    local previewY = math.floor(centerY - (adjustedH / 2) + offsetY)



    SKIN:Bang('!SetVariable', 'EditorViewerImageX', tostring(previewX))



    SKIN:Bang('!SetVariable', 'EditorViewerImageY', tostring(previewY))



    SKIN:Bang('!SetVariable', 'EditorViewerImageW', tostring(adjustedW))



    SKIN:Bang('!SetVariable', 'EditorViewerImageH', tostring(adjustedH))



    SKIN:Bang('!UpdateMeter', 'MeterViewerPreviewImage')



end



local function syncImageAdjustmentUI(record)



    local adjustment = { OffsetX = 0, OffsetY = 0, SizeOffset = 0 }



    local imageAdjustKey = getImageAdjustmentKeyForRecord(record)



    if imageAdjustKey then



        adjustment = getDraftImageAdjustment(imageAdjustKey)



    end



    setImageAdjustInput('EditorImageAdjustXValue', 'EditorImageAdjustXDisplayText', 'EditorImageAdjustXPlaceholder', 'MeterImageAdjustText', adjustment.OffsetX)



    setImageAdjustInput('EditorImageAdjustYValue', 'EditorImageAdjustYDisplayText', 'EditorImageAdjustYPlaceholder', 'MeterImageAdjust2Text', toUserFacingImageOffsetY(adjustment.OffsetY))



    setImageAdjustInput('EditorImageAdjustSizeValue', 'EditorImageAdjustSizeDisplayText', 'EditorImageAdjustSizePlaceholder', 'MeterImageAdjust3Text', adjustment.SizeOffset)



    syncPreviewImageGeometry(adjustment)



end



local function setDirty(value)



    writeDraftMeta('Dirty', value and '1' or '0')



end



local function captureResponsiveLiveState(targetId, configPath)



    if not targetId or targetId == '' or not configPath or configPath == '' then



        return



    end



    if targetId == 'Inventory' then

        if EditorIsRainmeterConfigActive(configPath) then

            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()', configPath)

        end

        return

    end



    if trim(SKIN:GetVariable('ResponsiveLayout_' .. targetId .. '_LiveActive', '0')) == '1' and EditorIsRainmeterConfigActive(configPath) then



        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()', configPath)



    end



end





local function refreshItemConsumers(targets)



    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))



    if rootConfig == '' then



        return



    end



    local refreshHotbar = true



    local refreshInventory = true



    if type(targets) == 'table' then



        refreshHotbar = targets.hotbar ~= false



        refreshInventory = targets.inventory ~= false



    end



    if refreshHotbar then



        captureResponsiveLiveState('Hotbar', rootConfig .. '\\Hotbar')

        local hotbarConfig = rootConfig .. '\\Hotbar'

        if EditorIsRainmeterConfigActive(hotbarConfig) then

            SKIN:Bang('!Refresh', hotbarConfig, 'Hotbar.ini')

        end



    end



    if refreshInventory and isInventoryConsumerActive() then



        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', rootConfig .. '\\Inventory')



        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', rootConfig .. '\\Inventory')



        SKIN:Bang('!Redraw', rootConfig .. '\\Inventory')



    end



end



local function refreshConsumersAfterEditorClose()



    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))



    if rootConfig == '' then



        return



    end



    captureResponsiveLiveState('Hotbar', rootConfig .. '\\Hotbar')



    captureResponsiveLiveState('Inventory', rootConfig .. '\\Inventory')



    local hotbarConfig = rootConfig .. '\\Hotbar'

    if EditorIsRainmeterConfigActive(hotbarConfig) then

        SKIN:Bang('!Refresh', hotbarConfig, 'Hotbar.ini')

    end



    if isInventoryConsumerActive() then

        local inventoryBgConfig = rootConfig .. '\\InventoryBG'

        if EditorIsRainmeterConfigActive(inventoryBgConfig) then

            SKIN:Bang('!Refresh', inventoryBgConfig, 'InventoryBG.ini')

        end



        SKIN:Bang('!Refresh', rootConfig .. '\\Inventory', 'Inventory.ini')

    end



end

local function refreshDraftItemConsumersLite(targets)



    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))



    if rootConfig == '' then



        return



    end



    local refreshHotbar = true



    local refreshInventory = true



    if type(targets) == 'table' then



        refreshHotbar = targets.hotbar ~= false



        refreshInventory = targets.inventory ~= false



    end



    if refreshHotbar then



        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', "InitInfos('force')", rootConfig .. '\\Hotbar')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', rootConfig .. '\\Hotbar')



    end



    if refreshInventory and isInventoryConsumerActive() then



        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', "InitInfos('force')", rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', rootConfig .. '\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', rootConfig .. '\\Inventory')



        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', rootConfig .. '\\Inventory')



        SKIN:Bang('!Redraw', rootConfig .. '\\Inventory')



    end



end
