-- Split from ExtraContent\Jukebox\DiscSlot\JukeboxDiscSlot.lua lines 1555-2289.
JukeboxDiscSlotTextFit = nil

function EnsureJukeboxDiscSlotTextFit()
    if JukeboxDiscSlotTextFit == nil then
        JukeboxDiscSlotTextFit = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\LocalizationTextFit.lua')
    end
    return JukeboxDiscSlotTextFit
end

function ApplyDiscSlotTextFit(meterName, text, baseFontSize, widthPx, minScale)
    local helper = EnsureJukeboxDiscSlotTextFit()
    if not helper or not helper.ApplyMeterTextFit then
        return
    end
    helper.ApplyMeterTextFit(SKIN, meterName, text, {
        baseFontSize = tonumber(baseFontSize) or 12,
        widthPx = tonumber(widthPx) or 0,
        minScale = tonumber(minScale) or 0.60,
        probeMeterName = 'MeterJukeboxDiscSlotTextFitProbe',
        setText = false,
        update = false,
    })
end

local function syncPageMeters()
    local m = pageControlMetrics()
    local controlsHidden = optionsVisible() and 0 or 1
    local localOnlyHidden = isExternalPlaybackSourceMode() and 1 or 0
    local external = externalTransportMetrics()
    syncExternalCoverMeters()
    setVariable('JukeboxDiscSlotPageText', tostring(currentPage) .. ' / ' .. tostring(totalPages))
    local originX = contentX()
    setVariable('JukeboxDiscSlotLocalOnlyHidden', localOnlyHidden)
    setVariable('JukeboxDiscSlotPagePrevX', m.prevX + originX)
    setVariable('JukeboxDiscSlotPageLabelX', m.labelX + originX)
    setVariable('JukeboxDiscSlotPageNextX', m.nextX + originX)
    setVariable('JukeboxDiscSlotPageControlY', m.y)
    setVariable('JukeboxDiscSlotPagePrevHitX', m.prevHitX + originX)
    setVariable('JukeboxDiscSlotPageNextHitX', m.nextHitX + originX)
    setVariable('JukeboxDiscSlotPageHitY', m.hitY)
    setVariable('JukeboxDiscSlotPageHitW', m.hitW)
    setVariable('JukeboxDiscSlotPageHitH', m.hitH)
    setVariable('JukeboxDiscSlotPageFontSize', m.fontSize)
    setVariable('JukeboxDiscSlotOpenFolderX', m.openFolderX + originX)
    setVariable('JukeboxDiscSlotOpenFolderHitX', m.openFolderHitX + originX)
    setVariable('JukeboxDiscSlotOpenFolderHitW', m.openFolderHitW)
    setVariable('JukeboxDiscSlotOpenFolderW', m.openFolderHitW)
    setVariable('JukeboxDiscSlotRepeatX', m.repeatX + originX)
    setVariable('JukeboxDiscSlotRepeatY', m.repeatY)
    setVariable('JukeboxDiscSlotRepeatHitX', m.repeatHitX + originX)
    setVariable('JukeboxDiscSlotRepeatHitW', m.repeatHitW)
    setVariable('JukeboxDiscSlotRepeatColor', m.repeatColor)
    setVariable('JukeboxDiscSlotRepeatOneHidden', m.repeatOneHidden)
    setVariable('JukeboxDiscSlotRepeatOneX', m.repeatOneX + originX)
    setVariable('JukeboxDiscSlotRepeatOneY', m.repeatOneY)
    setVariable('JukeboxDiscSlotRepeatOneFontSize', m.repeatOneFontSize)
    setVariable('JukeboxDiscSlotShuffleX', m.shuffleX + originX)
    setVariable('JukeboxDiscSlotShuffleY', m.shuffleY)
    setVariable('JukeboxDiscSlotShuffleHitX', m.shuffleHitX + originX)
    setVariable('JukeboxDiscSlotShuffleHitW', m.shuffleHitW)
    setVariable('JukeboxDiscSlotShuffleColor', m.shuffleColor)
    setVariable('JukeboxDiscSlotCloseX', m.closeX + originX)
    setVariable('JukeboxDiscSlotCloseY', m.closeY)
    setVariable('JukeboxDiscSlotCloseHitX', m.closeHitX + originX)
    setVariable('JukeboxDiscSlotCloseHitY', m.closeHitY)
    setVariable('JukeboxDiscSlotMinimizeX', m.minimizeX + originX)
    setVariable('JukeboxDiscSlotMinimizeY', m.minimizeY)
    setVariable('JukeboxDiscSlotMinimizeHitX', m.minimizeHitX + originX)
    setVariable('JukeboxDiscSlotMinimizeHitY', m.minimizeHitY)
    setVariable('JukeboxDiscSlotMinimizeIconLeft', m.minimizeIconLeft)
    setVariable('JukeboxDiscSlotMinimizeIconRight', m.minimizeIconRight)
    setVariable('JukeboxDiscSlotMinimizeIconCenterX', m.minimizeIconCenterX)
    setVariable('JukeboxDiscSlotMinimizeIconTop', m.minimizeIconTop)
    setVariable('JukeboxDiscSlotMinimizeIconChevronY', m.minimizeIconChevronY)
    setVariable('JukeboxDiscSlotMinimizeIconBottom', m.minimizeIconBottom)
    setVariable('JukeboxDiscSlotMinimizeIconStroke', m.minimizeIconStroke)
    setVariable('JukeboxDiscSlotSettingsX', m.settingsX + originX)
    setVariable('JukeboxDiscSlotSettingsY', m.settingsY)
    setVariable('JukeboxDiscSlotSettingsHitX', m.settingsHitX + originX)
    setVariable('JukeboxDiscSlotSettingsHitY', m.settingsHitY)
    setVariable('JukeboxDiscSlotVolumeHidden', m.volumeHidden)
    setVariable('JukeboxDiscSlotVolumeHitX', m.volumeHitX + originX)
    setVariable('JukeboxDiscSlotVolumeHitY', m.volumeHitY)
    setVariable('JukeboxDiscSlotVolumeHitW', m.volumeHitW)
    setVariable('JukeboxDiscSlotVolumeHitH', m.volumeHitH)
    setVariable('JukeboxDiscSlotVolumeTrackX', m.volumeTrackX + originX)
    setVariable('JukeboxDiscSlotVolumeTrackY', m.volumeTrackY)
    setVariable('JukeboxDiscSlotVolumeTrackW', m.volumeTrackW)
    setVariable('JukeboxDiscSlotVolumeTrackH', m.volumeTrackH)
    setVariable('JukeboxDiscSlotVolumeTrackRadius', m.volumeTrackRadius)
    setVariable('JukeboxDiscSlotVolumeFillX', m.volumeFillX + originX)
    setVariable('JukeboxDiscSlotVolumeFillY', m.volumeFillY)
    setVariable('JukeboxDiscSlotVolumeFillW', m.volumeFillW)
    setVariable('JukeboxDiscSlotVolumeFillH', m.volumeFillH)
    setVariable('JukeboxDiscSlotVolumeFillHidden', m.volumeFillHidden)
    setVariable('JukeboxDiscSlotVolumeThumbX', m.volumeThumbX + originX)
    setVariable('JukeboxDiscSlotVolumeThumbY', m.volumeThumbY)
    setVariable('JukeboxDiscSlotVolumeThumbRadius', m.volumeThumbRadius)
    setVariable('JukeboxDiscSlotVolumeTrackColor', m.volumeTrackColor)
    setVariable('JukeboxDiscSlotVolumeFillColor', m.volumeFillColor)
    setVariable('JukeboxDiscSlotVolumeThumbColor', m.volumeThumbColor)
    setVariable('JukeboxDiscSlotVolumeCursor', m.volumeCursor)
    setVariable('JukeboxDiscSlotOptionsToggleX', m.optionsToggleX + originX)
    setVariable('JukeboxDiscSlotOptionsToggleY', m.optionsToggleY)
    setVariable('JukeboxDiscSlotOptionsToggleHitX', m.optionsToggleHitX + originX)
    setVariable('JukeboxDiscSlotOptionsToggleHitY', m.optionsToggleHitY)
    setVariable('JukeboxDiscSlotOptionsControlsHidden', controlsHidden)
    setVariable('JukeboxDiscSlotOptionsShowHidden', optionsVisible() and 0 or 1)
    setVariable('JukeboxDiscSlotOptionsHideHidden', optionsVisible() and 1 or 0)
    setVariable('JukeboxDiscSlotTopActionHitW', m.topActionHitW)
    setVariable('JukeboxDiscSlotTopActionHitH', m.topActionHitH)
    setVariable('JukeboxDiscSlotTopActionColor', m.topActionColor)
    setVariable('JukeboxDiscSlotActionSide', m.actionSide)
    setVariable('JukeboxDiscSlotCloseFontSize', m.topActionFontSize)
    setVariable('JukeboxDiscSlotControlIconStroke', m.iconStroke)
    setVariable('JukeboxDiscSlotCloseIconLeft', m.closeIconLeft)
    setVariable('JukeboxDiscSlotCloseIconRight', m.closeIconRight)
    setVariable('JukeboxDiscSlotCloseIconTop', m.closeIconTop)
    setVariable('JukeboxDiscSlotCloseIconBottom', m.closeIconBottom)
    setVariable('JukeboxDiscSlotTopActionIconLeft', m.actionIconLeft)
    setVariable('JukeboxDiscSlotTopActionIconRight', m.actionIconRight)
    setVariable('JukeboxDiscSlotTopActionIconTop', m.actionIconTop)
    setVariable('JukeboxDiscSlotTopActionIconBottom', m.actionIconBottom)
    setVariable('JukeboxDiscSlotControlIconLeft', m.iconLeft)
    setVariable('JukeboxDiscSlotControlIconTop', m.iconTop)
    setVariable('JukeboxDiscSlotControlIconBottom', m.iconBottom)
    setVariable('JukeboxDiscSlotControlIconLoopW', m.iconLoopW)
    setVariable('JukeboxDiscSlotControlIconLoopH', m.iconLoopH)
    setVariable('JukeboxDiscSlotControlIconLoopRadiusX', m.iconLoopRadiusX)
    setVariable('JukeboxDiscSlotControlIconLoopRadiusY', m.iconLoopRadiusY)
    setVariable('JukeboxDiscSlotControlIconArrowLeftNear', m.iconArrowLeftNear)
    setVariable('JukeboxDiscSlotControlIconBottomArrowUp', m.iconBottomArrowUp)
    setVariable('JukeboxDiscSlotControlIconBottomArrowDown', m.iconBottomArrowDown)
    setVariable('JukeboxDiscSlotControlIconShuffleLeft', m.shuffleLeft)
    setVariable('JukeboxDiscSlotControlIconShuffleRight', m.shuffleRight)
    setVariable('JukeboxDiscSlotControlIconShuffleTop', m.shuffleTop)
    setVariable('JukeboxDiscSlotControlIconShuffleBottom', m.shuffleBottom)
    setVariable('JukeboxDiscSlotControlIconShuffleMidLeft', m.shuffleMidLeft)
    setVariable('JukeboxDiscSlotControlIconShuffleMidRight', m.shuffleMidRight)
    setVariable('JukeboxDiscSlotControlIconShuffleArrowNear', m.shuffleArrowNear)
    setVariable('JukeboxDiscSlotControlIconShuffleTopArrowUp', m.shuffleTopArrowUp)
    setVariable('JukeboxDiscSlotControlIconShuffleTopArrowDown', m.shuffleTopArrowDown)
    setVariable('JukeboxDiscSlotControlIconShuffleBottomArrowUp', m.shuffleBottomArrowUp)
    setVariable('JukeboxDiscSlotControlIconShuffleBottomArrowDown', m.shuffleBottomArrowDown)
    setVariable('JukeboxDiscSlotExternalPlaybackHidden', external.playbackHidden)
    setVariable('JukeboxDiscSlotExternalOptionsHidden', external.optionsHidden)
    setVariable('JukeboxDiscSlotExternalButtonHitW', external.controls.playpause.hitW)
    setVariable('JukeboxDiscSlotExternalButtonHitH', external.controls.playpause.hitH)
    for _, control in ipairs(EXTERNAL_TRANSPORT_ORDER) do
        local prefix = control:sub(1, 1):upper() .. control:sub(2)
        if control == 'playpause' then
            prefix = 'PlayPause'
        end
        local values = external.controls[control]
        setVariable('JukeboxDiscSlotExternal' .. prefix .. 'HitX', values.hitX + originX)
        setVariable('JukeboxDiscSlotExternal' .. prefix .. 'HitY', values.hitY)
        setVariable('JukeboxDiscSlotExternal' .. prefix .. 'X', values.centerX + originX)
        setVariable('JukeboxDiscSlotExternal' .. prefix .. 'Y', values.centerY)
        setVariable('JukeboxDiscSlotExternal' .. prefix .. 'Disabled', external.disabled[control])
    end
    setVariable('JukeboxDiscSlotExternalPreviousColor', external.previousColor)
    setVariable('JukeboxDiscSlotExternalPlayPauseColor', external.playPauseColor)
    setVariable('JukeboxDiscSlotExternalNextColor', external.nextColor)
    setVariable('JukeboxDiscSlotExternalRepeatColor', external.repeatColor)
    setVariable('JukeboxDiscSlotExternalRepeatOneHidden', external.repeatOneHidden)
    setVariable('JukeboxDiscSlotExternalRepeatX', external.repeatX + originX)
    setVariable('JukeboxDiscSlotExternalRepeatY', external.repeatY)
    setVariable('JukeboxDiscSlotExternalRepeatOneX', external.repeatOneX + originX)
    setVariable('JukeboxDiscSlotExternalRepeatOneY', external.repeatOneY)
    setVariable('JukeboxDiscSlotExternalRepeatOneFontSize', external.repeatOneFontSize)
    setVariable('JukeboxDiscSlotExternalShuffleColor', external.shuffleColor)
    setVariable('JukeboxDiscSlotExternalShuffleX', external.shuffleX + originX)
    setVariable('JukeboxDiscSlotExternalShuffleY', external.shuffleY)
    setVariable('JukeboxDiscSlotExternalPlayHidden', external.playHidden)
    setVariable('JukeboxDiscSlotExternalPauseHidden', external.pauseHidden)
    ApplyDiscSlotTextFit(
        'MeterJukeboxDiscSlotOpenFolder',
        '#Loc_Common_OpenFolder#',
        m.fontSize,
        math.max(0, m.openFolderHitW - 8),
        0.55
    )
    updateMeter('MeterJukeboxDiscSlotOpenFolderHit')
    updateMeter('MeterJukeboxDiscSlotOpenFolder')
    updateMeter('MeterJukeboxDiscSlotRepeatHit')
    updateMeter('MeterJukeboxDiscSlotShuffleHit')
    updateMeter('MeterJukeboxDiscSlotCloseHit')
    updateMeter('MeterJukeboxDiscSlotMinimizeHit')
    updateMeter('MeterJukeboxDiscSlotSettingsHit')
    updateMeter('MeterJukeboxDiscSlotVolumeTrack')
    updateMeter('MeterJukeboxDiscSlotVolumeFill')
    updateMeter('MeterJukeboxDiscSlotVolumeThumb')
    updateMeter('MeterJukeboxDiscSlotVolumeHit')
    updateMeter('MeterJukeboxDiscSlotOptionsToggleHit')
    updateMeter('MeterJukeboxDiscSlotRepeatIcon')
    updateMeter('MeterJukeboxDiscSlotRepeatOne')
    updateMeter('MeterJukeboxDiscSlotShuffleIcon')
    updateMeter('MeterJukeboxDiscSlotCloseIcon')
    updateMeter('MeterJukeboxDiscSlotMinimizeIcon')
    updateMeter('MeterJukeboxDiscSlotSettingsIcon')
    updateMeter('MeterJukeboxDiscSlotOptionsShowIcon')
    updateMeter('MeterJukeboxDiscSlotOptionsHideIcon')
    updateMeter('MeterJukeboxDiscSlotExternalPreviousIcon')
    updateMeter('MeterJukeboxDiscSlotExternalPlayIcon')
    updateMeter('MeterJukeboxDiscSlotExternalPauseIcon')
    updateMeter('MeterJukeboxDiscSlotExternalNextIcon')
    updateMeter('MeterJukeboxDiscSlotExternalRepeatIcon')
    updateMeter('MeterJukeboxDiscSlotExternalRepeatOne')
    updateMeter('MeterJukeboxDiscSlotExternalShuffleIcon')
    updateMeter('MeterJukeboxDiscSlotExternalPreviousHit')
    updateMeter('MeterJukeboxDiscSlotExternalPlayPauseHit')
    updateMeter('MeterJukeboxDiscSlotExternalNextHit')
    updateMeter('MeterJukeboxDiscSlotExternalRepeatHit')
    updateMeter('MeterJukeboxDiscSlotExternalShuffleHit')
    updateMeter('MeterJukeboxDiscSlotPagePrevHit')
    updateMeter('MeterJukeboxDiscSlotPageNextHit')
    updateMeter('MeterJukeboxDiscSlotPagePrev')
    updateMeter('MeterJukeboxDiscSlotPageLabel')
    updateMeter('MeterJukeboxDiscSlotPageNext')
