return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local logNotice = app.logNotice
    local helperResult = app.helperResult
    local helpers = app.cacheHelpers or {}
    local normalizeStartupAutoRunOutput = helpers.normalizeStartupAutoRunOutput
    local parseStartupAutoRunResult = helpers.parseStartupAutoRunResult
    local defaultLoadingMessage = helpers.defaultLoadingMessage
    local showModalAlert = helpers.showModalAlert
    function methods.readPersistentCacheVariable(variableName, defaultValue)

        local resolved = trim(SKIN:GetVariable(tostring(variableName or ''), ''))

        if resolved == '' then

            return trim(defaultValue or '')

        end

        return resolved

    end

    function methods.writePersistentCacheVariable(variableName, value)

        local resolved = tostring(value or '')

        setVariable(variableName, resolved)

        SKIN:Bang('!WriteKeyValue', 'Variables', tostring(variableName or ''), resolved, methods.cachePath())

    end

    function methods.clearMemoryCaches()

        state.bundledFontFaceSet = nil

        state.bundledFontFaces = nil

        state.installedDriveTargets = nil

    end

    function methods.splitCachedList(rawValue)

        local values = {}

        local seen = {}

        for entry in tostring(rawValue or ''):gmatch('[^|]+') do

            local trimmedEntry = trim(entry)

            if trimmedEntry ~= '' and not seen[trimmedEntry] then

                values[#values + 1] = trimmedEntry

                seen[trimmedEntry] = true

            end

        end

        return values

    end

    function methods.joinCachedList(values)

        return table.concat(values or {}, '|')

    end

    function methods.cachedListHasEntries(values)

        return type(values) == 'table' and #values > 0

    end

    function methods.setBundledFontFaces(fontFaces)

        state.bundledFontFaces = {}

        state.bundledFontFaceSet = {}

        for _, fontName in ipairs(fontFaces or {}) do

            local trimmedName = trim(fontName)

            if trimmedName ~= '' and not state.bundledFontFaceSet[trimmedName] then

                state.bundledFontFaces[#state.bundledFontFaces + 1] = trimmedName

                state.bundledFontFaceSet[trimmedName] = true

            end

        end

        table.sort(state.bundledFontFaces)

    end

    function methods.setInstalledDriveTargetList(driveTargets)

        state.installedDriveTargets = {}

        local seen = {}

        for _, drive in ipairs(driveTargets or {}) do

            local normalized = string.upper(trim(drive):gsub('[\\/]+$', ''))

            if normalized ~= '' and not seen[normalized] then

                state.installedDriveTargets[#state.installedDriveTargets + 1] = normalized

                seen[normalized] = true

            end

        end

        table.sort(state.installedDriveTargets)

    end

    function methods.setLoadingVisible(visible, message)
        local defaultMessage = defaultLoadingMessage()

        setVariable('SettingsLoadingHidden', visible and '0' or '1')

        setVariable('SettingsLoadingText', defaultMessage)

        setVariable('SettingsLoadingDisplayText', visible and tostring(message or defaultMessage) or defaultMessage)

    end

    function methods.isLoadingVisible()

        return trim(SKIN:GetVariable('SettingsLoadingHidden', '1')) == '0'

    end

    function methods.resumePendingLoadIfNeeded()
        local loadKind = trim(state.pendingLoadKind or '')
        if loadKind == '' then
            return false
        end

        local message = trim(SKIN:GetVariable('SettingsLoadingDisplayText', ''))
        methods.setLoadingVisible(true, message ~= '' and message or nil)
        if state.pendingLoadHelperRunning == true then
            methods.SetUpdateJob('helperWatchdog', true)
        else
            methods.SetUpdateJob('deferredLoad', true)
        end
        return true
    end

    function methods.clearPendingRefreshState()

        state.pendingRefreshBatchIndex = 0

        state.pendingRefreshBatchTotal = 0

        state.pendingRefreshBatches = {}

        state.pendingRefreshOptions = nil

        state.pendingRefreshDelayTicksRemaining = 0

        if methods.CancelPendingLanguageSwitchInternal then
            methods.CancelPendingLanguageSwitchInternal()
        end

        setVariable('SettingsPendingRefreshBatchIndex', '0')

        setVariable('SettingsPendingRefreshBatchTotal', '0')

        methods.SetUpdateJob('deferredRefresh', false)

    end

    function methods.clearPendingLoadState(options)
        options = options or {}
        local abandonReason = trim(options.abandonActiveHelperReason or '')
        local clearIgnoredHelper = options.clearIgnoredHelper == true
        local ignoredHelperKind = trim(options.ignoredHelperKind or '')
        state.pendingLoadKind = nil
        state.pendingLoadFieldKey = nil
        state.pendingLoadRowIndex = 0
        state.pendingLoadDelayTicksRemaining = 0
        state.pendingLoadReopenDropdown = false
        state.pendingLoadValue = nil
        state.pendingLoadTexturePath = nil
        state.pendingLoadUsername = nil
        state.pendingLoadBeforeSnapshot = nil
        state.pendingLoadHistoryLabel = nil
        if abandonReason ~= '' then
            methods.rememberIgnoredPendingLoadHelperCompletion(abandonReason)
        else
            methods.clearPendingLoadHelperState()
        end
        if clearIgnoredHelper then
            methods.clearIgnoredPendingLoadHelperCompletion(ignoredHelperKind)
        end
        setVariable('SettingsPendingLoadKind', '')
        setVariable('SettingsPendingLoadFieldKey', '')
        setVariable('SettingsPendingLoadRowIndex', '0')
        methods.SetUpdateJob('deferredLoad', false)
    end
    function methods.clearPendingLoadHelperState()
        state.pendingLoadHelperRunning = false
        state.pendingLoadHelperKind = nil
        state.pendingLoadHelperMeasureName = nil
        state.pendingLoadHelperLoadKind = nil
        state.pendingLoadHelperStartedAt = 0
        state.pendingLoadHelperDeadlineAt = 0
        state.pendingLoadHelperTimeoutSeconds = 0
        methods.SetUpdateJob('helperWatchdog', false)
    end
    function methods.getIgnoredPendingLoadHelperCompletion(helperKind)
        local resolvedKind = trim(helperKind or '')
        if resolvedKind == '' then
            return nil
        end
        if type(state.ignoredPendingLoadHelpers) ~= 'table' then
            state.ignoredPendingLoadHelpers = {}
            return nil
        end
        local entry = state.ignoredPendingLoadHelpers[resolvedKind]
        if type(entry) ~= 'table' then
            return nil
        end
        return entry
    end
    function methods.clearIgnoredPendingLoadHelperCompletion(helperKind)
        local resolvedKind = trim(helperKind or '')
        if type(state.ignoredPendingLoadHelpers) ~= 'table' then
            state.ignoredPendingLoadHelpers = {}
            return
        end
        if resolvedKind == '' then
            state.ignoredPendingLoadHelpers = {}
            return
        end
        state.ignoredPendingLoadHelpers[resolvedKind] = nil
    end
    function methods.rememberIgnoredPendingLoadHelperCompletion(reason)
        local helperKind = trim(state.pendingLoadHelperKind or '')
        local measureName = trim(state.pendingLoadHelperMeasureName or '')
        if helperKind == '' or measureName == '' then
            methods.clearPendingLoadHelperState()
            return false
        end
        if type(state.ignoredPendingLoadHelpers) ~= 'table' then
            state.ignoredPendingLoadHelpers = {}
        end
        local protectedUntil = 0
        local now = os.time()
        if type(now) == 'number' and now > 0 then
            protectedUntil = now + 15
        end
        state.ignoredPendingLoadHelpers[helperKind] = {
            measureName = measureName,
            loadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or ''),
            reason = trim(reason or ''),
            protectedUntil = protectedUntil,
        }
        methods.clearPendingLoadHelperState()
        return true
    end
    function methods.handlePendingLoadHelperTimeout()
        local loadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or '')
        local timeoutSeconds = tonumber(state.pendingLoadHelperTimeoutSeconds) or 0
        local helperKind = trim(state.pendingLoadHelperKind or '')
        local helperMeasureName = trim(state.pendingLoadHelperMeasureName or '')
        local helperReason = 'watchdog-timeout'
        if timeoutSeconds > 0 then
            helperReason = helperReason .. ':' .. tostring(timeoutSeconds)
        end
        methods.clearPendingLoadState({
            abandonActiveHelperReason = helperReason,
            clearIgnoredHelper = false,
        })
        if helperMeasureName ~= '' and SKIN:GetMeasure(helperMeasureName) then
            SKIN:Bang('!CommandMeasure', helperMeasureName, 'Kill')
        end
        methods.clearPendingRefreshState()
        if methods.CancelPendingLanguageSwitchInternal then
            methods.CancelPendingLanguageSwitchInternal()
        end

        methods.setLoadingVisible(false)
        logNotice('Settings helper timed out: loadKind=' .. tostring(loadKind) .. ' helperKind=' .. tostring(helperKind) .. ' timeoutSeconds=' .. tostring(timeoutSeconds))
        local shouldAlertTimeout = loadKind == 'minecraftSkinApply'
            or loadKind == 'minecraftSkinFileAttach'
            or loadKind == 'startupAutoRunApply'
            or (loadKind == 'computerInfo' and state.pendingLoadFieldKey == 'refreshComputerInfo')
        if methods.ShowModalAlertByKeys and shouldAlertTimeout then
            methods.ShowModalAlertByKeys(
                'warn',
                'ModalAlert_HelperTimeout',
                'The requested task did not finish in time, so the wait was canceled. Try again shortly.'
            )
        end
        methods.renderActivePage()
    end
    function methods.checkPendingLoadHelperWatchdog()
        if state.pendingLoadHelperRunning ~= true then
            return false
        end
        local deadlineAt = tonumber(state.pendingLoadHelperDeadlineAt) or 0
        if deadlineAt <= 0 then
            return false
        end
        local now = os.time()
        if type(now) ~= 'number' or now < deadlineAt then
            return false
        end
        methods.handlePendingLoadHelperTimeout()
        return true
    end
    function methods.handleIgnoredPendingLoadHelperCompletion(helperKind)
        local entry = methods.getIgnoredPendingLoadHelperCompletion(helperKind)
        if not entry then
            return false
        end
        local measureName = trim(entry.measureName or '')
        local loadKind = trim(entry.loadKind or '')
        local reason = trim(entry.reason or '')
        local values = {}
        if measureName ~= '' then
            values = methods.parseCommandCaptureVariables(methods.runCommandMeasureOutput(measureName))
        end
        local status = string.upper(trim(values.DMEL_STATUS or ''))
        logNotice(
            'Ignored late helper completion: loadKind='
                .. tostring(loadKind)
                .. ' helperKind='
                .. tostring(helperKind or '')
                .. ' reason='
                .. tostring(reason ~= '' and reason or 'not-tracked')
                .. ' status='
                .. tostring(status))
        methods.clearIgnoredPendingLoadHelperCompletion(helperKind)
        return true
    end
    function methods.runCommandMeasureOutput(measureName)

        local measure = SKIN:GetMeasure(tostring(measureName or ''))

        if not measure then

            logNotice('Settings helper result measure is missing: ' .. tostring(measureName or ''))

            return ''

        end

        return tostring(measure:GetStringValue() or '')

    end
end
