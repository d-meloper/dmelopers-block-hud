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
    return 'powershell'
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
    local parameter = '-NoProfile -ExecutionPolicy Bypass -File ' .. PowerShellSingleQuoted(helperPath)
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