end

local function pointInside(px, py, x, y, w, h)
    return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

local function externalCoverAtPoint(x, y)
    if not isExternalPlaybackSourceMode() then
        return false
    end
    if numberVar('JukeboxDiscSlotExternalCoverHidden', 1) ~= 0 then
        return false
    end
    local coverX = numberVar('JukeboxDiscSlotExternalCoverX', 0) - contentX()
    local coverY = numberVar('JukeboxDiscSlotExternalCoverY', 0)
    local coverW = numberVar('JukeboxDiscSlotExternalCoverW', 0)
    local coverH = numberVar('JukeboxDiscSlotExternalCoverH', 0)
    if coverW <= 0 or coverH <= 0 then
        return false
    end
    return pointInside(x, y, coverX, coverY, coverW, coverH)
end

local function externalCoverFailureTooltipAtPoint(x, y)
    if not externalCoverLoadFailed then
        return nil
    end
    if externalCoverAtPoint(x, y) then
        return 'external-cover-failed', thumbnailLoadFailedTooltipText()
    end
    return nil
end

local function externalTransportControlAtPoint(x, y)
    if not isExternalPlaybackSourceMode() then
        return nil
    end
    local m = externalTransportMetrics()
    for _, control in ipairs(EXTERNAL_TRANSPORT_ORDER) do
        if externalTransportControlVisible(control) and (externalPlaybackConnected() or externalPrimaryTransportControl(control)) then
            local values = m.controls[control]
            if pointInside(x, y, values.hitX, values.hitY, values.hitW, values.hitH) then
                return control, externalTransportTooltipText(control)
            end
        end
    end
    return nil
