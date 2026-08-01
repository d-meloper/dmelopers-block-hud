-- Generated runtime aggregate for Rainmeter-safe split loading. Edit sibling part files instead.
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
    JukeboxScheduler.eventPollRuntimeTicks = JUKEBOX_EVENT_POLL_RUNTIME_TICKS
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

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
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
    return '"' .. trim(SKIN:GetVariable('@', '')) .. 'Defaults\\Runtime\\helpers\\BlockHudPowerShellHost.exe"'
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

function minimizedWidth() return math.max(1, round(SKIN:GetVariable('JukeboxMinimizedW', '100'))) end
function minimizedHeight() return math.max(1, round(SKIN:GetVariable('JukeboxMinimizedH', '40'))) end
function currentWindowX() return round(SKIN:GetVariable('CURRENTCONFIGX', '0')) end
function currentWindowY() return round(SKIN:GetVariable('CURRENTCONFIGY', '0')) end
function jukeboxMinimizedWorkArea(x) local probeX = round((tonumber(x) or currentWindowX()) + (minimizedWidth() / 2)); local probeY = currentWindowY(); if JukeboxWorkAreaForPoint then return JukeboxWorkAreaForPoint(probeX, probeY, JukeboxCurrentWorkArea()) end; return JukeboxCurrentWorkArea() end
function minimizedBottomY(x) local work = jukeboxMinimizedWorkArea(x); return round(work.bottom - minimizedHeight()) end
function clampMinimizedX(x) local work = jukeboxMinimizedWorkArea(x); return round(JukeboxClampToRange(round(x), work.x, work.right - minimizedWidth())) end
function persistSharedJukeboxX(x, mainY) local targetX = clampMinimizedX(x); local y = storedJukeboxMainY(mainY); SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', string.format('SetFixedPosition(%q,%d,%d)', 'Jukebox', targetX, y)); return targetX end
function moveJukeboxToMinimizedBottom(x) local targetX = clampMinimizedX(x); local targetY = minimizedBottomY(targetX); SKIN:Bang('!Move', tostring(targetX), tostring(targetY)); minimizedLastWindowY = targetY; return targetX, targetY end
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

-- Split from ExtraContent\Jukebox\Jukebox.lua lines 1087-2207.
local function updateDiscSlotMeters(configName)
    if not isRainmeterConfigActive(configName) then
        return false
    end
    SKIN:Bang('!UpdateMeterGroup', 'JukeboxDiscSlot', configName)
    SKIN:Bang('!Redraw', configName)
    return true
end

local function applyDiscSlotLayout(configName)
    return commandMeasureForActiveConfig('MeasureResponsiveLayout', 'ApplyLayout()', configName)
end


local function resetDiscSlotAnchorState()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', "SetPositionModeForIds('JukeboxDiscSlot','auto')")
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', "ClearFixedPositionsForIds('JukeboxDiscSlot')")
end
local function syncDiscSlotVisualState(configName)
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'SyncVisualState()', configName)
    end
end

local function resetDiscSlotRenderStateForClose(configName)
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'ResetRenderStateForClose()', configName)
    end
end

local function refreshDiscSlot(configName)
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'RefreshDiscs()', configName)
    end
end

local function isDiscSlotCommandTargetActive()
    local configName = discSlotConfigName()
    if isRainmeterConfigActive(configName) then
        discSlotLoaded = true
        discSlotActivationRequested = false
        return true
    end
    discSlotLoaded = false
    return false
end
local function clearDiscSlotPlaybackSelection(configName)
    if not isDiscSlotCommandTargetActive() then
        return
    end
    configName = configName or discSlotConfigName()
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'ClearPlaybackSelection()', configName)
end

local function setDiscSlotPlaybackSelection(slotIndex, slotName, configName)
    if not isDiscSlotCommandTargetActive() then
        return
    end
    configName = configName or discSlotConfigName()
    slotIndex = tonumber(slotIndex) or 0
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', string.format('SetPlaybackSelection(%d,%q)', slotIndex, tostring(slotName or '')), configName)
end

local function writePlaybackStateValue(name, value)
    local path = playbackStatePath()
    if path == '' then
        return false
    end
    SKIN:Bang('!WriteKeyValue', 'Variables', name, tostring(value or ''), path)
    return true
end

local function writeJukeboxDisplayMode(mode)
    mode = trim(mode):lower()
    if mode ~= 'minimized' then
        mode = 'main'
    end
    setVariable('JukeboxDisplayMode', mode)
    writePlaybackStateValue('JukeboxDisplayMode', mode)
    return mode
end

function writeJukeboxMainFormY(y)
    local value = tostring(round(tonumber(y) or 0))
    setVariable('JukeboxMainFormY', value)
    writePlaybackStateValue('JukeboxMainFormY', value)
    return tonumber(value) or 0
end

function storedJukeboxMainY(fallbackY, preferSnapshot)
    if preferSnapshot then
        local saved = tonumber(trim(SKIN:GetVariable('JukeboxMainFormY', '')))
        if saved ~= nil then
            return round(saved)
        end
    end
    local y = tonumber(trim(SKIN:GetVariable('ResponsiveLayout_Jukebox_FixedY', '')))
    if y ~= nil then
        return round(y)
    end
    return round(tonumber(fallbackY) or 0)
end

local function writeGeneralSettingValue(name, value)
    local path = generalSettingsPath()
    if path == '' then
        return false
    end
    SKIN:Bang('!WriteKeyValue', 'Variables', name, tostring(value or ''), path)
    return true
end

local function setExternalPlaybackVariable(name, value)
    setVariable(name, value)
end

function currentPlaybackVolume()
    return clampPlaybackVolume(SKIN:GetVariable('JukeboxPlaybackVolume', tostring(100)))
end

function setLocalPlaybackVolume(value, persist)
    local volume = clampPlaybackVolume(value)
    setVariable('JukeboxPlaybackVolume', tostring(volume))
    if persist then
        writePlaybackStateValue('JukeboxPlaybackVolume', tostring(volume))
    end
    return volume
end

function resetExternalCommandWatch()
    externalPlaybackState.commandWatch.active = false
    externalPlaybackState.commandWatch.command = ''
    externalPlaybackState.commandWatch.valueText = ''
    externalPlaybackState.commandWatch.ticks = 0
    externalPlaybackState.commandWatch.beforeState = ''
    externalPlaybackState.commandWatch.beforeIdentity = ''
    externalPlaybackState.commandWatch.beforePlayer = ''
    externalPlaybackState.commandWatch.supportFlag = ''
    externalPlaybackState.commandWatch.supportValue = ''
    externalPlaybackState.commandWatch.bestEffort = false
    externalPlaybackState.commandWatch.reconnectRetry = false
    externalPlaybackState.commandWatch.waitingForReconnect = false
    externalPlaybackState.commandWatch.toggleFallbackTried = false
    JukeboxScheduler.externalCommandWatchdog = false
    syncJukeboxRuntimeDriver()
end

local function resetExternalPlaybackState()
    externalPlaybackState.observed = false
    externalPlaybackState.pendingCommand = nil
    externalPlaybackState.pendingValueText = nil
    externalPlaybackState.pendingCommandReconnectRetry = false
    resetExternalCommandWatch()
    externalPlaybackState.bridgeActive = false
    externalPlaybackState.bridgeActivationRequested = false
    externalPlaybackState.bridgeReconnectRequested = false
    externalPlaybackState.status = '0'
    externalPlaybackState.player = ''
    externalPlaybackState.title = ''
    externalPlaybackState.artist = ''
    externalPlaybackState.album = ''
    externalPlaybackState.cover = ''
    externalPlaybackState:clearCoverFetchFailure()
    externalPlaybackState.coverRetryNonce = 0
    externalPlaybackState.duration = '0'
    externalPlaybackState.volume = '0'
    externalPlaybackState.state = '0'
    externalPlaybackState.repeatMode = '0'
    externalPlaybackState.shuffle = '0'
    externalPlaybackState.supportsPlayPause = '0'
    externalPlaybackState.supportsSkipPrevious = '0'
    externalPlaybackState.supportsSkipNext = '0'
    externalPlaybackState.supportsSetVolume = '0'
    externalPlaybackState.supportsToggleRepeatMode = '0'
    externalPlaybackState.supportsToggleShuffleActive = '0'
    externalPlaybackState.mediaIdentity = ''
    externalPlaybackState.visualSwitch.active = false
    externalPlaybackState.visualSwitch.token = ''
    externalPlaybackState.visualSwitch.playAfterStop = false
    externalPlaybackState.visualSwitch.mediaIdentity = ''
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    setExternalPlaybackVariable('JukeboxExternalStatus', '0')
    setExternalPlaybackVariable('JukeboxExternalPlayer', '')
    setExternalPlaybackVariable('JukeboxExternalTitle', '')
    setExternalPlaybackVariable('JukeboxExternalArtist', '')
    setExternalPlaybackVariable('JukeboxExternalAlbum', '')
    setExternalPlaybackVariable('JukeboxExternalCover', '')
    setExternalPlaybackVariable('JukeboxExternalCoverFetchFailed', '0')
    setExternalPlaybackVariable('JukeboxExternalCoverFailureIdentity', '')
    setExternalPlaybackVariable('JukeboxExternalCoverRetryNonce', '0')
    setExternalPlaybackVariable('JukeboxExternalDuration', '0')
    setExternalPlaybackVariable('JukeboxExternalVolume', '0')
    setExternalPlaybackVariable('JukeboxExternalState', '0')
    setExternalPlaybackVariable('JukeboxExternalRepeat', '0')
    setExternalPlaybackVariable('JukeboxExternalShuffle', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsPlayPause', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsSkipPrevious', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsSkipNext', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsSetVolume', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsToggleRepeatMode', '0')
    setExternalPlaybackVariable('JukeboxExternalSupportsToggleShuffleActive', '0')
end

local function isExternalBridgeActive()
    if externalPlaybackState.pluginLoadFailed or trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1' then
        return false
    end
    local configName = webNowPlayingBridgeConfigName()
    if configName == '' or not isRainmeterConfigActive(configName) then
        return false
    end
    return externalPlaybackState.bridgeActive or trim(SKIN:GetVariable('JukeboxExternalBridgeActive', '0')) == '1'
end

local function activateExternalBridge()
    if externalPlaybackState.pluginLoadFailed or trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1' then
        return false
    end
    local configName = webNowPlayingBridgeConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end
    if isExternalBridgeActive() then
        return true
    end
    if isRainmeterConfigActive(configName) then
        externalPlaybackState.bridgeActivationRequested = true
        return true
    end
    if externalPlaybackState.bridgeActivationRequested then
        return true
    end
    externalPlaybackState.bridgeActive = false
    externalPlaybackState.bridgeActivationRequested = true
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    SKIN:Bang('!ActivateConfig', configName, 'WebNowPlayingBridge.ini')
    return true
end

local function deactivateExternalBridge()
    externalPlaybackState.pendingCommand = nil
    externalPlaybackState.pendingValueText = nil
    externalPlaybackState.pendingCommandReconnectRetry = false
    externalPlaybackState.bridgeActivationRequested = false
    externalPlaybackState.bridgeReconnectRequested = false
    local configName = webNowPlayingBridgeConfigName()
    if configName ~= '' and isRainmeterConfigActive(configName) then
        SKIN:Bang('!DeactivateConfig', configName)
    end
    externalPlaybackState.bridgeActive = false
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    return true
end

local function quarantineExternalBridgeForStartup(forceDeactivate)
    externalPlaybackState.pendingCommand = nil
    externalPlaybackState.pendingValueText = nil
    externalPlaybackState.pendingCommandReconnectRetry = false
    externalPlaybackState.bridgeActivationRequested = false
    externalPlaybackState.bridgeReconnectRequested = false
    externalPlaybackState.bridgeActive = false
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')

    local configName = webNowPlayingBridgeConfigName()
    if configName ~= '' and configName:find('[\\/]') and (forceDeactivate or isRainmeterConfigActive(configName)) then
        SKIN:Bang('!DeactivateConfig', configName)
    end
    return true
end

local function syncExternalBridgeForMode()
    if isExternalPlaybackSourceMode() then
        if commandRunning.webNowPlayingInstall or trim(webNowPlayingInstallState.phase) ~= '' then
            return false
        end
        return activateExternalBridge()
    end
    deactivateExternalBridge()
    resetExternalPlaybackState()
    externalPlaybackState.pluginLoadFailed = false
    externalPlaybackState.bridgeFailureAlertShown = false
    setExternalPlaybackVariable('JukeboxExternalBridgePluginFailed', '0')
    return true
end

local function syncDiscSlotPlaybackModeControls(configName)
    configName = configName or discSlotConfigName()
    if not isDiscSlotCommandTargetActive() then
        return false
    end
    local repeatMode = currentRepeatMode()
    local shuffleEnabled = currentShuffleEnabled()
    if isExternalPlaybackSourceMode() then
        repeatMode = externalRepeatMode()
        shuffleEnabled = externalShuffleEnabled()
    end
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackSourceMode', currentPlaybackSourceMode(), configName)
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackRepeatMode', repeatMode, configName)
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackShuffle', shuffleEnabled and '1' or '0', configName)
    SKIN:Bang('!SetVariable', 'JukeboxPlaybackVolume', tostring(currentPlaybackVolume()), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalBridgeActive', isExternalBridgeActive() and '1' or '0', configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalStatus', trim(externalPlaybackState.status), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalPlayer', trim(externalPlaybackState.player), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalTitle', trim(externalPlaybackState.title), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalArtist', trim(externalPlaybackState.artist), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalAlbum', trim(externalPlaybackState.album), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCover', trim(externalPlaybackState.cover), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCoverFetchFailed', externalPlaybackState:coverFailureMatchesCurrent() and '1' or '0', configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCoverFailureIdentity', trim(externalPlaybackState.coverFailureIdentity), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalCoverRetryNonce', tostring(tonumber(externalPlaybackState.coverRetryNonce) or 0), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalDuration', trim(externalPlaybackState.duration), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalVolume', trim(externalPlaybackState.volume), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalState', trim(externalPlaybackState.state), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsPlayPause', trim(externalPlaybackState.supportsPlayPause), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsSkipPrevious', trim(externalPlaybackState.supportsSkipPrevious), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsSkipNext', trim(externalPlaybackState.supportsSkipNext), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsSetVolume', trim(externalPlaybackState.supportsSetVolume), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsToggleRepeatMode', trim(externalPlaybackState.supportsToggleRepeatMode), configName)
    SKIN:Bang('!SetVariable', 'JukeboxExternalSupportsToggleShuffleActive', trim(externalPlaybackState.supportsToggleShuffleActive), configName)
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', 'SyncVisualState()', configName)
    return true
end

local function syncSettingsPlaybackSourceMode()
    local mode = currentPlaybackSourceMode()
    local root = rootConfigName()
    local configName = root == '' and 'HUD\\Settings' or root .. '\\HUD\\Settings'
    if isRainmeterConfigActive(configName) then
        SKIN:Bang('!SetVariable', 'JukeboxPlaybackSourceMode', mode, configName)
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsCommit', 'SyncJukeboxPlaybackSourceMode()', configName)
    end
end
local function syncPlaybackModeState(persist, skipDiscSlotSync)
    local mode = currentRepeatMode()
    local shuffle = currentShuffleEnabled()
    setVariable('JukeboxPlaybackRepeatMode', mode)
    setVariable('JukeboxPlaybackShuffle', shuffle and '1' or '0')
    if persist then
        writePlaybackStateValue('JukeboxPlaybackRepeatMode', mode)
        writePlaybackStateValue('JukeboxPlaybackShuffle', shuffle and '1' or '0')
    end
    if not skipDiscSlotSync then
        syncDiscSlotPlaybackModeControls()
    end
    return mode, shuffle
end

local function requestHelperLoopModeSync()
    if isExternalPlaybackSourceMode() then
        return false
    end
    if runMeasure then
        return runMeasure('loop', 'MeasureJukeboxSetLoopRun', 'ModalAlert_JukeboxCommandFailed')
    end
    return false
end

function requestHelperVolumeSync(volume)
    if isExternalPlaybackSourceMode() then
        return false
    end
    if commandRunning.volume then
        commandRunning.volumePending = true
        return true
    end
    setVariable('JukeboxSetVolumeArgs', buildArgs('SetVolume', '', '', isPlaybackLoopEnabled(), clampPlaybackVolume(volume)))
    if runMeasure then
        return runMeasure('volume', 'MeasureJukeboxSetVolumeRun', 'ModalAlert_JukeboxCommandFailed')
    end
    return false
end

local function persistPlaybackSelection(slotIndex, slotName, path)
    slotIndex = tonumber(slotIndex) or 0
    slotName = tostring(slotName or '')
    path = tostring(path or '')
    writePlaybackStateValue('JukeboxPlaybackSelectedActive', '1')
    writePlaybackStateValue('JukeboxPlaybackSelectedSlotIndex', tostring(slotIndex))
    writePlaybackStateValue('JukeboxPlaybackSelectedName', slotName)
    writePlaybackStateValue('JukeboxPlaybackSelectedPath', path)
    setVariable('JukeboxPlaybackSelectedActive', '1')
    setVariable('JukeboxPlaybackSelectedSlotIndex', tostring(slotIndex))
    setVariable('JukeboxPlaybackSelectedName', slotName)
    setVariable('JukeboxPlaybackSelectedPath', path)
end

local function clearPersistedPlaybackSelection()
    writePlaybackStateValue('JukeboxPlaybackSelectedActive', '0')
    writePlaybackStateValue('JukeboxPlaybackSelectedSlotIndex', '0')
    writePlaybackStateValue('JukeboxPlaybackSelectedName', '')
    writePlaybackStateValue('JukeboxPlaybackSelectedPath', '')
    setVariable('JukeboxPlaybackSelectedActive', '0')
    setVariable('JukeboxPlaybackSelectedSlotIndex', '0')
    setVariable('JukeboxPlaybackSelectedName', '')
    setVariable('JukeboxPlaybackSelectedPath', '')
end

local function currentPlaybackSelection()
    return {
        active = trim(SKIN:GetVariable('JukeboxPlaybackSelectedActive', '0')) == '1',
        slotIndex = tonumber(trim(SKIN:GetVariable('JukeboxPlaybackSelectedSlotIndex', '0'))) or 0,
        slotName = trim(SKIN:GetVariable('JukeboxPlaybackSelectedName', '')),
        path = trim(SKIN:GetVariable('JukeboxPlaybackSelectedPath', '')),
    }
end

local function slotMatchesPlaybackSelection(slotIndex, slotName, path, state)
    state = state or currentPlaybackSelection()
    if not state.active then
        return false
    end
    slotIndex = tonumber(slotIndex) or 0
    slotName = trim(slotName)
    path = trim(path)
    if state.slotIndex > 0 and state.slotIndex == slotIndex and state.slotName == slotName then
        return true
    end
    return state.path ~= '' and path ~= '' and state.path == path
end

local function shouldSwitchDiscSlotPlayback(slotIndex, slotName, path)
    local state = currentPlaybackSelection()
    if not state.active then
        return false
    end
    return not slotMatchesPlaybackSelection(slotIndex, slotName, path, state)
end

local function captureJukeboxLiveState()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()')
end

function JukeboxApplyCurrentResponsiveLayout()
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')
end

local function currentJukeboxLiveRect()
    local x = round(tonumber(SKIN:GetVariable('CURRENTCONFIGX', '0')) or 0)
    local y = round(tonumber(SKIN:GetVariable('CURRENTCONFIGY', '0')) or 0)
    local width = tonumber(SKIN:GetVariable('JukeboxW', ''))
    local height = tonumber(SKIN:GetVariable('JukeboxH', ''))
    if not width or width <= 0 then
        width = tonumber(SKIN:GetVariable('CURRENTCONFIGWIDTH', '0'))
    end
    if not height or height <= 0 then
        height = tonumber(SKIN:GetVariable('CURRENTCONFIGHEIGHT', '0'))
    end
    if not width or width <= 0 then
        width = 100
    end
    if not height or height <= 0 then
        height = 126
    end
    return {
        x = x,
        y = y,
        width = round(width),
        height = round(height),
    }
end

function JukeboxCurrentWorkArea()
    local x = round(tonumber(SKIN:GetVariable('PWORKAREAX', '0')) or 0)
    local y = round(tonumber(SKIN:GetVariable('PWORKAREAY', '0')) or 0)
    local width = math.max(1, round(tonumber(SKIN:GetVariable('PWORKAREAWIDTH', '1920')) or 1920))
    local height = math.max(1, round(tonumber(SKIN:GetVariable('PWORKAREAHEIGHT', '1032')) or 1032))
    return {
        x = x,
        y = y,
        width = width,
        height = height,
        right = x + width,
        bottom = y + height,
    }
end

local function jukeboxWorkAreaRect(x, y, width, height)
    x = round(tonumber(x) or 0)
    y = round(tonumber(y) or 0)
    width = math.max(1, round(tonumber(width) or 1))
    height = math.max(1, round(tonumber(height) or 1))
    return {
        x = x,
        y = y,
        width = width,
        height = height,
        right = x + width,
        bottom = y + height,
        centerX = x + (width / 2),
        centerY = y + (height / 2),
    }
end

local function jukeboxMonitorWorkAreas()
    local result = {}
    local seen = {}
    for index = 1, 16 do
        local x = tonumber(SKIN:GetVariable('WORKAREAX@' .. tostring(index), ''))
        local y = tonumber(SKIN:GetVariable('WORKAREAY@' .. tostring(index), ''))
        local width = tonumber(SKIN:GetVariable('WORKAREAWIDTH@' .. tostring(index), ''))
        local height = tonumber(SKIN:GetVariable('WORKAREAHEIGHT@' .. tostring(index), ''))
        if x and y and width and height and width > 0 and height > 0 then
            local rect = jukeboxWorkAreaRect(x, y, width, height)
            local key = table.concat({ rect.x, rect.y, rect.width, rect.height }, ':')
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = rect
            end
        end
    end
    return result
end

local function jukeboxRectContainsPoint(rect, x, y)
    return rect and x >= rect.x and x < rect.right and y >= rect.y and y < rect.bottom
end

local function jukeboxDistanceSquaredToRectCenter(rect, x, y)
    local dx = (rect.centerX or 0) - x
    local dy = (rect.centerY or 0) - y
    return (dx * dx) + (dy * dy)
end

function JukeboxWorkAreaForPoint(x, y, fallback)
    x = round(tonumber(x) or 0)
    y = round(tonumber(y) or 0)
    local areas = jukeboxMonitorWorkAreas()
    local best = nil
    local bestDistance = nil
    for _, area in ipairs(areas) do
        if jukeboxRectContainsPoint(area, x, y) then
            return area
        end
        local distance = jukeboxDistanceSquaredToRectCenter(area, x, y)
        if best == nil or distance < bestDistance then
            best = area
            bestDistance = distance
        end
    end
    return best or fallback or JukeboxCurrentWorkArea()
end

local function jukeboxWorkAreaForRect(rect, fallback)
    rect = rect or currentJukeboxLiveRect()
    local width = math.max(1, round(tonumber(rect.width) or 100))
    local height = math.max(1, round(tonumber(rect.height) or 126))
    local x = round((tonumber(rect.x) or 0) + (width / 2))
    local y = round((tonumber(rect.y) or 0) + (height / 2))
    return JukeboxWorkAreaForPoint(x, y, fallback)
end

function JukeboxClampToRange(value, minValue, maxValue)
    value = tonumber(value) or 0
    if maxValue < minValue then
        maxValue = minValue
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function JukeboxClampRectToWorkArea(rect)
    rect = rect or currentJukeboxLiveRect()
    local width = math.max(1, round(tonumber(rect.width) or 100))
    local height = math.max(1, round(tonumber(rect.height) or 126))
    local work = jukeboxWorkAreaForRect(rect, JukeboxCurrentWorkArea())
    return {
        x = round(JukeboxClampToRange(rect.x, work.x, work.right - width)),
        y = round(JukeboxClampToRange(rect.y, work.y, work.bottom - height)),
        width = width,
        height = height,
    }
end

local function syncJukeboxLiveStateToDiscSlot(configName)
    configName = configName or discSlotConfigName()
    local rect = currentJukeboxLiveRect()
    if not isRainmeterConfigActive(configName) then
        return false
    end
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveActive', '1', configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveWindowX', tostring(rect.x), configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveWindowY', tostring(rect.y), configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveWidth', tostring(rect.width), configName)
    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Jukebox_LiveHeight', tostring(rect.height), configName)
    return true
