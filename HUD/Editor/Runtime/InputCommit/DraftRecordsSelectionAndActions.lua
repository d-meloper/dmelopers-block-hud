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



        Populated = false,



    }



end



local function writeRecordToPath(path, prefix, record)



    writeItemField(path, prefix, record.Section, 'Image', record.ImageKey or '')



    writeItemField(path, prefix, record.Section, 'Label', record.ItemName or '')



    writeItemField(path, prefix, record.Section, 'Action', record.ExecPath or '')



    writeItemField(path, prefix, record.Section, 'Qty', tostring(record.Qty or 0))

    writeItemField(path, prefix, record.Section, 'ConfirmBeforeRun', normalizeConfirmBeforeRun(record.ConfirmBeforeRun))



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

        }

    end

    writeRecordToPath(service.GetPaths(editorRoot).Draft, 'EditorDraftItem', record)

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Image', record.ImageKey or '')

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Label', record.ItemName or '')

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Action', record.ExecPath or '')

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_Qty', tostring(record.Qty or 0))

    mirrorConsumerVariable('EditorDraftItem_' .. record.Section .. '_ConfirmBeforeRun', normalizeConfirmBeforeRun(record.ConfirmBeforeRun))

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
        EditorLocalizationTextFit = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\LocalizationTextFit.lua')
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

function ApplyEditorTextFit(meterName, locKey, text, baseFontVariable, widthVariable)
    local helper = EnsureEditorLocalizationTextFit()
    if not helper or not helper.ApplyMeterTextFit then
        return
    end
    helper.ApplyMeterTextFit(SKIN, meterName, text, {
        locKey = locKey,
        baseFontSize = EditorTextFitNumericVariable(baseFontVariable, 10) or 10,
        widthPx = EditorTextFitNumericVariable(widthVariable, 0) or 0,
        minScale = 0.70,
        probeMeterName = 'MeterEditorTextFitProbe',
        setText = false,
        update = false,
    })
end

local function applyEditorStaticTextFitTarget(target)
    if not target then
        return
    end
    local text = target.text or ('#Loc_' .. target.key .. '#')
    ApplyEditorTextFit(
        target.meter,
        target.key or '',
        text,
        target.base,
        target.width
    )
end

function ApplyEditorStaticLocalizationTextFits()
    local targets = {
        { meter = 'MeterViewerLoadButtonLabel', key = 'Editor_LoadButton', base = 'ViewerLoadButtonFontSize', width = 'ViewerLoadButtonW' },
        { meter = 'MeterEditorLoadingLabelLine1', key = 'Editor_Loading_Line1', text = '#EditorLoadingTextLine1#', base = 'EditorUIFontSize', width = 'PanelWidth' },
        { meter = 'MeterEditorLoadingLabelLine2', key = 'Editor_Loading_Line2', text = '#EditorLoadingTextLine2#', base = 'EditorUIFontSize', width = 'PanelWidth' },
        { meter = 'MeterEditorNoSelectionMessage', key = 'Editor_NoSelection', base = 12, width = 'EditorNoSelectionMessageW' },
        { meter = 'MeterTopBarResetButtonLabel', key = 'Settings_Notice_Clear', base = 'EditorUIFontSize', width = 'ActionReset_W' },
        { meter = 'MeterSlotFormTitle', key = 'Editor_FormTitle', base = 'LabeledInputTitleFontSize', width = 'SlotFormTitle_W' },
        { meter = 'MeterSlotPathTitle', key = 'Editor_PathTitle', base = 'LabeledInputTitleFontSize', width = 'SlotPathTitle_W' },
        { meter = 'MeterRunConfirmToggleTitle', key = 'Editor_RunConfirmToggleTitle', base = 12, width = 'EditorRunConfirmToggleTitle_W' },
        { meter = 'MeterLabeledInputGroupTitle', key = 'Editor_PositionGroupTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInputGroupTitle_W' },
        { meter = 'MeterLabeledInputTitle', key = 'Editor_XTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInputTitle_W' },
        { meter = 'MeterLabeledInput2Title', key = 'Editor_YTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInput2Title_W' },
        { meter = 'MeterLabeledInput3Title', key = 'Editor_QtyTitle', base = 'LabeledInputTitleFontSize', width = 'SlotLabeledInput3Title_W' },
        { meter = 'MeterImageAdjustGroupTitle', key = 'Editor_ImageAdjustGroupTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjustGroupTitle_W' },
        { meter = 'MeterImageAdjustTitle', key = 'Editor_XTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjustTitle_W' },
        { meter = 'MeterImageAdjust2Title', key = 'Editor_YTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjust2Title_W' },
        { meter = 'MeterImageAdjust3Title', key = 'Editor_ImageAdjustSizeTitle', base = 'LabeledInputTitleFontSize', width = 'SlotImageAdjust3Title_W' },
    }
    for _, target in ipairs(targets) do
        applyEditorStaticTextFitTarget(target)
    end
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
    ApplyEditorTextFit('MeterItemActionPrimaryLabel', primaryLabelKey, '#Loc_' .. primaryLabelKey .. '#', 'EditorUIFontSize', 'ItemActionPrimaryW')



    setActionVariable('ActionItemPrimary_Hidden', primaryHidden)



    applyActionContract('ActionItemPrimary', primaryEnabled, primaryCommand, '#Loc_' .. primaryTooltipKey .. '#', primaryBgColor, primaryTextColor)



    setActionVariable('ActionItemCancelDelete_Hidden', cancelHidden)



    applyActionContract('ActionItemCancelDelete', cancelEnabled, cancelCommand, '#Loc_Editor_Action_DeleteCancel#', cancelBgColor, cancelTextColor)
    ApplyEditorTextFit('MeterItemActionCancelLabel', 'Editor_Action_DeleteCancel', '#Loc_Editor_Action_DeleteCancel#', 'EditorUIFontSize', 'ItemActionCancelW')



    setActionVariable('ActionItemConfirmDelete_Hidden', confirmHidden)



    applyActionContract('ActionItemConfirmDelete', confirmEnabled, confirmCommand, '#Loc_Editor_Action_DeleteTooltip#', confirmBgColor, confirmTextColor)
    ApplyEditorTextFit('MeterItemActionConfirmLabel', 'Editor_Action_DeleteConfirm', '#Loc_Editor_Action_DeleteConfirm#', 'EditorUIFontSize', 'ItemActionConfirmW')



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
