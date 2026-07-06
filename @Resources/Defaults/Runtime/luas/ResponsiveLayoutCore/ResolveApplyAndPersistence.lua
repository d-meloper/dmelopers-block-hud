-- Split from @Resources\Defaults\Runtime\luas\ResponsiveLayoutCore.lua lines 907-1748.
function M.ResolveRects(SKIN)
    local work = effectivePrimaryWorkArea(SKIN)
    local scale = normalizeScale(M.GetScale(SKIN))
    local indicatorUserScale = getIndicatorUserScale(SKIN)
    local rects = {}

    do
        local state = M.GetState(SKIN, 'Hotbar')
        local metrics = getHotbarMetrics(SKIN, scale, indicatorUserScale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Hotbar', state, work, metrics.windowWidth, metrics.windowHeight)
        else
            local visibleCenterX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0)
            local visibleBottomY = work.bottom + scaleNumber(state.OffsetYBase, scale, 0)
            rawX = visibleCenterX - (metrics.visibleLeft + (metrics.hotbarWidth / 2))
            rawY = visibleBottomY - (metrics.visibleTop + metrics.hotbarHeight)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.windowWidth, metrics.windowHeight)
        end
        rects.Hotbar = {
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = scale,
            metrics = metrics,
            visibleLeft = rawX + metrics.visibleLeft,
            visibleTop = rawY + metrics.visibleTop,
            visibleRight = rawX + metrics.visibleLeft + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleTop + metrics.visibleHeight,
            visibleCenterX = rawX + metrics.visibleLeft + (metrics.visibleWidth / 2),
            indicatorAnchorLeft = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) - (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorRight = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) + (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorTop = (rawY + metrics.visibleTop + metrics.visibleHeight) - metrics.indicatorAnchorSlotSize,
        }
    end

    do
        local state = M.GetState(SKIN, 'Inventory')
        local metrics = getInventoryMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Inventory', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0)
            rawY = work.centerY + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Inventory = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
            leftTopX = rawX,
            leftTopY = rawY,
            rightTopX = rawX + metrics.width,
            rightTopY = rawY,
        }
    end

    do
        local rawWork = work.raw or rawPrimaryWorkArea(SKIN)
        local inventoryWork = monitorWorkAreaForRect(SKIN, rects.Inventory, rawWork)
        rects.InventoryBG = {
            x = inventoryWork.x,
            y = inventoryWork.y,
            width = inventoryWork.width,
            height = inventoryWork.height,
            scale = scale,
        }
    end

    do
        local state = M.GetState(SKIN, 'Clock')
        local metrics = getClockMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Clock', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0) - metrics.centerX
            rawY = work.y + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Clock = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    do
        local state = M.GetState(SKIN, 'ClockSprite')
        local metrics = getClockSpriteMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'ClockSprite', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0) - round(metrics.width / 2)
            rawY = work.y + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.ClockSprite = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    do
        local state = M.GetState(SKIN, 'Jukebox')
        local metrics = getJukeboxMetrics(SKIN, scale)
        local width = metrics.width
        local height = metrics.height
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Jukebox', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0) - round(metrics.width / 2)
            rawY = work.centerY + scaleNumber(state.OffsetYBase, scale, 0) - round(metrics.height / 2)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        if M.CurrentSkinId(SKIN) ~= 'Jukebox' then
            local liveState = readLiveState(SKIN, 'Jukebox')
            if liveState and liveState.Active and liveState.WindowX ~= nil and liveState.WindowY ~= nil then
                rawX = round(liveState.WindowX)
                rawY = round(liveState.WindowY)
            end
        end
        rects.Jukebox = {
            x = rawX,
            y = rawY,
            width = width,
            height = height,
            scale = scale,
            metrics = metrics,
            topCenterX = rawX + (width / 2),
            topY = rawY,
        }
    end
    do
        local state = M.GetState(SKIN, 'JukeboxDiscSlot')
        local metrics = getJukeboxDiscSlotMetrics(SKIN, scale)
        local jukebox = rects.Jukebox
        local rawX
        local rawY
        if usesFixedPosition(state) then
            local visibleX
            visibleX, rawY = resolveFixedWindow(SKIN, 'JukeboxDiscSlot', state, work, metrics.visibleWidth, metrics.visibleHeight)
            local gutterWork = monitorWorkAreaForPoint(SKIN, visibleX, rawY, work)
            metrics = resolveJukeboxDiscSlotMetricsForVisibleLeft(metrics, visibleX, gutterWork)
            rawX = visibleX - metrics.contentX
        else
            local clampWork = monitorWorkAreaForPoint(SKIN, jukebox.x, jukebox.y, work)
            local horizontalClampWork = virtualWorkArea(SKIN, clampWork)
            local offsetX = scaleNumber(state.OffsetXBase, scale, 0)
            local offsetY = scaleNumber(state.OffsetYBase, scale, 0)
            local topY = jukebox.y - metrics.height - metrics.gap + offsetY
            local bottomY = jukebox.y + jukebox.height + metrics.gap + offsetY
            local jukeboxAnchorX = jukebox.x + (jukebox.width / 2)
            local rightColumnCenterX = metrics.usableX + ((metrics.usableWidth / 3) * 2.5)
            local visibleSlotX = clampWindowX(horizontalClampWork, jukeboxAnchorX + offsetX - rightColumnCenterX, metrics.visibleWidth)
            metrics = resolveJukeboxDiscSlotMetricsForVisibleLeft(metrics, visibleSlotX, clampWork)
            rawX = visibleSlotX - metrics.contentX
            if fitsWindowY(clampWork, topY, metrics.windowHeight) then
                rawY = round(topY)
            elseif fitsWindowY(clampWork, bottomY, metrics.windowHeight) then
                rawY = round(bottomY)
            else
                rawY = select(2, clampWindow(clampWork, rawX, topY, metrics.windowWidth, metrics.windowHeight))
            end
        end
        rects.JukeboxDiscSlot = {
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = scale,
            metrics = metrics,
            visibleLeft = rawX + metrics.contentX,
            visibleTop = rawY,
            visibleRight = rawX + metrics.contentX + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleHeight,
        }
    end

    do
        local state = M.GetState(SKIN, 'Herobrine')
        local metrics = getHerobrineMetrics(SKIN, scale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Herobrine', state, work, metrics.width, metrics.height)
        else
            rawX = work.centerX + scaleNumber(state.OffsetXBase, scale, 0) - round(metrics.width / 2)
            rawY = work.centerY + scaleNumber(state.OffsetYBase, scale, 0) - round(metrics.height / 2)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Herobrine = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    for _, indicatorId in ipairs({ 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' }) do
        local state = M.GetState(SKIN, indicatorId)
        local metrics = getIndicatorMetrics(indicatorId, scale, indicatorUserScale)
        local hotbar = rects.Hotbar
        local indicatorLayoutScale = resolvedIndicatorScale(scale, indicatorUserScale)
        local edgeInset = indicatorLayoutScale < 1 and round((1 - indicatorLayoutScale) * 10) or 0
        local definition = SKINS[indicatorId] or {}
        local offsetXBase = tonumber(state.OffsetXBase) or tonumber(definition.offsetX) or 0
        local offsetYBase = tonumber(state.OffsetYBase) or tonumber(definition.offsetY) or 0
        local commonIndicatorY = hotbar.indicatorAnchorTop + (offsetYBase * indicatorLayoutScale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, indicatorId, state, work, metrics.width, metrics.height + (metrics.gaugeY or 0))
        else
            if state.AnchorKind == 'HotbarVisibleLeftTop' then
                rawX = hotbar.indicatorAnchorLeft + (offsetXBase * indicatorLayoutScale) + edgeInset
                rawY = commonIndicatorY
            elseif state.AnchorKind == 'HotbarVisibleRightTop' then
                rawX = hotbar.indicatorAnchorRight + (offsetXBase * indicatorLayoutScale) - metrics.width - edgeInset
                rawY = commonIndicatorY
            elseif indicatorId == 'IndicatorExp' then
                local indicatorSpanWidth = hotbar.indicatorAnchorRight - hotbar.indicatorAnchorLeft
                local expBaseline = SKINS.IndicatorExp or {}
                local expBaselineOffsetY = tonumber(expBaseline.offsetY) or -63
                local expGaugeY = tonumber(metrics.gaugeY) or 0
                local expHeight = tonumber(metrics.height) or 1
                local expHotbarTopGap = tonumber(metrics.hotbarTopGap) or 7
                local expYOffsetDelta = (offsetYBase - expBaselineOffsetY) * indicatorLayoutScale
                rawX = hotbar.indicatorAnchorLeft + ((indicatorSpanWidth - metrics.width) / 2) + (offsetXBase * indicatorLayoutScale)
                rawY = hotbar.indicatorAnchorTop - expGaugeY - expHeight - expHotbarTopGap + expYOffsetDelta
            else
                rawX = hotbar.visibleCenterX + (offsetXBase * indicatorLayoutScale) - (metrics.width / 2)
                rawY = commonIndicatorY
            end
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height + (metrics.gaugeY or 0))
        end
        rects[indicatorId] = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    for _, panelId in ipairs({ 'Settings', 'Editor' }) do
        local state = M.GetState(SKIN, panelId)
        local metrics = getPanelMetrics(panelId, scale)
        local inventory = rects.Inventory
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, panelId, state, work, metrics.width, metrics.height)
        else
            if state.AnchorKind == 'InventoryLeftTop' then
                rawX = inventory.leftTopX + scaleNumber(state.OffsetXBase, scale, 0)
            else
                rawX = inventory.rightTopX + scaleNumber(state.OffsetXBase, scale, 0)
            end
            rawY = inventory.leftTopY + scaleNumber(state.OffsetYBase, scale, 0)
            rawX, rawY = clampWindow(work, rawX, rawY, metrics.width, metrics.height)
        end
        rects[panelId] = {
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = scale,
            metrics = metrics,
        }
    end

    rects.PrimaryWorkArea = work
    rects.Scale = scale
    return rects
end

function M.ResolveGridLayout(SKIN, source)
    local rects = M.ResolveRects(SKIN)
    if source == 'hotbar' then
        local hotbar = rects.Hotbar
        return {
            source = 'hotbar',
            x = hotbar.visibleLeft,
            y = hotbar.visibleTop,
            slotSize = hotbar.metrics.slotSize,
        }
    end
    if source == 'inventory' then
        local inventory = rects.Inventory
        return {
            source = 'inventory',
            x = inventory.x + inventory.metrics.gridOffsetX,
            y = inventory.y + inventory.metrics.gridOffsetY,
            slotSize = inventory.metrics.slotSize,
        }
    end
    return nil
end

function M.ResolveRelativeGridLayout(SKIN, source)
    local layout = M.ResolveGridLayout(SKIN, source)
    if not layout then
        return nil
    end
    local currentX = toNumber(SKIN, 'CURRENTCONFIGX', 0)
    local currentY = toNumber(SKIN, 'CURRENTCONFIGY', 0)
    return {
        source = layout.source,
        x = layout.x - currentX,
        y = layout.y - currentY,
        slotSize = layout.slotSize,
    }
end

local function applyWindowMove(SKIN, id, rect)
    local definition = SKINS[id]
    if not definition or not rect then
        return
    end
    SKIN:Bang('!Move', tostring(round(rect.x)), tostring(round(rect.y)), getRootConfig(SKIN) .. '\\' .. definition.config)
end

local function applyHotbarVars(SKIN, rect)
    local metrics = rect.metrics
    setVariableForConfig(SKIN, 'HotbarSlotSize', metrics.slotSize)
    setVariableForConfig(SKIN, 'HotbarTextYOffset', metrics.textYOffset)
    setVariableForConfig(SKIN, 'HotbarTextFontSize', metrics.textFontSize)
    setVariableForConfig(SKIN, 'HotbarItemSizeOffset', metrics.itemOffset)
end

local function applyInventoryVars(SKIN, rect)
    local m = rect.metrics
    for name, value in pairs({
        InventoryWidth = m.width,
        InventoryHeight = m.height,
        InventorySlotSize = m.slotSize,
        SlotSize = m.slotSize,
        InventoryGridOffsetX = m.gridOffsetX,
        InventoryGridOffsetY = m.gridOffsetY,
        InvOffsetX = m.gridOffsetX,
        InvOffsetY = m.gridOffsetY,
        InventoryItemSize = m.itemSize,
        TooltipTextFontSize = m.tooltipFontSize,
        PlayerOffsetX = m.playerOffsetX,
        PlayerOffsetY = m.playerOffsetY,
        PlayerWidth = m.playerWidth,
        PlayerHeight = m.playerHeight,
        PlayerCustomOffsetX = m.playerCustomOffsetX,
        PlayerCustomOffsetY = m.playerCustomOffsetY,
        PlayerCustomWidth = m.playerCustomWidth,
        PlayerCustomHeight = m.playerCustomHeight,
        SettingsButtonX = m.settingsButtonX,
        SettingsButtonY = m.settingsButtonY,
        SettingsButtonW = m.settingsButtonW,
        SettingsButtonH = m.settingsButtonH,
        OptionY = m.optionY,
        UsageGuideX = m.usageGuideX,
        UsageGuideY = m.usageGuideY,
        UsageGuideW = m.usageGuideW,
        UsageGuideH = m.usageGuideH,
        SteveSkinEditButtonX = m.steveSkinEditButtonX,
        SteveSkinEditButtonY = m.steveSkinEditButtonY,
        SteveSkinEditButtonW = m.steveSkinEditButtonW,
        SteveSkinEditButtonH = m.steveSkinEditButtonH,
        SkinFolderX = m.skinFolderX,
        SkinFolderY = m.skinFolderY,
        SkinFolderW = m.skinFolderW,
        SkinFolderH = m.skinFolderH,
        WorkProgressButtonX = m.workProgressButtonX,
        WorkProgressButtonY = m.workProgressButtonY,
        WorkProgressButtonW = m.workProgressButtonW,
        WorkProgressButtonH = m.workProgressButtonH,
        WorkProgressHidden = m.workProgressEnabled and 0 or 1,
        RefreshButtonX = m.refreshButtonX,
        RefreshButtonY = m.refreshButtonY,
        RefreshButtonW = m.refreshButtonW,
        RefreshButtonH = m.refreshButtonH,
        EditButtonX = m.editButtonX,
        EditButtonY = m.editButtonY,
        EditButtonW = m.editButtonW,
        EditButtonH = m.editButtonH,
        InventoryCloseButtonX = m.inventoryCloseButtonX,
        InventoryCloseButtonY = m.inventoryCloseButtonY,
        InventoryCloseButtonW = m.inventoryCloseButtonW,
        InventoryCloseButtonH = m.inventoryCloseButtonH,
        EditorModeBadgeW = m.badgeW,
        EditorModeBadgeH = m.badgeH,
        EditorModeBadgeY = m.badgeY,
        EditorModeBadgeFontSize = m.badgeFontSize,
        EditorModeBadgeX = round((m.width - m.badgeW) / 2),
        EditorModeBadgeLabelX = round((m.width - m.badgeW) / 2) + round(m.badgeW / 2),
        EditorModeBadgeLabelY = m.badgeY + round(m.badgeH / 2),
        InventoryRowExtraGap = m.rowExtraGap,
    }) do
        setVariableForConfig(SKIN, name, value)
    end
end

local function setMeterOption(SKIN, meterName, optionName, value)
    SKIN:Bang('!SetOption', meterName, optionName, tostring(value))
end

local function syncSelectedHighlight(SKIN)
    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()')
end

local function applyClockVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'ClockCenterX', m.centerX)
    setVariableForConfig(SKIN, 'ClockTimeTextSize', m.timeSize)
    setVariableForConfig(SKIN, 'ClockDateTextSize', m.dateSize)
    setVariableForConfig(SKIN, 'ClockTextGap', m.textGap)
