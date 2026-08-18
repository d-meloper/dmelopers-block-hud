-- Generated runtime aggregate for Rainmeter-safe split loading. Edit sibling part files instead.
-- Split from Editor\InputCommit.lua lines 1-1435.
local currentTarget = nil

EditorValueHelpers = nil



local editorRoot = nil



local editorItemService = nil

local modalAlertBridge = nil
local residentUpdateController = nil

local startEditorOpenLogFolderHelper = nil
local editorOpenLogFolderRunning = false



local closeDiscardApplied = false



local closeRequestMode = nil

local closeCommitChanged = false



local consumerMirroringSuspended = false



local deferredInitRequested = false



local sessionHeartbeatClockMs = -1



local dragOutsideClockMs = -1



local DRAG_OUTSIDE_CANCEL_TIMEOUT_MS = 1500



local DEFAULT_NEW_ITEM_IMAGE = 'default.png'



local IMAGE_ADJUSTMENT_MIN = -32



local IMAGE_ADJUSTMENT_MAX = 32



local undoHistory = {}



local redoHistory = {}



local sessionBaselineSnapshot = nil



local sessionHistoryInitialized = false



local resolveCommittedQtyValue

local getDraftMeta

local shouldSkipEmptyDraftPersist

local function ensureResidentUpdateController()
    if residentUpdateController == nil then
        residentUpdateController = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\ResidentUpdateController.lua')
    end
    return residentUpdateController
end

EditorLifecycle = EditorLifecycle or {}
function EditorLifecycle.EnsureResidentSurfaceLifecycle()
    if EditorLifecycle.ResidentSurfaceLifecycle == nil then
        EditorLifecycle.ResidentSurfaceLifecycle = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\ResidentSurfaceLifecycle.lua')
    end
    return EditorLifecycle.ResidentSurfaceLifecycle
end

function EnsureEditorValueHelpers()
    if EditorValueHelpers == nil then
        EditorValueHelpers = dofile((SKIN:GetVariable('CURRENTPATH', '') or '') .. 'Runtime\\EditorValueHelpers.lua')
    end
    return EditorValueHelpers
end
local applyRunConfirmToggleChange



local draftImageAdjustments = nil



local DELETE_BUTTON_BG_COLOR = '237,28,36,255'



local DELETE_BUTTON_TEXT_COLOR = '255,255,255,255'



local ADD_BUTTON_BG_COLOR = '23,120,51,255'



local ADD_BUTTON_TEXT_COLOR = '255,255,255,255'



local function trim(value)



    return tostring(value or ''):match('^%s*(.-)%s*$')



end

local function normalizeConfirmBeforeRun(value)
    return EnsureEditorValueHelpers().normalizeConfirmBeforeRun(value)
end

function normalizeActionType(value)
    return trim(value):lower() == 'folder' and 'folder' or ''
end

function normalizeFolderCountSync(value, actionType)
    if normalizeActionType(actionType) ~= 'folder' then
        return '0'
    end
    return trim(value) == '1' and '1' or '0'
end



local function hasSkinGetVariable()

    local ok, method = pcall(function()

        return SKIN and SKIN.GetVariable

    end)

    return ok and type(method) == 'function'

end

function EditorLifecycle.DecodeCatalogEscapes(value)
    return tostring(value or '')
        :gsub('\\n', '\n')
        :gsub('\\r', '\r')
        :gsub('\\t', '\t')
end

local function L(key, fallback)

    if hasSkinGetVariable() then

        return EditorLifecycle.DecodeCatalogEscapes(SKIN:GetVariable('Loc_' .. tostring(key or ''), fallback or ''))

    end

    if key == 'Editor_ItemReservedInventory' then

        return 'Inventory'

    end

    return EditorLifecycle.DecodeCatalogEscapes(fallback)

end

function registryInventoryLabelForCode(languageCode)
    if not hasSkinGetVariable() then
        return 'Inventory'
    end

    local requested = trim(languageCode)
    local fallback = trim(SKIN:GetVariable('DefaultFallbackLanguageCode', 'en-US'))
    local count = tonumber(SKIN:GetVariable('LanguageCount', '0')) or 0
    local fallbackLabel = ''
    for index = 1, count do
        local prefix = 'Language_' .. tostring(index) .. '_'
        local code = trim(SKIN:GetVariable(prefix .. 'Code', ''))
        local label = trim(SKIN:GetVariable(prefix .. 'InventoryLabel', ''))
        if label ~= '' then
            if code == requested then
                return label
            end
            if code == fallback then
                fallbackLabel = label
            end
        end
    end
    return fallbackLabel ~= '' and fallbackLabel or 'Inventory'
end

function currentLanguageCode()
    if not hasSkinGetVariable() then
        return 'en-US'
    end
    return trim(SKIN:GetVariable('LanguageCode', SKIN:GetVariable('DefaultFallbackLanguageCode', 'en-US')))
end

local function locRef(key)
    return '#Loc_' .. tostring(key or '') .. '#'
end

local RESERVED_INVENTORY_LABEL_VARIABLE = 'Loc_Editor_ItemReservedInventory'
local RESERVED_INVENTORY_LABEL_REFERENCE = '#' .. RESERVED_INVENTORY_LABEL_VARIABLE .. '#'

local function isReservedInventoryLabelValue(value)
    local text = trim(value)
    if text == '' then
        return false
    end
    if text == RESERVED_INVENTORY_LABEL_REFERENCE or text == RESERVED_INVENTORY_LABEL_VARIABLE then
        return true
    end
    if text == 'Inventory' or text == '인벤토리' then
        return true
    end

    local localized = trim(L('Editor_ItemReservedInventory', ''))
    if localized ~= '' and text == localized then
        return true
    end

    if text == registryInventoryLabelForCode(currentLanguageCode()) then
        return true
    end

    if hasSkinGetVariable() then
        local count = tonumber(SKIN:GetVariable('LanguageCount', '0')) or 0
        for index = 1, count do
            local label = trim(SKIN:GetVariable('Language_' .. tostring(index) .. '_InventoryLabel', ''))
            if label ~= '' and text == label then
                return true
            end
        end
    end

    return false
end

local function canonicalReservedInventoryLabel(value)
    local text = trim(value)
    if text == '' or isReservedInventoryLabelValue(text) then
        return registryInventoryLabelForCode(currentLanguageCode())
    end
    return text
end

local function reservedInventoryLabel()

    return registryInventoryLabelForCode(currentLanguageCode())

end

local RESERVED_SLOT = {



    ImageKey = 'more.png',



    ItemName = reservedInventoryLabel(),



    ExecPath = '_OPEN_INVENTORY_',



    Qty = 0,

    ConfirmBeforeRun = '0',

    ActionType = '',

    FolderCountSync = '0',



}



RESERVED_SLOT.ItemName = reservedInventoryLabel()



local function LF(key, args, fallback)

    local value = L(key, fallback)

    for index, argument in ipairs(args or {}) do

        local replacement = tostring(argument or '')

        value = value:gsub('%%' .. tostring(index), function()

            return replacement

        end)

    end

    return value

end



local function syncReservedSlotLabel()

    RESERVED_SLOT.ItemName = reservedInventoryLabel()

end

local function clamp(value, minValue, maxValue)
    return EnsureEditorValueHelpers().clamp(value, minValue, maxValue)
end



local resolveCommittedQtyValue



local function ensureService()



    if not editorRoot then



        editorRoot = SKIN:GetVariable('@')



    end



    if not editorItemService then



        editorItemService = dofile(editorRoot .. 'Defaults\\Runtime\\luas\\data\\EditorItemService.lua')



    end



    return editorItemService



end
local function ensureModalAlertBridge()
    if not editorRoot then
        editorRoot = SKIN:GetVariable('@')
    end
    if not modalAlertBridge then
        modalAlertBridge = dofile(editorRoot .. 'Defaults\\Runtime\\luas\\ModalAlertBridge.lua')
    end
    return modalAlertBridge
end

local function editorModalAlertLogPath()
    local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    return rootPath .. "Logs\\DMeloper's Block HUD Log.log"
