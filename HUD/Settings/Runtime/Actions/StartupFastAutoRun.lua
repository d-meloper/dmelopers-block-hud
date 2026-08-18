return function(app)
    local state = app.state
    local methods = app.methods
    local trim = app.trim

    local function luaString(value)
        return string.format('%q', tostring(value or ''))
    end

    local function modalConfigName()
        local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))
        if rootConfig == '' then
            return ''
        end
        return rootConfig .. '\\Utilities\\Modal'
    end

    local function nextConfirmationToken()
        state.startupFastAutoRunConfirmationCounter = (tonumber(state.startupFastAutoRunConfirmationCounter) or 0) + 1
        local clockPart = tostring(os.clock() or 0):gsub('[^0-9]', '')
        return 'SettingsFastStartup-' .. clockPart .. '-' .. tostring(state.startupFastAutoRunConfirmationCounter)
    end

    local function currentLiteral(fieldKey)
        local field = methods.getField(fieldKey)
        if not field then
            return '0'
        end
        return methods.normalizeToggleValue(methods.readFieldValue(field))
    end

    function methods.isStartupFastAutoRunConfirmationPending()
        return type(state.pendingStartupFastAutoRunConfirmation) == 'table'
            and trim(state.pendingStartupFastAutoRunConfirmation.token or '') ~= ''
    end

    function methods.clearPendingStartupFastAutoRunConfirmation(options)
        options = options or {}
        local pending = state.pendingStartupFastAutoRunConfirmation
        local expectedToken = trim(options.token or '')
        if expectedToken ~= ''
            and type(pending) == 'table'
            and trim(pending.token or '') ~= expectedToken then
            return false
        end

        state.pendingStartupFastAutoRunConfirmation = nil
        SKIN:Bang('!SetVariable', 'BlockHudSettingsStartupFastAutoRunConfirmDeferredOpen', '0')
        return pending ~= nil
    end

    function methods.ScheduleStartupAutoRunTransition(fieldKey, desiredLiteral, startupMethod)
        if methods.isLoadingVisible() then
            return false
        end

        local method = trim(startupMethod or ''):lower()
        if method ~= 'shortcut' and method ~= 'task' and method ~= 'all' then
            return false
        end

        local field = methods.getField(fieldKey)
        if not field then
            return false
        end

        return methods.ScheduleDropdownDataLoad(field.key, 0, 'startupAutoRunApply', false, {
            pendingValue = methods.normalizeToggleValue(desiredLiteral),
            startupMethod = method,
            requestToken = methods.nextStartupAutoRunRequestToken(),
            loadingText = methods.localize('Settings_Loading_StartupApply', 'Applying startup setting...\\nPlease wait.'),
        })
    end

    function methods.RequestStartupFastAutoRunConfirmation()
        if methods.isLoadingVisible() or methods.isStartupFastAutoRunConfirmationPending() then
            return false
        end
        if currentLiteral('startupAutoRun') ~= '1' or currentLiteral('startupFastAutoRun') ~= '0' then
            return false
        end

        local token = nextConfirmationToken()
        state.pendingStartupFastAutoRunConfirmation = { token = token }
        if methods.PreloadModalAlert then
            methods.PreloadModalAlert()
        end
        SKIN:Bang('!SetVariable', 'BlockHudSettingsStartupFastAutoRunConfirmDeferredOpen', '0')
        SKIN:Bang('!UpdateMeasure', 'MeasureSettingsStartupFastAutoRunConfirmDeferredOpen')
        SKIN:Bang('!SetVariable', 'BlockHudSettingsStartupFastAutoRunConfirmDeferredOpen', '1')
        SKIN:Bang('!UpdateMeasure', 'MeasureSettingsStartupFastAutoRunConfirmDeferredOpen')
        return true
    end

    function methods.OpenPendingStartupFastAutoRunConfirmation()
        local pending = state.pendingStartupFastAutoRunConfirmation
        local token = type(pending) == 'table' and trim(pending.token or '') or ''
        local modalConfig = modalConfigName()
        if token == '' or modalConfig == ''
            or currentLiteral('startupAutoRun') ~= '1'
            or currentLiteral('startupFastAutoRun') ~= '0' then
            methods.clearPendingStartupFastAutoRunConfirmation({ token = token })
            return false
        end

        local command = 'OpenCancelFirstConfirmByKeys('
            .. luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
            .. luaString(token) .. ','
            .. luaString('Modal_StartupFastAutoRunConfirm_Title') .. ','
            .. luaString('Modal_StartupFastAutoRunConfirm_Message') .. ','
            .. luaString('Common_Cancel') .. ','
            .. luaString('Modal_StartupFastAutoRunConfirm_Enable') .. ','
            .. luaString('MeasureSettingsCommit') .. ','
            .. luaString('CancelStartupFastAutoRun') .. ','
            .. luaString('ConfirmStartupFastAutoRun') .. ')'
        SKIN:Bang('!CommandMeasure', 'MeasureModal', command, modalConfig)
        return true
    end

    function methods.CancelStartupFastAutoRun(token)
        methods.clearPendingStartupFastAutoRunConfirmation({ token = token })
        methods.renderActivePage()
        return true
    end

    function methods.ConfirmStartupFastAutoRun(token)
        local pending = state.pendingStartupFastAutoRunConfirmation
        local pendingToken = type(pending) == 'table' and trim(pending.token or '') or ''
        if pendingToken == '' or trim(token or '') ~= pendingToken then
            return false
        end

        methods.clearPendingStartupFastAutoRunConfirmation({ token = pendingToken })
        if methods.isLoadingVisible()
            or currentLiteral('startupAutoRun') ~= '1'
            or currentLiteral('startupFastAutoRun') ~= '0' then
            methods.renderActivePage()
            return false
        end

        return methods.ScheduleStartupAutoRunTransition('startupFastAutoRun', '1', 'task')
    end
end
