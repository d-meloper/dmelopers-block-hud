-- Split from @Resources\Defaults\Runtime\luas\ResponsiveLayoutCore.lua lines 907-1748.
local function resolveIndependentIndicatorAnchorHotbar(SKIN, snapshot, indicatorUserScale, forcedMonitor)
    local state = resolveBaselineState(SKIN, 'Hotbar') or M.BaselineState('Hotbar')
    if not state then
        return nil
    end

    -- Indicators share the default HUD alignment, not the canonical Hotbar's
    -- live / fixed position. This keeps their auto placement stable across a
    -- Hotbar drag and the following independent config refresh.
    state.PositionMode = 'auto'
    state.FixedX = '0'
    state.FixedY = '0'
    state.MonitorFingerprint = ''
    state.MonitorRelativeX = ''
    state.MonitorRelativeY = ''

    local context, metrics = resolveLayoutContext(snapshot, 'Hotbar', state, nil, function(targetScale)
        return getHotbarMetrics(SKIN, targetScale, indicatorUserScale)
    end, false, forcedMonitor)
    local targetWork = context.work
    local targetScale = context.scale
    local visibleCenterX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0)
    local visibleBottomY = targetWork.bottom + scaleNumber(state.OffsetYBase, targetScale, 0)
    local rawX = visibleCenterX - (metrics.visibleLeft + (metrics.hotbarWidth / 2))
    local rawY = visibleBottomY - (metrics.visibleTop + metrics.hotbarHeight)
    rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.windowWidth, metrics.windowHeight)

    return attachMonitorContext({
        x = rawX,
        y = rawY,
        width = metrics.windowWidth,
        height = metrics.windowHeight,
        scale = targetScale,
        metrics = metrics,
        visibleLeft = rawX + metrics.visibleLeft,
        visibleTop = rawY + metrics.visibleTop,
        visibleRight = rawX + metrics.visibleLeft + metrics.visibleWidth,
        visibleBottom = rawY + metrics.visibleTop + metrics.visibleHeight,
        visibleCenterX = rawX + metrics.visibleLeft + (metrics.visibleWidth / 2),
        indicatorAnchorLeft = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) - (metrics.indicatorAnchorWidth / 2),
        indicatorAnchorRight = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) + (metrics.indicatorAnchorWidth / 2),
        indicatorAnchorTop = (rawY + metrics.visibleTop + metrics.visibleHeight) - metrics.indicatorAnchorSlotSize,
    }, context)
end

