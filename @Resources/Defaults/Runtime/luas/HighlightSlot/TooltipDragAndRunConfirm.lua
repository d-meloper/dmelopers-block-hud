-- Split from @Resources\Defaults\Runtime\luas\HighlightSlot.lua lines 806-1685.
local function UpdateInvTooltipText()
    if not curInfo then
        RunTooltipHide()
        return
    end
    local resultText = curInfo.ItemName or ''
    if (curInfo.Image or '') == '' then resultText = AddNotice(resultText, SKIN:GetVariable('Loc_HUD_MissingImage', '(이미지 없음)')) end
    if (curInfo.ItemName or '') == '' then resultText = AddNotice(resultText, SKIN:GetVariable('Loc_HUD_MissingItemName', '(아이템 이름 없음)')) end
    if (curInfo.ExecPath or '') == '' then resultText = AddNotice(resultText, SKIN:GetVariable('Loc_HUD_MissingExecPath', '(실행 경로 없음)')) end
    RunTooltipShowAt(resultText, false, lastMouseX, lastMouseY)
end
local function HideHighlight()
    if not showingHighlight then return end
    showingHighlight = false
    lastHighlightHlx = nil
    lastHighlightHly = nil
    SKIN:Bang('!HideMeter', 'MeterHighlight')
    SKIN:Bang(_G.DMeloper.BANG_REDRAW)
    if IsHotbar then
        hotbarTextVisible = false
        SKIN:Bang('!CommandMeasure', 'MeasureFade', 'Hide()')
    end
end
function HideEditorHighlight()
    LoadEssentials()
    HideHighlight()
end
local function ShowHighlight()
    if showingHighlight then return end
    showingHighlight = true
    SKIN:Bang('!ShowMeter', 'MeterHighlight')
end
local function getGridLayout(source)
    source = EditorItemService and EditorItemService.NormalizeSource(source) or source
    if source == currentSource() then
        return {
            source = source,
            x = X,
            y = Y,
            slotSize = SlotSize,
        }
    end
    if ResponsiveLayout and (source == 'hotbar' or source == 'inventory') then
        return ResponsiveLayout.ResolveRelativeGridLayout(SKIN, source)
    end
    return nil
end
local function getSlotCenter(layout, ix, iy)
    local extra = _G.DMeloper.GetRowExtraOffset(iy)
    return layout.x + ((ix - 0.5) * layout.slotSize),
        (layout.y - ((iy - 1) * layout.slotSize) - extra) + (layout.slotSize / 2)
end
local function getSlotInfoForSource(source, ix, iy)
    if source == currentSource() then
        return ItemInfosHolder.GetInfo(ix, iy)
    end
    local record = EditorItemService.GetSlotRecord(R, source, ix, iy)
    if not record or not record.Populated then
        return nil
    end
    return {
        Image = record.ImageKey,
        ItemName = record.ItemName,
        ExecPath = record.ExecPath,
        ConfirmBeforeRun = record.ConfirmBeforeRun,
        x = record.x,
        y = record.y,
        qty = record.Qty,
    }
end
local function HideSelectedHighlight()
    if not showingSelectedHighlight then return end
    showingSelectedHighlight = false
    lastSelectedHighlightKey = nil
    lastSelectedHlx = nil
    lastSelectedHly = nil
    lastSelectedHighlightSize = nil
    SKIN:Bang('!HideMeter', 'MeterSelectedSlotHighlight')
    SKIN:Bang(_G.DMeloper.BANG_REDRAW)
end
local function ShowSelectedHighlight()
    if showingSelectedHighlight then return end
    showingSelectedHighlight = true
    SKIN:Bang('!ShowMeter', 'MeterSelectedSlotHighlight')