end

local function editorModalAlertHost()
    return {
        skin = SKIN,
        name = 'Editor',
        targetConfig = SKIN:GetVariable('CURRENTCONFIG', ''),
        targetMeasure = 'MeasureInputCommit',
        deferredVariable = 'BlockHudEditorModalAlertDeferredOpen',
        deferredMeasure = 'MeasureEditorModalAlertDeferredOpen',
        logPath = editorModalAlertLogPath(),
        openLogCallback = 'OpenModalAlertLogFolder',
        openFolder = function()
            if startEditorOpenLogFolderHelper then
                return startEditorOpenLogFolderHelper()
            end
            return false
        end,
    }
end

local function showEditorModalAlert(level, summaryKey, fallback)
    local bridge = ensureModalAlertBridge()
    return bridge.ShowAlertByKeys(editorModalAlertHost(), {
        level = level,
        summaryKey = summaryKey,
        summaryText = L(summaryKey, fallback),
        logPath = editorModalAlertLogPath(),
    })
end

local function logEditorErrorAndAlert(message, summaryKey, fallback)
    local bridge = ensureModalAlertBridge()
    local key = trim(summaryKey or '')
    local summary = fallback or message
    if key ~= '' then
        summary = L(key, summary)
    end
    return bridge.LogErrorAndAlert(editorModalAlertHost(), {
        source = 'Editor',
        logMessage = message,
        summaryKey = key,
        summaryText = summary,
        logPath = editorModalAlertLogPath(),
    })
end



function EditorLifecycle.InternalStatePath()
    if not editorRoot then
        editorRoot = SKIN:GetVariable('@')
    end
    if editorRoot and editorRoot ~= '' then
        return editorRoot .. 'Defaults\\Runtime\\incs\\InternalState.inc'
    end
    return ''
end

function EditorLifecycle.VisibleMirrorConfigs(rootConfig)
    if rootConfig == '' then
        return {}
    end
    return {
        rootConfig .. '\\HUD\\Hotbar',
        rootConfig .. '\\HUD\\Inventory',
        rootConfig .. '\\HUD\\InventoryBG',
        rootConfig .. '\\HUD\\Editor',
    }
end

function EditorLifecycle.CreateSurface()
    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))
    local configPath = ''
    if rootConfig ~= '' then
        configPath = rootConfig .. '\\HUD\\Editor'
    end
    return EditorLifecycle.EnsureResidentSurfaceLifecycle().CreateSurface({
        skin = SKIN,
        surfaceId = 'Editor',
        configPath = configPath,
        entryFile = 'Editor.ini',
        measureName = 'MeasureInputCommit',
        visibleVariable = 'BlockHudEditorVisible',
        visibleMirrorConfigs = function()
            return EditorLifecycle.VisibleMirrorConfigs(rootConfig)
        end,
        internalStatePath = EditorLifecycle.InternalStatePath,
        clearVisibleOnRainmeterClose = true,
        preShowLayoutMeasure = 'MeasureResponsiveLayout',
        preShowLayoutCommand = 'ApplyLayout()',
    })
end

local function setEditorVisibleState(visible)
    return EditorLifecycle.CreateSurface():SetVisible(visible)
end

local function isEditorVisibleStateEnabled()
    return EditorLifecycle.CreateSurface():IsVisibleIntent()
end
local function playUiClick()



    if not editorRoot then



        editorRoot = SKIN:GetVariable('@')



    end



    local enabled = tonumber(trim(SKIN:GetVariable('UseClickSound', '1'))) or 1



    if enabled == 0 or not editorRoot or editorRoot == '' then



        return



    end



    SKIN:Bang('Play "' .. editorRoot .. 'Defaults\\Runtime\\audios\\click.wav"')



end



local function fileExists(path)



    local handle = io.open(tostring(path or ''), 'rb')



    if handle then



        handle:close()



        return true



    end



    return false



end



local function resolvePowerShellProgramPath()
    return 'powershell'
end



local function syncPowerShellProgramPath()



    SKIN:Bang('!SetVariable', 'EditorPowerShellProgram', resolvePowerShellProgramPath())



end

local function quotePowerShellArgument(value)
    value = tostring(value or '')
    value = value:gsub("'", "''")
    return "'" .. value .. "'"
end

local function buildOpenLogFolderArgs()
    local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    local helperPath = rootPath .. 'Utilities\\tools\\OpenSettingsLogFolder.ps1'
    return '-NoProfile -ExecutionPolicy Bypass -File ' .. quotePowerShellArgument(helperPath) ..
        ' -TargetRoot ' .. quotePowerShellArgument(rootPath)
end

startEditorOpenLogFolderHelper = function()
    if editorOpenLogFolderRunning then
        return false
    end
    if not SKIN:GetMeasure('MeasureEditorOpenLogFolderRun') then
        return false
    end
    syncPowerShellProgramPath()
    local args = buildOpenLogFolderArgs()
    if args == '' then
        return false
    end
    editorOpenLogFolderRunning = true
    SKIN:Bang('!SetVariable', 'EditorOpenLogFolderArgs', args)
    SKIN:Bang('!UpdateMeasure', 'MeasureEditorOpenLogFolderRun')
    SKIN:Bang('!CommandMeasure', 'MeasureEditorOpenLogFolderRun', 'Run')
    return true
end

function HandleEditorOpenLogFolderComplete()
    editorOpenLogFolderRunning = false
    return true
end




function PlayUiClick()



    playUiClick()



end



local function setRunConfirmToggleUi(enabled)



    local value = enabled and '1' or '0'



    local fillColor = enabled and SKIN:GetVariable('EditorRunConfirmToggleFillOnColor', '') or SKIN:GetVariable('EditorRunConfirmToggleFillOffColor', '0,0,0,0')



    SKIN:Bang('!SetVariable', 'EditorRunConfirmToggleValue', value)



    SKIN:Bang('!SetVariable', 'EditorRunConfirmToggleFillColor', fillColor)



    SKIN:Bang('!UpdateMeter', 'MeterRunConfirmToggleBackground')



    SKIN:Bang('!UpdateMeter', 'MeterRunConfirmToggleFill')



    SKIN:Bang('!Redraw')



end



function ToggleRunConfirmUi()



    playUiClick()



    local enabled = trim(SKIN:GetVariable('EditorRunConfirmToggleValue', '0')) ~= '1'

    setRunConfirmToggleUi(enabled)

    if applyRunConfirmToggleChange then

        applyRunConfirmToggleChange(enabled)

    end



end


local function numericVariable(name, fallback)



    local numeric = tonumber(trim(SKIN:GetVariable(name, tostring(fallback))))



    if numeric then



        return math.floor(numeric)



    end



    return fallback



end



local function wrapStepValue(value, minValue, maxValue)
    return EnsureEditorValueHelpers().wrapStepValue(value, minValue, maxValue)
end



local function currentValueFrom(variableName, minVariable, maxVariable)



    local minValue = numericVariable(minVariable, 1)



    local maxValue = numericVariable(maxVariable, 9)



    local numeric = tonumber(trim(SKIN:GetVariable(variableName, '')))



    if numeric then



        return clamp(math.floor(numeric), minValue, maxValue)



    end



    return nil



end



local function measureNumericValue(measureName, fallback)



    local measure = SKIN:GetMeasure(measureName)



    if not measure then



        return fallback



    end



    local value = tonumber(measure:GetValue())



    if value == nil then



        return fallback



    end



    return math.floor(value)



end



local INPUT_MEASURE_BY_TARGET = {



    name = 'MeasureInputField',



    path = 'MeasurePathInputField',



    x = 'MeasureInputField2',



    y = 'MeasureInputField3',



    qty = 'MeasureInputField4',



    imageOffsetX = 'MeasureInputField5',



    imageOffsetY = 'MeasureInputField6',



    imageSizeOffset = 'MeasureInputField7',



}