function M.ResolveRects(SKIN, snapshot, ownerRectOverrides, forcedMonitors, stateOverrides)
    snapshot = snapshot or M.SnapshotMonitors(SKIN)
    local work = snapshot.primary.work
    local scale = normalizeScale(snapshot.primary.scale)
    local indicatorUserScale = getIndicatorUserScale(SKIN)
    local rects = {}
    local function forcedMonitor(id)
        if type(forcedMonitors) ~= 'table' then
            return nil
        end
        return forcedMonitors[id]
    end
    local function resolvedState(id)
        local state = M.GetState(SKIN, id)
        local overrides = type(stateOverrides) == 'table' and stateOverrides[id] or nil
        if not state or type(overrides) ~= 'table' then
            return state
        end
        local result = {}
        for key, value in pairs(state) do
            result[key] = value
        end
        for key, value in pairs(overrides) do
            result[key] = value
        end
        return result
    end

    do
        local state = resolvedState('Hotbar')
        local context, metrics = resolveLayoutContext(snapshot, 'Hotbar', state, nil, function(targetScale)
            return getHotbarMetrics(SKIN, targetScale, indicatorUserScale)
        end, false, forcedMonitor('Hotbar'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Hotbar', state, targetWork, metrics.windowWidth, metrics.windowHeight, context)
        else
            local visibleCenterX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0)
            local visibleBottomY = targetWork.bottom + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX = visibleCenterX - (metrics.visibleLeft + (metrics.hotbarWidth / 2))
            rawY = visibleBottomY - (metrics.visibleTop + metrics.hotbarHeight)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.windowWidth, metrics.windowHeight)
        end
        local liveState = not forcedMonitor('Hotbar') and M.CurrentSkinId(SKIN) ~= 'Hotbar' and readLiveState(SKIN, 'Hotbar') or nil
        if canFollowLiveOwner(SKIN, 'Hotbar', liveState, snapshot) then
            local liveFallbackActive = context.fallbackActive
            rawX = round(liveState.WindowX)
            rawY = round(liveState.WindowY)
            context = contextForLiveRect(snapshot, buildRect(
                rawX,
                rawY,
                liveState.Width or metrics.windowWidth,
                liveState.Height or metrics.windowHeight
            ))
            context.fallbackActive = liveFallbackActive
            metrics = getHotbarMetrics(SKIN, context.scale, indicatorUserScale)
            targetScale = context.scale
        end
        rects.Hotbar = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = targetScale,
            metrics = metrics,
            visibleLeft = rawX + metrics.visibleLeft,
            visibleTop = rawY + metrics.visibleTop,
            visibleRight = rawX + metrics.visibleLeft + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleTop + metrics.visibleHeight,
            visibleCenterX = rawX + metrics.visibleLeft + (metrics.visibleWidth / 2),
            indicatorAnchorLeft = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) - (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorRight = (rawX + metrics.visibleLeft + (metrics.visibleWidth / 2)) + (metrics.indicatorAnchorWidth / 2),
            indicatorAnchorTop = (rawY + metrics.visibleTop + metrics.visibleHeight) - metrics.indicatorAnchorSlotSize,
        }, context)
    end

    do
        local state = resolvedState('Inventory')
        local context, metrics = resolveLayoutContext(snapshot, 'Inventory', state, nil, function(targetScale)
            return getInventoryMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Inventory'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Inventory', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0)
            rawY = targetWork.centerY + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        local liveState = not forcedMonitor('Inventory') and M.CurrentSkinId(SKIN) ~= 'Inventory' and readLiveState(SKIN, 'Inventory') or nil
        if canFollowLiveOwner(SKIN, 'Inventory', liveState, snapshot) then
            local liveFallbackActive = context.fallbackActive
            rawX = round(liveState.WindowX)
            rawY = round(liveState.WindowY)
            context = contextForLiveRect(snapshot, buildRect(
                rawX,
                rawY,
                liveState.Width or metrics.width,
                liveState.Height or metrics.height
            ))
            context.fallbackActive = liveFallbackActive
            metrics = getInventoryMetrics(SKIN, context.scale)
            targetScale = context.scale
        end
        rects.Inventory = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
            leftTopX = rawX,
            leftTopY = rawY,
            rightTopX = rawX + metrics.width,
            rightTopY = rawY,
        }, context)
    end

    do
        local inventoryContext = contextForMonitor(rects.Inventory.monitor, 'owner', rects.Inventory.fallbackActive, nil)
        local inventoryWork = inventoryContext.rawWork
        rects.InventoryBG = attachMonitorContext({
            x = inventoryWork.x,
            y = inventoryWork.y,
            width = inventoryWork.width,
            height = inventoryWork.height,
            scale = rects.Inventory.scale,
        }, inventoryContext)
    end

    do
        local state = resolvedState('Clock')
        local context, metrics = resolveLayoutContext(snapshot, 'Clock', state, nil, function(targetScale)
            return getClockMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Clock'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Clock', state, targetWork, metrics.width, metrics.contentHeight, context)
            rawY = rawY - metrics.effectTopInset
            if context.fallbackActive then
                rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
            end
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - metrics.centerX
            rawY = targetWork.y + scaleNumber(state.OffsetYBase, targetScale, 0) - metrics.effectTopInset
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Clock = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    do
        local state = resolvedState('ClockSprite')
        local context, metrics = resolveLayoutContext(snapshot, 'ClockSprite', state, nil, function(targetScale)
            return getClockSpriteMetrics(SKIN, targetScale)
        end, false, forcedMonitor('ClockSprite'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'ClockSprite', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - round(metrics.width / 2)
            rawY = targetWork.y + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects.ClockSprite = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    do
        local state = resolvedState('Jukebox')
        local targetScale = normalizeScale(M.GetScale(SKIN))
        local context, metrics = resolveLayoutContext(snapshot, 'Jukebox', state, nil, function()
            return getJukeboxMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Jukebox'))
        local targetWork = context.work
        local width = metrics.width
        local height = metrics.height
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Jukebox', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - round(metrics.width / 2)
            rawY = targetWork.centerY + scaleNumber(state.OffsetYBase, targetScale, 0) - round(metrics.height / 2)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        local explicitOwnerRect = ownerRectOverride(ownerRectOverrides, 'Jukebox')
        if explicitOwnerRect then
            local liveFallbackActive = context.fallbackActive
            rawX = round(explicitOwnerRect.WindowX)
            rawY = round(explicitOwnerRect.WindowY)
            context = contextForLiveRect(snapshot, buildRect(
                rawX,
                rawY,
                explicitOwnerRect.Width,
                explicitOwnerRect.Height
            ))
            context.fallbackActive = liveFallbackActive
            metrics = getJukeboxMetrics(SKIN, targetScale)
            width = metrics.width
            height = metrics.height
        elseif M.CurrentSkinId(SKIN) ~= 'Jukebox' then
            local liveState = readLiveState(SKIN, 'Jukebox')
            if canFollowLiveOwner(SKIN, 'Jukebox', liveState, snapshot) then
                local liveFallbackActive = context.fallbackActive
                rawX = round(liveState.WindowX)
                rawY = round(liveState.WindowY)
                context = contextForLiveRect(snapshot, buildRect(
                    rawX,
                    rawY,
                    liveState.Width or metrics.width,
                    liveState.Height or metrics.height
                ))
                context.fallbackActive = liveFallbackActive
                metrics = getJukeboxMetrics(SKIN, targetScale)
                width = metrics.width
                height = metrics.height
            end
        end
        rects.Jukebox = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = width,
            height = height,
            scale = targetScale,
            metrics = metrics,
            topCenterX = rawX + (width / 2),
            topY = rawY,
        }, context)
    end
    do
        local state = resolvedState('JukeboxDiscSlot')
        local jukebox = rects.Jukebox
        local targetScale = normalizeScale(M.GetScale(SKIN))
        local context, metrics = resolveLayoutContext(snapshot, 'JukeboxDiscSlot', state, jukebox.monitor, function()
            return getJukeboxDiscSlotMetrics(SKIN, targetScale)
        end, true)
        if not usesFixedPosition(state) and jukebox.fallbackActive then
            context.fallbackActive = true
        end
        local rawX
        local rawY
        if usesFixedPosition(state) then
            local visibleX
            visibleX, rawY = resolveFixedWindow(
                SKIN,
                'JukeboxDiscSlot',
                state,
                context.work,
                metrics.visibleWidth,
                metrics.visibleHeight,
                context
            )
            metrics = resolveJukeboxDiscSlotMetricsForVisibleLeft(metrics, visibleX, context.work)
            rawX = visibleX - metrics.contentX
        else
            local clampWork = context.work
            local offsetX = scaleNumber(state.OffsetXBase, targetScale, 0)
            local offsetY = scaleNumber(state.OffsetYBase, targetScale, 0)
            local topY = jukebox.y - metrics.height - metrics.gap + offsetY
            local bottomY = jukebox.y + jukebox.height + metrics.gap + offsetY
            local jukeboxAnchorX = jukebox.x + (jukebox.width / 2)
            local rightColumnCenterX = metrics.usableX + ((metrics.usableWidth / 3) * 2.5)
            local visibleSlotX = clampWindowX(clampWork, jukeboxAnchorX + offsetX - rightColumnCenterX, metrics.visibleWidth)
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
        rects.JukeboxDiscSlot = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.windowWidth,
            height = metrics.windowHeight,
            scale = targetScale,
            metrics = metrics,
            visibleLeft = rawX + metrics.contentX,
            visibleTop = rawY,
            visibleRight = rawX + metrics.contentX + metrics.visibleWidth,
            visibleBottom = rawY + metrics.visibleHeight,
        }, context)
    end

    do
        local state = resolvedState('Herobrine')
        local context, metrics = resolveLayoutContext(snapshot, 'Herobrine', state, nil, function(targetScale)
            return getHerobrineMetrics(SKIN, targetScale)
        end, false, forcedMonitor('Herobrine'))
        local targetWork = context.work
        local targetScale = context.scale
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, 'Herobrine', state, targetWork, metrics.width, metrics.height, context)
        else
            rawX = targetWork.centerX + scaleNumber(state.OffsetXBase, targetScale, 0) - round(metrics.width / 2)
            rawY = targetWork.centerY + scaleNumber(state.OffsetYBase, targetScale, 0) - round(metrics.height / 2)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects.Herobrine = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    local indicatorAnchorHotbar = resolveIndependentIndicatorAnchorHotbar(
        SKIN,
        snapshot,
        indicatorUserScale,
        forcedMonitor('Hotbar')
    ) or rects.Hotbar
    for _, indicatorId in ipairs({ 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' }) do
        local state = resolvedState(indicatorId)
        local hotbar = indicatorAnchorHotbar
        local context, metrics = resolveLayoutContext(snapshot, indicatorId, state, hotbar.monitor, function(targetScale)
            return getIndicatorMetrics(indicatorId, targetScale, indicatorUserScale)
        end, false, forcedMonitor(indicatorId))
        if not usesFixedPosition(state) and hotbar.fallbackActive then
            context.fallbackActive = true
        end
        local targetScale = context.scale
        local targetWork = context.work
        local indicatorLayoutScale = resolvedIndicatorScale(targetScale, indicatorUserScale)
        local edgeInset = indicatorLayoutScale < 1 and round((1 - indicatorLayoutScale) * 10) or 0
        local definition = SKINS[indicatorId] or {}
        local offsetXBase = tonumber(state.OffsetXBase) or tonumber(definition.offsetX) or 0
        local offsetYBase = tonumber(state.OffsetYBase) or tonumber(definition.offsetY) or 0
        local commonIndicatorY = hotbar.indicatorAnchorTop + (offsetYBase * indicatorLayoutScale)
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(
                SKIN,
                indicatorId,
                state,
                targetWork,
                metrics.width,
                metrics.height + (metrics.gaugeY or 0),
                context
            )
        else
            if state.AnchorKind == 'HotbarVisibleLeftTop' or state.AnchorKind == 'IndicatorBaselineLeftTop' then
                rawX = hotbar.indicatorAnchorLeft + (offsetXBase * indicatorLayoutScale) + edgeInset
                rawY = commonIndicatorY
            elseif state.AnchorKind == 'HotbarVisibleRightTop' or state.AnchorKind == 'IndicatorBaselineRightTop' then
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
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height + (metrics.gaugeY or 0))
        end
        rects[indicatorId] = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    for _, panelId in ipairs({ 'Settings', 'Editor' }) do
        local state = resolvedState(panelId)
        local inventory = rects.Inventory
        local context, metrics = resolveLayoutContext(snapshot, panelId, state, inventory.monitor, function(targetScale)
            return getPanelMetrics(panelId, targetScale)
        end)
        if not usesFixedPosition(state) and inventory.fallbackActive then
            context.fallbackActive = true
        end
        local targetScale = context.scale
        local targetWork = context.work
        local rawX
        local rawY
        if usesFixedPosition(state) then
            rawX, rawY = resolveFixedWindow(SKIN, panelId, state, targetWork, metrics.width, metrics.height, context)
        else
            if state.AnchorKind == 'InventoryLeftTop' then
                rawX = inventory.leftTopX + scaleNumber(state.OffsetXBase, targetScale, 0)
            else
                rawX = inventory.rightTopX + scaleNumber(state.OffsetXBase, targetScale, 0)
            end
            rawY = inventory.leftTopY + scaleNumber(state.OffsetYBase, targetScale, 0)
            rawX, rawY = clampWindow(targetWork, rawX, rawY, metrics.width, metrics.height)
        end
        rects[panelId] = attachMonitorContext({
            x = rawX,
            y = rawY,
            width = metrics.width,
            height = metrics.height,
            scale = targetScale,
            metrics = metrics,
        }, context)
    end

    rects.PrimaryWorkArea = work
    rects.Scale = scale
    rects.MonitorSnapshot = snapshot
    rects.TopologySignature = snapshot.signature
    return rects
end

local function mirrorForcedMonitors(id, monitor)
    local forcedMonitors = { [id] = monitor }
    if tostring(id):find('^Indicator') then
        forcedMonitors.Hotbar = monitor
    end
    return forcedMonitors
end

local function mirrorBaselineStateOverrides(id)
    local function autoState()
        return {
            PositionMode = 'auto',
            FixedX = '0',
            FixedY = '0',
            MonitorFingerprint = '',
            MonitorRelativeX = '',
            MonitorRelativeY = '',
        }
    end
    local overrides = { [id] = autoState() }
    if tostring(id):find('^Indicator') then
        -- Indicators use the Hotbar's responsive geometry only as a target-
        -- monitor baseline. Canonical Hotbar affinity must never leak into it.
        overrides.Hotbar = autoState()
    end
    return overrides
end

function M.ResolveMirrorRect(SKIN, id, monitorFingerprint, monitorIndex, snapshot)
    if not M.IsMirrorTarget or not M.IsMirrorTarget(id) then
        return nil
    end
    snapshot = snapshot or M.SnapshotMonitors(SKIN)
    local monitor = M.FindMonitor and M.FindMonitor(snapshot, monitorFingerprint, monitorIndex) or nil
    if not monitor then
        return nil
    end
    local rects = M.ResolveRects(
        SKIN,
        snapshot,
        nil,
        mirrorForcedMonitors(id, monitor),
        mirrorBaselineStateOverrides(id)
    )
    local rect = rects and rects[id] or nil
    if not rect then
        return nil
    end
    return rect, rects, monitor
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
    setVariableForConfig(SKIN, 'ClockTextShadowYOffset', m.shadowYOffset)
    setVariableForConfig(SKIN, 'ClockDateTextShadowYOffset', m.dateShadowYOffset)
    setVariableForConfig(SKIN, 'ClockTextShadowBlur', m.shadowBlur)
    setVariableForConfig(SKIN, 'ClockTextEffectTopInset', m.effectTopInset)
    setVariableForConfig(SKIN, 'ClockTextEffectBottomExtent', m.effectBottomExtent)
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
    setVariableForConfig(SKIN, 'JukeboxMinimizedW', m.minimizedWidth)
    setVariableForConfig(SKIN, 'JukeboxMinimizedH', m.minimizedHeight)
    setVariableForConfig(SKIN, 'JukeboxMainFormY', round(rect.y))
    setMeterOption(SKIN, 'MeterJukebox', 'W', m.width)
    setMeterOption(SKIN, 'MeterJukebox', 'H', m.height)
    setMeterOption(SKIN, 'MeterJukeboxAnimator', 'W', m.width)
    setMeterOption(SKIN, 'MeterJukeboxAnimator', 'H', m.height)
    setMeterOption(SKIN, 'MeterJukeboxMinimized', 'W', m.minimizedWidth)
    setMeterOption(SKIN, 'MeterJukeboxMinimized', 'H', m.minimizedHeight)
    setMeterOption(SKIN, 'MeterJukeboxMinimizedAnimator', 'W', m.minimizedWidth)
    setMeterOption(SKIN, 'MeterJukeboxMinimizedAnimator', 'H', m.minimizedHeight)
    SKIN:Bang('!UpdateMeter', 'MeterJukebox')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxAnimator')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxMinimized')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxMinimizedAnimator')
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

