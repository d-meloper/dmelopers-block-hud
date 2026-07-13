-- Split from @Resources\Defaults\Runtime\luas\HighlightSlot.lua lines 1686-2446.
local function performClickAction(info)
    if not info then return end
    local now = os.clock()
    if (now - lastClickT) < 0.5 then return end
    lastClickT = now
    local exec = info.ExecPath
    if not exec or exec == '' then
        if hasAssignedItemData(info) then
            showHudModalAlert('warn', 'ModalAlert_HudActionMissing', 'This slot has no action assigned.')
        end
        return
    end
    if IsInternalWebNowPlayingCoverPath(exec) then
        return
    end
    local confirmBeforeRun = trimText(info and info.ConfirmBeforeRun or '') == '1'
    PlayClickSound()
    if IsInventoryItem(exec) then
        ActivateAllInventory()
        LeaveSlot()
        return
    end
    local bang = BuildBang(exec)
    if not bang then
        showHudModalAlert('error', 'ModalAlert_HudActionInvalid', 'This slot action is invalid and could not be run. Edit the item action and try again.')
        return
    end
    if confirmBeforeRun then
        RunConfirm.open(info, exec, bang)
        return
    end
    SKIN:Bang(bang)
end
local function normalizeSlotIndex(value)
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end
    numeric = math.floor(numeric)
    if numeric < 1 then
        return nil
    end
    return numeric
end
local function syncSlotMeterState(ix, iy)
    LoadEssentials()
    ix = normalizeSlotIndex(ix)
    iy = normalizeSlotIndex(iy)
    if ix == nil or iy == nil then
        return false
    end
    if ix > SlotColumns or iy > SlotRows then
        return false
    end
    local centerX, centerY = getSlotCenter({ x = X, y = Y, slotSize = SlotSize }, ix, iy)
    lastMouseX = centerX
    lastMouseY = centerY
    if shouldIgnoreHotbarEditorSurface() then
        LeaveSlot()
        return false
    end
    if state == STATE_OUT then
        EnterSlot(ix, iy)
    elseif ix ~= lastIndexX or iy ~= lastIndexY or lastHighlightSource ~= currentSource() then
        ChangeSlot(ix, iy)
    elseif curInfo == nil then
        curInfo = ItemInfosHolder.GetInfo(ix, iy)
        UpdateItemText()
        RedrawAfterItemUpdate()
    end
    return true
end
function OnSlotMouseDown(ix, iy)
    syncSlotMeterState(ix, iy)
end
function OnSlotMouseUp(ix, iy)
    syncSlotMeterState(ix, iy)
end
function NotifyDragInside()
    LoadEssentials()
    if not isEditorOpen() then
        return
    end
    if dragInsideNotified then
        return
    end
    dragInsideNotified = true
    SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', 'NotifyDragInside()', editorConfigPath())
end
function OnMouseMove(x, y)
    LoadEssentials()
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    lastMouseX = x
    lastMouseY = y
    local disableSlotHoverHighlight = isLowSpecSlotHoverHighlightDisabled()
    local disableHoverTextTooltip = isLowSpecHoverTextTooltipDisabled()
    local meta = currentEditorMeta()
    local dragActive = meta and meta.DragActive or false
    if not IsHotbar then
        if not disableHoverTextTooltip then
            RunTooltipMove(x, y)
        end
        if not dragActive and (isOptionHovering or IsOptionHoverArea(x, y)) then
            if disableHoverTextTooltip then
                LeaveSlot()
            end
            return
        end
    end
    if shouldIgnoreHotbarEditorSurface() then
        LeaveSlot()
        return
    end
    if meta then
        if isMouseDown and not meta.DragActive and curInfo then
            local dx = x - mouseDownX
            local dy = y - mouseDownY
            if ((dx * dx) + (dy * dy)) >= (dragThreshold * dragThreshold) then
                local source = resolveEditorCommandSource(curInfo.x, curInfo.y)
                if not EditorItemService.IsReservedHotbarSlot(source, curInfo.x, curInfo.y) then
                    SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', string.format("BeginDrag('%s', %d, %d)", source, curInfo.x, curInfo.y), editorConfigPath())
                    meta = EditorItemService.ReadDraftMetaOnly(R)
                    ensureDragPayload(meta)
                end
            end
        end
        if meta.DragActive then
            HidePeerEditorDragSurfaceState()
            local target = getDragDropTarget(x, y)
            if not hasSameDragHoverTarget(target) then
                rememberDragHoverTarget(target)
                if target then
                    lastIndexX, lastIndexY = target.x, target.y
                    lastHighlightSource = target.source
                    curInfo = getSlotInfoForSource(target.source, target.x, target.y)
                    UpdateHighlight()
                    ShowHighlight()
                else
                    lastIndexX = -1
                    lastIndexY = -1
                    lastHighlightSource = nil
                    curInfo = nil
                    HideHighlight()
                    if not IsHotbar then
                        RunTooltipHide()
                    end
                end
            end
            NotifyDragInside()
            updateDragVisual(x, y, meta)
            return
        end
    end
    local idxX, idxY = ResolveSlotAtPoint(x, y)
    if idxX == nil or idxY == nil then
        LeaveSlot()
        return
    end
    if state == STATE_IN and idxX == lastIndexX and idxY == lastIndexY then
        if disableSlotHoverHighlight then
            if curInfo == nil then
                curInfo = ItemInfosHolder.GetInfo(idxX, idxY)
                UpdateItemText()
                RedrawAfterItemUpdate()
            end
            if IsHotbar then
                ShowHotbarText()
            end
            HideHighlight()
            return
        end
        if curInfo == nil then
            curInfo = ItemInfosHolder.GetInfo(idxX, idxY)
            UpdateItemText()
            RedrawAfterItemUpdate()
        end
        if IsHotbar then
            ShowHotbarText()
        end
        return
    end
    if state == STATE_OUT then
        EnterSlot(idxX, idxY)
        return
    end
    ChangeSlot(idxX, idxY)
