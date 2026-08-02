return function(app)

    local state = app.state
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local versionUpdateNotice = app.loadSharedLuaModule('VersionUpdateNotice.lua')
    local versionBadgeFeed = app.loadSharedLuaModule('VersionBadgeFeed.lua')
    local latestUpdateClientModule = app.loadSharedLuaModule('LatestUpdateClient.lua')
    local configState = app.loadSharedLuaModule('RainmeterConfigState.lua')

    local VERSION_STATUS_CACHE_SECONDS = 1
    local VERSION_STATUS_VISUAL_METERS = {
        'MeterSettingsNoticeBarBG',
        'MeterSettingsNoticeViewAllBG', 'MeterSettingsNoticeViewAllLabel',
        'MeterSettingsNoticeBodyText',
        'MeterSettingsNoticeDismissBG', 'MeterSettingsNoticeDismissLabel',
        'MeterSettingsLoadingCover', 'MeterSettingsLoadingLabel',
    }

    local VERSION_STATUS = {
        checking = {
            iconText = '...',
            bgColor = '74,109,167,255',
            textColor = '255,255,255,255',
            tooltipKey = 'Helper_VersionManager_Summary_UpdateChecking',
            tooltipFallback = 'Update status: checking latest version...',
        },
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
    local versionBadgeController = nil
    local latestUpdateClient = nil

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

    local function versionManagerLoadingText()
        local localizedDetail = methods.localizeFormat(
            'Settings_Notice_VersionManagerOpeningDetail',
            { '0' },
            'Opening the Skin manager.'
        )
        local normalizedDetail = tostring(localizedDetail or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
        return normalizedDetail:match('^(.-)\n\n') or normalizedDetail
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
            repositorySlug = readCacheVariable('VersionManagerCacheRepositorySlug'),
            releaseVariant = readCacheVariable('VersionManagerCacheReleaseVariant'),
            assetName = readCacheVariable('VersionManagerCacheAssetName'),
            status = readCacheVariable('VersionManagerCacheStatus'),
            errorCode = string.lower(readCacheVariable('VersionManagerCacheErrorCode')),
            failureHint = string.lower(readCacheVariable('VersionManagerCacheFailureHint')),
            lastCheckedAtUtc = readCacheVariable('VersionManagerCacheLastCheckedAtUtc'),
            lastAttemptAtUtc = readCacheVariable('VersionManagerCacheLastAttemptAtUtc'),
            lastNoticeAtUtc = readCacheVariable('VersionManagerCacheLastNoticeAtUtc'),
            lastNoticeVersion = readCacheVariable('VersionManagerCacheLastNoticeVersion'),
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
        local releaseVariant = trim(SKIN:GetVariable('UpdateReleaseVariant', ''))
        local repository = latestUpdateClientModule.ResolveRepository(
            SKIN:GetVariable('UpdateGithubOwner', ''),
            SKIN:GetVariable('UpdateGithubRepo', ''))
        local cacheProvenanceValid = repository ~= nil
            and latestUpdateClientModule.CacheProvenanceMatches(
                cache, releaseVariant, repository.slug)
        local resolvedStatus = VERSION_STATUS.unknown

        if state.versionBadgeCheckState == 'checking' then
            resolvedStatus = VERSION_STATUS.checking
        elseif state.versionBadgeCheckState == 'network-error'
            or cache.failureHint == 'offline' or cache.errorCode == 'badge-feed-network'
            or cache.errorCode == 'update-network-offline' then
            resolvedStatus = VERSION_STATUS.offline
        elseif state.versionBadgeCheckState == 'format-error'
            or cache.status == 'error' or cache.errorCode ~= '' then
            resolvedStatus = VERSION_STATUS.unknown
        elseif not cacheProvenanceValid then
            resolvedStatus = VERSION_STATUS.unknown
        elseif comparison == 0 or comparison == 1 then
            resolvedStatus = VERSION_STATUS.latest
        elseif comparison == -1 then
            resolvedStatus = VERSION_STATUS.outdated
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

    local function latestUpdateHelper()
        if latestUpdateClient then
            return latestUpdateClient
        end
        latestUpdateClient = latestUpdateClientModule.Create({
            skin = SKIN,
            configState = configState,
            deferredVariable = 'BlockHudSettingsLatestUpdateDeferredStart',
            deferredMeasure = 'MeasureSettingsLatestUpdateDeferredStart',
        })
        return latestUpdateClient
    end

    local function refreshVersionBadgeState()
        invalidateVersionStatusCache()
        if methods.renderVersionStatusState then
            methods.renderVersionStatusState()
        end
        refreshVersionStatusAndLoadingVisuals()
    end

    local function ensureVersionBadgeController()
        if versionBadgeController then
            return versionBadgeController
        end
        versionBadgeController = versionBadgeFeed.Create({
            skin = SKIN,
            currentVersion = function()
                return methods.readSettingsMetadataVersion()
            end,
            variant = function()
                return SKIN:GetVariable('UpdateReleaseVariant', '')
            end,
            repositorySlug = function()
                local repository = latestUpdateClientModule.ResolveRepository(
                    SKIN:GetVariable('UpdateGithubOwner', ''),
                    SKIN:GetVariable('UpdateGithubRepo', ''))
                return repository and repository.slug or ''
            end,
            cachePath = function()
                return methods.cachePath()
            end,
            onCacheChanged = function()
                invalidateVersionStatusCache()
            end,
            onStateChanged = function(stateName, detail)
                if stateName == 'checking' then
                    state.versionBadgeCheckState = 'checking'
                elseif stateName == 'error' and detail == 'network' then
                    state.versionBadgeCheckState = 'network-error'
                elseif stateName == 'error' then
                    state.versionBadgeCheckState = 'format-error'
                else
                    state.versionBadgeCheckState = ''
                end
                refreshVersionBadgeState()
            end,
            onOutdated = function(currentVersion, latestVersion)
                return versionNoticeHelper():QueueOutdated(currentVersion, latestVersion)
            end,
        })
        return versionBadgeController
    end

    function methods.isVersionManagerLaunchPending()
        return state.versionManagerLaunchPending == true
    end

    function methods.beginVersionManagerLaunchPending()
        local token = tostring(os.time() or 0) .. '-' .. tostring(math.floor((os.clock() or 0) * 1000))
        state.versionManagerLaunchPending = true
        state.versionManagerLaunchToken = token
        state.versionManagerLaunchLastStatus = ''
        state.versionManagerLaunchLastObservedToken = ''
        writeVersionManagerLaunchState(token, 'launching', '')
        if methods.setLoadingVisible then
            methods.setLoadingVisible(true, versionManagerLoadingText())
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
        return ensureVersionBadgeController():StartManual()
    end

    function methods.HandleVersionBadgeFeedSuccess()
        return ensureVersionBadgeController():CompleteFromMeasure()
    end

    function methods.HandleVersionBadgeFeedError(kind)
        return ensureVersionBadgeController():CompleteError(kind)
    end

    function methods.OpenPendingVersionNotice()
        return versionNoticeHelper():OpenPending()
    end

    function methods.OpenUpdateReleaseNotes()
        SKIN:Bang('["' .. versionUpdateNotice.ReleaseNotesUrl() .. '"]')
        return true
    end

    function methods.StartLatestVersionUpdate(token)
        return latestUpdateHelper():Request(
            token,
            methods.readSettingsMetadataVersion(),
            readCacheVariable('VersionManagerCacheLatestVersion'),
            SKIN:GetVariable('UpdateReleaseVariant', ''),
            SKIN:GetVariable('UpdateGithubOwner', ''),
            SKIN:GetVariable('UpdateGithubRepo', ''),
            readCacheVariable('VersionManagerCacheRepositorySlug'),
            readCacheVariable('VersionManagerCacheReleaseVariant'),
            readCacheVariable('VersionManagerCacheAssetName'))
    end

    function methods.OpenPendingLatestUpdate()
        return latestUpdateHelper():DispatchPending()
    end

    function methods.HandleExternalVersionCatalogRefreshComplete()
        if versionBadgeController and versionBadgeController:IsRunning() then
            state.versionBadgeCheckState = 'checking'
        else
            state.versionBadgeCheckState = ''
        end
        refreshVersionBadgeState()
    end

end