end

local function isDiscSlotActive()
    return trim(SKIN:GetVariable('ResponsiveLayout_JukeboxDiscSlot_LiveActive', '0')) == '1'
end

local function scheduleDiscSlotDeferredSync()
    discSlotDeferredAttempts = 0
    discSlotRefreshRecoveryRequested = false
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Execute 1')
end

local function isJukeboxDragAllowed()
    return trim(SKIN:GetVariable('AllowJukeboxDrag', '1')) == '1'
end

local function isJukeboxSnapAllowed()
    return trim(SKIN:GetVariable('AllowJukeboxSnapEdges', '0')) == '1'
end

local function setJukeboxDraggable(enabled)
    SKIN:Bang('!Draggable', enabled and isJukeboxDragAllowed() and '1' or '0')
    SKIN:Bang('!SnapEdges', isJukeboxSnapAllowed() and '1' or '0')
end

local function setDiscSlotHidden(hidden)
    local configName = discSlotConfigName()
    if setVariableForActiveConfig('JukeboxDiscSlotHidden', hidden and '1' or '0', configName) then
        updateDiscSlotMeters(configName)
        if hidden then
            JukeboxDiscSlotLifecycleSurface():CommandIfActive('MeasureJukeboxDiscSlot', 'SuspendDiscSlotResident()')
        end
    end
    return configName
end

local function deactivateDiscSlotSkin()
    discSlotPendingShow = false
    discSlotPendingShowSkipRefresh = false
    local configName = discSlotConfigName()
    local surface = JukeboxDiscSlotLifecycleSurface()
    if isRainmeterConfigActive(configName) then
        resetDiscSlotRenderStateForClose(configName)
        setDiscSlotHidden(true)
        syncDiscSlotVisualState(configName)
        surface:HideIfActive()
        discSlotLoaded = true
    else
        discSlotLoaded = false
    end
    discSlotActivationRequested = false
    setJukeboxDraggable(true)
    discSlotVisible = false
    return true
end
local function activateDiscSlot()
    local configName = discSlotConfigName()
    if isRainmeterConfigActive(configName) then
        discSlotLoaded = true
        discSlotActivationRequested = false
        discSlotRefreshRecoveryRequested = false
        return configName, false
    end
    if discSlotActivationRequested then
        return configName, true
    end
    discSlotLoaded = false
    JukeboxDiscSlotLifecycleSurface():ActivateIfInactive()
    discSlotActivationRequested = true
    discSlotLoaded = true
    return configName, true
end
local showDiscSlotNow = nil
function PreloadDiscSlotSkin()
    local configName = discSlotConfigName()
    if discSlotPendingShow then
        return false
    end
    if discSlotVisible and isDiscSlotCommandTargetActive() then
        return showDiscSlotNow(configName, true)
    end
    if isDiscSlotCommandTargetActive() then
        setVariableForActiveConfig('JukeboxDiscSlotHidden', '1', configName)
    end
    discSlotVisible = false
    return true
end

showDiscSlotNow = function(configName, skipRefresh)
    configName = configName or discSlotConfigName()
    local surface = JukeboxDiscSlotLifecycleSurface()
    if not surface:SetVariableIfActive('JukeboxDiscSlotHidden', '0') then
        discSlotLoaded = false
        discSlotActivationRequested = false
        discSlotRefreshRecoveryRequested = false
        return false
    end
    surface:ShowIfActive()
    surface:CommandIfActive('MeasureJukeboxDiscSlot', 'ResumeDiscSlotResident()')
    syncJukeboxLiveStateToDiscSlot(configName)
    applyDiscSlotLayout(configName)
    syncDiscSlotPlaybackModeControls(configName)
    updateDiscSlotMeters(configName)
    SKIN:Bang('!Redraw', configName)
    setJukeboxDraggable(false)
    discSlotVisible = true
    discSlotPendingShow = false
    discSlotPendingShowSkipRefresh = false
    discSlotActivationRequested = false
    discSlotRefreshRecoveryRequested = false
    discSlotDeferredAttempts = 0
    if not skipRefresh then
        refreshDiscSlot(configName)
    end
    return true
end
local function formatSummary(summary, placeholders)
    summary = tostring(summary or '')
    if type(placeholders) ~= 'table' then
        placeholders = { placeholders }
    end
    for index, placeholder in ipairs(placeholders) do
        local replacement = trim(placeholder):gsub('%%', '%%%%')
        summary = summary:gsub('%%' .. tostring(index), replacement)
    end
    return summary
end

local function decodeCatalogEscapes(value)
    return tostring(value or '')
        :gsub('\\n', '\n')
        :gsub('\\r', '\r')
        :gsub('\\t', '\t')
end

local function localizedSummary(key, fallback, placeholders)
    key = trim(key)
    local summary = ''
    if key ~= '' then
        summary = trim(SKIN:GetVariable('Loc_' .. key, fallback or ''))
    end
    if summary == '' then
        summary = trim(fallback or '')
    end
    return formatSummary(decodeCatalogEscapes(summary), placeholders)
end

local function showAlert(level, summaryKey, fallback, logPath, placeholder, options)
    local modal = ensureBridge()
    if not modal then
        SKIN:Bang('!Log', trim(fallback or 'Jukebox alert could not be shown.'), 'Error')
        return false
    end

    options = options or {}
    return modal.ShowAlertByKeys(modalAlertHost(), {
        level = level,
        summaryKey = summaryKey,
        summaryText = localizedSummary(summaryKey, fallback, placeholder),
        logPath = logPath or modalAlertLogPath(),
        primaryKey = options.primaryKey,
        openFolderPath = options.openFolderPath,
    })
end

function webNowPlayingInstallState.luaString(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\')
    value = value:gsub("'", "\\'")
    value = value:gsub('\r', '\\r')
    value = value:gsub('\n', '\\n')
    return "'" .. value .. "'"
end

function webNowPlayingInstallState.localized(key, englishFallback, koreanFallback)
    local languageCode = trim(SKIN:GetVariable('LanguageCode', '')):lower()
    local fallback = englishFallback
    if languageCode:find('ko', 1, true) == 1 then
        fallback = koreanFallback or englishFallback
    end
    return localizedSummary(key, fallback)
end

function webNowPlayingInstallState.localizedWithPlaceholder(key, englishFallback, koreanFallback, placeholder)
    local languageCode = trim(SKIN:GetVariable('LanguageCode', '')):lower()
    local fallback = englishFallback
    if languageCode:find('ko', 1, true) == 1 then
        fallback = koreanFallback or englishFallback
    end
    return localizedSummary(key, fallback, placeholder)
end

function webNowPlayingInstallState.modalConfigName()
    local root = rootConfigName()
    if root == '' then
        return 'Utilities\\Modal'
    end
    return root .. '\\Utilities\\Modal'
end

function webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.token = webNowPlayingInstallState.token + 1
    if webNowPlayingInstallState.token > 1000000 then
        webNowPlayingInstallState.token = 1
    end
    return 'web-now-playing-install-' .. tostring(webNowPlayingInstallState.token)
end

function webNowPlayingInstallState.requestDeferredOpen()
    SKIN:Bang('!SetVariable', 'BlockHudJukeboxWebNowPlayingInstallDeferredOpen', '0')
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxWebNowPlayingInstallDeferredOpen')
    SKIN:Bang('!SetVariable', 'BlockHudJukeboxWebNowPlayingInstallDeferredOpen', '1')
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxWebNowPlayingInstallDeferredOpen')
end

function webNowPlayingInstallState.openInstallConfirm()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenConfirm('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingInstallTitle', 'Plugin installation', '플러그인 설치')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingInstallMessage', 'Install the WebNowPlaying plugin for external music app integration. (Size: 52.5KB)', '외부 뮤직 앱 연동을 위해 WebNowPlaying 플러그인을 설치합니다. (용량: 52.5KB)')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingInstallButton', 'Install', '설치')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('Common_Cancel', 'Cancel', '취소')) .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('ConfirmWebNowPlayingInstall') .. ','
        .. webNowPlayingInstallState.luaString('CancelWebNowPlayingInstall') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end

