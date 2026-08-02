return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local logNotice = app.logNotice
    local helperResult = app.helperResult
    local configState = app.loadSharedLuaModule('RainmeterConfigState.lua')
    local helpers = app.cacheHelpers or {}
    local normalizeStartupAutoRunOutput = helpers.normalizeStartupAutoRunOutput
    local parseStartupAutoRunResult = helpers.parseStartupAutoRunResult
    local defaultLoadingMessage = helpers.defaultLoadingMessage
    local showModalAlert = helpers.showModalAlert
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
            methods.SetUpdateJob('helperWatchdog', true)
        else
            state.pendingLoadHelperStartedAt = 0
            state.pendingLoadHelperDeadlineAt = 0
            methods.SetUpdateJob('helperWatchdog', false)
        end
        setVariable(argsVariableName, tostring(args or ''))
        methods.SetUpdateJob('deferredLoad', false)
        SKIN:Bang('!UpdateMeasure', measureName)
        SKIN:Bang('!CommandMeasure', measureName, 'Run')
        return true
    end
    function methods.clearDetachedHelperState(helperKind)
        state.detachedHelperMeasures = state.detachedHelperMeasures or {}
        state.detachedHelperTokens = state.detachedHelperTokens or {}
        local resolvedKind = trim(helperKind or '')
        if resolvedKind ~= '' then
            state.detachedHelperMeasures[resolvedKind] = nil
            state.detachedHelperTokens[resolvedKind] = nil
        else
            state.detachedHelperMeasures = {}
            state.detachedHelperTokens = {}
        end

        local latestKind = ''
        local latestMeasureName = ''
        local latestLaunchToken = ''
        for activeKind, activeMeasureName in pairs(state.detachedHelperMeasures) do
            latestKind = tostring(activeKind or '')
            latestMeasureName = tostring(activeMeasureName or '')
            latestLaunchToken = tostring(state.detachedHelperTokens[latestKind] or '')
            break
        end

        state.detachedHelperRunning = next(state.detachedHelperMeasures) ~= nil
        state.detachedHelperKind = latestKind
        state.detachedHelperMeasureName = latestMeasureName
        state.detachedHelperLaunchToken = latestLaunchToken
    end

    function methods.startDetachedRunCommandHelper(helperKind, measureName, argsVariableName, args, options)
        options = options or {}
        if not SKIN:GetMeasure(tostring(measureName or '')) then
            logNotice('Settings detached helper run measure is missing: ' .. tostring(measureName or ''))
            return false
        end

        local resolvedKind = trim(helperKind or '')
        local resolvedMeasureName = tostring(measureName or '')
        local resolvedLaunchToken = trim(options.launchToken or '')
        state.detachedHelperMeasures = state.detachedHelperMeasures or {}
        state.detachedHelperTokens = state.detachedHelperTokens or {}
        if trim(state.detachedHelperMeasures[resolvedKind] or '') ~= '' then
            logNotice('Settings detached helper request ignored while the same action is still running: ' .. resolvedKind)
            return false
        end
        state.detachedHelperMeasures[resolvedKind] = resolvedMeasureName
        state.detachedHelperTokens[resolvedKind] = resolvedLaunchToken
        state.detachedHelperRunning = true
        state.detachedHelperKind = resolvedKind
        state.detachedHelperMeasureName = resolvedMeasureName
        state.detachedHelperLaunchToken = resolvedLaunchToken
        setVariable(argsVariableName, tostring(args or ''))
        SKIN:Bang('!UpdateMeasure', measureName)
        SKIN:Bang('!CommandMeasure', measureName, 'Run')
        return true
    end

    function methods.parseCommandCaptureVariables(raw)
        return helperResult.parseCommandCaptureVariables(raw)

    end

    function methods.computerInfoHelperScriptPath()

        return '.\\LoadComputerInfo.ps1'

    end

    function methods.computerInfoHelperArguments(options)

        options = options or {}

        local command = '-NoProfile -ExecutionPolicy Bypass -File '

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

            methods.computerInfoHelperArguments(options),

            {

                loadKind = trim(state.pendingLoadKind or '') ~= '' and trim(state.pendingLoadKind or '') or 'computerInfo',

                timeoutSeconds = 170,

            }

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

        return '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File '

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
        return '.\\PickMinecraftSkinFile.ps1'
    end

    function methods.minecraftSkinFilePickerArguments(model, sourcePath, username, options)
        options = options or {}
        local resolvedModel = 'wide'
        if methods.normalizeMinecraftSkinModelInput then
            resolvedModel = methods.normalizeMinecraftSkinModelInput(model)
        elseif string.lower(trim(model)) == 'slim' then
            resolvedModel = 'slim'
        end

        local command = '-NoProfile -STA -ExecutionPolicy Bypass -File '
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

        return '-NoProfile -ExecutionPolicy Bypass -File '

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

        local rootPath = trim(SKIN:GetVariable('ROOTCONFIGPATH', ''))

        rootPath = rootPath:gsub('[\\/]+$', '')

        if rootPath ~= '' then

            return rootPath

        end

        local currentPath = trim(SKIN:GetVariable('CURRENTPATH', ''))

        currentPath = currentPath:gsub('/', '\\'):gsub('[\\/]+$', '')

        local lowerPath = currentPath:lower()

        for _, suffix in ipairs({ '\\hud\\settings', '\\settings' }) do

            if lowerPath:sub(-#suffix) == suffix then

                return currentPath:sub(1, #currentPath - #suffix)

            end

        end

        return currentPath:match('^(.*)[\\/][^\\/]+$') or currentPath

    end

    function methods.openVersionManagerScriptPath()
        return '.\\OpenVersionManagerLauncher.ps1'
    end

    function methods.openVersionManagerHelperArguments(launchToken, initialAction)
        local args = '-NoProfile -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument(methods.openVersionManagerScriptPath())
            .. ' -TargetRoot '
            .. methods.escapeCommandArgument('..\\..')
            .. ' -LaunchToken '
            .. methods.escapeCommandArgument(trim(launchToken or ''))
            .. ' -EmitResultPairs'
        local action = trim(initialAction or '')
        if action ~= '' then
            args = args .. ' -InitialAction ' .. methods.escapeCommandArgument(action)
        end
        return args
    end

    function methods.startOpenVersionManagerHelper(initialAction)
        local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))
        local latestUpdateConfig = rootConfig ~= '' and (rootConfig .. '\\Utilities\\LatestUpdate') or ''
        if latestUpdateConfig ~= '' and configState.IsActive(SKIN, latestUpdateConfig) then
            SKIN:Bang('!CommandMeasure', 'MeasureLatestUpdate', 'Present()', latestUpdateConfig)
            return true
        end
        if methods.isVersionManagerLaunchPending and methods.isVersionManagerLaunchPending() then
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
            methods.openVersionManagerHelperArguments(launchToken, initialAction),
            { launchToken = launchToken }
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
        return '..\\..\\Utilities\\tools\\OpenSettingsLogFolder.ps1'
    end

    function methods.openLogFolderHelperArguments()
        return '-NoProfile -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument(methods.openLogFolderScriptPath())
            .. ' -TargetRoot '
            .. methods.escapeCommandArgument('..\\..')
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
end
