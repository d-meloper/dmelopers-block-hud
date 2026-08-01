-- Split from ExtraContent\Jukebox\DiscSlot\JukeboxDiscSlot.lua lines 844-1554.
local function clampCurrentPageToContent(persist)
    totalPages = calculateTotalPages()
    if currentPage >= 1 and currentPage <= totalPages then
        return
    end

    local playback = selectedPlaybackState()
    if playback.active and slotMatchesPlaybackState(slots[playback.index], playback) then
        local playbackPage = pageForSlot(playback.index)
        if playbackPage >= 1 and playbackPage <= totalPages then
            currentPage = playbackPage
        else
            currentPage = 1
        end
    else
        currentPage = 1
    end

    if persist ~= false then
        persistCurrentPage()
    end
end

local function pageControlMetrics()
    local m = metrics()
    local slotW = m.slotW
    local slotH = m.slotH
    local gap = math.max(0, numberVar('JukeboxDiscSlotGap', round(40 * m.scale)))
    local controlH = math.max(12, round(18 * m.scale))
    local buttonW = math.max(18, round(24 * m.scale))
    local buttonHitW = math.max(buttonW + round(16 * m.scale), round(36 * m.scale))
    local buttonHitH = math.max(controlH + round(12 * m.scale), round(28 * m.scale))
    local labelW = math.max(46, round(64 * m.scale))
    local openFolderW = math.max(60, round(84 * m.scale))
    local openFolderHitW = math.max(openFolderW + round(12 * m.scale), round(72 * m.scale))
    local iconSize = math.max(14, round(18 * m.scale))
    local iconHitW = math.max(iconSize + round(18 * m.scale), round(34 * m.scale))
    local iconGap = math.max(10, round(20 * m.scale))
    local panelGap = math.max(10, round(18 * m.scale))
    local totalW = (buttonW * 2) + labelW
    local controlCenterX = m.usableX + (m.cellW * 2.5)
    local x = round(controlCenterX - (totalW / 2))
    local shuffleX = round(x - panelGap - iconSize)
    local repeatX = round(shuffleX - iconGap - iconSize)
    local openFolderCenterX = round(repeatX - panelGap - (openFolderW / 2))
    local y = round(slotH + ((gap - controlH) / 2) + round(15 * m.scale))
    if y < slotH then
        y = slotH
    end
    local iconY = round(y + (controlH / 2) - (iconSize / 2))
    local repeatIconSize = math.max(iconSize + 1, round(iconSize * 1.15))
    local actionIconSize = math.max(repeatIconSize + 1, round(repeatIconSize * 1.3))
    local topActionGapY = math.max(16, round(24 * m.scale))
    local topActionHitW = math.max(actionIconSize + round(18 * m.scale), round(34 * m.scale))
    local topActionHitH = topActionHitW
    local repeatX = round(repeatX - ((repeatIconSize - iconSize) / 2))
    local repeatY = round(iconY - ((repeatIconSize - iconSize) / 2))
    local iconLeft = math.max(1, round(repeatIconSize * 0.12))
    local iconRight = math.max(iconLeft + 1, round(repeatIconSize * 0.88))
    local iconTop = math.max(1, round(repeatIconSize * 0.24))
    local iconBottom = math.max(iconTop + 1, round(repeatIconSize * 0.76))
    local actionIconLeft = math.max(1, round(actionIconSize * 0.12))
    local actionIconRight = math.max(actionIconLeft + 1, round(actionIconSize * 0.88))
    local actionIconTop = math.max(1, round(actionIconSize * 0.24))
    local actionIconBottom = math.max(actionIconTop + 1, round(actionIconSize * 0.76))
    local side = actionSide()
    local actionGutter = math.max(actionIconSize, round(m.actionGutter or 0))
    local actionSpan = math.max(1, actionIconRight - actionIconLeft)
    local currentActionOffset = math.max(actionIconSize, round(actionGutter * 0.6))
    local actionGap = math.max(0, currentActionOffset - actionSpan)
    local actionOffset = actionSpan + round(actionGap * 0.8)
    local topActionX = side == 'left' and (-actionOffset - actionIconLeft) or (slotW + actionOffset - actionIconRight)
    local topActionCenterX = round(topActionX + ((actionIconLeft + actionIconRight) / 2))
    local closeY = round(m.usableY + round(6 * m.scale))
    local optionsY = round(closeY + actionIconSize + topActionGapY)
    local minimizeY = round(m.usableY + m.usableH - actionIconSize - round(6 * m.scale))
    local minMinimizeY = optionsY + ((actionIconSize + topActionGapY) * 2)
    if minimizeY < minMinimizeY then
        minimizeY = minMinimizeY
    end
    local closeCenterY = round(closeY + (actionIconSize / 2))
    local closeIconLeft = math.max(1, round(actionIconSize * 0.26))
    local closeIconRight = math.max(closeIconLeft + 1, round(actionIconSize * 0.74))
    local closeIconTop = math.max(1, round(actionIconSize * 0.26))
    local closeIconBottom = math.max(closeIconTop + 1, round(actionIconSize * 0.74))
    local optionsIconSize = 22
    local settingsIconSize = 22
    local settingsY = round(minimizeY - actionIconSize - topActionGapY)
    local settingsCenterY = round(settingsY + (actionIconSize / 2))
    local optionsCenterY = round(optionsY + (actionIconSize / 2))
    local volumePercent = currentVolumePercent()
    local volumeEnabled = volumeControlEnabled()
    local volumeGapY = math.max(7, round(9 * m.scale))
    local volumeTrackW = math.max(3, round(4 * m.scale))
    local volumeTrackRadius = math.max(1, round(volumeTrackW / 2))
    local volumeTrackY = round(optionsY + actionIconSize + volumeGapY)
    local volumeTrackBottom = round(settingsY - volumeGapY)
    local minVolumeTrackH = math.max(18, round(28 * m.scale))
    if volumeTrackBottom < volumeTrackY + minVolumeTrackH then
        local centerY = round((optionsY + actionIconSize + settingsY) / 2)
        volumeTrackY = round(centerY - (minVolumeTrackH / 2))
        volumeTrackBottom = volumeTrackY + minVolumeTrackH
    end
    local volumeTrackH = math.max(minVolumeTrackH, volumeTrackBottom - volumeTrackY)
    local reducedVolumeTrackH = math.max(minVolumeTrackH, round(volumeTrackH * 0.8))
    local volumeTrackCenterY = round(volumeTrackY + (volumeTrackH / 2))
    volumeTrackH = reducedVolumeTrackH
    volumeTrackY = round(volumeTrackCenterY - (volumeTrackH / 2))
    local volumeTrackX = round(topActionCenterX - (volumeTrackW / 2))
    local volumeHitW = topActionHitW
    local volumeHitH = math.max(topActionHitH, volumeTrackH + round(14 * m.scale))
    local volumeHitX = round(topActionCenterX - (volumeHitW / 2))
    local volumeHitY = round(volumeTrackY + (volumeTrackH / 2) - (volumeHitH / 2))
    local volumeFillH = round(volumeTrackH * (volumePercent / 100))
    if volumeFillH < 0 then
        volumeFillH = 0
    elseif volumeFillH > volumeTrackH then
        volumeFillH = volumeTrackH
    end
    local volumeFillY = round(volumeTrackY + volumeTrackH - volumeFillH)
    local volumeThumbRadius = math.max(3, round(4 * m.scale))
    local volumeThumbY = round(volumeTrackY + volumeTrackH - (volumeTrackH * (volumePercent / 100)))
    local volumeTrackColor = volumeEnabled and '255,255,255,80' or '255,255,255,45'
    local volumeFillColor = volumeEnabled and '255,255,255,230' or '255,255,255,85'
    local volumeThumbColor = volumeEnabled and '255,255,255,230' or '255,255,255,95'
    local iconArrowLeftNear = math.min(iconRight - 1, round(repeatIconSize * 0.32))
    local iconArrowDelta = math.max(1, round(repeatIconSize * 0.22 * 0.64))
    local baseIconArrowDelta = math.max(2, round(iconSize * 0.22))
    local iconLoopW = math.max(1, iconRight - iconLeft)
    local iconLoopH = math.max(1, iconBottom - iconTop)
    local iconLoopRadiusX = math.max(2, math.min(round(repeatIconSize * 0.22), round(iconLoopW / 2)))
    local iconLoopRadiusY = math.max(2, math.min(round(repeatIconSize * 0.22), round(iconLoopH / 2)))
    local shuffleLeft = math.max(1, round(iconSize * 0.04))
    local shuffleRight = math.max(shuffleLeft + 1, round(iconSize * 0.96))
    local shuffleTop = math.max(1, round(iconSize * 0.20))
    local shuffleBottom = math.max(shuffleTop + 1, round(iconSize * 0.80))
    local shuffleMidLeft = math.max(shuffleLeft + 1, round(iconSize * 0.28))
    local shuffleMidRight = math.max(shuffleMidLeft + 1, round(iconSize * 0.72))
    local shuffleArrowDelta = math.max(1, round(baseIconArrowDelta * 0.5))
    local shuffleArrowNear = math.max(shuffleLeft + 1, shuffleRight - shuffleArrowDelta)
    local mode = currentRepeatMode()
    return {
        openFolderX = openFolderCenterX,
        openFolderW = openFolderW,
        openFolderHitX = round(openFolderCenterX - (openFolderHitW / 2)),
        openFolderHitW = openFolderHitW,
        repeatX = repeatX,
        repeatY = repeatY,
        repeatHitX = round(repeatX + (repeatIconSize / 2) - (iconHitW / 2)),
        repeatHitW = iconHitW,
        repeatVisualX = repeatX,
        repeatVisualY = repeatY,
        repeatVisualW = repeatIconSize,
        repeatVisualH = repeatIconSize,
        repeatColor = mode == 'off' and '255,255,255,90' or '255,255,255,230',
        repeatOneHidden = mode == 'one' and 0 or 1,
        repeatOneX = round(repeatX + (repeatIconSize * 1.2)),
        repeatOneY = round(repeatY + (repeatIconSize * 0.78)),
        repeatOneFontSize = math.max(6, round(7 * m.scale)),
        shuffleX = shuffleX,
        shuffleY = iconY,
        shuffleHitX = round(shuffleX + (iconSize / 2) - (iconHitW / 2)),
        shuffleHitW = iconHitW,
        shuffleVisualX = shuffleX,
        shuffleVisualY = iconY,
        shuffleVisualW = iconSize,
        shuffleVisualH = iconSize,
        shuffleColor = currentShuffleEnabled() and '255,255,255,230' or '255,255,255,90',
        actionSide = side,
        closeX = topActionX,
        closeY = closeY,
        closeHitX = round(topActionCenterX - (topActionHitW / 2)),
        closeHitY = round(closeCenterY - (topActionHitH / 2)),
        minimizeX = topActionX,
        minimizeY = minimizeY,
        minimizeHitX = round(topActionCenterX - (topActionHitW / 2)),
        minimizeHitY = round(minimizeY + (actionIconSize / 2) - (topActionHitH / 2)),
        minimizeIconLeft = math.max(1, round(actionIconSize * 0.25)),
        minimizeIconRight = math.max(2, round(actionIconSize * 0.75)),
        minimizeIconCenterX = math.max(1, round(actionIconSize * 0.5)),
        minimizeIconTop = math.max(1, round(actionIconSize * 0.292)),
        minimizeIconChevronY = math.max(2, round(actionIconSize * 0.542)),
        minimizeIconBottom = math.max(3, round(actionIconSize * 0.708)),
        minimizeIconStroke = math.max(1, round(actionIconSize * 0.083)),
        settingsX = round(topActionCenterX - (settingsIconSize / 2)),
        settingsY = round(settingsCenterY - (settingsIconSize / 2)),
        settingsHitX = round(topActionCenterX - (topActionHitW / 2)),
        settingsHitY = round(settingsCenterY - (topActionHitH / 2)),
        volumeHidden = 0,
        volumeHitX = volumeHitX,
        volumeHitY = volumeHitY,
        volumeHitW = volumeHitW,
        volumeHitH = volumeHitH,
        volumeTrackX = volumeTrackX,
        volumeTrackY = volumeTrackY,
        volumeTrackW = volumeTrackW,
        volumeTrackH = volumeTrackH,
        volumeTrackRadius = volumeTrackRadius,
        volumeFillX = volumeTrackX,
        volumeFillY = volumeFillY,
        volumeFillW = volumeTrackW,
        volumeFillH = volumeFillH,
        volumeFillHidden = volumeFillH <= 0 and 1 or 0,
        volumeThumbX = topActionCenterX,
        volumeThumbY = volumeThumbY,
        volumeThumbRadius = volumeThumbRadius,
        volumeTrackColor = volumeTrackColor,
        volumeFillColor = volumeFillColor,
        volumeThumbColor = volumeThumbColor,
        volumeCursor = volumeEnabled and 1 or 0,
        optionsToggleX = round(topActionCenterX - (optionsIconSize / 2)),
        optionsToggleY = round(optionsCenterY - (optionsIconSize / 2)),
        optionsToggleHitX = round(topActionCenterX - (topActionHitW / 2)),
        optionsToggleHitY = round(optionsCenterY - (topActionHitH / 2)),
        topActionHitW = topActionHitW,
        topActionHitH = topActionHitH,
        topActionColor = '255,255,255,230',
        topActionFontSize = math.max(10, round(16 * m.scale)),
        iconStroke = math.max(1, round(2 * m.scale)),
        closeIconLeft = closeIconLeft,
        closeIconRight = closeIconRight,
        closeIconTop = closeIconTop,
        closeIconBottom = closeIconBottom,
        actionIconLeft = actionIconLeft,
        actionIconRight = actionIconRight,
        actionIconTop = actionIconTop,
        actionIconBottom = actionIconBottom,
        iconLeft = iconLeft,
        iconTop = iconTop,
        iconBottom = iconBottom,
        iconLoopW = iconLoopW,
        iconLoopH = iconLoopH,
        iconLoopRadiusX = iconLoopRadiusX,
        iconLoopRadiusY = iconLoopRadiusY,
        iconArrowLeftNear = iconArrowLeftNear,
        iconBottomArrowUp = iconBottom - iconArrowDelta,
        iconBottomArrowDown = iconBottom + iconArrowDelta,
        shuffleLeft = shuffleLeft,
        shuffleRight = shuffleRight,
        shuffleTop = shuffleTop,
        shuffleBottom = shuffleBottom,
        shuffleMidLeft = shuffleMidLeft,
        shuffleMidRight = shuffleMidRight,
        shuffleArrowNear = shuffleArrowNear,
        shuffleTopArrowUp = math.max(0, shuffleTop - shuffleArrowDelta),
        shuffleTopArrowDown = shuffleTop + shuffleArrowDelta,
        shuffleBottomArrowUp = shuffleBottom - shuffleArrowDelta,
        shuffleBottomArrowDown = shuffleBottom + shuffleArrowDelta,
        prevX = round(x + (buttonW / 2)),
        labelX = round(x + buttonW + (labelW / 2)),
        nextX = round(x + buttonW + labelW + (buttonW / 2)),
        y = round(y + (controlH / 2)),
        prevHitX = round(x + (buttonW / 2) - (buttonHitW / 2)),
        nextHitX = round(x + buttonW + labelW + (buttonW / 2) - (buttonHitW / 2)),
        hitY = round(y + (controlH / 2) - (buttonHitH / 2)),
        hitW = buttonHitW,
        hitH = buttonHitH,
        h = controlH,
        fontSize = math.max(8, round(12 * m.scale)),
    }
