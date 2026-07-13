-- Split from ExtraContent\Jukebox\DiscSlot\JukeboxDiscSlot.lua lines 2290-2808.
function Initialize()
    scanRunning = false
    openFolderRunning = false
    clearSlots()
    currentPage = readPersistedPage()
    totalPages = math.max(1, currentPage)
    syncScannerVariables()
    syncPixelationVariables()
    JukeboxDiscSlotSyncVolumeDialogVariables()
    syncPageMeters()
end

function ResumeDiscSlotResident()
    EnsureJukeboxDiscSlotResidentUpdateController().ResumeSurface('JukeboxDiscSlot')
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    EnsureJukeboxDiscSlotResidentSurface():CommandIfActive('MeasureResponsiveLayout', 'ApplyLayout()')
    SyncVisualState()
    return true
end

function SuspendDiscSlotResident()
    EnsureJukeboxDiscSlotResidentUpdateController().SuspendSurface('JukeboxDiscSlot')
    resetInteractionState()
    EnsureJukeboxDiscSlotResidentSurface():CommandIfActive('MeasureResponsiveLayout', 'DeactivateLiveState()')
    return true
end

function RestoreDiscSlotResidentOnRefresh()
    if isHidden() then
        return SuspendDiscSlotResident()
    end
    return ResumeDiscSlotResident()
end

function RefreshDiscs()
    if scanRunning then
        return false
    end
    if isExternalPlaybackSourceMode() then
        scanRunning = false
        clearSlots()
        clampCurrentPageToContent(false)
        syncDiscMeters()
        syncPageMeters()
        syncSelectedAfterScan(true)
        updateMeterGroup('JukeboxDiscSlot')
        redraw()
        return true
    end
    syncScannerVariables()
    local measure = SKIN:GetMeasure('MeasureJukeboxDiscSlotScanRun')
    if not measure then
        SKIN:Bang('!Log', 'Jukebox DiscSlot scanner measure is missing.', 'Warning')
        requestDiscSlotAlert('scanner_missing', 'measure_missing', false)
        syncDiscMeters()
        syncPageMeters()
        syncSelectedAfterScan(true)
        return false
    end
    scanRunning = true
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxDiscSlotScanRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotScanRun', 'Run')
    return true
end

function HandleScanComplete()
    scanRunning = false
    local values = parsePairs(scanMeasureOutput())
    if upper(values.DMEL_STATUS) ~= 'OK' then
        SKIN:Bang('!Log', 'Jukebox DiscSlot scanner failed or returned malformed output.', 'Warning')
        requestDiscSlotAlert('scanner_failed', 'malformed_output', false)
    else
        applyScanValues(values)
    end
    syncDiscMeters()
    syncPageMeters()
    syncSelectedAfterScan(false)
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
    return true
end

function HandlePixelateCoverComplete()
    local pixelator = loadImagePixelation()
    if not pixelator then
        return false
    end

    local result = pixelator:handleComplete(measureOutput('MeasureJukeboxDiscSlotPixelateRun'))
    if not result.accepted then
        logPixelationFailure({
            newFailure = true,
            message = result.message,
        })
        syncExternalCoverMeters()
        updateMeterGroup('JukeboxDiscSlot')
        redraw()
        return false
    end
    if result.newFailure or result.warning then
        logPixelationFailure(result)
    end
    if result.queued and result.queued.newFailure then
        logPixelationFailure(result.queued)
    end
    syncExternalCoverMeters()
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
    return result.ok
end

function HandleExternalCoverFingerprintComplete()
    local values = parsePairs(measureOutput('MeasureJukeboxDiscSlotFingerprintRun'))
    local accepted = JukeboxDiscSlotExternalCoverFingerprint.applyResult(values)
    if not accepted and upper(values.DMEL_STATUS) ~= 'OK' then
        SKIN:Bang('!Log', 'Jukebox external cover fingerprint failed: ' .. trim(values.DMEL_ERROR_CODE), 'Warning')
    end
    syncExternalCoverMeters()
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
    return accepted
end

function SyncVisualState()
    syncDiscMeters()
    if isHidden() then
        resetInteractionState()
    end
    syncSelectedAfterScan(false)
    syncPageMeters()
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
end

local function showPage(page)
    totalPages = calculateTotalPages()
    if totalPages < 1 then
        totalPages = 1
    end
    page = math.floor(tonumber(page) or currentPage)
    if page < 1 then
        page = totalPages
    elseif page > totalPages then
        page = 1
    end
    currentPage = page
    persistCurrentPage()
    resetInteractionState()
    syncDiscMeters()
    syncSelectedAfterScan(false)
    syncPageMeters()
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
    return true