end
function OnMouseDown(x, y)
    LoadEssentials()
    suppressNextMouseUp = false
    clearHotbarWindowDragState()
    local disableSlotHoverHighlight = isLowSpecSlotHoverHighlightDisabled()
    local disableHoverTextTooltip = isLowSpecHoverTextTooltipDisabled()
    local meta = currentEditorMeta()
    if shouldIgnoreHotbarEditorSurface() then
        LeaveSlot()
        isMouseDown = false
        clearHotbarWindowDragState()
        return
    end
    if meta and meta.DragActive then
        SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', 'CancelDrag()', editorConfigPath())
        hideDragVisual()
        LeaveSlot()
        isMouseDown = false
        return
    end
    if disableHoverTextTooltip and not IsHotbar and IsOptionHoverArea(tonumber(x) or 0, tonumber(y) or 0) then
        LeaveSlot()
        isMouseDown = false
        return
    end
    isMouseDown = true
    mouseDownX = tonumber(x) or 0
    mouseDownY = tonumber(y) or 0
    captureHotbarWindowDragStart()
    if disableSlotHoverHighlight or disableHoverTextTooltip then
        local idxX, idxY = ResolveSlotAtPoint(mouseDownX, mouseDownY)
        if idxX ~= nil and idxY ~= nil then
            state = STATE_IN
            lastIndexX, lastIndexY = idxX, idxY
            lastHighlightSource = currentSource()
            curInfo = ItemInfosHolder.GetInfo(idxX, idxY)
        else
            LeaveSlot()
        end
    end
end
function OnMouseLeave()
    LoadEssentials()
    clearHotbarWindowDragState()
    local meta = currentEditorMeta()
    if meta and meta.DragActive then
        dragInsideNotified = false
        SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', 'NotifyDragOutside()', editorConfigPath())
        hideDragVisual()
        LeaveSlot()
        return
    end
    hideDragVisual()
    LeaveSlot()
