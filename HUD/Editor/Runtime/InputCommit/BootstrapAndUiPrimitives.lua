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