function webNowPlayingInstallState.portOwnerFallbackLabel()
    return webNowPlayingInstallState.localized(
        'ModalAlert_WebNowPlayingUnknownOwner',
        'another Windows local account',
        'another Windows local account')
end

function webNowPlayingInstallState.setPortOwner(values)
    values = values or {}
    webNowPlayingInstallState.ownerPid = trim(values.DMEL_OWNER_PID or '')
    webNowPlayingInstallState.ownerUser = trim(values.DMEL_OWNER_USER or '')
    webNowPlayingInstallState.ownerDomain = trim(values.DMEL_OWNER_DOMAIN or '')
    if webNowPlayingInstallState.ownerUser ~= '' and webNowPlayingInstallState.ownerDomain ~= '' then
        webNowPlayingInstallState.ownerLabel = webNowPlayingInstallState.ownerDomain .. '\\' .. webNowPlayingInstallState.ownerUser
    elseif webNowPlayingInstallState.ownerUser ~= '' then
        webNowPlayingInstallState.ownerLabel = webNowPlayingInstallState.ownerUser
    else
        webNowPlayingInstallState.ownerLabel = webNowPlayingInstallState.portOwnerFallbackLabel()
    end
end

function webNowPlayingInstallState.openPortOwnerTerminateConfirm()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenConfirm('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingConflictTitle', 'Music app conflict', 'Music app conflict')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingPortInUseOtherUser', 'Rainmeter is running in another Windows local account and is connected to the WebNowPlaying port, causing a conflict.\\nTo use an external music app in the current local account, the process in the other local account must be terminated.\\nTerminate that Rainmeter process now?', 'Rainmeter is running in another Windows local account and is connected to the WebNowPlaying port, causing a conflict.\\nTo use an external music app in the current local account, the process in the other local account must be terminated.\\nTerminate that Rainmeter process now?')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingTerminateOtherProcess', 'Terminate process', 'Terminate process')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('Common_Close', 'Close', 'Close')) .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('ConfirmWebNowPlayingPortOwnerTerminate') .. ','
        .. webNowPlayingInstallState.luaString('CancelWebNowPlayingPortOwnerTerminate') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end

function webNowPlayingInstallState.openPortOwnerForceConfirm()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenConfirm('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingConflictTitle', 'Music app conflict', 'Music app conflict')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingTerminateConfirm', 'Force termination can cause unexpected problems. We recommend logging into that Windows account and closing Rainmeter manually. Force terminate now?', 'Force termination can cause unexpected problems. We recommend logging into that Windows account and closing Rainmeter manually. Force terminate now?')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('ModalAlert_WebNowPlayingForceTerminate', 'Force terminate', 'Force terminate')) .. ','
        .. webNowPlayingInstallState.luaString(webNowPlayingInstallState.localized('Common_Close', 'Close', 'Close')) .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('ForceTerminateWebNowPlayingPortOwner') .. ','
        .. webNowPlayingInstallState.luaString('CancelWebNowPlayingPortOwnerTerminate') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end

function webNowPlayingInstallState.openInstallProgress()
    local configName = webNowPlayingInstallState.modalConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local token = webNowPlayingInstallState.nextToken()
    webNowPlayingInstallState.openCommand = 'OpenByKeys('
        .. webNowPlayingInstallState.luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
        .. webNowPlayingInstallState.luaString(token) .. ','
        .. webNowPlayingInstallState.luaString('Loc_ModalAlert_WebNowPlayingInstallTitle') .. ','
        .. webNowPlayingInstallState.luaString('Loc_ModalAlert_WebNowPlayingInstallProgress') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('MeasureJukebox') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('') .. ','
        .. webNowPlayingInstallState.luaString('none') .. ')'

    webNowPlayingInstallState.requestDeferredOpen()
    return true
end
function webNowPlayingInstallState.showInstallAlert(level, key, englishFallback, koreanFallback)
    local languageCode = trim(SKIN:GetVariable('LanguageCode', '')):lower()
    local fallback = englishFallback
    if languageCode:find('ko', 1, true) == 1 then
        fallback = koreanFallback or englishFallback
    end
    return showAlert(level, key, fallback, modalAlertLogPath())
end
local function hotbarConfigName()
    local root = trim(SKIN:GetVariable('ROOTCONFIG', ''))
    if root == '' then
        return ''
    end
    return root .. '\\HUD\\Hotbar'
end

local function currentPlaybackHotbarText(trackName)
    return localizedSummary('Jukebox_NowPlayingFormat', 'Now playing: %1', trackName)
end

local function showHotbarText(text, pinned)
    text = trim(text)
    if text == '' then
        return false
    end

    local configName = hotbarConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end

    local command = pinned
        and string.format('ShowPinnedExternalHotbarText(%q,%q,%q)', 'Jukebox', text, 'scroll')
        or string.format('ShowExternalHotbarText(%q,%q)', text, 'scroll')
    commandMeasureForActiveConfig('MeasureHighlight', command, configName)
    return true
end

local function showCurrentPlaybackHotbarTextForSelection(selection, pinned)
    selection = selection or currentPlaybackSelection()
    if not selection.active then
        return false
    end

    local trackName = trim(selection.slotName)
    if trackName == '' then
        return false
    end

    return showHotbarText(currentPlaybackHotbarText(trackName), pinned)
end

local function externalPlaybackDisplayName()
    local title = trim(externalPlaybackState.title)
    local artist = trim(externalPlaybackState.artist)
    if title ~= '' and artist ~= '' then
        return title .. ' - ' .. artist
    elseif title ~= '' then
        return title
    elseif artist ~= '' then
        return artist
    end
    return ''
end

local function externalPlaybackConnected()
    if externalPlaybackState.pluginLoadFailed or not externalPlaybackState.bridgeActive then
        return false
    end
    -- WebNowPlaying Status is the connection signal; Player is display metadata and may be blank for some native/desktop sources.
    return trim(externalPlaybackState.status) == '1'
end

function externalCommandSupportFlag(command)
    if command == 'PlayPause' or command == 'Play' or command == 'Pause' then
        return 'supportsPlayPause'
    elseif command == 'Next' then
        return 'supportsSkipNext'
    elseif command == 'Previous' then
        return 'supportsSkipPrevious'
    elseif command == 'Repeat' then
        return 'supportsToggleRepeatMode'
    elseif command == 'Shuffle' then
        return 'supportsToggleShuffleActive'
    elseif command == 'SetVolume' then
        return 'supportsSetVolume'
    end
    return ''
end

function externalCommandCanRunBestEffort(command)
    return command == 'PlayPause' or command == 'Play' or command == 'Pause' or command == 'Next' or command == 'Previous'
end

function externalCommandLogKey(reason, command, suffix)
    return tostring(reason or '') .. ':' .. tostring(command or '') .. ':' .. tostring(suffix or '')
end

function logExternalCommand(message, level)
    SKIN:Bang('!Log', tostring(message or ''), level or 'Notice')
end

function logExternalCommandThrottled(key, message, level, throttleSeconds)
    key = tostring(key or '')
    local now = os.time() or 0
    local throttle = tonumber(throttleSeconds) or EXTERNAL_COMMAND_LOG_THROTTLE_SECONDS
    local previous = externalPlaybackState.commandLogTimes[key] or 0
    if previous > 0 and now < previous + throttle then
        return false
    end
    externalPlaybackState.commandLogTimes[key] = now
    logExternalCommand(message, level)
    return true
end

function externalCommandSupportState(command)
    local supportFlag = externalCommandSupportFlag(command)
    if supportFlag == '' then
        return '', '', true, false
    end
    local supportValue = trim(externalPlaybackState[supportFlag]):lower()
    local supported = supportValue == '1' or supportValue == 'true'
    local bestEffort = false
    if not supported and externalCommandCanRunBestEffort(command) and externalPlaybackConnected() then
        bestEffort = true
        supported = true
    end
    return supportFlag, supportValue, supported, bestEffort
end

local showCurrentExternalPlaybackHotbarText
showExternalPlayerUnavailable = nil

function beginExternalCommandWatch(command, valueText, supportFlag, supportValue, bestEffort, reconnectRetry, toggleFallbackTried)
    externalPlaybackState.commandWatch.active = true
    externalPlaybackState.commandWatch.command = trim(command)
    externalPlaybackState.commandWatch.valueText = trim(valueText)
    externalPlaybackState.commandWatch.ticks = 0
    externalPlaybackState.commandWatch.beforeState = trim(externalPlaybackState.state)
    externalPlaybackState.commandWatch.beforeIdentity = externalPlaybackState:trackIdentity()
    externalPlaybackState.commandWatch.beforePlayer = trim(externalPlaybackState.player)
    externalPlaybackState.commandWatch.supportFlag = trim(supportFlag)
    externalPlaybackState.commandWatch.supportValue = trim(supportValue)
    externalPlaybackState.commandWatch.bestEffort = bestEffort and true or false
    externalPlaybackState.commandWatch.reconnectRetry = reconnectRetry and true or false
    externalPlaybackState.commandWatch.waitingForReconnect = false
    externalPlaybackState.commandWatch.toggleFallbackTried = toggleFallbackTried and true or false
    JukeboxScheduler.externalCommandWatchdog = true
    syncJukeboxRuntimeDriver()
end

function externalCommandObservedResult()
    if not externalPlaybackState.commandWatch.active then
        return true
    end
    if externalPlaybackState.pluginLoadFailed or not externalPlaybackConnected() then
        return false
    end
    local command = externalPlaybackState.commandWatch.command
    local currentState = trim(externalPlaybackState.state)
    if command == 'Play' then
        return currentState == '1'
    elseif command == 'Pause' then
        return currentState ~= '1'
    elseif command == 'PlayPause' then
        return currentState ~= '' and currentState ~= externalPlaybackState.commandWatch.beforeState
    elseif command == 'Next' or command == 'Previous' then
        local beforeIdentity = trim(externalPlaybackState.commandWatch.beforeIdentity)
        local currentIdentity = externalPlaybackState:trackIdentity()
        return beforeIdentity ~= '' and currentIdentity ~= '' and currentIdentity ~= beforeIdentity
    elseif command == 'Repeat' then
        return trim(externalPlaybackState.repeatMode) ~= ''
    elseif command == 'Shuffle' then
        return trim(externalPlaybackState.shuffle) ~= ''
    elseif command == 'SetVolume' then
        return trim(externalPlaybackState.volume) == trim(externalPlaybackState.commandWatch.valueText)
    end
    return true
end

function finishExternalCommandWatchIfObserved()
    if externalPlaybackState.commandWatch.active and externalCommandObservedResult() then
        resetExternalCommandWatch()
        return true
    end
    return false
end

function requestExternalBridgeReconnect(command, valueText)
    command = trim(command)
    if command == '' or externalPlaybackState.bridgeReconnectRequested then
        return false
    end
    local configName = webNowPlayingBridgeConfigName()
    if configName == '' or not configName:find('[\\/]') then
        return false
    end
    local requested = false
    if isRainmeterConfigActive(configName) then
        requested = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', 'Reconnect()', configName)
    else
        externalPlaybackState.bridgeActivationRequested = false
        requested = activateExternalBridge()
    end
    if not requested then
        return false
    end
    externalPlaybackState.bridgeReconnectRequested = true
    externalPlaybackState.pendingCommand = command
    externalPlaybackState.pendingValueText = trim(valueText)
    externalPlaybackState.pendingCommandReconnectRetry = true
    externalPlaybackState.bridgeActive = false
    setExternalPlaybackVariable('JukeboxExternalBridgeActive', '0')
    logExternalCommandThrottled(
        externalCommandLogKey('bridge-reconnect', command, trim(externalPlaybackState.player)),
        'Jukebox WebNowPlaying reconnect requested after command produced no observable state change: command=' .. command .. ' player=' .. trim(externalPlaybackState.player),
        'Warning',
        5)
    return true
end

local function requestExternalPlayPauseFallback(previousCommand)
    previousCommand = trim(previousCommand)
    if previousCommand ~= 'Play' and previousCommand ~= 'Pause' then
        return false
    end
    if externalPlaybackState.commandWatch.toggleFallbackTried then
        return false
    end
    if not externalPlaybackConnected() then
        return false
    end

    local fallbackCommand = 'PlayPause'
    local supportFlag, supportValue, supported, bestEffort = externalCommandSupportState(fallbackCommand)
    if not supported then
        return false
    end

    local sent = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', string.format('SendCommand(%q,%q)', fallbackCommand, ''), webNowPlayingBridgeConfigName())
    if not sent then
        return false
    end

    logExternalCommandThrottled(
        externalCommandLogKey('toggle-fallback', previousCommand, trim(externalPlaybackState.player)),
        'Jukebox WebNowPlaying command fallback sent after no observable state change: original=' .. previousCommand
            .. ' fallback=' .. fallbackCommand
            .. ' player=' .. trim(externalPlaybackState.player)
            .. ' support=' .. trim(supportFlag) .. '=' .. trim(supportValue)
            .. ' bestEffort=' .. (bestEffort and '1' or '0'),
        'Warning',
        5)
    beginExternalCommandWatch(fallbackCommand, '', supportFlag, supportValue, bestEffort, externalPlaybackState.commandWatch.reconnectRetry, true)
    return true
end

function tickExternalCommandWatchdog()
    if not externalPlaybackState.commandWatch.active then
        JukeboxScheduler.externalCommandWatchdog = false
        return false
    end
    if finishExternalCommandWatchIfObserved() then
        return true
    end
    externalPlaybackState.commandWatch.ticks = externalPlaybackState.commandWatch.ticks + 1
    if externalPlaybackState.commandWatch.ticks < EXTERNAL_COMMAND_WATCHDOG_TIMEOUT_TICKS then
        return true
    end
    local message = 'Jukebox WebNowPlaying command had no observable state change: command=' .. externalPlaybackState.commandWatch.command
        .. ' player=' .. trim(externalPlaybackState.player)
        .. ' state=' .. trim(externalPlaybackState.state)
        .. ' support=' .. trim(externalPlaybackState.commandWatch.supportFlag) .. '=' .. trim(externalPlaybackState.commandWatch.supportValue)
        .. ' bestEffort=' .. (externalPlaybackState.commandWatch.bestEffort and '1' or '0')
    local command = externalPlaybackState.commandWatch.command
    if requestExternalPlayPauseFallback(command) then
        return true
    end
    if not externalPlaybackState.commandWatch.reconnectRetry and requestExternalBridgeReconnect(command, externalPlaybackState.commandWatch.valueText) then
        externalPlaybackState.commandWatch.ticks = 0
        externalPlaybackState.commandWatch.reconnectRetry = true
        externalPlaybackState.commandWatch.waitingForReconnect = true
        return true
    end
    logExternalCommandThrottled(externalCommandLogKey('no-state-change', command, externalPlaybackState.commandWatch.beforePlayer), message, 'Warning')
    resetExternalCommandWatch()
    setJukeboxAnimatorPlaybackActive(externalPlaybackConnected() and trim(externalPlaybackState.state) == '1')
    syncDiscSlotPlaybackModeControls()
    showExternalPlayerUnavailable('no-observable-change', command)
    return false
end

function externalPlaybackState:trackIdentity()
    local player = trim(self.player)
    local title = trim(self.title)
    local artist = trim(self.artist)
    local album = trim(self.album)
    if title ~= '' or artist ~= '' or album ~= '' then
        return table.concat({ player, title, artist, album }, '\31')
    end
    return table.concat({ player, trim(self.cover), trim(self.duration) }, '\31')
end

function externalPlaybackState:hasTrackIdentity()
    return trim(self.title) ~= '' or trim(self.artist) ~= '' or trim(self.album) ~= '' or trim(self.cover) ~= ''
end

function externalPlaybackState:currentCoverFailureIdentity()
    return trim(self:trackIdentity())
end