end
function OnMouseUp(x, y)
    LoadEssentials()
    x = tonumber(x) or lastMouseX
    y = tonumber(y) or lastMouseY
    lastMouseX = x
    lastMouseY = y
    local disableSlotHoverHighlight = isLowSpecSlotHoverHighlightDisabled()
    local disableHoverTextTooltip = isLowSpecHoverTextTooltipDisabled()
    local meta = currentEditorMeta()
    local dragActive = meta and meta.DragActive or false
    if not dragActive and isOptionHovering then
        isMouseDown = false
        clearHotbarWindowDragState()
        return
    end
    if not dragActive and disableHoverTextTooltip and not IsHotbar and IsOptionHoverArea(x, y) then
        isMouseDown = false
        clearHotbarWindowDragState()
        return
    end
    if shouldIgnoreHotbarEditorSurface() then
        LeaveSlot()
        isMouseDown = false
        clearHotbarWindowDragState()
        return
    end
    local shouldRouteToEditor = isEditorInteractive() and (not IsHotbar or shouldRouteHotbarInputToEditor())
    if shouldRouteToEditor
        and not (
            IsHotbar
            and not isPanelActive('Inventory')
            and EditorItemService.IsReservedHotbarSlot('hotbar', lastIndexX, lastIndexY)
        ) then
        if lastIndexX < 1 or lastIndexY < 1 then
            local idxX, idxY = ResolveSlotAtPoint(x, y)
            if idxX ~= nil and idxY ~= nil then
                lastIndexX, lastIndexY = idxX, idxY
                if state == STATE_OUT then
                    EnterSlot(idxX, idxY)
                else
                    ChangeSlot(idxX, idxY)
                end
            end
        end
        local meta = EditorItemService.ReadDraftMetaOnly(R)
        if meta.DragActive then
            local target = getDragDropTarget(x, y)
            if target then
                SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', string.format("CommitDragTo('%s', %d, %d)", target.source, target.x, target.y), editorConfigPath())
            else
                SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', 'CancelDrag()', editorConfigPath())
            end
            hideDragVisual()
            isMouseDown = false
            clearHotbarWindowDragState()
            return
        end
        if lastIndexX >= 1 and lastIndexY >= 1 then
            local source = resolveEditorCommandSource(lastIndexX, lastIndexY)
            SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', string.format("SelectDraftTarget('%s', %d, %d)", source, lastIndexX, lastIndexY), editorConfigPath())
        end
        isMouseDown = false
        clearHotbarWindowDragState()
        return
    end
    if suppressNextMouseUp then
        suppressNextMouseUp = false
        isMouseDown = false
        clearHotbarWindowDragState()
        return
    end
    if (disableSlotHoverHighlight or disableHoverTextTooltip) and curInfo == nil then
        local idxX, idxY = ResolveSlotAtPoint(x, y)
        if idxX ~= nil and idxY ~= nil then
            curInfo = ItemInfosHolder.GetInfo(idxX, idxY)
        end
    end
    if not detectHotbarWindowMovement() then
        performClickAction(curInfo)
    end
    isMouseDown = false
    clearHotbarWindowDragState()
end
local EDITOR_DRAFT_META_KEYS = {
    'SchemaVersion',
    'Dirty',
    'EditorOpen',
    'HeartbeatClockMs',
    'PickerModalOpen',
    'SelectedSource',
    'SelectedX',
    'SelectedY',
    'SelectedSection',
    'DragSource',
    'DragX',
    'DragY',
    'DragActive',
}
local function syncEditorDraftMetaToConfig(configPath, overrides)
    if not configPath or configPath == '' then
        return
    end
    for _, key in ipairs(EDITOR_DRAFT_META_KEYS) do
        local variableName = 'EditorDraftMeta_' .. key
        local value = overrides and overrides[key]
        if value == nil then
            value = SKIN:GetVariable(variableName, nil)
        end
        if value ~= nil then
            SKIN:Bang('!SetVariable', variableName, tostring(value), configPath)
        end
    end
end
local function primeEditorOpenState(rootPath)
    if not rootPath or rootPath == '' then
        return
    end
    local openOverrides = {
        EditorOpen = '1',
        HeartbeatClockMs = tostring(EditorItemService.GetCurrentSessionClockMs()),
    }
    for _, configName in ipairs({ 'HUD\\Hotbar', 'HUD\\Inventory', 'HUD\\InventoryBG' }) do
        local configPath = rootPath .. '\\' .. configName
        if isRainmeterConfigActive(configPath) then
            syncEditorDraftMetaToConfig(configPath, openOverrides)
        end
    end
    local inventoryConfig = rootPath .. '\\HUD\\Inventory'
    if IsInventoryVisibleStateEnabled() and isRainmeterConfigActive(inventoryConfig) then
        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', inventoryConfig)
        SKIN:Bang('!Redraw', inventoryConfig)
    end
    resetHotbarInteraction(rootPath)
end
function StartInventoryResponsiveLayoutTimer()
    if not IsInventoryVisibleStateEnabled() then
        ResidentUpdateController.SetDriver('Inventory', 'runtime', false)
        return 0
    end
    ResidentUpdateController.SetDriver('Inventory', 'runtime', true)
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    return 0
end

function StopInventoryResponsiveLayoutTimer()
    ResidentUpdateController.SetDriver('Inventory', 'runtime', false)
    return 0
end

function ContinueInventoryResponsiveLayoutTimer()
    return StartInventoryResponsiveLayoutTimer()
end
function ResumeInventoryResident()
    LoadEssentials()
    ResidentUpdateController.ResumeSurface('Inventory')
    PreloadModal()
    SKIN:Bang('!CommandMeasure', 'MeasurePlayerSkinState', 'Sync()')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
    StartInventoryResponsiveLayoutTimer()
    SKIN:Bang('!Draggable', SKIN:GetVariable('AllowInventoryDrag', '1'))
    SKIN:Bang('!SnapEdges', SKIN:GetVariable('AllowInventorySnapEdges', '1'))
    SKIN:Bang('!UnpauseMeasure', 'MeasureAnimation')
    SKIN:Bang('!CommandMeasure', 'MeasureAnimation', 'Sync()')
    SKIN:Bang('!UpdateMeasure', 'MeasureAnimation')
    SKIN:Bang('!UpdateMeter', 'MeterPlayerDefault')
    SKIN:Bang('!UpdateMeter', 'MeterPlayerCustom')
    ApplyInventoryStaticLocalizationTextFits()
    SKIN:Bang('!UpdateMeter', 'MeterEditorModeBadgeLabel')
    SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()')
    SKIN:Bang('!Redraw')