end

local function applyClockSpriteVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'ClockSpriteRenderSize', m.size)
    SKIN:Bang('!UpdateMeter', 'MeterClockSprite')
end

local function applyJukeboxVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'JukeboxW', m.width)
    setVariableForConfig(SKIN, 'JukeboxH', m.height)
    setMeterOption(SKIN, 'MeterJukebox', 'W', m.width)
    setMeterOption(SKIN, 'MeterJukebox', 'H', m.height)
    setMeterOption(SKIN, 'MeterJukeboxAnimator', 'W', m.width)
    setMeterOption(SKIN, 'MeterJukeboxAnimator', 'H', m.height)
    SKIN:Bang('!UpdateMeter', 'MeterJukebox')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxAnimator')
end
local function applyJukeboxDiscSlotVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'JukeboxDiscSlotW', m.visibleWidth)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotH', m.visibleHeight)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotContentX', m.contentX)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotOutline', m.outline)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableX', m.usableX)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableY', m.usableY)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableW', m.usableWidth)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotUsableH', m.usableHeight)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotGap', m.gap)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotActionSide', m.actionSide)
    setVariableForConfig(SKIN, 'JukeboxDiscSlotActionGutter', m.actionGutter)
    setMeterOption(SKIN, 'MeterJukeboxDiscSlot', 'W', m.visibleWidth)
    setMeterOption(SKIN, 'MeterJukeboxDiscSlot', 'H', m.visibleHeight)
    SKIN:Bang('!UpdateMeterGroup', 'JukeboxDiscSlot')