end

function PreviousPage()
    if isHidden() or isExternalPlaybackSourceMode() then
        return false
    end
    return JukeboxDiscSlotPlayClickSoundForResult(showPage(currentPage - 1))
end

function NextPage()
    if isHidden() or isExternalPlaybackSourceMode() then
        return false
    end
    return JukeboxDiscSlotPlayClickSoundForResult(showPage(currentPage + 1))
end
function OpenAudioFolder()
    if openFolderRunning then
        return false
    end
    if isHidden() or isExternalPlaybackSourceMode() or not optionsVisible() then
        return false
    end
    local path = audioDirectoryPath()
    if path == '' then
        return false
    end
    if not SKIN:GetMeasure('MeasureJukeboxDiscSlotOpenFolderRun') then
        SKIN:Bang('!Log', 'Jukebox DiscSlot open-folder measure is missing.', 'Warning')
        return false
    end
    if not JukeboxDiscSlotSyncOpenFolderVariables(path) then
        SKIN:Bang('!Log', 'Jukebox DiscSlot open-folder arguments could not be built.', 'Warning')
        return false
    end
    JukeboxDiscSlotPlayClickSound()
    openFolderRunning = true
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxDiscSlotOpenFolderRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotOpenFolderRun', 'Run')
    return true
end

function HandleOpenAudioFolderComplete()
    openFolderRunning = false
    return true
end

function OpenVolumeDialog()
    if JukeboxDiscSlotVolumeDialogRunning then
        return false
    end
    if isHidden() or not optionsVisible() then
        return false
    end
    if not volumeControlEnabled() then
        hideHover()
        hideTooltip(true)
        return false
    end
    if not SKIN:GetMeasure('MeasureJukeboxDiscSlotVolumeDialogRun') then
        SKIN:Bang('!Log', 'Jukebox DiscSlot volume dialog measure is missing.', 'Warning')
        requestDiscSlotAlert('volume_dialog_failed', 'measure_missing', false)
        return false
    end
    JukeboxDiscSlotSyncVolumeDialogVariables()
    hideTooltip(true)
    hideHover()
    clearVolumeDrag()
    JukeboxDiscSlotPlayClickSound()
    JukeboxDiscSlotVolumeDialogRunning = true
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxDiscSlotVolumeDialogRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotVolumeDialogRun', 'Run')
    return true
end

function HandleVolumeDialogComplete()
    JukeboxDiscSlotVolumeDialogRunning = false
    local values = parsePairs(measureOutput('MeasureJukeboxDiscSlotVolumeDialogRun'))
    local status = upper(values.DMEL_STATUS)
    if status == 'CANCEL' then
        return true
    end
    if status ~= 'OK' then
        SKIN:Bang('!Log', 'Jukebox DiscSlot volume dialog failed or returned malformed output.', 'Warning')
        requestDiscSlotAlert('volume_dialog_failed', status == '' and 'missing_status' or status, false)
        return false
    end
    local value = tonumber(values.DMEL_VALUE)
    if value == nil then
        SKIN:Bang('!Log', 'Jukebox DiscSlot volume dialog did not return a usable DMEL_VALUE.', 'Warning')
        requestDiscSlotAlert('volume_dialog_failed', 'missing_value', false)
        return false
    end
    value = clampVolumePercent(value)
    setDisplayedVolume(value)
    syncPageMeters()
    if not callJukebox(string.format('SetPlaybackVolume(%q)', tostring(value))) then
        SKIN:Bang('!Log', 'Jukebox DiscSlot could not reach the main Jukebox to apply volume dialog value.', 'Warning')
        requestDiscSlotAlert('volume_dialog_failed', 'jukebox_unreachable', false)
        return false
    end
    redraw()
    return true
end

function CloseDiscSlot()
    if isHidden() or not optionsVisible() then
        return false
    end
    return JukeboxDiscSlotPlayClickSoundForResult(callJukebox('HideDiscSlot()'))
end

function MinimizeJukebox()
    if isHidden() or not optionsVisible() then
        return false
    end
    hideTooltip(true)
    hideHover()
    return JukeboxDiscSlotPlayClickSoundForResult(callJukebox('MinimizeJukebox()'))