end
function RestoreInventoryResidentOnRefresh()
    LoadEssentials()
    local wasVisible = IsInventoryVisibleStateEnabled()
    if not wasVisible then
        SKIN:Bang('!UpdateMeasure', 'MeasureInventoryEnableGuard')
        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
        SuspendInventoryResident()
        return
    end
    ResumeInventoryResident()
end
function SuspendInventoryResident()
    LoadEssentials()
    callHerobrine('CloseInventory')
    ResetInteractionState()
    StopInventoryResponsiveLayoutTimer()
    SKIN:Bang('!CommandMeasure', 'MeasureAnimation', 'StopAnimationTimer()')
    SKIN:Bang('!PauseMeasure', 'MeasureAnimation')
    ResidentUpdateController.SuspendSurface('Inventory')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
    SKIN:Bang('!Redraw')
end
local prepareInventoryOpenPosition = nil
local showResidentConfigAfterLayout = nil

function ApplyInventoryBackdropOpenZOrder(rootPath)
    rootPath = tostring(rootPath or SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath == '' then
        return
    end

    local inventoryBgConfig = rootPath .. '\\HUD\\InventoryBG'
    local hudBelowBackdropConfigs = {
        rootPath .. '\\HUD\\Hotbar',
        rootPath .. '\\HUD\\Clock',
        rootPath .. '\\HUD\\ClockSprite',
        rootPath .. '\\HUD\\Indicators\\Heart',
        rootPath .. '\\HUD\\Indicators\\Armor',
        rootPath .. '\\HUD\\Indicators\\Food',
        rootPath .. '\\HUD\\Indicators\\Air',
        rootPath .. '\\HUD\\Indicators\\Exp'
    }

    if isRainmeterConfigActive(inventoryBgConfig) then
        SKIN:Bang('!ZPos', '-1', inventoryBgConfig)
    end
    for _, configPath in ipairs(hudBelowBackdropConfigs) do
        if isRainmeterConfigActive(configPath) then
            SKIN:Bang('!ZPos', '-2', configPath)
        end
    end
end

function RestoreInventoryBackgroundActiveConfig()
    LoadEssentials()
    InventoryLifecycle.CreateInventoryBgSurface():ShowActiveAfterLayout()
    SKIN:Bang('!Redraw')
end

function HideInventoryBackgroundActiveConfig()
    InventoryLifecycle.CreateInventoryBgSurface():SuspendIfActiveThenHide()
    SKIN:Bang('!Redraw')
end

function UnloadInventoryBackgroundActiveConfig()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
    SKIN:Bang('!DeactivateConfig')
end

function ShouldUnloadInventoryBackground()
    return trimText(SKIN:GetVariable('EnableInventorySkin', '1')) == '0'
end

function RestoreInventoryAfterBackgroundReady()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath == '' then
        return
    end
    local inventoryConfig = rootPath .. '\\HUD\\Inventory'
    local inventoryActive = isRainmeterConfigActive(inventoryConfig)
    prepareInventoryOpenPosition(inventoryActive, inventoryConfig)
    if not inventoryActive then
        RequestInventoryActivation(inventoryConfig)
        return
    end
    local editorOpen = isEditorOpen()
    if editorOpen then
        syncEditorDraftMetaToConfig(inventoryConfig)
    end
    showResidentConfigAfterLayout(inventoryConfig)
    HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'ResumeInventoryResident()', inventoryConfig)
    if editorOpen then
        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', inventoryConfig)
        SKIN:Bang('!Redraw', inventoryConfig)
    end
    HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'RollHerobrineInventoryReplacement()', inventoryConfig)
end

function RestoreInventoryBackgroundActiveConfigOnRefresh()
    LoadEssentials()
    if RainmeterConfigState then
        RainmeterConfigState.Register(SKIN)
    end
    local wasVisible = IsInventoryVisibleStateEnabled()
    if not wasVisible then
        SKIN:Bang('!UpdateMeasure', 'MeasureInventoryBGEnableGuard')
        if ShouldUnloadInventoryBackground() then
            UnloadInventoryBackgroundActiveConfig()
        else
            HideInventoryBackgroundActiveConfig()
        end
        return
    end
    RestoreInventoryBackgroundActiveConfig()
    RestoreInventoryAfterBackgroundReady()