end

local function externalPlaybackConnected()
    return boolVariable('JukeboxExternalBridgeActive') and trim(SKIN:GetVariable('JukeboxExternalStatus', '0')) == '1'
end

local function externalPlaybackPlayable()
    return externalPlaybackConnected() and boolVariable('JukeboxExternalSupportsPlayPause')
end

function externalPrimaryTransportControl(control)
    return control == 'previous' or control == 'playpause' or control == 'next'
end

local function externalControlSupported(control)
    if not isExternalPlaybackSourceMode() or not externalPlaybackConnected() then
        return false
    end
    if control == 'previous' then
        return boolVariable('JukeboxExternalSupportsSkipPrevious')
    elseif control == 'playpause' then
        return boolVariable('JukeboxExternalSupportsPlayPause')
    elseif control == 'next' then
        return boolVariable('JukeboxExternalSupportsSkipNext')
    elseif control == 'repeat' then
        return boolVariable('JukeboxExternalSupportsToggleRepeatMode')
    elseif control == 'shuffle' then
        return boolVariable('JukeboxExternalSupportsToggleShuffleActive')
    end
    return false
end

function externalControlClickable(control)
    if not isExternalPlaybackSourceMode() then
        return false
    end
    if externalPrimaryTransportControl(control) then
        return true
    end
    return externalPlaybackConnected() and externalControlSupported(control)