end

local function volumeControlAtPoint(x, y)
    if not optionsVisible() then
        return nil
    end
    if isExternalPlaybackSourceMode() and not externalVolumeStateConnected() then
        return nil
    end
    local m = pageControlMetrics()
    if pointInside(x, y, m.volumeHitX, m.volumeHitY, m.volumeHitW, m.volumeHitH) then
        return 'volume', volumeTooltipText()
    end
    return nil
end

local function controlAtPoint(x, y)
    local m = pageControlMetrics()
    if pointInside(x, y, m.optionsToggleHitX, m.optionsToggleHitY, m.topActionHitW, m.topActionHitH) then
        return 'options-toggle', optionsVisibilityTooltipText()
    end
    if isExternalPlaybackSourceMode() then
        local externalControl, externalText = externalTransportControlAtPoint(x, y)
        if externalControl ~= nil then
            return externalControl, externalText
        end
    end
    if not optionsVisible() then
        return nil
    end
    local volumeControl, volumeText = volumeControlAtPoint(x, y)
    if volumeControl ~= nil then
        return volumeControl, volumeText
    end
    if pointInside(x, y, m.closeHitX, m.closeHitY, m.topActionHitW, m.topActionHitH) then
        return 'close', closeTooltipText()
    end
    if pointInside(x, y, m.minimizeHitX, m.minimizeHitY, m.topActionHitW, m.topActionHitH) then
        return 'minimize', minimizeTooltipText()
    end
    if pointInside(x, y, m.settingsHitX, m.settingsHitY, m.topActionHitW, m.topActionHitH) then
        return 'settings', settingsTooltipText()
    end
    if isExternalPlaybackSourceMode() then
        return nil
    end
    if pointInside(x, y, m.openFolderHitX, m.hitY, m.openFolderHitW, m.hitH) then
        return 'open-folder', openFolderTooltipText()
    end
    if pointInside(x, y, m.repeatHitX, m.hitY, m.repeatHitW, m.hitH) then
        return 'repeat', repeatTooltipText()
    end
    if pointInside(x, y, m.shuffleHitX, m.hitY, m.shuffleHitW, m.hitH) then
        return 'shuffle', shuffleTooltipText()
    end
    return nil