end
function DeactivateClosedInventoryBackgroundOnRefresh()
    LoadEssentials()
    if IsInventoryVisibleStateEnabled() then
        RestoreInventoryBackgroundActiveConfig()
        RestoreInventoryAfterBackgroundReady()
        return
    end

    if ShouldUnloadInventoryBackground() then
        UnloadInventoryBackgroundActiveConfig()
    else
        HideInventoryBackgroundActiveConfig()
    end
end
function DeactivateInventoryBackgroundActiveConfig()
    LoadEssentials()
    if ShouldUnloadInventoryBackground() then
        UnloadInventoryBackgroundActiveConfig()
    else
        HideInventoryBackgroundActiveConfig()
    end
end
function RequestInventoryBackgroundActivation(inventoryBgConfig)
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    InventoryLifecycle.CreateInventoryBgSurface(rootPath):ActivateIfInactive()
    SKIN:Bang('!SetVariable', 'BlockHudInventoryOpenDeferredRestore', '1')
    SKIN:Bang('!UpdateMeasure', 'MeasureInventoryOpenDeferredRestore')
end
function RequestInventoryActivation(inventoryConfig)
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    InventoryLifecycle.CreateInventorySurface(rootPath):ActivateIfInactive()
    SKIN:Bang('!SetVariable', 'BlockHudInventoryPanelOpenDeferredRestore', '1')
    SKIN:Bang('!UpdateMeasure', 'MeasureInventoryPanelOpenDeferredRestore')
end
function RestoreInventoryOpenAfterBackgroundActivation()
    LoadEssentials()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath == '' then
        return
    end
    local inventoryBgConfig = rootPath .. '\\HUD\\InventoryBG'
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RestoreInventoryBackgroundActiveConfigOnRefresh()', inventoryBgConfig)
end
function RestoreInventoryOpenAfterInventoryActivation()
    LoadEssentials()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath == '' then
        return
    end
    local inventoryConfig = rootPath .. '\\HUD\\Inventory'
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RestoreInventoryActiveConfigOnOpen()', inventoryConfig)
end
function RestoreInventoryActiveConfigOnOpen()
    LoadEssentials()
    if RainmeterConfigState then
        RainmeterConfigState.Register(SKIN)
    end
    if not IsInventoryVisibleStateEnabled() then
        SuspendInventoryResident()
        SKIN:Bang('!Hide')
        return
    end
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
    SKIN:Bang('!Show')
    ResumeInventoryResident()
    SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility')
    SKIN:Bang('!Redraw')
    RollHerobrineInventoryReplacement()
end
prepareInventoryOpenPosition = function(inventoryActive, inventoryConfig)
    if inventoryActive then
        HighlightCommandMeasureForActiveConfig('MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()', inventoryConfig)
    else
        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()')
    end
end