end

local function externalTransportControlLabel(control)
    if control == 'previous' then
        return externalPreviousTooltipText()
    elseif control == 'playpause' then
        return externalPlayPauseTooltipText()
    elseif control == 'next' then
        return externalNextTooltipText()
    elseif control == 'repeat' then
        return externalRepeatTooltipLabel()
    elseif control == 'shuffle' then
        return externalShuffleTooltipLabel()
    end
    return ''
end

local function externalUnsupportedTooltipText(control)
    local label = externalTransportControlLabel(control)
    if label == '' then
        return ''
    end
    return localizedFormatText('Loc_JukeboxExternal_UnsupportedFormat', '*%1 is not supported by this app', { label })
end

local function externalTransportTooltipText(control)
    if not externalControlSupported(control) and not externalControlClickable(control) then
        return externalUnsupportedTooltipText(control)
    end
    if control == 'repeat' then
        return repeatTooltipText()
    elseif control == 'shuffle' then
        return shuffleTooltipText()
    end
    return externalTransportControlLabel(control)
end

local function externalTransportControlVisible(control)
    if control == 'repeat' or control == 'shuffle' then
        return optionsVisible()
    end
    return true
end
local function externalTransportColor(control)
    if not externalControlSupported(control) then
        if externalControlClickable(control) then
            return '255,255,255,160'
        end
        return '255,255,255,70'
    end
    if control == 'repeat' and currentRepeatMode() == 'off' then
        return '255,255,255,110'
    end
    if control == 'shuffle' and not currentShuffleEnabled() then
        return '255,255,255,110'
    end
    return '255,255,255,230'
