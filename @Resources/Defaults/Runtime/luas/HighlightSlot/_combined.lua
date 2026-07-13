-- Generated runtime aggregate for Rainmeter-safe split loading. Edit sibling part files instead.
-- Split from @Resources\Defaults\Runtime\luas\HighlightSlot.lua lines 1-805.
local DRAG_IMAGE_METER = 'MeterDragItem'
local DRAG_TEXT_METER = 'MeterDragItemText'
local curInfo = nil
local lastIndexX = -1
local lastIndexY = -1
local lastHighlightSource = nil
local lastClickT = 0
local useClickSound = 0
local lastItemName = 'NONE'
local lastLanguageCode = nil
local lastCreatorProfileLanguageCode = nil
local lastHighlightHlx = nil
local lastHighlightHly = nil
local lastSelectedHighlightKey = nil
local lastSelectedHlx = nil
local lastSelectedHly = nil
local lastSelectedHighlightSize = nil
local clickSoundPath = ''
local loadedEssentials = false
local showingHighlight = false
local showingSelectedHighlight = false
local IsHotbar = false
local ItemInfosHolder = nil
local EditorItemService = nil
local ItemDataRepository = nil
local ImageAdjuster = nil
local ResponsiveLayout = nil
local ModalAlertBridge = nil
local HerobrineEvents = nil
local RainmeterConfigState = nil
local ResidentUpdateController = nil
local LanguageBranching = nil
local LanguageRegistry = nil
local LocalizationTextFit = nil
HighlightSlotActionLaunch = nil
local IsMissingHintVisible = true
local isOptionHovering = false
local isTooltipVisible = false
local R = ''
local UpdateItemText
local isRainmeterConfigActive = nil
local tooltipMeasureAvailable = nil
local RunConfirm = {
    pending = nil,
    counter = 0,
    modalPreloadRequested = false,
    lockVariable = 'BlockHudRunConfirmPendingToken',
    deferredOpenVariable = 'BlockHudRunConfirmDeferredOpen',
}
local X = 0
local Y = 0
local SlotSize = 0
local SlotRows = 0
local SlotColumns = 0
local HighlightSizeOffset = 0
local ItemSize = 0
local InvOffsetX = 0
local InvOffsetY = 0
local lastMouseX = 0
local lastMouseY = 0
local STATE_OUT = 0
local STATE_IN = 1
local state = STATE_OUT
local isMouseDown = false
local mouseDownX = 0
local mouseDownY = 0
local mouseDownWindowX = nil
local mouseDownWindowY = nil
local hotbarWindowMovedDuringClick = false
local dragThreshold = 8
local activeDragVisual = false
local dragPayloadKey = nil
local dragPayload = nil
local dragVisualImagePath = nil
local dragVisualImageX = nil
local dragVisualImageY = nil
local dragVisualImageSize = nil
local dragVisualText = nil
local dragVisualTextX = nil
local dragVisualTextY = nil
local dragVisualTextVisible = false
local dragHoverTargetKey = nil
local dragHoverHasTarget = false
local dragHoverTracked = false
local dragInsideNotified = false
local suppressNextMouseUp = false
local hotbarTextEnabled = nil
local hotbarTextVisible = false
local pinnedExternalHotbarTextOwner = ''
local OPTION_HOVER_AREAS = {
    { hidden = 'HideUsageGuide', x = 'UsageGuideX', y = 'UsageGuideY', w = 'UsageGuideW', h = 'UsageGuideH' },
    { hidden = '', x = 'SteveSkinEditButtonX', y = 'SteveSkinEditButtonY', w = 'SteveSkinEditButtonW', h = 'SteveSkinEditButtonH' },
    { hidden = 'HideSkinFolderButton', x = 'SkinFolderX', y = 'SkinFolderY', w = 'SkinFolderW', h = 'SkinFolderH' },
    { hidden = 'WorkProgressHidden', x = 'WorkProgressButtonX', y = 'WorkProgressButtonY', w = 'WorkProgressButtonW', h = 'WorkProgressButtonH' },
    { hidden = 'HideEditButton', x = 'EditButtonX', y = 'EditButtonY', w = 'EditButtonW', h = 'EditButtonH' },
    { hidden = 'HideSettingsButton', x = 'SettingsButtonX', y = 'SettingsButtonY', w = 'SettingsButtonW', h = 'SettingsButtonH' },
    { hidden = 'HideInventoryCloseButton', x = 'InventoryCloseButtonX', y = 'InventoryCloseButtonY', w = 'InventoryCloseButtonW', h = 'InventoryCloseButtonH' },
}
local CREATOR_PROFILE_METERS = { 'MeterPlayerDefault', 'MeterPlayerCustom' }
local function GetSkinNumber(name, fallback)
    local raw = SKIN:GetVariable(name, nil)
    if raw == nil then
        return fallback or 0
    end
    local value = _G.DMeloper.EvalNumber(raw)
    if value == nil then
        return fallback or 0
    end
    return value