local INDICATOR_RENDER_MEASURES = {
    'MeasureGaugeRatio',
    'MeasureGaugeRenderedWidth',
    'MeasureGaugeRenderedHeight',
    'MeasureGaugeImageOffset',
    'MeasureGaugeFillWidth',
    'MeasureGaugeTopCropWidth',
    'MeasureGaugeX',
}

local EXP_TEXT_METERS = {
    'MeterTexto',
    'MeterTexto2',
    'MeterTexto3',
    'MeterTexto4',
    'MeterText',
}

local function updateIndicatorRenderConsumers(SKIN, id)
    for _, measureName in ipairs(INDICATOR_RENDER_MEASURES) do
        SKIN:Bang('!UpdateMeasure', measureName)
    end
    if id == 'IndicatorExp' then
        SKIN:Bang('!UpdateMeasure', 'MeasureExp')
    end
    SKIN:Bang('!UpdateMeter', 'MeterGaugeBottom')
    SKIN:Bang('!UpdateMeter', 'MeterGaugeTop')
    if id == 'IndicatorExp' then
        for _, meterName in ipairs(EXP_TEXT_METERS) do
            SKIN:Bang('!UpdateMeter', meterName)
        end
    end
    SKIN:Bang('!Redraw')
end

local function applyIndicatorVars(SKIN, id, rect)
    local m = rect.metrics
    if id == 'IndicatorExp' then
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
        setVariableForConfig(SKIN, 'GaugeY', m.gaugeY)
        setVariableForConfig(SKIN, 'ExpGaugeY', m.gaugeY)
        setVariableForConfig(SKIN, 'ExpTextX', m.textX)
        setVariableForConfig(SKIN, 'ExpTextY', m.textY)
        setVariableForConfig(SKIN, 'ExpTextFontSize', m.textFontSize)
    else
        setVariableForConfig(SKIN, 'DEFAULT_SIZE_RATIO', m.sizeRatio)
        setVariableForConfig(SKIN, 'SizeRatio', m.sizeRatio)
    end
    updateIndicatorRenderConsumers(SKIN, id)
