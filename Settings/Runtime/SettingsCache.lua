return function(app)

    local state = app.state

    local schema = app.schema

    local methods = app.methods

    local trim = app.trim

    local setVariable = app.setVariable

    local logNotice = app.logNotice

    local function normalizeStartupAutoRunOutput(raw)
        local normalized = tostring(raw or ''):gsub('%z', '')
        normalized = normalized:gsub('^\239\187\191', '')
        return normalized
    end

    local function parseStartupAutoRunResult(raw, fallback)
        local normalized = normalizeStartupAutoRunOutput(raw)
        local values = methods.parseCommandCaptureVariables(normalized)
        local literal = trim(values.DMEL_VALUE or '')
        if literal ~= '0' and literal ~= '1' then
            literal = ''
            for line in normalized:gmatch('[^\r\n]+') do
                local candidate = trim(line):gsub('^\239\187\191', '')
                if candidate == '0' or candidate == '1' then
                    literal = candidate
                end
            end
        end

        local status = string.upper(trim(values.DMEL_STATUS or ''))
        if status == '' and literal ~= '' then
            status = 'OK'
        end

        return {
            status = status,
            literal = literal ~= '' and literal or methods.normalizeToggleValue(fallback),
            hasLiteral = literal == '0' or literal == '1',
            code = trim(values.DMEL_CODE or ''),
            message = trim(values.DMEL_MESSAGE or ''),
            normalizedOutput = normalized,
        }
    end

    local function defaultLoadingMessage()
        return methods.localize('Settings_Loading', 'Loading...\\nPlease wait.')
    end

    local function showModalAlert(level, summaryKey, fallback, logPath)
        if not methods.ShowModalAlertByKeys then
            return false
        end
        return methods.ShowModalAlertByKeys(level, summaryKey, fallback, logPath)
    end



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

        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredRefresh', 'Stop 1')

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
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLoad', 'Stop 1')
    end
    function methods.clearPendingLoadHelperState()
        state.pendingLoadHelperRunning = false
        state.pendingLoadHelperKind = nil
        state.pendingLoadHelperMeasureName = nil
        state.pendingLoadHelperLoadKind = nil
        state.pendingLoadHelperStartedAt = 0
        state.pendingLoadHelperDeadlineAt = 0
        state.pendingLoadHelperTimeoutSeconds = 0
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsHelperWatchdog', 'Stop 1')
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
        local helperReason = 'watchdog-timeout'
        if timeoutSeconds > 0 then
            helperReason = helperReason .. ':' .. tostring(timeoutSeconds)
        end
        methods.clearPendingLoadState({
            abandonActiveHelperReason = helperReason,
            clearIgnoredHelper = false,
        })
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



    function methods.startRunCommandHelper(helperKind, measureName, argsVariableName, args, options)
        options = options or {}
        local loadKind = trim(options.loadKind or state.pendingLoadKind or '')
        local shouldAlertStartFailure = loadKind == 'minecraftSkinApply'
            or loadKind == 'minecraftSkinFileAttach'
            or loadKind == 'startupAutoRunApply'
            or (loadKind == 'computerInfo' and state.pendingLoadFieldKey == 'refreshComputerInfo')
        local ignoredPendingHelper = methods.getIgnoredPendingLoadHelperCompletion(helperKind)
        if ignoredPendingHelper then
            logNotice('Settings helper start blocked while a previous helper completion is still pending cleanup: ' .. tostring(helperKind or ''))
            if methods.ShowModalAlertByKeys and shouldAlertStartFailure then
                methods.ShowModalAlertByKeys(
                    'warn',
                    'ModalAlert_HelperBusy',
                    'The previous task is still cleaning up, so the request cannot start again now. Try again shortly.'
                )
            end
            return false
        end
        if not SKIN:GetMeasure(tostring(measureName or '')) then
            logNotice('Settings helper run measure is missing: ' .. tostring(measureName or ''))
            if methods.ShowModalAlertByKeys and shouldAlertStartFailure then
                methods.ShowModalAlertByKeys(
                    'error',
                    'ModalAlert_HelperStartFailed',
                    'The requested task could not be started. Refresh the skin and try again.'
                )
            end
            return false
        end
        methods.clearPendingLoadHelperState()
        local timeoutSeconds = math.max(0, tonumber(options.timeoutSeconds) or 0)
        local startedAt = os.time()
        state.pendingLoadHelperRunning = true
        state.pendingLoadHelperKind = tostring(helperKind or '')
        state.pendingLoadHelperMeasureName = tostring(measureName or '')
        state.pendingLoadHelperLoadKind = loadKind
        state.pendingLoadHelperTimeoutSeconds = timeoutSeconds
        if type(startedAt) == 'number' and startedAt > 0 and timeoutSeconds > 0 then
            state.pendingLoadHelperStartedAt = startedAt
            state.pendingLoadHelperDeadlineAt = startedAt + timeoutSeconds
            SKIN:Bang('!CommandMeasure', 'MeasureSettingsHelperWatchdog', 'Stop 1')
            SKIN:Bang('!CommandMeasure', 'MeasureSettingsHelperWatchdog', 'Execute 1')
        else
            state.pendingLoadHelperStartedAt = 0
            state.pendingLoadHelperDeadlineAt = 0
            SKIN:Bang('!CommandMeasure', 'MeasureSettingsHelperWatchdog', 'Stop 1')
        end
        setVariable(argsVariableName, tostring(args or ''))
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLoad', 'Stop 1')
        SKIN:Bang('!UpdateMeasure', measureName)
        SKIN:Bang('!CommandMeasure', measureName, 'Run')
        return true
    end
    function methods.clearDetachedHelperState(helperKind)
        state.detachedHelperMeasures = state.detachedHelperMeasures or {}
        local resolvedKind = trim(helperKind or '')
        if resolvedKind ~= '' then
            state.detachedHelperMeasures[resolvedKind] = nil
        else
            state.detachedHelperMeasures = {}
        end

        local latestKind = ''
        local latestMeasureName = ''
        for activeKind, activeMeasureName in pairs(state.detachedHelperMeasures) do
            latestKind = tostring(activeKind or '')
            latestMeasureName = tostring(activeMeasureName or '')
            break
        end

        state.detachedHelperRunning = next(state.detachedHelperMeasures) ~= nil
        state.detachedHelperKind = latestKind
        state.detachedHelperMeasureName = latestMeasureName
    end

    function methods.startDetachedRunCommandHelper(helperKind, measureName, argsVariableName, args)
        if not SKIN:GetMeasure(tostring(measureName or '')) then
            logNotice('Settings detached helper run measure is missing: ' .. tostring(measureName or ''))
            if methods.ShowModalAlertByKeys and trim(helperKind or '') == 'openLogFolder' then
                methods.ShowModalAlertByKeys(
                    'error',
                    'ModalAlert_OpenLogFailed',
                    'The log folder could not be opened. Check whether File Explorer is working normally.'
                )
            end
            return false
        end

        local resolvedKind = trim(helperKind or '')
        local resolvedMeasureName = tostring(measureName or '')
        state.detachedHelperMeasures = state.detachedHelperMeasures or {}
        state.detachedHelperMeasures[resolvedKind] = resolvedMeasureName
        state.detachedHelperRunning = true
        state.detachedHelperKind = resolvedKind
        state.detachedHelperMeasureName = resolvedMeasureName
        setVariable(argsVariableName, tostring(args or ''))
        SKIN:Bang('!UpdateMeasure', measureName)
        SKIN:Bang('!CommandMeasure', measureName, 'Run')
        return true
    end

    function methods.parseCommandCaptureVariables(raw)

        local values = {}

        for line in tostring(raw or ''):gmatch('[^\r\n]+') do

            local normalizedLine = tostring(line or '')
            normalizedLine = normalizedLine:gsub('^\239\187\191', '')
            normalizedLine = normalizedLine:match('^%s*(.-)%s*$') or ''

            local key, value = normalizedLine:match('^([A-Z_]+)=(.*)$')

            if key then

                values[key] = trim(value)

            end

        end

        return values

    end


    function methods.computerInfoHelperScriptPath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'LoadComputerInfo.ps1'

    end



    function methods.computerInfoHelperArguments(options)

        options = options or {}

        local command = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '

            .. methods.escapeCommandArgument(methods.computerInfoHelperScriptPath())



        if options.includeFonts then

            command = command .. ' -IncludeFonts -FontsPath ' .. methods.escapeCommandArgument(methods.resourceFontsPath())

        end



        if options.includeDrives then

            command = command .. ' -IncludeDrives'

        end



        if options.includeStartupAutoRun then

            command = command .. ' -IncludeStartupAutoRun'

        end



        return command

    end



    function methods.runComputerInfoHelper(options)

        logNotice('Settings computer info helper was requested through the legacy synchronous path; using cache fallback.')

        return {}

    end


    function methods.startComputerInfoHelper(options)

        return methods.startRunCommandHelper(

            'computerInfo',

            'MeasureSettingsComputerInfoRun',

            'SettingsComputerInfoHelperArgs',

            methods.computerInfoHelperArguments(options)

        )

    end



    function methods.applyComputerInfoStartupAutoRunLiteral(literal)

        local field = methods.getField('startupAutoRun')

        if not field then

            return '0'

        end



        local currentLiteral = methods.normalizeToggleValue(methods.readFieldValue(field))

        local helperLiteral = trim(literal)

        if helperLiteral ~= '0' and helperLiteral ~= '1' then

            return currentLiteral

        end

        local actualLiteral = methods.normalizeToggleValue(helperLiteral)

        methods.persistStartupAutoRunCache(actualLiteral)

        methods.setFieldSessionValue(field, actualLiteral)

        methods.persistStartupAutoRunSetting(actualLiteral, { currentLiteral = currentLiteral })

        return actualLiteral

    end

    function methods.minecraftSkinFetchArguments(username, model)
        local resolvedModel = 'wide'
        if methods.normalizeMinecraftSkinModelInput then
            resolvedModel = methods.normalizeMinecraftSkinModelInput(model)
        elseif string.lower(trim(model)) == 'slim' then
            resolvedModel = 'slim'
        end

        return '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File '

            .. methods.escapeCommandArgument(methods.fetchMinecraftSkinScriptPath())

            .. ' -Username '

            .. methods.escapeCommandArgument(trim(username))

            .. ' -OutputDirectory '

            .. methods.escapeCommandArgument(methods.playerSkinImageDirectoryPath())

            .. ' -Model '

            .. methods.escapeCommandArgument(resolvedModel)

            .. ' -TimeoutSeconds 12'

    end

    function methods.startMinecraftSkinFetch(username, model, loadKind)

        return methods.startRunCommandHelper(

            'minecraftSkin',

            'MeasureSettingsMinecraftSkinRun',

            'SettingsMinecraftSkinHelperArgs',

            methods.minecraftSkinFetchArguments(username, model),
            {
                loadKind = trim(loadKind or '') ~= '' and trim(loadKind or '') or 'minecraftSkinApply',
                timeoutSeconds = 25,
            }

        )

    end

    function methods.minecraftSkinFilePickerScriptPath()
        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'PickMinecraftSkinFile.ps1'
    end

    function methods.minecraftSkinFilePickerArguments(model, sourcePath, username, options)
        options = options or {}
        local resolvedModel = 'wide'
        if methods.normalizeMinecraftSkinModelInput then
            resolvedModel = methods.normalizeMinecraftSkinModelInput(model)
        elseif string.lower(trim(model)) == 'slim' then
            resolvedModel = 'slim'
        end

        local command = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument(methods.minecraftSkinFilePickerScriptPath())
            .. ' -OutputDirectory '
            .. methods.escapeCommandArgument(methods.playerSkinImageDirectoryPath())
            .. ' -Model '
            .. methods.escapeCommandArgument(resolvedModel)
        if trim(sourcePath or '') ~= '' then
            command = command
                .. ' -SourcePath '
                .. methods.escapeCommandArgument(trim(sourcePath))
        end
        if trim(username or '') ~= '' then
            command = command
                .. ' -Username '
                .. methods.escapeCommandArgument(trim(username))
        end
        if trim(options.initialDirectory or '') ~= '' then
            command = command
                .. ' -InitialDirectory '
                .. methods.escapeCommandArgument(trim(options.initialDirectory))
        end
        if options.acceptRenderedBody == true then
            command = command .. ' -AcceptRenderedBody'
        end
        return command
    end

    function methods.startMinecraftSkinFilePicker(model, sourcePath, username, loadKind, options)
        return methods.startRunCommandHelper(
            'minecraftSkinFile',
            'MeasureSettingsMinecraftSkinFileRun',
            'SettingsMinecraftSkinFileHelperArgs',
            methods.minecraftSkinFilePickerArguments(model, sourcePath, username, options),
            {
                loadKind = trim(loadKind or '') ~= '' and trim(loadKind or '') or 'minecraftSkinFileAttach',
                timeoutSeconds = trim(sourcePath or '') ~= '' and 25 or 120,
            }
        )
    end

    function methods.startupAutoRunHelperArguments(mode)

        return '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '

            .. methods.escapeCommandArgument('.\\StartupAutoRun.ps1')

            .. ' -Mode '

            .. tostring(mode or 'probe')

    end

    function methods.startStartupAutoRunHelper(desiredLiteral)

        local mode = desiredLiteral == nil and 'probe' or (methods.normalizeToggleValue(desiredLiteral) == '1' and 'enable' or 'disable')

        local args = methods.startupAutoRunHelperArguments(mode)

        return methods.startRunCommandHelper(

            'startupAutoRun',

            'MeasureSettingsStartupAutoRun',

            'SettingsStartupAutoRunHelperArgs',

            args

        )

    end


    function methods.settingsSkinRootPath()

        local currentPath = trim(SKIN:GetVariable('CURRENTPATH', ''))

        currentPath = currentPath:gsub('[\\/]+$', '')

        return currentPath:match('^(.*)[\\/][^\\/]+$') or currentPath

    end

    function methods.openVersionManagerScriptPath()
        return methods.settingsSkinRootPath() .. '\\tools\\OpenVersionManager.ps1'
    end

    function methods.versionCatalogScriptPath()
        return methods.settingsSkinRootPath() .. '\\tools\\GetVersionReleaseCatalog.ps1'
    end

    function methods.versionCatalogHelperArguments()
        return '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument(methods.versionCatalogScriptPath())
            .. ' -CurrentTargetRoot '
            .. methods.escapeCommandArgument(methods.settingsSkinRootPath())
            .. ' -NonInteractive -EmitResultPairs -SyncUpdateCache'
    end

    function methods.startVersionCatalogHelper()
        return methods.startDetachedRunCommandHelper(
            'versionCatalog',
            'MeasureSettingsVersionCatalogRun',
            'SettingsVersionCatalogHelperArgs',
            methods.versionCatalogHelperArguments()
        )
    end

    function methods.openVersionManagerHelperArguments(launchToken)
        return '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument(methods.openVersionManagerScriptPath())
            .. ' -TargetRoot '
            .. methods.escapeCommandArgument(methods.settingsSkinRootPath())
            .. ' -LaunchToken '
            .. methods.escapeCommandArgument(trim(launchToken or ''))
            .. ' -EmitResultPairs'
    end

    function methods.startOpenVersionManagerHelper()
        if methods.isVersionManagerLaunchPending and methods.isVersionManagerLaunchPending() then
            logNotice('Version manager launch request ignored because the previous launch is still pending.')
            return false
        end

        local launchToken = ''
        if methods.beginVersionManagerLaunchPending then
            launchToken = methods.beginVersionManagerLaunchPending()
            methods.renderActivePage()
        end

        local started = methods.startDetachedRunCommandHelper(
            'openVersionManager',
            'MeasureSettingsOpenVersionManagerRun',
            'SettingsOpenVersionManagerHelperArgs',
            methods.openVersionManagerHelperArguments(launchToken)
        )
        if not started and methods.clearVersionManagerLaunchPending then
            methods.clearVersionManagerLaunchPending()
            showModalAlert(
                'error',
                'ModalAlert_VersionManagerFailed',
                'Skins could not be opened from Settings. Refresh the skin and try again.'
            )
        end
        return started
    end
    function methods.openLogFolderScriptPath()
        return methods.settingsSkinRootPath() .. '\\tools\\OpenSettingsLogFolder.ps1'
    end

    function methods.openLogFolderHelperArguments()
        return '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument(methods.openLogFolderScriptPath())
            .. ' -TargetRoot '
            .. methods.escapeCommandArgument(methods.settingsSkinRootPath())
            .. ' -EmitResultPairs'
    end

    function methods.startOpenLogFolderHelper()
        return methods.startDetachedRunCommandHelper(
            'openLogFolder',
            'MeasureSettingsOpenLogFolderRun',
            'SettingsOpenLogFolderHelperArgs',
            methods.openLogFolderHelperArguments()
        )
    end

    function methods.defaultDriveTargets(field)

        local drives = {}

        local currentTarget = trim(methods.currentDiskTargetForField(field))

        if currentTarget ~= '' then

            drives[#drives + 1] = currentTarget

        end

        if #drives == 0 then

            local expTargetField = methods.getField('expDiskTarget')

            local expTarget = expTargetField and trim(methods.readFieldValue(expTargetField)) or ''

            if expTarget ~= '' then

                drives[#drives + 1] = expTarget

            end

        end

        if #drives == 0 then

            drives[#drives + 1] = 'C:'

        end

        return drives

    end



    function methods.loadInstalledDriveTargets(field)

        local hadDriveTargets = methods.cachedListHasEntries(state.installedDriveTargets)

        local values = methods.runComputerInfoHelper({ includeDrives = true, tag = 'drives' })

        local drives = methods.splitCachedList(values.DMEL_DRIVETARGETS or '')

        if #drives > 0 then

            methods.setInstalledDriveTargetList(drives)

            return state.installedDriveTargets or {}

        end

        if hadDriveTargets then

            return state.installedDriveTargets or {}

        end

        if methods.RestorePersistentCache('driveTargets') then

            return state.installedDriveTargets or {}

        end

        methods.setInstalledDriveTargetList(methods.defaultDriveTargets(field))

        return state.installedDriveTargets or {}

    end



    function methods.resourceFontsPath()

        methods.ensurePaths()

        return state.resourcesRoot .. 'Fonts'

    end



    function methods.loadBundledFontFaces(field)

        local hadBundledFonts = methods.cachedListHasEntries(state.bundledFontFaces)

        local values = methods.runComputerInfoHelper({ includeFonts = true, tag = 'fonts' })

        local fontFaces = methods.splitCachedList(values.DMEL_FONTFAMILIES or '')

        if #fontFaces > 0 then

            methods.setBundledFontFaces(fontFaces)

            return state.bundledFontFaceSet or {}

        end

        if hadBundledFonts then

            return state.bundledFontFaceSet or {}

        end

        if methods.RestorePersistentCache('fontFamily') then

            return state.bundledFontFaceSet or {}

        end

        methods.setBundledFontFaces({})

        return state.bundledFontFaceSet or {}

    end



    function methods.loadComputerInfoCaches(driveField)

        local values = methods.runComputerInfoHelper({

            includeFonts = true,

            includeDrives = true,

            includeStartupAutoRun = true,

            tag = 'computer_info',

        })

        local fontFaces = methods.splitCachedList(values.DMEL_FONTFAMILIES or '')

        if #fontFaces > 0 then

            methods.setBundledFontFaces(fontFaces)

        elseif not methods.cachedListHasEntries(state.bundledFontFaces) and not methods.RestorePersistentCache('fontFamily') then

            methods.setBundledFontFaces({})

        end



        local drives = methods.splitCachedList(values.DMEL_DRIVETARGETS or '')

        if #drives > 0 then

            methods.setInstalledDriveTargetList(drives)

        elseif not methods.cachedListHasEntries(state.installedDriveTargets) and not methods.RestorePersistentCache('driveTargets') then

            methods.setInstalledDriveTargetList(methods.defaultDriveTargets(driveField))

        end

        methods.applyComputerInfoStartupAutoRunLiteral(values.DMEL_STARTUPAUTORUN or '')

        return values

    end



    function methods.persistPersistentCache(kind)

        if kind == 'fontFamily' then

            methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)

            methods.writePersistentCacheVariable('SettingsPersistentCacheFontsLoaded', methods.cachedListHasEntries(state.bundledFontFaces) and '1' or '0')

            methods.writePersistentCacheVariable('SettingsPersistentCacheFontFamilies', methods.joinCachedList(state.bundledFontFaces or {}))

            return

        end



        if kind == 'driveTargets' then

            methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)

            methods.writePersistentCacheVariable('SettingsPersistentCacheDrivesLoaded', methods.cachedListHasEntries(state.installedDriveTargets) and '1' or '0')

            methods.writePersistentCacheVariable('SettingsPersistentCacheDriveTargets', methods.joinCachedList(state.installedDriveTargets or {}))

            return

        end



        if kind == 'computerInfo' then

            methods.persistPersistentCache('fontFamily')

            methods.persistPersistentCache('driveTargets')

        end

    end



    function methods.RestorePersistentCache(kind)

        local version = methods.readPersistentCacheVariable('SettingsPersistentCacheFormatVersion', '')

        if version ~= state.cacheFormatVersion then

            return false

        end



        if kind == 'fontFamily' then

            if methods.readPersistentCacheVariable('SettingsPersistentCacheFontsLoaded', '0') ~= '1' then

                return false

            end

            methods.setBundledFontFaces(methods.splitCachedList(methods.readPersistentCacheVariable('SettingsPersistentCacheFontFamilies', '')))

            return state.bundledFontFaces ~= nil and #state.bundledFontFaces > 0

        end



        if kind == 'driveTargets' then

            if methods.readPersistentCacheVariable('SettingsPersistentCacheDrivesLoaded', '0') ~= '1' then

                return false

            end

            methods.setInstalledDriveTargetList(methods.splitCachedList(methods.readPersistentCacheVariable('SettingsPersistentCacheDriveTargets', '')))

            return state.installedDriveTargets ~= nil and #state.installedDriveTargets > 0

        end



        if kind == 'computerInfo' then

            if not methods.RestorePersistentCache('fontFamily') then

                return false

            end

            if not methods.RestorePersistentCache('driveTargets') then

                return false

            end

            return methods.startupAutoRunCacheInitialized()

        end



        return false

    end



    function methods.ScheduleDropdownDataLoad(fieldKey, rowIndex, forcedKind, reopenAfterLoad, options)

        options = options or {}

        local field = methods.getField(fieldKey)

        if not field then

            return

        end

        if not forcedKind and not methods.hasDropdown(field) then

            return

        end



        local kind = forcedKind or (field.dropdownId == 'fontFamily' and 'fontFamily' or 'driveTargets')

        methods.closeDropdownInternal()

        methods.clearPendingLoadState()

        state.pendingLoadKind = kind

        state.pendingLoadFieldKey = fieldKey

        state.pendingLoadRowIndex = tonumber(rowIndex) or 0

        state.pendingLoadDelayTicksRemaining = math.max(0, tonumber(options.delayTicks) or 1)

        state.pendingLoadReopenDropdown = reopenAfterLoad ~= false

        state.pendingLoadValue = options.pendingValue
        state.pendingLoadTexturePath = options.pendingTexturePath
        state.pendingLoadUsername = options.pendingUsername

        state.pendingLoadBeforeSnapshot = options.beforeSnapshot

        state.pendingLoadHistoryLabel = options.historyLabel

        setVariable('SettingsPendingLoadKind', kind)

        setVariable('SettingsPendingLoadFieldKey', fieldKey)

        setVariable('SettingsPendingLoadRowIndex', tostring(state.pendingLoadRowIndex))

        methods.setLoadingVisible(true, options.loadingText)

        methods.renderActivePage()

        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLoad', 'Stop 1')
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsDeferredLoad', 'Execute 1')

    end



    function methods.CancelPendingLoad()

        if state.pendingLoadHelperRunning == true then
            local activeLoadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or '')
            methods.clearPendingLoadState({
                abandonActiveHelperReason = 'canceled',
                clearIgnoredHelper = false,
            })
        else
            methods.clearPendingLoadState()
        end

        methods.setLoadingVisible(false)

        methods.renderActivePage()

        return true

    end

    function methods.applyInstalledDriveTargetsFromValues(field, values)

        local hadDriveTargets = methods.cachedListHasEntries(state.installedDriveTargets)

        local drives = methods.splitCachedList(values.DMEL_DRIVETARGETS or '')

        if #drives > 0 then

            methods.setInstalledDriveTargetList(drives)

            return state.installedDriveTargets or {}

        end

        if hadDriveTargets then

            return state.installedDriveTargets or {}

        end

        if methods.RestorePersistentCache('driveTargets') then

            return state.installedDriveTargets or {}

        end

        methods.setInstalledDriveTargetList(methods.defaultDriveTargets(field))

        return state.installedDriveTargets or {}

    end



    function methods.applyBundledFontFacesFromValues(field, values)

        local hadBundledFonts = methods.cachedListHasEntries(state.bundledFontFaces)

        local fontFaces = methods.splitCachedList(values.DMEL_FONTFAMILIES or '')

        if #fontFaces > 0 then

            methods.setBundledFontFaces(fontFaces)

            return state.bundledFontFaceSet or {}

        end

        if hadBundledFonts then

            return state.bundledFontFaceSet or {}

        end

        if methods.RestorePersistentCache('fontFamily') then

            return state.bundledFontFaceSet or {}

        end

        methods.setBundledFontFaces({})

        return state.bundledFontFaceSet or {}

    end



    function methods.applyComputerInfoCachesFromValues(driveField, values)

        methods.applyBundledFontFacesFromValues(nil, values)

        methods.applyInstalledDriveTargetsFromValues(driveField, values)

        methods.applyComputerInfoStartupAutoRunLiteral(values.DMEL_STARTUPAUTORUN or '')

        return values

    end



    function methods.applyStartupAutoRunProbeOutput(output)

        local field = methods.getField('startupAutoRun')

        if not field then

            return '0'

        end

        local currentLiteral = methods.normalizeToggleValue(methods.readFieldValue(field))

        local result = parseStartupAutoRunResult(output, currentLiteral)
        local actualLiteral = methods.normalizeToggleValue(result.literal)

        methods.persistStartupAutoRunCache(actualLiteral)

        methods.setFieldSessionValue(field, actualLiteral)

        methods.persistStartupAutoRunSetting(actualLiteral, { currentLiteral = currentLiteral })

        return actualLiteral

    end



    function methods.applyStartupAutoRunApplyOutput(output, field)

        local previousLiteral = field and methods.readFieldValue(field) or '0'
        local result = parseStartupAutoRunResult(output, previousLiteral)
        local succeeded = result.status == 'OK' and result.hasLiteral
        local actualLiteral = methods.normalizeToggleValue(result.literal)

        if not succeeded then
            logNotice(
                'Startup auto-run helper failed: status='
                    .. result.status
                    .. ' code='
                    .. result.code
                    .. ' hasLiteral='
                    .. tostring(result.hasLiteral)
            )
            if methods.ShowModalAlertByKeys then
                methods.ShowModalAlertByKeys(
                    'error',
                    'ModalAlert_StartupAutoRunFailed',
                    'The startup-program setting result could not be confirmed. The setting may not have been applied.'
                )
            end
        end

        methods.persistStartupAutoRunCache(actualLiteral)

        if field then

            methods.setFieldSessionValue(field, actualLiteral)

        end

        methods.persistStartupAutoRunSetting(actualLiteral, { force = true, currentLiteral = previousLiteral })

        if succeeded and state.pendingLoadBeforeSnapshot and field then

            methods.pushHistory(state.pendingLoadHistoryLabel or field.historyLabel, state.pendingLoadBeforeSnapshot, {

                afterSnapshot = methods.captureSnapshot(),

            })

        end

        return actualLiteral

    end



    function methods.applyMinecraftSkinFetchResult(result)

        local canonicalField = methods.getField('minecraftSkinUsername')

        local status = result and result.status or ''

        local resolvedImagePath = trim(result and result.imagePath or '')
        local resolvedTexturePath = trim(result and result.texturePath or '')
        local resolvedModel = ''
        if result and result.model ~= nil then
            if methods.normalizeMinecraftSkinModelInput then
                resolvedModel = methods.normalizeMinecraftSkinModelInput(result.model)
            elseif string.lower(trim(result.model)) == 'slim' then
                resolvedModel = 'slim'
            else
                resolvedModel = 'wide'
            end
        end

        methods.appendMinecraftSkinDebugLog('applyMinecraftSkinFetchResult status=' .. tostring(status) .. ' username=' .. tostring(result and result.username or '') .. ' imagePath=' .. tostring(resolvedImagePath) .. ' texturePath=' .. tostring(resolvedTexturePath) .. ' model=' .. tostring(resolvedModel) .. ' message=' .. tostring(result and result.message or ''))

        if status == 'OK' and canonicalField then


            local targetSet = {}

            methods.applyFieldValue(canonicalField, result.username, { targetSet = targetSet })
            if resolvedModel ~= '' then
                local modelField = methods.getField('minecraftSkinModel')
                if modelField then
                    methods.applyFieldValue(modelField, resolvedModel, { targetSet = targetSet })
                else
                    methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinModel', resolvedModel)
                end
            end

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', resolvedImagePath)

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', '1')
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', resolvedTexturePath)

            if methods.syncInventoryPlayerSkinLiveState then

                methods.syncInventoryPlayerSkinLiveState(result.username, resolvedImagePath, targetSet, { verified = true })

            end

            methods.refreshTargets(targetSet)

            methods.rememberMinecraftSkinHistory(result.username)

            if state.pendingLoadBeforeSnapshot then

                methods.pushHistory(state.pendingLoadHistoryLabel or canonicalField.historyLabel, state.pendingLoadBeforeSnapshot, {

                    afterSnapshot = methods.captureSnapshot(),

                })

            end

        elseif status == 'RESET' and canonicalField then


            local targetSet = {}

            methods.applyFieldValue(canonicalField, '', { targetSet = targetSet })

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', '')

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', '0')
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', '')

            if methods.syncInventoryPlayerSkinLiveState then

                methods.syncInventoryPlayerSkinLiveState('', '', targetSet)

            end

            methods.refreshTargets(targetSet)

            if state.pendingLoadBeforeSnapshot then

                methods.pushHistory(state.pendingLoadHistoryLabel or canonicalField.historyLabel, state.pendingLoadBeforeSnapshot, {

                    afterSnapshot = methods.captureSnapshot(),

                })

            end

        else

            local errorMessage = result and result.message or ''
            local modalErrorMessage = errorMessage
            local modalSummaryKey = ''

            if errorMessage == '' then

                errorMessage = methods.localize('Settings_Notice_MinecraftFailed', 'The Minecraft skin could not be loaded. Check the log folder for details.')
                modalErrorMessage = methods.localize('ModalAlert_MinecraftFailed', 'The Minecraft skin could not be loaded. Check the username and try again.')
                modalSummaryKey = 'ModalAlert_MinecraftFailed'

            end

            methods.syncMinecraftSkinDraftFromCanonical()


            logNotice(methods.localizeFormat('Settings_Notice_MinecraftFetchFailed', { errorMessage }, errorMessage))
            if methods.ShowModalAlertByKeys then
                methods.ShowModalAlertByKeys(
                    'error',
                    modalSummaryKey,
                    modalErrorMessage
                )
            end

        end

    end

    function methods.applyMinecraftSkinFileAttachResult(result)
        result = result or {}
        local status = string.upper(trim(result.status or ''))
        local message = trim(result.message or '')
        local imagePath = trim(result.imagePath or '')
        local texturePath = trim(result.texturePath or '')
        local model = trim(result.model or '')
        local username = trim(result.username or '')
        local logPath = trim(result.logPath or '')

        methods.appendMinecraftSkinDebugLog('applyMinecraftSkinFileAttachResult status=' .. tostring(status) .. ' imagePath=' .. tostring(imagePath) .. ' texturePath=' .. tostring(texturePath) .. ' model=' .. tostring(model) .. ' message=' .. tostring(message) .. ' logPath=' .. tostring(logPath))

        if status == 'CANCEL' then
            logNotice('Minecraft skin file attachment canceled.')
            return
        end

        if status == 'OK' and imagePath ~= '' then
            if username == '' then
                username = 'A'
            end
            methods.applyMinecraftSkinFetchResult({
                status = 'OK',
                username = username,
                imagePath = imagePath,
                texturePath = texturePath,
                model = model,
                message = '',
            })
            if methods.syncMinecraftSkinDraft then
                methods.syncMinecraftSkinDraft('')
            end
            return
        end

        if message == '' then
            message = methods.localize('ModalAlert_MinecraftSkinFileInvalid', 'Attach a correct 64x64 PNG Minecraft skin texture.')
        end

        logNotice(methods.localizeFormat('Settings_Notice_MinecraftSkinFileFailed', { message }, message))
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_MinecraftSkinFileInvalid',
                message,
                logPath
            )
        end
    end

    function methods.restorePendingMinecraftSkinModelSelection()
        local snapshot = state.pendingLoadBeforeSnapshot
        if not snapshot then
            return
        end

        local previousModel = trim(snapshot.minecraftSkinModel or '')
        if previousModel == '' then
            return
        end

        local modelField = methods.getField('minecraftSkinModel')
        if not modelField then
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinModel', previousModel)
            return
        end

        methods.applyFieldValue(modelField, previousModel, { targetSet = {} })
    end

    function methods.applyMinecraftSkinTextureRenderResult(result)
        result = result or {}
        local status = string.upper(trim(result.status or ''))
        local message = trim(result.message or '')
        local imagePath = trim(result.imagePath or '')
        local texturePath = trim(result.texturePath or '')
        local model = trim(result.model or '')
        local username = trim(result.username or '')
        local logPath = trim(result.logPath or '')

        if username == '' then
            local canonicalField = methods.getField('minecraftSkinUsername')
            username = canonicalField and trim(methods.readFieldValue(canonicalField)) or ''
        end

        methods.appendMinecraftSkinDebugLog('applyMinecraftSkinTextureRenderResult status=' .. tostring(status) .. ' username=' .. tostring(username) .. ' imagePath=' .. tostring(imagePath) .. ' texturePath=' .. tostring(texturePath) .. ' model=' .. tostring(model) .. ' message=' .. tostring(message) .. ' logPath=' .. tostring(logPath))

        if status == 'OK' and imagePath ~= '' then
            methods.applyMinecraftSkinFetchResult({
                status = 'OK',
                username = username,
                imagePath = imagePath,
                texturePath = texturePath,
                model = model,
                message = '',
            })
            if methods.syncMinecraftSkinDraft then
                methods.syncMinecraftSkinDraft(username)
            end
            return
        end

        if message == '' then
            message = methods.localize('ModalAlert_MinecraftSkinFileInvalid', 'Attach a correct 64x64 PNG Minecraft skin texture.')
        end

        if methods.restorePendingMinecraftSkinModelSelection then
            methods.restorePendingMinecraftSkinModelSelection()
        end

        logNotice(methods.localizeFormat('Settings_Notice_MinecraftSkinFileFailed', { message }, message))
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_MinecraftSkinFileInvalid',
                message,
                logPath
            )
        end
    end



    function methods.handleOpenVersionManagerHelperResult(values)
        local status = string.upper(trim(values.DMEL_STATUS or ''))
        local logPath = trim(values.DMEL_LOGPATH or '')
        local message = trim(values.DMEL_MESSAGE or '')

        if status == 'OK' or status == 'CANCEL' then
            if methods.clearVersionManagerLaunchPending then
                methods.clearVersionManagerLaunchPending()
            end
            return
        end

        if status == 'WARN' then
            local details = {}
            if message ~= '' then
                details[#details + 1] = message
            end
            if logPath ~= '' then
                details[#details + 1] = 'log=' .. logPath
            end
            if #details == 0 then
                details[#details + 1] = 'Version manager launch confirmation timed out.'
            end
            logNotice('Version manager warning: ' .. table.concat(details, ' | '))
            -- The launcher has started; keep the Settings watchdog pending so
            -- slower packaged installs can still report the eventual shown/error state.
            return
        end

        if methods.clearVersionManagerLaunchPending then
            methods.clearVersionManagerLaunchPending()
        end

        local details = {}
        if message ~= '' then
            details[#details + 1] = message
        end
        if logPath ~= '' then
            details[#details + 1] = 'log=' .. logPath
        end
        if #details == 0 then
            details[#details + 1] = 'Version manager failed.'
        end
        if status == '' then
            status = 'ERROR'
            details[#details + 1] = 'missing DMEL_STATUS output'
        end


        logNotice('Version manager ' .. string.lower(status) .. ': ' .. table.concat(details, ' | '))
        showModalAlert(
            'error',
            'ModalAlert_VersionManagerFailed',
            'Skins could not be opened from Settings. Refresh the skin and try again.',
            logPath
        )
    end

    function methods.handleVersionCatalogHelperResult(values)
        local cachePairs = {
            VersionManagerCacheLatestVersion = trim(values.DMEL_LATESTVERSION or ''),
            VersionManagerCacheStatus = trim(values.DMEL_CACHESTATUS or ''),
            VersionManagerCacheErrorCode = trim(values.DMEL_CACHEERRORCODE or ''),
            VersionManagerCacheFailureHint = trim(values.DMEL_CACHEFAILUREHINT or ''),
            VersionManagerCacheLastCheckedAtUtc = trim(values.DMEL_CACHELASTCHECKEDATUTC or ''),
        }

        for variableName, value in pairs(cachePairs) do
            methods.writePersistentCacheVariable(variableName, value)
        end

        if methods.handleVersionCatalogCacheRefreshComplete then
            methods.handleVersionCatalogCacheRefreshComplete(values)
        end
    end

    function methods.handleOpenLogFolderHelperResult(values)
        local status = string.upper(trim(values.DMEL_STATUS or ''))
        local logPath = trim(values.DMEL_LOGPATH or '')
        local message = trim(values.DMEL_MESSAGE or '')

        if status == 'OK' then
            return
        end

        local details = {}

        if message ~= '' then
            details[#details + 1] = message
        end
        if logPath ~= '' then
            details[#details + 1] = 'log=' .. logPath
        end

        if status == '' then
            status = 'ERROR'
            details[#details + 1] = 'missing DMEL_STATUS output'
        end

        if #details == 0 then
            details[#details + 1] = 'Log folder open failed.'
        end


        logNotice('Log folder open ' .. string.lower(status) .. ': ' .. table.concat(details, ' | '))
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_OpenLogFailed',
                'The log folder could not be opened. Check whether File Explorer is working normally.'
            )
        end
    end

    function methods.finishPendingLoadCycle()

        local reopenFieldKey = state.pendingLoadFieldKey

        local reopenRowIndex = state.pendingLoadRowIndex

        local shouldReopenDropdown = state.pendingLoadReopenDropdown

        methods.clearPendingLoadState()

        methods.setLoadingVisible(false)



        local reopenField = methods.getField(reopenFieldKey)

        if shouldReopenDropdown and reopenField and methods.hasDropdown(reopenField) and state.currentVisibleRows[reopenFieldKey] then

            state.activeDropdownFieldKey = reopenFieldKey

            state.activeDropdownRowIndex = state.currentVisibleRows[reopenFieldKey] or reopenRowIndex or 0

            state.activeDropdownPageIndex = methods.optionPageForValue(reopenField, methods.readFieldValue(reopenField))

        end



        methods.renderActivePage()

    end



    function methods.HandleHelperComplete(helperKind)
        if state.pendingLoadHelperRunning ~= true then
            if methods.handleIgnoredPendingLoadHelperCompletion(helperKind) then
                return
            end
            return
        end
        if trim(state.pendingLoadHelperKind or '') ~= trim(helperKind or '') then
            if methods.handleIgnoredPendingLoadHelperCompletion(helperKind) then
                return
            end
            return
        end
        local loadKind = state.pendingLoadKind
        local field = methods.getField(state.pendingLoadFieldKey)
        local output = methods.runCommandMeasureOutput(state.pendingLoadHelperMeasureName)
        local values = methods.parseCommandCaptureVariables(output)
        local shouldFinishLoadCycle = true
        if loadKind == 'fontFamily' then
            methods.applyBundledFontFacesFromValues(field, values)
            if not state.bundledFontFaces or #state.bundledFontFaces == 0 then
                methods.setBundledFontFaces({})
                logNotice('Settings UI bundled font scan returned no resource fonts.')
            end
            methods.persistPersistentCache('fontFamily')
        elseif loadKind == 'driveTargets' then
            methods.applyInstalledDriveTargetsFromValues(field, values)
            if not state.installedDriveTargets or #state.installedDriveTargets == 0 then
                methods.setInstalledDriveTargetList(methods.defaultDriveTargets(field))
                logNotice('Settings UI drive load fallback applied.')
            end
            methods.persistPersistentCache('driveTargets')
        elseif loadKind == 'computerInfo' then
            local driveField = methods.getField('expSource') or methods.getField('healthSource')
            methods.applyComputerInfoCachesFromValues(driveField, values)
            if not state.bundledFontFaces or #state.bundledFontFaces == 0 then
                methods.setBundledFontFaces({})
                logNotice('Settings UI bundled font scan returned no resource fonts.')
            end
            if not state.installedDriveTargets or #state.installedDriveTargets == 0 then
                methods.setInstalledDriveTargetList(methods.defaultDriveTargets(driveField))
                logNotice('Settings UI drive load fallback applied.')
            end
            if state.pendingLoadFieldKey == 'refreshComputerInfo'
                and methods.ShowModalAlertByKeys
                and ((not state.bundledFontFaces or #state.bundledFontFaces == 0)
                    or (not state.installedDriveTargets or #state.installedDriveTargets == 0)) then
                methods.ShowModalAlertByKeys(
                    'warn',
                    'ModalAlert_ComputerInfoUnavailable',
                    'Some computer information could not be loaded, so default options are being shown.'
                )
            end
            methods.persistPersistentCache('computerInfo')
            if state.pendingLoadFieldKey == 'startupAutoRun' then
                methods.captureBaselineState()
            end
        elseif loadKind == 'startupAutoRunProbe' then
            methods.applyStartupAutoRunProbeOutput(output)
            methods.captureBaselineState()
        elseif loadKind == 'startupAutoRunApply' then
            methods.applyStartupAutoRunApplyOutput(output, field)
        elseif loadKind == 'minecraftSkinApply' then
            methods.applyMinecraftSkinFetchResult({
                status = trim(values.DMEL_STATUS or ''),
                username = trim(values.DMEL_USERNAME or ''),
                imagePath = trim(values.DMEL_IMAGEPATH or ''),
                texturePath = trim(values.DMEL_TEXTUREPATH or ''),
                model = trim(values.DMEL_MODEL or ''),
                message = trim(values.DMEL_MESSAGE or ''),
                logPath = trim(values.DMEL_LOGPATH or values.DMEL_DEBUGLOG or ''),
            })
        elseif loadKind == 'minecraftSkinFileAttach' then
            methods.applyMinecraftSkinFileAttachResult({
                status = trim(values.DMEL_STATUS or ''),
                username = trim(values.DMEL_USERNAME or ''),
                imagePath = trim(values.DMEL_IMAGEPATH or ''),
                texturePath = trim(values.DMEL_TEXTUREPATH or ''),
                model = trim(values.DMEL_MODEL or ''),
                message = trim(values.DMEL_MESSAGE or ''),
                logPath = trim(values.DMEL_LOGPATH or ''),
            })
        elseif loadKind == 'minecraftSkinModelRender' then
            methods.applyMinecraftSkinTextureRenderResult({
                status = trim(values.DMEL_STATUS or ''),
                username = trim(values.DMEL_USERNAME or state.pendingLoadUsername or ''),
                imagePath = trim(values.DMEL_IMAGEPATH or ''),
                texturePath = trim(values.DMEL_TEXTUREPATH or state.pendingLoadTexturePath or ''),
                model = trim(values.DMEL_MODEL or state.pendingLoadValue or ''),
                message = trim(values.DMEL_MESSAGE or ''),
                logPath = trim(values.DMEL_LOGPATH or values.DMEL_DEBUGLOG or ''),
            })
        end
        if shouldFinishLoadCycle ~= false then
            methods.finishPendingLoadCycle()
        end
    end

    function methods.HandleDetachedHelperComplete(helperKind)
        local resolvedKind = trim(helperKind or '')
        state.detachedHelperMeasures = state.detachedHelperMeasures or {}
        local measureName = trim(state.detachedHelperMeasures[resolvedKind] or '')
        if measureName == '' then
            if state.detachedHelperRunning ~= true then
                return
            end
            if trim(state.detachedHelperKind or '') ~= resolvedKind then
                return
            end
            measureName = trim(state.detachedHelperMeasureName or '')
        end

        if measureName == '' then
            methods.clearDetachedHelperState(resolvedKind)
            return
        end

        local output = methods.runCommandMeasureOutput(measureName)
        local values = methods.parseCommandCaptureVariables(output)

        if resolvedKind == 'openLogFolder' then
            methods.handleOpenLogFolderHelperResult(values)
        elseif resolvedKind == 'openVersionManager' then
            methods.handleOpenVersionManagerHelperResult(values)
        elseif resolvedKind == 'versionCatalog' then
            methods.handleVersionCatalogHelperResult(values)
        end

        methods.clearDetachedHelperState(resolvedKind)
    end

    function methods.RunPendingLoad()

        if not state.pendingLoadKind or state.pendingLoadKind == '' then

            methods.clearPendingLoadState()

            methods.setLoadingVisible(false)

            methods.renderActivePage()

            return

        end



        if state.pendingLoadHelperRunning == true then

            methods.checkPendingLoadHelperWatchdog()

            return

        end



        if (state.pendingLoadDelayTicksRemaining or 0) > 0 then

            state.pendingLoadDelayTicksRemaining = state.pendingLoadDelayTicksRemaining - 1

            return

        end



        local loadKind = state.pendingLoadKind

        local field = methods.getField(state.pendingLoadFieldKey)

        local started = false



        if loadKind == 'fontFamily' then

            started = methods.startComputerInfoHelper({ includeFonts = true })

        elseif loadKind == 'driveTargets' then

            started = methods.startComputerInfoHelper({ includeDrives = true })

        elseif loadKind == 'computerInfo' then

            started = methods.startComputerInfoHelper({ includeFonts = true, includeDrives = true, includeStartupAutoRun = true })

        elseif loadKind == 'startupAutoRunProbe' then

            started = methods.startStartupAutoRunHelper(nil)

        elseif loadKind == 'startupAutoRunApply' then

            started = methods.startStartupAutoRunHelper(state.pendingLoadValue)

        elseif loadKind == 'minecraftSkinApply' then

            local requestedUsername = trim(state.pendingLoadValue or '')

            methods.appendMinecraftSkinDebugLog('RunPendingLoad minecraftSkinApply requestedUsername=' .. tostring(requestedUsername))

            if requestedUsername == '' then

                methods.applyMinecraftSkinFetchResult({ status = 'RESET', username = '', imagePath = '', message = '' })

                methods.finishPendingLoadCycle()

                return

            end


            if string.lower(requestedUsername) == 'a' then

                local localResult = methods.resolveLocalMinecraftSkinResult(requestedUsername)

                methods.appendMinecraftSkinDebugLog('RunPendingLoad attachedLocalResult=' .. tostring(localResult ~= nil))

                if localResult then

                    methods.applyMinecraftSkinFetchResult(localResult)

                    methods.finishPendingLoadCycle()

                    return

                end

                methods.applyMinecraftSkinFileAttachResult({
                    status = 'ERROR',
                    username = 'A',
                    imagePath = '',
                    texturePath = '',
                    message = methods.localize('Settings_Notice_MinecraftSkinFileMissing', 'The attached Minecraft skin file cache is missing. Attach the 64x64 PNG skin texture again.'),
                    logPath = '',
                })

                methods.finishPendingLoadCycle()

                return

            end



            local modelField = methods.getField('minecraftSkinModel')
            local currentModel = modelField and methods.readFieldValue(modelField) or SKIN:GetVariable('MinecraftSkinModel', 'wide')
            local requestedModel = methods.normalizeMinecraftSkinModelInput and methods.normalizeMinecraftSkinModelInput(currentModel) or (string.lower(trim(currentModel)) == 'slim' and 'slim' or 'wide')
            started = methods.startMinecraftSkinFetch(requestedUsername, requestedModel, 'minecraftSkinApply')

            methods.appendMinecraftSkinDebugLog('RunPendingLoad helperStarted=' .. tostring(started))

        elseif loadKind == 'minecraftSkinFileAttach' then

            local requestedModel = trim(state.pendingLoadValue or '')
            local initialDirectory = methods.playerSkinImageDirectoryPath and methods.playerSkinImageDirectoryPath() or ''

            methods.appendMinecraftSkinDebugLog('RunPendingLoad minecraftSkinFileAttach model=' .. tostring(requestedModel) .. ' initialDirectory=' .. tostring(initialDirectory))

            started = methods.startMinecraftSkinFilePicker(requestedModel, nil, 'A', 'minecraftSkinFileAttach', {
                acceptRenderedBody = true,
                initialDirectory = initialDirectory,
            })

            methods.appendMinecraftSkinDebugLog('RunPendingLoad filePickerStarted=' .. tostring(started))
        elseif loadKind == 'minecraftSkinModelRender' then

            local requestedModel = trim(state.pendingLoadValue or '')
            if methods.normalizeMinecraftSkinModelInput then
                requestedModel = methods.normalizeMinecraftSkinModelInput(requestedModel)
            elseif string.lower(requestedModel) ~= 'slim' then
                requestedModel = 'wide'
            end
            local requestedUsername = trim(state.pendingLoadUsername or '')
            if requestedUsername == '' then
                local canonicalField = methods.getField('minecraftSkinUsername')
                requestedUsername = canonicalField and trim(methods.readFieldValue(canonicalField)) or ''
            end
            local texturePath = trim(state.pendingLoadTexturePath or '')
            if texturePath == '' and methods.resolveCurrentMinecraftSkinTexturePath then
                texturePath = methods.resolveCurrentMinecraftSkinTexturePath(requestedUsername)
            end

            methods.appendMinecraftSkinDebugLog('RunPendingLoad minecraftSkinModelRender username=' .. tostring(requestedUsername) .. ' model=' .. tostring(requestedModel) .. ' texturePath=' .. tostring(texturePath))

            if texturePath ~= '' then
                started = methods.startMinecraftSkinFilePicker(requestedModel, texturePath, requestedUsername, 'minecraftSkinModelRender')
                methods.appendMinecraftSkinDebugLog('RunPendingLoad modelRenderHelperStarted=' .. tostring(started))
            elseif requestedUsername ~= '' then
                local localResult = methods.resolveLocalMinecraftSkinResult and methods.resolveLocalMinecraftSkinResult(requestedUsername) or nil
                if localResult and trim(localResult.imagePath or '') ~= '' and trim(localResult.texturePath or '') == '' then
                    localResult.model = requestedModel
                    methods.appendMinecraftSkinDebugLog('RunPendingLoad modelRender reused body-only cache imagePath=' .. tostring(localResult.imagePath))
                    methods.applyMinecraftSkinTextureRenderResult(localResult)
                    methods.finishPendingLoadCycle()
                    return
                end

                if string.lower(requestedUsername) ~= 'a' then
                    started = methods.startMinecraftSkinFetch(requestedUsername, requestedModel, 'minecraftSkinModelRender')
                    methods.appendMinecraftSkinDebugLog('RunPendingLoad modelRenderFetchStarted=' .. tostring(started))
                else
                    methods.applyMinecraftSkinTextureRenderResult({
                        status = 'ERROR',
                        username = requestedUsername,
                        imagePath = '',
                        texturePath = '',
                        model = requestedModel,
                        message = methods.localize('Settings_Notice_MinecraftSkinFileMissing', 'The attached Minecraft skin file cache is missing. Attach the 64x64 PNG skin texture again.'),
                        logPath = '',
                    })
                    methods.finishPendingLoadCycle()
                    return
                end
            else
                methods.applyMinecraftSkinTextureRenderResult({
                    status = 'ERROR',
                    username = requestedUsername,
                    imagePath = '',
                    texturePath = '',
                    model = requestedModel,
                    message = methods.localize('Settings_Notice_MinecraftSkinFileMissing', 'The attached Minecraft skin file cache is missing. Attach the 64x64 PNG skin texture again.'),
                    logPath = '',
                })
                methods.finishPendingLoadCycle()
                return
            end

        end



        if not started then

            logNotice('Settings helper could not be started for pending load: ' .. tostring(loadKind or ''))

            if loadKind == 'minecraftSkinModelRender' and methods.restorePendingMinecraftSkinModelSelection then
                methods.restorePendingMinecraftSkinModelSelection()
            end

            if methods.getIgnoredPendingLoadHelperCompletion(loadKind) then
                methods.clearPendingLoadState({ clearIgnoredHelper = false })
                methods.setLoadingVisible(false)
                methods.renderActivePage()
            else
                methods.finishPendingLoadCycle()
            end

        end

    end

end