function externalPlaybackState:clearCoverFetchFailure()
    self.coverFetchFailed = false
    self.coverFailureIdentity = ''
    self.coverFailureUrl = ''
    self.coverFailureStatus = ''
end

function externalPlaybackState:markCoverFetchFailure(url, statusCode)
    local identity = self:currentCoverFailureIdentity()
    if identity == '' or not self:hasTrackIdentity() then
        return false
    end
    self.coverFetchFailed = true
    self.coverFailureIdentity = identity
    self.coverFailureUrl = trim(url)
    self.coverFailureStatus = trim(statusCode)
    return true
end

function externalPlaybackState:coverFailureMatchesCurrent()
    return self.coverFetchFailed
        and trim(self.coverFailureIdentity) ~= ''
        and trim(self.coverFailureIdentity) == self:currentCoverFailureIdentity()
end

function externalPlaybackState:nextVisualSwitchToken()
    self.visualSwitch.counter = (tonumber(self.visualSwitch.counter) or 0) + 1
    if self.visualSwitch.counter > 999999 then
        self.visualSwitch.counter = 1
    end
    return 'external-switch-' .. tostring(self.visualSwitch.counter)
end

function externalPlaybackState:clearVisualSwitch()
    self.visualSwitch.active = false
    self.visualSwitch.token = ''
    self.visualSwitch.playAfterStop = false
    self.visualSwitch.mediaIdentity = ''
end

function externalPlaybackState:startVisualSwitch(playAfterStop)
    self.visualSwitch.active = true
    self.visualSwitch.token = self:nextVisualSwitchToken()
    self.visualSwitch.playAfterStop = playAfterStop and true or false
    self.visualSwitch.mediaIdentity = self.mediaIdentity
    setJukeboxAnimatorPlaybackActive(false)
    startJukeboxAnimation('stop', self.visualSwitch.token)
    return true
end

function externalPlaybackState:playVisual()
    self:clearVisualSwitch()
    setJukeboxAnimatorPlaybackActive(true)
    showCurrentExternalPlaybackHotbarText(false)
    startJukeboxAnimation('play')
    return true
end

function externalPlaybackState:stopVisual()
    self:clearVisualSwitch()
    setJukeboxAnimatorPlaybackActive(false)
    startJukeboxAnimation('stop')
    return true
end

function externalPlaybackState:applyVisualTransition(hadObservation, wasPlaying, isPlaying, mediaChanged)
    if self.visualSwitch.active then
        self.visualSwitch.playAfterStop = self.visualSwitch.playAfterStop or isPlaying
        if mediaChanged then
            self.visualSwitch.mediaIdentity = self.mediaIdentity
        end
        return true
    end

    if not hadObservation then
        setJukeboxAnimatorPlaybackActive(isPlaying)
        return false
    end

    if mediaChanged and wasPlaying and isPlaying then
        return self:startVisualSwitch(true)
    end

    if mediaChanged or wasPlaying ~= isPlaying then
        if isPlaying then
            return self:playVisual()
        elseif wasPlaying then
            return self:stopVisual()
        end
    end

    setJukeboxAnimatorPlaybackActive(isPlaying)
    return false
end

function externalPlaybackState:completeVisualSwitch(token)
    if not self.visualSwitch.active or trim(self.visualSwitch.token) ~= trim(token) then
        return false
    end
    local shouldPlay = self.visualSwitch.playAfterStop and isExternalPlaybackSourceMode() and self.bridgeActive and externalPlaybackConnected() and trim(self.state) == '1'
    self:clearVisualSwitch()
    if shouldPlay then
        return self:playVisual()
    end
    setJukeboxAnimatorPlaybackActive(false)
    return true
end
showCurrentExternalPlaybackHotbarText = function(pinned)
    if not externalPlaybackConnected() or trim(externalPlaybackState.state) == '0' then
        return false
    end
    local trackName = externalPlaybackDisplayName()
    if trackName == '' then
        return false
    end
    return showHotbarText(currentPlaybackHotbarText(trackName), pinned)
end

-- Split from ExtraContent\Jukebox\Jukebox.lua lines 2208-3022.
function fileNameFromPath(path)
    path = trim(path)
    if path == '' then
        return ''
    end
    return path:match('[^\\/]+$') or path
end

function audioFileNameFromValues(values)
    local name = trim(values and values.DMEL_AUDIOFILE or '')
    if name ~= '' then
        return name
    end
    local pending = pendingDiscSlotPlayback
    if pending and trim(pending.path) ~= '' then
        return fileNameFromPath(pending.path)
    end
    return ''
end


function requestEmergencyStop(reason)
    if commandRunning.emergencyStop then
        return false
    end

    local measure = SKIN:GetMeasure('MeasureJukeboxEmergencyStopRun')
    if not measure then
        SKIN:Bang('!Log', 'Jukebox emergency stop could not run: missing emergency stop measure. Reason=' .. tostring(reason or ''), 'Error')
        return false
    end

    syncHelperVariables()
    commandRunning.emergencyStop = true
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxEmergencyStopRun')
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxEmergencyStopRun', 'Run')
    return true
end

function logErrorAndAlert(message)
    forceHideJukeboxAnimator()
    requestEmergencyStop('lua-error')

    local modal = ensureBridge()
    if not modal then
        SKIN:Bang('!Log', tostring(message or 'Jukebox runtime error.'), 'Error')
        return false
    end

    return modal.LogErrorAndAlert(modalAlertHost(), {
        source = 'Jukebox',
        logMessage = tostring(message or 'Jukebox runtime error.'),
        summaryText = localizedSummary('ModalAlert_JukeboxCommandFailed', 'The Jukebox command could not be completed. Refresh the skin and try again.'),
        logPath = modalAlertLogPath(),
        dedupeSeconds = 0,
    })
end

safeCall = function(callback)
    local ok, result = pcall(callback)
    if not ok then
        logErrorAndAlert('Jukebox Lua error: ' .. tostring(result))
        return false
    end
    return result
end

function parsePairs(output)
    return EnsureJukeboxHelperResultModule().parseDmelPairs(output)
end

function outputPreview(output)
    return EnsureJukeboxHelperResultModule().outputPreview(output, 180)
end

function classifyInvalidHelperOutput(kind, output)
    if trim(output) == '' then
        return 'ModalAlert_JukeboxHelperNoOutput', ''
    end

    local preview = outputPreview(output)
    if preview ~= '' then
        local lowerPreview = preview:lower()
        if lowerPreview:find(helperScriptFileName():lower(), 1, true) or lowerPreview:find('jukeboxplayer', 1, true) then
            return 'ModalAlert_JukeboxHelperScriptMissing', helperScriptFileName()
        end
        SKIN:Bang('!Log', 'Jukebox helper returned malformed output for ' .. tostring(kind or 'unknown') .. ': ' .. preview, 'Warning')
    end
    return 'ModalAlert_JukeboxHelperMalformedOutput', ''
end
function measureOutput(measureName)
    local measure = SKIN:GetMeasure(measureName)
    if not measure then
        return ''
    end
    return tostring(measure:GetStringValue() or '')
end

function summaryKeyForCode(code, defaultKey)
    code = upper(code)
    if code == 'AUDIO_MISSING' then
        return 'ModalAlert_JukeboxAudioMissing'
    elseif code == 'HELPER_START_FAILED' then
        return 'ModalAlert_JukeboxHelperStartFailed'
    elseif code == 'OUTPUT_INVALID' then
        return 'ModalAlert_JukeboxHelperMalformedOutput'
    elseif code == 'EVENT_POLL_FAILED' then
        return 'ModalAlert_JukeboxEventPollFailed'
    elseif code == 'PLAYBACK_FAILED' or code == 'MEDIA_FAILED' or code == 'MEDIA_OPEN_FAILED' then
        return 'ModalAlert_JukeboxPlaybackFailed'
    end
    return defaultKey or 'ModalAlert_JukeboxCommandFailed'
end

function fallbackForKey(key)
    if key == 'ModalAlert_JukeboxAudioMissing' then
        return 'The Jukebox audio file is missing: %1'
    elseif key == 'ModalAlert_JukeboxHelperStartFailed' then
        return 'The Jukebox player could not be started. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxHelperScriptMissing' then
        return 'The Jukebox player file could not be found: %1'
    elseif key == 'ModalAlert_JukeboxHelperNoOutput' then
        return 'The Jukebox player did not return a result. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxHelperMalformedOutput' then
        return 'The Jukebox player returned an unreadable result. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxHelperOutputInvalid' then
        return 'The Jukebox player returned an invalid result. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxEventPollFailed' then
        return 'The Jukebox player status could not be checked. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxPlaybackFailed' then
        return 'The Jukebox audio could not be played. Check whether Windows can play the audio file.'
    elseif key == 'ModalAlert_JukeboxExternalPlayerUnavailable' then
        return 'The external player status could not be read. Check the WebNowPlaying plugin and browser extension connection.'
    elseif key == 'ModalAlert_JukeboxExternalNoPlayer' then
        return 'No external music app is connected. Open a supported browser player, start playback, and make sure the WebNowPlaying browser extension is enabled for that tab.'
    elseif key == 'ModalAlert_JukeboxExternalNoMedia' then
        return 'The external music app is visible, but no playable media status is available. Start playback in the browser or app, then try again.'
    elseif key == 'ModalAlert_JukeboxExternalBridgeInactive' then
        return 'The external music app bridge is not ready yet. Wait a moment, then try again. If it keeps failing, reselect external music app mode in Jukebox Settings.'
    elseif key == 'ModalAlert_JukeboxExternalCommandUnsupported' then
        return 'The connected external app does not support %1 through WebNowPlaying. Use the player controls directly or try a different supported player.'
    elseif key == 'ModalAlert_JukeboxExternalCommandNoResponse' then
        return 'The %1 command was sent, but the external app did not report any change. Check whether the WebNowPlaying extension can control the current tab.'
    elseif key == 'ModalAlert_WebNowPlayingPluginUnavailable' then
        return 'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.'
    elseif key == 'ModalAlert_WebNowPlayingInitializationFailed' then
        return 'External music app features did not initialize correctly. Related Jukebox external player features may not work correctly. Local Jukebox playback can still be used.'
    elseif key == 'ModalAlert_WebNowPlayingStatusMeasureMissing' then
        return 'WebNowPlaying did not create the status measure. The Rainmeter plugin may be missing, blocked, or still loading. Re-select external music app mode in Jukebox Settings after checking the plugin.'
    elseif key == 'ModalAlert_WebNowPlayingMeasureReadFailed' then
        return 'WebNowPlaying loaded, but Jukebox could not read one of its status values. Refresh the skin, then check the plugin and browser extension if the problem repeats.'
    elseif key == 'ModalAlert_JukeboxUnsupportedAudio' then
        return '"%1" is not a supported file.\n\n<Supported file types>\n %2'
    elseif key == 'ModalAlert_JukeboxDiscSlotScannerMissing' then
        return 'The Jukebox disc scanner is unavailable. Refresh the skin or reinstall Block HUD.'
    elseif key == 'ModalAlert_JukeboxDiscSlotScannerFailed' then
        return 'The Jukebox disc list could not be refreshed. Check the audio folder and refresh the skin.'
    elseif key == 'ModalAlert_JukeboxDiscSlotSettingsRouteFailed' then
        return 'The Jukebox settings page could not be opened. Refresh the skin and try again.'
    elseif key == 'ModalAlert_JukeboxDiscSlotVolumeDialogFailed' then
        return 'The Jukebox volume input window could not be completed. Refresh the skin and try again.'
    end
    return 'The Jukebox command could not be completed. Refresh the skin and try again.'
end

local function externalCommandRequiresValue(command)
    return command == 'SetVolume'
end

function externalCommandDisplayName(command)
    command = trim(command)
    if command == 'Previous' then
        return localizedSummary('JukeboxExternal_Previous', 'Previous')
    elseif command == 'Play' or command == 'Pause' or command == 'PlayPause' then
        return localizedSummary('JukeboxExternal_PlayPause', 'Play/Pause')
    elseif command == 'Next' then
        return localizedSummary('JukeboxExternal_Next', 'Next')
    elseif command == 'Repeat' then
        return localizedSummary('JukeboxExternal_Repeat', 'Repeat')
    elseif command == 'Shuffle' then
        return localizedSummary('JukeboxExternal_Shuffle', 'Shuffle')
    elseif command == 'SetVolume' then
        return localizedSummary('JukeboxExternal_Volume', 'Volume')
    end
    return command ~= '' and command or localizedSummary('JukeboxExternal_PlayPause', 'Play/Pause')
end

function webNowPlayingInitializationAlertKey(reason)
    reason = trim(reason):lower()
    if reason == 'status_measure_missing' then
        return 'ModalAlert_WebNowPlayingStatusMeasureMissing'
    elseif reason:find('read_failed:', 1, true) == 1 then
        return 'ModalAlert_WebNowPlayingMeasureReadFailed'
    end
    return 'ModalAlert_WebNowPlayingInitializationFailed'
end

function externalUnavailableAlertKey(reason, command)
    reason = trim(reason):lower()
    if reason:find('unsupported:', 1, true) == 1 then
        return 'ModalAlert_JukeboxExternalCommandUnsupported'
    elseif reason == 'no-observable-change' then
        return 'ModalAlert_JukeboxExternalCommandNoResponse'
    elseif reason == 'inactive-bridge' or reason == 'pending-bridge-inactive' then
        return 'ModalAlert_JukeboxExternalBridgeInactive'
    elseif trim(externalPlaybackState.player) ~= '' or externalPlaybackState:hasTrackIdentity() then
        return 'ModalAlert_JukeboxExternalNoMedia'
    end
    return 'ModalAlert_JukeboxExternalNoPlayer'
end

showExternalPlayerUnavailable = function(reason, command)
    reason = trim(reason)
    command = trim(command)
    if reason:lower() == 'no-observable-change' then
        return false
    end
    local key = externalUnavailableAlertKey(reason, command)
    local placeholders = nil
    if key == 'ModalAlert_JukeboxExternalCommandUnsupported'
        or key == 'ModalAlert_JukeboxExternalCommandNoResponse' then
        placeholders = { externalCommandDisplayName(command) }
    end
    return showAlert(
        'warn',
        key,
        fallbackForKey(key),
        modalAlertLogPath(),
        placeholders)
end

local function showWebNowPlayingPluginUnavailable()
    setVariableForActiveConfig('BlockHudDiagnosticsSuppressWebNowPlayingPluginAt', tostring(os.time() or 0), diagnosticsConfigName())
    return showAlert(
        'warn',
        'ModalAlert_WebNowPlayingPluginUnavailable',
        fallbackForKey('ModalAlert_WebNowPlayingPluginUnavailable'),
        modalAlertLogPath())
end

function webNowPlayingInstallState.initializationFailedMessage(key)
    key = trim(key)
    if key == '' then
        key = 'ModalAlert_WebNowPlayingInitializationFailed'
    end
    return localizedSummary(key, fallbackForKey(key))
end

function webNowPlayingInstallState.showInitializationFailed(force)
    if not force and externalPlaybackState.bridgeFailureAlertShown then
        return false
    end
    externalPlaybackState.bridgeFailureAlertShown = true
    local reason = trim(SKIN:GetVariable('JukeboxExternalBridgeFailureReason', ''))
    if reason ~= '' then
        SKIN:Bang('!Log', 'Jukebox WebNowPlaying bridge initialization failed: ' .. reason, 'Warning')
    end
    local key = webNowPlayingInitializationAlertKey(reason)
    return showAlert(
        'error',
        key,
        webNowPlayingInstallState.initializationFailedMessage(key),
        modalAlertLogPath())