local PICKER_RUN_BY_KIND = {



    path = {



        measure = 'MeasurePathPickRun',



        runningVar = 'EditorPathPickerRunning',



        restartVar = 'EditorPathPickerRestartPending',



    },



    image = {



        measure = 'MeasureImagePickRun',



        runningVar = 'EditorImagePickerRunning',



        restartVar = 'EditorImagePickerRestartPending',



    },



}



local function readPendingInputValue(target)



    return SKIN:GetVariable('EditorPendingInputValue', '')



end



local function clearPendingInputValue()



    SKIN:Bang('!SetVariable', 'EditorPendingInputValue', '')



end



local function setLabeledInput(valueVariable, displayVariable, placeholderVariable, meterName, resolved)



    local display = resolved



    if display == '' then



        display = SKIN:GetVariable(placeholderVariable, '')



    end



    SKIN:Bang('!SetVariable', valueVariable, resolved)



    SKIN:Bang('!SetVariable', displayVariable, display)



    SKIN:Bang('!UpdateMeter', meterName)



end



local function setBasicInput(resolved)



    local display = tostring(resolved or '')



    if display == '' then



        display = locRef('Editor_Placeholder_Text')



    end



    SKIN:Bang('!SetVariable', 'EditorInputValue', resolved)



    SKIN:Bang('!SetVariable', 'EditorInputDisplayText', display)



    SKIN:Bang('!UpdateMeter', 'MeterInputFieldText')



end

local function setPathInput(resolved, displayLabel)



    local service = ensureService()



    if service.ClearProgramActionLabelCache then



        service.ClearProgramActionLabelCache(editorRoot)



    end



    local display = tostring(resolved or '')



    local selectedName = trim(displayLabel)
    if selectedName == '' then
        selectedName = service.DescribeAction(resolved, editorRoot)
    end



    local summaryText = ' '



    if display == '' then



        display = locRef('Editor_PathPrompt')



        selectedName = ' '



    elseif service.IsAppsFolderAction and service.IsAppsFolderAction(resolved) then



        summaryText = '< ' .. tostring(selectedName or '') .. ' >'



    else



        local selectedNameText = tostring(selectedName or '')
        if selectedNameText ~= '' then
            summaryText = LF('Editor_PathSelectedFormat', { selectedNameText }, '< ' .. selectedNameText .. ' > selected.')
        else
            summaryText = locRef('Editor_PathPrompt')
        end



    end



    SKIN:Bang('!SetVariable', 'EditorInputValue2', resolved)



    SKIN:Bang('!SetVariable', 'EditorInputDisplayText2', display)



    SKIN:Bang('!SetVariable', 'EditorSelectedPathName', tostring(selectedName or ''))



    SKIN:Bang('!SetVariable', 'EditorSelectedPathSummaryText', summaryText)



    SKIN:Bang('!UpdateMeter', 'MeterPathInputText')



    SKIN:Bang('!UpdateMeter', 'MeterPathSummary')



end



local function normalizeImageAsset(value)



    local service = ensureService()



    return service.NormalizeImageAsset(trim(value)) or trim(value)



end



local function setImageKey(resolved)



    local service = ensureService()



    local imagePath = SKIN:GetVariable('EditorDefaultViewerImagePath', '')



    local imageKey = normalizeImageAsset(resolved)



    if imageKey ~= '' then



        imagePath = service.GetImagePath(editorRoot, imageKey)



    end



    SKIN:Bang('!SetVariable', 'EditorImageKeyValue', imageKey)



    SKIN:Bang('!SetVariable', 'ViewerSampleImagePath', imagePath)



    SKIN:Bang('!UpdateMeter', 'MeterViewerPreviewImage')

    if type(SyncEditorPixelationState) == 'function' then
        SyncEditorPixelationState(imageKey)
    end

    SKIN:Bang('!CommandMeasure', 'MeasureItemImageAnimator', 'RefreshBindings()')



end



local function logMessage(level, message)



    if tostring(level or ''):lower() == 'error' then
        logEditorErrorAndAlert(message, '', message)
    else
        SKIN:Bang('!Log', message, level or 'Notice')
    end



end



local function refreshThemeVisuals()



    local measures = {



        'MeasureInputField',



        'MeasurePathInputField',



        'MeasureInputField2',



        'MeasureInputField3',



        'MeasureInputField4',



    }



    for _, measureName in ipairs(measures) do



        SKIN:Bang('!UpdateMeasure', measureName)



    end



    local meters = {



        'MeterEditorPanel',



        'MeterTopBarUndoButtonBackground',



        'MeterTopBarUndoButtonLabel',



        'MeterTopBarRedoButtonBackground',



        'MeterTopBarRedoButtonLabel',



        'MeterTopBarResetButtonBackground',



        'MeterTopBarResetButtonLabel',



        'MeterFooterPagePrevButtonBackground',



        'MeterFooterPagePrevButtonLabel',



        'MeterFooterPageCurrentButtonBackground',



        'MeterFooterPageCurrentButtonLabel',



        'MeterFooterPageNextButtonBackground',



        'MeterFooterPageNextButtonLabel',



        'MeterCloseButtonBackground',



        'MeterCloseButtonLabel',



        'MeterFooterBarBackground',



        'MeterItemActionPrimaryBackground',



        'MeterItemActionPrimaryLabel',



        'MeterItemActionCancelBackground',



        'MeterItemActionCancelLabel',



        'MeterItemActionConfirmBackground',



        'MeterItemActionConfirmLabel',



        'MeterEditorLoadingOverlay',



        'MeterEditorLoadingLabelLine1',

        'MeterEditorLoadingLabelLine2',



        'MeterEditorNoSelectionOverlay',



        'MeterEditorNoSelectionMessage',



    }



    for _, meterName in ipairs(meters) do



        SKIN:Bang('!UpdateMeter', meterName)



    end



    SKIN:Bang('!UpdateMeterGroup', 'EditorPage1')



    SKIN:Bang('!UpdateMeterGroup', 'EditorPage2')



    SKIN:Bang('!Redraw')



end



local function setEditorLoadingVisible(visible)



    SKIN:Bang('!SetVariable', 'EditorLoadingHidden', visible and '0' or '1')



    SKIN:Bang('!UpdateMeter', 'MeterEditorLoadingOverlay')



    SKIN:Bang('!UpdateMeter', 'MeterEditorLoadingLabelLine1')

    SKIN:Bang('!UpdateMeter', 'MeterEditorLoadingLabelLine2')



    SKIN:Bang('!Redraw')



end

function SetEditorLoadingText(line1, line2)
    SKIN:Bang('!SetVariable', 'EditorLoadingTextLine1', line1 or '#Loc_Editor_Loading_Line1#')
    SKIN:Bang('!SetVariable', 'EditorLoadingTextLine2', line2 or '#Loc_Editor_Loading_Line2#')
    SKIN:Bang('!UpdateMeter', 'MeterEditorLoadingLabelLine1')
    SKIN:Bang('!UpdateMeter', 'MeterEditorLoadingLabelLine2')
end

function ShowEditorSaveLoading()
    SetEditorLoadingText('#Loc_Editor_SaveLoading_Line1#', '#Loc_Editor_SaveLoading_Line2#')
    setEditorLoadingVisible(true)
end



local function cancelDeferredInitialize()



    deferredInitRequested = false



    SKIN:Bang('!CommandMeasure', 'MeasureEditorDeferredInit', 'Stop 1')



end



local function syncPageDisplay()



    local pageCount = tonumber(trim(SKIN:GetVariable('EditorPageCount', '2'))) or 2



    if pageCount < 1 then



        pageCount = 1



    end



    local pageIndex = tonumber(trim(SKIN:GetVariable('EditorPageIndex', '1'))) or 1



    pageIndex = math.floor(pageIndex)



    pageIndex = ((pageIndex - 1) % pageCount) + 1



    local bottomVariable = 'ShowcasePage1BottomY'



    local pageLabel = tostring(pageIndex) .. '/' .. tostring(pageCount)



    SKIN:Bang('!ShowMeterGroup', 'EditorPage1')



    SKIN:Bang('!HideMeterGroup', 'EditorPage2')



    if pageIndex == 2 then



        bottomVariable = 'ShowcasePage2BottomY'



        SKIN:Bang('!HideMeterGroup', 'EditorPage1')



        SKIN:Bang('!ShowMeterGroup', 'EditorPage2')



    end



    SKIN:Bang('!SetVariable', 'EditorPageIndex', tostring(pageIndex))



    SKIN:Bang('!SetVariable', 'EditorActivePageBottomY', SKIN:GetVariable(bottomVariable, SKIN:GetVariable('EditorActivePageBottomY', '')))



    SKIN:Bang('!SetVariable', 'EditorPageToggleText', pageLabel)



    SKIN:Bang('!SetVariable', 'ActionPageCurrent_LabelText', pageLabel)