end

local function pixelationBlockSize()
    return math.max(1, round(numberVar('JukeboxDiscSlotExternalCoverPixelBlock', 3)))
end

local function pixelationFitMode()
    local mode = trim(SKIN:GetVariable('JukeboxDiscSlotExternalCoverFitMode', 'Cover')):lower()
    if mode == 'contain' then
        return 'Contain'
    elseif mode == 'stretch' then
        return 'Stretch'
    end
    return 'Cover'
end

local function pixelationSampleMode()
    local mode = trim(SKIN:GetVariable('JukeboxDiscSlotExternalCoverSampleMode', 'Average')):lower()
    if mode == 'nearest' then
        return 'Nearest'
    end
    return 'Average'
end

local function externalCoverFileFingerprint(coverImage)
    local path = trim(coverImage)
    if path == '' then
        return ''
    end
    if trim(JukeboxDiscSlotExternalCoverFingerprint.hash) ~= '' then
        return trim(JukeboxDiscSlotExternalCoverFingerprint.hash)
    end
    return 'path-pending:' .. rollingHash(path)
end

local function resetExternalCoverStability()
    externalCoverStableKey = ''
    externalCoverStableCount = 0
end

local function requestExternalCoverRefresh(refreshKey)
    refreshKey = tostring(refreshKey or '')
    if externalCoverRefreshKey ~= refreshKey then
        externalCoverRefreshKey = refreshKey
        externalCoverRefreshTicksRemaining = EXTERNAL_COVER_REFRESH_MAX_TICKS
    elseif externalCoverRefreshTicksRemaining <= 0 then
        externalCoverRefreshTicksRemaining = EXTERNAL_COVER_REFRESH_MAX_TICKS
    end