end
local function getSelectedSlotForCurrentSurface()
    if not EditorItemService then
        return nil
    end
    local meta = EditorItemService.ReadDraftMetaOnly(R)
    if not meta.EditorOpen or EditorItemService.IsDraftSessionStale(R, meta) then
        return nil
    end
    if not meta.SelectedSource or meta.SelectedX < 1 or meta.SelectedY < 1 then
        return nil
    end
    local selectedSource = meta.SelectedSource
    local selectedX = meta.SelectedX
    local selectedY = meta.SelectedY
    local useBottom = EditorItemService.GetUseBottomSlot(R)
    if IsHotbar then
        if selectedSource == 'hotbar' and selectedY == 1 then
            return 'hotbar', selectedX, selectedY
        end
        return nil
    end
    if selectedSource == 'inventory' then
        return 'inventory', selectedX, selectedY
    end
    if selectedSource == 'hotbar' and not useBottom and selectedY == 1 and selectedX <= 9 then
        return 'inventory', selectedX, 1
    end
    return nil
end
function SyncSelectedSlotHighlight()
    LoadEssentials()
    local source, selectedX, selectedY = getSelectedSlotForCurrentSurface()
    if not source then
        HideSelectedHighlight()
        return
    end
    local layout = getGridLayout(source)
    if not layout then
        HideSelectedHighlight()
        return
    end
    local highlightSize = layout.slotSize + HighlightSizeOffset
    local centerOffset = ((layout.slotSize - highlightSize) / 2)
    local slotCenterX, slotCenterY = getSlotCenter(layout, selectedX, selectedY)
    local selectedHlx = slotCenterX - (layout.slotSize / 2) + centerOffset
    local selectedHly = slotCenterY - (layout.slotSize / 2) + centerOffset
    local selectionKey = table.concat({ tostring(source), tostring(selectedX), tostring(selectedY), tostring(layout.slotSize), tostring(HighlightSizeOffset) }, ':')
    local changed = false
    if selectionKey ~= lastSelectedHighlightKey or selectedHlx ~= lastSelectedHlx or selectedHly ~= lastSelectedHly then
        lastSelectedHighlightKey = selectionKey
        lastSelectedHlx = selectedHlx
        lastSelectedHly = selectedHly
        SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'selectedHlx', selectedHlx)
        SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'selectedHly', selectedHly)
        changed = true
    end
    if highlightSize ~= lastSelectedHighlightSize then
        lastSelectedHighlightSize = highlightSize
        SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'SelectedSlotHighlightSize', highlightSize)
        changed = true
    end
    if changed then
        SKIN:Bang(_G.DMeloper.BANG_UPDATE_METER, 'MeterSelectedSlotHighlight')
    end
    if not showingSelectedHighlight then
        ShowSelectedHighlight()
        changed = true
    end
    if changed then
        SKIN:Bang(_G.DMeloper.BANG_REDRAW)
    end
end
local function syncSelectedHighlightVisibilityGuard()
    if not showingSelectedHighlight then
        return
    end
    if getSelectedSlotForCurrentSurface() then
        return
    end
    HideSelectedHighlight()
end
local function UpdateHighlight()
    if lastIndexX < 1 or lastIndexY < 1 then
        return
    end
    local layout = getGridLayout(lastHighlightSource or currentSource())
    if not layout then
        return
    end
    local highlightSize = layout.slotSize + HighlightSizeOffset
    local centerOffset = ((layout.slotSize - highlightSize) / 2)
    local slotCenterX, slotCenterY = getSlotCenter(layout, lastIndexX, lastIndexY)
    local hlx = slotCenterX - (layout.slotSize / 2) + centerOffset
    local hly = slotCenterY - (layout.slotSize / 2) + centerOffset
    local highlightShapeSize = tostring(highlightSize)
    local currentHighlightShapeSize = tostring(SKIN:GetVariable('HighlightShapeSize', '') or '')
    if hlx == lastHighlightHlx and hly == lastHighlightHly and currentHighlightShapeSize == highlightShapeSize then
        return
    end
    lastHighlightHlx = hlx
    lastHighlightHly = hly
    SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'hlx', hlx)
    SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'hly', hly)
    SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'HighlightShapeSize', highlightShapeSize)
    SKIN:Bang(_G.DMeloper.BANG_UPDATE_METER, 'MeterHighlight')
end
UpdateItemText = function()
    if IsHotbar then UpdateHotbarText() else UpdateInvTooltipText() end
end
local function RedrawAfterItemUpdate()
    if IsHotbar then
        SKIN:Bang(_G.DMeloper.BANG_REDRAW)
    end