end

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

    if rootConfig == '' or not EditorIsRainmeterConfigActive(rootConfig .. '\\HUD\\Inventory') then

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

        local configPath = rootConfig .. '\\HUD\\' .. consumer

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

        ActionType = '',

        FolderCountSync = '0',

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

        mirrorDraftMetaVariable(variableName, resolved)

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



        captureResponsiveLiveState('Hotbar', rootConfig .. '\\HUD\\Hotbar')

        local hotbarConfig = rootConfig .. '\\HUD\\Hotbar'

        if EditorIsRainmeterConfigActive(hotbarConfig) then

            SKIN:Bang('!Refresh', hotbarConfig, 'Hotbar.ini')

        end



    end



    if refreshInventory and isInventoryConsumerActive() then



        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!Redraw', rootConfig .. '\\HUD\\Inventory')



    end



end



local function refreshConsumersAfterEditorClose()



    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))



    if rootConfig == '' then



        return



    end



    captureResponsiveLiveState('Hotbar', rootConfig .. '\\HUD\\Hotbar')



    captureResponsiveLiveState('Inventory', rootConfig .. '\\HUD\\Inventory')



    local hotbarConfig = rootConfig .. '\\HUD\\Hotbar'

    if EditorIsRainmeterConfigActive(hotbarConfig) then

        SKIN:Bang('!Refresh', hotbarConfig, 'Hotbar.ini')

    end



    if isInventoryConsumerActive() then

        local inventoryBgConfig = rootConfig .. '\\HUD\\InventoryBG'

        if EditorIsRainmeterConfigActive(inventoryBgConfig) then

            SKIN:Bang('!Refresh', inventoryBgConfig, 'InventoryBG.ini')

        end



        SKIN:Bang('!Refresh', rootConfig .. '\\HUD\\Inventory', 'Inventory.ini')

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



        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', "InitInfos('force')", rootConfig .. '\\HUD\\Hotbar')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', rootConfig .. '\\HUD\\Hotbar')



    end



    if refreshInventory and isInventoryConsumerActive() then



        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', "InitInfos('force')", rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!UpdateMeasure', 'MeasureEditorModeBadgeVisibility', rootConfig .. '\\HUD\\Inventory')



        SKIN:Bang('!Redraw', rootConfig .. '\\HUD\\Inventory')



    end



end

-- Split from Editor\InputCommit.lua lines 2662-3982.
local function markDirtyAndRefresh()    setDirty(true)



    refreshDraftItemConsumersLite()



end



local function cloneRecord(record)



    return {



        Source = record.Source,



        Section = record.Section,



        x = record.x,



        y = record.y,



        ImageKey = record.ImageKey or '',



        ItemName = record.ItemName or '',

        ExecPath = record.ExecPath or '',

        ConfirmBeforeRun = normalizeConfirmBeforeRun(record.ConfirmBeforeRun),

        ActionType = normalizeActionType(record.ActionType),

        FolderCountSync = normalizeFolderCountSync(record.FolderCountSync, record.ActionType),



        Qty = record.Qty or 0,



        Populated = record.Populated == true,



    }



end



local function emptyRecord(source, x, y)



    local service = ensureService()



    return {



        Source = source,



        Section = service.GetSectionName(source, x, y),



        x = x,



        y = y,



        ImageKey = '',



        ItemName = '',



        ExecPath = '',



        Qty = 0,

        ConfirmBeforeRun = '0',

        ActionType = '',

        FolderCountSync = '0',



        Populated = false,



    }



end



local function writeRecordToPath(path, prefix, record)



    writeItemField(path, prefix, record.Section, 'Image', record.ImageKey or '')



    writeItemField(path, prefix, record.Section, 'Label', record.ItemName or '')



    writeItemField(path, prefix, record.Section, 'Action', record.ExecPath or '')



    writeItemField(path, prefix, record.Section, 'Qty', tostring(record.Qty or 0))

    writeItemField(path, prefix, record.Section, 'ConfirmBeforeRun', normalizeConfirmBeforeRun(record.ConfirmBeforeRun))

    writeItemField(path, prefix, record.Section, 'ActionType', normalizeActionType(record.ActionType))

    writeItemField(path, prefix, record.Section, 'FolderCountSync', normalizeFolderCountSync(record.FolderCountSync, record.ActionType))



end



local function writeDraftRecord(record)

    local service = ensureService()

    if service.IsReservedHotbarSlot(record.Source, record.x, record.y) then
        local existingLabel = trim(record.ItemName or '')
        if existingLabel == '' then
            existingLabel = trim(SKIN:GetVariable('EditorDraftItem_Slot10_Label', ''))
        end
        if existingLabel == '' then
            existingLabel = trim(SKIN:GetVariable('HotbarItem_Slot10_Label', ''))
        end
        if existingLabel == '' then
            existingLabel = RESERVED_SLOT.ItemName
        end
        existingLabel = canonicalReservedInventoryLabel(existingLabel)

        record = {

            Source = 'hotbar',

            Section = 'Slot10',

            x = 10,

            y = 1,

            ImageKey = RESERVED_SLOT.ImageKey,

            ItemName = existingLabel,

            ExecPath = RESERVED_SLOT.ExecPath,

            Qty = RESERVED_SLOT.Qty,

            ConfirmBeforeRun = '0',

            ActionType = '',

            FolderCountSync = '0',

        }

    end

    writeRecordToPath(service.GetPaths(editorRoot).Draft, 'EditorDraftItem', record)

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Image', record.ImageKey or '')

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Label', record.ItemName or '')

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Action', record.ExecPath or '')

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Qty', tostring(record.Qty or 0))

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_ConfirmBeforeRun', normalizeConfirmBeforeRun(record.ConfirmBeforeRun))

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_ActionType', normalizeActionType(record.ActionType))

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_FolderCountSync', normalizeFolderCountSync(record.FolderCountSync, record.ActionType))

end



local function updateCurrentTarget(record)



    if not record then



        currentTarget = nil



        return



    end



    currentTarget = {



        Source = record.Source,



        Section = record.Section,



        x = record.x,



        y = record.y,



        ImageKey = record.ImageKey,



        ItemName = record.ItemName,

        ExecPath = record.ExecPath,



        Qty = record.Qty,

        ConfirmBeforeRun = normalizeConfirmBeforeRun(record.ConfirmBeforeRun),

        ActionType = normalizeActionType(record.ActionType),

        FolderCountSync = normalizeFolderCountSync(record.FolderCountSync, record.ActionType),



    }



end



local function isCurrentTargetSlot(source, x, y)



    if not currentTarget then



        return false



    end



    return currentTarget.Source == source

        and currentTarget.x == x

        and currentTarget.y == y



end



local function syncCoordinateRanges(source)



    local service = ensureService()



    local useBottomSlot = service.GetUseBottomSlot(editorRoot)



    local bounds = nil



    if not useBottomSlot then



        bounds = service.GetCoordBounds('inventory', true)



    end



    if not bounds then



        bounds = service.GetCoordBounds(source, useBottomSlot) or service.GetCoordBounds('inventory', useBottomSlot)



    end



    SKIN:Bang('!SetVariable', 'EditorLabeledInputMin', tostring(bounds.XMin))



    SKIN:Bang('!SetVariable', 'EditorLabeledInputMax', tostring(bounds.XMax))



    SKIN:Bang('!SetVariable', 'EditorLabeledInput2Min', tostring(bounds.YMin))



    SKIN:Bang('!SetVariable', 'EditorLabeledInput2Max', tostring(bounds.YMax))