end

local function clearExternalCoverRefresh()
    externalCoverRefreshKey = ''
    externalCoverRefreshTicksRemaining = 0
end

local function externalCoverMediaIdentity(coverImage)
    local separator = string.char(31)
    local player = trim(SKIN:GetVariable('JukeboxExternalPlayer', ''))
    local title = trim(SKIN:GetVariable('JukeboxExternalTitle', ''))
    local artist = trim(SKIN:GetVariable('JukeboxExternalArtist', ''))
    local album = trim(SKIN:GetVariable('JukeboxExternalAlbum', ''))
    if title ~= '' or artist ~= '' or album ~= '' then
        return table.concat({ player, title, artist, album }, separator)
    end
    return table.concat({ player, trim(coverImage), trim(SKIN:GetVariable('JukeboxExternalDuration', '0')) }, separator)
end

function JukeboxDiscSlotExternalCoverFingerprint.trackingKey(coverImage)
    local path = trim(coverImage)
    if path == '' then
        return ''
    end
    return table.concat({ path, externalCoverMediaIdentity(path) }, string.char(31))
end

function JukeboxDiscSlotExternalCoverFingerprint.reset()
    JukeboxDiscSlotExternalCoverFingerprint.running = false
    JukeboxDiscSlotExternalCoverFingerprint.token = ''
    JukeboxDiscSlotExternalCoverFingerprint.key = ''
    JukeboxDiscSlotExternalCoverFingerprint.hash = ''
    JukeboxDiscSlotExternalCoverFingerprint.length = ''
    JukeboxDiscSlotExternalCoverFingerprint.format = ''
    JukeboxDiscSlotExternalCoverFingerprint.refreshTicks = 0
    JukeboxDiscSlotExternalCoverFingerprint.cooldownTicks = 0
end

function JukeboxDiscSlotExternalCoverFingerprint.updateTracking(coverImage)
    local key = JukeboxDiscSlotExternalCoverFingerprint.trackingKey(coverImage)
    if key == '' then
        JukeboxDiscSlotExternalCoverFingerprint.currentKey = ''
        JukeboxDiscSlotExternalCoverFingerprint.currentPath = ''
        JukeboxDiscSlotExternalCoverFingerprint.reset()
        JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks = 0
        return ''
    end
    if JukeboxDiscSlotExternalCoverFingerprint.currentKey ~= key then
        JukeboxDiscSlotExternalCoverFingerprint.previousKey = JukeboxDiscSlotExternalCoverFingerprint.currentKey
        JukeboxDiscSlotExternalCoverFingerprint.previousPath = JukeboxDiscSlotExternalCoverFingerprint.currentPath
        JukeboxDiscSlotExternalCoverFingerprint.previousHash = JukeboxDiscSlotExternalCoverFingerprint.hash
        JukeboxDiscSlotExternalCoverFingerprint.currentKey = key
        JukeboxDiscSlotExternalCoverFingerprint.currentPath = trim(coverImage)
        JukeboxDiscSlotExternalCoverFingerprint.hash = ''
        JukeboxDiscSlotExternalCoverFingerprint.length = ''
        JukeboxDiscSlotExternalCoverFingerprint.format = ''
        JukeboxDiscSlotExternalCoverFingerprint.running = false
        JukeboxDiscSlotExternalCoverFingerprint.token = ''
        JukeboxDiscSlotExternalCoverFingerprint.key = ''
        JukeboxDiscSlotExternalCoverFingerprint.refreshTicks = JukeboxDiscSlotExternalCoverFingerprint.refreshLimit
        JukeboxDiscSlotExternalCoverFingerprint.cooldownTicks = 0
        JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks = JukeboxDiscSlotExternalCoverFingerprint.reuseGraceLimit
        resetExternalCoverStability()
    end
    return key
end

function JukeboxDiscSlotExternalCoverFingerprint.buildArgs(coverImage, token)
    return table.concat({
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(fingerprintHelperPath()),
        '-SourcePath', quotePowerShellArgument(coverImage),
        '-Token', quotePowerShellArgument(token),
    }, ' ')
end

function JukeboxDiscSlotExternalCoverFingerprint.request(coverImage, trackingKey)
    if JukeboxDiscSlotExternalCoverFingerprint.running then
        return true
    end
    if trim(coverImage) == '' or trim(trackingKey) == '' then
        return false
    end
    if not SKIN:GetMeasure('MeasureJukeboxDiscSlotFingerprintRun') then
        SKIN:Bang('!Log', 'Jukebox external cover fingerprint measure is missing.', 'Warning')
        return false
    end

    JukeboxDiscSlotExternalCoverFingerprint.sequence = (tonumber(JukeboxDiscSlotExternalCoverFingerprint.sequence) or 0) + 1
    if JukeboxDiscSlotExternalCoverFingerprint.sequence > 999999 then
        JukeboxDiscSlotExternalCoverFingerprint.sequence = 1
    end
    local token = 'external-cover-fingerprint-' .. tostring(JukeboxDiscSlotExternalCoverFingerprint.sequence)
    JukeboxDiscSlotExternalCoverFingerprint.running = true
    JukeboxDiscSlotExternalCoverFingerprint.token = token
    JukeboxDiscSlotExternalCoverFingerprint.key = trackingKey
    setVariable('JukeboxDiscSlotFingerprintArgs', JukeboxDiscSlotExternalCoverFingerprint.buildArgs(coverImage, token))
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxDiscSlotFingerprintRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotFingerprintRun', 'Run')
    return true