end
local function GetSkinValue(name)
    return GetSkinNumber(name, 0)
end
local function isLowSpecSlotHoverHighlightDisabled()
    return GetSkinValue('LowSpecDisableSlotHoverHighlight') == 1
end
local function isLowSpecHoverTextTooltipDisabled()
    return GetSkinValue('LowSpecDisableHoverTextTooltip') == 1
end
local function editorConfigPath()
    return SKIN:GetVariable('ROOTCONFIG') .. '\\HUD\\Editor'
end
local isPanelActive
local isEditorOpen
local clearStaleEditorSession
local getEditorInteractionMode
local isHotbarExecutionMode
local isHotbarEditingMode
local isEditorInteractive
local function settingsConfigPath()
    return SKIN:GetVariable('ROOTCONFIG') .. '\\HUD\\Settings'
end
local function isSettingsOpen()
    local raw = tostring(SKIN:GetVariable('BlockHudSettingsVisible', '0') or '')
    raw = raw:gsub('^%s+', ''):gsub('%s+$', '')
    return raw == '1'
end
local function isSettingsPanelActive()
    return isPanelActive('Settings') and isSettingsOpen()
end
isEditorInteractive = function()
    return isEditorOpen()
end
getEditorInteractionMode = function()
    if not isEditorInteractive() then
        return 'normal'
    end
    if IsInventoryVisibleStateEnabled() then
        return 'editor_attached'
    end
    return 'editor_detached'
end
isHotbarExecutionMode = function()
    return IsHotbar and getEditorInteractionMode() ~= 'editor_attached'
end
isHotbarEditingMode = function()
    return IsHotbar and getEditorInteractionMode() == 'editor_attached'
end
local function isEditorPanelActive()
    return isEditorOpen() and isPanelActive('Editor')
end
local function currentEditorMeta()
    if not isEditorOpen() then
        return nil
    end
    return EditorItemService.ReadDraftMetaOnly(R)
end
local function resetHotbarInteraction(rootPath)
    if rootPath ~= '' then
        HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'ResetInteractionState()', rootPath .. '\\HUD\\Hotbar')
    end
end
local function refreshHotbarOnly(rootPath)
    if rootPath and rootPath ~= '' then
        SKIN:Bang('!Refresh', rootPath .. '\\HUD\\Hotbar', 'Hotbar.ini')
    end
end
local function clearPanelLiveState(panelId)
    if not ResponsiveLayout then
        return
    end
    local liveState = ResponsiveLayout.GetLiveState(SKIN, panelId)
    local x = (liveState and liveState.WindowX) or 0
    local y = (liveState and liveState.WindowY) or 0
    ResponsiveLayout.WriteLiveState(SKIN, panelId, false, x, y, true)
end
local function closeEditorPanel()
    local editorOpen = isEditorOpen()
    local editorConfig = editorConfigPath()
    local editorActive = editorOpen and isRainmeterConfigActive(editorConfig)
    clearPanelLiveState('Editor')
    if editorActive then
        HighlightCommandMeasureForActiveConfig('MeasureInputCommit', 'CloseEditor()', editorConfig)
        return
    end
    if editorOpen and clearStaleEditorSession then
        clearStaleEditorSession()
    end
end
local function closeSettingsPanel()
    local rootPath = tostring(SKIN:GetVariable('ROOTCONFIG', '') or '')
    clearPanelLiveState('Settings')
    if isSettingsOpen() then
        SetSettingsVisibleState(false, rootPath)
        local settingsConfig = settingsConfigPath()
        HighlightCommandMeasureForActiveConfig('MeasureSettingsCommit', 'CloseSettings()', settingsConfig)
        HighlightHideActiveConfig(settingsConfig)
    end
end
function SetEditorVisibleState(visible, rootPath)
    return PanelLifecycle.CreateEditorSurface(rootPath):SetVisible(visible)
end
function IsEditorVisibleStateEnabled()
    return PanelLifecycle.CreateEditorSurface():IsVisibleIntent()
end
function SetSettingsVisibleState(visible, rootPath)
    return PanelLifecycle.CreateSettingsSurface(rootPath):SetVisible(visible)
end
function SetInventoryVisibleState(visible, rootPath)
    return InventoryLifecycle.CreateInventorySurface(rootPath):SetVisible(visible)
end
function IsInventoryVisibleStateEnabled()
    return InventoryLifecycle.CreateInventorySurface():IsVisibleIntent()
