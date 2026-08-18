-- Split from ExtraContent\Jukebox\Jukebox.lua lines 1-1086.
local bridge = nil
JukeboxHelperResult = nil
local initialized = false
local commandRunning = {
    playback = false,
    stop = false,
    emergencyStop = false,
    loop = false,
    volume = false,
    poll = false,
    webNowPlayingInstall = false,
    openLogFolder = false,
    stopPendingAfterExternalSwitch = false,
    volumePending = false,
}
local pollSuspendedAfterError = false
local safeCall = nil
local residentUpdateController = nil
local residentSurfaceLifecycle = nil
local syncJukeboxRuntimeDriver = nil
local syncJukeboxAnimationDriver = nil
local jukeboxAnimatorPhase = 'hidden'
local minimizedAnimatorPhase = 'hidden'
local JukeboxScheduler = {
    responsive = false,
    eventPolling = false,
    eventPollRuntimeTicks = 0,
    minimizedIdle = false,
    externalCommandWatchdog = false,
}
local JUKEBOX_EVENT_POLL_RUNTIME_TICKS = 4
local JUKEBOX_EVENT_RECONCILE_RUNTIME_TICKS = 238
local jukeboxEventSignalMode = 'unknown'

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

-- DMEL_COMPAT:jukebox.event-signal-fallback
local function setJukeboxEventSignalMode(values)
    if trim(values and values.DMEL_EVENTSIGNAL or '') == '1' then
        jukeboxEventSignalMode = 'signal'
        JukeboxScheduler.eventPollRuntimeTicks = 0
    else
        jukeboxEventSignalMode = 'legacy'
        JukeboxScheduler.eventPollRuntimeTicks = JUKEBOX_EVENT_POLL_RUNTIME_TICKS
    end
end

local function jukeboxEventSignalCount()
    local measure = SKIN:GetMeasure('MeasureJukeboxEventSignalCount')
    if not measure then
        return 0
    end
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxEventSignalCount')
    return math.max(0, tonumber(measure:GetValue()) or 0)
end

local function ensureResidentUpdateController()
    if residentUpdateController == nil then
        residentUpdateController = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\ResidentUpdateController.lua')
    end
    return residentUpdateController
end