end

local function controlTooltipAtPoint(x, y)
    local m = pageControlMetrics()
    if pointInside(x, y, m.optionsToggleHitX, m.optionsToggleHitY, m.topActionHitW, m.topActionHitH) then
        return 'options-toggle', optionsVisibilityTooltipText()
    end
    if isExternalPlaybackSourceMode() then
        local externalControl, externalText = externalTransportControlAtPoint(x, y)
        if externalControl ~= nil then
            return externalControl, externalText
        end
    end
    if not optionsVisible() then
        return nil
    end
    local volumeControl, volumeText = volumeControlAtPoint(x, y)
    if volumeControl ~= nil then
        return volumeControl, volumeText
    end
    if pointInside(x, y, m.closeHitX, m.closeHitY, m.topActionHitW, m.topActionHitH) then
        return 'close', closeTooltipText()
    end
    if pointInside(x, y, m.minimizeHitX, m.minimizeHitY, m.topActionHitW, m.topActionHitH) then
        return 'minimize', minimizeTooltipText()
    end
    if pointInside(x, y, m.settingsHitX, m.settingsHitY, m.topActionHitW, m.topActionHitH) then
        return 'settings', settingsTooltipText()
    end
    if isExternalPlaybackSourceMode() then
        return nil
    end
    local folderX = round(m.openFolderX - (m.openFolderW / 2))
    local folderY = round(m.y - (m.h / 2))
    if pointInside(x, y, folderX, folderY, m.openFolderW, m.h) then
        return 'open-folder', openFolderTooltipText()
    end
    if pointInside(x, y, m.repeatVisualX, m.repeatVisualY, m.repeatVisualW, m.repeatVisualH) then
        return 'repeat', repeatTooltipText()
    end
    if pointInside(x, y, m.shuffleVisualX, m.shuffleVisualY, m.shuffleVisualW, m.shuffleVisualH) then
        return 'shuffle', shuffleTooltipText()
    end
    return nil