end

local function setMirrorTargetVariable(SKIN, targetConfig, name, value)
    setVariableForConfig(SKIN, name, value, targetConfig)
end

function M.ApplyMirrorTarget(SKIN, id, rect, targetConfig)
    targetConfig = trim(targetConfig or '')
    if targetConfig == '' or not rect or not M.IsMirrorTarget or not M.IsMirrorTarget(id) then
        return nil
    end

    local monitor = rect.monitor
    local work = rect.workArea or (monitor and monitor.work) or nil
    local rawWork = rect.rawWorkArea or (monitor and monitor.rawWork) or work
    if not monitor or not work or not rawWork then
        return nil
    end

    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedMonitorFingerprint', monitor.fingerprint)
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedMonitorIndex', monitor.index)
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkX', round(work.x))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkY', round(work.y))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkWidth', round(work.width))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorAssignedWorkHeight', round(work.height))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedX', round(rect.x))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedY', round(rect.y))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedWidth', round(rect.width))
    setMirrorTargetVariable(SKIN, targetConfig, 'MirrorExpectedHeight', round(rect.height))

    local metrics = rect.metrics or {}
    if id == 'Hotbar' then
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarSlotSize', metrics.slotSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarTextYOffset', metrics.textYOffset)
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarTextFontSize', metrics.textFontSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'HotbarItemSizeOffset', metrics.itemOffset)
    elseif id == 'Clock' then
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockCenterX', metrics.centerX)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTimeTextSize', metrics.timeSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockDateTextSize', metrics.dateSize)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextGap', metrics.textGap)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextShadowYOffset', metrics.shadowYOffset)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockDateTextShadowYOffset', metrics.dateShadowYOffset)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextShadowBlur', metrics.shadowBlur)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextEffectTopInset', metrics.effectTopInset)
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockTextEffectBottomExtent', metrics.effectBottomExtent)
    elseif id == 'ClockSprite' then
        setMirrorTargetVariable(SKIN, targetConfig, 'ClockSpriteRenderSize', metrics.size)
    elseif tostring(id):find('^Indicator') then
        setMirrorTargetVariable(SKIN, targetConfig, 'SizeRatio', metrics.sizeRatio)
        if id == 'IndicatorExp' then
            setMirrorTargetVariable(SKIN, targetConfig, 'GaugeY', metrics.gaugeY)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpGaugeY', metrics.gaugeY)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpTextX', metrics.textX)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpTextY', metrics.textY)
            setMirrorTargetVariable(SKIN, targetConfig, 'ExpTextFontSize', metrics.textFontSize)
        else
            setMirrorTargetVariable(SKIN, targetConfig, 'DEFAULT_SIZE_RATIO', metrics.sizeRatio)
        end
    end

    SKIN:Bang('!Move', tostring(round(rect.x)), tostring(round(rect.y)), targetConfig)
    return {
        id = id,
        config = targetConfig,
        x = round(rect.x),
        y = round(rect.y),
        width = round(rect.width),
        height = round(rect.height),
        monitorFingerprint = monitor.fingerprint,
        monitorIndex = monitor.index,
    }