local function ensureResidentSurfaceLifecycle()
    if residentSurfaceLifecycle == nil then
        residentSurfaceLifecycle = dofile((SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\ResidentSurfaceLifecycle.lua')
    end
    return residentSurfaceLifecycle
end

syncJukeboxRuntimeDriver = function()
    local enabled = JukeboxScheduler.responsive
        or JukeboxScheduler.eventPolling
        or JukeboxScheduler.minimizedIdle
        or JukeboxScheduler.externalCommandWatchdog
    ensureResidentUpdateController().SetDriver('Jukebox', 'runtime', enabled)
end

syncJukeboxAnimationDriver = function()
    local enabled = jukeboxAnimatorPhase ~= 'hidden' or minimizedAnimatorPhase ~= 'hidden'
    ensureResidentUpdateController().SetDriver('Jukebox', 'animation', enabled)
end

function StartJukeboxEventPolling()
    if pollSuspendedAfterError then
        return 0
    end
    JukeboxScheduler.eventPolling = true
    if jukeboxEventSignalMode == 'signal' then
        JukeboxScheduler.eventPollRuntimeTicks = 0
    else
        JukeboxScheduler.eventPollRuntimeTicks = JUKEBOX_EVENT_POLL_RUNTIME_TICKS
    end
    syncJukeboxRuntimeDriver()
    return 0
end

function StopJukeboxEventPolling()
    JukeboxScheduler.eventPolling = false
    JukeboxScheduler.eventPollRuntimeTicks = 0
    syncJukeboxRuntimeDriver()
    return 0
end

function ContinueJukeboxEventPolling()
    if pollSuspendedAfterError then
        return StopJukeboxEventPolling()
    end
    return StartJukeboxEventPolling()
end
local discSlotVisible = false
local discSlotLoaded = false
local discSlotActivationRequested = false
local discSlotDeferredAttempts = 0
local discSlotRefreshRecoveryRequested = false
local discSlotPendingShow = false
local discSlotPendingShowSkipRefresh = false
local animationEngine = nil
local jukeboxAnimator = nil
jukeboxAnimatorPhase = 'hidden'
local jukeboxAnimatorKind = ''
local jukeboxAnimatorPlaybackActive = false
local jukeboxAnimatorElapsedMs = 0
local jukeboxAnimatorWaitMs = 0
local jukeboxAnimatorCurrentFrameCount = 0
local jukeboxAnimatorCurrentFrameMs = 42
local jukeboxAnimatorLastPlayingIndex = 0
local jukeboxAnimatorRandomSeeded = false
local jukeboxAnimatorTransitionCallbackToken = ''
minimizedAnimator = nil
minimizedAnimatorPhase = 'hidden'
minimizedAnimatorKind = ''
minimizedAnimatorPlaybackActive = false
minimizedAnimatorElapsedMs = 0
minimizedAnimatorWaitMs = 0
minimizedAnimatorCurrentFrameCount = 0
minimizedAnimatorCurrentFrameMs = 42
minimizedAnimatorLastPlayingIndex = 0
minimizedAnimatorRandomSeeded = false
minimizedDragging = false
minimizedDragAllowedAtDown = false
minimizedDragMoved = false
minimizedLastWindowY = nil
minimizedDownX = 0
minimizedDownY = 0
minimizedDownWindowX = 0
minimizedDownWindowY = 0
MINIMIZED_DRAG_THRESHOLD = 3
local SUPPORTED_AUDIO_EXTENSIONS = '.m4a, .mp3, .wav, .wma, .aac'
local PLAYBACK_SOURCE_LOCAL = 'local'
local PLAYBACK_SOURCE_EXTERNAL = 'external'
EXTERNAL_COMMAND_WATCHDOG_TIMEOUT_TICKS = 8
EXTERNAL_COMMAND_LOG_THROTTLE_SECONDS = 15

local externalPlaybackState = {
    bridgeActive = false,
    bridgeActivationRequested = false,
    bridgeReconnectRequested = false,
    pluginLoadFailed = false,
    bridgeFailureAlertShown = false,
    observed = false,
    status = '0',
    player = '',
    title = '',
    artist = '',
    album = '',
    cover = '',
    coverFetchFailed = false,
    coverFailureIdentity = '',
    coverFailureUrl = '',
    coverFailureStatus = '',
    coverRetryNonce = 0,
    duration = '0',
    volume = '0',
    state = '0',
    repeatMode = '0',
    shuffle = '0',
    supportsPlayPause = '0',
    supportsSkipPrevious = '0',
    supportsSkipNext = '0',
    supportsSetVolume = '0',
    supportsToggleRepeatMode = '0',
    supportsToggleShuffleActive = '0',
    mediaIdentity = '',
    visualSwitch = {
        active = false,
        token = '',
        counter = 0,
        playAfterStop = false,
        mediaIdentity = '',
    },
    commandWatch = {
        active = false,
        command = '',
        valueText = '',
        ticks = 0,
        beforeState = '',
        beforeIdentity = '',
        beforePlayer = '',
        supportFlag = '',
        supportValue = '',
        bestEffort = false,
        reconnectRetry = false,
        waitingForReconnect = false,
        toggleFallbackTried = false,
    },
    commandLogTimes = {},
}

webNowPlayingInstallState = {
    phase = '',
    requestedMode = '',
    previousMode = '',
    token = 0,
    openCommand = '',
    bypassPreflight = false,
    ownerPid = '',
    ownerUser = '',
    ownerDomain = '',
    ownerLabel = '',
}

local pendingDiscSlotPlayback = nil
local discSlotSwitchState = {
    pending = nil,
    token = 0,
    tryStartPlay = nil,
}

local isRainmeterConfigActive = nil
local runMeasure = nil


local ANIMATOR_TICK_MS = 42
local ANIMATOR_FRAME_MS = 42
local ANIMATOR_TRANSITION_FRAME_MS = ANIMATOR_TICK_MS * 2
local ANIMATOR_PLAYING_FRAME_MS = ANIMATOR_FRAME_MS * 1.7
local ANIMATOR_FRAME_WIDTH = 100
local ANIMATOR_FRAME_HEIGHT = 126
local ANIMATOR_COLUMNS = 3
local ANIMATOR_TRANSITION_FRAME_COUNT = 12
local ANIMATOR_PLAYING_FRAME_COUNT = 9
local ANIMATOR_PLAYING_SHEET_COUNT = 11
local ANIMATOR_PLAYING_DELAY_MS = 1000
MINIMIZED_ANIMATOR_FRAME_HEIGHT = 40
MINIMIZED_ANIMATOR_IMAGE_ROOT = 'Defaults\\Runtime\\images\\jukebox\\Minimized\\'
local ANIMATOR_IMAGE_BASE_ROOT = 'Defaults\\Runtime\\images\\jukebox\\'
local DISC_SLOT_DEFERRED_MAX_ATTEMPTS = 10
local ANIMATOR_TRANSITION_PROFILES = {
    play = 'jukeboxSpriteSheet_play.png',
    stop = 'jukeboxSpriteSheet_stop.png',
}

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

local function externalRepeatMode()
    local mode = trim(externalPlaybackState.repeatMode)
    if mode == '1' then
        return 'one'
    end
    if mode == '0' then
        return 'off'
    end
    return 'all'
end

local function externalShuffleEnabled()
    return trim(externalPlaybackState.shuffle) == '1'
end

local function normalizedPlaybackSourceMode(value)
    local mode = trim(value):lower()
    if mode == PLAYBACK_SOURCE_EXTERNAL then
        return PLAYBACK_SOURCE_EXTERNAL
    end
    return PLAYBACK_SOURCE_LOCAL
end

local function currentPlaybackSourceMode()
    return normalizedPlaybackSourceMode(SKIN:GetVariable('JukeboxPlaybackSourceMode', PLAYBACK_SOURCE_LOCAL))
end

local function isExternalPlaybackSourceMode()
    return currentPlaybackSourceMode() == PLAYBACK_SOURCE_EXTERNAL
end

local function isJukeboxNoteAnimationDisabled()
    return trim(SKIN:GetVariable('DisableJukeboxNoteAnimation', '0')) == '1'
end

local function shouldAutoCloseDiscSlotOnExternalPlayPause()
    return trim(SKIN:GetVariable('AutoCloseJukeboxDiscSlotOnExternalPlayPause', '1')) ~= '0'
end

local function isJukebox2DModeEnabled()
    return trim(SKIN:GetVariable('EnableJukebox2DMode', '0')) == '1'
end

local function jukeboxModeFolderName()
    return isJukebox2DModeEnabled() and '2D' or '3D'
end

local function isPlaybackLoopEnabled()
    return currentRepeatMode() == 'one'
end

local function setVariable(name, value)
    SKIN:Bang('!SetVariable', tostring(name or ''), tostring(value or ''))
end

local function fileExists(path)
    local handle = io.open(tostring(path or ''), 'rb')
    if handle then
        handle:close()
        return true
    end
    return false
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

function EnsureJukeboxHelperResultModule()
    if JukeboxHelperResult == nil then
        JukeboxHelperResult = dofile(joinPath(trim(SKIN:GetVariable('CURRENTPATH', '')), 'Runtime\\JukeboxHelperResult.lua'))
    end
    return JukeboxHelperResult
end

local function quotePowerShellArgument(value)
    value = tostring(value or '')
    value = value:gsub('`', '``')
    value = value:gsub('"', '`"')
    return '"' .. value .. '"'
end

local function resolvePowerShellProgramPath()
    return 'powershell'
end

local function rollingHash(text)
    local hash = 5381
    text = tostring(text or '')
    for index = 1, #text do
        hash = (hash * 33 + text:byte(index)) % 4294967296
    end
    return string.format('%08x', hash)
end

local function instanceKey()
    local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', 'BlockHud'))
    local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    local safeRoot = rootConfig:gsub('[^%w_%-]', '_')
    if safeRoot == '' then
        safeRoot = 'BlockHud'
    end
    return safeRoot .. '-' .. rollingHash(rootPath)
end

local function helperStateRootOverride()
    return trim(SKIN:GetVariable('JukeboxHelperStateRoot', ''))
end

local function eventSignalDirectoryPath()
    return trim(SKIN:GetVariable('JukeboxEventSignalDirectory', ''))
end

local function playbackStatePath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Customs\\Data\\JukeboxPlaybackState.inc')
end

local function generalSettingsPath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Customs\\Settings\\General.inc')
end

local function helperScriptFileName()
    return 'JukeboxPlayer.ps1'
end

local function scriptPath()
    return joinPath(trim(SKIN:GetVariable('CURRENTPATH', '')), helperScriptFileName())
end

local function emergencyStopScriptPath()
    return joinPath(trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\helpers\\JukeboxEmergencyStop.ps1')
end

local function buildArgs(command, audioOverride, requestPath, loopEnabled, volumePercent)
    local resolvedAudioPath = audioOverride or ''
    local args = {
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(scriptPath()),
        '-Command', quotePowerShellArgument(command),
        '-AudioPath', quotePowerShellArgument(resolvedAudioPath),
        '-Volume', quotePowerShellArgument(tostring(clampPlaybackVolume(volumePercent))),
    }

    if loopEnabled then
        args[#args + 1] = '-Loop'
    end

    local overrideStateRoot = helperStateRootOverride()
    if overrideStateRoot ~= '' then
        args[#args + 1] = '-StateRoot'
        args[#args + 1] = quotePowerShellArgument(overrideStateRoot)
    end
    args[#args + 1] = '-InstanceKey'
    args[#args + 1] = quotePowerShellArgument(instanceKey())
    local signalDirectory = eventSignalDirectoryPath()
    if signalDirectory ~= '' then
        args[#args + 1] = '-EventSignalDirectory'
        args[#args + 1] = quotePowerShellArgument(signalDirectory)
    end
    return table.concat(args, ' ')
end

function webNowPlayingInstallState.scriptFileName()
    return 'JukeboxWebNowPlayingInstaller.ps1'
end

function webNowPlayingInstallState.scriptPath()
    return joinPath(trim(SKIN:GetVariable('CURRENTPATH', '')), webNowPlayingInstallState.scriptFileName())
end

function webNowPlayingInstallState.buildArgs(action)
    local normalizedAction = trim(action)
    if normalizedAction == '' then
        normalizedAction = 'Check'
    end
    local args = {
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(webNowPlayingInstallState.scriptPath()),
        '-Action', quotePowerShellArgument(normalizedAction),
    }
    if normalizedAction:lower() == 'terminateportowner' and trim(webNowPlayingInstallState.ownerPid) ~= '' then
        args[#args + 1] = '-OwnerPid'
        args[#args + 1] = quotePowerShellArgument(trim(webNowPlayingInstallState.ownerPid))
    end
    return table.concat(args, ' ')
end

local function buildOpenLogFolderArgs()
    local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    local helperPath = joinPath(rootPath, 'Utilities\\tools\\OpenSettingsLogFolder.ps1')
    return table.concat({
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(helperPath),
        '-TargetRoot', quotePowerShellArgument(rootPath),
        '-EmitResultPairs',
    }, ' ')
end

local function startJukeboxOpenLogFolderHelper()
    if commandRunning.openLogFolder then
        return false
    end
    if not SKIN:GetMeasure('MeasureJukeboxOpenLogFolderRun') then
        return false
    end
    local args = buildOpenLogFolderArgs()
    if args == '' then
        return false
    end
    setVariable('JukeboxPowerShellProgram', resolvePowerShellProgramPath())
    commandRunning.openLogFolder = true
    setVariable('JukeboxOpenLogFolderArgs', args)
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxOpenLogFolderRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxOpenLogFolderRun', 'Run')
    return true
end

function HandleOpenLogFolderComplete()
    commandRunning.openLogFolder = false
    return true
end

local function buildEmergencyStopArgs()
    local args = {
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', quotePowerShellArgument(emergencyStopScriptPath()),
        '-InstanceKey', quotePowerShellArgument(instanceKey()),
    }
    local overrideStateRoot = helperStateRootOverride()
    if overrideStateRoot ~= '' then
        args[#args + 1] = '-StateRoot'
        args[#args + 1] = quotePowerShellArgument(overrideStateRoot)
    end
    return table.concat(args, ' ')
end

local function syncHelperVariables()
    local volume = currentPlaybackVolume()
    setVariable('JukeboxPowerShellProgram', resolvePowerShellProgramPath())
    setVariable('JukeboxPlaybackArgs', buildArgs('Play', '', '', isPlaybackLoopEnabled(), volume))
    setVariable('JukeboxStopArgs', buildArgs('Stop', '', '', false, volume))
    setVariable('JukeboxSetLoopArgs', buildArgs('SetLoop', '', '', isPlaybackLoopEnabled(), volume))
    setVariable('JukeboxSetVolumeArgs', buildArgs('SetVolume', '', '', isPlaybackLoopEnabled(), volume))
    setVariable('JukeboxPollEventArgs', buildArgs('PollEvent', '', '', false, volume))
    setVariable('JukeboxEmergencyStopArgs', buildEmergencyStopArgs())
    setVariable('JukeboxWebNowPlayingInstallerArgs', webNowPlayingInstallState.buildArgs('Check'))
    setVariable('JukeboxOpenLogFolderArgs', buildOpenLogFolderArgs())
end
local function ensureBridge()
    if bridge then
        return bridge
    end

    local resourcesRoot = trim(SKIN:GetVariable('@', ''))
    if resourcesRoot == '' then
        return nil
    end

    bridge = dofile(resourcesRoot .. 'Defaults\\Runtime\\luas\\ModalAlertBridge.lua')
    return bridge
end

local function modalAlertLogPath()
    local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    return rootPath .. "Logs\\DMeloper's Block HUD Log.log"
end

local function jukeboxDiscAudioDirectoryPath()
    local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))
    if rootPath == '' then
        return ''
    end
    return joinPath(rootPath, '@Resources\\Customs\\Audios\\Jukebox Disc')
end

local function modalAlertHost()
    return {
        skin = SKIN,
        name = 'Jukebox',
        targetConfig = SKIN:GetVariable('CURRENTCONFIG', ''),
        targetMeasure = 'MeasureJukebox',
        deferredVariable = 'BlockHudJukeboxModalAlertDeferredOpen',
        deferredMeasure = 'MeasureJukeboxModalAlertDeferredOpen',
        logPath = modalAlertLogPath(),
        openLogCallback = 'OpenModalAlertLogFolder',
        openFolder = function()
            return startJukeboxOpenLogFolderHelper()
        end,
    }
end
local function rootConfigName()
    local root = trim(SKIN:GetVariable('ROOTCONFIG', ''))
    if root ~= '' then
        return root
    end

    local current = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
    local suffix = '\\ExtraContent\\Jukebox'
    if current:sub(-#suffix) == suffix then
        return trim(current:sub(1, #current - #suffix))
    end
    return current
end

local function discSlotConfigName()
    local root = rootConfigName()
    if root == '' then
        return 'ExtraContent\\Jukebox\\DiscSlot'
    end
    return root .. '\\ExtraContent\\Jukebox\\DiscSlot'
end
function jukeboxConfigName()
    local root = rootConfigName()
    if root == '' then
        return 'ExtraContent\\Jukebox'
    end
    return root .. '\\ExtraContent\\Jukebox'
end

local function webNowPlayingBridgeConfigName()
    local root = rootConfigName()
    if root == '' then
        return 'ExtraContent\\Jukebox\\WebNowPlayingBridge'
    end
    return root .. '\\ExtraContent\\Jukebox\\WebNowPlayingBridge'
end

local function diagnosticsConfigName()
    local root = rootConfigName()
    if root == '' then
        return 'Utilities\\Diagnostics'
    end
    return root .. '\\Utilities\\Diagnostics'
end

local function round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

function clampPlaybackVolume(value)
    local volume = round(tonumber(value) or 100)
    if volume < 0 then
        return 0
    end
    if volume > 100 then
        return 100
    end
    return volume
end

local function redraw()
    SKIN:Bang('!Redraw')
end

local function resourcesRoot()
    return trim(SKIN:GetVariable('@', ''))
end
local function playClickSound()
    local enabled = tonumber(trim(SKIN:GetVariable('UseClickSound', '1'))) or 1
    if enabled == 0 then
        return false
    end
    local root = resourcesRoot()
    if root == '' then
        return false
    end
    -- Temporarily disabled Jukebox UI click sound.
    -- SKIN:Bang('PlayStop')
    -- SKIN:Bang('Play "' .. joinPath(root, [[Defaults\Runtime\audios\click.wav]]) .. '"')
    return true
end

local function playClickSoundForResult(result)
    if result then
        playClickSound()
    end
    return result
end
local function allowCrossConfigValue(value)
    if value == nil then
        return true
    end
    local normalized = trim(value):lower()
    return not (value == false or normalized == '0' or normalized == 'false' or normalized == 'refresh')
end

local function rainmeterActionArgument(value)
    return '"' .. tostring(value or ''):gsub('"', [[\"]]) .. '"'
end

function isJukeboxFeatureEnabled()
    return trim(SKIN:GetVariable('EnableJukeboxSkin', '1')) ~= '0'
end

function JukeboxCurrentDisplayMode()
    local mode = trim(SKIN:GetVariable('JukeboxDisplayMode', 'main')):lower()
    if mode == 'minimized' then
        return 'minimized'
    end
    return 'main'
end

function JukeboxIsMinimizedForm()
    return JukeboxCurrentDisplayMode() == 'minimized'
end

local JukeboxConfigState = nil

local function jukeboxConfigState()
    if not JukeboxConfigState then
        JukeboxConfigState = dofile(SKIN:GetVariable('@', '') .. 'Defaults\\Runtime\\luas\\RainmeterConfigState.lua')
    end
    return JukeboxConfigState
end

local function createResidentSurface(surfaceId, configPath, entryFile, measureName)
    return ensureResidentSurfaceLifecycle().CreateSurface({
        skin = SKIN,
        surfaceId = surfaceId,
        configPath = configPath,
        entryFile = entryFile,
        measureName = measureName,
    })
end

function JukeboxLifecycleSurface()
    return createResidentSurface('Jukebox', jukeboxConfigName(), 'Jukebox.ini', 'MeasureJukebox')
end

function JukeboxDiscSlotLifecycleSurface()
    return createResidentSurface('JukeboxDiscSlot', discSlotConfigName(), 'JukeboxDiscSlot.ini', 'MeasureJukeboxDiscSlot')
end

function isRainmeterConfigActive(configName)
    configName = trim(configName)
    if configName == jukeboxConfigName() then
        return JukeboxLifecycleSurface():IsActive()
    end
    if configName == discSlotConfigName() then
        return JukeboxDiscSlotLifecycleSurface():IsActive()
    end
    return jukeboxConfigState().IsActive(SKIN, configName)
end

function setVariableForActiveConfig(name, value, configName)
    configName = trim(configName)
    if configName == '' then
        return false
    end
    if configName == discSlotConfigName() then
        return JukeboxDiscSlotLifecycleSurface():SetVariableIfActive(name, value)
    end
    if configName == jukeboxConfigName() then
        return JukeboxLifecycleSurface():SetVariableIfActive(name, value)
    end
    if not isRainmeterConfigActive(configName) then
        return false
    end
    SKIN:Bang('!SetVariable', tostring(name or ''), tostring(value or ''), configName)
    return true
end

function commandMeasureForActiveConfig(measureName, command, configName)
    configName = trim(configName)
    if configName == '' then
        return false
    end
    if configName == discSlotConfigName() then
        return JukeboxDiscSlotLifecycleSurface():CommandIfActive(measureName, command)
    end
    if configName == jukeboxConfigName() then
        return JukeboxLifecycleSurface():CommandIfActive(measureName, command)
    end
    if not isRainmeterConfigActive(configName) then
        return false
    end
    SKIN:Bang('!CommandMeasure', measureName, command, configName)
    return true
end

local function jukeboxImageRoot()
    return ANIMATOR_IMAGE_BASE_ROOT .. jukeboxModeFolderName() .. '\\'
end

local function jukeboxImagePath(fileName)
    return resourcesRoot() .. jukeboxImageRoot() .. tostring(fileName or '')
end

local function loadAnimationEngine()
    if animationEngine == nil then
        animationEngine = dofile(resourcesRoot() .. 'Defaults\\Runtime\\luas\\AnimationEngine.lua')
    end
    return animationEngine
end
function setMinimizedPlaybackActiveVariable(isActive, allowCrossConfig)
    local value = isActive and '1' or '0'
    setVariable('JukeboxMinimizedPlaybackActive', value)
end

function syncMinimizedPlaybackActive(isActive, allowCrossConfig)
    setMinimizedPlaybackActiveVariable(isActive, allowCrossConfig)
    if JukeboxIsMinimizedForm() and SetJukeboxMinimizedPlaybackActive then
        SetJukeboxMinimizedPlaybackActive(isActive and '1' or '0')
    end
end

function startMinimizedVisualAnimation(kind)
    if not JukeboxIsMinimizedForm() or not StartJukeboxMinimizedAnimation then
        return false
    end
    return StartJukeboxMinimizedAnimation(kind)
end

function forceHideMinimizedVisualAnimation(allowCrossConfig)
    setMinimizedPlaybackActiveVariable(false, allowCrossConfig)
    if ForceHideJukeboxMinimizedAnimation then
        return ForceHideJukeboxMinimizedAnimation()
    end
    return false
end

local function updateJukeboxAnimatorMeters()
    SKIN:Bang('!UpdateMeter', 'MeterJukebox')
    SKIN:Bang('!UpdateMeter', 'MeterJukeboxAnimator')
end


local function syncJukeboxModeImages()
    local baseImage = jukeboxImagePath('jukebox.png')
    local animatorImage = jukeboxImagePath(ANIMATOR_TRANSITION_PROFILES.play)
    setVariable('JukeboxImage', baseImage)
    setVariable('JukeboxAnimatorImage', animatorImage)
    SKIN:Bang('!SetOption', 'MeterJukebox', 'ImageName', baseImage)
    if jukeboxAnimator == nil or jukeboxAnimatorPhase == 'hidden' then
        SKIN:Bang('!SetOption', 'MeterJukeboxAnimator', 'ImageName', animatorImage)
    end
    updateJukeboxAnimatorMeters()
end

local function setJukeboxAnimatorHidden(hidden)
    if JukeboxIsMinimizedForm() then
        setVariable('JukeboxAnimatorHidden', '1')
        setVariable('JukeboxBaseHidden', '1')
    else
        setVariable('JukeboxAnimatorHidden', hidden and '1' or '0')
        setVariable('JukeboxBaseHidden', hidden and '0' or '1')
    end
    updateJukeboxAnimatorMeters()
    redraw()
end

local function normalizeAnimationKind(kind)
    kind = trim(kind):lower()
    if kind == 'stop' then
        return 'stop'
    end
    return 'play'
end

local function seedJukeboxAnimatorRandom()
    if jukeboxAnimatorRandomSeeded then
        return
    end
    local x = tonumber(trim(SKIN:GetVariable('CURRENTCONFIGX', '0'))) or 0
    local y = tonumber(trim(SKIN:GetVariable('CURRENTCONFIGY', '0'))) or 0
    local seed = math.floor((os.time() + (x * 31) + (y * 17)) % 2147483647)
    if seed <= 0 then
        seed = os.time()
    end
    math.randomseed(seed)
    math.random()
    math.random()
    math.random()
    jukeboxAnimatorRandomSeeded = true
end

local function chooseJukeboxPlayingSheetIndex()
    seedJukeboxAnimatorRandom()
    local index = math.random(1, ANIMATOR_PLAYING_SHEET_COUNT)
    if jukeboxAnimatorLastPlayingIndex > 0 and ANIMATOR_PLAYING_SHEET_COUNT > 1 then
        index = math.random(1, ANIMATOR_PLAYING_SHEET_COUNT - 1)
        if index >= jukeboxAnimatorLastPlayingIndex then
            index = index + 1
        end
    end
    jukeboxAnimatorLastPlayingIndex = index
    return index
end

local function profileForJukeboxAnimatorSheet(sheetName, frameCount, frameMs)
    frameMs = tonumber(frameMs) or ANIMATOR_FRAME_MS
    return {
        sheetPath = jukeboxImagePath(sheetName),
        meterName = 'MeterJukeboxAnimator',
        frameWidth = ANIMATOR_FRAME_WIDTH,
        frameHeight = ANIMATOR_FRAME_HEIGHT,
        frameCount = frameCount,
        columns = ANIMATOR_COLUMNS,
        tickMs = ANIMATOR_TICK_MS,
        frameMs = frameMs,
        mode = 'once',
        redrawOnFrameChangeOnly = true,
        skipCatchUp = frameMs <= ANIMATOR_FRAME_MS,
        maxCatchUpFrames = 4,
        frozen = false,
        freezeFrame = 0,
    }
end

local function buildJukeboxAnimator(sheetName, frameCount, frameMs)
    local profile = profileForJukeboxAnimatorSheet(sheetName, frameCount, frameMs)
    jukeboxAnimatorCurrentFrameCount = profile.frameCount
    jukeboxAnimatorCurrentFrameMs = profile.frameMs
    jukeboxAnimator = loadAnimationEngine().create(SKIN, profile)
    jukeboxAnimator:Initialize()
end

local function hideJukeboxAnimatorVisual(allowCrossConfig)
    jukeboxAnimatorPhase = 'hidden'
    jukeboxAnimatorKind = ''
    jukeboxAnimatorTransitionCallbackToken = ''
    jukeboxAnimatorElapsedMs = 0
    jukeboxAnimatorWaitMs = 0
    if jukeboxAnimator ~= nil then
        jukeboxAnimator:Pause()
    end
    setJukeboxAnimatorHidden(true)
    syncJukeboxAnimationDriver()
end

local function forceHideJukeboxAnimator(allowCrossConfig)
    discSlotSwitchState.pending = nil
    if externalPlaybackState.visualSwitch then
        externalPlaybackState.visualSwitch.active = false
        externalPlaybackState.visualSwitch.token = ''
        externalPlaybackState.visualSwitch.playAfterStop = false
        externalPlaybackState.visualSwitch.mediaIdentity = ''
    end
    jukeboxAnimatorPlaybackActive = false
    syncMinimizedPlaybackActive(false, allowCrossConfig)
    hideJukeboxAnimatorVisual(allowCrossConfig)
    if allowCrossConfigValue(allowCrossConfig) then
        forceHideMinimizedVisualAnimation(allowCrossConfig)
    end
end

local function startJukeboxAnimatorTransition(kind, token)
    kind = normalizeAnimationKind(kind)
    buildJukeboxAnimator(ANIMATOR_TRANSITION_PROFILES[kind], ANIMATOR_TRANSITION_FRAME_COUNT, ANIMATOR_TRANSITION_FRAME_MS)
    jukeboxAnimatorPhase = 'transition'
    jukeboxAnimatorKind = kind
    jukeboxAnimatorTransitionCallbackToken = trim(token)
    jukeboxAnimatorElapsedMs = 0
    jukeboxAnimatorWaitMs = 0
    setJukeboxAnimatorHidden(false)
    jukeboxAnimator:Play()
    syncJukeboxAnimationDriver()
end

local function startJukeboxPlayingSheet()
    local index = chooseJukeboxPlayingSheetIndex()
    buildJukeboxAnimator('jukeboxSpriteSheet_playing' .. tostring(index) .. '.png', ANIMATOR_PLAYING_FRAME_COUNT, ANIMATOR_PLAYING_FRAME_MS)
    jukeboxAnimatorPhase = 'playing'
    jukeboxAnimatorKind = 'playing'
    jukeboxAnimatorElapsedMs = 0
    jukeboxAnimatorWaitMs = 0
    setJukeboxAnimatorHidden(false)
    jukeboxAnimator:Play()
    syncJukeboxAnimationDriver()
end

local function notifyJukeboxAnimationComplete(kind, token)
    token = trim(token)
    if token == '' then
        return
    end
    if HandleJukeboxAnimationComplete then
        HandleJukeboxAnimationComplete(trim(kind), token)
    end
end

local function enterJukeboxPlayingDelay()
    jukeboxAnimatorPhase = 'waiting'
    jukeboxAnimatorKind = 'playing'
    jukeboxAnimatorElapsedMs = 0
    jukeboxAnimatorWaitMs = 0
    if jukeboxAnimator ~= nil then
        jukeboxAnimator:Pause()
    end
    setJukeboxAnimatorHidden(true)
    syncJukeboxAnimationDriver()
end

local function setJukeboxAnimatorPlaybackActive(isActive, allowCrossConfig)
    jukeboxAnimatorPlaybackActive = isActive and true or false
    syncMinimizedPlaybackActive(jukeboxAnimatorPlaybackActive, allowCrossConfig)
    if not jukeboxAnimatorPlaybackActive then
        hideJukeboxAnimatorVisual(allowCrossConfig)
        return
    end

    if isJukeboxNoteAnimationDisabled() then
        hideJukeboxAnimatorVisual(allowCrossConfig)
        return
    end

    if jukeboxAnimatorPhase == 'transition' then
        return
    end
    if jukeboxAnimatorPhase ~= 'playing' and jukeboxAnimatorPhase ~= 'waiting' then
        enterJukeboxPlayingDelay()
    end
end

local function startJukeboxAnimation(kind, token)
    kind = normalizeAnimationKind(kind)
    if kind ~= 'play' then
        jukeboxAnimatorPlaybackActive = false
    end
    hideJukeboxAnimatorVisual()
    startMinimizedVisualAnimation(kind)
    if isJukeboxNoteAnimationDisabled() then
        notifyJukeboxAnimationComplete(kind, token)
        return
    end
    startJukeboxAnimatorTransition(kind, token)
end

function minimizedWidth()
    return math.max(1, round(SKIN:GetVariable('JukeboxMinimizedW', '100')))
end

function minimizedHeight()
    return math.max(1, round(SKIN:GetVariable('JukeboxMinimizedH', '40')))
end

function currentWindowX()
    return round(SKIN:GetVariable('CURRENTCONFIGX', '0'))
end

function currentWindowY()
    return round(SKIN:GetVariable('CURRENTCONFIGY', '0'))
end

function jukeboxMinimizedWorkArea(x)
    local probeX = round((tonumber(x) or currentWindowX()) + (minimizedWidth() / 2))
    local probeY = currentWindowY()
    if JukeboxWorkAreaForPoint then
        return JukeboxWorkAreaForPoint(probeX, probeY, JukeboxCurrentWorkArea())
    end
    return JukeboxCurrentWorkArea()
end

function minimizedBottomY(x)
    local work = jukeboxMinimizedWorkArea(x)
    return round(work.bottom - minimizedHeight())
end

function clampMinimizedX(x)
    local work = jukeboxMinimizedWorkArea(x)
    return round(JukeboxClampToRange(round(x), work.x, work.right - minimizedWidth()))
end

function persistSharedJukeboxX(x, mainY)
    local targetX = clampMinimizedX(x)
    if JukeboxMonitorFallbackActive() then
        return targetX
    end
    local y = storedJukeboxMainY(mainY)
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', string.format('SetFixedPosition(%q,%d,%d)', 'Jukebox', targetX, y))
    return targetX
end

function moveJukeboxToMinimizedBottom(x)
    local targetX = clampMinimizedX(x)
    local targetY = minimizedBottomY(targetX)
    SKIN:Bang('!Move', tostring(targetX), tostring(targetY))
    minimizedLastWindowY = targetY
    return targetX, targetY
end
function updateMinimizedMeters() SKIN:Bang('!UpdateMeter', 'MeterJukeboxMinimized'); SKIN:Bang('!UpdateMeter', 'MeterJukeboxMinimizedAnimator') end
function setJukeboxMinimizedMouseEnabled(enabled) if enabled then SKIN:Bang('!EnableMeasure', 'MeasureJukeboxMinimizedMouse'); SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxMinimizedMouse') else SKIN:Bang('!DisableMeasure', 'MeasureJukeboxMinimizedMouse') end; return true end
function minimizedImagePath(fileName) return resourcesRoot() .. MINIMIZED_ANIMATOR_IMAGE_ROOT .. tostring(fileName or '') end
function syncMinimizedModeImages() local baseImage = minimizedImagePath('jukebox.png'); local animatorImage = minimizedImagePath(ANIMATOR_TRANSITION_PROFILES.play); setVariable('JukeboxMinimizedImage', baseImage); setVariable('JukeboxMinimizedAnimatorImage', animatorImage); SKIN:Bang('!SetOption', 'MeterJukeboxMinimized', 'ImageName', baseImage); if minimizedAnimator == nil or minimizedAnimatorPhase == 'hidden' then SKIN:Bang('!SetOption', 'MeterJukeboxMinimizedAnimator', 'ImageName', animatorImage) end; updateMinimizedMeters() end
function setJukeboxMinimizedAnimatorHidden(hidden) if not JukeboxIsMinimizedForm() then setVariable('JukeboxMinimizedAnimatorHidden', '1'); setVariable('JukeboxMinimizedBaseHidden', '1') else setVariable('JukeboxMinimizedAnimatorHidden', hidden and '1' or '0'); setVariable('JukeboxMinimizedBaseHidden', hidden and '0' or '1') end; updateMinimizedMeters(); redraw() end
function seedMinimizedAnimatorRandom() if minimizedAnimatorRandomSeeded then return end; local seed = math.floor((os.time() + (currentWindowX() * 31) + (minimizedBottomY(currentWindowX()) * 17)) % 2147483647); if seed <= 0 then seed = os.time() end; math.randomseed(seed); math.random(); math.random(); math.random(); minimizedAnimatorRandomSeeded = true end
function chooseMinimizedPlayingSheetIndex() seedMinimizedAnimatorRandom(); local index = math.random(1, ANIMATOR_PLAYING_SHEET_COUNT); if minimizedAnimatorLastPlayingIndex > 0 and ANIMATOR_PLAYING_SHEET_COUNT > 1 then index = math.random(1, ANIMATOR_PLAYING_SHEET_COUNT - 1); if index >= minimizedAnimatorLastPlayingIndex then index = index + 1 end end; minimizedAnimatorLastPlayingIndex = index; return index end
function profileForMinimizedAnimatorSheet(sheetName, frameCount, frameMs) frameMs = tonumber(frameMs) or ANIMATOR_FRAME_MS; return { sheetPath = minimizedImagePath(sheetName), meterName = 'MeterJukeboxMinimizedAnimator', frameWidth = ANIMATOR_FRAME_WIDTH, frameHeight = MINIMIZED_ANIMATOR_FRAME_HEIGHT, frameCount = frameCount, columns = ANIMATOR_COLUMNS, tickMs = ANIMATOR_TICK_MS, frameMs = frameMs, mode = 'once', redrawOnFrameChangeOnly = true, skipCatchUp = frameMs <= ANIMATOR_FRAME_MS, maxCatchUpFrames = 4, frozen = false, freezeFrame = 0 } end
function buildMinimizedAnimator(sheetName, frameCount, frameMs) local profile = profileForMinimizedAnimatorSheet(sheetName, frameCount, frameMs); minimizedAnimatorCurrentFrameCount = profile.frameCount; minimizedAnimatorCurrentFrameMs = profile.frameMs; minimizedAnimator = loadAnimationEngine().create(SKIN, profile); minimizedAnimator:Initialize() end
function StopJukeboxMinimizedIdleTimer() JukeboxScheduler.minimizedIdle = false; syncJukeboxRuntimeDriver(); return 0 end
function StartJukeboxMinimizedIdleTimer() JukeboxScheduler.minimizedIdle = true; syncJukeboxRuntimeDriver(); return 0 end
function ContinueJukeboxMinimizedIdleTimer() if not JukeboxIsMinimizedForm() then return StopJukeboxMinimizedIdleTimer() end; return StartJukeboxMinimizedIdleTimer() end
function HideJukeboxMinimizedAnimation() minimizedAnimatorPhase = 'hidden'; minimizedAnimatorKind = ''; minimizedAnimatorElapsedMs = 0; minimizedAnimatorWaitMs = 0; if minimizedAnimator ~= nil then minimizedAnimator:Pause() end; setJukeboxMinimizedAnimatorHidden(true); syncJukeboxAnimationDriver(); return true end
function ForceHideJukeboxMinimizedAnimation() minimizedAnimatorPlaybackActive = false; setMinimizedPlaybackActiveVariable(false); return HideJukeboxMinimizedAnimation() end
function startMinimizedAnimatorTransition(kind) kind = normalizeAnimationKind(kind); buildMinimizedAnimator(ANIMATOR_TRANSITION_PROFILES[kind], ANIMATOR_TRANSITION_FRAME_COUNT, ANIMATOR_TRANSITION_FRAME_MS); minimizedAnimatorPhase = 'transition'; minimizedAnimatorKind = kind; minimizedAnimatorElapsedMs = 0; minimizedAnimatorWaitMs = 0; setJukeboxMinimizedAnimatorHidden(false); minimizedAnimator:Play(); syncJukeboxAnimationDriver() end
function startMinimizedPlayingSheet() local index = chooseMinimizedPlayingSheetIndex(); buildMinimizedAnimator('jukeboxSpriteSheet_playing' .. tostring(index) .. '.png', ANIMATOR_PLAYING_FRAME_COUNT, ANIMATOR_PLAYING_FRAME_MS); minimizedAnimatorPhase = 'playing'; minimizedAnimatorKind = 'playing'; minimizedAnimatorElapsedMs = 0; minimizedAnimatorWaitMs = 0; setJukeboxMinimizedAnimatorHidden(false); minimizedAnimator:Play(); syncJukeboxAnimationDriver() end
function enterMinimizedPlayingDelay() minimizedAnimatorPhase = 'waiting'; minimizedAnimatorKind = 'playing'; minimizedAnimatorElapsedMs = 0; minimizedAnimatorWaitMs = 0; if minimizedAnimator ~= nil then minimizedAnimator:Pause() end; setJukeboxMinimizedAnimatorHidden(true); syncJukeboxAnimationDriver() end
function SetJukeboxMinimizedPlaybackActive(value) minimizedAnimatorPlaybackActive = tostring(value or '') == '1' or tostring(value or ''):lower() == 'true'; setMinimizedPlaybackActiveVariable(minimizedAnimatorPlaybackActive); if not minimizedAnimatorPlaybackActive or isJukeboxNoteAnimationDisabled() then return HideJukeboxMinimizedAnimation() end; if minimizedAnimatorPhase == 'transition' then return true end; if minimizedAnimatorPhase ~= 'playing' and minimizedAnimatorPhase ~= 'waiting' then enterMinimizedPlayingDelay() end; return true end
function StartJukeboxMinimizedAnimation(kind) kind = normalizeAnimationKind(kind); if kind ~= 'play' then minimizedAnimatorPlaybackActive = false; setMinimizedPlaybackActiveVariable(false) end; HideJukeboxMinimizedAnimation(); if not JukeboxIsMinimizedForm() or isJukeboxNoteAnimationDisabled() then return false end; startMinimizedAnimatorTransition(kind); return true end
function restoreMinimizedPlaybackVisual() local active = trim(SKIN:GetVariable('JukeboxMinimizedPlaybackActive', '0')) == '1'; if not active and trim(SKIN:GetVariable('JukeboxPlaybackSelectedActive', '0')) == '1' then active = true end; return SetJukeboxMinimizedPlaybackActive(active and '1' or '0') end
function snapJukeboxMinimizedToBottomWhenIdle() if minimizedDragging then return false end; local y = currentWindowY(); local expectedY = minimizedBottomY(currentWindowX()); if minimizedLastWindowY ~= nil and y == minimizedLastWindowY and y == expectedY then return false end; minimizedLastWindowY = y; if y == expectedY then return false end; moveJukeboxToMinimizedBottom(currentWindowX()); return true end
function PollJukeboxMinimizedIdle() return safeCall(function() if not JukeboxIsMinimizedForm() then return StopJukeboxMinimizedIdleTimer() end; return snapJukeboxMinimizedToBottomWhenIdle() end) end
function ContinueJukeboxMinimizedAnimationAfterDelay() return safeCall(function() if not JukeboxIsMinimizedForm() or isJukeboxNoteAnimationDisabled() then HideJukeboxMinimizedAnimation(); return false end; if minimizedAnimatorPhase ~= 'waiting' then return false end; if not minimizedAnimatorPlaybackActive then HideJukeboxMinimizedAnimation(); return false end; startMinimizedPlayingSheet(); return true end) end
function UpdateJukeboxMinimizedAnimation() return safeCall(function() if not JukeboxIsMinimizedForm() then HideJukeboxMinimizedAnimation(); return false end; snapJukeboxMinimizedToBottomWhenIdle(); if isJukeboxNoteAnimationDisabled() then if minimizedAnimatorPhase ~= 'hidden' then HideJukeboxMinimizedAnimation() end; return false end; if minimizedAnimatorPhase == 'hidden' then return false end; if minimizedAnimatorPhase == 'waiting' then if not minimizedAnimatorPlaybackActive then HideJukeboxMinimizedAnimation(); return false end; minimizedAnimatorWaitMs = minimizedAnimatorWaitMs + ANIMATOR_TICK_MS; if minimizedAnimatorWaitMs >= ANIMATOR_PLAYING_DELAY_MS then startMinimizedPlayingSheet() end; return true end; if minimizedAnimator == nil then HideJukeboxMinimizedAnimation(); return false end; minimizedAnimator:Update(); minimizedAnimatorElapsedMs = minimizedAnimatorElapsedMs + ANIMATOR_TICK_MS; if minimizedAnimatorElapsedMs < (minimizedAnimatorCurrentFrameMs * math.max(1, minimizedAnimatorCurrentFrameCount)) then return true end; if minimizedAnimatorPhase == 'transition' then local finishedKind = minimizedAnimatorKind; if finishedKind == 'play' and minimizedAnimatorPlaybackActive then enterMinimizedPlayingDelay() else HideJukeboxMinimizedAnimation() end elseif minimizedAnimatorPhase == 'playing' then if minimizedAnimatorPlaybackActive then enterMinimizedPlayingDelay() else HideJukeboxMinimizedAnimation() end else HideJukeboxMinimizedAnimation() end; return true end) end
