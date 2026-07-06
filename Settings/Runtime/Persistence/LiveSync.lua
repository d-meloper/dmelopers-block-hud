return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    function methods.isWindowOptionToggleField(field)
        local optionName = methods.windowOptionNameForField(field)
        if optionName == '' then
            return false
        end
        return #methods.windowOptionTargetIdsForField(field) > 0
    end
    local ConfigState = nil

    local function configState()
        if not ConfigState then
            ConfigState = app.loadSharedLuaModule('RainmeterConfigState.lua')
        end
        return ConfigState
    end

    local function isRainmeterConfigActive(configName)
        return configState().IsActive(SKIN, configName)
    end
    local function isRefreshTargetConfigActive(targetName)
        methods.ensurePaths()
        local target = schema.refreshTargetsByName[targetName]
        if not target or state.rootConfig == '' then
            return false
        end
        return isRainmeterConfigActive(state.rootConfig .. '\\' .. target.config)
    end
    function methods.isConfigTargetLiveActive(targetName)
        methods.ensurePaths()
        local target = schema.refreshTargetsByName[targetName]
        if not target or state.rootConfig == '' then
            return false
        end
        local liveState = methods.readRuntimeState(targetName)
        return liveState ~= nil and liveState.Active or false
    end
    function methods.isConfigTargetActive(targetName)
        return isRefreshTargetConfigActive(targetName)
    end
    function methods.isConfigTargetRefreshable(targetName)
        return isRefreshTargetConfigActive(targetName)
    end
    function methods.configPathForRefreshTarget(targetName)
        methods.ensurePaths()
        local target = schema.refreshTargetsByName[targetName]
        if not target or state.rootConfig == '' then
            return ''
        end
        return state.rootConfig .. '\\' .. target.config
    end

    function methods.syncModalBaseFont(resolved)
        methods.ensurePaths()
        if state.rootConfig == '' then
            return false
        end
        local modalConfigPath = state.rootConfig .. '\\Modal'
        if not isRainmeterConfigActive(modalConfigPath) then
            return false
        end
        SKIN:Bang('!SetVariable', 'BaseFont', tostring(resolved or ''), modalConfigPath)
        SKIN:Bang('!UpdateMeterGroup', 'ModalMeters', modalConfigPath)
        SKIN:Bang('!Redraw', modalConfigPath)
        return true
    end

    function methods.syncHerobrineLiveState(field, resolved)
        local key = field and field.key or ''
        if key ~= 'herobrineEnabled' then
            return false
        end

        methods.ensurePaths()
        local enabledField = methods.getField('herobrineEnabled')
        local enabledVariable = enabledField and enabledField.variableName or 'EnableHerobrineSkin'
        local enabledValue = methods.normalizeToggleValue(resolved)
        local herobrineConfigPath = methods.configPathForRefreshTarget('Herobrine')

        for _, targetName in ipairs({ 'Hotbar', 'Inventory', 'Settings', 'Herobrine' }) do
            local configPath = methods.configPathForRefreshTarget(targetName)
            if configPath ~= '' and methods.isConfigTargetActive(targetName) then
                SKIN:Bang('!SetVariable', enabledVariable, enabledValue, configPath)
            end
        end

        local highlightSyncSent = false
        for _, targetName in ipairs({ 'Inventory', 'Hotbar' }) do
            local configPath = methods.configPathForRefreshTarget(targetName)
            if configPath ~= '' and methods.isConfigTargetRefreshable(targetName) then
                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', string.format('SyncHerobrineSettings(%q)', enabledValue), configPath)
                highlightSyncSent = true
                break
            end
        end

        if herobrineConfigPath ~= '' and not highlightSyncSent then
            if enabledValue == '1' then
                if not methods.isConfigTargetActive('Herobrine') then
                    SKIN:Bang('!ActivateConfig', herobrineConfigPath, 'Herobrine.ini')
                end
            else
                if methods.isConfigTargetRefreshable('Herobrine') then
                    SKIN:Bang('!CommandMeasure', 'MeasureHerobrine', 'Disable()', herobrineConfigPath)
                end
                if methods.isConfigTargetActive('Herobrine') then
                    SKIN:Bang('!DeactivateConfig', herobrineConfigPath)
                end
            end
        end

        return true
    end

    function methods.syncWindowOptionToggleState(field, resolved)
        if not methods.isWindowOptionToggleField(field) then
            return false
        end
        methods.ensurePaths()
        local literal = methods.normalizeToggleValue(resolved) == '1' and '1' or '0'
        local optionName = methods.windowOptionNameForField(field)
        for _, targetName in ipairs(methods.windowOptionTargetIdsForField(field)) do
            local isRefreshable = methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable(targetName) or methods.isConfigTargetActive(targetName)
            if isRefreshable then
                local target = schema.refreshTargetsByName[targetName]
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', field.variableName, literal, configPath)
                SKIN:Bang('!' .. optionName, literal, configPath)
            end
        end
        return true
    end

    function methods.syncInventoryRefreshPositionLockState(field, resolved)
        if not field or field.key ~= 'inventoryRefreshPositionLock' then
            return false
        end
        methods.ensurePaths()
        local target = schema.refreshTargetsByName.Inventory
        if not target then
            return false
        end
        local inventoryRefreshable = methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable('Inventory') or methods.isConfigTargetActive('Inventory')
        if not inventoryRefreshable then
            return false
        end
        local configPath = state.rootConfig .. '\\' .. target.config
        SKIN:Bang('!SetVariable', field.variableName, methods.normalizeToggleValue(resolved), configPath)
        return true
    end
    function methods.syncHotbarInventoryEnabledLiveState(field, resolved)
        if not field or field.key ~= 'inventoryEnabled' then
            return false
        end
        methods.ensurePaths()
        if not methods.isConfigTargetActive('Hotbar') then
            return false
        end
        local target = schema.refreshTargetsByName.Hotbar
        if not target then
            return false
        end
        local configPath = state.rootConfig .. '\\' .. target.config
        SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)
        SKIN:Bang('!CommandMeasure', 'MeasureHotbarLayout', 'ApplyLayout()', configPath)
        return true
    end

    function methods.syncInventoryTooltipSize(field, resolved)
        if not field or field.key ~= 'inventoryTooltipSize' then
            return false
        end
        methods.ensurePaths()
        local core = methods.responsiveLayoutCore()
        local scale = (core and core.GetScale and tonumber(core.GetScale(SKIN))) or 1
        local numericResolved = tonumber(resolved) or tonumber(field.min) or 8
        local scaledValue = tostring(math.max(8, math.floor((numericResolved * scale) + 0.5)))
        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))
        local inventoryActive = methods.isConfigTargetActive('Inventory')
        local inventoryRefreshable = inventoryActive or (methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable('Inventory'))
        if inventoryRefreshable then
            local target = schema.refreshTargetsByName.Inventory
            if target then
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)
                SKIN:Bang('!SetVariable', field.variableName, scaledValue, configPath)
                if inventoryActive then
                    SKIN:Bang('!SetOption', 'MeterText', 'FontSize', scaledValue, configPath)
                    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshCurrentTooltip()', configPath)
                    SKIN:Bang('!Redraw', configPath)
                end
            end
        end
        return true
    end
    function methods.syncInventoryItemSize(field, resolved)
        if not field or field.key ~= 'inventoryItemSize' then
            return false
        end
        methods.ensurePaths()
        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))
        local inventoryActive = methods.isConfigTargetActive('Inventory')
        local inventoryRefreshable = inventoryActive or (methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable('Inventory'))
        if inventoryRefreshable then
            local target = schema.refreshTargetsByName.Inventory
            if target then
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)
                if inventoryActive then
                    SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', configPath)
                    SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()', configPath)
                    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', configPath)
                    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', configPath)
                    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', configPath)
                    SKIN:Bang('!Redraw', configPath)
                end
            end
        end
        return true
    end
    function methods.syncInventorySupportToggle(field, resolved)
        local key = field and field.key or ''
        local meterByKey = {
            hideUsageGuide = { 'MeterOpenInfo' },
            hideSkinFolderButton = { 'MeterOpenSkinFolder' },
            hideEditButton = { 'MeterEdit' },
            hideSettingsButton = { 'MeterSettingsUIButton' },
        }
        if key ~= 'hideSteve' and not meterByKey[key] then
            return false
        end
        methods.ensurePaths()
        local inventoryActive = methods.isConfigTargetActive('Inventory')
        local inventoryRefreshable = inventoryActive or (methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable('Inventory'))
        if inventoryRefreshable then
            local target = schema.refreshTargetsByName.Inventory
            if target then
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)
                if inventoryActive then
                    if key == 'hideSteve' then
                        SKIN:Bang('!CommandMeasure', 'MeasurePlayerSkinState', 'Sync()', configPath)
                    else
                        for _, meterName in ipairs(meterByKey[key]) do
                            SKIN:Bang('!UpdateMeter', meterName, configPath)
                        end
                        SKIN:Bang('!Redraw', configPath)
                    end
                end
            end
        end
        return true
    end
    function methods.syncInventoryPlayerSkinLiveState(username, imagePath, targetSet, options)
        methods.ensurePaths()
        options = options or {}
        local allowStoredWidePath = options.verified == true or methods.isMinecraftSkinImagePathVerified(imagePath)
        local resolvedImagePath = methods.resolveStoredMinecraftSkinImagePath(username, imagePath, { allowStoredWidePath = allowStoredWidePath })
        local resolvedImagePathVerified = resolvedImagePath ~= '' and allowStoredWidePath
        local inventoryActive = methods.isConfigTargetActive('Inventory')
        local inventoryRefreshable = inventoryActive or (methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable('Inventory'))
        if not inventoryRefreshable then
            return false
        end
        local target = schema.refreshTargetsByName.Inventory
        if not target then
            return false
        end
        local configPath = state.rootConfig .. '\\' .. target.config
        SKIN:Bang('!SetVariable', 'MinecraftSkinUsername', tostring(username or ''), configPath)
        SKIN:Bang('!SetVariable', 'MinecraftSkinImagePath', resolvedImagePath, configPath)
        SKIN:Bang('!SetVariable', 'MinecraftSkinImagePathVerified', resolvedImagePathVerified and '1' or '0', configPath)
        if inventoryActive then
            SKIN:Bang('!CommandMeasure', 'MeasurePlayerSkinState', 'Sync()', configPath)

        end
        if targetSet then
            targetSet.Inventory = nil
        end
        return true
    end
    function methods.syncInventoryBottomRowLiveState(field, resolved, targetSet)
        if not field or field.key ~= 'inventoryBottomRow' then
            return false
        end
        methods.ensurePaths()
        local literal = methods.normalizeToggleValue(resolved)
        local handled = false
        local inventoryActive = methods.isConfigTargetActive('Inventory')
        local inventoryRefreshable = inventoryActive or (methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable('Inventory'))
        local target = schema.refreshTargetsByName.Inventory
        if target and inventoryRefreshable then
            local configPath = state.rootConfig .. '\\' .. target.config
            SKIN:Bang('!SetVariable', field.variableName, literal, configPath)
            if inventoryActive then
                SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()', configPath)
                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', configPath)
                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', configPath)
                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', configPath)
                SKIN:Bang('!Redraw', configPath)
            end
            handled = true
        end
        local hotbarTarget = schema.refreshTargetsByName.Hotbar
        if hotbarTarget and methods.isConfigTargetActive('Hotbar') then
            local hotbarConfigPath = state.rootConfig .. '\\' .. hotbarTarget.config
            local inventoryState = methods.readRuntimeState('Inventory')
            SKIN:Bang('!SetVariable', field.variableName, literal, hotbarConfigPath)
            if inventoryState then
                SKIN:Bang('!SetVariable', 'ResponsiveLayout_Inventory_LiveActive', inventoryState.Active and '1' or '0', hotbarConfigPath)
                if inventoryState.WindowX ~= nil then
                    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Inventory_LiveWindowX', tostring(inventoryState.WindowX), hotbarConfigPath)
                end
                if inventoryState.WindowY ~= nil then
                    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Inventory_LiveWindowY', tostring(inventoryState.WindowY), hotbarConfigPath)
                end
            end
            handled = true
        end
        local editorTarget = schema.refreshTargetsByName.Editor
        if editorTarget and methods.isConfigTargetActive('Editor') then
            local editorConfigPath = state.rootConfig .. '\\' .. editorTarget.config
            SKIN:Bang('!SetVariable', field.variableName, literal, editorConfigPath)
            SKIN:Bang('!CommandMeasure', 'MeasureInputCommit', string.format("SyncInventoryBottomRowLiveState('%s')", literal), editorConfigPath)
            handled = true
        end
        if targetSet then
            targetSet.Inventory = nil
            targetSet.Editor = nil
        end
        return handled
    end

    function methods.isClockHideMeridiemField(field)

        return field ~= nil and (field.key == 'clockHideMeridiem' or field.variableName == 'HideClockMeridiem')

    end



    function methods.clockLiveMeterNames()

        return { 'MeterTime24', 'MeterDate24', 'MeterTime12', 'MeterDate12', 'MeterTime12NoMeridiem', 'MeterDate12NoMeridiem' }

    end



    function methods.readClockDisplayModeLiteral()
        local field = methods.getField('clockType')
        if field then
            return methods.normalizeClockDisplayModeValue(methods.readFieldValue(field))
        end
        return methods.normalizeClockDisplayModeValue(SKIN:GetVariable('ClockDisplayMode', 'default'))
    end

    function methods.clockSurfaceEnabledForMode(targetName, mode, globalEnabled)
        if methods.normalizeToggleValue(globalEnabled) ~= '1' then
            return false
        end
        local normalizedMode = methods.normalizeClockDisplayModeValue(mode)
        if targetName == 'Clock' then
            return normalizedMode ~= 'sprite'
        end
        if targetName == 'ClockSprite' then
            return normalizedMode ~= 'text'
        end
        return false
    end

    function methods.readClockGlobalEnabledLiteral()
        local field = methods.getField('clockEnabled')
        if field then
            return methods.normalizeToggleValue(methods.readFieldValue(field))
        end
        return methods.normalizeToggleValue(SKIN:GetVariable('EnableClockSkin', '1'))
    end

    function methods.syncClockSurfaceActivation(mode, globalEnabled)
        local normalizedMode = methods.normalizeClockDisplayModeValue(mode)
        local enabledLiteral = methods.normalizeToggleValue(globalEnabled)
        local textEnabled = normalizedMode == 'sprite' and '0' or '1'
        local spriteEnabled = normalizedMode == 'text' and '0' or '1'
        methods.writeIniVariable(methods.settingsFilePath('Clock'), 'EnableClockTextSkin', textEnabled)
        methods.writeIniVariable(methods.settingsFilePath('Clock'), 'EnableClockSpriteSkin', spriteEnabled)
        setVariable('EnableClockTextSkin', textEnabled)
        setVariable('EnableClockSpriteSkin', spriteEnabled)
        for _, targetName in ipairs({ 'Clock', 'ClockSprite' }) do
            local target = schema.refreshTargetsByName[targetName]
            if target then
                if methods.clockSurfaceEnabledForMode(targetName, normalizedMode, enabledLiteral) then
                    methods.activateConfigTarget(targetName)
                else
                    methods.deactivateConfigTarget(targetName)
                end
            end
        end
    end

    function methods.syncClockType(field, resolved)
        if not field or field.key ~= 'clockType' then
            return false
        end
        methods.syncClockSurfaceActivation(resolved, methods.readClockGlobalEnabledLiteral())
        return true
    end

    function methods.syncClockSpriteSize(field, resolved)
        if not field or field.key ~= 'clockSpriteSize' then
            return false
        end
        methods.ensurePaths()
        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))
        if methods.isConfigTargetActive('ClockSprite') then
            local target = schema.refreshTargetsByName.ClockSprite
            if target then
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)
                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)
                SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', configPath)
                SKIN:Bang('!Redraw', configPath)
            end
        end
        return true
    end

    function methods.readClockHideMeridiemLiteral()

        local field = methods.getField('clockHideMeridiem')

        if field then

            return methods.normalizeToggleValue(methods.readFieldValue(field))

        end

        return methods.normalizeToggleValue(SKIN:GetVariable('HideClockMeridiem', '0'))

    end



    function methods.syncClock24Hour(field, resolved)

        if not field or field.key ~= 'clock24Hour' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                local literal = methods.normalizeToggleValue(resolved)

                SKIN:Bang('!SetVariable', field.variableName, literal, configPath)

                for _, meterName in ipairs(methods.clockLiveMeterNames()) do

                    SKIN:Bang('!UpdateMeter', meterName, configPath)

                end

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockHideMeridiem(field, resolved)

        if not methods.isClockHideMeridiemField(field) then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                local literal = methods.normalizeToggleValue(resolved)

                SKIN:Bang('!SetVariable', 'HideClockMeridiem', literal, configPath)

                SKIN:Bang('!UpdateMeasure', 'MeasureTime12', configPath)

                SKIN:Bang('!UpdateMeasure', 'MeasureTime12NoMeridiem', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterTime12', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterTime12NoMeridiem', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockDateSize(field, resolved)

        if not field or field.key ~= 'clockDateSize' then

            return false

        end

        methods.ensurePaths()

        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockTextColor(field, resolved)

        if not field or field.key ~= 'clockTextColor' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                for _, meterName in ipairs(methods.clockLiveMeterNames()) do

                    SKIN:Bang('!SetOption', meterName, 'FontColor', tostring(resolved), configPath)

                    SKIN:Bang('!UpdateMeter', meterName, configPath)

                end

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncHotbarTextColor(field, resolved)

        if not field or field.key ~= 'hotbarTextColor' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Hotbar') then

            local target = schema.refreshTargetsByName.Hotbar

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureFade', 'RefreshBaseColor()', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterHotbarText', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockActivationResync(field, shouldActivate)

        if not field or field.key ~= 'clockEnabled' then

            return false

        end

        methods.syncClockSurfaceActivation(methods.readClockDisplayModeLiteral(), shouldActivate and '1' or '0')

        if shouldActivate ~= true then

            return true

        end

        methods.ensurePaths()

        local target = schema.refreshTargetsByName.Clock

        local clock24HourField = methods.getField('clock24Hour')

        local clockTextColorField = methods.getField('clockTextColor')

        local clockHideMeridiemLiteral = methods.readClockHideMeridiemLiteral()

        if not target or not clock24HourField or not clockTextColorField then

            return false

        end

        local configPath = state.rootConfig .. '\\' .. target.config

        local literal = methods.normalizeToggleValue(methods.readFieldValue(clock24HourField))

        local colorLiteral = methods.normalizeStoredClockColorValue(methods.readFieldValue(clockTextColorField), '255,255,255,255')

        SKIN:Bang('!SetVariable', clock24HourField.variableName, literal, configPath)

        SKIN:Bang('!SetVariable', 'HideClockMeridiem', clockHideMeridiemLiteral, configPath)

        SKIN:Bang('!UpdateMeasure', 'MeasureTime12', configPath)

        SKIN:Bang('!UpdateMeasure', 'MeasureTime12NoMeridiem', configPath)

        for _, meterName in ipairs(methods.clockLiveMeterNames()) do

            SKIN:Bang('!SetOption', meterName, 'FontColor', colorLiteral, configPath)

            SKIN:Bang('!UpdateMeter', meterName, configPath)

        end

        SKIN:Bang('!Redraw', configPath)

        return true

    end
end
