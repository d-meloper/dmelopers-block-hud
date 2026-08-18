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
