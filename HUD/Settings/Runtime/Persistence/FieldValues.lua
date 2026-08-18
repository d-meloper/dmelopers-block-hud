return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local HUD_MIRROR_TARGETS = {
        Hotbar = true,
        IndicatorHeart = true,
        IndicatorArmor = true,
        IndicatorFood = true,
        IndicatorAir = true,
        IndicatorExp = true,
        Clock = true,
        ClockSprite = true,
    }
    function methods.readRuntimeState(targetId)

        local core = methods.responsiveLayoutCore()

        if not core or not core.GetLiveState then

            return nil

        end

        return core.GetLiveState(SKIN, targetId)

    end



    function methods.writeIniVariable(path, variableName, value)

        local resolved = tostring(value or '')

        setVariable(variableName, resolved)

        SKIN:Bang('!WriteKeyValue', 'Variables', variableName, resolved, path)

    end



    function methods.writeIniKeyValue(path, sectionName, keyName, value)

        if not path or path == '' or not sectionName or sectionName == '' or not keyName or keyName == '' then

            return

        end

        SKIN:Bang('!WriteKeyValue', sectionName, keyName, tostring(value or ''), path)

    end



    function methods.settingsFilePath(fileKey)

        methods.ensurePaths()

        if fileKey == 'State' then

            return methods.statePath()

        end

        return state.settingsRoot .. schema.settingsFiles[fileKey]

    end

    function methods.readIniVariableFromFile(path, variableName, fallback)
        local handle = io.open(tostring(path or ''), 'rb')
        if not handle then
            return trim(fallback or '')
        end

        local data = handle:read('*all') or ''
        handle:close()

        if data:sub(1, 2) == '\255\254' then
            data = data:sub(3):gsub('%z', '')
        elseif data:sub(1, 3) == '\239\187\191' then
            data = data:sub(4)
        end

        local targetName = trim(variableName)
        for line in tostring(data or ''):gmatch('[^\r\n]+') do
            local key, value = line:match('^%s*([^=]+)%s*=%s*(.-)%s*$')
            if trim(key or '') == targetName then
                return trim(value or '')
            end
        end

        return trim(fallback or '')
    end


    function methods.settingsIniPath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'Settings.ini'

    end



    function methods.readSettingsMetadataVersion()

        if state.settingsMetadataVersion ~= nil then

            return state.settingsMetadataVersion

        end



        local resolved = trim(SKIN:GetVariable('AppVersion', ''))
        if resolved == '' then
            resolved = trim(SKIN:GetVariable('Version', ''))
        end

        if resolved == '' then

            local path = methods.settingsIniPath()

            local handle = io.open(path, 'rb')

            if handle then

                local bytes = handle:read('*all') or ''

                handle:close()

                local marker = 'V\0e\0r\0s\0i\0o\0n\0=\0'

                local startIndex = bytes:find(marker, 1, true)

                if startIndex then

                    local cursor = startIndex + #marker

                    local fragments = {}

                    while cursor <= #bytes do

                        local low = bytes:byte(cursor)

                        local high = bytes:byte(cursor + 1)

                        if not low or not high or low == 0x0D or low == 0x0A then

                            break

                        end

                        fragments[#fragments + 1] = string.char(low)

                        cursor = cursor + 2

                    end

                    resolved = trim(table.concat(fragments))

                end

            end

        end



        state.settingsMetadataVersion = resolved

        return resolved

    end



    function methods.appVersionDisplayValue()

        local resolved = methods.readSettingsMetadataVersion()

        if trim(resolved) == '' then

            return 'v?'

        end

        return 'v' .. resolved

    end



    function methods.readFieldValue(field)

        return trim(SKIN:GetVariable(field.variableName, ''))

    end

    function methods.readStoredJukeboxPlaybackSourceMode()
        local field = methods.getField('jukeboxPlaybackSourceMode')
        if not field then
            return 'local'
        end

        local stored = methods.readIniVariableFromFile(
            methods.settingsFilePath(field.settingsFile),
            field.variableName,
            methods.readFieldValue(field)
        )
        return methods.normalizeFieldValue(field, stored, 'local')
    end

    function methods.syncJukeboxPlaybackSourceModeFromStorage()
        local field = methods.getField('jukeboxPlaybackSourceMode')
        if not field then
            return 'local'
        end

        local stored = methods.readStoredJukeboxPlaybackSourceMode()
        setVariable(field.variableName, stored)
        return stored
    end


    function methods.setFieldSessionValue(field, value)

        if not field then

            return

        end

        setVariable(field.variableName, tostring(value or ''))

    end



    function methods.normalizeToggleValue(raw)

        return trim(raw) == '1' and '1' or '0'

    end



    function methods.normalizeIntegerValue(field, raw, fallback)

        local numeric = tonumber(trim(raw))

        if not numeric then

            numeric = tonumber(trim(fallback)) or field.min or 0

        end

        numeric = math.floor(numeric)

        if field.min ~= nil and numeric < field.min then

            numeric = field.min

        end

        if field.max ~= nil and numeric > field.max then

            numeric = field.max

        end

        return tostring(numeric)

    end



    local function clampClockColorChannel(value)

        local numeric = tonumber(value)

        if not numeric then

            return nil

        end

        numeric = math.floor(numeric + 0.5)

        if numeric < 0 then

            numeric = 0

        elseif numeric > 255 then

            numeric = 255

        end

        return numeric

    end



    local function formatClockColorRgba(red, green, blue, alpha)

        return string.format('%d,%d,%d,%d', red, green, blue, alpha)

    end

    local function formatClockColorRgb(red, green, blue)

        return string.format('%d,%d,%d', red, green, blue)

    end



    local function parseStoredClockColorValue(raw)

        local parts = {}

        for token in string.gmatch(trim(raw), '[^,%s]+') do

            parts[#parts + 1] = token

        end

        if #parts < 3 or #parts > 4 then

            return nil

        end

        local red = clampClockColorChannel(parts[1])

        local green = clampClockColorChannel(parts[2])

        local blue = clampClockColorChannel(parts[3])

        local alpha = clampClockColorChannel(parts[4] or '255')

        if not red or not green or not blue or not alpha then

            return nil

        end

        return formatClockColorRgba(red, green, blue, alpha), red, green, blue, alpha

    end



    local function parseHexClockColorValue(raw)

        local digits = trim(raw):match('^#([%x][%x][%x][%x][%x][%x])$')

        if not digits then

            return nil

        end

        local red = tonumber(digits:sub(1, 2), 16)

        local green = tonumber(digits:sub(3, 4), 16)

        local blue = tonumber(digits:sub(5, 6), 16)

        local alpha = 255

        return formatClockColorRgba(red, green, blue, alpha), red, green, blue, alpha

    end



    function methods.normalizeClockColorValue(raw, fallback)

        local normalized = parseHexClockColorValue(raw)

        if normalized then

            return normalized

        end

        normalized = parseStoredClockColorValue(raw)

        if normalized then

            return normalized

        end

        normalized = parseHexClockColorValue(fallback)

        if normalized then

            return normalized

        end

        normalized = parseStoredClockColorValue(fallback)

        if normalized then

            return normalized

        end

        return '255,255,255,255'

    end

    function methods.normalizeClockColorFieldValue(field, raw, fallback)

        local normalized, red, green, blue, alpha = parseHexClockColorValue(raw)

        if not normalized then

            normalized, red, green, blue, alpha = parseStoredClockColorValue(raw)

        end

        if not normalized then

            normalized, red, green, blue, alpha = parseHexClockColorValue(fallback)

        end

        if not normalized then

            normalized, red, green, blue, alpha = parseStoredClockColorValue(fallback)

        end

        if not normalized then

            red, green, blue, alpha = 255, 255, 255, 255

        end

        if field and field.colorStorage == 'rgb' then

            return formatClockColorRgb(red, green, blue)

        end

        return formatClockColorRgba(red, green, blue, alpha)

    end



    function methods.displayClockColorValue(raw)

        local _, red, green, blue = parseStoredClockColorValue(raw)

        if red == nil then

            _, red, green, blue = parseHexClockColorValue(raw)

        end

        if red == nil then

            return '#FFFFFF'

        end

        return string.format('#%02X%02X%02X', red, green, blue)

    end



    function methods.isIndicatorLikeField(field)

        return field and (field.dropdownId == 'indicatorSource' or field.dropdownId == 'indicatorExpLevel')

    end



    function methods.pairedDiskTargetField(field)

        if not field or not field.pairedDiskTargetFieldKey then

            return nil

        end

        return methods.getField(field.pairedDiskTargetFieldKey)

    end



    function methods.currentDiskTargetForField(field)

        local targetField = methods.pairedDiskTargetField(field)

        if not targetField then

            return ''

        end

        return trim(methods.readFieldValue(targetField))

    end



    function methods.normalizeClockDisplayModeValue(raw)
        local normalized = string.lower(trim(raw))
        if normalized == 'text' or normalized == 'sprite' then
            return normalized
        end
        return 'default'
    end

    function methods.normalizeFieldValue(field, raw, fallback)

        if field.valueType == 'bool' then

            return methods.normalizeToggleValue(raw)

        end

        if field.valueType == 'integer' then

            return methods.normalizeIntegerValue(field, raw, fallback)

        end

        if field and field.key == 'clockType' then
            return methods.normalizeClockDisplayModeValue(raw)
        end
        if field and field.key == 'jukeboxPlaybackSourceMode' then
            if methods.normalizeJukeboxPlaybackSourceModeInput then
                return methods.normalizeJukeboxPlaybackSourceModeInput(raw)
            end
            local mode = string.lower(trim(raw))
            return mode == 'external' and 'external' or 'local'
        end
        if field and field.dropdownId == 'clockColor' then

            return methods.normalizeClockColorFieldValue(field, raw, fallback)

        end

        return methods.normalizeTextAliasInput(field, raw)

    end



    function methods.collectFieldTargets(targetSet, field)
        for _, targetName in ipairs(field.refreshTargets or {}) do
            targetSet[targetName] = true
        end
        local loadingTextKey = trim(field.refreshLoadingTextKey or '')
        if loadingTextKey ~= '' and trim(targetSet.__loadingText or '') == '' then
            targetSet.__loadingText = methods.localize(loadingTextKey, field.refreshLoadingTextFallback or '')
        end
        if trim(field.refreshCompletionTarget or '') == 'JukeboxReady' then
            targetSet.__waitForJukeboxReady = true
        end
    end
    function methods.fieldTargetsSettings(field)
        for _, targetName in ipairs(field and field.refreshTargets or {}) do
            if targetName == 'Settings' then
                return true
            end
        end
        return false
    end
    function methods.fieldTargetsHudMirror(field)
        if not field or field.sessionOnly or field.settingsFile == 'State' then
            return false
        end
        for _, targetName in ipairs(field.refreshTargets or {}) do
            if HUD_MIRROR_TARGETS[targetName] then
                return true
            end
        end
        return false
    end
    function methods.syncHudMirrorFieldVariable(field, resolved)
        if not methods.fieldTargetsHudMirror(field) or trim(field.variableName or '') == '' then
            return false
        end
        local value = tostring(resolved or '')
        SKIN:Bang('!SetVariableGroup', field.variableName, value, 'HudMirrorRuntime')
        if field.hudMirrorResponsiveBase == true then
            SKIN:Bang('!SetVariableGroup', 'ResponsiveBase_' .. field.variableName, value, 'HudMirrorRuntime')
        end
        return true
    end
    function methods.syncSettingsTargetVariable(field, resolved)
        if not field or trim(field.variableName or '') == '' or not methods.fieldTargetsSettings(field) then
            return false
        end
        setVariable(field.variableName, tostring(resolved or ''))
        return true
    end
end
