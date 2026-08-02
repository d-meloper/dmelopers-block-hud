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
