return function(app)
    local state = app.state
    local methods = app.methods
    local trim = app.trim

    function methods.escapeCommandArgument(value)
        local resolved = tostring(value or '')
        return '"' .. resolved:gsub('"', '""') .. '"'
    end

    function methods.parseStartupAutoRunLiteral(raw, fallback)
        local literal = tostring(fallback or '0')
        for line in tostring(raw or ''):gmatch('[^\r\n]+') do
            local trimmedLine = trim(line)
            if trimmedLine == '0' or trimmedLine == '1' then
                literal = trimmedLine
            end
        end
        return literal
    end

    function methods.startupAutoRunCacheInitialized()
        return methods.readPersistentCacheVariable('SettingsPersistentCacheStartupAutoRunInitialized', '0') == '1'
            and methods.readPersistentCacheVariable('SettingsPersistentCacheStartupFastAutoRunInitialized', '0') == '1'
    end

    function methods.startupAutoRunCachedValue()
        return methods.normalizeToggleValue(methods.readPersistentCacheVariable('SettingsPersistentCacheStartupAutoRunValue', '0'))
    end

    function methods.startupFastAutoRunCachedValue()
        return methods.normalizeToggleValue(methods.readPersistentCacheVariable('SettingsPersistentCacheStartupFastAutoRunValue', '0'))
    end

    function methods.normalizeStartupAutoRunState(mainLiteral, fastLiteral)
        local mainValue = methods.normalizeToggleValue(mainLiteral)
        local fastValue = methods.normalizeToggleValue(fastLiteral)
        if mainValue ~= '1' then
            fastValue = '0'
        end
        return mainValue, fastValue
    end

    function methods.currentStartupAutoRunState()
        local mainField = methods.getField('startupAutoRun')
        local fastField = methods.getField('startupFastAutoRun')
        local mainValue = mainField and methods.readFieldValue(mainField) or '0'
        local fastValue = fastField and methods.readFieldValue(fastField) or '0'
        mainValue, fastValue = methods.normalizeStartupAutoRunState(mainValue, fastValue)
        return {
            value = mainValue,
            fastValue = fastValue,
        }
    end

    function methods.persistStartupAutoRunCache(mainLiteral, fastLiteral)
        local mainValue, fastValue = methods.normalizeStartupAutoRunState(mainLiteral, fastLiteral)
        methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)
        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupAutoRunInitialized', '1')
        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupAutoRunValue', mainValue)
        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupFastAutoRunInitialized', '1')
        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupFastAutoRunValue', fastValue)
    end

    function methods.persistStartupAutoRunSettings(mainLiteral, fastLiteral, options)
        options = options or {}
        local mainField = methods.getField('startupAutoRun')
        local fastField = methods.getField('startupFastAutoRun')
        if not mainField or not fastField then
            return false
        end

        local mainValue, fastValue = methods.normalizeStartupAutoRunState(mainLiteral, fastLiteral)
        local current = options.currentState or methods.currentStartupAutoRunState()
        if options.force == true or current.value ~= mainValue then
            methods.writeIniVariable(methods.settingsFilePath(mainField.settingsFile), mainField.variableName, mainValue)
        end
        if options.force == true or current.fastValue ~= fastValue then
            methods.writeIniVariable(methods.settingsFilePath(fastField.settingsFile), fastField.variableName, fastValue)
        end
        return true
    end

    function methods.persistStartupAutoRunSetting(literal, options)
        local current = methods.currentStartupAutoRunState()
        return methods.persistStartupAutoRunSettings(literal, current.fastValue, options)
    end

    function methods.applyStartupAutoRunState(mainLiteral, fastLiteral, options)
        options = options or {}
        local mainField = methods.getField('startupAutoRun')
        local fastField = methods.getField('startupFastAutoRun')
        if not mainField or not fastField then
            return nil
        end

        local current = methods.currentStartupAutoRunState()
        local mainValue, fastValue = methods.normalizeStartupAutoRunState(mainLiteral, fastLiteral)
        methods.persistStartupAutoRunCache(mainValue, fastValue)
        methods.setFieldSessionValue(mainField, mainValue)
        methods.setFieldSessionValue(fastField, fastValue)
        methods.persistStartupAutoRunSettings(mainValue, fastValue, {
            force = options.force == true,
            currentState = current,
        })
        return {
            value = mainValue,
            fastValue = fastValue,
        }
    end

    function methods.resolveStartupAutoRunState(desiredLiteral)
        if desiredLiteral ~= nil then
            return methods.normalizeToggleValue(desiredLiteral)
        end
        if methods.startupAutoRunCacheInitialized() then
            return methods.startupAutoRunCachedValue()
        end
        return methods.currentStartupAutoRunState().value
    end

    function methods.hydrateStartupAutoRunFieldFromCache()
        if not methods.startupAutoRunCacheInitialized() then
            return false
        end
        methods.applyStartupAutoRunState(
            methods.startupAutoRunCachedValue(),
            methods.startupFastAutoRunCachedValue())
        return true
    end

    function methods.probeStartupAutoRunField()
        local current = methods.currentStartupAutoRunState()
        if methods.startupAutoRunCacheInitialized() then
            current = methods.applyStartupAutoRunState(
                methods.startupAutoRunCachedValue(),
                methods.startupFastAutoRunCachedValue()) or current
        end
        return current.value
    end
end