end

function M.ApplyCurrentSkin(SKIN, options, snapshot)
    local id = M.CurrentSkinId(SKIN)
    if not id then
        return nil
    end
    if type(options) == 'table' and options.snapshot then
        snapshot = options.snapshot
    end
    local ownerRectOverrides = type(options) == 'table' and options.ownerRectOverrides or nil
    local forcedMonitors = type(options) == 'table' and options.forcedMonitors or nil
    local rects = M.ResolveRects(SKIN, snapshot, ownerRectOverrides, forcedMonitors)
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
        SKIN:Bang('!UpdateMeterGroup', 'ResidentUpdateInventory')
        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()')
        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()')
        syncSelectedHighlight(SKIN)
        SKIN:Bang('!Redraw')
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
        local persistWindowPosition = options ~= false and options ~= 0
        if type(options) == 'table' and options.persistWindowPosition == false then
            persistWindowPosition = false
        end
        if persistWindowPosition and not rect.fallbackActive then
            syncRainmeterWindowPosition(SKIN, id, rect.x, rect.y, true)
        end
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
        local fallbackBlocked = resolvedMode == 'fixed' and M.IsMonitorFallback(SKIN, id)
        if state and not fallbackBlocked and normalizePositionMode(state.PositionMode) ~= resolvedMode then
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
            state.MonitorFingerprint = ''
            state.MonitorRelativeX = ''
            state.MonitorRelativeY = ''
            M.WriteState(SKIN, id, state, true)
        end
    end