end

function JukeboxDiscSlotExternalCoverFingerprint.needsRefresh()
    if JukeboxDiscSlotExternalCoverFingerprint.refreshTicks <= 0 then
        return false
    end
    if JukeboxDiscSlotExternalCoverFingerprint.cooldownTicks > 0 then
        JukeboxDiscSlotExternalCoverFingerprint.cooldownTicks = JukeboxDiscSlotExternalCoverFingerprint.cooldownTicks - 1
        return false
    end
    JukeboxDiscSlotExternalCoverFingerprint.cooldownTicks = JukeboxDiscSlotExternalCoverFingerprint.refreshInterval
    return true
end

function JukeboxDiscSlotExternalCoverFingerprint.ready(coverImage)
    local trackingKey = JukeboxDiscSlotExternalCoverFingerprint.updateTracking(coverImage)
    if trackingKey == '' then
        return false
    end

    if JukeboxDiscSlotExternalCoverFingerprint.hash == '' then
        JukeboxDiscSlotExternalCoverFingerprint.request(coverImage, trackingKey)
        return false
    end
    if JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks > 0
        and JukeboxDiscSlotExternalCoverFingerprint.previousPath ~= ''
        and trim(coverImage) == JukeboxDiscSlotExternalCoverFingerprint.previousPath
        and JukeboxDiscSlotExternalCoverFingerprint.previousHash ~= ''
        and JukeboxDiscSlotExternalCoverFingerprint.hash == JukeboxDiscSlotExternalCoverFingerprint.previousHash then
        JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks = JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks - 1
        if JukeboxDiscSlotExternalCoverFingerprint.needsRefresh() then
            JukeboxDiscSlotExternalCoverFingerprint.request(coverImage, trackingKey)
        end
        return JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks <= 0
    end
    if JukeboxDiscSlotExternalCoverFingerprint.needsRefresh() then
        JukeboxDiscSlotExternalCoverFingerprint.request(coverImage, trackingKey)
    end
    return true
end

function JukeboxDiscSlotExternalCoverFingerprint.applyResult(values)
    values = values or {}
    local token = trim(values.DMEL_TOKEN)
    local expectedToken = trim(JukeboxDiscSlotExternalCoverFingerprint.token)
    local status = upper(values.DMEL_STATUS)
    local hash = trim(values.DMEL_SOURCE_FINGERPRINT)
    local pendingKey = JukeboxDiscSlotExternalCoverFingerprint.key
    JukeboxDiscSlotExternalCoverFingerprint.running = false
    JukeboxDiscSlotExternalCoverFingerprint.token = ''
    JukeboxDiscSlotExternalCoverFingerprint.key = ''

    if token == '' or token ~= expectedToken then
        return false
    end
    if status ~= 'OK' or hash == '' then
        return false
    end
    if pendingKey ~= '' and pendingKey == JukeboxDiscSlotExternalCoverFingerprint.currentKey then
        if JukeboxDiscSlotExternalCoverFingerprint.hash ~= '' and JukeboxDiscSlotExternalCoverFingerprint.hash ~= hash then
            resetExternalCoverStability()
        end
        JukeboxDiscSlotExternalCoverFingerprint.hash = hash
        JukeboxDiscSlotExternalCoverFingerprint.length = trim(values.DMEL_SOURCE_LENGTH)
        JukeboxDiscSlotExternalCoverFingerprint.format = trim(values.DMEL_SOURCE_FORMAT)
        if JukeboxDiscSlotExternalCoverFingerprint.previousHash == '' or JukeboxDiscSlotExternalCoverFingerprint.hash ~= JukeboxDiscSlotExternalCoverFingerprint.previousHash then
            JukeboxDiscSlotExternalCoverFingerprint.reuseGraceTicks = 0
        end
        return true
    end
    return false
end

local function externalCoverReadyForPixelation(coverImage)
    local path = trim(coverImage)
    local fingerprint = externalCoverFileFingerprint(path)
    if path == '' or fingerprint == '' then
        resetExternalCoverStability()
        return false, false
    end

    local key = path .. string.char(31) .. fingerprint
    if externalCoverStableKey ~= key then
        externalCoverStableKey = key
        externalCoverStableCount = 1
        return false, true
    end

    externalCoverStableCount = externalCoverStableCount + 1
    return externalCoverStableCount >= EXTERNAL_COVER_STABLE_REQUIRED_COUNT, true
end

local function externalCoverSignature(coverImage, coverSize)
    local separator = string.char(31)
    return table.concat({
        trim(coverImage),
        externalCoverFileFingerprint(coverImage),
        externalCoverMediaIdentity(coverImage),
        trim(SKIN:GetVariable('JukeboxExternalCoverRetryNonce', '0')),
        tostring(coverSize),
        tostring(pixelationBlockSize()),
        pixelationFitMode(),
        pixelationSampleMode(),
    }, separator)