end

local function syncPlaybackSelectionVariables(active, index, name, path)
    if active then
        setVariable('JukeboxPlaybackSelectedActive', 1)
        setVariable('JukeboxPlaybackSelectedSlotIndex', tonumber(index) or 0)
        setVariable('JukeboxPlaybackSelectedName', name or '')
        setVariable('JukeboxPlaybackSelectedPath', path or '')
    else
        setVariable('JukeboxPlaybackSelectedActive', 0)
        setVariable('JukeboxPlaybackSelectedSlotIndex', 0)
        setVariable('JukeboxPlaybackSelectedName', '')
        setVariable('JukeboxPlaybackSelectedPath', '')
    end
end

local function hideSelectedHighlight(redrawNow)
    setVariable('JukeboxDiscSlotSelectedX', 0)
    setVariable('JukeboxDiscSlotSelectedY', 0)
    setVariable('JukeboxDiscSlotSelectedSize', 0)
    setVariable('JukeboxDiscSlotSelectedHidden', 1)
    updateMeter('MeterJukeboxDiscSlotSelectedHighlight')
    if redrawNow ~= false then
        redraw()
    end
end

local function clearSelected(redrawNow)
    setVariable('JukeboxDiscSlotSelectedSlotIndex', 0)
    setVariable('JukeboxDiscSlotSelectedName', '')
    syncPlaybackSelectionVariables(false)
    hideSelectedHighlight(redrawNow)