end



function SyncInventoryBottomRowLiveState(value)
    local literal = trim(value) == '1' and '1' or '0'
    SKIN:Bang('!SetVariable', 'UseInventoryBottomRow', literal)
    if currentTarget then
        syncCoordinateRanges(currentTarget.Source)
    else
        syncCoordinateRanges('inventory')
    end
    SKIN:Bang('!Redraw')
    return 0
end


local function resolveCoordinateDestination(source, nextX, nextY)



    local service = ensureService()



    local normalizedSource = service.NormalizeSource(source)



    if normalizedSource ~= 'hotbar' and normalizedSource ~= 'inventory' then



        return normalizedSource, nextX, nextY



    end



    if service.GetUseBottomSlot(editorRoot) then



        return normalizedSource, nextX, nextY



    end



    if tonumber(nextY) == 1 then



        return 'hotbar', nextX, 1



    end



    return 'inventory', nextX, nextY



end



local function isValidLogicalCoordinate(source, x, y)



    local service = ensureService()



    if service.GetUseBottomSlot(editorRoot) then



        return service.IsValidCoord(source, x, y, true)



    end



    local destinationSource, destinationX, destinationY = resolveCoordinateDestination(source, x, y)



    return service.IsValidCoord(destinationSource, destinationX, destinationY, false)



end



local function updateItemActionMeters()



    local meters = {



        'MeterItemActionPrimaryBackground',



        'MeterItemActionPrimaryLabel',



        'MeterItemActionCancelBackground',



        'MeterItemActionCancelLabel',



        'MeterItemActionConfirmBackground',



        'MeterItemActionConfirmLabel',



    }



    for _, meterName in ipairs(meters) do



        SKIN:Bang('!UpdateMeter', meterName)



    end



end



local function setActionVariable(name, value)



    SKIN:Bang('!SetVariable', name, tostring(value or ''))



end

local function setActionLocalizationVariable(name, key)

    setActionVariable(name, '#Loc_' .. key .. '#')

end

EditorLocalizationTextFit = nil

function EnsureEditorLocalizationTextFit()
    if EditorLocalizationTextFit == nil then
        local textFitModule = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\LocalizationTextFit.lua')
        EditorLocalizationTextFit = textFitModule.Create(SKIN, {
            widthProbeMeterName = 'MeterEditorTextFitProbe',
            wrapProbeMeterName = 'MeterEditorTextFitWrapProbe',
        })
    end
    return EditorLocalizationTextFit
end

function EditorTextFitNumericVariable(name, fallback)
    local direct = tonumber(tostring(name or ''))
    if direct ~= nil then
        return direct
    end
    local replaced = SKIN:ReplaceVariables('#' .. tostring(name or '') .. '#')
    local numeric = tonumber(replaced)
    if numeric ~= nil then
        return numeric
    end
    local ok, parsed = pcall(function()
        return SKIN:ParseFormula(replaced)
    end)
    return (ok and tonumber(parsed)) or fallback
end

function ApplyEditorTextFit(meterName, text, baseFontVariable, widthVariable, heightVariable, policy)
    local fitter = EnsureEditorLocalizationTextFit()
    if not fitter then
        return nil
    end
    return fitter:Apply({
        meterName = meterName,
        text = text,
        baseFontSize = EditorTextFitNumericVariable(baseFontVariable, 10) or 10,
        widthPx = EditorTextFitNumericVariable(widthVariable, 0) or 0,
        heightPx = EditorTextFitNumericVariable(heightVariable, 0) or 0,
        policy = policy or 'wrap4',
    })
end

local function applyEditorStaticTextFitTarget(target)
    if not target then
        return
    end
    local text = target.text or ('#Loc_' .. target.key .. '#')
    ApplyEditorTextFit(
        target.meter,
        text,
        target.base,
        target.width,
        target.height,
        target.policy
    )
end

function ApplyEditorStaticLocalizationTextFits()
    local targets = {
        { meter = 'MeterViewerLoadButtonLabel', key = 'Editor_LoadButton', base = 'ViewerLoadButtonFontSize', width = 'ViewerLoadButtonW', height = 'ViewerLoadButtonH' },
        { meter = 'MeterEditorLoadingLabelLine1', key = 'Editor_Loading_Line1', text = '#EditorLoadingTextLine1#', base = 'EditorUIFontSize', width = 'PanelWidth', height = 18, policy = 'single-line' },
        { meter = 'MeterEditorLoadingLabelLine2', key = 'Editor_Loading_Line2', text = '#EditorLoadingTextLine2#', base = 'EditorUIFontSize', width = 'PanelWidth', height = 18, policy = 'single-line' },
        { meter = 'MeterEditorNoSelectionMessage', key = 'Editor_NoSelection', base = 12, width = 'EditorNoSelectionMessageW', height = 'EditorNoSelectionMessageH' },
        { meter = 'MeterTopBarResetButtonLabel', key = 'Settings_Notice_Clear', base = 'EditorUIFontSize', width = 'ActionReset_W', height = 'ActionReset_H' },
        { meter = 'MeterFormTitle', key = 'Editor_FormTitle', base = 'LabeledInputTitleFontSize', width = 'SlotFormTitle_W', height = 'SlotFormTitle_H' },
        { meter = 'MeterPathTitle', key = 'Editor_PathTitle', base = 'LabeledInputTitleFontSize', width = 'SlotPathTitle_W', height = 'SlotPathTitle_H' },
        { meter = 'MeterRunConfirmToggleTitle', key = 'Editor_RunConfirmToggleTitle', base = 12, width = 'EditorRunConfirmToggleTitle_W', height = 'EditorRunConfirmToggleTitle_H' },
        { meter = 'MeterLabeledInputGroupTitle', key = 'Editor_PositionGroupTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInputGroupTitle_W', height = 'SlotLabeledInputGroupTitle_H' },
        { meter = 'MeterLabeledInputTitle', key = 'Editor_XTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInputTitle_W', height = 'SlotLabeledInputTitle_H' },
        { meter = 'MeterLabeledInput2Title', key = 'Editor_YTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInput2Title_W', height = 'SlotLabeledInput2Title_H' },
        { meter = 'MeterLabeledInput3Title', key = 'Editor_QtyTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInput3Title_W', height = 'SlotLabeledInput3Title_H' },
        { meter = 'MeterFolderCountSyncToggleTitle', key = 'Editor_FolderCountSyncTitle', base = 12, width = 'EditorFolderCountSyncToggleTitle_W', height = 'EditorFolderCountSyncToggleTitle_H' },
        { meter = 'MeterImageAdjustGroupTitle', key = 'Editor_ImageAdjustGroupTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjustGroupTitle_W', height = 'SlotImageAdjustGroupTitle_H' },
        { meter = 'MeterImageAdjustTitle', key = 'Editor_XTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjustTitle_W', height = 'SlotImageAdjustTitle_H' },
        { meter = 'MeterImageAdjust2Title', key = 'Editor_YTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjust2Title_W', height = 'SlotImageAdjust2Title_H' },
        { meter = 'MeterImageAdjust3Title', key = 'Editor_ImageAdjustSizeTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjust3Title_W', height = 'SlotImageAdjust3Title_H' },
    }
    for _, target in ipairs(targets) do
        applyEditorStaticTextFitTarget(target)
    end
end

function EditorLifecycle.SetFolderCountUnavailable(unavailable)
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncUnavailable', unavailable and '1' or '0')
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncTooltip', unavailable and '#Loc_Editor_FolderCountSyncUnavailable#' or '#Loc_Editor_FolderCountSyncTooltip#')
    SKIN:Bang('!UpdateMeter', 'MeterFolderCountSyncToggleTitle')
    SKIN:Bang('!UpdateMeter', 'MeterFolderCountSyncToggleBackground')
    SKIN:Bang('!UpdateMeter', 'MeterFolderCountSyncToggleFill')
end