end

local function logPixelationFailure(result)
    if not result or (not result.newFailure and not result.warning) then
        return false
    end
    local detail = trim(result.message)
    if detail == '' then
        detail = 'unknown error'
    end
    SKIN:Bang('!Log', 'Jukebox external cover pixelation failed: ' .. detail, 'Warning')
    return true
end
local function externalCoverDisplayImage(coverImage, fallbackImage, coverSize)
    coverImage = trim(coverImage)
    if coverImage == '' then
        return fallbackImage, false, false
    end

    local pixelator = loadImagePixelation()
    if not pixelator then
        return brokenThumbnailImage(fallbackImage), true, false
    end

    local blockSize = pixelationBlockSize()
    local fitMode = pixelationFitMode()
    local sampleMode = pixelationSampleMode()
    local result = pixelator:requestImage({
        sourcePath = coverImage,
        fallbackPath = fallbackImage,
        width = coverSize,
        height = coverSize,
        blockSize = blockSize,
        fitMode = fitMode,
        sampleMode = sampleMode,
        signature = externalCoverSignature(coverImage, coverSize),
    })
    logPixelationFailure(result)
    if result and result.failed then
        return brokenThumbnailImage(fallbackImage), true, false
    end
    if result and (result.pending or result.started or result.queued) then
        return loadingThumbnailImage(fallbackImage), false, true
    end

    local displayPath = trim(result and result.displayPath or '')
    if displayPath == '' then
        SKIN:Bang('!Log', 'Jukebox external cover display path missing.', 'Warning')
        return brokenThumbnailImage(fallbackImage), true, false
    end
    return displayPath, false, false
end

local function syncExternalCoverMeters()
    local m = metrics()
    local external = isExternalPlaybackSourceMode()
    local gridImage = trim(SKIN:GetVariable('JukeboxDiscSlotGridImage', ''))
    local thumbnailImage = trim(SKIN:GetVariable('JukeboxDiscSlotThumbnailImage', gridImage))
    local fallbackImage = thumbnailImage ~= '' and thumbnailImage or gridImage
    local coverImage = trim(SKIN:GetVariable('JukeboxExternalCover', ''))
    local frameBase = 310
    local mediaBase = 280
    local frameSize = math.max(1, math.min(m.slotW, m.slotH))
    local scale = frameSize / frameBase
    local coverSize = math.max(1, round(mediaBase * scale))
    local coverX = round((m.slotW - coverSize) / 2)
    local coverY = round((m.slotH - coverSize) / 2)
    local displayImage = fallbackImage
    local coverFailed = false
    local coverPending = false
    local externalPlayable = external and externalPlaybackPlayable()
    local failureIdentity = trim(SKIN:GetVariable('JukeboxExternalCoverFailureIdentity', ''))
    local fetchFailed = externalPlayable
        and boolVariable('JukeboxExternalCoverFetchFailed')
        and failureIdentity ~= ''
        and failureIdentity == externalCoverMediaIdentity(coverImage)
    local showExternalCover = externalPlayable and coverImage ~= '' and not fetchFailed
    local coverReady = false
    local coverReadable = false
    if showExternalCover then
        local fingerprintReady = JukeboxDiscSlotExternalCoverFingerprint.ready(coverImage)
        if fingerprintReady then
            coverReady, coverReadable = externalCoverReadyForPixelation(coverImage)
        else
            coverReadable = true
            coverPending = true
        end
    else
        JukeboxDiscSlotExternalCoverFingerprint.updateTracking('')
        resetExternalCoverStability()
    end
    if fetchFailed then
        displayImage = brokenThumbnailImage(fallbackImage)
        coverFailed = true
        coverPending = false
    elseif showExternalCover and coverReady then
        displayImage, coverFailed, coverPending = externalCoverDisplayImage(coverImage, fallbackImage, coverSize)
    elseif showExternalCover and coverReadable then
        displayImage = loadingThumbnailImage(fallbackImage)
        coverPending = true
    end
    externalCoverLoadFailed = fetchFailed or (showExternalCover and coverReady and coverFailed) or false
    if coverPending then
        requestExternalCoverRefresh(table.concat({ coverImage, externalCoverStableKey, trim(SKIN:GetVariable('JukeboxExternalCoverRetryNonce', '0')), tostring(coverSize) }, string.char(31)))
    else
        clearExternalCoverRefresh()
    end
    if showExternalCover and JukeboxDiscSlotExternalCoverFingerprint.refreshTicks > 0 then
        JukeboxDiscSlotExternalCoverFingerprint.refreshTicks = math.max(0, JukeboxDiscSlotExternalCoverFingerprint.refreshTicks - 1)
        if not coverPending then
            requestExternalCoverRefresh(table.concat({ coverImage, JukeboxDiscSlotExternalCoverFingerprint.hash, tostring(JukeboxDiscSlotExternalCoverFingerprint.refreshTicks), tostring(coverSize) }, string.char(31)))
        end
    end
    local coverVisible = fetchFailed or (showExternalCover and (coverReady or coverReadable))

    setVariable('JukeboxDiscSlotImage', external and fallbackImage or gridImage)
    setVariable('JukeboxDiscSlotExternalCoverImage', displayImage)
    setVariable('JukeboxDiscSlotExternalCoverX', coverX + contentX())
    setVariable('JukeboxDiscSlotExternalCoverY', coverY)
    setVariable('JukeboxDiscSlotExternalCoverW', coverSize)
    setVariable('JukeboxDiscSlotExternalCoverH', coverSize)
    setVariable('JukeboxDiscSlotExternalCoverHidden', coverVisible and 0 or 1)
    updateMeter('MeterJukeboxDiscSlot')
    updateMeter('MeterJukeboxDiscSlotExternalCover')