end

local function formatRelative(value)
    return string.format('%.12g', tonumber(value) or 0)
end

local function relativeCoordinate(position, workStart, workSize, windowSize)
    local span = (tonumber(workSize) or 0) - (tonumber(windowSize) or 0)
    if span == 0 then
        return 0
    end
    return ((tonumber(position) or 0) - (tonumber(workStart) or 0)) / span
end

local function logicalRectGeometry(id, rect)
    if not rect then
        return nil
    end
    if id == 'JukeboxDiscSlot' then
        return {
            x = rect.visibleLeft or rect.x,
            y = rect.visibleTop or rect.y,
            width = rect.metrics and rect.metrics.visibleWidth or rect.width,
            height = rect.metrics and rect.metrics.visibleHeight or rect.height,
            probeX = rect.x,
            probeY = rect.y,
            probeWidth = rect.width,
            probeHeight = rect.height,
        }
    end
    return {
        x = rect.x,
        y = rect.y,
        width = rect.width,
        height = rect.height,
        probeX = rect.x,
        probeY = rect.y,
        probeWidth = rect.width,
        probeHeight = rect.height,
    }
end

local function logicalSizeForMonitor(SKIN, id, monitor)
    local targetScale = monitor and monitor.scale or M.GetScale(SKIN)
    local metrics = nil
    if id == 'Hotbar' then
        metrics = getHotbarMetrics(SKIN, targetScale, getIndicatorUserScale(SKIN))
        return metrics.windowWidth, metrics.windowHeight, metrics
    elseif id == 'Inventory' then
        metrics = getInventoryMetrics(SKIN, targetScale)
    elseif id == 'Clock' then
        metrics = getClockMetrics(SKIN, targetScale)
    elseif id == 'ClockSprite' then
        metrics = getClockSpriteMetrics(SKIN, targetScale)
    elseif id == 'Jukebox' then
        metrics = getJukeboxMetrics(SKIN, M.GetScale(SKIN))
    elseif id == 'JukeboxDiscSlot' then
        metrics = getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
        return metrics.visibleWidth, metrics.visibleHeight, metrics
    elseif id == 'Herobrine' then
        metrics = getHerobrineMetrics(SKIN, targetScale)
    elseif id == 'Settings' or id == 'Editor' then
        metrics = getPanelMetrics(id, targetScale)
    elseif id:find('^Indicator') then
        metrics = getIndicatorMetrics(id, targetScale, getIndicatorUserScale(SKIN))
    end
    if metrics then
        return metrics.width, metrics.height, metrics
    end
    return nil, nil, nil
end