end

local function updateSelected(index, redrawNow)
    local slot = slots[index]
    if not isSupported(slot) then
        clearSelected(redrawNow)
        return
    end

    setVariable('JukeboxDiscSlotSelectedSlotIndex', index)
    setVariable('JukeboxDiscSlotSelectedName', slot.name)
    syncPlaybackSelectionVariables(true, index, slot.name, slot.path)

    local ix, iy = slotCoordinates(index)
    if not ix or not iy then
        hideSelectedHighlight(redrawNow)
        return
    end

    local m = metrics()
    local cellSize = math.min(m.cellW, m.cellH)
    local offset = round(SELECT_HIGHLIGHT_OFFSET_BASE * m.scale)
    local size = math.max(1, round(cellSize + offset))
    local centerX = m.usableX + ((ix - 0.5) * m.cellW)
    local centerY = m.usableY + ((iy - 0.5) * m.cellH)
    local x = round(centerX - (size / 2))
    local y = round(centerY - (size / 2))

    setVariable('JukeboxDiscSlotSelectedX', x + contentX())
    setVariable('JukeboxDiscSlotSelectedY', y)
    setVariable('JukeboxDiscSlotSelectedSize', size)
    setVariable('JukeboxDiscSlotSelectedHidden', 0)
    updateMeter('MeterJukeboxDiscSlotSelectedHighlight')
    if redrawNow ~= false then
        redraw()
    end
end

local function syncSelectedAfterScan(redrawNow)
    local index = selectedIndex()
    if index >= 1 then
        local slot = slots[index]
        if isSupported(slot) and trim(slot.name) == selectedName() then
            updateSelected(index, redrawNow)
            return
        end
    end

    local playback = selectedPlaybackState()
    if playback.active then
        if playback.index >= 1 and slotMatchesPlaybackState(slots[playback.index], playback) then
            updateSelected(playback.index, redrawNow)
            return
        end
        for candidate = 1, highestSlot do
            if slotMatchesPlaybackState(slots[candidate], playback) then
                updateSelected(candidate, redrawNow)
                return
            end
        end
    end

    clearSelected(redrawNow)
end

local function discGeometry(index, slot)
    local ix, iy = slotCoordinates(index)
    local m = metrics()
    if not ix or not iy then
        return 0, 0, 0
    end

    local cellSize = math.min(m.cellW, m.cellH)
    local size = math.max(1, round(cellSize * DISC_SIZE_RATIO))
    local centerX = m.usableX + ((ix - 0.5) * m.cellW)
    local centerY = m.usableY + ((iy - 0.5) * m.cellH)
    local x = round(centerX - (size / 2))
    local y = round(centerY - (size / 2))
    if isPresent(slot) and not slot.supported then
        y = y - round((64 / 1024) * size)
    end
    return x, y, size