function EditorLifecycle.SetFolderCountSyncUi(record)
    local service = ensureService()
    local populated = record and record.Populated == true
    local reserved = record and service.IsReservedHotbarSlot(record.Source, record.x, record.y)
    local actionType = populated and normalizeActionType(record.ActionType) or ''
    local eligible = populated and not reserved and actionType == 'folder'
    local linked = eligible and normalizeFolderCountSync(record.FolderCountSync, actionType) == '1'
    local manualQty = record and tostring(record.Qty or 0) or '0'

    SKIN:Bang('!SetVariable', 'EditorActionTypeValue', actionType)
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncValue', linked and '1' or '0')
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncEligible', eligible and '1' or '0')
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncCommand', eligible and '[!CommandMeasure MeasureInputCommit "ToggleFolderCountSyncUi()"]' or '')
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncCursor', eligible and '1' or '0')
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncTitleColor', eligible and SKIN:GetVariable('EditorInputTextColor', '') or SKIN:GetVariable('EditorButtonDisabledTextColor', ''))
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncToggleBgColor', eligible and SKIN:GetVariable('EditorButtonBgColor', '') or SKIN:GetVariable('EditorButtonDisabledBgColor', ''))
    SKIN:Bang('!SetVariable', 'EditorFolderCountSyncFillColor', linked and SKIN:GetVariable('EditorFolderCountSyncFillOnColor', '') or SKIN:GetVariable('EditorFolderCountSyncFillOffColor', '0,0,0,0'))
    SKIN:Bang('!SetVariable', 'EditorQtyInputEnabled', linked and '0' or '1')
    SKIN:Bang('!SetVariable', 'EditorQtyInputCommand', linked and '' or '[!CommandMeasure MeasureInputCommit "PrepareInputTarget(\'qty\')"][!UpdateMeasure MeasureInputField4][!CommandMeasure MeasureInputField4 "ExecuteBatch 1-2"]')
    SKIN:Bang('!SetVariable', 'EditorQtyInputCursor', linked and '0' or '1')
    SKIN:Bang('!SetVariable', 'EditorQtyInputBgColor', linked and SKIN:GetVariable('EditorButtonDisabledBgColor', '') or SKIN:GetVariable('EditorInputBgColor', ''))
    SKIN:Bang('!SetVariable', 'EditorQtyInputStrokeColor', linked and SKIN:GetVariable('EditorButtonDisabledTextColor', '') or SKIN:GetVariable('EditorInputStrokeColor', ''))
    SKIN:Bang('!SetVariable', 'EditorQtyInputTextColor', linked and SKIN:GetVariable('EditorButtonDisabledTextColor', '') or SKIN:GetVariable('EditorInputTextColor', ''))
    EditorLifecycle.SetFolderCountUnavailable(false)

    if linked then
        setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', '0')
        if type(RefreshFolderCountSync) == 'function' and tonumber(trim(SKIN:GetVariable('EditorPageIndex', '1'))) == 2 then
            RefreshFolderCountSync()
        end
    else
        setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', manualQty)
    end

    SKIN:Bang('!UpdateMeasure', 'MeasureInputField4')
    SKIN:Bang('!UpdateMeter', 'MeterLabeledInput3FieldBackground')
    SKIN:Bang('!UpdateMeter', 'MeterLabeledInput3Text')
    SKIN:Bang('!UpdateMeter', 'MeterFolderCountSyncToggleTitle')
    SKIN:Bang('!UpdateMeter', 'MeterFolderCountSyncToggleBackground')
    SKIN:Bang('!UpdateMeter', 'MeterFolderCountSyncToggleFill')
end



local function getButtonContractColors(enabled, bgOverride, textOverride)



    if bgOverride and textOverride then



        return bgOverride, textOverride



    end



    local activeBg = SKIN:GetVariable('EditorButtonBgColor', '0,0,0,0')



    local activeText = SKIN:GetVariable('EditorButtonTextColor', '255,255,255,255')



    local disabledBg = SKIN:GetVariable('EditorButtonDisabledBgColor', activeBg)



    local disabledText = SKIN:GetVariable('EditorButtonDisabledTextColor', activeText)



    if enabled then



        return bgOverride or activeBg, textOverride or activeText



    end



    return bgOverride or disabledBg, textOverride or disabledText



end



local function applyActionContract(prefix, enabled, command, tooltip, bgOverride, textOverride)



    local bgColor, textColor = getButtonContractColors(enabled, bgOverride, textOverride)



    setActionVariable(prefix .. '_Enabled', enabled and '1' or '0')



    setActionVariable(prefix .. '_Command', enabled and (command or '') or '')



    setActionVariable(prefix .. '_Tooltip', tooltip or '')



    setActionVariable(prefix .. '_BgColor', bgColor)



    setActionVariable(prefix .. '_TextColor', textColor)



end



local function syncItemActionState(record, mode)



    local service = ensureService()



    local primaryHidden = '1'



    local cancelHidden = '1'



    local confirmHidden = '1'



    local primaryLabelKey = 'Common_Add'



    local primaryCommand = ''



    local primaryTooltipKey = 'Editor_Action_NoSelection'



    local cancelCommand = ''



    local confirmCommand = ''



    local primaryEnabled = false



    local cancelEnabled = false



    local confirmEnabled = false



    local primaryBgColor = SKIN:GetVariable('EditorButtonBgColor', '0,0,0,0')



    local primaryTextColor = SKIN:GetVariable('EditorButtonTextColor', '255,255,255,255')



    local cancelBgColor = SKIN:GetVariable('EditorButtonBgColor', '0,0,0,0')



    local cancelTextColor = SKIN:GetVariable('EditorButtonTextColor', '255,255,255,255')



    local confirmBgColor = SKIN:GetVariable('EditorButtonBgColor', '0,0,0,0')



    local confirmTextColor = SKIN:GetVariable('EditorButtonTextColor', '255,255,255,255')



    if record and not service.IsReservedHotbarSlot(record.Source, record.x, record.y) then



        if mode == 'confirmDelete' and record.Populated then



            cancelHidden = '0'



            confirmHidden = '0'



            cancelCommand = '[!CommandMeasure MeasureInputCommit "CancelDeleteSelectedItem()"]'



            confirmCommand = '[!CommandMeasure MeasureInputCommit "ConfirmDeleteSelectedItem()"]'



            cancelEnabled = true



            confirmEnabled = true



            confirmBgColor = DELETE_BUTTON_BG_COLOR



            confirmTextColor = DELETE_BUTTON_TEXT_COLOR



        else



            primaryHidden = '0'



            if record.Populated then



                primaryLabelKey = 'Editor_Action_Delete'



                primaryCommand = '[!CommandMeasure MeasureInputCommit "RequestDeleteSelectedItem()"]'



                primaryTooltipKey = 'Editor_Action_DeleteTooltip'



                primaryEnabled = true



                primaryBgColor = DELETE_BUTTON_BG_COLOR



                primaryTextColor = DELETE_BUTTON_TEXT_COLOR



            else



                primaryLabelKey = 'Common_Add'



                primaryCommand = '[!CommandMeasure MeasureInputCommit "AddSelectedDraftItem()"]'



                primaryTooltipKey = 'Editor_Action_AddTooltip'



                primaryEnabled = true



                primaryBgColor = ADD_BUTTON_BG_COLOR



                primaryTextColor = ADD_BUTTON_TEXT_COLOR



            end



        end



    end



    setActionLocalizationVariable('ActionItemPrimary_LabelText', primaryLabelKey)
    ApplyEditorTextFit('MeterItemActionPrimaryLabel', '#Loc_' .. primaryLabelKey .. '#', 'EditorUIFontSize', 'ItemActionPrimaryW', 'ItemActionPrimaryH', 'wrap4')



    setActionVariable('ActionItemPrimary_Hidden', primaryHidden)



    applyActionContract('ActionItemPrimary', primaryEnabled, primaryCommand, '#Loc_' .. primaryTooltipKey .. '#', primaryBgColor, primaryTextColor)



    setActionVariable('ActionItemCancelDelete_Hidden', cancelHidden)



    applyActionContract('ActionItemCancelDelete', cancelEnabled, cancelCommand, '#Loc_Editor_Action_DeleteCancel#', cancelBgColor, cancelTextColor)
    ApplyEditorTextFit('MeterItemActionCancelLabel', '#Loc_Editor_Action_DeleteCancel#', 'EditorUIFontSize', 'ItemActionCancelW', 'ItemActionCancelH', 'wrap4')



    setActionVariable('ActionItemConfirmDelete_Hidden', confirmHidden)



    applyActionContract('ActionItemConfirmDelete', confirmEnabled, confirmCommand, '#Loc_Editor_Action_DeleteTooltip#', confirmBgColor, confirmTextColor)
    ApplyEditorTextFit('MeterItemActionConfirmLabel', '#Loc_Editor_Action_DeleteConfirm#', 'EditorUIFontSize', 'ItemActionConfirmW', 'ItemActionConfirmH', 'wrap4')



    updateItemActionMeters()



    SKIN:Bang('!Redraw')