function M.CommitFixedPosition(SKIN, id, desiredX, desiredY, probeX, probeY, probeWidth, probeHeight, logicalWidth, logicalHeight, snapshot)
    if not id or id == 'InventoryBG' or not SKINS[id] then
        return false, nil
    end
    local x = tonumber(desiredX)
    local y = tonumber(desiredY)
    if x == nil or y == nil then
        return false, nil
    end

    local state = M.GetState(SKIN, id)
    if not state then
        return false, nil
    end
    local rects = nil
    local geometry = nil
    if tonumber(probeWidth) == nil or tonumber(probeHeight) == nil
        or tonumber(logicalWidth) == nil or tonumber(logicalHeight) == nil then
        rects = M.ResolveRects(SKIN, snapshot)
        geometry = logicalRectGeometry(id, rects and rects[id])
    end

    local provisionalLogicalWidth = math.max(1, tonumber(logicalWidth) or (geometry and geometry.width) or tonumber(probeWidth) or 1)
    local provisionalLogicalHeight = math.max(1, tonumber(logicalHeight) or (geometry and geometry.height) or tonumber(probeHeight) or 1)
    local resolvedProbeX = tonumber(probeX)
    local resolvedProbeY = tonumber(probeY)
    local resolvedProbeWidth = math.max(1, tonumber(probeWidth) or (geometry and geometry.probeWidth) or provisionalLogicalWidth)
    local resolvedProbeHeight = math.max(1, tonumber(probeHeight) or (geometry and geometry.probeHeight) or provisionalLogicalHeight)
    if resolvedProbeX == nil then
        if id == 'JukeboxDiscSlot' and geometry then
            resolvedProbeX = x - ((geometry.x or 0) - (geometry.probeX or 0))
        else
            resolvedProbeX = x
        end
    end
    if resolvedProbeY == nil then
        resolvedProbeY = y
    end

    local monitorSnapshot = rects and rects.MonitorSnapshot or snapshot or M.SnapshotMonitors(SKIN)
    local probe = buildRect(resolvedProbeX, resolvedProbeY, resolvedProbeWidth, resolvedProbeHeight)
    local affinityFallback, _, affinityIsFallback = affinityMonitor(monitorSnapshot, state)
    if affinityIsFallback then
        return false, nil
    end
    local monitor = M.SelectMonitorForRect(monitorSnapshot, probe, affinityFallback or monitorSnapshot.primary)
    local targetLogicalWidth, targetLogicalHeight, targetMetrics = logicalSizeForMonitor(SKIN, id, monitor)
    local storedX = x
    local storedY = y
    if id == 'Clock' and targetMetrics then
        storedY = y + (tonumber(targetMetrics.effectTopInset) or 0)
        targetLogicalHeight = targetMetrics.contentHeight or targetLogicalHeight
    end
    local resolvedLogicalWidth = math.max(1, tonumber(targetLogicalWidth) or tonumber(logicalWidth) or (geometry and geometry.width) or resolvedProbeWidth)
    local resolvedLogicalHeight = math.max(1, tonumber(targetLogicalHeight) or tonumber(logicalHeight) or (geometry and geometry.height) or resolvedProbeHeight)
    local relativeX = relativeCoordinate(storedX, monitor.work.x, monitor.work.width, resolvedLogicalWidth)
    local relativeY = relativeCoordinate(storedY, monitor.work.y, monitor.work.height, resolvedLogicalHeight)
    local fixedX = tostring(round(storedX))
    local fixedY = tostring(round(storedY))
    local affinity = {
        MonitorFingerprint = monitor.fingerprint,
        MonitorRelativeX = formatRelative(relativeX),
        MonitorRelativeY = formatRelative(relativeY),
        monitor = monitor,
    }

    local changed = normalizePositionMode(state.PositionMode) ~= 'fixed'
        or tostring(state.FixedX or '') ~= fixedX
        or tostring(state.FixedY or '') ~= fixedY
        or tostring(state.MonitorFingerprint or '') ~= affinity.MonitorFingerprint
        or tostring(state.MonitorRelativeX or '') ~= affinity.MonitorRelativeX
        or tostring(state.MonitorRelativeY or '') ~= affinity.MonitorRelativeY
    if not changed then
        return false, affinity
    end

    state.PositionMode = 'fixed'
    state.FixedX = fixedX
    state.FixedY = fixedY
    state.MonitorFingerprint = affinity.MonitorFingerprint
    state.MonitorRelativeX = affinity.MonitorRelativeX
    state.MonitorRelativeY = affinity.MonitorRelativeY
    M.WriteState(SKIN, id, state, true, { syncRainmeterPosition = false })
    return true, affinity
end

function M.SetFixedPosition(SKIN, id, x, y)
    return M.CommitFixedPosition(SKIN, id, x, y)
end

function M.CaptureFixedPositionsForIds(SKIN, ids, positionsById)
    positionsById = positionsById or {}
    for _, id in ipairs(normalizedStateTargetIds(ids)) do
        local state = M.GetState(SKIN, id)
        local position = positionsById[id]
        if state and position then
            M.CommitFixedPosition(SKIN, id, position.x, position.y)
        end
    end
end

function M.AutoMonitorOwner(id)
    return AUTO_MONITOR_OWNER[id]
end

local function exportedMonitorContext(monitor, fallbackActive)
    local work = monitor.work
    local rawWork = monitor.rawWork
    return {
        Fingerprint = monitor.fingerprint,
        MonitorIndex = monitor.index,
        WorkX = round(work.x),
        WorkY = round(work.y),
        WorkWidth = round(work.width),
        WorkHeight = round(work.height),
        RawWorkX = round(rawWork.x),
        RawWorkY = round(rawWork.y),
        RawWorkWidth = round(rawWork.width),
        RawWorkHeight = round(rawWork.height),
        Scale = monitor.scale or M.ScaleForWorkArea(work),
        FallbackActive = fallbackActive == true,
    }
end