end

local function tickExternalCoverRefresh()
    if externalCoverRefreshTicksRemaining <= 0 then
        return false
    end

    syncExternalCoverMeters()
    externalCoverRefreshTicksRemaining = math.max(0, externalCoverRefreshTicksRemaining - 1)
    return true
end
local function externalTransportMetrics()
    local m = metrics()
    local page = pageControlMetrics()
    local hitW = math.max(30, round(38 * m.scale))
    local hitH = hitW
    local gap = math.max(4, round(8 * m.scale))
    local centerY = page.y
    local hitY = round(centerY - (hitH / 2))
    local iconSize = math.max(14, round(20 * m.scale))
    local repeatIconSize = math.max(iconSize + 1, round(iconSize * 1.15))
    local shuffleIconSize = iconSize
    local controls = {}

    local playbackTotalW = (hitW * #EXTERNAL_PLAYBACK_CONTROLS) + (gap * (#EXTERNAL_PLAYBACK_CONTROLS - 1))
    local clusterShiftX = round(m.usableW * 0.10)
    -- Align with the Jukebox anchor column, then tune the external control cluster.
    local playbackCenterX = round(m.usableX + (m.cellW * 2.5) - clusterShiftX)
    local playbackStartX = round(playbackCenterX - (playbackTotalW / 2))
    for index, control in ipairs(EXTERNAL_PLAYBACK_CONTROLS) do
        local hitX = round(playbackStartX + ((index - 1) * (hitW + gap)))
        local centerX = round(hitX + (hitW / 2))
        controls[control] = {
            hitX = hitX,
            hitY = hitY,
            hitW = hitW,
            hitH = hitH,
            centerX = centerX,
            centerY = centerY,
        }
    end

    local repeatCenterX = round(page.repeatVisualX + (page.repeatVisualW / 2) - clusterShiftX)
    local optionStride = hitW + gap
    local optionCenters = {
        ['repeat'] = round(repeatCenterX - (optionStride / 2)),
        shuffle = round(repeatCenterX + (optionStride / 2)),
    }
    for _, control in ipairs(EXTERNAL_OPTION_CONTROLS) do
        local centerX = optionCenters[control]
        local hitX = round(centerX - (hitW / 2))
        controls[control] = {
            hitX = hitX,
            hitY = hitY,
            hitW = hitW,
            hitH = hitH,
            centerX = centerX,
            centerY = centerY,
        }
    end

    local repeatControl = controls['repeat']
    local shuffle = controls.shuffle
    return {
        playbackHidden = isExternalPlaybackSourceMode() and 0 or 1,
        optionsHidden = (isExternalPlaybackSourceMode() and optionsVisible()) and 0 or 1,
        disabled = {
            previous = externalControlClickable('previous') and 0 or 1,
            playpause = externalControlClickable('playpause') and 0 or 1,
            next = externalControlClickable('next') and 0 or 1,
            ['repeat'] = externalControlClickable('repeat') and 0 or 1,
            shuffle = externalControlClickable('shuffle') and 0 or 1,
        },
        controls = controls,
        playHidden = trim(SKIN:GetVariable('JukeboxExternalState', '0')) == '1' and 1 or 0,
        pauseHidden = trim(SKIN:GetVariable('JukeboxExternalState', '0')) == '1' and 0 or 1,
        previousColor = externalTransportColor('previous'),
        playPauseColor = externalTransportColor('playpause'),
        nextColor = externalTransportColor('next'),
        repeatColor = externalTransportColor('repeat'),
        repeatOneHidden = currentRepeatMode() == 'one' and 0 or 1,
        repeatX = round(repeatControl.centerX - (repeatIconSize / 2)),
        repeatY = round(repeatControl.centerY - (repeatIconSize / 2)),
        repeatSize = repeatIconSize,
        repeatOneX = round((repeatControl.centerX - (repeatIconSize / 2)) + (repeatIconSize * 1.2)),
        repeatOneY = round((repeatControl.centerY - (repeatIconSize / 2)) + (repeatIconSize * 0.78)),
        repeatOneFontSize = math.max(6, round(7 * m.scale)),
        shuffleColor = externalTransportColor('shuffle'),
        shuffleX = round(shuffle.centerX - (shuffleIconSize / 2)),
        shuffleY = round(shuffle.centerY - (shuffleIconSize / 2)),
        shuffleSize = shuffleIconSize,
    }
end