end
function OpenJukeboxSettings()
    if isHidden() or not optionsVisible() then
        return false
    end
    hideTooltip(true)
    hideHover()
    local resources = tostring(SKIN:GetVariable('@') or '')
    if resources == '' then
        SKIN:Bang('!Log', 'Jukebox DiscSlot could not resolve the resources root for Settings routing.', 'Warning')
        requestDiscSlotAlert('settings_route_failed', 'resources_root_missing', false)
        return false
    end
    local ok, launcher = pcall(dofile, resources .. 'Defaults\\Runtime\\luas\\SettingsRouteLauncher.lua')
    if not ok or type(launcher) ~= 'table' or type(launcher.Open) ~= 'function' then
        SKIN:Bang('!Log', 'Jukebox DiscSlot could not open the Settings route launcher.', 'Warning')
        requestDiscSlotAlert('settings_route_failed', 'launcher_unavailable', false)
        return false
    end
    return JukeboxDiscSlotPlayClickSoundForResult(launcher.Open(SKIN, 'content', 'jukebox'))
end
function ToggleRepeatMode()
    if isHidden() or isExternalPlaybackSourceMode() or not optionsVisible() then
        return false
    end
    return JukeboxDiscSlotPlayClickSoundForResult(callJukebox('TogglePlaybackRepeatMode()'))
end

function ToggleShuffleMode()
    if isHidden() or isExternalPlaybackSourceMode() or not optionsVisible() then
        return false
    end
    return JukeboxDiscSlotPlayClickSoundForResult(callJukebox('TogglePlaybackShuffle()'))
end
local function requestExternalTransport(control, command)
    if isHidden() or not externalTransportControlVisible(control) or not externalControlClickable(control) then
        return false
    end
    hideTooltip(true)
    hideHover()
    return JukeboxDiscSlotPlayClickSoundForResult(callJukebox(command))
end
function ExternalPrevious()
    return requestExternalTransport('previous', 'ExternalPrevious()')
end

function ExternalPlayPause()
    if requestExternalTransport('playpause', 'ExternalPlayPause()') then
        callJukebox('HideDiscSlot()')
        return true
    end
    return false
end

function ExternalNext()
    return requestExternalTransport('next', 'ExternalNext()')
end

function ExternalRepeat()
    return requestExternalTransport('repeat', 'ExternalRepeat()')
end


function ExternalShuffle()
    return requestExternalTransport('shuffle', 'ExternalShuffle()')
end

function ToggleOptionsVisibility()
    if isHidden() then
        return false
    end
    local nextValue = optionsVisible() and 0 or 1
    setVariable('JukeboxDiscSlotOptionsVisible', nextValue)
    persistOptionsVisibility(nextValue)
    hideTooltip(true)
    hideHover()
    syncPageMeters()
    updateMeterGroup('JukeboxDiscSlot')
    JukeboxDiscSlotPlayClickSound()
    redraw()
    return true
end
function PlayNextFromPlaybackSelection(shuffle, fromEnded)
    local currentIndex = currentPlaybackSlotIndex()
    local nextIndex = trim(shuffle) == '1' and nextRandomSlotIndex(currentIndex) or nextSequentialSlotIndex(currentIndex)
    if not nextIndex then
        requestEndedPlaybackClear()
        return false
    end
    local slot = slots[nextIndex]
    if not isSupported(slot) then
        requestEndedPlaybackClear()
        return false
    end
    if trim(fromEnded) == '1' then
        return callJukebox(string.format('RequestEndedDiscSlotPlayback(%d,%q,%q)', tonumber(nextIndex) or 0, tostring(slot.name or ''), tostring(slot.path or '')))
    end
    return requestPlayback(nextIndex, slot, 'play')
end

function SetPlaybackSelection(slotIndex, slotName)
    slotIndex = tonumber(slotIndex) or 0
    slotName = trim(slotName)
    local slot = slots[slotIndex]
    if not isSupported(slot) or trim(slot.name) ~= slotName then
        clearSelected(true)
        return false
    end
    updateSelected(slotIndex, true)
    return true
end

function ClearPlaybackSelection()
    clearSelected(true)
end

function OnControlMouseLeave()
    if volumeDragActive then
        return
    end
    hideTooltip(true)
end

function OnVolumeControlMouseLeave()
    clearVolumeDrag()
    hideTooltip(true)
end

function TickTooltipWatchdog()
    if not tooltipVisible or tooltipKey == '' then
        tooltipWatchdogRemainingMs = TOOLTIP_STALE_HIDE_MS
        return
    end
    if tooltipLastX == nil or tooltipLastY == nil then
        return
    end
    tooltipWatchdogRemainingMs = tooltipWatchdogRemainingMs - TOOLTIP_WATCHDOG_TICK_MS
    if tooltipWatchdogRemainingMs <= 0 then
        hideTooltip(true)
        tooltipWatchdogRemainingMs = TOOLTIP_STALE_HIDE_MS
    end