end
function dispatchExternalCommand(command, valueText, context)
    local supportFlag, supportValue, supported, bestEffort = externalCommandSupportState(command)
    if not supported then
        logExternalCommandThrottled(
            externalCommandLogKey('unsupported', command, trim(externalPlaybackState.player)),
            'Jukebox WebNowPlaying command blocked because the player reports no support: command=' .. command
                .. ' player=' .. trim(externalPlaybackState.player)
                .. ' support=' .. supportFlag .. '=' .. supportValue,
            'Warning')
        return showExternalPlayerUnavailable('unsupported:' .. supportFlag .. '=' .. supportValue, command)
    end
    if bestEffort then
        logExternalCommandThrottled(
            externalCommandLogKey('best-effort', command, trim(externalPlaybackState.player)),
            'Jukebox WebNowPlaying command is being sent despite a disabled support flag: command=' .. command
                .. ' player=' .. trim(externalPlaybackState.player)
                .. ' support=' .. supportFlag .. '=' .. supportValue,
            'Warning')
    end
    local sent = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', string.format('SendCommand(%q,%q)', command, valueText), webNowPlayingBridgeConfigName())
    if sent then
        logExternalCommand('Jukebox WebNowPlaying command sent: command=' .. command .. ' player=' .. trim(externalPlaybackState.player) .. ' context=' .. tostring(context or 'direct'), 'Notice')
        beginExternalCommandWatch(command, valueText, supportFlag, supportValue, bestEffort, tostring(context or '') == 'reconnect-retry')
        return true
    end
    logExternalCommandThrottled(
        externalCommandLogKey('inactive-bridge', command, trim(externalPlaybackState.player)),
        'Jukebox WebNowPlaying command could not be sent because the bridge config is inactive: command=' .. command,
        'Warning')
    return showExternalPlayerUnavailable('inactive-bridge', command)
end

local function requestExternalCommand(command, value)
    command = trim(command)
    local lowerCommand = command:lower()
    if lowerCommand == 'playpause' then
        command = 'PlayPause'
    elseif lowerCommand == 'play' then
        command = 'Play'
    elseif lowerCommand == 'pause' then
        command = 'Pause'
    elseif lowerCommand == 'next' then
        command = 'Next'
    elseif lowerCommand == 'previous' then
        command = 'Previous'
    elseif lowerCommand == 'repeat' or lowerCommand == 'repeatmode' then
        command = 'Repeat'
    elseif lowerCommand == 'shuffle' then
        command = 'Shuffle'
    elseif lowerCommand == 'setvolume' then
        command = 'SetVolume'
    end
    if command == '' or not isExternalPlaybackSourceMode() then
        return false
    end

    local valueText = ''
    if value ~= nil then
        valueText = trim(value)
    end
    if externalCommandRequiresValue(command) and valueText == '' then
        return false
    end

    if externalPlaybackState.pluginLoadFailed or trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1' then
        return webNowPlayingInstallState.showInitializationFailed(true)
    end

    if not isExternalBridgeActive() then
        externalPlaybackState.pendingCommand = command
        externalPlaybackState.pendingValueText = valueText
        externalPlaybackState.pendingCommandReconnectRetry = false
        logExternalCommandThrottled(
            externalCommandLogKey('queued-activation', command, ''),
            'Jukebox WebNowPlaying command queued while bridge activates: command=' .. command,
            'Notice')
        activateExternalBridge()
        return true
    end
    if not externalPlaybackConnected() then
        logExternalCommandThrottled(
            externalCommandLogKey('unavailable', command, trim(externalPlaybackState.player)),
            'Jukebox WebNowPlaying command blocked because no external player is connected: command=' .. command,
            'Warning')
        return showExternalPlayerUnavailable('command-blocked-unavailable', command)
    end

    return dispatchExternalCommand(command, valueText, 'direct')
end

local function completePendingDiscSlotPlayback()
    local pending = pendingDiscSlotPlayback
    pendingDiscSlotPlayback = nil
    if not pending then
        return
    end

    if pending.action == 'pause' then
        StopJukeboxEventPolling()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
    elseif pending.action == 'switch-pause' then
        StopJukeboxEventPolling()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        local pendingSwitch = discSlotSwitchState.pending
        if pendingSwitch and pendingSwitch.token == trim(pending.switchToken) then
            pendingSwitch.pauseOk = true
            if discSlotSwitchState.tryStartPlay then
                discSlotSwitchState.tryStartPlay()
            end
        end
    else
        persistPlaybackSelection(pending.slotIndex, pending.slotName, pending.path)
        setDiscSlotPlaybackSelection(pending.slotIndex, pending.slotName)
        showCurrentPlaybackHotbarTextForSelection(currentPlaybackSelection())
        if pending.switchToken and discSlotSwitchState.pending and discSlotSwitchState.pending.token == trim(pending.switchToken) then
            discSlotSwitchState.pending = nil
        end
        setJukeboxAnimatorPlaybackActive(true)
        StartJukeboxEventPolling()
    end
end

local function discardPendingDiscSlotPlayback()
    pendingDiscSlotPlayback = nil
    forceHideJukeboxAnimator()
end

local function requestDiscSlotAutoAdvance(shuffleEnabled)
    if not isDiscSlotCommandTargetActive() then
        return false
    end
    local configName = discSlotConfigName()
    syncDiscSlotPlaybackModeControls(configName)
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlot', string.format('PlayNextFromPlaybackSelection(%q,%q)', shuffleEnabled and '1' or '0', '1'), configName)
    return true
end

local function clearEndedDiscSlotPlayback()
    StopJukeboxEventPolling()
    clearPersistedPlaybackSelection()
    clearDiscSlotPlaybackSelection()
    startJukeboxAnimation('stop')
    return true
end

local function handleTrackEndedEvent()
    if currentRepeatMode() == 'all' then
        if requestDiscSlotAutoAdvance(currentShuffleEnabled()) then
            return true
        end
    end
    return clearEndedDiscSlotPlayback()
end

local function handlePlayerEvent(values)
    local code = upper(values and values.DMEL_CODE or '')
    if code == 'TRACK_ENDED' then
        return handleTrackEndedEvent()
    end
    return true
end

local function handleResult(kind, output, defaultKey)
    local values = parsePairs(output)
    local status = upper(values.DMEL_STATUS)
    local logPath = trim(values.DMEL_LOGPATH)
    if logPath == '' then
        logPath = modalAlertLogPath()
    end

    if status == '' then
        local key, placeholder = classifyInvalidHelperOutput(kind, output)
        pollSuspendedAfterError = true
        StopJukeboxEventPolling()
        discardPendingDiscSlotPlayback()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        requestEmergencyStop('missing-helper-status')
        forceHideJukeboxAnimator()
        showAlert('error', key, fallbackForKey(key), logPath, placeholder)
        return false
    end

    if status == 'OK' then
        if kind == 'playback' then
            completePendingDiscSlotPlayback()
        elseif kind == 'stop' then
            StopJukeboxEventPolling()
            setJukeboxAnimatorPlaybackActive(false)
            clearPersistedPlaybackSelection()
            clearDiscSlotPlaybackSelection()
        elseif kind == 'poll' and trim(values.DMEL_EVENT) == '1' then
            handlePlayerEvent(values)
        end
        return true
    end

    if upper(values.DMEL_CODE) == 'HELPER_BUSY' then
        if kind == 'poll' then
            return true
        end
        if kind == 'stop' and isExternalPlaybackSourceMode() then
            requestEmergencyStop('external-stop-helper-busy')
            setJukeboxAnimatorPlaybackActive(false)
            clearPersistedPlaybackSelection()
            clearDiscSlotPlaybackSelection()
        end
        return false
    end

    local key = summaryKeyForCode(values.DMEL_CODE, defaultKey)
    local level = status == 'WARN' and 'warn' or 'error'
    if kind == 'playback' then
        discardPendingDiscSlotPlayback()
    end
    local placeholder = ''
    if key == 'ModalAlert_JukeboxAudioMissing' then
        placeholder = audioFileNameFromValues(values)
    end
    if level == 'error' and (kind ~= 'stop' or isExternalPlaybackSourceMode()) then
        pollSuspendedAfterError = true
        StopJukeboxEventPolling()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        requestEmergencyStop('helper-error-' .. trim(values.DMEL_CODE))
        forceHideJukeboxAnimator()
    end
    showAlert(level, key, fallbackForKey(key), logPath, placeholder)
    return false
end

runMeasure = function(kind, measureName, missingKey)
    syncHelperVariables()

    if commandRunning[kind] then
        return false
    end

    if not SKIN:GetMeasure(measureName) then
        showAlert('error', missingKey, fallbackForKey(missingKey), modalAlertLogPath())
        return false
    end

    commandRunning[kind] = true
    SKIN:Bang('!UpdateMeasure', measureName)
    SKIN:Bang('!CommandMeasure', measureName, 'Run')
    return true
end
function webNowPlayingInstallState.reset()
    webNowPlayingInstallState.phase = ''
    webNowPlayingInstallState.requestedMode = ''
    webNowPlayingInstallState.previousMode = ''
    webNowPlayingInstallState.openCommand = ''
    webNowPlayingInstallState.ownerPid = ''
    webNowPlayingInstallState.ownerUser = ''
    webNowPlayingInstallState.ownerDomain = ''
    webNowPlayingInstallState.ownerLabel = ''
end

function webNowPlayingInstallState.fallbackToLocal()
    webNowPlayingInstallState.openCommand = ''
    local ok = setPlaybackSourceModeInternal(PLAYBACK_SOURCE_LOCAL)
    webNowPlayingInstallState.reset()
    return ok
end

function webNowPlayingInstallState.applyExternalModeAfterReady()
    externalPlaybackState.pluginLoadFailed = false
    externalPlaybackState.bridgeFailureAlertShown = false
    setExternalPlaybackVariable('JukeboxExternalBridgePluginFailed', '0')
    webNowPlayingInstallState.phase = ''
    webNowPlayingInstallState.bypassPreflight = true
    local ok = setPlaybackSourceModeInternal(PLAYBACK_SOURCE_EXTERNAL)
    webNowPlayingInstallState.bypassPreflight = false
    webNowPlayingInstallState.reset()
    return ok
end

function webNowPlayingInstallState.start(action, previousMode)
    if commandRunning.webNowPlayingInstall then
        return true
    end

    if not SKIN:GetMeasure('MeasureJukeboxWebNowPlayingInstallRun') then
        webNowPlayingInstallState.fallbackToLocal()
        webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingInstallFailed',
            'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.\n\nThe plugin could not be installed. Check your internet connection and try again.',
            '외부 뮤직 앱 연동을 위한 플러그인을 불러오지 못했습니다. 주크박스 설정에서 재생 소스의 \'외부 뮤직 앱\'을 클릭해 다시 시도해보세요.\n\n플러그인을 설치하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.')
        return false
    end

    local normalizedAction = trim(action)
    if normalizedAction == '' then
        normalizedAction = 'Check'
    end

    webNowPlayingInstallState.phase = normalizedAction:lower()
    webNowPlayingInstallState.requestedMode = PLAYBACK_SOURCE_EXTERNAL
    webNowPlayingInstallState.previousMode = normalizedPlaybackSourceMode(previousMode)
    webNowPlayingInstallState.openCommand = ''
    setVariable('JukeboxWebNowPlayingInstallerArgs', webNowPlayingInstallState.buildArgs(normalizedAction))
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxWebNowPlayingInstallRun')
    commandRunning.webNowPlayingInstall = true
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxWebNowPlayingInstallRun', 'Run')
    return true
end

function webNowPlayingInstallState.handleComplete()
    commandRunning.webNowPlayingInstall = false
    local output = measureOutput('MeasureJukeboxWebNowPlayingInstallRun')
    webNowPlayingInstallState.openCommand = ''
    local values = parsePairs(output)
    local status = upper(values.DMEL_STATUS)
    local code = upper(values.DMEL_CODE)
    local phase = trim(webNowPlayingInstallState.phase)

    if status == '' then
        local preview = outputPreview(output)
        if preview ~= '' then
            SKIN:Bang('!Log', 'Jukebox WebNowPlaying installer returned no DMEL_STATUS: ' .. preview, 'Warning')
        end
        webNowPlayingInstallState.fallbackToLocal()
        return webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingInstallFailed',
            'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.\n\nThe plugin could not be installed. Check your internet connection and try again.',
            '외부 뮤직 앱 연동을 위한 플러그인을 불러오지 못했습니다. 주크박스 설정에서 재생 소스의 \'외부 뮤직 앱\'을 클릭해 다시 시도해보세요.\n\n플러그인을 설치하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.')
    end

    if phase == 'check' then
        if status == 'NOOP' and code == 'PORT_IN_USE_OTHER_USER' then
            webNowPlayingInstallState.fallbackToLocal()
            webNowPlayingInstallState.setPortOwner(values)
            webNowPlayingInstallState.previousMode = PLAYBACK_SOURCE_LOCAL
            return webNowPlayingInstallState.openPortOwnerTerminateConfirm()
        end
        if status == 'NOOP' and code == 'PORT_IN_USE' then
            webNowPlayingInstallState.fallbackToLocal()
            return webNowPlayingInstallState.showInstallAlert(
                'error',
                'ModalAlert_WebNowPlayingPortInUse',
                'More than one Rainmeter process is currently running.\nThe external music app feature may not work correctly.\nPlease restart your computer and try again.',
                '현재 레인미터 프로세스가 두 개 이상 켜져 있습니다.\n외부 뮤직 앱 기능이 정상 작동하지 않을 수 있으니,\n컴퓨터를 재부팅 후 다시 이용해 주세요.')
        end
        if (status == 'OK' and code == 'INSTALLED') or (status == 'NOOP' and code == 'ALREADY_INSTALLED') then
            return webNowPlayingInstallState.applyExternalModeAfterReady()
        end
        if status == 'NOOP' and (code == 'MISSING' or code == 'INCOMPATIBLE_ARCH') then
            return webNowPlayingInstallState.openInstallConfirm()
        end
        local detail = 'status=' .. status .. '; code=' .. code
        local message = outputPreview(values.DMEL_MESSAGE or '')
        if message ~= '' then
            detail = detail .. '; message=' .. message
        end
        SKIN:Bang('!Log', 'Jukebox WebNowPlaying check returned unexpected result: ' .. detail, 'Warning')
        webNowPlayingInstallState.fallbackToLocal()
        return webNowPlayingInstallState.showInstallAlert(
            'warn',
            'ModalAlert_WebNowPlayingInstallUnavailable',
            'WebNowPlaying installation could not be checked. Install the WebNowPlaying Rainmeter plugin manually, then try external player mode again.',
            'WebNowPlaying 설치 상태를 확인하지 못했습니다. WebNowPlaying Rainmeter 플러그인을 수동으로 설치한 뒤 외부 플레이어 모드를 다시 시도하세요.')
    end

    if phase == 'install' then
        if (status == 'OK' and code == 'INSTALLED') or (status == 'NOOP' and code == 'ALREADY_INSTALLED') then
            webNowPlayingInstallState.showInstallAlert(
                'warn',
                'ModalAlert_WebNowPlayingInstallSucceeded',
                'Plugin installation is complete. Refresh the skin if it does not connect to the external music app immediately.',
                '플러그인 설치가 완료됐습니다. 외부 뮤직 앱에 바로 연결되지 않으면 스킨을 새로고침하세요.')
            return webNowPlayingInstallState.applyExternalModeAfterReady()
        end
        webNowPlayingInstallState.fallbackToLocal()
        return webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingInstallFailed',
            'The plugin for external music app integration could not be loaded. In Jukebox Settings, click playback source \'External music app\' to try again.\n\nThe plugin could not be installed. Check your internet connection and try again.',
            '외부 뮤직 앱 연동을 위한 플러그인을 불러오지 못했습니다. 주크박스 설정에서 재생 소스의 \'외부 뮤직 앱\'을 클릭해 다시 시도해보세요.\n\n플러그인을 설치하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.')
    end

    if phase == 'terminateportowner' then
        if status == 'OK' and code == 'TERMINATED' then
            webNowPlayingInstallState.showInstallAlert(
                'warn',
                'ModalAlert_WebNowPlayingTerminateSucceeded',
                'The other account Rainmeter process was terminated. Jukebox will check WebNowPlaying again.',
                'The other account Rainmeter process was terminated. Jukebox will check WebNowPlaying again.')
            return webNowPlayingInstallState.start('Check', PLAYBACK_SOURCE_LOCAL)
        end

        webNowPlayingInstallState.fallbackToLocal()
        if code == 'ACCESS_DENIED' then
            return webNowPlayingInstallState.showInstallAlert(
                'error',
                'ModalAlert_WebNowPlayingTerminateAccessDenied',
                'The other account Rainmeter process could not be terminated because access was denied. Log into that Windows account and close Rainmeter manually.',
                'The other account Rainmeter process could not be terminated because access was denied. Log into that Windows account and close Rainmeter manually.')
        end
        if code == 'OWNER_CHANGED' or code == 'ALREADY_STOPPED' or code == 'OWNER_IS_CURRENT' then
            return webNowPlayingInstallState.showInstallAlert(
                'warn',
                'ModalAlert_WebNowPlayingTerminateOwnerChanged',
                'The WebNowPlaying port owner changed before termination. Try external player mode again after checking Rainmeter in the other Windows account.',
                'The WebNowPlaying port owner changed before termination. Try external player mode again after checking Rainmeter in the other Windows account.')
        end
        return webNowPlayingInstallState.showInstallAlert(
            'error',
            'ModalAlert_WebNowPlayingTerminateFailed',
            'The other account Rainmeter process could not be terminated. Log into that Windows account and close Rainmeter manually.',
            'The other account Rainmeter process could not be terminated. Log into that Windows account and close Rainmeter manually.')
    end

    webNowPlayingInstallState.fallbackToLocal()
    return false
