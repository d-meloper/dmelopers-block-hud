return function(app)

    local state = app.state
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local logNotice = app.logNotice

    local VERSION_MANAGER_LAUNCH_TIMEOUT_SECONDS = 20
    local VERSION_STATUS_CACHE_SECONDS = 1
    local VERSION_STATUS_AUTO_REFRESH_SECONDS = 24 * 60 * 60
    local VERSION_STATUS_RETRY_SECONDS = 15 * 60
    local VERSION_STATUS_REFRESH_TIMEOUT_SECONDS = 120
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

    local function parseComparableVersion(raw)
        local normalized = trim(raw):gsub('^[vV]', '')
        local core = normalized:match('^(%d[%d%.]*)')
        if not core then
            return nil
        end
        core = core:gsub('%.$', '')
        local suffix = normalized:sub(#core + 1)
        if core == '' or core:find('%.%.', 1, true) then
            return nil
        end
        if suffix ~= '' and not suffix:match('^[-+_ ].*') then
            return nil
        end

        local parts = {}
        for value in core:gmatch('%d+') do
            parts[#parts + 1] = tonumber(value) or 0
        end
        if #parts == 0 then
            return nil
        end
        return parts
    end

    local function compareVersions(leftRaw, rightRaw)
        local left = parseComparableVersion(leftRaw)
        local right = parseComparableVersion(rightRaw)
        if not left or not right then
            return nil
        end

        local limit = math.max(#left, #right)
        for index = 1, limit do
            local leftPart = left[index] or 0
            local rightPart = right[index] or 0
            if leftPart < rightPart then
                return -1
            end
            if leftPart > rightPart then
                return 1
            end
        end

        return 0
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

    local function isVersionManagerCacheEmpty(cache)
        return trim(cache.latestVersion or '') == ''
            and trim(cache.status or '') == ''
            and trim(cache.errorCode or '') == ''
            and trim(cache.lastCheckedAtUtc or '') == ''
    end

    local function parseCacheCheckedAtSeconds(raw)
        local year, month, day, hour, minute, second = trim(raw):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$')
        if not year then
            return nil
        end

        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(minute),
            sec = tonumber(second),
            isdst = false,
        })
    end

    local function cacheAgeSeconds(cache, now)
        local checkedAt = parseCacheCheckedAtSeconds(cache.lastCheckedAtUtc)
        if not checkedAt then
            return nil
        end

        local age = now - checkedAt
        if age < 0 then
            return 0
        end
        return age
    end

    local function isVersionCatalogCacheRefreshRunning(now)
        if state.versionStatusRefreshRunning ~= true then
            return false
        end

        local startedAt = tonumber(state.versionStatusRefreshStartedAt) or 0
        if startedAt > 0 and (now - startedAt) >= VERSION_STATUS_REFRESH_TIMEOUT_SECONDS then
            state.versionStatusRefreshRunning = false
            state.versionStatusRefreshStartedAt = 0
            logNotice('Version status auto refresh timed out; another refresh may be attempted.')
            return false
        end

        return true
    end

    local function isVersionCatalogRefreshAttemptOnCooldown(now)
        local lastAttemptAt = tonumber(state.versionStatusLastRefreshAttemptAt) or 0
        return lastAttemptAt > 0 and (now - lastAttemptAt) < VERSION_STATUS_RETRY_SECONDS
    end

    local function shouldStartVersionCatalogCacheRefresh(cache, now)
        if isVersionManagerCacheEmpty(cache) then
            return true
        end

        local status = string.lower(trim(cache.status or ''))
        local latestVersion = trim(cache.latestVersion or '')
        local latestComparable = parseComparableVersion(latestVersion)
        local age = cacheAgeSeconds(cache, now)

        if status == 'ready' and (latestVersion == '' or not latestComparable) then
            return true
        end
        if status == 'error' then
            return age == nil or age >= VERSION_STATUS_RETRY_SECONDS
        end
        if latestVersion == '' then
            return true
        end
        if age == nil then
            return true
        end
        return age >= VERSION_STATUS_AUTO_REFRESH_SECONDS
    end

    local function maybeStartVersionCatalogCacheRefresh(cache, now)
        if isVersionCatalogCacheRefreshRunning(now) or isVersionCatalogRefreshAttemptOnCooldown(now) then
            return
        end
        if not shouldStartVersionCatalogCacheRefresh(cache, now) then
            return
        end

        state.versionStatusLastRefreshAttemptAt = now
        if methods.startVersionCatalogHelper then
            local started = methods.startVersionCatalogHelper()
            if started then
                state.versionStatusRefreshRunning = true
                state.versionStatusRefreshStartedAt = now
            else
                logNotice('Version status auto refresh could not start.')
            end
        end
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
        maybeStartVersionCatalogCacheRefresh(cache, now)
        local comparison = compareVersions(currentVersion, cache.latestVersion)
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
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsVersionManagerLaunchWatchdog', 'Stop 1')
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsVersionManagerLaunchWatchdog', 'Execute 1')
        return token
    end

    function methods.clearVersionManagerLaunchPending(options)
        state.versionManagerLaunchPending = false
        state.versionManagerLaunchStartedAt = 0
        state.versionManagerLaunchToken = ''
        state.versionManagerLaunchLastStatus = ''
        state.versionManagerLaunchLastObservedToken = ''
        writeVersionManagerLaunchState('', '', '')
        if methods.setLoadingVisible then
            methods.setLoadingVisible(false)
        end
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsVersionManagerLaunchWatchdog', 'Stop 1')
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
            SKIN:Bang('!CommandMeasure', 'MeasureSettingsVersionManagerLaunchWatchdog', 'Stop 1')
            return
        end

        local now = nowWallClockSeconds()
        local startedAt = tonumber(state.versionManagerLaunchStartedAt) or 0
        if startedAt > 0 and (now - startedAt) >= VERSION_MANAGER_LAUNCH_TIMEOUT_SECONDS then
            logNotice('Version manager launch state timed out while waiting for the window to appear.')
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
            logNotice('Version manager launch state reported an error before the window was shown.')
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

    function methods.handleVersionCatalogCacheRefreshComplete()
        state.versionStatusRefreshRunning = false
        state.versionStatusRefreshStartedAt = 0
        invalidateVersionStatusCache()
        if methods.renderVersionStatusState then
            methods.renderVersionStatusState()
        end
        refreshVersionStatusAndLoadingVisuals()
    end

end
