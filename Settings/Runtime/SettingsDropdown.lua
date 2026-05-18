return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable

    local languageDisplayKorean = '한국어'
    local languageDisplayEnglish = 'English'
    local clockTypeKeyByValue = {
        default = 'Settings_ClockType_BothDefault',
        text = 'Settings_ClockType_TextOnly',
        sprite = 'Settings_ClockType_SpriteOnly',
    }

    local clockTypeCanonicalByInput = {
        default = 'default',
        both = 'default',
        text = 'text',
        sprite = 'sprite',
    }

    local clockColorKeyByValue = {
        ['#FFFFFF'] = 'Settings_ClockColor_WhiteDefault',
        ['#B0B0B0'] = 'Settings_ClockColor_Gray',
        ['#707070'] = 'Settings_ClockColor_DarkGray',
        ['#000000'] = 'Settings_ClockColor_Black',
        ['#FF8080'] = 'Settings_ClockColor_LightRed',
        ['#55CC55'] = 'Settings_ClockColor_Green',
        ['#4A90E2'] = 'Settings_ClockColor_Blue',
        ['#1F3A93'] = 'Settings_ClockColor_Navy',
        ['#8E44AD'] = 'Settings_ClockColor_Purple',
    }

    local clockColorFallbackByValue = {
        ['#FFFFFF'] = 'White (default)',
        ['#B0B0B0'] = 'Gray',
        ['#707070'] = 'Dark gray',
        ['#000000'] = 'Black',
        ['#FF8080'] = 'Light red',
        ['#55CC55'] = 'Green',
        ['#4A90E2'] = 'Blue',
        ['#1F3A93'] = 'Navy',
        ['#8E44AD'] = 'Purple',
    }

    local indicatorSourceDisplayByValue = { disabled = 'Off' }
    local indicatorSourceCanonicalByInput = { disabled = 'disabled', off = 'disabled' }
    local indicatorSourceFallbackByValue = {
        cpuIdle = 'CPU free',
        cpuLoad = 'CPU usage',
        ramFree = 'RAM free',
        ramUsed = 'RAM usage',
        batteryCharge = 'Battery charge',
        batteryDrain = 'Battery drain',
        gpuFree = 'GPU free',
        gpuUsed = 'GPU usage',
        vramFree = 'VRAM free',
        vramUsed = 'VRAM usage',
    }

    local function indicatorSourceDisplayLabel(appliedValue)
        local canonical = trim(appliedValue)
        local fallback = indicatorSourceFallbackByValue[canonical] or canonical
        return trim(methods.localize('Settings_IndicatorSource_' .. canonical, fallback))
    end

    local function indicatorOffDisplayLabel()
        return trim(methods.localize('Settings_Dropdown_Disabled', 'Off'))
    end

    local function indicatorExpLinkedDisplayLabel()
        return trim(methods.localize('Settings_Dropdown_ExpLinked', 'Linked to XP bar'))
    end

    local function indicatorDiskSuffixLabel(appliedValue)
        if trim(appliedValue) == 'diskFree' then
            return trim(methods.localize('Settings_IndicatorSource_DiskFree', 'Disk free'))
        end
        return trim(methods.localize('Settings_IndicatorSource_DiskUsed', 'Disk usage'))
    end

    local function minecraftDefaultSteveDisplayLabel()
        return trim(methods.localize('Settings_Dropdown_MinecraftDefaultSteve', 'Default Steve'))
    end

    local function minecraftAlexDisplayLabel()
        return trim(methods.localize('Settings_Dropdown_MinecraftAlex', 'Alex'))
    end

    local function clockTypeDisplayLabel(value)
        local canonical = trim(value)
        local key = clockTypeKeyByValue[canonical] or clockTypeKeyByValue[methods.normalizeClockDisplayModeValue(canonical)]
        local fallback = canonical == 'default' and 'Use both' or canonical == 'text' and 'Text only' or canonical == 'sprite' and 'Clock only' or canonical
        return key and trim(methods.localize(key, fallback)) or fallback
    end

    local function clockColorDisplayLabel(value)
        local canonical = trim(value)
        local key = clockColorKeyByValue[canonical]
        local fallback = clockColorFallbackByValue[canonical] or canonical
        return key and trim(methods.localize(key, fallback)) or fallback
    end

    local function resolveIndicatorSourceCanonical(resolved)
        local normalized = trim(resolved)
        local lowered = string.lower(normalized)
        local canonical = indicatorSourceCanonicalByInput[normalized] or indicatorSourceCanonicalByInput[lowered]
        if canonical and canonical ~= '' then
            return canonical
        end

        for _, option in ipairs(schema.indicatorBaseOptions) do
            local optionCanonical = trim(option.appliedValue)
            local display = indicatorSourceDisplayLabel(optionCanonical)
            if normalized == display or lowered == string.lower(display) then
                return optionCanonical
            end
        end

        return nil
    end

    for _, option in ipairs(schema.indicatorBaseOptions) do
        local canonical = trim(option.appliedValue)
        local display = indicatorSourceDisplayLabel(canonical)
        local loweredCanonical = string.lower(canonical)
        local loweredDisplay = string.lower(display)

        indicatorSourceDisplayByValue[canonical] = display
        indicatorSourceDisplayByValue[loweredCanonical] = display
        indicatorSourceCanonicalByInput[canonical] = canonical
        indicatorSourceCanonicalByInput[loweredCanonical] = canonical
        indicatorSourceCanonicalByInput[display] = canonical
        indicatorSourceCanonicalByInput[loweredDisplay] = canonical
    end

    local function languageDropdownOptions()
        return {
            { displayLabel = languageDisplayKorean, appliedValue = 'ko-KR' },
            { displayLabel = languageDisplayEnglish, appliedValue = 'en-US' },
        }
    end

    function methods.indicatorDiskDisplayLabel(diskTarget, appliedValue)
        local prefix = trim(diskTarget)
        local suffix = indicatorDiskSuffixLabel(appliedValue)
        if prefix ~= '' then
            return prefix .. ' ' .. suffix
        end
        return suffix
    end

    function methods.buildIndicatorDropdownOptions(field)
        local options = {}
        local seenDisk = {}
        local currentSource = trim(methods.readFieldValue(field))
        local currentDiskTarget = methods.currentDiskTargetForField(field)

        if field.dropdownId == 'indicatorSource' then
            options[#options + 1] = { displayLabel = indicatorOffDisplayLabel(), appliedValue = 'disabled' }
        elseif field.dropdownId == 'indicatorExpLevel' then
            options[#options + 1] = { displayLabel = indicatorExpLinkedDisplayLabel(), appliedValue = '-1' }
        end

        for _, option in ipairs(schema.indicatorBaseOptions) do
            options[#options + 1] = {
                displayLabel = indicatorSourceDisplayLabel(option.appliedValue),
                appliedValue = option.appliedValue,
            }
        end

        for _, drive in ipairs(state.installedDriveTargets or {}) do
            options[#options + 1] = { displayLabel = methods.indicatorDiskDisplayLabel(drive, 'diskFree'), appliedValue = 'diskFree', diskTarget = drive }
            options[#options + 1] = { displayLabel = methods.indicatorDiskDisplayLabel(drive, 'diskUsed'), appliedValue = 'diskUsed', diskTarget = drive }
            seenDisk[drive .. '|diskFree'] = true
            seenDisk[drive .. '|diskUsed'] = true
        end

        if (currentSource == 'diskFree' or currentSource == 'diskUsed') and currentDiskTarget ~= '' then
            local signature = string.upper(currentDiskTarget) .. '|' .. currentSource
            if not seenDisk[signature] then
                table.insert(options, 1, {
                    displayLabel = methods.indicatorDiskDisplayLabel(currentDiskTarget, currentSource),
                    appliedValue = currentSource,
                    diskTarget = currentDiskTarget,
                })
            end
        end

        return options
    end

    function methods.buildMinecraftSkinHistoryDropdownOptions()
        local options = {
            { displayLabel = minecraftDefaultSteveDisplayLabel(), appliedValue = '' },
            { displayLabel = minecraftAlexDisplayLabel(), appliedValue = 'Alex' },
        }
        local seen = { alex = true }
        for _, skinName in ipairs(methods.readMinecraftSkinHistoryNames()) do
            local key = string.lower(trim(skinName))
            if key ~= '' and not seen[key] then
                options[#options + 1] = { displayLabel = skinName, appliedValue = skinName, canDelete = true }
                seen[key] = true
            end
        end
        return options
    end

    function methods.clampIndicatorBarLiteral(raw)
        local numeric = tonumber(trim(raw))
        if not numeric then
            return nil
        end
        numeric = math.floor(numeric)
        if numeric < 0 then
            numeric = 0
        elseif numeric > 100 then
            numeric = 100
        end
        return tostring(numeric)
    end

    function methods.clampIndicatorLevelLiteral(raw)
        local numeric = tonumber(trim(raw))
        if not numeric then
            return nil
        end
        numeric = math.floor(numeric)
        if numeric == -1 then
            return '-1'
        end
        if numeric < 0 then
            numeric = 0
        elseif numeric > 9999 then
            numeric = 9999
        end
        return tostring(numeric)
    end

    function methods.clampIndicatorManualLiteral(field, raw)
        if not field then
            return nil
        end
        if field.dropdownId == 'indicatorExpLevel' then
            return methods.clampIndicatorLevelLiteral(raw)
        end
        if field.dropdownId == 'indicatorSource' then
            return methods.clampIndicatorBarLiteral(raw)
        end
        return nil
    end

    function methods.resolveIndicatorLikeInput(field, raw)
        local resolved = trim(raw)
        local lowered = string.lower(resolved)

        if field.dropdownId == 'indicatorExpLevel' then
            if resolved == indicatorExpLinkedDisplayLabel() or resolved == '-1' then
                return { value = '-1' }
            end
        elseif resolved == indicatorOffDisplayLabel() or lowered == 'disabled' then
            return { value = 'disabled' }
        end

        local clampedLiteral = methods.clampIndicatorManualLiteral(field, resolved)
        if clampedLiteral ~= nil then
            return { value = clampedLiteral }
        end

        local canonical = resolveIndicatorSourceCanonical(resolved)
        if canonical and canonical ~= '' then
            return { value = canonical }
        end

        local diskTarget, diskState = resolved:match('^([A-Za-z]:)%s*(.+)$')
        local normalizedDiskState = trim(diskState)
        local currentDiskFreeText = indicatorDiskSuffixLabel('diskFree')
        local currentDiskUsedText = indicatorDiskSuffixLabel('diskUsed')
        if diskTarget and normalizedDiskState ~= ''
            and (normalizedDiskState == currentDiskFreeText or normalizedDiskState == currentDiskUsedText) then
            return {
                value = normalizedDiskState == currentDiskFreeText and 'diskFree' or 'diskUsed',
                diskTarget = string.upper(trim(diskTarget)),
            }
        end

        return { value = resolved }
    end

    function methods.displayValueForField(field, storedValue)
        local resolved = trim(storedValue)
        if not field then
            return resolved
        end
        if field.key == 'language' then
            return methods.normalizeLanguageCode(resolved, resolved) == 'en-US' and languageDisplayEnglish or languageDisplayKorean
        end
        if field.dropdownId == 'indicatorExpLevel' and resolved == '-1' then
            return indicatorExpLinkedDisplayLabel()
        end
        if field.key == 'clockType' then
            return clockTypeDisplayLabel(resolved)
        end
        if field.key == 'clockTextColor' or field.key == 'hotbarTextColor' then
            return methods.displayClockColorValue(resolved)
        end
        if methods.isIndicatorLikeField(field) and resolved ~= '' then
            if resolved == 'disabled' then
                return indicatorOffDisplayLabel()
            end
            if resolved == 'diskFree' or resolved == 'diskUsed' then
                return methods.indicatorDiskDisplayLabel(methods.currentDiskTargetForField(field), resolved)
            end
            local canonical = indicatorSourceDisplayByValue[resolved] and resolved or indicatorSourceCanonicalByInput[string.lower(resolved)]
            return canonical and indicatorSourceDisplayLabel(canonical) or resolved
        end
        return resolved
    end

    function methods.normalizeTextAliasInput(field, raw)
        local resolved = trim(raw)
        if field and field.key == 'language' then
            local loweredResolved = string.lower(resolved)
            if loweredResolved == 'en' or loweredResolved == 'en-us' or resolved == languageDisplayEnglish then
                return 'en-US'
            end
            if loweredResolved == 'ko' or loweredResolved == 'ko-kr' or resolved == languageDisplayKorean then
                return 'ko-KR'
            end
            return methods.normalizeLanguageCode(resolved, 'ko-KR')
        end
        if field and field.key == 'clockType' then
            local loweredResolved = string.lower(resolved)
            local canonical = clockTypeCanonicalByInput[loweredResolved]
            if canonical then
                return canonical
            end
            for value, key in pairs(clockTypeKeyByValue) do
                local display = clockTypeDisplayLabel(value)
                if resolved == display or loweredResolved == string.lower(display) then
                    return value
                end
            end
            return methods.normalizeClockDisplayModeValue(resolved)
        end
        if methods.isIndicatorLikeField(field) then
            return methods.resolveIndicatorLikeInput(field, resolved).value
        end
        return resolved
    end

    function methods.currentDropdownOptions(field)
        if not field then
            return {}
        end

        if field.dropdownId == 'indicatorSource' or field.dropdownId == 'indicatorExpLevel' then
            return methods.buildIndicatorDropdownOptions(field)
        end

        if field.dropdownId == 'language' then
            return languageDropdownOptions()
        end

        if field.dropdownId == 'clockType' then
            return {
                { displayLabel = clockTypeDisplayLabel('default'), appliedValue = 'default' },
                { displayLabel = clockTypeDisplayLabel('text'), appliedValue = 'text' },
                { displayLabel = clockTypeDisplayLabel('sprite'), appliedValue = 'sprite' },
            }
        end

        if field.dropdownId == 'clockColor' then
            local options = {}
            for _, option in ipairs(schema.clockColorOptions or {}) do
                options[#options + 1] = {
                    displayLabel = clockColorDisplayLabel(option.appliedValue),
                    appliedValue = option.appliedValue,
                }
            end
            return options
        end

        if field.dropdownId == 'fontFamily' then
            local options = {}
            local bundled = state.bundledFontFaceSet or {}
            local currentValue = trim(methods.readFieldValue(field))

            for _, fontName in ipairs(state.bundledFontFaces or {}) do
                if bundled[fontName] then
                    options[#options + 1] = { displayLabel = fontName, appliedValue = fontName }
                end
            end

            if currentValue ~= '' and not bundled[currentValue] then
                options[#options + 1] = { displayLabel = currentValue, appliedValue = currentValue }
            end

            return options
        end

        if field.dropdownId == 'minecraftSkinHistory' then
            return methods.buildMinecraftSkinHistoryDropdownOptions()
        end

        return {}
    end

    function methods.dropdownPageCount(field)
        local options = methods.currentDropdownOptions(field)
        local count = #options
        if count < 1 then
            return 1
        end
        return math.max(1, math.ceil(count / state.dropdownRowsPerPage))
    end

    function methods.syncDropdownPageIndex(field)
        local pageCount = methods.dropdownPageCount(field)
        if state.activeDropdownPageIndex < 1 then
            state.activeDropdownPageIndex = 1
        end
        if state.activeDropdownPageIndex > pageCount then
            state.activeDropdownPageIndex = pageCount
        end
    end

    function methods.optionPageForValue(field, value)
        local options = methods.currentDropdownOptions(field)
        local trimmedValue = trim(value)
        local currentDiskTarget = methods.currentDiskTargetForField(field)
        local fallbackPage = 1
        local normalizedCurrentClockColor = nil

        if field and (field.key == 'clockTextColor' or field.key == 'hotbarTextColor') then
            normalizedCurrentClockColor = methods.normalizeClockColorValue(trimmedValue, trimmedValue)
        end

        for index, option in ipairs(options) do
            local optionValue = trim(option.appliedValue)
            if normalizedCurrentClockColor ~= nil then
                local normalizedOption = methods.normalizeClockColorValue(optionValue, optionValue)
                if normalizedOption == normalizedCurrentClockColor then
                    return math.ceil(index / state.dropdownRowsPerPage)
                end
            end
            if optionValue == trimmedValue then
                if fallbackPage == 1 then
                    fallbackPage = math.ceil(index / state.dropdownRowsPerPage)
                end
                if trim(option.diskTarget or '') == trim(currentDiskTarget) then
                    return math.ceil(index / state.dropdownRowsPerPage)
                end
            end
        end

        return fallbackPage
    end

    function methods.ensureDropdownDataReady(field, rowIndex)
        if not field or not methods.hasDropdown(field) then
            return 'ready'
        end

        if field.dropdownId == 'language' or field.dropdownId == 'clockType' or field.dropdownId == 'clockColor' or field.dropdownId == 'minecraftSkinHistory' then
            return 'ready'
        end

        if field.dropdownId == 'fontFamily' then
            if state.bundledFontFaces and #state.bundledFontFaces > 0 then
                return 'ready'
            end
            if methods.RestorePersistentCache('fontFamily') then
                return 'ready'
            end
            methods.ScheduleDropdownDataLoad(field.key, rowIndex)
            return 'scheduled'
        end

        if field.dropdownId == 'indicatorSource' or field.dropdownId == 'indicatorExpLevel' then
            if state.installedDriveTargets then
                return 'ready'
            end
            if methods.RestorePersistentCache('driveTargets') then
                return 'ready'
            end
            methods.ScheduleDropdownDataLoad(field.key, rowIndex)
            return 'scheduled'
        end

        return 'ready'
    end

    function methods.clearDropdownVisualState()
        setVariable('SettingsDropdownHidden', '1')
        setVariable('SettingsDropdownFieldKey', '')
        setVariable('SettingsDropdownRowIndex', '0')
        setVariable('SettingsDropdownPageText', '1/1')
        setVariable('SettingsDropdownPagePrevBgColor', SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('SettingsDropdownPagePrevTextColor', SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))
        setVariable('SettingsDropdownPageCurrentBgColor', SKIN:GetVariable('SettingsButtonBgColor', ''))
        setVariable('SettingsDropdownPageCurrentTextColor', SKIN:GetVariable('SettingsButtonTextColor', ''))
        setVariable('SettingsDropdownPageNextBgColor', SKIN:GetVariable('SettingsButtonDisabledBgColor', ''))
        setVariable('SettingsDropdownPageNextTextColor', SKIN:GetVariable('SettingsButtonDisabledTextColor', ''))
        for slotIndex = 1, state.dropdownRowsPerPage do
            setVariable('SettingsDropdownOption' .. slotIndex .. 'Hidden', '1')
            setVariable('SettingsDropdownOption' .. slotIndex .. 'LabelText', '')
            setVariable('SettingsDropdownOption' .. slotIndex .. 'AppliedValue', '')
            setVariable('SettingsDropdownOption' .. slotIndex .. '_LabelW', '0')
            setVariable('SettingsDropdownOption' .. slotIndex .. '_DeleteHidden', '1')
        end
        state.currentDropdownOptionBySlot = {}
    end

    function methods.closeDropdownInternal()
        state.activeDropdownFieldKey = nil
        state.activeDropdownRowIndex = 0
        state.activeDropdownPageIndex = 1
        state.currentDropdownOptionBySlot = {}
    end
end