showResidentConfigAfterLayout = function(configPath)
    local function roundWindowCoordinate(value)
        local number = tonumber(value)
        if not number then
            return nil
        end
        if number >= 0 then
            return tostring(math.floor(number + 0.5))
        end
        return tostring(math.ceil(number - 0.5))
    end

    local function setResidentLayoutVariable(name, value)
        local text = trimText(value)
        if text == '' then
            return false
        end
        return HighlightSetVariableForActiveConfig(name, text, configPath)
    end

    local statePrefix = 'ResponsiveLayout_Inventory_'
    for _, field in ipairs({ 'AnchorKind', 'ReferenceTarget', 'OffsetXBase', 'OffsetYBase', 'ScaleMode' }) do
        setResidentLayoutVariable(statePrefix .. field, SKIN:GetVariable(statePrefix .. field, ''))
    end

    local mode = trimText(SKIN:GetVariable(statePrefix .. 'PositionMode', 'auto'))
    local fixedX = trimText(SKIN:GetVariable(statePrefix .. 'FixedX', '0'))
    local fixedY = trimText(SKIN:GetVariable(statePrefix .. 'FixedY', '0'))
    local liveX = trimText(SKIN:GetVariable(statePrefix .. 'LiveWindowX', fixedX))
    local liveY = trimText(SKIN:GetVariable(statePrefix .. 'LiveWindowY', fixedY))
    local liveWidth = trimText(SKIN:GetVariable(statePrefix .. 'LiveWidth', ''))
    local liveHeight = trimText(SKIN:GetVariable(statePrefix .. 'LiveHeight', ''))
    local currentConfig = trimText(SKIN:GetVariable('CURRENTCONFIG', '')):gsub('/', '\\')
    local rootConfig = trimText(SKIN:GetVariable('ROOTCONFIG', '')):gsub('/', '\\')
    local isCurrentInventory = currentConfig ~= ''
        and ((rootConfig ~= '' and currentConfig:lower() == (rootConfig .. '\\HUD\\Inventory'):lower())
            or (rootConfig == '' and (currentConfig:lower():match('\\inventory$') ~= nil or currentConfig:lower() == 'inventory')))

    if isCurrentInventory then
        local currentX = roundWindowCoordinate(SKIN:GetVariable('CURRENTCONFIGX', fixedX))
        local currentY = roundWindowCoordinate(SKIN:GetVariable('CURRENTCONFIGY', fixedY))
        if currentX and currentY then
            mode = 'fixed'
            fixedX = currentX
            fixedY = currentY
            liveX = currentX
            liveY = currentY
        end
        liveWidth = trimText(SKIN:GetVariable('CURRENTCONFIGWIDTH', liveWidth))
        liveHeight = trimText(SKIN:GetVariable('CURRENTCONFIGHEIGHT', liveHeight))
    end

    setResidentLayoutVariable(statePrefix .. 'PositionMode', mode)
    setResidentLayoutVariable(statePrefix .. 'FixedX', fixedX)
    setResidentLayoutVariable(statePrefix .. 'FixedY', fixedY)
    setResidentLayoutVariable(statePrefix .. 'LiveActive', '1')
    setResidentLayoutVariable(statePrefix .. 'LiveWindowX', liveX)
    setResidentLayoutVariable(statePrefix .. 'LiveWindowY', liveY)
    setResidentLayoutVariable(statePrefix .. 'LiveWidth', liveWidth)
    setResidentLayoutVariable(statePrefix .. 'LiveHeight', liveHeight)
    HighlightCommandMeasureForActiveConfig('MeasureResponsiveLayout', 'ApplyLayout()', configPath)
    return HighlightShowActiveConfig(configPath)
end

function ActivateAllInventory()
    LoadEssentials()
    if trimText(SKIN:GetVariable('EnableInventorySkin', '1')) == '0' then
        return
    end
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    local inventoryBgConfig = rootPath .. '\\HUD\\InventoryBG'
    local inventoryConfig = rootPath .. '\\HUD\\Inventory'
    local editorOpen = isEditorOpen()
    local inventoryBgActive = isRainmeterConfigActive(inventoryBgConfig)
    local inventoryActive = isRainmeterConfigActive(inventoryConfig)
    SetInventoryVisibleState(true, rootPath)
    prepareInventoryOpenPosition(inventoryActive, inventoryConfig)
    if not inventoryBgActive then
        InventoryLifecycle.CreateInventoryBgSurface(rootPath):ActivateIfInactive()
        return
    end
    if editorOpen then
        if inventoryBgActive then
            syncEditorDraftMetaToConfig(inventoryBgConfig)
        end
        if inventoryActive then
            syncEditorDraftMetaToConfig(inventoryConfig)
        end
    end
    if inventoryBgActive then
        HighlightCommandMeasureForActiveConfig('MeasureResponsiveLayout', 'ApplyLayout()', inventoryBgConfig)
        HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'RestoreInventoryBackgroundActiveConfig()', inventoryBgConfig)
    end
    if inventoryActive then
        showResidentConfigAfterLayout(inventoryConfig)
        HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'ResumeInventoryResident()', inventoryConfig)
    else
        RequestInventoryActivation(inventoryConfig)
    end
    if editorOpen and inventoryActive then
        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', inventoryConfig)
        SKIN:Bang('!Redraw', inventoryConfig)
    end
    if inventoryActive then
        HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'RollHerobrineInventoryReplacement()', inventoryConfig)
    end
    ApplyInventoryBackdropOpenZOrder(rootPath)
end
function ResetInteractionState()
    LoadEssentials()
    LoadAllSkinValue()
    isOptionHovering = false
    suppressNextMouseUp = false
    isMouseDown = false
    clearHotbarWindowDragState()
    hideDragVisual()
    LeaveSlot()
end
function PreloadModal()
    LoadEssentials()
    RunConfirm.clear()
    RunConfirm.preload(SKIN:GetVariable('ROOTCONFIG'), ModalAlertBridge == nil)
    if ModalAlertBridge then
        ModalAlertBridge.Preload(modalAlertHost())
    end
end
function OpenPendingRunConfirmModal()
    LoadEssentials()
    if RunConfirm.showPendingModal() then
        RunConfirm.modalPreloadRequested = true
        SKIN:Bang('!SetVariable', 'BlockHudModalPreloaded', '1')
    end
end
function PreloadModalAlert()
    LoadEssentials()
    if ModalAlertBridge then
        return ModalAlertBridge.Preload(modalAlertHost())
    end
    return false