end
function RefreshHoveredInfo()
    LoadEssentials()
    ItemInfosHolder.RefreshInfos()
    local infoX = lastIndexX
    local infoY = lastIndexY
    if infoX < 1 or infoY < 1 then
        local _, selectedX, selectedY = getSelectedSlotForCurrentSurface()
        if not selectedX or not selectedY then
            return
        end
        infoX = selectedX
        infoY = selectedY
    end
    curInfo = ItemInfosHolder.GetInfo(infoX, infoY)
    UpdateItemText()
    RedrawAfterItemUpdate()
end
function RefreshCurrentTooltip()
    LoadEssentials()
    if isLowSpecHoverTextTooltipDisabled() then
        if isOptionHovering then
            RunTooltipCommand('RefreshCurrent()')
            return
        end
        RefreshHoveredInfo()
        return
    end
    if isOptionHovering then
        RunTooltipCommand('RefreshCurrent()')
        return
    end
    RefreshHoveredInfo()
end
local function EnterSlot(ix, iy)
    state = STATE_IN
    lastIndexX, lastIndexY = ix, iy
    lastHighlightSource = currentSource()
    curInfo = ItemInfosHolder.GetInfo(ix, iy)
    if isLowSpecSlotHoverHighlightDisabled() then
        HideHighlight()
    else
        UpdateHighlight()
        ShowHighlight()
    end
    UpdateItemText()
    RedrawAfterItemUpdate()
end
local function ChangeSlot(ix, iy)
    lastIndexX, lastIndexY = ix, iy
    lastHighlightSource = currentSource()
    curInfo = ItemInfosHolder.GetInfo(ix, iy)
    if isLowSpecSlotHoverHighlightDisabled() then
        HideHighlight()
    else
        UpdateHighlight()
        ShowHighlight()
    end
    UpdateItemText()
    RedrawAfterItemUpdate()
end
function LeaveSlot()
    state = STATE_OUT
    lastIndexX = -1
    lastIndexY = -1
    lastHighlightSource = nil
    curInfo = nil
    HideHighlight()
    if not isOptionHovering then
        RunTooltipHide()
    end
end
function EnterOptionHover(label)
    LoadEssentials()
    local meta = currentEditorMeta()
    if meta and meta.DragActive then
        return
    end
    isOptionHovering = true
    state = STATE_OUT
    curInfo = nil
    HideHighlight()
    if isLowSpecHoverTextTooltipDisabled() then
        if label and label ~= '' then
            RunTooltipShowAt(label, true, lastMouseX, lastMouseY)
        end
        return
    end
    if not IsHotbar then
        RunTooltipMove(lastMouseX, lastMouseY, true)
    end
    if label and label ~= '' then
        isTooltipVisible = true
        RunTooltipCommand(string.format('EnterOption(%q)', tostring(label or '')))
    end
end
function EnterOptionHoverVariable(variableName)
    EnterOptionHover(SKIN:GetVariable(tostring(variableName or '')) or '')
end
function LeaveOptionHover()
    LoadEssentials()
    isOptionHovering = false
    isTooltipVisible = false
    RunTooltipCommand('LeaveOption()')
end
local function IsPointInRect(x, y, left, top, width, height)
    return x >= left and x < (left + width) and y >= top and y < (top + height)
end
local function IsOptionHoverArea(x, y)
    if IsHotbar then return false end
    for _, area in ipairs(OPTION_HOVER_AREAS) do
        if area.hidden == '' or GetSkinValue(area.hidden) == 0 then
            local left = GetSkinValue(area.x)
            local top = GetSkinValue(area.y)
            local width = GetSkinValue(area.w)
            local height = GetSkinValue(area.h)
            if IsPointInRect(x, y, left, top, width, height) then
                return true
            end
        end
    end
    return false
end
local function GetSlotRowIndexForLayout(layout, minRow, maxRow, mouseY)
    for rowIndex = minRow, maxRow do
        local rowTop = layout.y - ((rowIndex - 1) * layout.slotSize) - _G.DMeloper.GetRowExtraOffset(rowIndex)
        local rowBottom = rowTop + layout.slotSize
        if mouseY >= rowTop and mouseY < rowBottom then
            return rowIndex
        end
    end
    return nil