end

function TickRuntimeWatchdogs()
    TickTooltipWatchdog()
    tickExternalCoverRefresh()
    return true
end

function OnMouseMove(x, y)
    if isHidden() then
        resetInteractionState()
        return
    end

    local localX, localY = contentLocalPoint(x, y)
    if volumeDragActive then
        if volumeControlAtPoint(localX, localY) then
            applyVolumeFromPoint(localY, x, y)
        else
            clearVolumeDrag()
            hideTooltip(true)
        end
        return
    end
    local controlKey, controlTooltip = controlTooltipAtPoint(localX, localY)
    if controlKey then
        hideHover()
        showTooltip(controlTooltip, x, y, tooltipKey ~= controlTooltip)
        return
    end

    local coverKey, coverTooltip = externalCoverFailureTooltipAtPoint(localX, localY)
    if coverKey then
        hideHover()
        showTooltip(coverTooltip, x, y, tooltipKey ~= coverTooltip)
        return
    end

    if isExternalPlaybackSourceMode() then
        hideHover()
        if externalCoverAtPoint(localX, localY) then
            hideTooltip(true)
        else
            resetInteractionState()
        end
        return
    end

    local ix, iy, index = slotAtPoint(localX, localY)
    local slot = index and slots[index] or nil
    if ix == nil or iy == nil or not isPresent(slot) then
        resetInteractionState()
        return
    end

    local previousHoverKey = hoverKey
    local currentHoverKey = slotKey(ix, iy)
    updateHover(ix, iy)
    showTooltip(tooltipTextForSlot(slot), x, y, previousHoverKey ~= currentHoverKey)
end

function OnMouseDown(x, y)
    if isHidden() then
        mouseDownSlot = nil
        clearVolumeDrag()
        return
    end

    local localX, localY = contentLocalPoint(x, y)
    if volumeControlAtPoint(localX, localY) then
        mouseDownSlot = nil
        hideHover()
        if volumeControlEnabled() then
            volumeDragActive = true
            lastVolumeCommandValue = nil
            JukeboxDiscSlotPlayClickSound()
            applyVolumeFromPoint(localY, x, y)
        else
            showTooltip(volumeTooltipText(), x, y, true)
        end
        return
    end
    if controlAtPoint(localX, localY) then
        mouseDownSlot = nil
        return
    end

    if isExternalPlaybackSourceMode() then
        mouseDownSlot = nil
        hideHover()
        return
    end

    local ix, iy, index = slotAtPoint(localX, localY)
    local slot = index and slots[index] or nil
    if not isPresent(slot) then
        mouseDownSlot = nil
        return
    end

    mouseDownSlot = index
    updateHover(ix, iy)
end

function OnMouseUp(x, y)
    if isHidden() then
        mouseDownSlot = nil
        clearVolumeDrag()
        return
    end

    local localX, localY = contentLocalPoint(x, y)
    if volumeDragActive then
        if volumeControlAtPoint(localX, localY) then
            applyVolumeFromPoint(localY, x, y)
        end
        clearVolumeDrag()
        return
    end
    if controlAtPoint(localX, localY) then
        mouseDownSlot = nil
        return
    end

    if isExternalPlaybackSourceMode() then
        mouseDownSlot = nil
        hideHover()
        return
    end

    local ix, iy, index = slotAtPoint(localX, localY)
    if mouseDownSlot == nil or index ~= mouseDownSlot then
        mouseDownSlot = nil
        return
    end

    local slot = slots[index]
    if not isPresent(slot) then
        mouseDownSlot = nil
        return
    end

    if not slot.supported then
        if requestUnsupportedModal(slot) then
            JukeboxDiscSlotPlayClickSound()
        end
        mouseDownSlot = nil
        return
    end

    local action = 'play'
    if selectedIndex() == index and selectedName() == trim(slot.name) then
        action = 'pause'
    end
    if requestPlayback(index, slot, action) then
        JukeboxDiscSlotPlayClickSound()
        callJukebox('HideDiscSlot()')
    end
    mouseDownSlot = nil
end

function OnMouseLeave()
    resetInteractionState()
end

function ResetRenderStateForClose()
    mouseDownSlot = nil
    clearVolumeDrag()
    hideHover()
    resetTooltipRenderMeters()
    updateMeterGroup('JukeboxDiscSlot')
    redraw()
end
