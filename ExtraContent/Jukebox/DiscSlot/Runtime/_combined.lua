-- Generated runtime aggregate for Rainmeter-safe split loading. Edit sibling part files instead.
-- Split from ExtraContent\Jukebox\DiscSlot\JukeboxDiscSlot.lua lines 1-843.
local GRID_COLUMNS = 3
local GRID_ROWS = 3
local SLOTS_PER_PAGE = GRID_COLUMNS * GRID_ROWS
local SELECT_HIGHLIGHT_OFFSET_BASE = 10
local DISC_SIZE_RATIO = 0.8
local SUPPORTED_EXTENSIONS = '.m4a, .mp3, .wav, .wma, .aac'
local TOOLTIP_STALE_HIDE_MS = 800
local TOOLTIP_WATCHDOG_TICK_MS = 250

local hoverKey = ''
local mouseDownSlot = nil
local volumeDragActive = false
local lastVolumeCommandValue = nil
local slots = {}
local highestSlot = 0
local currentPage = 1
local totalPages = 1
local tooltipVisible = false
local tooltipKey = ''
local tooltipLastX = nil
local tooltipLastY = nil
local tooltipWatchdogRemainingMs = TOOLTIP_STALE_HIDE_MS
local randomSeeded = false
local scanRunning = false
local openFolderRunning = false
JukeboxDiscSlotVolumeDialogRunning = false
local imagePixelationModule = nil
local imagePixelationLoadFailed = false
JukeboxDiscSlotHelperResult = nil
local externalCoverPixelator = nil
local externalCoverLoadFailed = false
local externalCoverStableKey = ''
local externalCoverStableCount = 0
local externalCoverRefreshTicksRemaining = 0
local externalCoverRefreshKey = ''
local EXTERNAL_COVER_STABLE_REQUIRED_COUNT = 2
local EXTERNAL_COVER_REFRESH_MAX_TICKS = 24
local EXTERNAL_PLAYBACK_CONTROLS = { 'previous', 'playpause', 'next' }
local EXTERNAL_OPTION_CONTROLS = { 'repeat', 'shuffle' }
local EXTERNAL_TRANSPORT_ORDER = { 'previous', 'playpause', 'next', 'repeat', 'shuffle' }
JukeboxDiscSlotExternalCoverFingerprint = {
    running = false,
    token = '',
    key = '',
    hash = '',
    length = '',
    format = '',
    currentKey = '',
    currentPath = '',
    previousKey = '',
    previousPath = '',
    previousHash = '',
    reuseGraceTicks = 0,
    refreshTicks = 0,
    cooldownTicks = 0,
    sequence = 0,
    reuseGraceLimit = 8,
    refreshLimit = 24,
    refreshInterval = 2,
}
JukeboxDiscSlotResidentUpdateController = nil
JukeboxDiscSlotResidentSurfaceLifecycle = nil

function EnsureJukeboxDiscSlotResidentUpdateController()
    if JukeboxDiscSlotResidentUpdateController == nil then
        JukeboxDiscSlotResidentUpdateController = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\ResidentUpdateController.lua')
    end
    return JukeboxDiscSlotResidentUpdateController
end

function EnsureJukeboxDiscSlotResidentSurfaceLifecycle()
    if JukeboxDiscSlotResidentSurfaceLifecycle == nil then
        JukeboxDiscSlotResidentSurfaceLifecycle = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\ResidentSurfaceLifecycle.lua')
    end
    return JukeboxDiscSlotResidentSurfaceLifecycle
end

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function CreateJukeboxDiscSlotResidentSurface(configPath, surfaceId, entryFile, measureName)
    return EnsureJukeboxDiscSlotResidentSurfaceLifecycle().CreateSurface({
        skin = SKIN,
        surfaceId = surfaceId or 'JukeboxDiscSlot',
        configPath = trim(configPath) ~= '' and trim(configPath) or trim(SKIN:GetVariable('CURRENTCONFIG', '')),
        entryFile = entryFile or 'JukeboxDiscSlot.ini',
        measureName = measureName or 'MeasureJukeboxDiscSlot',
    })