end
local function ResolveSlotPointForLayout(layout, bounds, x, y)
    if not layout or not bounds then
        return nil, nil
    end
    local relX = x - layout.x
    local idxX = math.floor(relX / layout.slotSize) + 1
    local idxY = GetSlotRowIndexForLayout(layout, bounds.YMin, bounds.YMax, y)
    idxX = _G.DMeloper.Clamp(idxX, bounds.XMin - 1, bounds.XMax + 1)
    if idxX < bounds.XMin or idxX > bounds.XMax or idxY == nil then
        return nil, nil
    end
    return idxX, idxY
end
local function GetSlotRowIndex(mouseY)
    return GetSlotRowIndexForLayout({ y = Y, slotSize = SlotSize }, 1, SlotRows, mouseY)
end
local function ResolveSlotAtPoint(x, y)
    return ResolveSlotPointForLayout(
        { x = X, y = Y, slotSize = SlotSize },
        { XMin = 1, XMax = SlotColumns, YMin = 1, YMax = SlotRows },
        x,
        y
    )
end
local useBottomSlot
local isInventoryHotbarAliasRow
local shouldIgnoreHotbarEditorSurface
local shouldRouteHotbarInputToEditor
local resolveEditorCommandSource
local function resolveDragDropTargetForSource(source, x, y, useBottom)
    local bounds = EditorItemService.GetCoordBounds(source, useBottom)
    local layout = getGridLayout(source)
    local ix, iy = ResolveSlotPointForLayout(layout, bounds, x, y)
    if ix == nil or iy == nil then
        return nil
    end
    return { source = source, x = ix, y = iy }
end
local function oppositeDragDropSource(source)
    if source == 'hotbar' then
        return 'inventory'
    end
    if source == 'inventory' then
        return 'hotbar'
    end
    return nil
end
local function getDragDropTarget(x, y)
    local useBottom = useBottomSlot()
    if not IsHotbar and isEditorOpen() and not useBottom then
        local layout = getGridLayout('inventory')
        local ix, iy = ResolveSlotPointForLayout(layout, { XMin = 1, XMax = 9, YMin = 1, YMax = 4 }, x, y)
        if ix == nil or iy == nil then
            return nil
        end
        local targetSource = (iy == 1) and 'hotbar' or 'inventory'
        return { source = targetSource, x = ix, y = iy }
    end
    local source = currentSource()
    local target = resolveDragDropTargetForSource(source, x, y, useBottom)
    if target then
        return target
    end
    if useBottom and isEditorOpen() then
        local oppositeSource = oppositeDragDropSource(source)
        if oppositeSource then
            return resolveDragDropTargetForSource(oppositeSource, x, y, useBottom)
        end
    end
    return nil
end
function HideLocalDragSourceSlot(meta)
    if not meta or not meta.DragActive then
        return
    end
    local source = EditorItemService.NormalizeSource(meta.DragSource)
    local dragX = tonumber(meta.DragX) or 0
    local dragY = tonumber(meta.DragY) or 0
    local sourceX = nil
    local sourceY = nil
    if dragX < 1 or dragY < 1 then
        return
    end
    if IsHotbar then
        if source == 'hotbar' and dragY == 1 then
            sourceX = dragX
            sourceY = dragY
        end
    elseif source == 'inventory' then
        sourceX = dragX
        sourceY = dragY
    elseif source == 'hotbar' and not useBottomSlot() and dragY == 1 and dragX <= 9 then
        sourceX = dragX
        sourceY = 1
    end
    if not sourceX or not sourceY then
        return
    end
    local meterSuffix = 'x' .. tostring(sourceX) .. 'y' .. tostring(sourceY)
    local meterName = 'MeterSlot_' .. meterSuffix
    local meterTextName = 'MeterSlotText_' .. meterSuffix
    SKIN:Bang('!HideMeter', meterName)
    SKIN:Bang('!HideMeter', meterTextName)
    SKIN:Bang('!SetOption', meterTextName, 'Text', '')
    SKIN:Bang('!UpdateMeter', meterName)
    SKIN:Bang('!UpdateMeter', meterTextName)