end
local function closeInventoryPanels(rootPath)
    if not rootPath or rootPath == '' then
        return
    end
    SetInventoryVisibleState(false, rootPath)
    clearPanelLiveState('Inventory')
    clearPanelLiveState('InventoryBG')
    local inventoryConfig = rootPath .. '\\HUD\\Inventory'
    local inventoryBgConfig = rootPath .. '\\HUD\\InventoryBG'
    local currentConfig = tostring(SKIN:GetVariable('CURRENTCONFIG', '') or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
    local inventoryBgConfigKey = inventoryBgConfig:lower()
    local function closeInventory()
        InventoryLifecycle.CreateInventorySurface(rootPath):SuspendIfActiveThenHide()
    end
    local function closeInventoryBackground()
        if isRainmeterConfigActive(inventoryBgConfig) then
            if currentConfig == inventoryBgConfigKey then
                HideInventoryBackgroundActiveConfig()
            else
                HighlightCommandMeasureForActiveConfig('MeasureHighlight', 'HideInventoryBackgroundActiveConfig()', inventoryBgConfig)
            end
        end
    end
    if currentConfig == inventoryBgConfigKey then
        closeInventory()
        closeInventoryBackground()
    else
        closeInventoryBackground()
        closeInventory()
    end
end
local function roundValue(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end
local function clampValue(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end
local function readLivePanelState(panelId)
    if not ResponsiveLayout or not ResponsiveLayout.GetLiveState then
        return nil
    end
    return ResponsiveLayout.GetLiveState(SKIN, panelId)
end
isPanelActive = function(configName)
    local liveState = readLivePanelState(configName)
    return liveState ~= nil and liveState.Active or false
end
local function livePanelPosition(configName)
    local liveState = readLivePanelState(configName)
    if not liveState or not liveState.Active or liveState.WindowX == nil or liveState.WindowY == nil then
        return nil
    end
    return { x = liveState.WindowX, y = liveState.WindowY }
end
local function clearHotbarWindowDragState()
    mouseDownWindowX = nil
    mouseDownWindowY = nil
    hotbarWindowMovedDuringClick = false
end
local function currentConfigWindowPosition()
    local x = tonumber(SKIN:GetVariable('CURRENTCONFIGX', ''))
    local y = tonumber(SKIN:GetVariable('CURRENTCONFIGY', ''))
    if x == nil or y == nil then
        return nil
    end
    return { x = x, y = y }
end
local function currentHotbarWindowPosition()
    if IsHotbar then
        local current = currentConfigWindowPosition()
        if current then
            return current
        end
    end
    local live = livePanelPosition('Hotbar')
    if live then
        return live
    end
    return nil
end
local function captureHotbarWindowDragStart()
    clearHotbarWindowDragState()
    if not IsHotbar then
        return
    end
    local position = currentHotbarWindowPosition()
    if not position then
        return
    end
    mouseDownWindowX = position.x
    mouseDownWindowY = position.y
end
local function detectHotbarWindowMovement()
    hotbarWindowMovedDuringClick = false
    if not IsHotbar or mouseDownWindowX == nil or mouseDownWindowY == nil then
        return false
    end
    local position = currentHotbarWindowPosition()
    if not position then
        return false
    end
    hotbarWindowMovedDuringClick = position.x ~= mouseDownWindowX or position.y ~= mouseDownWindowY
    return hotbarWindowMovedDuringClick
end
local function defaultPanelPosition(panelId)
    if not ResponsiveLayout then
        return nil
    end
    local rects = ResponsiveLayout.ResolveRects(SKIN)
    local inventory = rects and rects.Inventory
    local work = rects and rects.PrimaryWorkArea
    local scale = rects and rects.Scale
    local baseline = ResponsiveLayout.BaselineState(panelId)
    if not inventory or not work or not scale or not baseline then
        return nil
    end
    local offsetX = tonumber(baseline.OffsetXBase) or 0
    local offsetY = tonumber(baseline.OffsetYBase) or 0
    local width = panelId == 'Settings' and 360 or 320
    local height = panelId == 'Settings' and 336 or 680
    local rawX
    if baseline.AnchorKind == 'InventoryLeftTop' then
        rawX = inventory.leftTopX + (offsetX * scale)
    else
        rawX = inventory.rightTopX + (offsetX * scale)
    end
    local rawY = inventory.leftTopY + (offsetY * scale)
    rawX = roundValue(clampValue(rawX, work.x, math.max(work.x, work.right - width)))
    rawY = roundValue(clampValue(rawY, work.y, math.max(work.y, work.bottom - height)))
    return { x = rawX, y = rawY }
end
local function isPanelAtDefaultPosition(panelId, configName)
    local current = livePanelPosition(configName)
    local target = defaultPanelPosition(panelId)
    if not current or not target then
        return false
    end
    return math.abs(current.x - target.x) <= 1 and math.abs(current.y - target.y) <= 1
end
local function editorDraftPath()
    return R .. 'Customs\\Data\\EditorDraft.inc'
end
local function currentSource()
    return IsHotbar and 'hotbar' or 'inventory'
end
local function LoadAllSkinValue()
    X = GetSkinValue('X')
    Y = GetSkinValue('Y')
    SlotColumns = GetSkinValue('SlotColumns')
    SlotRows = GetSkinValue('SlotRows')
    HighlightSizeOffset = GetSkinValue('SlotHighlightSizeOffset')
    IsMissingHintVisible = GetSkinValue('ShowMissingHintText') == 1
    if IsHotbar then
        SlotSize = GetSkinValue('HotbarSlotSize')
        ItemSize = SlotSize + GetSkinValue('HotbarItemSizeOffset')
    else
        SlotSize = GetSkinValue('SlotSize')
        ItemSize = GetSkinValue('InventoryItemSize')
        InvOffsetX = GetSkinValue('InvOffsetX')
        InvOffsetY = GetSkinValue('InvOffsetY')
        X = X + InvOffsetX
        Y = Y + InvOffsetY
    end
end
function HudActionFileExists(path)
    local handle = io.open(tostring(path or ''), 'rb')
    if handle then
        handle:close()
        return true
    end
    return false
end

function ResolveHudActionPowerShellProgramPath()
    return '"' .. tostring(SKIN:GetVariable('@', '') or '') .. 'Defaults\\Runtime\\helpers\\BlockHudPowerShellHost.exe"'
end

function SyncHudActionPowerShellProgramPath()
    SKIN:Bang('!SetVariable', 'HudActionPowerShellProgram', ResolveHudActionPowerShellProgramPath())
end
local function LoadEssentials()
    if loadedEssentials then return end
    loadedEssentials = true
    R = SKIN:GetVariable('@')
    SyncHudActionPowerShellProgramPath()
    dofile(R .. 'Defaults\\Runtime\\luas\\DMeloper.lua')
    ItemInfosHolder = dofile(R .. 'Defaults\\Runtime\\luas\\ItemInfosHolder.lua')
    EditorItemService = dofile(R .. 'Defaults\\Runtime\\luas\\data\\EditorItemService.lua')
    ItemDataRepository = dofile(R .. 'Defaults\\Runtime\\luas\\data\\ItemDataRepository.lua')
    ImageAdjuster = ItemDataRepository.GetImageAdjuster(R)
    ResponsiveLayout = dofile(R .. 'Defaults\\Runtime\\luas\\ResponsiveLayoutCore.lua')
    ModalAlertBridge = dofile(R .. 'Defaults\\Runtime\\luas\\ModalAlertBridge.lua')
    RainmeterConfigState = dofile(R .. 'Defaults\\Runtime\\luas\\RainmeterConfigState.lua')
    ResidentSurfaceLifecycle = dofile(R .. 'Defaults\\Runtime\\luas\\ResidentSurfaceLifecycle.lua')
    ResidentUpdateController = dofile(R .. 'Defaults\\Runtime\\luas\\ResidentUpdateController.lua')
    LanguageBranching = dofile(R .. 'Defaults\\Runtime\\luas\\LanguageBranching.lua')
    LanguageRegistry = dofile(R .. 'Defaults\\Runtime\\luas\\LanguageRegistry.lua')
    LocalizationTextFit = dofile(R .. 'Defaults\\Runtime\\luas\\LocalizationTextFit.lua')
    local skinRoot = tostring(SKIN:GetVariable('ROOTCONFIGPATH', '') or '')
    skinRoot = skinRoot:gsub('^%s+', ''):gsub('%s+$', '')
    if skinRoot ~= '' and skinRoot:sub(-1) ~= '\\' and skinRoot:sub(-1) ~= '/' then
        skinRoot = skinRoot .. '\\'
    end
    HerobrineEvents = dofile(skinRoot .. 'ExtraContent\\Herobrine\\HerobrineEvents.lua')
    SettingsRouteLauncher = dofile(R .. 'Defaults\\Runtime\\luas\\SettingsRouteLauncher.lua')
    clickSoundPath = R .. 'Defaults\\Runtime\\audios\\click.wav'
    useClickSound = tonumber(SKIN:GetVariable('UseClickSound')) or 0
    IsHotbar = GetSkinValue('IsHotbar') == 1
    LoadAllSkinValue()
    SKIN:Bang(_G.DMeloper.BANG_SET_VARIABLE, 'HighlightShapeSize', tostring(SlotSize + HighlightSizeOffset))
end
function ApplyInventoryStaticLocalizationTextFits()
    if IsHotbar or not LocalizationTextFit or not LocalizationTextFit.ApplyMeterTextFit then
        return
    end
    LocalizationTextFit.ApplyMeterTextFit(SKIN, 'MeterEditorModeBadgeLabel', '#Loc_Inventory_EditorModeBadgeText#', {
        baseFontSize = GetSkinNumber('EditorModeBadgeFontSize', 20),
        widthPx = math.max(0, GetSkinNumber('EditorModeBadgeW', 245) - 18),
        minScale = 0.55,
        probeMeterName = 'MeterInventoryTextFitProbe',
        setText = false,
        update = false,
    })
end
local function callHerobrine(methodName, ...)
    if HerobrineEvents and type(HerobrineEvents[methodName]) == 'function' then
        return HerobrineEvents[methodName](SKIN, ...)
    end
    return false
end
local function HasTooltipMeasure()
    if tooltipMeasureAvailable == true then
        return true
    end
    local ok, measure = pcall(function()
        return SKIN:GetMeasure('MeasureTooltip')
    end)
    if ok and measure ~= nil then
        tooltipMeasureAvailable = true
        return true
    end
    return false
end
local function RunTooltipCommand(command)
    if IsHotbar or not command or command == '' or not HasTooltipMeasure() then
        return
    end
    SKIN:Bang('!CommandMeasure', 'MeasureTooltip', command)
end
local function SetHotbarText(text, mode)
    SKIN:Bang('!CommandMeasure', 'MeasureFade', string.format('SetText(%q,%q)', tostring(text or ''), tostring(mode or 'static')))
end
local function RunTooltipShowAt(text, isOption, x, y)
    isTooltipVisible = true
    RunTooltipCommand(string.format('ShowItemNameAt(%q, %s, %s, %s)', tostring(text or ''), isOption and 'true' or 'false', tostring(x), tostring(y)))
end
local function RunTooltipHide()
    isTooltipVisible = false
    RunTooltipCommand('Hide()')
end
local function RunTooltipMove(x, y, force)
    if not force and not isTooltipVisible then
        return
    end
    RunTooltipCommand(string.format('OnMouseMove(%s,%s,%s)', tostring(x), tostring(y), force and 'true' or 'false'))
end
local function trimText(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end
local function logWarning(message)
    SKIN:Bang('!Log', message, 'Warning')
end
isRainmeterConfigActive = function(configPath)
    local targetConfig = trimText(configPath)
    if targetConfig == '' or not RainmeterConfigState then
        return false
    end
    return RainmeterConfigState.IsActive(SKIN, targetConfig)
end
function HighlightSetVariableForActiveConfig(name, value, configPath)
    local targetConfig = trimText(configPath)
    if targetConfig == '' or not RainmeterConfigState then
        return false
    end
    return RainmeterConfigState.SetVariableIfActive(SKIN, name, value, targetConfig)
end
function HighlightCommandMeasureForActiveConfig(measureName, command, configPath)
    local targetConfig = trimText(configPath)
    if targetConfig == '' or not RainmeterConfigState then
        return false
    end
    return RainmeterConfigState.CommandIfActive(SKIN, measureName, command, targetConfig)
end
function HighlightShowActiveConfig(configPath)
    local targetConfig = trimText(configPath)
    if targetConfig == '' or not RainmeterConfigState then
        return false
    end
    return RainmeterConfigState.ShowIfActive(SKIN, targetConfig)
end
function HighlightHideActiveConfig(configPath)
    local targetConfig = trimText(configPath)
    if targetConfig == '' or not RainmeterConfigState then
        return false
    end
    return RainmeterConfigState.HideIfActive(SKIN, targetConfig)
end
PanelLifecycle = PanelLifecycle or {}
function PanelLifecycle.InternalStatePath()
    return R .. 'Defaults\\Runtime\\incs\\InternalState.inc'
end
function PanelLifecycle.ResolveRootPath(rootPath)
    local resolved = trimText(rootPath)
    if resolved ~= '' then
        return resolved
    end
    return trimText(SKIN:GetVariable('ROOTCONFIG', ''))
end
function PanelLifecycle.ConfigPath(rootPath, relativePath)
    rootPath = PanelLifecycle.ResolveRootPath(rootPath)
    if rootPath == '' then
        return ''
    end
    return rootPath .. '\\' .. relativePath
end
function PanelLifecycle.EditorVisibleMirrorConfigs(rootPath)
    rootPath = PanelLifecycle.ResolveRootPath(rootPath)
    if rootPath == '' then
        return {}
    end
    return {
        rootPath .. '\\HUD\\Hotbar',
        rootPath .. '\\HUD\\Inventory',
        rootPath .. '\\HUD\\InventoryBG',
        rootPath .. '\\HUD\\Editor',
    }
end
function PanelLifecycle.SettingsVisibleMirrorConfigs(rootPath)
    rootPath = PanelLifecycle.ResolveRootPath(rootPath)
    if rootPath == '' then
        return {}
    end
    return {
        rootPath .. '\\HUD\\Settings',
        rootPath .. '\\HUD\\Inventory',
        rootPath .. '\\HUD\\InventoryBG',
        rootPath .. '\\HUD\\Hotbar',
    }
end
function PanelLifecycle.CreateEditorSurface(rootPath)
    LoadEssentials()
    return ResidentSurfaceLifecycle.CreateSurface({
        skin = SKIN,
        surfaceId = 'Editor',
        configPath = PanelLifecycle.ConfigPath(rootPath, 'HUD\\Editor'),
        entryFile = 'Editor.ini',
        measureName = 'MeasureInputCommit',
        visibleVariable = 'BlockHudEditorVisible',
        visibleMirrorConfigs = function()
            return PanelLifecycle.EditorVisibleMirrorConfigs(rootPath)
        end,
        internalStatePath = PanelLifecycle.InternalStatePath,
        clearVisibleOnRainmeterClose = true,
        preShowLayoutMeasure = 'MeasureResponsiveLayout',
        preShowLayoutCommand = 'ApplyLayout()',
    })
end
function PanelLifecycle.CreateSettingsSurface(rootPath)
    LoadEssentials()
    return ResidentSurfaceLifecycle.CreateSurface({
        skin = SKIN,
        surfaceId = 'Settings',
        configPath = PanelLifecycle.ConfigPath(rootPath, 'HUD\\Settings'),
        entryFile = 'Settings.ini',
        measureName = 'MeasureSettingsCommit',
        visibleVariable = 'BlockHudSettingsVisible',
        visibleMirrorConfigs = function()
            return PanelLifecycle.SettingsVisibleMirrorConfigs(rootPath)
        end,
        internalStatePath = PanelLifecycle.InternalStatePath,
        clearVisibleOnRainmeterClose = true,
        preShowLayoutMeasure = 'MeasureResponsiveLayout',
        preShowLayoutCommand = 'ApplyLayout()',
    })
end
InventoryLifecycle = InventoryLifecycle or {}
function InventoryLifecycle.InternalStatePath()
    return R .. 'Defaults\\Runtime\\incs\\InternalState.inc'
end
function InventoryLifecycle.ResolveRootPath(rootPath)
    local resolved = trimText(rootPath)
    if resolved ~= '' then
        return resolved
    end
    return trimText(SKIN:GetVariable('ROOTCONFIG', ''))
end
function InventoryLifecycle.InventoryConfigPath(rootPath)
    rootPath = InventoryLifecycle.ResolveRootPath(rootPath)
    if rootPath == '' then
        return ''
    end
    return rootPath .. '\\HUD\\Inventory'
end
function InventoryLifecycle.InventoryBgConfigPath(rootPath)
    rootPath = InventoryLifecycle.ResolveRootPath(rootPath)
    if rootPath == '' then
        return ''
    end
    return rootPath .. '\\HUD\\InventoryBG'
end
function InventoryLifecycle.InventoryVisibleMirrorConfigs(rootPath)
    rootPath = InventoryLifecycle.ResolveRootPath(rootPath)
    if rootPath == '' then
        return {}
    end
    return {
        rootPath .. '\\HUD\\Hotbar',
        rootPath .. '\\HUD\\Inventory',
        rootPath .. '\\HUD\\InventoryBG',
        rootPath .. '\\HUD\\Editor',
    }
end
function InventoryLifecycle.IsInventoryFeatureEnabled()
    return trimText(SKIN:GetVariable('EnableInventorySkin', '1')) ~= '0'
end
function InventoryLifecycle.InventoryVisibleMirrorResolver(rootPath)
    return function()
        return InventoryLifecycle.InventoryVisibleMirrorConfigs(rootPath)
    end
end
function InventoryLifecycle.CreateInventorySurface(rootPath, configPath, beforeShow)
    LoadEssentials()
    return ResidentSurfaceLifecycle.CreateSurface({
        skin = SKIN,
        surfaceId = 'Inventory',
        configPath = configPath or InventoryLifecycle.InventoryConfigPath(rootPath),
        entryFile = 'Inventory.ini',
        measureName = 'MeasureHighlight',
        visibleVariable = 'BlockHudInventoryVisible',
        visibleMirrorConfigs = InventoryLifecycle.InventoryVisibleMirrorResolver(rootPath),
        internalStatePath = InventoryLifecycle.InternalStatePath,
        clearVisibleOnRainmeterClose = true,
        resumeCommand = 'ResumeInventoryResident()',
        suspendCommand = 'SuspendInventoryResident()',
        preShowLayoutMeasure = 'MeasureResponsiveLayout',
        preShowLayoutCommand = 'ApplyLayout()',
        featureEnabled = InventoryLifecycle.IsInventoryFeatureEnabled,
        beforeShow = beforeShow,
    })
end
function InventoryLifecycle.CreateInventoryBgSurface(rootPath)
    LoadEssentials()
    return ResidentSurfaceLifecycle.CreateSurface({
        skin = SKIN,
        surfaceId = 'InventoryBG',
        configPath = InventoryLifecycle.InventoryBgConfigPath(rootPath),
        entryFile = 'InventoryBG.ini',
        measureName = 'MeasureHighlight',
        visibleVariable = 'BlockHudInventoryVisible',
        visibleMirrorConfigs = InventoryLifecycle.InventoryVisibleMirrorResolver(rootPath),
        internalStatePath = InventoryLifecycle.InternalStatePath,
        clearVisibleOnRainmeterClose = true,
        preShowLayoutMeasure = 'MeasureResponsiveLayout',
        preShowLayoutCommand = '',
        featureEnabled = InventoryLifecycle.IsInventoryFeatureEnabled,
        beforeShow = function()
            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
            SKIN:Bang('!Draggable', '0')
            ApplyInventoryBackdropOpenZOrder(rootPath)
        end,
        beforeSuspend = function()
            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
        end,
    })
end
function EnsureHighlightSlotActionLaunch()
    if HighlightSlotActionLaunch == nil then
        HighlightSlotActionLaunch = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\HighlightSlotActionLaunch.lua')
    end
    return HighlightSlotActionLaunch
end

local function IsUrl(s)
    return EnsureHighlightSlotActionLaunch().isUrl(s)
end
local function IsUriScheme(s)
    return EnsureHighlightSlotActionLaunch().isUriScheme(s)
end
local function LooksLikePlainPath(s)
    return EnsureHighlightSlotActionLaunch().looksLikePlainPath(s)
end
function IsInternalWebNowPlayingCoverPath(s)
    local backslash = string.char(92)
    local normalized = trimText(s):gsub('/', backslash):lower()
    normalized = normalized:gsub('^%[', ''):gsub('%]$', ''):gsub('^"', ''):gsub('"$', '')
    if normalized == 'cover.png' then
        return true
    end
    return normalized:find(backslash .. 'rainmeter' .. backslash .. 'webnowplaying' .. backslash .. 'cover.png', 1, true) ~= nil
end
local function IsBracketedBang(s)
    return EnsureHighlightSlotActionLaunch().isBracketedBang(s)
end
local function LuaStringLiteral(value)
    return EnsureHighlightSlotActionLaunch().luaStringLiteral(value)
end
function PowerShellSingleQuoted(value)
    return EnsureHighlightSlotActionLaunch().powerShellSingleQuoted(value)
end

local function startHudOpenLogFolderHelper()
    if not SKIN:GetMeasure('MeasureHudActionRun') then
        return false
    end
    local rootPath = trimText(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return false
    end
    local helperPath = rootPath .. 'Utilities\\tools\\OpenSettingsLogFolder.ps1'
    local parameter = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' .. PowerShellSingleQuoted(helperPath)
        .. ' -TargetRoot ' .. PowerShellSingleQuoted(rootPath)
    SyncHudActionPowerShellProgramPath()
    SKIN:Bang('!SetOption', 'MeasureHudActionRun', 'Parameter', parameter)
    SKIN:Bang('!UpdateMeasure', 'MeasureHudActionRun')
    SKIN:Bang('!CommandMeasure', 'MeasureHudActionRun', 'Run')
    return true
end

function QuoteActionArg(value)
    return EnsureHighlightSlotActionLaunch().quoteActionArg(value)
end
function SplitExecutablePath(exec)
    return EnsureHighlightSlotActionLaunch().splitExecutablePath(exec)
end
function BuildBang(exec)
    return EnsureHighlightSlotActionLaunch().buildBang(exec, function(value)
        logWarning('[HighlightSlot] unsafe action contains an unwrapped ] delimiter: ' .. value)
    end)
end
local function PlayClickSound()
    if useClickSound == 0 then return end
    SKIN:Bang('PlayStop')
    SKIN:Bang('Play "' .. clickSoundPath .. '"')
end
local function IsInventoryItem(s)
    return s == _G.DMeloper.OPEN_INVENTORY_KEY
end
local function CurrentLanguageCode()
    return LanguageRegistry.NormalizeLanguageCode(SKIN, LanguageBranching.CurrentSkinLanguageCode(SKIN, 'en-US'), 'en-US')
end
local function ReservedInventoryDisplayName()
    return LanguageRegistry.GetInventoryLabel(SKIN, CurrentLanguageCode())
end
local function InventoryUsageGuideUrl()
    return LanguageBranching.SelectKoreanElseGlobal(
        CurrentLanguageCode(),
        'https://www.notion.so/aismash/DMeloper-s-Minecraft-HUD-2ef2dc0bb4ae80b680f6e32702630721?source=copy_link',
        'https://www.notion.so/aismash/DMeloper-s-Block-HUD-Global-35c2dc0bb4ae801abf7dd76acee80689?source=copy_link'
    )
end
local function CreatorProfileUrl()
    return LanguageBranching.SelectKoreanElseGlobal(CurrentLanguageCode(), 'https://litt.ly/dmeloper', 'https://linktr.ee/dmeloper.dev')
end
local function SyncCreatorProfileLink()
    if IsHotbar then
        return
    end
    if tostring(SKIN:GetVariable('PlayerBitmap', '') or '') == '' then
        return
    end
    local currentLanguageCode = CurrentLanguageCode()
    if lastCreatorProfileLanguageCode == currentLanguageCode then
        return
    end
    lastCreatorProfileLanguageCode = currentLanguageCode
    local action = '["' .. CreatorProfileUrl() .. '"]'
    for _, meterName in ipairs(CREATOR_PROFILE_METERS) do
        SKIN:Bang(_G.DMeloper.BANG_SET_OPTION, meterName, 'LeftMouseUpAction', action)
    end
end
local function ResetItemTextCache()
    lastItemName = 'NONE'
    if not IsHotbar then
        return
    end
    SetHotbarText('', 'static')
end
local function SyncLanguageSensitiveItemText()
    local currentLanguageCode = CurrentLanguageCode()
    if lastLanguageCode == currentLanguageCode then
        return
    end
    lastLanguageCode = currentLanguageCode
    if ItemInfosHolder and type(ItemInfosHolder.RefreshInfos) == 'function' then
        ItemInfosHolder.RefreshInfos()
    end
    ResetItemTextCache()
    if curInfo and lastIndexX >= 1 and lastIndexY >= 1 then
        curInfo = ItemInfosHolder.GetInfo(lastIndexX, lastIndexY)
        UpdateItemText()
    end
end
local function ShowHotbarText()
    if hotbarTextEnabled == false then
        return
    end
    if hotbarTextVisible then
        SKIN:Bang('!CommandMeasure', 'MeasureFade', 'KeepAlive()')
        return
    end
    hotbarTextVisible = true
    SKIN:Bang('!CommandMeasure', 'MeasureFade', 'Show()')
end
local function AddNotice(origin, notice, isHotbar)
    if not IsMissingHintVisible then return end
    if origin == '' then return notice end
    if isHotbar then return origin .. ' ' .. notice end
    return origin .. '\n' .. notice
end
local function UpdateHotbarText()
    if not curInfo then return end
    local resultText = IsInventoryItem(curInfo.ExecPath or '') and ReservedInventoryDisplayName() or (curInfo.ItemName or '')
    if (curInfo.Image or '') == '' then resultText = AddNotice(resultText, SKIN:GetVariable('Loc_HUD_MissingImage', '(이미지 없음)'), true) end
    if (curInfo.ItemName or '') == '' then resultText = AddNotice(resultText, SKIN:GetVariable('Loc_HUD_MissingName', '(이름 없음)'), true) end
    if (curInfo.ExecPath or '') == '' then resultText = AddNotice(resultText, SKIN:GetVariable('Loc_HUD_MissingExecPath', '(실행 경로 없음)'), true) end
    if resultText ~= lastItemName then
        lastItemName = resultText
        SetHotbarText(lastItemName, 'static')
    end
    ShowHotbarText()
end
local function showExternalHotbarText(text, pinnedOwner, textMode)
    LoadEssentials()
    if not IsHotbar then
        return false
    end
    text = trimText(text)
    if text == '' then
        return false
    end
    if pinnedOwner ~= nil then
        pinnedOwner = trimText(pinnedOwner)
        if pinnedOwner == '' then
            return false
        end
        pinnedExternalHotbarTextOwner = pinnedOwner
        SKIN:Bang('!CommandMeasure', 'MeasureFade', 'Pin()')
    end
    local hotbarTextMode = tostring(textMode or ''):match('^%s*(.-)%s*$') or ''
    if hotbarTextMode ~= 'scroll' then
        hotbarTextMode = pinnedOwner == 'Jukebox' and 'scroll' or 'static'
    end
    lastItemName = text
    SetHotbarText(text, hotbarTextMode)
    ShowHotbarText()
    return true
end
function ShowExternalHotbarText(text, mode)
    return showExternalHotbarText(text, nil, mode)
end
function ShowPinnedExternalHotbarText(owner, text, mode)
    return showExternalHotbarText(text, owner, mode)
end
function ReleasePinnedExternalHotbarText(owner)
    LoadEssentials()
    if not IsHotbar then
        return false
    end
    owner = trimText(owner)
    if owner == '' or pinnedExternalHotbarTextOwner ~= owner then
        return false
    end
    pinnedExternalHotbarTextOwner = ''
    SKIN:Bang('!CommandMeasure', 'MeasureFade', 'Unpin()')
    return true
end
function ShowBackgroundHotbarText(owner, text, mode)
    LoadEssentials()
    if not IsHotbar then
        return false
    end
    owner = trimText(owner)
    text = trimText(text)
    if owner == '' or text == '' then
        return false
    end
    local hotbarTextMode = tostring(mode or ''):match('^%s*(.-)%s*$') or ''
    if hotbarTextMode ~= 'scroll' then
        hotbarTextMode = 'static'
    end
    SKIN:Bang('!CommandMeasure', 'MeasureFade', string.format('SetBackgroundText(%q,%q,%q)', owner, text, hotbarTextMode))
    return true
end
function ClearBackgroundHotbarText(owner)
    LoadEssentials()
    if not IsHotbar then
        return false
    end
    owner = trimText(owner)
    if owner == '' then
        return false
    end
    SKIN:Bang('!CommandMeasure', 'MeasureFade', string.format('ClearBackgroundText(%q)', owner))
    return true
end

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
    dragVisualImagePath = nil
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
    dragPayloadKey = payloadKey
    dragPayload = {
        imagePath = EditorItemService.GetImagePath(R, dragRecord.ImageKey),
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
    if payload.imagePath ~= dragVisualImagePath then
        dragVisualImagePath = payload.imagePath
        SKIN:Bang('!SetOption', DRAG_IMAGE_METER, 'ImageName', payload.imagePath)
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