end


local function applyHerobrineVars(SKIN, rect)
    local m = rect.metrics
    setVariableForConfig(SKIN, 'HerobrineApparitionRenderW', m.width)
    setVariableForConfig(SKIN, 'HerobrineApparitionRenderH', m.height)
    setVariableForConfig(SKIN, 'HerobrineApparitionMargin', m.margin)
    SKIN:Bang('!SetOption', 'MeterHerobrineApparition', 'W', tostring(m.width))
    SKIN:Bang('!SetOption', 'MeterHerobrineApparition', 'H', tostring(m.height))
    SKIN:Bang('!UpdateMeter', 'MeterHerobrineApparition')
    SKIN:Bang('!CommandMeasure', 'MeasureHerobrine', 'ReflowApparition()')
end

local function applyIndicatorVars(SKIN, id, rect)
    local m = rect.metrics
    if id == 'IndicatorExp' then
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
        setVariableForConfig(SKIN, 'ExpGaugeY', m.gaugeY)
        setVariableForConfig(SKIN, 'ExpTextX', m.textX)
        setVariableForConfig(SKIN, 'ExpTextY', m.textY)
        setVariableForConfig(SKIN, 'ExpTextFontSize', m.textFontSize)
    else
        setVariableForConfig(SKIN, 'DEFAULT_SIZE_RATIO', m.sizeRatio)
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
    end
