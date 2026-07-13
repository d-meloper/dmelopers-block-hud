return function(app)

    local state = app.state
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local versionUpdateNotice = app.loadSharedLuaModule('VersionUpdateNotice.lua')
    local configState = app.loadSharedLuaModule('RainmeterConfigState.lua')

    local VERSION_MANAGER_LAUNCH_TIMEOUT_SECONDS = 20
    local VERSION_STATUS_CACHE_SECONDS = 1
    local VERSION_STATUS_VISUAL_METERS = {
        'MeterSettingsNoticeBarBG',
        'MeterSettingsNoticeViewAllBG', 'MeterSettingsNoticeViewAllLabel',
        'MeterSettingsNoticeBodyText',
        'MeterSettingsNoticeDismissBG', 'MeterSettingsNoticeDismissLabel',
        'MeterSettingsLoadingCover', 'MeterSettingsLoadingLabel',
    }

    local VERSION_STATUS = {
        latest = {
            iconText = '✓',
            bgColor = '64,158,83,255',
            textColor = '255,255,255,255',
            tooltipKey = 'Settings_Notice_VersionStatus_Latest',
            tooltipFallback = 'Current skin version is up to date.',
        },
        outdated = {
            iconText = '!',
            bgColor = '184,134,11,255',
            textColor = '255,255,255,255',
            tooltipKey = 'Settings_Notice_VersionStatus_Outdated',
            tooltipFallback = 'Current skin version is not the latest version.',
        },
        unknown = {
            iconText = 'X',
            bgColor = '192,72,72,255',
            textColor = '255,255,255,255',
            tooltipKey = 'Settings_Notice_VersionStatus_Unknown',
            tooltipFallback = 'Latest version information is unavailable.',
        },
        offline = {
            iconText = 'X',
            bgColor = '192,72,72,255',
            textColor = '255,255,255,255',
            tooltipKey = 'Settings_Notice_VersionStatus_Offline',
            tooltipFallback = 'The internet connection is unavailable.',
        },
    }

    local cachedVersionStatus = nil
    local updateNotice = nil

    local function localizedVariableOrText(key, fallback)
        local variableRef = methods.localizationVariableRef and methods.localizationVariableRef(key) or ''
        if variableRef ~= '' then
            return variableRef
        end
        return methods.localize(key, fallback)
    end

    local function nowWallClockSeconds()
        return tonumber(os.time() or 0) or 0
    end

    local function refreshVersionStatusAndLoadingVisuals()
        for _, meterName in ipairs(VERSION_STATUS_VISUAL_METERS) do
            SKIN:Bang('!UpdateMeter', meterName)
        end
        SKIN:Bang('!Redraw')
    end

    local function invalidateVersionStatusCache()
        cachedVersionStatus = nil
    end

    local function readCacheVariable(name)
        return trim(SKIN:GetVariable(tostring(name or ''), ''))
    end

    local function writeCacheVariable(name, value)
        if methods.writePersistentCacheVariable then
            methods.writePersistentCacheVariable(name, value)
        else
            setVariable(name, tostring(value or ''))
        end
    end

    local function readVersionManagerCache()
        return {
            latestVersion = readCacheVariable('VersionManagerCacheLatestVersion'),
            status = readCacheVariable('VersionManagerCacheStatus'),
            errorCode = string.lower(readCacheVariable('VersionManagerCacheErrorCode')),
            failureHint = string.lower(readCacheVariable('VersionManagerCacheFailureHint')),
            lastCheckedAtUtc = readCacheVariable('VersionManagerCacheLastCheckedAtUtc'),
        }
    end

    local function readVersionManagerLaunchState()
        return {
            launchToken = readCacheVariable('VersionManagerLaunchToken'),
            status = string.lower(readCacheVariable('VersionManagerLaunchStatus')),
            message = readCacheVariable('VersionManagerLaunchMessage'),
        }
    end

    local function writeVersionManagerLaunchState(launchToken, status, message)
        writeCacheVariable('VersionManagerLaunchToken', launchToken)
        writeCacheVariable('VersionManagerLaunchStatus', status)
        writeCacheVariable('VersionManagerLaunchMessage', message)
    end

    local function resolveVersionStatus()
        local now = nowWallClockSeconds()
        if cachedVersionStatus and now < (cachedVersionStatus.expiresAt or 0) then
            return cachedVersionStatus.versionText, cachedVersionStatus.status
        end

        local currentVersion = trim(methods.readSettingsMetadataVersion())
        local versionText = methods.appVersionDisplayValue()
        local cache = readVersionManagerCache()
        local comparison = versionUpdateNotice.CompareVersions(currentVersion, cache.latestVersion)
        local resolvedStatus = VERSION_STATUS.unknown

        if comparison == 0 or comparison == 1 then
            resolvedStatus = VERSION_STATUS.latest
        elseif comparison == -1 then
            resolvedStatus = VERSION_STATUS.outdated
        elseif cache.failureHint == 'offline' or cache.errorCode == 'update-network-offline' then
            resolvedStatus = VERSION_STATUS.offline
        end

        cachedVersionStatus = {
            versionText = versionText,
            status = resolvedStatus,
            expiresAt = now + VERSION_STATUS_CACHE_SECONDS,
        }
        return versionText, resolvedStatus
    end

    local function modalConfigName()
        local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))
        if rootConfig == '' then
            return ''
        end
        return rootConfig .. '\\Utilities\\Modal'
    end

    local function versionNoticeHelper()
        if updateNotice then
            return updateNotice
        end

        updateNotice = versionUpdateNotice.Create({
            skin = SKIN,
            targetConfig = function()
                return SKIN:GetVariable('CURRENTCONFIG', '')
            end,
            targetMeasure = 'MeasureSettingsCommit',
            modalConfig = modalConfigName,
            deferredVariable = 'BlockHudSettingsVersionNoticeDeferredOpen',
            deferredMeasure = 'MeasureSettingsVersionNoticeDeferredOpen',
            releaseNotesCallback = 'OpenUpdateReleaseNotes',
            updateCallback = 'StartLatestVersionUpdate',
            configState = configState,
        })
        return updateNotice
    end

    function methods.isVersionManagerLaunchPending()
        return state.versionManagerLaunchPending == true
    end

    function methods.beginVersionManagerLaunchPending()
        local token = tostring(os.time() or 0) .. '-' .. tostring(math.floor((os.clock() or 0) * 1000))
        state.versionManagerLaunchPending = true
        state.versionManagerLaunchStartedAt = nowWallClockSeconds()
        state.versionManagerLaunchToken = token
        state.versionManagerLaunchLastStatus = ''
        state.versionManagerLaunchLastObservedToken = ''
        writeVersionManagerLaunchState(token, 'launching', '')
        if methods.setLoadingVisible then
            methods.setLoadingVisible(true, methods.localize('Settings_Notice_VersionManagerOpening', 'Opening Skins...\nPlease wait.'))
        end
        if methods.renderVersionStatusState then
            methods.renderVersionStatusState()
        end
        refreshVersionStatusAndLoadingVisuals()
        methods.SetUpdateJob('versionManager', true)
        return token
    end

    function methods.clearVersionManagerLaunchPending(options)
        local token = trim(state.versionManagerLaunchToken or '')
        state.versionManagerLaunchPending = false
        state.versionManagerLaunchStartedAt = 0
        state.versionManagerLaunchToken = ''
        state.versionManagerLaunchLastStatus = ''
        state.versionManagerLaunchLastObservedToken = ''
        writeVersionManagerLaunchState('', '', '')
        if methods.setLoadingVisible then
            methods.setLoadingVisible(false)
        end
        methods.SetUpdateJob('versionManager', false)
        if not options or options.render ~= false then
            invalidateVersionStatusCache()
            if methods.renderVersionStatusState then
                methods.renderVersionStatusState()
            end
            refreshVersionStatusAndLoadingVisuals()
        end
    end

    function methods.RunPendingVersionManagerLaunch()
        if methods.isVersionManagerLaunchPending() ~= true then
            methods.SetUpdateJob('versionManager', false)
            return
        end

        local now = nowWallClockSeconds()
        local startedAt = tonumber(state.versionManagerLaunchStartedAt) or 0
        if startedAt > 0 and (now - startedAt) >= VERSION_MANAGER_LAUNCH_TIMEOUT_SECONDS then
            methods.clearVersionManagerLaunchPending()
            return
        end

        local launchState = readVersionManagerLaunchState()
        local expectedToken = trim(state.versionManagerLaunchToken or '')
        local observedToken = trim(launchState.launchToken or '')
        local status = trim(launchState.status or '')
        local matched = expectedToken ~= '' and expectedToken == observedToken

        if state.versionManagerLaunchLastStatus == status
            and state.versionManagerLaunchLastObservedToken == observedToken then
            return
        end

        state.versionManagerLaunchLastStatus = status
        state.versionManagerLaunchLastObservedToken = observedToken

        if matched and status == 'shown' then
            methods.clearVersionManagerLaunchPending()
            return
        end

        if matched and status == 'error' then
            methods.clearVersionManagerLaunchPending()
        end
    end

    function methods.renderVersionStatusState()
        local versionText, status = resolveVersionStatus()
        local versionManagerTooltip = localizedVariableOrText(
            'Settings_Tooltip_openVersionManager',
            'Opens Skins for installed skins, old-data import, updates, and logs.'
        )
        setVariable('SettingsNoticeBarHidden', '0')
        setVariable('SettingsNoticeBodyHidden', '0')
        setVariable('SettingsNoticeDismissHidden', '0')
        setVariable('SettingsNoticeText', versionText)
        setVariable('SettingsNoticeTextToolTip', '')
        setVariable('SettingsNoticeViewAllText', methods.localize('Settings_Field_openVersionManager_Label', 'Skins'))
        setVariable('SettingsNoticeViewAllToolTip', versionManagerTooltip)
        setVariable('SettingsNoticeDismissText', status.iconText)
        setVariable('SettingsNoticeDismissBgColor', status.bgColor)
        setVariable('SettingsNoticeDismissTextColor', status.textColor)
        setVariable('SettingsNoticeDismissTooltip', localizedVariableOrText(status.tooltipKey, status.tooltipFallback))
    end

    function methods.TryOpenLatestVersionNotice()
        local currentVersion = trim(methods.readSettingsMetadataVersion())
        local cache = readVersionManagerCache()
        if trim(cache.status):lower() ~= 'ready' then
            return false
        end
        return versionNoticeHelper():QueueOutdated(currentVersion, cache.latestVersion)
    end

    function methods.OpenPendingVersionNotice()
        return versionNoticeHelper():OpenPending()
    end

    function methods.OpenUpdateReleaseNotes()
        SKIN:Bang('["' .. versionUpdateNotice.ReleaseNotesUrl() .. '"]')
        return true
    end

    function methods.StartLatestVersionUpdate()
        if methods.startOpenVersionManagerHelper then
            return methods.startOpenVersionManagerHelper('InstallLatest')
        end
        return false
    end

    function methods.HandleExternalVersionCatalogRefreshComplete()
        invalidateVersionStatusCache()
        if methods.renderVersionStatusState then
            methods.renderVersionStatusState()
        end
        refreshVersionStatusAndLoadingVisuals()
    end

end