end
function OpenPendingModalAlert()
    LoadEssentials()
    if ModalAlertBridge then
        return ModalAlertBridge.OpenPending(modalAlertHost())
    end
    return false
end
function OpenModalAlertLogFolder(token)
    LoadEssentials()
    if ModalAlertBridge then
        return ModalAlertBridge.OpenLogFolder(modalAlertHost(), token)
    end
    return false
end
function ConfirmPendingRun(token)
    LoadEssentials()
    local normalizedToken = tostring(token or '')
    local lockToken = RunConfirm.currentLock()
    if not RunConfirm.pending or RunConfirm.pending.token ~= normalizedToken or lockToken ~= normalizedToken then
        if RunConfirm.pending and RunConfirm.pending.token == normalizedToken and lockToken ~= normalizedToken then
            RunConfirm.pending = nil
        end
        logWarning('[HighlightSlot] ignored stale run confirmation token.')
        return
    end
    local pending = RunConfirm.pending
    local exec = pending.exec or ''
    local bang = pending.action or ''
    RunConfirm.clear()
    if IsInternalWebNowPlayingCoverPath(exec) then
        return
    end
    if bang == '' then
        showHudModalAlert('error', 'ModalAlert_HudActionInvalid', 'This slot action is invalid and could not be run. Edit the item action and try again.')
        return
    end
    SKIN:Bang(bang)
end
function CancelPendingRun(token)
    LoadEssentials()
    local normalizedToken = tostring(token or '')
    local lockToken = RunConfirm.currentLock()
    if not RunConfirm.pending or RunConfirm.pending.token ~= normalizedToken or lockToken ~= normalizedToken then
        if RunConfirm.pending and RunConfirm.pending.token == normalizedToken and lockToken ~= normalizedToken then
            RunConfirm.pending = nil
        end
        logWarning('[HighlightSlot] ignored stale run cancellation token.')
        return
    end
    RunConfirm.clear()
end
function HandleInventoryBackgroundMouseMove(x, y)
    LoadEssentials()
    local meta = currentEditorMeta()
    if not meta or not meta.DragActive then
        return
    end
    local currentX = tonumber(SKIN:GetVariable('CURRENTCONFIGX', '')) or tonumber(SKIN:GetVariable('PWORKAREAX', '0')) or 0
    local currentY = tonumber(SKIN:GetVariable('CURRENTCONFIGY', '')) or tonumber(SKIN:GetVariable('PWORKAREAY', '0')) or 0
    local inventoryX = tonumber(SKIN:GetVariable('ResponsiveLayout_Inventory_LiveWindowX', '0')) or 0
    local inventoryY = tonumber(SKIN:GetVariable('ResponsiveLayout_Inventory_LiveWindowY', '0')) or 0
    local localX = (tonumber(x) or 0) + currentX - inventoryX
    local localY = (tonumber(y) or 0) + currentY - inventoryY
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', string.format('OnMouseMove(%s,%s)', tostring(localX), tostring(localY)), SKIN:GetVariable('ROOTCONFIG') .. '\\HUD\\Inventory')
end
function HandleInventoryBackgroundMouseUp(x, y)
    LoadEssentials()
    local meta = currentEditorMeta()
    if not meta or not meta.DragActive then
        return
    end
    local currentX = tonumber(SKIN:GetVariable('CURRENTCONFIGX', '')) or tonumber(SKIN:GetVariable('PWORKAREAX', '0')) or 0
    local currentY = tonumber(SKIN:GetVariable('CURRENTCONFIGY', '')) or tonumber(SKIN:GetVariable('PWORKAREAY', '0')) or 0
    local inventoryX = tonumber(SKIN:GetVariable('ResponsiveLayout_Inventory_LiveWindowX', '0')) or 0
    local inventoryY = tonumber(SKIN:GetVariable('ResponsiveLayout_Inventory_LiveWindowY', '0')) or 0
    local localX = (tonumber(x) or 0) + currentX - inventoryX
    local localY = (tonumber(y) or 0) + currentY - inventoryY
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', string.format('OnMouseUp(%s,%s)', tostring(localX), tostring(localY)), SKIN:GetVariable('ROOTCONFIG') .. '\\HUD\\Inventory')
end
function HandleInventoryBackgroundClose(source)
    LoadEssentials()
    local dragMeta = currentEditorMeta()
    if dragMeta and dragMeta.DragActive then
        return
    end
    ResetInteractionState()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    local closeSource = trimText(source)
    if closeSource == '' then
        closeSource = 'background'
    end
    resetHotbarInteraction(rootPath)
    if closeSource == 'button' then
        PlayClickSound()
    end
    local editorVisibleIntent = IsEditorVisibleStateEnabled()
    local editorVisible = editorVisibleIntent and isEditorPanelActive()
    local editorOpen = isEditorOpen()
    if editorVisible or (editorOpen and editorVisibleIntent) then
        local meta = EditorItemService.ReadDraftMetaOnly(R)
        if meta.PickerModalOpen then
            SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', 'SetPickerModalOpen(0)', editorConfigPath())
        end
        closeEditorPanel()
        if not isEditorOpen() and rootPath ~= '' then
            SetEditorVisibleState(false, rootPath)
            PanelLifecycle.CreateEditorSurface(rootPath):HideIfActive()
        end
        if closeSource == 'background' then
            return
        end

    elseif editorOpen then
        closeEditorPanel()
        if rootPath ~= '' then
            SetEditorVisibleState(false, rootPath)
            PanelLifecycle.CreateEditorSurface(rootPath):HideIfActive()
        end
    end
    if rootPath ~= '' then
        closeInventoryPanels(rootPath)
    end