end

function M.ApplyCurrentSkin(SKIN)
    local id = M.CurrentSkinId(SKIN)
    if not id then
        return nil
    end
    local rects = M.ResolveRects(SKIN)
    local rect = rects[id]
    if not rect then
        return nil
    end

    if id == 'Hotbar' then
        applyHotbarVars(SKIN, rect)
        SKIN:Bang('!CommandMeasure', 'MeasureHotbarLayout', 'ApplyLayout()')
        syncSelectedHighlight(SKIN)
    elseif id == 'Inventory' then
        applyInventoryVars(SKIN, rect)
        setMeterOption(SKIN, 'MeterInventory', 'W', rect.metrics.width)
        setMeterOption(SKIN, 'MeterInventory', 'H', rect.metrics.height)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'X', rect.metrics.settingsButtonX)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'Y', rect.metrics.settingsButtonY)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'W', rect.metrics.settingsButtonW)
        setMeterOption(SKIN, 'MeterSettingsUIButton', 'H', rect.metrics.settingsButtonH)
        setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'Hidden', rect.metrics.workProgressEnabled and 0 or 1)
        if rect.metrics.workProgressEnabled then
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'X', rect.metrics.workProgressButtonX)
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'Y', rect.metrics.workProgressButtonY)
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'W', rect.metrics.workProgressButtonW)
            setMeterOption(SKIN, 'MeterWorkProgressUIButton', 'H', rect.metrics.workProgressButtonH)
        end
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'X', rect.metrics.refreshButtonX)
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'Y', rect.metrics.refreshButtonY)
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'W', rect.metrics.refreshButtonW)
        setMeterOption(SKIN, 'MeterRefreshUIButton', 'H', rect.metrics.refreshButtonH)
        setMeterOption(SKIN, 'MeterOpenInfo', 'X', rect.metrics.usageGuideX)
        setMeterOption(SKIN, 'MeterOpenInfo', 'Y', rect.metrics.usageGuideY)
        setMeterOption(SKIN, 'MeterOpenInfo', 'W', rect.metrics.usageGuideW)
        setMeterOption(SKIN, 'MeterOpenInfo', 'H', rect.metrics.usageGuideH)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'X', rect.metrics.steveSkinEditButtonX)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'Y', rect.metrics.steveSkinEditButtonY)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'W', rect.metrics.steveSkinEditButtonW)
        setMeterOption(SKIN, 'MeterSteveSkinEditButton', 'H', rect.metrics.steveSkinEditButtonH)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'X', rect.metrics.skinFolderX)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'Y', rect.metrics.skinFolderY)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'W', rect.metrics.skinFolderW)
        setMeterOption(SKIN, 'MeterOpenSkinFolder', 'H', rect.metrics.skinFolderH)
        setMeterOption(SKIN, 'MeterEdit', 'X', rect.metrics.editButtonX)
        setMeterOption(SKIN, 'MeterEdit', 'Y', rect.metrics.editButtonY)
        setMeterOption(SKIN, 'MeterEdit', 'W', rect.metrics.editButtonW)
        setMeterOption(SKIN, 'MeterEdit', 'H', rect.metrics.editButtonH)
        setMeterOption(SKIN, 'MeterInventoryClose', 'X', rect.metrics.inventoryCloseButtonX)
        setMeterOption(SKIN, 'MeterInventoryClose', 'Y', rect.metrics.inventoryCloseButtonY)
        setMeterOption(SKIN, 'MeterInventoryClose', 'W', rect.metrics.inventoryCloseButtonW)
        setMeterOption(SKIN, 'MeterInventoryClose', 'H', rect.metrics.inventoryCloseButtonH)
        setMeterOption(SKIN, 'MeterEditorModeBadgeBackground', 'X', round((rect.metrics.width - rect.metrics.badgeW) / 2))
        setMeterOption(SKIN, 'MeterEditorModeBadgeBackground', 'Y', rect.metrics.badgeY)
        setMeterOption(SKIN, 'MeterEditorModeBadgeLabel', 'X', round((rect.metrics.width - rect.metrics.badgeW) / 2) + round(rect.metrics.badgeW / 2))
        setMeterOption(SKIN, 'MeterEditorModeBadgeLabel', 'Y', rect.metrics.badgeY + round(rect.metrics.badgeH / 2))
        setMeterOption(SKIN, 'MeterEditorModeBadgeLabel', 'FontSize', rect.metrics.badgeFontSize)
        for _, meterName in ipairs({
            'MeterInventory',
            'MeterPlayerDefault',
            'MeterPlayerCustom',
            'MeterSettingsUIButton',
            'MeterRefreshUIButton',
            'MeterOpenInfo',
            'MeterSteveSkinEditButton',
            'MeterOpenSkinFolder',
            'MeterEdit',
            'MeterInventoryClose',
            'MeterEditorModeBadgeBackground',
            'MeterEditorModeBadgeLabel',
        }) do
            SKIN:Bang('!UpdateMeter', meterName)
        end
        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()')
        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()')
        syncSelectedHighlight(SKIN)
    elseif id == 'Clock' then
        applyClockVars(SKIN, rect)
    elseif id == 'ClockSprite' then
        applyClockSpriteVars(SKIN, rect)
    elseif id == 'Jukebox' then
        applyJukeboxVars(SKIN, rect)
    elseif id == 'JukeboxDiscSlot' then
        applyJukeboxDiscSlotVars(SKIN, rect)
    elseif id == 'Herobrine' then
        applyHerobrineVars(SKIN, rect)
    elseif id:find('^Indicator') then
        applyIndicatorVars(SKIN, id, rect)
    elseif id == 'InventoryBG' then
        setVariableForConfig(SKIN, 'InventoryBGWidth', rect.width)
        setVariableForConfig(SKIN, 'InventoryBGHeight', rect.height)
        SKIN:Bang('!UpdateMeter', 'MeterBackground')
        SKIN:Bang('!Redraw')
    end

    if id ~= 'Herobrine' then
        applyWindowMove(SKIN, id, rect)
        syncRainmeterWindowPosition(SKIN, id, rect.x, rect.y, true)
    end

    return {
        id = id,
        x = round(rect.x),
        y = round(rect.y),
        width = round(rect.width),
        height = round(rect.height),
        rects = rects,
    }