end
local function clearDragPayload()
    dragPayloadKey = nil
    dragPayload = nil
end
local function dragHoverKey(target)
    if not target then
        return nil
    end
    return table.concat({ tostring(target.source), tostring(target.x), tostring(target.y) }, ':')
end
local function hasSameDragHoverTarget(target)
    if not dragHoverTracked then
        return false
    end
    if not target then
        return not dragHoverHasTarget
    end
    return dragHoverHasTarget and dragHoverTargetKey == dragHoverKey(target)
end
local function rememberDragHoverTarget(target)
    dragHoverTracked = true
    dragHoverHasTarget = target ~= nil
    dragHoverTargetKey = dragHoverKey(target)
end
local function resetDragHoverTracking()
    dragHoverTargetKey = nil
    dragHoverHasTarget = false
    dragHoverTracked = false
    dragInsideNotified = false
end
local function hideDragVisual()
    resetDragHoverTracking()
    clearDragPayload()
    dragVisualImage.path = nil
    dragVisualImage.crop = nil
    dragVisualImageX = nil
    dragVisualImageY = nil
    dragVisualImageSize = nil
    dragVisualText = nil
    dragVisualTextX = nil
    dragVisualTextY = nil
    dragVisualTextVisible = false
    if not activeDragVisual then return end
    activeDragVisual = false
    SKIN:Bang('!HideMeter', DRAG_IMAGE_METER)
    SKIN:Bang('!HideMeter', DRAG_TEXT_METER)
    SKIN:Bang('!UpdateMeter', DRAG_IMAGE_METER)
    SKIN:Bang('!UpdateMeter', DRAG_TEXT_METER)
    SKIN:Bang('!Redraw')
end
function HideEditorDragVisual()
    LoadEssentials()
    hideDragVisual()
end
function HidePeerEditorDragSurfaceState()
    LoadEssentials()
    local rootConfig = tostring(SKIN:GetVariable('ROOTCONFIG', '') or ''):match('^%s*(.-)%s*$')
    if rootConfig == '' then
        return
    end
    local peerConfig = rootConfig .. '\\HUD\\' .. (IsHotbar and 'Inventory' or 'Hotbar')
    if isRainmeterConfigActive and not isRainmeterConfigActive(peerConfig) then
        return
    end
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'HideEditorDragVisual()', peerConfig)
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'HideEditorHighlight()', peerConfig)
end
local function ensureDragPayload(meta)
    if not meta or not meta.DragActive or not meta.DragSource then
        clearDragPayload()
        return nil
    end
    local payloadKey = table.concat({ tostring(meta.DragSource), tostring(meta.DragX), tostring(meta.DragY) }, ':')
    if dragPayloadKey == payloadKey and dragPayload then
        return dragPayload
    end
    local dragRecord = EditorItemService.GetDraftSlotRecord(R, meta.DragSource, meta.DragX, meta.DragY)
    if not dragRecord or not dragRecord.Populated then
        clearDragPayload()
        return nil
    end
    local offsetX, offsetY, offsetSize = ImageAdjuster.GetAdjustments(dragRecord.ImageKey)
    local presentation = EditorItemService.GetImagePresentation(
        R,
        dragRecord.ImageKey,
        SKIN:GetVariable('ItemImageAtlasProfiles', ''))
    dragPayloadKey = payloadKey
    dragPayload = {
        imagePath = presentation.ImagePath,
        imageCrop = presentation.ImageCrop,
        qty = dragRecord.Qty or 0,
        adjustedItemSize = ItemSize + offsetSize,
        offsetX = offsetX,
        offsetY = offsetY,
    }
    return dragPayload