end
local function runPlaybackCommand(command, audioOverride, missingKey, pendingPlayback)
    syncHelperVariables()

    if commandRunning.playback then
        return false
    end

    local loopEnabled = command == 'Play' and isPlaybackLoopEnabled()
    local volume = currentPlaybackVolume()
    pendingDiscSlotPlayback = pendingPlayback

    if not SKIN:GetMeasure('MeasureJukeboxPlaybackRun') then
        pendingDiscSlotPlayback = nil
        showAlert('error', missingKey, fallbackForKey(missingKey), modalAlertLogPath())
        return false
    end

    setVariable('JukeboxPlaybackArgs', buildArgs(command, audioOverride or '', '', loopEnabled, volume))
    SKIN:Bang('!UpdateMeasure', 'MeasureJukeboxPlaybackRun')
    commandRunning.playback = true
    SKIN:Bang('!CommandMeasure', 'MeasureJukeboxPlaybackRun', 'Run')
    return true
end

local function stopLocalPlayback()
    pendingDiscSlotPlayback = nil
    discSlotSwitchState.pending = nil
    forceHideJukeboxAnimator()
    if commandRunning.stop then
        return true
    end
    if runMeasure and runMeasure('stop', 'MeasureJukeboxStopRun', 'ModalAlert_JukeboxCommandFailed') then
        return true
    end
    setJukeboxAnimatorPlaybackActive(false)
    clearPersistedPlaybackSelection()
    clearDiscSlotPlaybackSelection()
    return true
end

function setPlaybackSourceModeInternal(mode)
    local nextMode = normalizedPlaybackSourceMode(mode)
    local previousMode = currentPlaybackSourceMode()
    if nextMode == PLAYBACK_SOURCE_EXTERNAL and not webNowPlayingInstallState.bypassPreflight then
        return webNowPlayingInstallState.start('Check', previousMode)
    end
    if previousMode == nextMode and trim(SKIN:GetVariable('JukeboxPlaybackSourceMode', '')) == nextMode then
        setVariableForActiveConfig('JukeboxPlaybackSourceMode', nextMode, diagnosticsConfigName())
        syncExternalBridgeForMode()
        syncSettingsPlaybackSourceMode()
        syncDiscSlotPlaybackModeControls()
        PreloadDiscSlotSkin()
        return true
    end

    if nextMode == PLAYBACK_SOURCE_EXTERNAL then
        if commandRunning.playback then
            commandRunning.stopPendingAfterExternalSwitch = true
        end
        stopLocalPlayback()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        setJukeboxAnimatorPlaybackActive(false)
    else
        deactivateExternalBridge()
        resetExternalPlaybackState()
        externalPlaybackState.pluginLoadFailed = false
        externalPlaybackState.bridgeFailureAlertShown = false
        setExternalPlaybackVariable('JukeboxExternalBridgePluginFailed', '0')
        setJukeboxAnimatorPlaybackActive(false)
    end

    deactivateDiscSlotSkin()
    setVariable('JukeboxPlaybackSourceMode', nextMode)
    setVariableForActiveConfig('JukeboxPlaybackSourceMode', nextMode, diagnosticsConfigName())
    writeGeneralSettingValue('JukeboxPlaybackSourceMode', nextMode)
    syncExternalBridgeForMode()
    syncSettingsPlaybackSourceMode()
    syncDiscSlotPlaybackModeControls()
    PreloadDiscSlotSkin()
    return true
end

discSlotSwitchState.nextToken = function()
    discSlotSwitchState.token = discSlotSwitchState.token + 1
    if discSlotSwitchState.token > 1000000 then
        discSlotSwitchState.token = 1
    end
    return tostring(discSlotSwitchState.token)
end

discSlotSwitchState.tryStartPlay = function()
    local pendingSwitch = discSlotSwitchState.pending
    if not pendingSwitch or pendingSwitch.playStarted then
        return false
    end
    if not pendingSwitch.pauseOk or not pendingSwitch.stopAnimationDone then
        return false
    end

    pendingSwitch.playStarted = true
    local accepted = runPlaybackCommand('Play', pendingSwitch.targetPath, 'ModalAlert_JukeboxHelperStartFailed', {
        slotIndex = pendingSwitch.targetSlotIndex,
        slotName = pendingSwitch.targetSlotName,
        path = pendingSwitch.targetPath,
        action = 'play',
        switchToken = pendingSwitch.token,
    })
    if accepted then
        startJukeboxAnimation('play')
        return true
    end

    discSlotSwitchState.pending = nil
    forceHideJukeboxAnimator()
    return false
end

local function beginDiscSlotSwitchPlayback(slotIndex, slotName, path)
    local token = discSlotSwitchState.nextToken()
    discSlotSwitchState.pending = {
        token = token,
        targetSlotIndex = tonumber(slotIndex) or 0,
        targetSlotName = trim(slotName),
        targetPath = trim(path),
        pauseOk = false,
        stopAnimationDone = false,
        playStarted = false,
    }

    local accepted = runPlaybackCommand('Pause', '', 'ModalAlert_JukeboxHelperStartFailed', {
        slotIndex = tonumber(slotIndex) or 0,
        slotName = trim(slotName),
        path = trim(path),
        action = 'switch-pause',
        switchToken = token,
    })
    if accepted then
        setJukeboxAnimatorPlaybackActive(false)
        startJukeboxAnimation('stop', token)
    else
        discSlotSwitchState.pending = nil
    end
    return accepted
end

local function beginEndedDiscSlotSwitchPlayback(slotIndex, slotName, path)
    local token = discSlotSwitchState.nextToken()
    discSlotSwitchState.pending = {
        token = token,
        targetSlotIndex = tonumber(slotIndex) or 0,
        targetSlotName = trim(slotName),
        targetPath = trim(path),
        pauseOk = true,
        stopAnimationDone = false,
        playStarted = false,
    }

    pendingDiscSlotPlayback = nil
    clearPersistedPlaybackSelection()
    clearDiscSlotPlaybackSelection()
    startJukeboxAnimation('stop', token)
    return true
end

-- Split from ExtraContent\Jukebox\Jukebox.lua lines 3023-4111.
function Initialize(allowCrossConfig)
    local allowExternal = allowCrossConfigValue(allowCrossConfig)
    initialized = true
    discSlotVisible = false
    pendingDiscSlotPlayback = nil
    discSlotSwitchState.pending = nil
    discSlotSwitchState.token = 0
    discSlotLoaded = false
    animationEngine = nil
    jukeboxAnimator = nil
    jukeboxAnimatorPhase = 'hidden'
    jukeboxAnimatorKind = ''
    jukeboxAnimatorPlaybackActive = false
    jukeboxAnimatorElapsedMs = 0
    jukeboxAnimatorWaitMs = 0
    jukeboxAnimatorCurrentFrameCount = 0
    jukeboxAnimatorCurrentFrameMs = ANIMATOR_FRAME_MS
    jukeboxAnimatorLastPlayingIndex = 0
    jukeboxAnimatorRandomSeeded = false
    jukeboxAnimatorTransitionCallbackToken = ''
    minimizedAnimator = nil
    minimizedAnimatorPhase = 'hidden'
    minimizedAnimatorKind = ''
    minimizedAnimatorPlaybackActive = false
    minimizedAnimatorElapsedMs = 0
    minimizedAnimatorWaitMs = 0
    minimizedAnimatorCurrentFrameCount = 0
    minimizedAnimatorCurrentFrameMs = ANIMATOR_FRAME_MS
    minimizedAnimatorLastPlayingIndex = 0
    minimizedAnimatorRandomSeeded = false
    minimizedDragging = false
    minimizedDragAllowedAtDown = false
    minimizedDragMoved = false
    minimizedLastWindowY = nil
    JukeboxScheduler.eventPolling = false
    JukeboxScheduler.eventPollRuntimeTicks = 0
    JukeboxScheduler.minimizedIdle = false
    JukeboxScheduler.responsive = false
    syncJukeboxModeImages()
    syncMinimizedModeImages()
    setJukeboxMinimizedMouseEnabled(JukeboxIsMinimizedForm())
    setJukeboxAnimatorHidden(true)
    setJukeboxMinimizedAnimatorHidden(true)
    setJukeboxDraggable(true)
    local configuredSourceMode = trim(SKIN:GetVariable('JukeboxPlaybackSourceMode', ''))
    local sourceMode = normalizedPlaybackSourceMode(configuredSourceMode)
    setVariable('JukeboxPlaybackSourceMode', sourceMode)
    if allowExternal then
        setVariableForActiveConfig('JukeboxPlaybackSourceMode', sourceMode, diagnosticsConfigName())
    end
    if configuredSourceMode == '' or configuredSourceMode:lower() ~= sourceMode then
        writeGeneralSettingValue('JukeboxPlaybackSourceMode', sourceMode)
    end
    syncPlaybackModeState(true, true)
    syncHelperVariables()

    if sourceMode == PLAYBACK_SOURCE_EXTERNAL then
        quarantineExternalBridgeForStartup(not allowExternal)
        if commandRunning.playback then
            commandRunning.stopPendingAfterExternalSwitch = true
        end
        stopLocalPlayback()
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        if allowExternal then
            deactivateDiscSlotSkin()
        end
        setJukeboxAnimatorPlaybackActive(false, allowCrossConfig)
        webNowPlayingInstallState.start('Check', PLAYBACK_SOURCE_LOCAL)
    elseif allowExternal then
        syncExternalBridgeForMode()
    end
    if allowExternal and isDiscSlotCommandTargetActive() then
        scheduleDiscSlotDeferredSync()
    end
end

function PreloadJukeboxAnimator(allowCrossConfig)
    return safeCall(function()
        syncJukeboxModeImages()
        syncMinimizedModeImages()
        hideJukeboxAnimatorVisual(allowCrossConfig)
        HideJukeboxMinimizedAnimation()
        return true
    end)
end

function RestorePlaybackAnimation(allowCrossConfig)
    return safeCall(function()
        local allowExternal = allowCrossConfigValue(allowCrossConfig)
        if not initialized then
            Initialize(allowCrossConfig)
        end
        if isExternalPlaybackSourceMode() then
            if allowExternal then
                syncExternalBridgeForMode()
            end
            if externalPlaybackState.bridgeActive and externalPlaybackConnected() and trim(externalPlaybackState.state) == '1' then
                setJukeboxAnimatorPlaybackActive(true, allowCrossConfig)
                return true
            end
            hideJukeboxAnimatorVisual(allowCrossConfig)
            return false
        end

        local selection = currentPlaybackSelection()
        if selection.active and trim(selection.path) ~= '' then
            setJukeboxAnimatorPlaybackActive(true, allowCrossConfig)
            StartJukeboxEventPolling()
            return true
        end
        hideJukeboxAnimatorVisual(allowCrossConfig)
        return false
    end)
end
function StartJukeboxResponsiveLayoutTimer()
    JukeboxScheduler.responsive = true
    syncJukeboxRuntimeDriver()
    SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    return 0
end

function StopJukeboxResponsiveLayoutTimer()
    JukeboxScheduler.responsive = false
    syncJukeboxRuntimeDriver()
    return 0
end

function ContinueJukeboxResponsiveLayoutTimer()
    return StartJukeboxResponsiveLayoutTimer()
end
function persistCurrentJukeboxFixedPosition()
    local rect = JukeboxClampRectToWorkArea(currentJukeboxLiveRect())
    writeJukeboxMainFormY(rect.y)
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', string.format('SetFixedPosition(%q,%d,%d)', 'Jukebox', rect.x, rect.y))
    return rect
end

function hideDiscSlotForJukeboxFormSwitch()
    discSlotPendingShow = false
    discSlotPendingShowSkipRefresh = false
    discSlotActivationRequested = false
    if discSlotVisible then
        HideDiscSlot()
    else
        local configName = discSlotConfigName()
        if isRainmeterConfigActive(configName) then
            local surface = JukeboxDiscSlotLifecycleSurface()
            resetDiscSlotRenderStateForClose(configName)
            setDiscSlotHidden(true)
            syncDiscSlotVisualState(configName)
            surface:CommandIfActive('MeasureJukeboxDiscSlot', 'SuspendDiscSlotResident()')
            surface:HideIfActive()
        end
        discSlotVisible = false
    end
    return true
end

function enterJukeboxMinimizedForm(x)
    local targetX = persistSharedJukeboxX(x or currentWindowX())
    writeJukeboxDisplayMode('minimized')
    hideDiscSlotForJukeboxFormSwitch()
    setJukeboxDraggable(true)
    setJukeboxMinimizedMouseEnabled(true)
    syncMinimizedModeImages()
    setJukeboxAnimatorHidden(true)
    moveJukeboxToMinimizedBottom(targetX)
    setMinimizedPlaybackActiveVariable(jukeboxAnimatorPlaybackActive)
    restoreMinimizedPlaybackVisual()
    StartJukeboxMinimizedIdleTimer()
    redraw()
    return true
end

function enterJukeboxMainForm(x)
    local restoreY = storedJukeboxMainY(SKIN:GetVariable('ResponsiveLayout_Jukebox_FixedY', '0'), JukeboxIsMinimizedForm())
    local targetX = persistSharedJukeboxX(x or currentWindowX(), restoreY)
    local rect = JukeboxClampRectToWorkArea({ x = targetX, y = restoreY, width = tonumber(SKIN:GetVariable('JukeboxW', '80')) or 80, height = tonumber(SKIN:GetVariable('JukeboxH', '101')) or 101 })
    writeJukeboxDisplayMode('main')
    StopJukeboxMinimizedIdleTimer()
    HideJukeboxMinimizedAnimation()
    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', string.format('SetFixedPosition(%q,%d,%d)', 'Jukebox', rect.x, rect.y))
    SKIN:Bang('!Move', tostring(rect.x), tostring(rect.y))
    setJukeboxDraggable(true)
    setJukeboxMinimizedMouseEnabled(false)
    setJukeboxMinimizedAnimatorHidden(true)
    RestorePlaybackAnimation()
    redraw()
    return true
end

function RestoreJukeboxFormOnRefresh()
    return safeCall(function()
        if JukeboxIsMinimizedForm() then
            return enterJukeboxMinimizedForm(currentWindowX())
        end
        return enterJukeboxMainForm(currentWindowX())
    end)
end

function HandleJukeboxClose()
    return safeCall(function()
        if JukeboxIsMinimizedForm() then
            persistSharedJukeboxX(currentWindowX())
        else
            persistCurrentJukeboxFixedPosition()
        end
        StopPlayback()
        requestEmergencyStop('close')
        StopJukeboxMinimizedIdleTimer()
        StopJukeboxResponsiveLayoutTimer()
        StopJukeboxEventPolling()
        ensureResidentUpdateController().SuspendSurface('Jukebox')
        SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'DeactivateLiveState()')
        return true
    end)
end

function MinimizeJukebox()
    return safeCall(function()
        if not isJukeboxFeatureEnabled() then
            return false
        end
        if not initialized then
            Initialize()
        end
        local rect = persistCurrentJukeboxFixedPosition()
        return enterJukeboxMinimizedForm(rect.x)
    end)