end

local function syncDiscMeters()
    for visibleIndex = 1, SLOTS_PER_PAGE do
        local suffix = meterSuffix(visibleIndex)
        local index = globalSlotIndex(visibleIndex)
        local slot = index and slots[index] or nil
        if isPresent(slot) then
            local x, y, size = discGeometry(index, slot)
            setVariable('JukeboxDiscSlotDisc' .. suffix .. 'X', x + contentX())
            setVariable('JukeboxDiscSlotDisc' .. suffix .. 'Y', y)
            setVariable('JukeboxDiscSlotDisc' .. suffix .. 'Size', size)
            if slot.supported then
                setVariable('JukeboxDiscSlotDisc' .. suffix .. 'Image', SKIN:GetVariable('JukeboxDiscSlotDiscImage', ''))
            else
                setVariable('JukeboxDiscSlotDisc' .. suffix .. 'Image', SKIN:GetVariable('JukeboxDiscSlotBrokenDiscImage', ''))
            end
            setVariable('JukeboxDiscSlotDisc' .. suffix .. 'Hidden', 0)
        else
            setVariable('JukeboxDiscSlotDisc' .. suffix .. 'Hidden', 1)
        end
        updateMeter('MeterJukeboxDiscSlotDisc' .. suffix)
    end
end
local function parsePairs(output)
    return EnsureJukeboxDiscSlotHelperResultModule().parseLinePairs(output)
end

local function measureOutput(measureName)
    local measure = SKIN:GetMeasure(measureName)
    if not measure then
        return ''
    end
    return tostring(measure:GetStringValue() or '')
end

local function scanMeasureOutput()
    return measureOutput('MeasureJukeboxDiscSlotScanRun')
end

local function clearSlots()
    slots = {}
    highestSlot = 0
    totalPages = 1
end

local function applyScanValues(values)
    clearSlots()
    highestSlot = math.max(0, math.floor(tonumber(values.DMEL_HIGHEST_SLOT) or 0))
    for index = 1, highestSlot do
        local prefix = 'DMEL_SLOT' .. tostring(index) .. '_'
        if trim(values[prefix .. 'PRESENT']) == '1' then
            local supported = trim(values[prefix .. 'SUPPORTED']) == '1'
            slots[index] = {
                present = true,
                supported = supported,
                name = trim(values[prefix .. 'NAME']),
                stem = trim(values[prefix .. 'STEM']),
                extension = trim(values[prefix .. 'EXT']),
                path = trim(values[prefix .. 'PATH']),
            }
        end
    end
    totalPages = calculateTotalPages()
    clampCurrentPageToContent(true)