end
local function updateDragVisual(x, y, meta)
    local payload = ensureDragPayload(meta)
    if not payload then
        hideDragVisual()
        return
    end
    HideLocalDragSourceSlot(meta)
    local imageX = x - (payload.adjustedItemSize / 2) + payload.offsetX
    local imageY = y - (payload.adjustedItemSize / 2) + payload.offsetY
    local imageDirty = false
    local textDirty = false
    if payload.imagePath ~= dragVisualImage.path then
        dragVisualImage.path = payload.imagePath
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'ImageName', payload.imagePath)
        imageDirty = true
    end
    if payload.imageCrop ~= dragVisualImage.crop then
        dragVisualImage.crop = payload.imageCrop
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'ImageCrop', payload.imageCrop)
        imageDirty = true
    end
    if imageX ~= dragVisualImageX then
        dragVisualImageX = imageX
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'X', imageX)
        imageDirty = true
    end
    if imageY ~= dragVisualImageY then
        dragVisualImageY = imageY
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'Y', imageY)
        imageDirty = true
    end
    if payload.adjustedItemSize ~= dragVisualImageSize then
        dragVisualImageSize = payload.adjustedItemSize
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'W', payload.adjustedItemSize)
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'H', payload.adjustedItemSize)
        imageDirty = true
    end
    if not activeDragVisual then
        SKIN:Bang('!ShowMeter', DRAG_IMAGE_METER)
        imageDirty = true
    end
    if payload.qty > 1 then
        local textValue = tostring(payload.qty)
        local textX = imageX + payload.adjustedItemSize
        local textY = imageY + payload.adjustedItemSize - 22
        if textValue ~= dragVisualText then
            dragVisualText = textValue
            SKIN:Bang('!SetOption', DRAG_TEXT_METER, 'Text', textValue)
            textDirty = true
        end
        if textX ~= dragVisualTextX then
            dragVisualTextX = textX
            SKIN:Bang('!SetOption', DRAG_TEXT_METER, 'X', textX)
            textDirty = true
        end
        if textY ~= dragVisualTextY then
            dragVisualTextY = textY
            SKIN:Bang('!SetOption', DRAG_TEXT_METER, 'Y', textY)
            textDirty = true
        end
        if not dragVisualTextVisible then
            dragVisualTextVisible = true
            SKIN:Bang('!ShowMeter', DRAG_TEXT_METER)
            textDirty = true
        end
    else
        dragVisualText = nil
        dragVisualTextX = nil
        dragVisualTextY = nil
        if dragVisualTextVisible then
            dragVisualTextVisible = false
            SKIN:Bang('!HideMeter', DRAG_TEXT_METER)
            textDirty = true
        end
    end
    if imageDirty then
        SKIN:Bang('!UpdateMeter', DRAG_IMAGE_METER)
    end
    if textDirty then
        SKIN:Bang('!UpdateMeter', DRAG_TEXT_METER)
    end
    if imageDirty or textDirty then
        SKIN:Bang('!Redraw')
    end
    activeDragVisual = true
end
clearStaleEditorSession = function()
    local meta = EditorItemService.ReadDraftMetaOnly(R)
    hideDragVisual()
    isMouseDown = false
    mouseDownX = 0
    mouseDownY = 0
    LeaveSlot()
    for key, value in pairs({
        Dirty = '0',
        EditorOpen = '0',
        HeartbeatClockMs = '0',
        SelectedSource = '',
        SelectedX = '0',
        SelectedY = '0',
        SelectedSection = '',
        DragSource = '',
        DragX = '0',
        DragY = '0',
        DragActive = '0',
        PickerModalOpen = '0',
    }) do
        SKIN:Bang('!SetVariable', 'EditorDraftMeta_' .. key, value)
    end
    suppressNextMouseUp = true
    if meta.DragActive then
        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()')
        SKIN:Bang('!Refresh')
    end
end
isEditorOpen = function()
    local meta = EditorItemService.ReadDraftMetaOnly(R)
    if not meta.EditorOpen then
        return false
    end
    if EditorItemService.IsDraftSessionStale(R, meta) then
        clearStaleEditorSession()
        return false
    end
    return true
end
useBottomSlot = function()
    return EditorItemService.GetUseBottomSlot(R)
end
isInventoryHotbarAliasRow = function(ix, iy)
    if IsHotbar then
        return false
    end
    if tonumber(iy) ~= 1 then
        return false
    end
    if not isEditorInteractive() then
        return false
    end
    return not useBottomSlot()
end
shouldRouteHotbarInputToEditor = function()
    return IsHotbar and isEditorInteractive()
end
shouldIgnoreHotbarEditorSurface = function()
    return false