end



local function hasActiveEditorSelection()



    return currentTarget ~= nil



end



local function updateEditorControlGateMeters()



    for _, meterName in ipairs({



        'MeterCloseButtonBackground',



        'MeterCloseButtonLabel',



        'MeterTopBarUndoButtonBackground',



        'MeterTopBarUndoButtonLabel',



        'MeterTopBarRedoButtonBackground',



        'MeterTopBarRedoButtonLabel',



        'MeterTopBarResetButtonBackground',



        'MeterTopBarResetButtonLabel',



        'MeterFooterPagePrevButtonBackground',



        'MeterFooterPagePrevButtonLabel',



        'MeterFooterPageCurrentButtonBackground',



        'MeterFooterPageCurrentButtonLabel',



        'MeterFooterPageNextButtonBackground',



        'MeterFooterPageNextButtonLabel',



        'MeterEditorNoSelectionOverlay',



        'MeterEditorNoSelectionMessage',



    }) do



        SKIN:Bang('!UpdateMeter', meterName)



    end



end



local function syncEditorControlGate()



    local enabled = hasActiveEditorSelection()



    SKIN:Bang('!SetVariable', 'EditorNoSelectionOverlayHidden', enabled and '1' or '0')



    applyActionContract('ActionCloseEditor', true, '[!CommandMeasure MeasureInputCommit "PlayUiClick()"][!CommandMeasure MeasureInputCommit "CloseEditor()"]', locRef('Editor_Action_Close'))



    applyActionContract('ActionPagePrev', enabled, '[!CommandMeasure MeasureInputCommit "PrevEditorPage()"]', locRef('Editor_Action_PagePrev'))



    applyActionContract('ActionPageCurrent', false, '', locRef('Editor_Action_PageCurrent'))



    applyActionContract('ActionPageNext', enabled, '[!CommandMeasure MeasureInputCommit "NextEditorPage()"]', locRef('Editor_Action_PageNext'))



    ApplyEditorStaticLocalizationTextFits()



    updateEditorControlGateMeters()



end



local function clearEditorUI()



    currentTarget = nil



    setImageKey(DEFAULT_NEW_ITEM_IMAGE)



    setBasicInput('')



    setPathInput('')

    setRunConfirmToggleUi(false)

    setLabeledInput('EditorLabeledInputValue', 'EditorLabeledInputDisplayText', 'EditorLabeledInputPlaceholder', 'MeterLabeledInputText', '')



    setLabeledInput('EditorLabeledInput2Value', 'EditorLabeledInput2DisplayText', 'EditorLabeledInput2Placeholder', 'MeterLabeledInput2Text', '')



    setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', '0')

    EditorLifecycle.SetFolderCountSyncUi(nil)



    syncImageAdjustmentUI(nil)



    syncCoordinateRanges('inventory')



    syncItemActionState(nil)



    syncEditorControlGate()



    refreshThemeVisuals()



end



local function updateEmptyTargetUI(record)



    updateCurrentTarget(record)



    setImageKey(DEFAULT_NEW_ITEM_IMAGE)



    setBasicInput('')



    setPathInput('')

    setRunConfirmToggleUi(false)

    setLabeledInput('EditorLabeledInputValue', 'EditorLabeledInputDisplayText', 'EditorLabeledInputPlaceholder', 'MeterLabeledInputText', tostring(record.x))



    setLabeledInput('EditorLabeledInput2Value', 'EditorLabeledInput2DisplayText', 'EditorLabeledInput2Placeholder', 'MeterLabeledInput2Text', tostring(record.y))



    setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', tostring(record.Qty or 0))

    EditorLifecycle.SetFolderCountSyncUi(record)



    syncImageAdjustmentUI(nil)



    syncCoordinateRanges(record.Source)



    syncItemActionState(record)



    syncEditorControlGate()



    refreshThemeVisuals()



end



local function updateTargetUI(record)



    updateCurrentTarget(record)



    setImageKey(record.ImageKey)



    setBasicInput(record.ItemName)



    setPathInput(record.ExecPath)

    setRunConfirmToggleUi(normalizeConfirmBeforeRun(record.ConfirmBeforeRun) == '1')

    setLabeledInput('EditorLabeledInputValue', 'EditorLabeledInputDisplayText', 'EditorLabeledInputPlaceholder', 'MeterLabeledInputText', tostring(record.x))



    setLabeledInput('EditorLabeledInput2Value', 'EditorLabeledInput2DisplayText', 'EditorLabeledInput2Placeholder', 'MeterLabeledInput2Text', tostring(record.y))



    setLabeledInput('EditorLabeledInput3Value', 'EditorLabeledInput3DisplayText', 'EditorLabeledInput3Placeholder', 'MeterLabeledInput3Text', tostring(record.Qty or 0))

    EditorLifecycle.SetFolderCountSyncUi(record)



    syncImageAdjustmentUI(record)



    syncCoordinateRanges(record.Source)



    syncItemActionState(record)



    syncEditorControlGate()



    refreshThemeVisuals()



end



local function syncSelectedSlotConsumers()



    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))



    if rootConfig == '' then



        return



    end



    for _, consumer in ipairs({ 'Hotbar', 'Inventory' }) do

        local configPath = rootConfig .. '\\HUD\\' .. consumer

        if EditorIsRainmeterConfigActive(configPath) then

            SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', configPath)

        end

    end



end



local function persistSelection(record)



    if record and record.Source and record.x and record.y then



        writeDraftMeta('SelectedSource', record.Source)



        writeDraftMeta('SelectedX', record.x)



        writeDraftMeta('SelectedY', record.y)



        writeDraftMeta('SelectedSection', record.Section)



    else



        writeDraftMeta('SelectedSource', '')



        writeDraftMeta('SelectedX', 0)



        writeDraftMeta('SelectedY', 0)



        writeDraftMeta('SelectedSection', '')



    end



    syncSelectedSlotConsumers()



end



local function setSelection(record)



    local service = ensureService()



    if not record or service.IsReservedHotbarSlot(record.Source, record.x, record.y) then



        persistSelection(nil)

        clearEditorUI()



        return false



    end



    persistSelection(record)



    if record.Populated then



        updateTargetUI(record)



    else



        updateEmptyTargetUI(record)



    end



    return true



end



local function refreshDragConsumersLite(targets)



    refreshDraftItemConsumersLite(targets)



end

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

        if normalizeActionType(leftRecord.ActionType) ~= normalizeActionType(rightRecord.ActionType) then
            return false
        end

        if normalizeFolderCountSync(leftRecord.FolderCountSync, leftRecord.ActionType) ~= normalizeFolderCountSync(rightRecord.FolderCountSync, rightRecord.ActionType) then
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