function M.CurrentMonitorContext(SKIN, id, x, y, width, height, snapshot)
    if tonumber(x) ~= nil and tonumber(y) ~= nil and tonumber(width) ~= nil and tonumber(height) ~= nil then
        snapshot = snapshot or M.SnapshotMonitors(SKIN)
        local fallback = snapshot.primary
        if id and SKINS[id] then
            local state = M.GetState(SKIN, id)
            local affinityFallback, _, affinityIsFallback = affinityMonitor(snapshot, state)
            if affinityFallback and not affinityIsFallback then
                fallback = affinityFallback
            end
        end
        local monitor = M.SelectMonitorForRect(snapshot, buildRect(x, y, width, height), fallback)
        local exported = exportedMonitorContext(monitor, false)
        if id == 'Jukebox' or id == 'JukeboxDiscSlot' then
            exported.Scale = M.GetScale(SKIN)
        end
        return exported
    end
    id = id or M.CurrentSkinId(SKIN)
    local rects = M.ResolveRects(SKIN, snapshot)
    local rect = rects and rects[id]
    if not rect or not rect.monitor then
        return exportedMonitorContext(rects.MonitorSnapshot.primary, false)
    end
    local exported = exportedMonitorContext(rect.monitor, rect.fallbackActive)
    if id == 'Jukebox' or id == 'JukeboxDiscSlot' then
        exported.Scale = M.GetScale(SKIN)
    end
    return exported
end

function M.ResolveInventoryLiveWindowPosition(SKIN)     local rects = M.ResolveRects(SKIN)     local inventory = rects and rects.Inventory     if not inventory then         return nil     end     return { x = round(inventory.x), y = round(inventory.y) } end  function M.LiveWindowPositionForId(SKIN, id, fallbackRects)
    if not SKINS[id] then
        return nil
    end
    local fallback = fallbackRects and fallbackRects[id]
    local function visiblePosition(position)
        if id ~= 'JukeboxDiscSlot' or not position then
            return position
        end
        local metrics = fallback and fallback.metrics or nil
        local work = fallback and fallback.workArea or nil
        local width = tonumber(position.width)
        local height = tonumber(position.height)
        if width and height then
            local snapshot = fallbackRects and fallbackRects.MonitorSnapshot or M.SnapshotMonitors(SKIN)
            local monitor = M.SelectMonitorForRect(snapshot, buildRect(position.x, position.y, width, height), snapshot.primary)
            metrics = getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
            work = monitor.work
        end
        metrics = metrics or getJukeboxDiscSlotMetrics(SKIN, M.GetScale(SKIN))
        local contentX = tonumber(metrics.contentX) or 0
        if width then
            local visibleWidth = tonumber(metrics.visibleWidth) or tonumber(metrics.width) or 1
            local actionGutter = tonumber(metrics.actionGutter or metrics.controlRightGutter) or 0
            local extraWidth = math.max(0, round(width - visibleWidth))
            local rightContentX = math.max(0, extraWidth - actionGutter)
            local rightVisibleX = (tonumber(position.x) or 0) + rightContentX
            if work and (rightVisibleX + visibleWidth + actionGutter) <= (work.right + 0.5) then
                contentX = rightContentX
            else
                contentX = extraWidth
            end
        end
        return {
            x = round((tonumber(position.x) or 0) + contentX),
            y = round(tonumber(position.y) or 0),
        }
    end
    local sameSkinPosition = sameSkinCurrentWindowPosition(SKIN, id)
    if sameSkinPosition then
        sameSkinPosition.width = tonumber(trim(SKIN:GetVariable('CURRENTCONFIGWIDTH', '')))
        sameSkinPosition.height = tonumber(trim(SKIN:GetVariable('CURRENTCONFIGHEIGHT', '')))
        return visiblePosition(sameSkinPosition)
    end
    local liveState = readLiveState(SKIN, id)
    if liveState and liveState.Active then
        if liveState.WindowX ~= nil and liveState.WindowY ~= nil then
            return visiblePosition({ x = liveState.WindowX, y = liveState.WindowY, width = liveState.Width, height = liveState.Height })
        end
        return nil
    end
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

    fallbackRects = fallbackRects or M.ResolveRects(SKIN)
    local geometry = logicalRectGeometry(id, fallbackRects and fallbackRects[id])
    local probeX = position.x
    local probeY = position.y
    if id == 'JukeboxDiscSlot' and geometry then
        probeX = position.x - ((geometry.x or 0) - (geometry.probeX or 0))
    end
    return M.CommitFixedPosition(
        SKIN,
        id,
        position.x,
        position.y,
        probeX,
        probeY,
        geometry and geometry.probeWidth,
        geometry and geometry.probeHeight,
        geometry and geometry.width,
        geometry and geometry.height
    )
end

function M.CaptureCurrentSkinState(SKIN)     local id = M.CurrentSkinId(SKIN)     if not id then         return nil     end     return M.GetState(SKIN, id) end

TAB_TARGETS.jukebox = { 'Jukebox', 'JukeboxDiscSlot' }

return M