end

function RestoreJukeboxFromMinimized(x)
    return safeCall(function()
        return enterJukeboxMainForm(x)
    end)
end

function CleanupJukeboxMinimized()
    return safeCall(function()
        StopJukeboxMinimizedIdleTimer()
        HideJukeboxMinimizedAnimation()
        return true
    end)
end

function StopPlaybackForFeatureDisable()
    return safeCall(function()
        hideDiscSlotForJukeboxFormSwitch()
        StopPlayback()
        requestEmergencyStop('feature-disable')
        return true
    end)
end

function HandleJukeboxRealUnload(allowCrossConfig)
    return safeCall(function()
        ensureResidentUpdateController().SuspendSurface('Jukebox')
        StopJukeboxResponsiveLayoutTimer()
        StopJukeboxEventPolling()
        pendingDiscSlotPlayback = nil
        discSlotSwitchState.pending = nil
        clearPersistedPlaybackSelection()
        clearDiscSlotPlaybackSelection()
        forceHideJukeboxAnimator(allowCrossConfig)
        requestEmergencyStop('real-unload')
        return true
    end)
end
function PreloadModalAlert()
    return safeCall(function()
        syncHelperVariables()
        local modal = ensureBridge()
        if modal then
            modal.Preload(modalAlertHost())
        end
        return true
    end)
end

function OpenPendingModalAlert()
    return safeCall(function()
        local modal = ensureBridge()
        if modal then
            return modal.OpenPending(modalAlertHost())
        end
        return false
    end)
end

function OpenPendingWebNowPlayingInstallConfirm()
    return safeCall(function()
        local configName = webNowPlayingInstallState.modalConfigName()
        if configName == '' or trim(webNowPlayingInstallState.openCommand) == '' then
            return false
        end
        SKIN:Bang('!CommandMeasure', 'MeasureModal', webNowPlayingInstallState.openCommand, configName)
        return true
    end)
end

function ConfirmWebNowPlayingInstall(token)
    return safeCall(function()
        if trim(token) == '' or trim(webNowPlayingInstallState.openCommand) == '' then
            return false
        end
        webNowPlayingInstallState.openCommand = ''
        local started = webNowPlayingInstallState.start('Install', webNowPlayingInstallState.previousMode)
        if started then
            webNowPlayingInstallState.openInstallProgress()
        end
        return started
    end)
end

function CancelWebNowPlayingInstall(token)
    return safeCall(function()
        return webNowPlayingInstallState.fallbackToLocal()
    end)
end

function ConfirmWebNowPlayingPortOwnerTerminate(token)
    return safeCall(function()
        if trim(token) == '' or trim(webNowPlayingInstallState.ownerPid) == '' then
            return false
        end
        webNowPlayingInstallState.openCommand = ''
        return webNowPlayingInstallState.openPortOwnerForceConfirm()
    end)
end

function ForceTerminateWebNowPlayingPortOwner(token)
    return safeCall(function()
        if trim(token) == '' or trim(webNowPlayingInstallState.ownerPid) == '' then
            return false
        end
        webNowPlayingInstallState.openCommand = ''
        return webNowPlayingInstallState.start('TerminatePortOwner', webNowPlayingInstallState.previousMode)
    end)
end

function CancelWebNowPlayingPortOwnerTerminate(token)
    return safeCall(function()
        return webNowPlayingInstallState.fallbackToLocal()
    end)
end

function HandleWebNowPlayingInstallComplete()
    return safeCall(function()
        return webNowPlayingInstallState.handleComplete()
    end)
end

function OpenModalAlertLogFolder(token)
    return safeCall(function()
        local modal = ensureBridge()
        if modal then
            return modal.OpenLogFolder(modalAlertHost(), token)
        end
        return false
    end)
end

function SeedDiscSlotLayoutContext()
    return safeCall(function()
        captureJukeboxLiveState()
        syncJukeboxLiveStateToDiscSlot(discSlotConfigName())
        return true
    end)
end

function ShowDiscSlot()
    return safeCall(function()
        captureJukeboxLiveState()
        resetDiscSlotAnchorState()
        local configName, activatedNow = activateDiscSlot()
        if activatedNow then
            discSlotPendingShow = true
            discSlotPendingShowSkipRefresh = false
            discSlotVisible = true
            setJukeboxDraggable(false)
            scheduleDiscSlotDeferredSync()
            return true
        end
        return showDiscSlotNow(configName)
    end)
end

function HideDiscSlot()
    return safeCall(function()
        discSlotPendingShow = false
        discSlotPendingShowSkipRefresh = false
        local configName = discSlotConfigName()
        if isRainmeterConfigActive(configName) then
            local surface = JukeboxDiscSlotLifecycleSurface()
            resetDiscSlotRenderStateForClose(configName)
            setDiscSlotHidden(true)
            syncDiscSlotVisualState(configName)
            surface:HideIfActive()
        end
        setJukeboxDraggable(true)
        discSlotVisible = false
        return true
    end)
end

function ToggleDiscSlot()
    return safeCall(function()
        local result = false
        if discSlotVisible and not discSlotPendingShow then
            result = HideDiscSlot()
        else
            result = ShowDiscSlot()
        end
        return playClickSoundForResult(result)
    end)
end

function TryCompleteDiscSlotDeferredSync()
    return safeCall(function()
        if not discSlotPendingShow then
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
            return false
        end
        local configName = discSlotConfigName()
        if isRainmeterConfigActive(configName) then
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
            return showDiscSlotNow(configName, discSlotPendingShowSkipRefresh)
        end
        discSlotDeferredAttempts = discSlotDeferredAttempts + 1
        if discSlotActivationRequested and not discSlotRefreshRecoveryRequested and discSlotDeferredAttempts >= 3 then
            discSlotRefreshRecoveryRequested = true
            SKIN:Bang('!Refresh', configName)
            return true
        end
        if discSlotDeferredAttempts >= DISC_SLOT_DEFERRED_MAX_ATTEMPTS then
            SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
            discSlotPendingShow = false
            discSlotPendingShowSkipRefresh = false
            discSlotActivationRequested = false
            discSlotRefreshRecoveryRequested = false
            discSlotLoaded = false
            discSlotVisible = false
            setJukeboxDraggable(true)
            return false
        end
        return true
    end)
end

function SetPlaybackSourceMode(mode)
    return safeCall(function()
        return setPlaybackSourceModeInternal(mode)
    end)
end

function ExternalPlayPause()
    return safeCall(function()
        local command = trim(externalPlaybackState.state) == '1' and 'Pause' or 'Play'
        return requestExternalCommand(command)
    end)
end

function ExternalNext()
    return safeCall(function()
        return requestExternalCommand('Next')
    end)
end

function ExternalPrevious()
    return safeCall(function()
        return requestExternalCommand('Previous')
    end)
end

function ExternalRepeat()
    return safeCall(function()
        return requestExternalCommand('Repeat')
    end)
end

function ExternalShuffle()
    return safeCall(function()
        return requestExternalCommand('Shuffle')
    end)
end

function SetPlaybackVolume(value)
    return safeCall(function()
        local volume = clampPlaybackVolume(value)
        if isExternalPlaybackSourceMode() then
            return requestExternalCommand('SetVolume', tostring(volume))
        end
        setLocalPlaybackVolume(volume, true)
        requestHelperVolumeSync(volume)
        syncDiscSlotPlaybackModeControls()
        return true
    end)
end

function TogglePlaybackRepeatMode()
    return safeCall(function()
        if isExternalPlaybackSourceMode() then
            return requestExternalCommand('Repeat')
        end
        local mode = currentRepeatMode()
        if mode == 'all' then
            mode = 'one'
        elseif mode == 'one' then
            mode = 'off'
        else
            mode = 'all'
        end
        setVariable('JukeboxPlaybackRepeatMode', mode)
        syncPlaybackModeState(true)
        requestHelperLoopModeSync()
        return true
    end)
end

function TogglePlaybackShuffle()
    return safeCall(function()
        if isExternalPlaybackSourceMode() then
            return requestExternalCommand('Shuffle')
        end
        setVariable('JukeboxPlaybackShuffle', currentShuffleEnabled() and '0' or '1')
        syncPlaybackModeState(true)
        return true
    end)
end

function CleanupDiscSlot()
    return safeCall(function()
        return deactivateDiscSlotSkin()
    end)
end

function HandleDiscSlotManualDeactivate()
    return safeCall(function()
        local configName = discSlotConfigName()
        discSlotPendingShow = false
        discSlotPendingShowSkipRefresh = false
        discSlotActivationRequested = false
        discSlotRefreshRecoveryRequested = false
        discSlotDeferredAttempts = 0
        discSlotLoaded = false
        discSlotVisible = false
        setJukeboxDraggable(true)
        jukeboxConfigState().Unregister(SKIN, configName)
        ensureResidentUpdateController().SetDriver('JukeboxDiscSlot', 'runtime', false, true)
        SKIN:Bang('!CommandMeasure', 'MeasureJukeboxDiscSlotDeferredSyncTimer', 'Stop 1')
        return true
    end)
end

function CleanupJukeboxAnimator()
    return safeCall(function()
        forceHideJukeboxAnimator()
        return true
    end)
end

function ContinueJukeboxAnimationAfterDelay()
    return safeCall(function()
        if isJukeboxNoteAnimationDisabled() then
            hideJukeboxAnimatorVisual()
            return false
        end
        if jukeboxAnimatorPhase ~= 'waiting' then
            return false
        end
        if not jukeboxAnimatorPlaybackActive then
            hideJukeboxAnimatorVisual()
            return false
        end
        startJukeboxPlayingSheet()
        return true
    end)
end

function UpdateJukeboxAnimation()
    return safeCall(function()
        if isJukeboxNoteAnimationDisabled() then
            if jukeboxAnimatorPhase ~= 'hidden' then
                local finishedKind = jukeboxAnimatorKind
                local callbackToken = jukeboxAnimatorTransitionCallbackToken
                hideJukeboxAnimatorVisual()
                notifyJukeboxAnimationComplete(finishedKind, callbackToken)
            end
            return false
        end

        if jukeboxAnimatorPhase == 'hidden' then
            return false
        end

        if jukeboxAnimatorPhase == 'waiting' then
            if not jukeboxAnimatorPlaybackActive then
                hideJukeboxAnimatorVisual()
                return false
            end
            jukeboxAnimatorWaitMs = jukeboxAnimatorWaitMs + ANIMATOR_TICK_MS
            if jukeboxAnimatorWaitMs >= ANIMATOR_PLAYING_DELAY_MS then
                startJukeboxPlayingSheet()
            end
            return true
        end

        if jukeboxAnimator == nil then
            hideJukeboxAnimatorVisual()
            return false
        end

        jukeboxAnimator:Update()
        jukeboxAnimatorElapsedMs = jukeboxAnimatorElapsedMs + ANIMATOR_TICK_MS
        if jukeboxAnimatorElapsedMs < (jukeboxAnimatorCurrentFrameMs * math.max(1, jukeboxAnimatorCurrentFrameCount)) then
            return true
        end

        if jukeboxAnimatorPhase == 'transition' then
            local finishedKind = jukeboxAnimatorKind
            local callbackToken = jukeboxAnimatorTransitionCallbackToken
            jukeboxAnimatorTransitionCallbackToken = ''
            if finishedKind == 'play' and jukeboxAnimatorPlaybackActive then
                enterJukeboxPlayingDelay()
            else
                hideJukeboxAnimatorVisual()
            end
            notifyJukeboxAnimationComplete(finishedKind, callbackToken)
        elseif jukeboxAnimatorPhase == 'playing' then
            if jukeboxAnimatorPlaybackActive then
                enterJukeboxPlayingDelay()
            else
                hideJukeboxAnimatorVisual()
            end
        else
            hideJukeboxAnimatorVisual()
        end
        return true
    end)
end

function OnJukeboxMinimizedMouseDown(x, y)
    return safeCall(function()
        if not JukeboxIsMinimizedForm() then
            return false
        end
        minimizedDragging = true
        minimizedDragAllowedAtDown = isJukeboxDragAllowed()
        minimizedDragMoved = false
        minimizedDownX = tonumber(x) or 0
        minimizedDownY = tonumber(y) or 0
        minimizedDownWindowX = currentWindowX()
        minimizedDownWindowY = currentWindowY()
        minimizedLastWindowY = minimizedDownWindowY
        return true
    end)
end

function OnJukeboxMinimizedMouseMove(x, y)
    return safeCall(function()
        if not JukeboxIsMinimizedForm() or not minimizedDragging or not minimizedDragAllowedAtDown then
            return false
        end
        local mouseX = tonumber(x) or minimizedDownX
        local mouseY = tonumber(y) or minimizedDownY
        local dx = mouseX - minimizedDownX
        local dy = mouseY - minimizedDownY
        local windowDx = currentWindowX() - minimizedDownWindowX
        local windowDy = currentWindowY() - minimizedDownWindowY
        if math.abs(dx) >= MINIMIZED_DRAG_THRESHOLD or math.abs(dy) >= MINIMIZED_DRAG_THRESHOLD
            or math.abs(windowDx) >= MINIMIZED_DRAG_THRESHOLD or math.abs(windowDy) >= MINIMIZED_DRAG_THRESHOLD then
            minimizedDragMoved = true
        end
        return true
    end)
end

function OnJukeboxMinimizedMouseUp(x, y)
    return safeCall(function()
        if not JukeboxIsMinimizedForm() then
            minimizedDragging = false
            return false
        end
        local moved = minimizedDragMoved
        if minimizedDragging and not moved then
            local mouseX = tonumber(x) or minimizedDownX
            local mouseY = tonumber(y) or minimizedDownY
            moved = math.abs(mouseX - minimizedDownX) > MINIMIZED_DRAG_THRESHOLD or math.abs(mouseY - minimizedDownY) > MINIMIZED_DRAG_THRESHOLD
        end
        minimizedDragging = false
        minimizedDragAllowedAtDown = false
        minimizedDragMoved = false
        if moved then
            local targetX = persistSharedJukeboxX(currentWindowX())
            moveJukeboxToMinimizedBottom(targetX)
            return true
        end
        return playClickSoundForResult(RestoreJukeboxFromMinimized(currentWindowX()))
    end)
end

function OnJukeboxMinimizedMouseLeave()
    return safeCall(function()
        if not JukeboxIsMinimizedForm() then
            return false
        end
        if minimizedDragging and minimizedDragAllowedAtDown and minimizedDragMoved then
            local targetX = persistSharedJukeboxX(currentWindowX())
            moveJukeboxToMinimizedBottom(targetX)
        end
        minimizedDragging = false
        minimizedDragAllowedAtDown = false
        minimizedDragMoved = false
        return true
    end)
end

function RequestDiscSlotPlayback(slotIndex, slotName, path, action)
    return safeCall(function()
        slotIndex = tonumber(slotIndex) or 0
        slotName = trim(slotName)
        path = trim(path)
        action = trim(action):lower()
        if action ~= 'play' and action ~= 'pause' then
            return false
        end
        if action == 'play' and path == '' then
            return false
        end
        if isExternalPlaybackSourceMode() then
            return false
        end
        if discSlotSwitchState.pending then
            return false
        end

        pollSuspendedAfterError = false
        StartJukeboxEventPolling()
        if action == 'play' and shouldSwitchDiscSlotPlayback(slotIndex, slotName, path) then
            return beginDiscSlotSwitchPlayback(slotIndex, slotName, path)
        end

        local command = action == 'pause' and 'Pause' or 'Play'
        local accepted = runPlaybackCommand(command, path, 'ModalAlert_JukeboxHelperStartFailed', {
            slotIndex = slotIndex,
            slotName = slotName,
            path = path,
            action = action,
        })
        if accepted then
            if action == 'pause' then
                setJukeboxAnimatorPlaybackActive(false)
            end
            startJukeboxAnimation(action == 'pause' and 'stop' or 'play')
        end
        return accepted
    end)
end