local function updateFieldAtLocator(locator, fieldName, value, actionType)



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



        local resolvedActionType = normalizeActionType(actionType)
        local resolvedFolderCountSync = normalizeFolderCountSync(record.FolderCountSync, resolvedActionType)

        if record.ExecPath == resolvedPath
            and normalizeActionType(record.ActionType) == resolvedActionType
            and normalizeFolderCountSync(record.FolderCountSync, record.ActionType) == resolvedFolderCountSync then



            return



        end



        record.ExecPath = resolvedPath

        record.ActionType = resolvedActionType

        record.FolderCountSync = resolvedFolderCountSync



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

                    or normalizeConfirmBeforeRun(record.ConfirmBeforeRun) ~= '0'
                    or normalizeActionType(record.ActionType) ~= ''
                    or normalizeFolderCountSync(record.FolderCountSync, record.ActionType) ~= '0' then



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

                        ActionType = '',

                        FolderCountSync = '0',



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



local function commitPathForLocator(value, locator, displayLabel, actionType)



    local resolved = trim(value)



    if shouldMirrorInputToVisibleSelection(locator) then



        setPathInput(resolved, displayLabel)

        SKIN:Bang('!SetVariable', 'EditorActionTypeValue', normalizeActionType(actionType))

        if normalizeActionType(actionType) ~= 'folder' then
            SKIN:Bang('!SetVariable', 'EditorFolderCountSyncValue', '0')
        end



    end



    updateFieldAtLocator(locator, 'Action', resolved, actionType)



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
        or normalizeActionType(record.ActionType) ~= ''
        or normalizeFolderCountSync(record.FolderCountSync, record.ActionType) ~= '0'
    local imageChanged = imageKey ~= "" and record.ImageKey ~= imageKey
    if not pathChanged and not imageChanged then
        return
    end

    local beforeSnapshot = captureDraftSnapshot()
    if pathChanged then
        record.ExecPath = resolvedPath
        record.ActionType = ''
        record.FolderCountSync = '0'
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

        SKIN:Bang('!SetVariable', 'EditorActionTypeValue', '')

        SKIN:Bang('!SetVariable', 'EditorFolderCountSyncValue', '0')



        if imageKey ~= "" then



            setImageKey(imageKey)



        end



    end



    UpdatePickedProgramAtLocator(resolvedPath, imageKey, locator)



end

local function commitQtyForLocator(value, locator)

    local record = getRecordByLocator(locator)
    if record and normalizeFolderCountSync(record.FolderCountSync, record.ActionType) == '1' then
        if shouldMirrorInputToVisibleSelection(locator) and type(RefreshFolderCountSync) == 'function' then
            RefreshFolderCountSync()
        end
        return
    end



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

    if normalizedTarget == 'qty' and record
        and normalizeFolderCountSync(record.FolderCountSync, record.ActionType) == '1' then
        return
    end



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

function CommitPath(value, displayLabel, actionType)



    commitPathForLocator(value, nil, displayLabel, actionType)



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

    record.ActionType = normalizeActionType(SKIN:GetVariable('EditorActionTypeValue', ''))

    record.FolderCountSync = normalizeFolderCountSync(SKIN:GetVariable('EditorFolderCountSyncValue', '0'), record.ActionType)



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

    SKIN:Bang('!CommandMeasure', 'MeasurePathPicker', 'Update()')
    SKIN:Bang('!CommandMeasure', 'MeasureImagePicker', 'Update()')



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

EditorInputCommitPixelBridge = {
    trim = trim,
    normalizeImageAsset = normalizeImageAsset,
    defaultImageKey = DEFAULT_NEW_ITEM_IMAGE,
    playClick = playUiClick,
    hasSelection = hasActiveEditorSelection,
    log = logMessage,
    alert = logEditorErrorAndAlert,
    localize = function(key, fallback)
        return L(key, fallback)
    end,
    languageCode = function()
        return currentLanguageCode()
    end,
    userAlert = function(message)
        local summary = trim(message)
        if summary == '' then
            summary = 'Image pixelation failed.'
        end
        return showEditorModalAlert('error', '', summary)
    end,
    unsupportedAlert = function(message)
        return showEditorModalAlert('warn', '', trim(message))
    end,
    setLoadingVisible = setEditorLoadingVisible,
    commitImageKey = function(imageKey)
        return commitImageKeyForLocator(imageKey, nil)
    end,
    itemImageDirectory = function()
        local paths = ensureService().GetPaths(editorRoot)
        return trim(paths and paths.ItemImageDirectory or '')
    end,
    itemImagePath = function(imageKey)
        return ensureService().GetImagePath(editorRoot, normalizeImageAsset(imageKey))
    end,
}

function SyncEditorPixelationState(imageKey)
    if EditorInputCommitPixelBridge and type(EditorInputCommitPixelBridge.syncPixelationState) == 'function' then
        return EditorInputCommitPixelBridge.syncPixelationState(imageKey)
    end
    return nil
end

function ApplyImagePixelation()
    logMessage('Warning', 'Editor image pixelation module is not loaded.')
    return false
end

function HandleEditorPixelationComplete()
    logMessage('Warning', 'Editor image pixelation completion was ignored because the module is not loaded.')
    return false
end

function CleanupEditorPixelationImagesAfterPersist()
    return false
end

function HandleEditorPixelCleanupComplete()
    logMessage('Warning', 'Editor image pixelation cleanup completion was ignored because the module is not loaded.')
    return false
end

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
    if tonumber(trim(SKIN:GetVariable('EditorPageIndex', '1'))) == 2 and type(RefreshFolderCountSync) == 'function' then
        RefreshFolderCountSync()
    end
    refreshThemeVisuals()
end

function ResumeEditorResident(allowConsumerMirror)
    closeDiscardApplied = false
    closeRequestMode = nil
    closeCommitChanged = false
    ensureResidentUpdateController().ResumeSurface('Editor')
    SKIN:Bang('!CommandMeasure', 'MeasureItemImageAnimator', 'Resume()')
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
    SKIN:Bang('!CommandMeasure', 'MeasureItemImageAnimator', 'Suspend()')
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

function CleanupEditorClosedRuntimeState()
    setEditorVisibleState(false)
    cancelDeferredInitialize()
    setEditorLoadingVisible(false)
    clearPickerRunState('path')
    clearPickerRunState('image')
    SetPickerModalOpen(0)
    clearDragState()
    StopEditorResponsiveLayoutTimer()
    ensureResidentUpdateController().SuspendSurface('Editor')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
    SKIN:Bang('!Redraw')
end

function HandleClose(reason)






    if closeDiscardApplied then
        CleanupEditorClosedRuntimeState()



        return



    end



    if deferredInitRequested then



        cancelDeferredInitialize()



        setEditorLoadingVisible(false)



        discardDraftSession(true)
        CleanupEditorClosedRuntimeState()



        return



    end



    local allowConsumerRefresh = trim(reason) ~= 'rainmeter-close'

    local requestedMode = closeRequestMode



    closeRequestMode = nil



    if requestedMode == 'editor' then



        if tryCommitClose('Editor draft autosaved on close.') and closeCommitChanged and allowConsumerRefresh then

            refreshConsumersAfterEditorClose()



        end


        CleanupEditorClosedRuntimeState()



        return



    end



    if tryCommitClose('Editor draft autosaved on close.') and closeCommitChanged and allowConsumerRefresh then

            refreshConsumersAfterEditorClose()



    end


    CleanupEditorClosedRuntimeState()


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



    ShowEditorSaveLoading()

    local committed = tryCommitClose('Editor draft autosaved on close.')



    closeRequestMode = nil



    if not committed then



        setEditorLoadingVisible(false)

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



    ShowEditorSaveLoading()

    local wasRepaired, repairLogs = normalizeInvalidDraftChanges()



    if wasRepaired then



        for _, repairLog in ipairs(repairLogs) do



            logMessage('Warning', 'Draft auto-repaired before save: ' .. repairLog)



        end



    end



    if not writePersistedFromDraft() then

        setEditorLoadingVisible(false)
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



    setEditorLoadingVisible(false)

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

    SKIN:Bang('!CommandMeasure', 'MeasureItemImageAnimator', 'RefreshBindings()')

    if nextPage == 2 and type(RefreshFolderCountSync) == 'function' then
        RefreshFolderCountSync()
    end



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