end

function EnsureJukeboxDiscSlotResidentSurface()
    return CreateJukeboxDiscSlotResidentSurface()
end

local function upper(value)
    return string.upper(trim(value))
end

local function normalizedRepeatMode(value)
    local mode = trim(value):lower()
    if mode == 'one' or mode == 'off' then
        return mode
    end
    return 'all'
end

local function currentRepeatMode()
    return normalizedRepeatMode(SKIN:GetVariable('JukeboxPlaybackRepeatMode', 'all'))
end

local function currentShuffleEnabled()
    return trim(SKIN:GetVariable('JukeboxPlaybackShuffle', '0')) == '1'
end

local function boolVariable(name)
    local value = trim(SKIN:GetVariable(name, '0')):lower()
    return value == '1' or value == 'true'
end

local function currentPlaybackSourceMode()
    local mode = trim(SKIN:GetVariable('JukeboxPlaybackSourceMode', 'local')):lower()
    if mode == 'external' then
        return 'external'
    end
    return 'local'
end

local function isExternalPlaybackSourceMode()
    return currentPlaybackSourceMode() == 'external'
end

local function numberVar(name, fallback)
    local parsed = tonumber(SKIN:GetVariable(name, tostring(fallback or 0)))
    if parsed ~= nil then
        return parsed
    end
    return tonumber(fallback) or 0
end


local function round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function clampVolumePercent(value)
    local volume = round(tonumber(value) or 0)
    if volume < 0 then
        return 0
    end
    if volume > 100 then
        return 100
    end
    return volume
end
local function contentX()
    return round(numberVar('JukeboxDiscSlotContentX', 0))
end

local function actionSide()
    local side = trim(SKIN:GetVariable('JukeboxDiscSlotActionSide', 'right'))
    if side == 'left' then
        return 'left'
    end
    return 'right'
end

local function contentLocalPoint(x, y)
    return (tonumber(x) or 0) - contentX(), tonumber(y) or 0
end

local function setVariable(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value or ''))
end

local function updateMeter(name)
    SKIN:Bang('!UpdateMeter', name)
end

local function updateMeterGroup(name)
    SKIN:Bang('!UpdateMeterGroup', name)
end

local function redraw()
    SKIN:Bang('!Redraw')
end

local function joinPath(base, leaf)
    base = tostring(base or '')
    leaf = tostring(leaf or '')
    if base == '' then
        return leaf
    end
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then
        return base .. leaf
    end
    return base .. '\\' .. leaf
end

function EnsureJukeboxDiscSlotHelperResultModule()
    if JukeboxDiscSlotHelperResult == nil then
        JukeboxDiscSlotHelperResult = dofile(joinPath(trim(SKIN:GetVariable('CURRENTPATH', '')), '..\\Runtime\\JukeboxHelperResult.lua'))
    end
    return JukeboxDiscSlotHelperResult
end

function JukeboxDiscSlotPlayClickSound()
    local enabled = tonumber(trim(SKIN:GetVariable('UseClickSound', '1'))) or 1
    if enabled == 0 then
        return false
    end
    local root = trim(SKIN:GetVariable('@', ''))
    if root == '' then
        return false
    end
    -- Temporarily disabled Jukebox UI click sound.
    -- SKIN:Bang('PlayStop')
    -- SKIN:Bang('Play "' .. joinPath(root, [[Defaults\Runtime\audios\click.wav]]) .. '"')
    return true
end

function JukeboxDiscSlotPlayClickSoundForResult(result)
    if result then
        JukeboxDiscSlotPlayClickSound()
    end
    return result