function RequestEndedDiscSlotPlayback(slotIndex, slotName, path)
    return safeCall(function()
        slotIndex = tonumber(slotIndex) or 0
        slotName = trim(slotName)
        path = trim(path)
        if slotIndex <= 0 or path == '' then
            return false
        end
        if isExternalPlaybackSourceMode() then
            return false
        end
        if discSlotSwitchState.pending then
            return false
        end

        pollSuspendedAfterError = false
        StartJukeboxEventPolling()
        return beginEndedDiscSlotSwitchPlayback(slotIndex, slotName, path)
    end)
end

function HandleJukeboxAnimationComplete(kind, token)
    return safeCall(function()
        kind = trim(kind):lower()
        token = trim(token)
        if kind ~= 'stop' then
            return false
        end
        local pendingSwitch = discSlotSwitchState.pending
        if pendingSwitch and pendingSwitch.token == token then
            pendingSwitch.stopAnimationDone = true
            if discSlotSwitchState.tryStartPlay then
                return discSlotSwitchState.tryStartPlay()
            end
            return true
        end
        return externalPlaybackState:completeVisualSwitch(token)
    end)
end

function ClearEndedDiscSlotPlayback()
    return safeCall(function()
        return clearEndedDiscSlotPlayback()
    end)
end

function ShowDiscSlotAlert(kind, detail)
    return safeCall(function()
        kind = trim(kind)
        local key = ''
        if kind == 'scanner_missing' then
            key = 'ModalAlert_JukeboxDiscSlotScannerMissing'
        elseif kind == 'scanner_failed' then
            key = 'ModalAlert_JukeboxDiscSlotScannerFailed'
        elseif kind == 'settings_route_failed' then
            key = 'ModalAlert_JukeboxDiscSlotSettingsRouteFailed'
        elseif kind == 'volume_dialog_failed' then
            key = 'ModalAlert_JukeboxDiscSlotVolumeDialogFailed'
        else
            SKIN:Bang('!Log', 'Ignored unknown Jukebox DiscSlot alert kind: ' .. tostring(kind), 'Warning')
            return false
        end
        return showAlert('warn', key, fallbackForKey(key), modalAlertLogPath())
    end)
end

function ShowUnsupportedAudio(fileName, supportedExtensions)
    return safeCall(function()
        fileName = trim(fileName)
        if fileName == '' then
            fileName = '?'
        end
        supportedExtensions = trim(supportedExtensions)
        if supportedExtensions == '' then
            supportedExtensions = SUPPORTED_AUDIO_EXTENSIONS
        end
        return showAlert(
            'warn',
            'ModalAlert_JukeboxUnsupportedAudio',
            fallbackForKey('ModalAlert_JukeboxUnsupportedAudio'),
            modalAlertLogPath(),
            { fileName, supportedExtensions },
            { primaryKey = 'Loc_Common_OpenFolder', openFolderPath = jukeboxDiscAudioDirectoryPath() })
    end)
end
function ShowCurrentPlaybackHotbarText()
    return safeCall(function()
        if isExternalPlaybackSourceMode() then
            return showCurrentExternalPlaybackHotbarText(true)
        end
        return showCurrentPlaybackHotbarTextForSelection(nil, true)
    end)
end

function ReleaseCurrentPlaybackHotbarText()
    return safeCall(function()
        local configName = hotbarConfigName()
        if configName == '' or not configName:find('[\\/]') then
            return false
        end
        commandMeasureForActiveConfig('MeasureHighlight', string.format('ReleasePinnedExternalHotbarText(%q)', 'Jukebox'), configName)
        return true
    end)
end

function HandleExternalCoverFetchFailure(url, statusCode)
    return safeCall(function()
        if not isExternalPlaybackSourceMode() then
            return false
        end
        if not externalPlaybackState:markCoverFetchFailure(url, statusCode) then
            return false
        end
        SKIN:Bang('!Log', 'Jukebox marked external cover fetch failure: status=' .. trim(statusCode), 'Warning')
        syncDiscSlotPlaybackModeControls()
        return true
    end)
end

function RetryExternalCoverFetch()
    return safeCall(function()
        if not isExternalPlaybackSourceMode() then
            return false
        end
        externalPlaybackState:clearCoverFetchFailure()
        externalPlaybackState.coverRetryNonce = (tonumber(externalPlaybackState.coverRetryNonce) or 0) + 1
        if externalPlaybackState.coverRetryNonce > 999999 then
            externalPlaybackState.coverRetryNonce = 1
        end
        syncDiscSlotPlaybackModeControls()
        local bridgeActive = commandMeasureForActiveConfig('MeasureWebNowPlayingBridge', 'RefreshCover()', webNowPlayingBridgeConfigName())
        if not bridgeActive then
            SKIN:Bang('!Log', 'Jukebox external cover retry requested while WebNowPlaying bridge is inactive.', 'Warning')
        end
        return bridgeActive
    end)
end

function SyncExternalPlaybackState()
    return safeCall(function()
        local hadExternalObservation = externalPlaybackState.observed
        local wasExternalPlaying = hadExternalObservation and externalPlaybackState.bridgeActive and externalPlaybackConnected() and trim(externalPlaybackState.state) == '1'
        local previousMediaIdentity = hadExternalObservation and trim(externalPlaybackState.mediaIdentity) or ''
        externalPlaybackState.pluginLoadFailed = trim(SKIN:GetVariable('JukeboxExternalBridgePluginFailed', '0')) == '1'
        if not externalPlaybackState.pluginLoadFailed then
            externalPlaybackState.bridgeFailureAlertShown = false
        end
        local bridgeConfigActive = isRainmeterConfigActive(webNowPlayingBridgeConfigName())
        externalPlaybackState.bridgeActive = not externalPlaybackState.pluginLoadFailed
            and bridgeConfigActive
            and trim(SKIN:GetVariable('JukeboxExternalBridgeActive', '0')) == '1'
        externalPlaybackState.bridgeActivationRequested = false
        externalPlaybackState.status = trim(SKIN:GetVariable('JukeboxExternalStatus', '0'))
        externalPlaybackState.player = trim(SKIN:GetVariable('JukeboxExternalPlayer', ''))
        externalPlaybackState.title = trim(SKIN:GetVariable('JukeboxExternalTitle', ''))
        externalPlaybackState.artist = trim(SKIN:GetVariable('JukeboxExternalArtist', ''))
        externalPlaybackState.album = trim(SKIN:GetVariable('JukeboxExternalAlbum', ''))
        externalPlaybackState.cover = trim(SKIN:GetVariable('JukeboxExternalCover', ''))
        externalPlaybackState.duration = trim(SKIN:GetVariable('JukeboxExternalDuration', '0'))
        externalPlaybackState.volume = trim(SKIN:GetVariable('JukeboxExternalVolume', '0'))
        externalPlaybackState.state = trim(SKIN:GetVariable('JukeboxExternalState', '0'))
        externalPlaybackState.repeatMode = trim(SKIN:GetVariable('JukeboxExternalRepeat', '0'))
        externalPlaybackState.shuffle = trim(SKIN:GetVariable('JukeboxExternalShuffle', '0'))
        externalPlaybackState.supportsPlayPause = trim(SKIN:GetVariable('JukeboxExternalSupportsPlayPause', '0'))
        externalPlaybackState.supportsSkipPrevious = trim(SKIN:GetVariable('JukeboxExternalSupportsSkipPrevious', '0'))
        externalPlaybackState.supportsSkipNext = trim(SKIN:GetVariable('JukeboxExternalSupportsSkipNext', '0'))
        externalPlaybackState.supportsSetVolume = trim(SKIN:GetVariable('JukeboxExternalSupportsSetVolume', '0'))
        externalPlaybackState.supportsToggleRepeatMode = trim(SKIN:GetVariable('JukeboxExternalSupportsToggleRepeatMode', '0'))
        externalPlaybackState.supportsToggleShuffleActive = trim(SKIN:GetVariable('JukeboxExternalSupportsToggleShuffleActive', '0'))
        if externalPlaybackState.pluginLoadFailed then
            externalPlaybackState.bridgeReconnectRequested = false
        elseif externalPlaybackState.bridgeActive and externalPlaybackConnected() then
            externalPlaybackState.bridgeReconnectRequested = false
        end
        if isExternalPlaybackSourceMode() then
            if externalPlaybackState.pluginLoadFailed then
                externalPlaybackState.pendingCommand = nil
                externalPlaybackState.pendingValueText = nil
                externalPlaybackState.pendingCommandReconnectRetry = false
                externalPlaybackState:clearVisualSwitch()
                externalPlaybackState:clearCoverFetchFailure()
                setJukeboxAnimatorPlaybackActive(false)
                syncDiscSlotPlaybackModeControls()
                webNowPlayingInstallState.showInitializationFailed(false)
                return true
            end
            local externalPlaying = externalPlaybackState.bridgeActive and externalPlaybackConnected() and externalPlaybackState.state == '1'
            local currentMediaIdentity = externalPlaybackState:trackIdentity()
            if hadExternalObservation and previousMediaIdentity ~= '' and currentMediaIdentity ~= '' and previousMediaIdentity ~= currentMediaIdentity then
                externalPlaybackState:clearCoverFetchFailure()
            elseif externalPlaybackState.coverFetchFailed and not externalPlaybackState:coverFailureMatchesCurrent() then
                externalPlaybackState:clearCoverFetchFailure()
            end
            local mediaChanged = hadExternalObservation
                and previousMediaIdentity ~= ''
                and currentMediaIdentity ~= ''
                and previousMediaIdentity ~= currentMediaIdentity
                and externalPlaybackState:hasTrackIdentity()
            externalPlaybackState.mediaIdentity = currentMediaIdentity
            externalPlaybackState:applyVisualTransition(hadExternalObservation, wasExternalPlaying, externalPlaying, mediaChanged)
            externalPlaybackState.observed = true
            syncDiscSlotPlaybackModeControls()
            if externalPlaybackState.pendingCommand then
                if externalPlaybackState.pluginLoadFailed then
                    externalPlaybackState.pendingCommand = nil
                    externalPlaybackState.pendingValueText = nil
                    externalPlaybackState.pendingCommandReconnectRetry = false
                    webNowPlayingInstallState.showInitializationFailed(false)
                elseif not externalPlaybackState.bridgeActive then
                    if not externalPlaybackState.bridgeReconnectRequested then
                        externalPlaybackState.pendingCommand = nil
                        externalPlaybackState.pendingValueText = nil
                        externalPlaybackState.pendingCommandReconnectRetry = false
                        webNowPlayingInstallState.showInitializationFailed(false)
                    end
                elseif not externalPlaybackConnected() then
                    if not externalPlaybackState.bridgeReconnectRequested then
                        local pendingCommand = externalPlaybackState.pendingCommand
                        externalPlaybackState.pendingCommand = nil
                        externalPlaybackState.pendingValueText = nil
                        externalPlaybackState.pendingCommandReconnectRetry = false
                        showExternalPlayerUnavailable('pending-command-unavailable', pendingCommand)
                    end
                else
                    local command = externalPlaybackState.pendingCommand
                    local valueText = externalPlaybackState.pendingValueText or ''
                    local retryAfterReconnect = externalPlaybackState.pendingCommandReconnectRetry
                    externalPlaybackState.pendingCommand = nil
                    externalPlaybackState.pendingValueText = nil
                    externalPlaybackState.pendingCommandReconnectRetry = false
                    dispatchExternalCommand(command, valueText, retryAfterReconnect and 'reconnect-retry' or 'pending')
                end
            end
            finishExternalCommandWatchIfObserved()
        else
            externalPlaybackState.observed = false
            externalPlaybackState.mediaIdentity = ''
            externalPlaybackState:clearVisualSwitch()
        end
        return true
    end)
end

function StopPlayback()
    return safeCall(function()
        if not initialized then
            Initialize()
        end
        if isExternalPlaybackSourceMode() then
            pendingDiscSlotPlayback = nil
            discSlotSwitchState.pending = nil
            externalPlaybackState.pendingCommand = nil
            externalPlaybackState.pendingValueText = nil
            forceHideJukeboxAnimator()
            setJukeboxAnimatorPlaybackActive(false)
            deactivateExternalBridge()
            resetExternalPlaybackState()
            return true
        end
        return stopLocalPlayback()
    end)
end

function PollPlayerEvent()
    return safeCall(function()
        if pollSuspendedAfterError then
            StopJukeboxEventPolling()
            return false
        end
        if not initialized then
            Initialize()
        end
        if discSlotPendingShow then
            TryCompleteDiscSlotDeferredSync()
        end
        if isExternalPlaybackSourceMode() then
            return true
        end

        if runMeasure and runMeasure('poll', 'MeasureJukeboxPollEventRun', 'ModalAlert_JukeboxEventPollFailed') then
            return true
        end
        return false
    end)
end

function UpdateJukeboxAnimationDriver()
    if not initialized then
        return 0
    end

    if jukeboxAnimatorPhase ~= 'hidden' then
        UpdateJukeboxAnimation()
    end
    if minimizedAnimatorPhase ~= 'hidden' then
        UpdateJukeboxMinimizedAnimation()
    end

    syncJukeboxAnimationDriver()
    return 0
end

function UpdateJukeboxRuntime()
    if not initialized then
        return 0
    end
    if JukeboxScheduler.responsive then
        SKIN:Bang('!UpdateMeasure', 'MeasureResponsiveLayout')
    end
    if JukeboxScheduler.minimizedIdle then
        PollJukeboxMinimizedIdle()
    end
    if JukeboxScheduler.eventPolling then
        JukeboxScheduler.eventPollRuntimeTicks = JukeboxScheduler.eventPollRuntimeTicks + 1
        if JukeboxScheduler.eventPollRuntimeTicks >= JUKEBOX_EVENT_POLL_RUNTIME_TICKS then
            JukeboxScheduler.eventPollRuntimeTicks = 0
            PollPlayerEvent()
        end
    end
    if JukeboxScheduler.externalCommandWatchdog then
        tickExternalCommandWatchdog()
    end
    syncJukeboxRuntimeDriver()
    return 0
end

function Update()
    return 0
end

function HandleCommandComplete(kind)
    return safeCall(function()
        kind = trim(kind)
        local measureName = 'MeasureJukeboxPlaybackRun'
        if kind == 'stop' then
            measureName = 'MeasureJukeboxStopRun'
        elseif kind == 'loop' then
            measureName = 'MeasureJukeboxSetLoopRun'
        elseif kind == 'volume' then
            measureName = 'MeasureJukeboxSetVolumeRun'
        elseif kind == 'poll' then
            measureName = 'MeasureJukeboxPollEventRun'
        end
        if commandRunning[kind] ~= nil then
            commandRunning[kind] = false
        end
        if kind == 'playback' and commandRunning.stopPendingAfterExternalSwitch then
            commandRunning.stopPendingAfterExternalSwitch = false
            stopLocalPlayback()
            return true
        end
        if isExternalPlaybackSourceMode() and (kind == 'playback' or kind == 'stop' or kind == 'loop' or kind == 'volume') then
            if kind == 'playback' then
                stopLocalPlayback()
            elseif kind == 'stop' then
                return handleResult(kind, measureOutput(measureName), 'ModalAlert_JukeboxCommandFailed')
            elseif kind == 'volume' then
                commandRunning.volumePending = false
            end
            return true
        end
        local defaultKey = kind == 'poll' and 'ModalAlert_JukeboxEventPollFailed' or 'ModalAlert_JukeboxCommandFailed'
        local result = handleResult(kind, measureOutput(measureName), defaultKey)
        if kind == 'volume' and commandRunning.volumePending then
            commandRunning.volumePending = false
            requestHelperVolumeSync(currentPlaybackVolume())
        end
        return result
    end)
end


function HandleEmergencyStopComplete()
    return safeCall(function()
        commandRunning.emergencyStop = false
        local values = parsePairs(measureOutput('MeasureJukeboxEmergencyStopRun'))
        local status = upper(values.DMEL_STATUS)
        if status == '' then
            SKIN:Bang('!Log', 'Jukebox emergency stop returned no DMEL_STATUS.', 'Warning')
        elseif status == 'ERROR' then
            SKIN:Bang('!Log', 'Jukebox emergency stop failed: ' .. trim(values.DMEL_MESSAGE), 'Error')
        end
        return true
    end)
end