end
function HandleEditButtonClick()
    LoadEssentials()
    ResetInteractionState()
    PlayClickSound()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    if IsEditorVisibleStateEnabled() then
        if isEditorOpen() then
            closeEditorPanel()
            if not isEditorOpen() and rootPath ~= '' then
                SetEditorVisibleState(false, rootPath)
                PanelLifecycle.CreateEditorSurface(rootPath):HideIfActive()
            end
            refreshHotbarOnly(rootPath)
            return
        end
        if rootPath ~= '' then
            SetEditorVisibleState(false, rootPath)
            PanelLifecycle.CreateEditorSurface(rootPath):HideIfActive()
        end
    end
    local editorSurface = PanelLifecycle.CreateEditorSurface(rootPath)
    editorSurface:SetVisible(true)
    primeEditorOpenState(rootPath)
    local editorConfig = rootPath .. '\\HUD\\Editor'
    local editorActive = isRainmeterConfigActive(editorConfig)
    if not editorActive then
        editorSurface:ActivateIfInactive()
    end
    if editorActive then
        editorSurface:ShowActiveAfterLayout()
        editorSurface:CommandIfActive('MeasureInputCommit', 'ResumeEditorResident()')
    end
    refreshHotbarOnly(rootPath)
end
function HandleSettingsButtonClick()
    LoadEssentials()
    ResetInteractionState()
    PlayClickSound()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    local settingsConfig = rootPath .. '\\HUD\\Settings'
    local settingsActive = isRainmeterConfigActive(settingsConfig)
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    if isSettingsOpen() and settingsActive then
        closeSettingsPanel()
        return
    end
    if not settingsActive then
        SettingsRouteLauncher.Open(SKIN, 'normal', 'general', '1')
        return
    end
    local settingsSurface = PanelLifecycle.CreateSettingsSurface(rootPath)
    settingsSurface:SetVisible(true)
    settingsSurface:ShowActiveAfterLayout()
    settingsSurface:CommandIfActive('MeasureSettingsCommit', "OpenSettingsRoute('normal','general','1')")
end
function HandleRefreshButtonClick()
    SKIN:Bang('!RefreshApp')
end
function HandleSteveSkinEditButtonClick()
    LoadEssentials()
    ResetInteractionState()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    PlayClickSound()
    SettingsRouteLauncher.Open(SKIN, 'normal', 'inventory', '2')
end
function HandleCreatorProfileClick()
    LoadEssentials()
    ResetInteractionState()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    PlayClickSound()
    SKIN:Bang('["' .. CreatorProfileUrl() .. '"]')
end
function HandleOpenWorkProgressClick()
    LoadEssentials()
    if GetSkinValue('EnableWorkProgress') == 0 then
        return
    end
    ResetInteractionState()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    PlayClickSound()
    SKIN:Bang('["https://www.notion.so/aismash/35c2dc0bb4ae80c7a033e942069d76c3?source=copy_link"]')
end
function HandleOpenInfoClick()
    LoadEssentials()
    ResetInteractionState()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    PlayClickSound()
    SKIN:Bang('["' .. InventoryUsageGuideUrl() .. '"]')
end
function HandleOpenSkinFolderClick()
    LoadEssentials()
    ResetInteractionState()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    if rootPath ~= '' then
        resetHotbarInteraction(rootPath)
    end
    PlayClickSound()
    SKIN:Bang('["' .. R .. 'Customs\\Images\\Items"]')
end
function Update()
    LoadEssentials()
    SyncCreatorProfileLink()
    SyncLanguageSensitiveItemText()
    syncHotbarTextVisibility()
    syncSelectedHighlightVisibilityGuard()
    return 0
end