end
local function rollingHash(value)
    value = tostring(value or '')
    local hash = 5381
    for index = 1, #value do
        hash = ((hash * 33) + value:byte(index)) % 4294967296
    end
    return string.format('%08x', hash)
end

local function sanitizePathSegment(value)
    value = trim(value):gsub('[^A-Za-z0-9_%-]+', '_'):gsub('_+', '_')
    value = value:gsub('^_+', ''):gsub('_+$', '')
    if value == '' then
        return 'default'
    end
    if #value > 80 then
        value = value:sub(1, 80):gsub('_+$', '')
        if value == '' then
            return 'default'
        end
    end
    return value
end
local function fileExists(path)
    local handle = io.open(tostring(path or ''), 'rb')
    if handle then
        handle:close()
        return true
    end
    return false
end

local function quotePowerShellArgument(value)
    value = tostring(value or '')
    value = value:gsub('`', '``')
    value = value:gsub('"', '`"')
    return '"' .. value .. '"'
end

function JukeboxDiscSlotQuotePowerShellSingleQuotedArgument(value)
    value = tostring(value or '')
    value = value:gsub("'", "''")
    return "'" .. value .. "'"
end

local function quoteCommandLineArgument(value)
    value = tostring(value or '')
    local result = { '"' }
    local backslashes = 0
    for index = 1, #value do
        local char = value:sub(index, index)
        if char == '\\' then
            backslashes = backslashes + 1
        elseif char == '"' then
            result[#result + 1] = string.rep('\\', (backslashes * 2) + 1)
            result[#result + 1] = '"'
            backslashes = 0
        else
            if backslashes > 0 then
                result[#result + 1] = string.rep('\\', backslashes)
                backslashes = 0
            end
            result[#result + 1] = char
        end
    end
    if backslashes > 0 then
        result[#result + 1] = string.rep('\\', backslashes * 2)
    end
    result[#result + 1] = '"'
    return table.concat(result)
end

local function resolvePowerShellProgramPath()
    return 'powershell'
end

local function pixelationHelperPath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\helpers\\PixelateImage.ps1')
end

local function fingerprintHelperPath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\helpers\\GetImageFingerprint.ps1')
end

local function configuredThumbnailImage(variableName, fallbackImage)
    local path = trim(SKIN:GetVariable(variableName, ''))
    if path ~= '' then
        return path
    end
    return fallbackImage
end

local function loadingThumbnailImage(fallbackImage)
    return configuredThumbnailImage('JukeboxDiscSlotLoadingThumbnailImage', fallbackImage)
end

local function brokenThumbnailImage(fallbackImage)
    return configuredThumbnailImage('JukeboxDiscSlotBrokenThumbnailImage', fallbackImage)
end

local function imagePixelationLuaPath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\luas\\ImagePixelation.lua')
end

local function imagePixelationCacheNamespace()
    local instanceSource = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
    if instanceSource == '' then
        instanceSource = trim(SKIN:GetVariable('ROOTCONFIG', '')) .. '\\ExtraContent\\Jukebox\\DiscSlot'
    end
    return sanitizePathSegment(instanceSource) .. '-' .. rollingHash(instanceSource)
end

local requestDiscSlotAlert

local function loadImagePixelation()
    if externalCoverPixelator ~= nil then
        return externalCoverPixelator
    end
    if imagePixelationLoadFailed then
        return nil
    end

    if imagePixelationModule == nil then
        local modulePath = imagePixelationLuaPath()
        local ok, moduleOrError = pcall(dofile, modulePath)
        if not ok or type(moduleOrError) ~= 'table' or type(moduleOrError.create) ~= 'function' then
            imagePixelationLoadFailed = true
            SKIN:Bang('!Log', 'Jukebox external cover pixelation module could not be loaded: ' .. tostring(moduleOrError), 'Warning')
            return nil
        end
        imagePixelationModule = moduleOrError
    end

    externalCoverPixelator = imagePixelationModule.create(SKIN, {
        helperPath = pixelationHelperPath(),
        argsVariable = 'JukeboxDiscSlotPixelateArgs',
        runMeasure = 'MeasureJukeboxDiscSlotPixelateRun',
        cacheNamespace = imagePixelationCacheNamespace(),
        defaultWidth = 280,
        defaultHeight = 280,
        defaultBlockSize = numberVar('JukeboxDiscSlotExternalCoverPixelBlock', 3),
        fitMode = trim(SKIN:GetVariable('JukeboxDiscSlotExternalCoverFitMode', 'Cover')),
        sampleMode = trim(SKIN:GetVariable('JukeboxDiscSlotExternalCoverSampleMode', 'Average')),
    })
    return externalCoverPixelator
end

local function scannerScriptPath()
    return joinPath(trim(SKIN:GetVariable('CURRENTPATH', '')), 'JukeboxDiscSlotScanner.ps1')
end

local function audioDirectoryPath()
    return joinPath(trim(SKIN:GetVariable('ROOTCONFIGPATH', '')), '@Resources\\Customs\\Audios\\Jukebox Disc')
end

local function openFolderHelperPath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\helpers\\OpenFolder.ps1')
end

function JukeboxDiscSlotBuildOpenAudioFolderArgs(path)
    local helperPath = openFolderHelperPath()
    if helperPath == '' then
        return ''
    end

    return table.concat({
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', quoteCommandLineArgument(helperPath),
        '-Path', quoteCommandLineArgument(path),
        '-Create',
    }, ' ')
end

function JukeboxDiscSlotSyncOpenFolderVariables(path)
    local args = JukeboxDiscSlotBuildOpenAudioFolderArgs(path)
    if args == '' then
        return false
    end
    setVariable('JukeboxDiscSlotOpenFolderProgram', resolvePowerShellProgramPath())
    setVariable('JukeboxDiscSlotOpenFolderArgs', args)
    return true
end

local function stateFilePath()
    return joinPath(trim(SKIN:GetVariable('ROOTCONFIGPATH', '')), '@Resources\\Customs\\Data\\JukeboxDiscSlots.json')
end

local function playbackStatePath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Customs\\Data\\JukeboxPlaybackState.inc')
end

local function buildScannerArgs()
    return table.concat({
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(scannerScriptPath()),
        '-AudioDirectory', quotePowerShellArgument(audioDirectoryPath()),
        '-StatePath', quotePowerShellArgument(stateFilePath()),
        '-SupportedExtensions', quotePowerShellArgument(SUPPORTED_EXTENSIONS),
    }, ' ')
end


local function syncScannerVariables()
    setVariable('JukeboxDiscSlotScannerProgram', resolvePowerShellProgramPath())
    setVariable('JukeboxDiscSlotScannerArgs', buildScannerArgs())
end

local function syncPixelationVariables()
    setVariable('JukeboxDiscSlotPixelateProgram', resolvePowerShellProgramPath())
    setVariable('JukeboxDiscSlotFingerprintProgram', resolvePowerShellProgramPath())
end


local function isHidden()
    return numberVar('JukeboxDiscSlotHidden', 1) ~= 0
end

local function isHoverHighlightDisabled()
    return numberVar('LowSpecDisableSlotHoverHighlight', 0) ~= 0
end

local function isHoverTextTooltipFixed()
    return numberVar('LowSpecDisableHoverTextTooltip', 0) ~= 0
end

local function metrics()
    local usableX = numberVar('JukeboxDiscSlotUsableX', 5)
    local usableY = numberVar('JukeboxDiscSlotUsableY', 5)
    local usableW = math.max(0, numberVar('JukeboxDiscSlotUsableW', 300))
    local usableH = math.max(0, numberVar('JukeboxDiscSlotUsableH', 300))
    local cellW = usableW / GRID_COLUMNS
    local cellH = usableH / GRID_ROWS
    return {
        slotW = math.max(1, numberVar('JukeboxDiscSlotW', 310)),
        slotH = math.max(1, numberVar('JukeboxDiscSlotH', 310)),
        usableX = usableX,
        usableY = usableY,
        usableW = usableW,
        usableH = usableH,
        cellW = cellW,
        cellH = cellH,
        actionGutter = math.max(0, numberVar('JukeboxDiscSlotActionGutter', 52)),
        scale = math.min(usableW / 300, usableH / 300),
    }
end

local function pageForSlot(index)
    index = tonumber(index) or 0
    if index < 1 then
        return 1
    end
    return math.floor((index - 1) / SLOTS_PER_PAGE) + 1
end

local function calculateTotalPages()
    return math.max(1, pageForSlot(highestSlot))
end

local function pageStartIndex()
    return ((currentPage - 1) * SLOTS_PER_PAGE) + 1
end

local function globalSlotIndex(visibleIndex)
    visibleIndex = tonumber(visibleIndex) or 0
    if visibleIndex < 1 or visibleIndex > SLOTS_PER_PAGE then
        return nil
    end
    return pageStartIndex() + visibleIndex - 1
end

local function visibleSlotIndexForGlobal(index)
    index = tonumber(index) or 0
    local first = pageStartIndex()
    local last = first + SLOTS_PER_PAGE - 1
    if index < first or index > last then
        return nil
    end
    return index - first + 1
end

local function slotIndex(ix, iy)
    if not ix or not iy then
        return nil
    end
    return globalSlotIndex(((iy - 1) * GRID_COLUMNS) + ix)
end

local function slotCoordinates(index)
    local visibleIndex = visibleSlotIndexForGlobal(index)
    if not visibleIndex then
        return nil, nil
    end
    local ix = ((visibleIndex - 1) % GRID_COLUMNS) + 1
    local iy = math.floor((visibleIndex - 1) / GRID_COLUMNS) + 1
    return ix, iy
end
local function slotAtPoint(x, y)
    local m = metrics()
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    if m.usableW <= 0 or m.usableH <= 0 then
        return nil, nil, nil
    end
    if x < m.usableX or x >= (m.usableX + m.usableW) then
        return nil, nil, nil
    end
    if y < m.usableY or y >= (m.usableY + m.usableH) then
        return nil, nil, nil
    end

    local ix = math.floor((x - m.usableX) / m.cellW) + 1
    local iy = math.floor((y - m.usableY) / m.cellH) + 1
    if ix < 1 or ix > GRID_COLUMNS or iy < 1 or iy > GRID_ROWS then
        return nil, nil, nil
    end
    return ix, iy, slotIndex(ix, iy)
end

local function slotKey(ix, iy)
    if not ix or not iy then
        return ''
    end
    return tostring(ix) .. ':' .. tostring(iy)
end

local function meterSuffix(index)
    return string.format('%02d', tonumber(index) or 0)
end

local function isPresent(slot)
    return slot ~= nil and slot.present == true
end

local function isSupported(slot)
    return isPresent(slot) and slot.supported == true
end

local function selectedIndex()
    return numberVar('JukeboxDiscSlotSelectedSlotIndex', 0)
end

local function selectedName()
    return trim(SKIN:GetVariable('JukeboxDiscSlotSelectedName', ''))
end

local function selectedPlaybackState()
    return {
        active = numberVar('JukeboxPlaybackSelectedActive', 0) == 1,
        index = numberVar('JukeboxPlaybackSelectedSlotIndex', 0),
        name = trim(SKIN:GetVariable('JukeboxPlaybackSelectedName', '')),
        path = trim(SKIN:GetVariable('JukeboxPlaybackSelectedPath', '')),
    }
end

local function normalizedPath(path)
    return trim(path):gsub('/', '\\'):lower()
end

local function slotMatchesPlaybackState(slot, state)
    if not isSupported(slot) or not state or not state.active then
        return false
    end
    if state.path ~= '' and normalizedPath(slot.path) == normalizedPath(state.path) then
        return true
    end
    return state.name ~= '' and trim(slot.name) == state.name
end

local function hasTooltipMeasure()
    local ok, measure = pcall(function()
        return SKIN:GetMeasure('MeasureTooltip')
    end)
    return ok and measure ~= nil
end

local function runTooltipCommand(command)
    if not command or command == '' or not hasTooltipMeasure() then
        return
    end
    SKIN:Bang('!CommandMeasure', 'MeasureTooltip', command)
end

local function resetTooltipWatchdog()
    tooltipLastX = nil
    tooltipLastY = nil
    tooltipWatchdogRemainingMs = TOOLTIP_STALE_HIDE_MS
end

local function noteTooltipPosition(x, y, resetStable)
    local nextX = tonumber(x) or 0
    local nextY = tonumber(y) or 0
    if resetStable or tooltipLastX ~= nextX or tooltipLastY ~= nextY then
        tooltipLastX = nextX
        tooltipLastY = nextY
        tooltipWatchdogRemainingMs = TOOLTIP_STALE_HIDE_MS
    end
end

local function showTooltip(text, x, y, force)
    text = tostring(text or '')
    if text == '' then
        return
    end
    local textChanged = force or tooltipKey ~= text
    tooltipVisible = true
    if textChanged then
        noteTooltipPosition(x, y, true)
        tooltipKey = text
        runTooltipCommand(string.format('ShowItemNameAt(%q, false, %s, %s)', text, tostring(x), tostring(y)))
        return
    end
    if not isHoverTextTooltipFixed() then
        noteTooltipPosition(x, y, false)
        runTooltipCommand(string.format('OnMouseMove(%s,%s,false)', tostring(x), tostring(y)))
    end
end

local function hideTooltip(force)
    if not force and not tooltipVisible and tooltipKey == '' then
        return
    end
    tooltipVisible = false
    tooltipKey = ''
    resetTooltipWatchdog()
    runTooltipCommand('Hide()')
end

local function resetTooltipRenderMeters()
    hideTooltip(true)
    SKIN:Bang('!SetOption', 'MeterPanel', 'X', '0')
    SKIN:Bang('!SetOption', 'MeterPanel', 'Y', '0')
    SKIN:Bang('!SetOption', 'MeterPanel', 'W', '0')
    SKIN:Bang('!SetOption', 'MeterPanel', 'H', '0')
    SKIN:Bang('!SetOption', 'MeterText', 'X', '0')
    SKIN:Bang('!SetOption', 'MeterText', 'Y', '0')
    SKIN:Bang('!SetOption', 'MeterText', 'FontColor', '255,255,255,0')
    updateMeterGroup('Tooltip')
end
local function unsupportedTooltipText()
    local text = trim(SKIN:GetVariable('Loc_JukeboxDiscSlot_UnsupportedFile', 'Unsupported file'))
    if text == '' then
        return 'Unsupported file'
    end
    return text
end

local function tooltipTextForSlot(slot)
    if not isPresent(slot) then
        return ''
    end
    if slot.supported then
        return trim(slot.stem)
    end
    return unsupportedTooltipText()
end

local function localizedControlText(key, fallback)
    local text = trim(SKIN:GetVariable(key, fallback or ''))
    if text == '' then
        return fallback or ''
    end
    return text
end

local function localizedFormatText(key, fallback, values)
    local text = localizedControlText(key, fallback)
    for index, value in ipairs(values or {}) do
        local replacement = tostring(value or ''):gsub('%%', '%%%%')
        text = text:gsub('%%' .. tostring(index), replacement)
    end
    return text
end

local function thumbnailLoadFailedTooltipText()
    return localizedControlText('Loc_JukeboxDiscSlot_ThumbnailLoadFailed', 'The thumbnail could not be loaded.')
end

local function repeatTooltipText()
    local mode = currentRepeatMode()
    if mode == 'one' then
        return localizedControlText('Loc_JukeboxDiscSlot_RepeatOne', 'Repeat one')
    elseif mode == 'off' then
        return localizedControlText('Loc_JukeboxDiscSlot_RepeatOff', 'Repeat off')
    end
    return localizedControlText('Loc_JukeboxDiscSlot_RepeatAll', 'Repeat all')
end

local function shuffleTooltipText()
    if currentShuffleEnabled() then
        return localizedControlText('Loc_JukeboxDiscSlot_ShuffleOn', 'Shuffle on')
    end
    return localizedControlText('Loc_JukeboxDiscSlot_ShuffleOff', 'Shuffle off')
end

local function externalPreviousTooltipText()
    return localizedControlText('Loc_JukeboxExternal_Previous', 'Previous')
end

local function externalPlayPauseTooltipText()
    return localizedControlText('Loc_JukeboxExternal_PlayPause', 'Play/Pause')
end

local function externalNextTooltipText()
    return localizedControlText('Loc_JukeboxExternal_Next', 'Next')
end

local function externalRepeatTooltipLabel()
    return localizedControlText('Loc_JukeboxExternal_Repeat', 'Repeat')
end

local function externalShuffleTooltipLabel()
    return localizedControlText('Loc_JukeboxExternal_Shuffle', 'Shuffle')
end

local function openFolderTooltipText()
    return localizedControlText('Loc_Common_OpenFolder', 'Open folder')
end

local function closeTooltipText()
    return localizedControlText('Loc_Common_Close', 'Close')
end

local function minimizeTooltipText()
    return localizedControlText('Loc_JukeboxDiscSlot_Minimize', 'Minimize Jukebox')
end

local function settingsTooltipText()
    local target = localizedControlText('Loc_Settings_Content_Jukebox', 'Jukebox')
    local settings = localizedControlText('Loc_Inventory_SettingsButtonName', 'settings')
    return trim(target .. ' ' .. settings)
end

local function externalVolumeStateConnected()
    return boolVariable('JukeboxExternalBridgeActive') and trim(SKIN:GetVariable('JukeboxExternalStatus', '0')) == '1'
end

local function volumeControlEnabled()
    if not isExternalPlaybackSourceMode() then
        return true
    end
    return externalVolumeStateConnected() and boolVariable('JukeboxExternalSupportsSetVolume')
end

local function currentVolumePercent()
    if isExternalPlaybackSourceMode() then
        if not externalVolumeStateConnected() then
            return 0
        end
        return clampVolumePercent(numberVar('JukeboxExternalVolume', 0))
    end
    return clampVolumePercent(numberVar('JukeboxPlaybackVolume', 100))
end

local function volumeTooltipText()
    if isExternalPlaybackSourceMode() then
        if not externalVolumeStateConnected() then
            return ''
        end
        if not volumeControlEnabled() then
            return localizedControlText('Loc_JukeboxDiscSlot_VolumeUnsupported', 'This app does not support volume control.')
        end
    end
    local format = localizedControlText('Loc_JukeboxDiscSlot_VolumeFormat', 'Volume: %1%')
    return trim(format:gsub('%%1', tostring(currentVolumePercent())))
end

function JukeboxDiscSlotSyncVolumeDialogVariables()
    local centerX = round(SKIN:GetVariable('CURRENTCONFIGX', '0')) + contentX() + round(numberVar('JukeboxDiscSlotW', 240) / 2)
    local centerY = round(SKIN:GetVariable('CURRENTCONFIGY', '0')) + round(numberVar('JukeboxDiscSlotH', 240) / 2)
    local title = localizedControlText('Loc_JukeboxExternal_Volume', 'Volume')
    local label = trim(title .. ' (0-100)')
    local applyText = localizedControlText('Loc_Settings_Field_applyMinecraftSkin_Action', 'Apply')
    local cancelText = localizedControlText('Loc_Common_Cancel', 'Cancel')
    setVariable('JukeboxDiscSlotVolumeDialogProgram', resolvePowerShellProgramPath())
    setVariable('JukeboxDiscSlotVolumeDialogArgs', table.concat({
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-File', quoteCommandLineArgument('.\\JukeboxVolumeDialog.ps1'),
        '-InitialValue', tostring(currentVolumePercent()),
        '-CenterX', tostring(centerX),
        '-CenterY', tostring(centerY),
        '-Title', quoteCommandLineArgument(title),
        '-LabelText', quoteCommandLineArgument(label),
        '-CancelText', quoteCommandLineArgument(cancelText),
        '-ApplyText', quoteCommandLineArgument(applyText),
    }, ' '))
    return true
end

local function optionsVisible()
    return numberVar('JukeboxDiscSlotOptionsVisible', 1) ~= 0
end

local function optionsVisibilityTooltipText()
    if optionsVisible() then
        return localizedControlText('Loc_JukeboxDiscSlot_HideOptions', 'Hide options')
    end
    return localizedControlText('Loc_JukeboxDiscSlot_ShowOptions', 'Show options')
end

local function persistOptionsVisibility()
    local path = playbackStatePath()
    if path == '' then
        return false
    end
    local value = optionsVisible() and '1' or '0'
    SKIN:Bang('!WriteKeyValue', 'Variables', 'JukeboxDiscSlotOptionsVisible', value, path)
    return true
end

local function hideHover()
    if hoverKey == '' and numberVar('JukeboxDiscSlotHoverHidden', 1) ~= 0 then
        return
    end
    hoverKey = ''
    setVariable('JukeboxDiscSlotHoverHidden', 1)
    updateMeter('MeterJukeboxDiscSlotHover')
    redraw()
end

local function updateHover(ix, iy)
    local key = slotKey(ix, iy)
    if key == '' then
        hideHover()
        return
    end
    if isHoverHighlightDisabled() then
        hideHover()
        return
    end
    if key == hoverKey and numberVar('JukeboxDiscSlotHoverHidden', 1) == 0 then
        return
    end

    local m = metrics()
    local x = round(m.usableX + ((ix - 1) * m.cellW))
    local y = round(m.usableY + ((iy - 1) * m.cellH))
    local w = round(m.cellW)
    local h = round(m.cellH)

    hoverKey = key
    setVariable('JukeboxDiscSlotHoverX', x + contentX())
    setVariable('JukeboxDiscSlotHoverY', y)
    setVariable('JukeboxDiscSlotHoverW', w)
    setVariable('JukeboxDiscSlotHoverH', h)
    setVariable('JukeboxDiscSlotHoverHidden', 0)
    updateMeter('MeterJukeboxDiscSlotHover')
    redraw()
end

local function persistCurrentPage()
    local path = playbackStatePath()
    if path == '' then
        return false
    end
    SKIN:Bang('!WriteKeyValue', 'Variables', 'JukeboxDiscSlotCurrentPage', tostring(currentPage), path)
    return true
end

local function readPersistedPage()
    local page = math.floor(numberVar('JukeboxDiscSlotCurrentPage', 1))
    if page < 1 then
        return 1
    end
    return page
end

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
        '-NoProfile',
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

local function jukeboxResidentSurface(configName)
    return CreateJukeboxDiscSlotResidentSurface(configName, 'Jukebox', 'Jukebox.ini', 'MeasureJukebox')
end

function JukeboxDiscSlotIsRainmeterConfigActive(configName)
    return jukeboxResidentSurface(configName):IsActive()
end

local function callJukebox(command)
    local config = jukeboxConfigName()
    if config == '' then
        return false
    end
    return jukeboxResidentSurface(config):CommandIfActive('MeasureJukebox', command)
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