end
local function jukeboxConfigName()
    local root = trim(SKIN:GetVariable('ROOTCONFIG', ''))
    if root ~= '' then
        return root .. '\\ExtraContent\\Jukebox'
    end

    local current = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
    local suffix = '\\DiscSlot'
    if current:sub(-#suffix) == suffix then
        return current:sub(1, #current - #suffix)
    end
    return current
end

local JukeboxDiscSlotConfigState = nil

local function jukeboxDiscSlotConfigState()
    if not JukeboxDiscSlotConfigState then
        JukeboxDiscSlotConfigState = dofile(SKIN:GetVariable('@', '') .. 'Defaults\\Runtime\\luas\\RainmeterConfigState.lua')
    end
    return JukeboxDiscSlotConfigState
end

function JukeboxDiscSlotIsRainmeterConfigActive(configName)
    return jukeboxDiscSlotConfigState().IsActive(SKIN, configName)
end

local function callJukebox(command)
    local config = jukeboxConfigName()
    if config == '' then
        return false
    end
    if not JukeboxDiscSlotIsRainmeterConfigActive(config) then
        return false
    end
    SKIN:Bang('!CommandMeasure', 'MeasureJukebox', command, config)
    return true
end

requestDiscSlotAlert = function(kind, detail, dedupeByDetail)
    kind = trim(kind)
    detail = trim(detail)
    if kind == '' then
        return false
    end
    return callJukebox(string.format('ShowDiscSlotAlert(%q,%q)', kind, detail))
end

local function volumeValueFromPoint(y)
    local m = pageControlMetrics()
    if m.volumeTrackH <= 0 then
        return currentVolumePercent()
    end
    local relative = (m.volumeTrackY + m.volumeTrackH - (tonumber(y) or 0)) / m.volumeTrackH
    return clampVolumePercent(relative * 100)
end

local function setDisplayedVolume(value)
    value = clampVolumePercent(value)
    if isExternalPlaybackSourceMode() then
        setVariable('JukeboxExternalVolume', tostring(value))
    else
        setVariable('JukeboxPlaybackVolume', tostring(value))
    end
end

local function applyVolumeFromPoint(y, screenX, screenY)
    if not volumeControlEnabled() then
        return false
    end
    local value = volumeValueFromPoint(y)
    setDisplayedVolume(value)
    syncPageMeters()
    if lastVolumeCommandValue ~= value then
        lastVolumeCommandValue = value
        callJukebox(string.format('SetPlaybackVolume(%q)', tostring(value)))
    end
    hideHover()
    showTooltip(volumeTooltipText(), screenX, screenY, true)
    redraw()
    return true
end

local function ensureRandomSeeded()
    if randomSeeded then
        return
    end
    randomSeeded = true
    math.randomseed(os.time() + highestSlot + currentPage)
    math.random()
    math.random()
end

local function supportedSlotIndices()
    local indices = {}
    for index = 1, highestSlot do
        if isSupported(slots[index]) then
            indices[#indices + 1] = index
        end
    end
    return indices
end

local function currentPlaybackSlotIndex()
    local playback = selectedPlaybackState()
    if playback.active then
        if playback.index >= 1 and slotMatchesPlaybackState(slots[playback.index], playback) then
            return playback.index
        end
        for index = 1, highestSlot do
            if slotMatchesPlaybackState(slots[index], playback) then
                return index
            end
        end
    end
    return selectedIndex()
end

local function nextSequentialSlotIndex(currentIndex)
    local indices = supportedSlotIndices()
    if #indices == 0 then
        return nil
    end
    currentIndex = tonumber(currentIndex) or 0
    for _, index in ipairs(indices) do
        if index > currentIndex then
            return index
        end
    end
    return indices[1]
end

local function nextRandomSlotIndex(currentIndex)
    local indices = supportedSlotIndices()
    if #indices == 0 then
        return nil
    end
    currentIndex = tonumber(currentIndex) or 0
    if #indices > 1 then
        local filtered = {}
        for _, index in ipairs(indices) do
            if index ~= currentIndex then
                filtered[#filtered + 1] = index
            end
        end
        if #filtered > 0 then
            indices = filtered
        end
    end
    ensureRandomSeeded()
    return indices[math.random(1, #indices)]
end

local function requestEndedPlaybackClear()
    return callJukebox('ClearEndedDiscSlotPlayback()')
end

local function requestPlayback(index, slot, action)
    if isExternalPlaybackSourceMode() then
        return false
    end
    if not isSupported(slot) then
        return false
    end
    action = trim(action):lower()
    if action ~= 'play' and action ~= 'pause' then
        return false
    end
    if action == 'play' and trim(slot.path) == '' then
        return false
    end
    return callJukebox(string.format('RequestDiscSlotPlayback(%d,%q,%q,%q)', tonumber(index) or 0, tostring(slot.name or ''), tostring(slot.path or ''), action))
end

local function requestUnsupportedModal(slot)
    local fileName = trim(slot and slot.name or '')
    if fileName == '' then
        fileName = trim(slot and slot.extension or '')
    end
    return callJukebox(string.format('ShowUnsupportedAudio(%q,%q)', fileName, SUPPORTED_EXTENSIONS))
end


local function clearVolumeDrag()
    volumeDragActive = false
    lastVolumeCommandValue = nil
end

local function resetInteractionState()
    mouseDownSlot = nil
    clearVolumeDrag()
    hideHover()
    hideTooltip(true)
end

function RetryExternalCoverClick()
    local shouldRetry = externalCoverLoadFailed
    resetInteractionState()
    if not shouldRetry then
        return true
    end
    resetExternalCoverStability()
    local retryNonce = (tonumber(SKIN:GetVariable('JukeboxExternalCoverRetryNonce', '0')) or 0) + 1
    if retryNonce > 999999 then
        retryNonce = 1
    end
    setVariable('JukeboxExternalCoverFetchFailed', '0')
    setVariable('JukeboxExternalCoverFailureIdentity', '')
    setVariable('JukeboxExternalCoverRetryNonce', tostring(retryNonce))
    requestExternalCoverRefresh(table.concat({ 'manual-retry', tostring(retryNonce), tostring(os.time() or 0) }, string.char(31)))
    local sent = callJukebox('RetryExternalCoverFetch()')
    syncExternalCoverMeters()
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
    return sent
end

function IgnoreExternalCoverClick()
    return RetryExternalCoverClick()
end