end

function M.ReflowTargets(SKIN, ids, options)
    local rootConfig = getRootConfig(SKIN)
    if rootConfig == '' then
        return
    end
    local currentId = M.CurrentSkinId(SKIN)
    local forceRefresh = options == true or (type(options) == 'table' and options.forceRefresh == true)
    for _, id in ipairs(ids or {}) do
        local definition = SKINS[id]
        if definition and (forceRefresh or id == currentId or M.IsSkinActive(SKIN, id)) then
            SKIN:Bang('!Refresh', rootConfig .. '\\' .. definition.config, definition.file)
        end
    end
end  local function normalizedStateTargetIds(ids)
    local targets = {}
    local seen = {}
    for _, id in ipairs(ids or {}) do
        if id ~= 'InventoryBG' and SKINS[id] and not seen[id] then
            targets[#targets + 1] = id
            seen[id] = true
        end
    end
    return targets
end

function M.SetPositionModeForIds(SKIN, ids, mode)
    local resolvedMode = normalizePositionMode(mode)
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        if state then
            state.PositionMode = resolvedMode
            M.WriteState(SKIN, id, state, true)
        end
    end
end

function M.ClearFixedPositionsForIds(SKIN, ids)
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        if state then
            state.FixedX = '0'
            state.FixedY = '0'
            M.WriteState(SKIN, id, state, true)
        end
    end
end
function M.SetFixedPosition(SKIN, id, x, y)
    if not id or id == 'InventoryBG' or not SKINS[id] then
        return false
    end
    local state = M.GetState(SKIN, id)
    if not state then
        return false
    end
    state.PositionMode = 'fixed'
    state.FixedX = tostring(round(tonumber(x) or 0))
    state.FixedY = tostring(round(tonumber(y) or 0))
    M.WriteState(SKIN, id, state, true)
    return true
end

function M.CaptureFixedPositionsForIds(SKIN, ids, positionsById)
    positionsById = positionsById or {}
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        local position = positionsById[id]
        if state and position then
            state.FixedX = tostring(round(tonumber(position.x) or 0))
            state.FixedY = tostring(round(tonumber(position.y) or 0))
            state.PositionMode = 'fixed'
            M.WriteState(SKIN, id, state, true)
        end
    end
end

function M.ResolveInventoryLiveWindowPosition(SKIN)     local rects = M.ResolveRects(SKIN)     local inventory = rects and rects.Inventory     if not inventory then         return nil     end     return { x = round(inventory.x), y = round(inventory.y) } end  function M.LiveWindowPositionForId(SKIN, id, fallbackRects)
    if not SKINS[id] then
        return nil
    end
    local function visiblePosition(position)
        if id ~= 'JukeboxDiscSlot' or not position then
            return position
        end
        local metrics = getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
        local gutter = nil
        if tonumber(position.width) then
            gutter = math.max(0, round((tonumber(position.width) or 0) - metrics.visibleWidth))
        end
        if gutter == nil then
            gutter = tonumber(trim(SKIN:GetVariable('JukeboxDiscSlotContentX', '')))
        end
        if gutter == nil then
            gutter = metrics.tooltipLeftGutter
        end
        gutter = clamp(gutter, 0, metrics.tooltipLeftGutterMax or metrics.tooltipLeftGutter)
        return {
            x = round((tonumber(position.x) or 0) + gutter),
            y = round(tonumber(position.y) or 0),
        }
    end
    local sameSkinPosition = sameSkinCurrentWindowPosition(SKIN, id)
    if sameSkinPosition then
        return visiblePosition(sameSkinPosition)
    end
    local liveState = readLiveState(SKIN, id)
    if liveState and liveState.Active then
        if liveState.WindowX ~= nil and liveState.WindowY ~= nil then
            return visiblePosition({ x = liveState.WindowX, y = liveState.WindowY, width = liveState.Width })
        end
        return nil
    end
    local fallback = fallbackRects and fallbackRects[id]
    if fallback then
        if id == 'JukeboxDiscSlot' and fallback.visibleLeft ~= nil then
            return { x = fallback.visibleLeft, y = fallback.y }
        end
        return { x = fallback.x, y = fallback.y }
    end
    return nil
end

local function roundedWindowPosition(x, y)
    local numericX = tonumber(x)
    local numericY = tonumber(y)
    if numericX == nil or numericY == nil then
        return nil
    end
    return {
        x = round(numericX),
        y = round(numericY),
    }
end

local function resolvePositionForPersistence(SKIN, id, x, y, fallbackRects)
    local livePosition = M.LiveWindowPositionForId(SKIN, id, nil)
    if livePosition then
        return {
            x = round(tonumber(livePosition.x) or 0),
            y = round(tonumber(livePosition.y) or 0),
        }
    end
    local explicitPosition = roundedWindowPosition(x, y)
    if explicitPosition then
        return explicitPosition
    end
    local fallback = fallbackRects and fallbackRects[id]
    if fallback then
        return {
            x = round(tonumber(fallback.x) or 0),
            y = round(tonumber(fallback.y) or 0),
        }
    end
    return nil
end

local function sameRoundedPosition(left, right)
    if not left or not right then
        return false
    end
    return round(tonumber(left.x) or 0) == round(tonumber(right.x) or 0)
        and round(tonumber(left.y) or 0) == round(tonumber(right.y) or 0)
end

function M.ApplyPositionFixedState(SKIN, ids, isFixed)
    local targetIds = normalizedStateTargetIds(ids)
    if #targetIds == 0 then
        return
    end
    if not isFixed then
        M.SetPositionModeForIds(SKIN, targetIds, 'auto')
        M.ClearFixedPositionsForIds(SKIN, targetIds)
        M.ReflowTargets(SKIN, targetIds)
        return
    end

    local rects = M.ResolveRects(SKIN)
    local positionsById = {}
    for _, id in ipairs(targetIds) do
        local position = M.LiveWindowPositionForId(SKIN, id, rects)
        if position then
            positionsById[id] = position
        end
    end
    M.CaptureFixedPositionsForIds(SKIN, targetIds, positionsById)
    M.SetPositionModeForIds(SKIN, targetIds, 'fixed')
    M.ReflowTargets(SKIN, targetIds)
end

function M.PersistCurrentFixedPosition(SKIN, id, x, y)
    if not id or id == 'InventoryBG' or not SKINS[id] then
        return false
    end
    local state = M.GetState(SKIN, id)
    if not state then
        return false
    end

    local mode = normalizePositionMode(state.PositionMode)
    local fallbackRects = nil
    local position = resolvePositionForPersistence(SKIN, id, x, y, nil)
    if not position or mode ~= 'fixed' then
        fallbackRects = M.ResolveRects(SKIN)
        if not position then
            position = resolvePositionForPersistence(SKIN, id, x, y, fallbackRects)
        end
    end
    if not position then
        return false
    end

    if mode ~= 'fixed' then
        local fallback = fallbackRects and fallbackRects[id]
        if sameRoundedPosition(position, fallback) then
            return false
        end
    end

    local roundedX = tostring(position.x)
    local roundedY = tostring(position.y)
    if mode == 'fixed' and tostring(state.FixedX or '') == roundedX and tostring(state.FixedY or '') == roundedY then
        return false
    end

    state.PositionMode = 'fixed'
    state.FixedX = roundedX
    state.FixedY = roundedY
    M.WriteState(SKIN, id, state, true)
    return true
end

function M.CaptureCurrentSkinState(SKIN)     local id = M.CurrentSkinId(SKIN)     if not id then         return nil     end     return M.GetState(SKIN, id) end  return M
