return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
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

    end



    function methods.startupAutoRunCachedValue()

        return methods.normalizeToggleValue(methods.readPersistentCacheVariable('SettingsPersistentCacheStartupAutoRunValue', '0'))

    end



    function methods.persistStartupAutoRunCache(literal)

        methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)

        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupAutoRunInitialized', '1')

        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupAutoRunValue', methods.normalizeToggleValue(literal))

    end



    function methods.persistStartupAutoRunSetting(literal, options)

        options = options or {}

        local field = methods.getField('startupAutoRun')

        if not field then

            return

        end

        local normalized = methods.normalizeToggleValue(literal)

        local currentLiteral = options.currentLiteral ~= nil and methods.normalizeToggleValue(options.currentLiteral) or methods.normalizeToggleValue(methods.readFieldValue(field))

        if options.force ~= true and currentLiteral == normalized then

            return

        end

        methods.writeIniVariable(methods.settingsFilePath(field.settingsFile), field.variableName, normalized)

    end



    function methods.resolveStartupAutoRunState(desiredLiteral)

        local field = methods.getField('startupAutoRun')

        local fallback = field and methods.normalizeToggleValue(methods.readFieldValue(field)) or '0'

        if desiredLiteral ~= nil then

            return methods.normalizeToggleValue(desiredLiteral)

        end

        if methods.startupAutoRunCacheInitialized() then

            return methods.startupAutoRunCachedValue()

        end

        return fallback

    end


    function methods.hydrateStartupAutoRunFieldFromCache()

        local field = methods.getField('startupAutoRun')

        if not field or not methods.startupAutoRunCacheInitialized() then

            return false

        end

        methods.setFieldSessionValue(field, methods.startupAutoRunCachedValue())

        return true

    end



    function methods.probeStartupAutoRunField()

        local field = methods.getField('startupAutoRun')

        if not field then

            return '0'

        end

        local actualLiteral = methods.resolveStartupAutoRunState(nil)

        methods.setFieldSessionValue(field, actualLiteral)

        return actualLiteral

    end
end