end
resolveEditorCommandSource = function(ix, iy)
    if IsHotbar then
        return 'hotbar'
    end
    if isInventoryHotbarAliasRow(ix, iy) then
        return 'hotbar'
    end
    return currentSource()
end
local function syncHotbarTextVisibility()
    if not IsHotbar then
        return
    end
    local shouldEnable = not isHotbarEditingMode()
    if hotbarTextEnabled == shouldEnable then
        return
    end
    if not shouldEnable then
        hotbarTextVisible = false
    end
    hotbarTextEnabled = shouldEnable
    SKIN:Bang('!CommandMeasure', 'MeasureFade', shouldEnable and 'Enable()' or 'Disable()')
end
function RollHerobrineInventoryReplacement()
    LoadEssentials()
    return callHerobrine('RollInventoryReplacement')
end
function SyncHerobrineSettings(enabled)
    LoadEssentials()
    return callHerobrine('SyncSettings', enabled)
end
function CaptureHerobrineInventoryReplacement()
    LoadEssentials()
    return callHerobrine('CaptureInventoryReplacement')
end
function HandleHerobrineInventoryClose()
    LoadEssentials()
    return callHerobrine('CloseInventory')
end
local function getRunConfirmDisplayName(info)
    local display = trimText(info and info.ItemName or '')
    if display == '' then
        display = RunConfirm.localizedText('Loc_HUD_MissingItemName', '(missing item name)')
    end
    return display
end
function RunConfirm.localizedText(key, fallback)
    local value = trimText(SKIN:GetVariable(key, fallback or ''))
    if value == '' then
        return fallback or ''
    end
    return value
end
function RunConfirm.modalConfigPath(rootPath)
    if rootPath == nil or rootPath == '' then
        return ''
    end
    return rootPath .. '\\Utilities\\Modal'
end
function RunConfirm.setLock(token)
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath == nil or rootPath == '' then
        return
    end
    local value = tostring(token or '')
    local currentConfig = trimText(SKIN:GetVariable('CURRENTCONFIG', ''))
    for _, configName in ipairs({ 'Hotbar', 'Inventory' }) do
        local targetConfig = rootPath .. '\\HUD\\' .. configName
        if targetConfig ~= currentConfig and isRainmeterConfigActive and isRainmeterConfigActive(targetConfig) then
            SKIN:Bang('!SetVariable', RunConfirm.lockVariable, value, targetConfig)
        end
    end
    SKIN:Bang('!SetVariable', RunConfirm.lockVariable, value)
end
function RunConfirm.currentLock()
    return trimText(SKIN:GetVariable(RunConfirm.lockVariable, ''))
end
function RunConfirm.clear()
    RunConfirm.pending = nil
    RunConfirm.setLock('')
end
function RunConfirm.nextToken()
    RunConfirm.counter = RunConfirm.counter + 1
    local clockPart = tostring(os.clock()):gsub('[^0-9]', '')
    return currentSource() .. '-' .. clockPart .. '-' .. tostring(RunConfirm.counter)
end
function RunConfirm.isModalActive(rootPath)
    local configPath = RunConfirm.modalConfigPath(rootPath)
    return configPath ~= '' and isRainmeterConfigActive and isRainmeterConfigActive(configPath)
end
function RunConfirm.preload(rootPath, activateModal)
    local configPath = RunConfirm.modalConfigPath(rootPath)
    if configPath == '' then
        return
    end
    RunConfirm.modalPreloadRequested = true
    SKIN:Bang('!SetVariable', 'BlockHudModalPreloaded', '1')
    if activateModal ~= false and not RunConfirm.isModalActive(rootPath) then
        SKIN:Bang('!ActivateConfig', configPath, 'Modal.ini')
    end
end
function RunConfirm.showPendingModal()
    local pending = RunConfirm.pending
    if pending == nil or trimText(pending.openCommand) == '' then
        return false
    end
    if RunConfirm.currentLock() ~= tostring(pending.token or '') then
        RunConfirm.pending = nil
        return false
    end
    local configPath = RunConfirm.modalConfigPath(SKIN:GetVariable('ROOTCONFIG'))
    if configPath == '' then
        logWarning('[HighlightSlot] could not resolve Modal config path for pending run confirmation.')
        return false
    end
    SKIN:Bang('!CommandMeasure', 'MeasureModal', pending.openCommand, configPath)
    return true
end
function RunConfirm.deferOpen(rootPath)
    local configPath = RunConfirm.modalConfigPath(rootPath)
    if configPath == '' then
        return
    end
    if not RunConfirm.isModalActive(rootPath) then
        SKIN:Bang('!ActivateConfig', configPath, 'Modal.ini')
    end
    SKIN:Bang('!SetVariable', RunConfirm.deferredOpenVariable, '0')
    SKIN:Bang('!UpdateMeasure', 'MeasureRunConfirmDeferredOpen')
    SKIN:Bang('!SetVariable', RunConfirm.deferredOpenVariable, '1')
    SKIN:Bang('!UpdateMeasure', 'MeasureRunConfirmDeferredOpen')
end
function RunConfirm.open(info, exec, action)
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    local configPath = RunConfirm.modalConfigPath(rootPath)
    if configPath == '' then
        logWarning('[HighlightSlot] could not resolve Modal config path for run confirmation.')
        return false
    end
    local modalIsActive = RunConfirm.isModalActive(rootPath)
    RunConfirm.clear()
    local token = RunConfirm.nextToken()
    if IsInternalWebNowPlayingCoverPath(exec) then
        return false
    end
    RunConfirm.pending = {
        token = token,
        exec = exec,
        action = action,
        openCommand = '',
    }
    RunConfirm.setLock(token)
    local displayName = getRunConfirmDisplayName(info)
    local command = 'OpenConfirmByKeys('
        .. LuaStringLiteral(SKIN:GetVariable('CURRENTCONFIG')) .. ','
        .. LuaStringLiteral(token) .. ','
        .. LuaStringLiteral('Loc_RunConfirm_Title') .. ','
        .. LuaStringLiteral('Loc_RunConfirm_Message') .. ','
        .. LuaStringLiteral('Loc_RunConfirm_Run') .. ','
        .. LuaStringLiteral('Loc_Common_Cancel') .. ','
        .. LuaStringLiteral('MeasureHighlight') .. ','
        .. LuaStringLiteral('ConfirmPendingRun') .. ','
        .. LuaStringLiteral('CancelPendingRun') .. ','
        .. LuaStringLiteral(displayName) .. ')'
    RunConfirm.pending.openCommand = command
    if modalIsActive and RunConfirm.showPendingModal() then
        return true
    end
    logWarning('[HighlightSlot] Modal was not active before run confirmation; activating deferred fallback path.')
    RunConfirm.deferOpen(rootPath)
    return true
end
local function modalAlertLogPath()
    local rootPath = trimText(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    return rootPath .. 'Logs\\DMeloper' .. string.char(39) .. 's Block HUD Log.log'
end
local function modalAlertHost()
    return {
        skin = SKIN,
        name = IsHotbar and 'Hotbar' or 'Inventory',
        targetConfig = SKIN:GetVariable('CURRENTCONFIG', ''),
        targetMeasure = 'MeasureHighlight',
        deferredVariable = 'BlockHudHudModalAlertDeferredOpen',
        deferredMeasure = 'MeasureHudModalAlertDeferredOpen',
        logPath = modalAlertLogPath(),
        openLogCallback = 'OpenModalAlertLogFolder',
        openFolder = function()
            return startHudOpenLogFolderHelper()
        end,
    }
end
local function showHudModalAlert(level, summaryKey, fallback)
    if not ModalAlertBridge then
        return false
    end
    local key = trimText(summaryKey or '')
    local summary = trimText(SKIN:GetVariable('Loc_' .. key, fallback or ''))
    if summary == '' then
        summary = trimText(fallback or '')
    end
    return ModalAlertBridge.ShowAlertByKeys(modalAlertHost(), {
        level = level,
        summaryKey = key,
        summaryText = summary,
        logPath = modalAlertLogPath(),
    })
end
local function hasAssignedItemData(info)
    if not info then
        return false
    end
    return trimText(info.ItemName or '') ~= '' or trimText(info.Image or '') ~= ''
end
