return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    function methods.refreshTargets(targetSet, options)

        local refreshOptions = options or {}

        if targetSet and refreshOptions.includeSettings == nil then
            refreshOptions.includeSettings = targetSet.__includeSettings == true
        end

        if targetSet and trim(refreshOptions.loadingText or '') == '' then
            refreshOptions.loadingText = targetSet.__loadingText
        end

        if targetSet and refreshOptions.waitForJukeboxReady == nil then
            refreshOptions.waitForJukeboxReady = targetSet.__waitForJukeboxReady == true
        end

        if methods.QueueRefreshTargets then

            local shouldRenderSettings = refreshOptions.includeSettings == true or trim(refreshOptions.loadingText or '') ~= ''

            if trim(refreshOptions.loadingText or '') ~= '' then
                methods.setLoadingVisible(true, refreshOptions.loadingText)
            end

            if shouldRenderSettings then
                methods.renderActivePage()
            end

            local queued = methods.QueueRefreshTargets(targetSet, refreshOptions)

            if not queued then
                if trim(refreshOptions.loadingText or '') ~= '' then
                    methods.setLoadingVisible(false)
                end
                if shouldRenderSettings then
                    methods.renderActivePage()
                end
            end

            return

        end

        methods.ensurePaths()

        for targetName, _ in pairs(targetSet or {}) do

            if targetName ~= 'Settings' then

                local target = schema.refreshTargetsByName[targetName]

                if target and state.rootConfig ~= '' then

                    local configPath = state.rootConfig .. '\\' .. target.config

                    local isActive = methods.isConfigTargetActive(targetName)
                    local isRefreshable = isActive or (methods.isConfigTargetRefreshable and methods.isConfigTargetRefreshable(targetName))

                    if isRefreshable then

                        if isActive and targetName == 'Inventory' then

                            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()', configPath)

                        elseif isActive then

                            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()', configPath)

                        end

                        SKIN:Bang('!Refresh', configPath, target.file)

                    end

                end

            end

        end

    end


    function methods.activationSemanticValue(field, resolved)

        if not field then

            return nil

        end

        local activateTargets = field.activateTargets or {}

        local deactivateTargets = field.deactivateTargets or activateTargets

        if #activateTargets == 0 and #deactivateTargets == 0 then

            return nil

        end

        if field.valueType == 'bool' then

            return methods.normalizeToggleValue(resolved) == '1'

        end

        if field.dropdownId == 'indicatorSource' then

            return trim(resolved) ~= 'disabled'

        end

        return nil

    end



    function methods.activateConfigTarget(targetName)

        methods.ensurePaths()

        if not targetName or targetName == '' or state.rootConfig == '' then

            return

        end

        local target = schema.refreshTargetsByName[targetName]

        if target then

            local configPath = state.rootConfig .. '\\' .. target.config

            if not methods.isConfigTargetActive or not methods.isConfigTargetActive(targetName) then

                SKIN:Bang('!ActivateConfig', configPath, target.file)

            end

        end

    end



    function methods.deactivateConfigTarget(targetName)

        methods.ensurePaths()

        if not targetName or targetName == '' or state.rootConfig == '' then

            return

        end

        local target = schema.refreshTargetsByName[targetName]

        if target then

            local configPath = state.rootConfig .. '\\' .. target.config

            if methods.isConfigTargetActive and methods.isConfigTargetActive(targetName) then

                SKIN:Bang('!DeactivateConfig', configPath)

            end

        end

    end


    local function configPathForTarget(targetName)

        methods.ensurePaths()

        local target = schema.refreshTargetsByName[targetName]

        if not target or state.rootConfig == '' then

            return '', nil

        end

        return state.rootConfig .. '\\' .. target.config, target

    end


    local function rainmeterBangArgument(value)

        return '"' .. tostring(value or ''):gsub('"', [[\"]]) .. '"'

    end


    local function appendRainmeterAction(actions, command, ...)

        local parts = { command }

        for _, argument in ipairs({ ... }) do

            table.insert(parts, rainmeterBangArgument(argument))

        end

        table.insert(actions, '[' .. table.concat(parts, ' ') .. ']')

    end


    function methods.stopAndDeactivateJukeboxTargets()

        local jukeboxConfig = configPathForTarget('Jukebox')

        local discSlotConfig = configPathForTarget('JukeboxDiscSlot')

        local mainActive = methods.isConfigTargetActive and methods.isConfigTargetActive('Jukebox')

        local discSlotActive = methods.isConfigTargetActive and methods.isConfigTargetActive('JukeboxDiscSlot')

        local actions = {}


        if discSlotActive and discSlotConfig ~= '' then

            SKIN:Bang('!DeactivateConfig', discSlotConfig)

        end




        if mainActive and jukeboxConfig ~= '' then

            appendRainmeterAction(actions, '!CommandMeasure', 'MeasureJukebox', 'StopPlaybackForFeatureDisable()', jukeboxConfig)

            table.insert(actions, '[!Delay 50]')

            appendRainmeterAction(actions, '!DeactivateConfig', jukeboxConfig)

        end


        if #actions > 0 then

            SKIN:Bang(table.concat(actions, ''))

        end


    end


    function methods.syncFieldActivationState(field, resolved)

        local activateTargets = field and field.activateTargets or {}

        local deactivateTargets = field and field.deactivateTargets or activateTargets

        local shouldActivate = methods.activationSemanticValue(field, resolved)

        if shouldActivate == nil then

            return nil

        end

        if field and field.key == 'jukeboxEnabled' and not shouldActivate then
            methods.BeginJukeboxSettingsApply('inactive')
            return methods.stopAndDeactivateJukeboxTargets()

        end

        local targetList = shouldActivate and activateTargets or deactivateTargets
        local jukeboxAlreadyActive = false
        if field and field.key == 'jukeboxEnabled' and shouldActivate then
            jukeboxAlreadyActive = methods.isConfigTargetActive('Jukebox')
            methods.BeginJukeboxSettingsApply('ready')
        end

        for _, targetName in ipairs(targetList) do

            if shouldActivate then

                methods.activateConfigTarget(targetName)

            else

                methods.deactivateConfigTarget(targetName)

            end

        end

        if jukeboxAlreadyActive then
            methods.RequestJukeboxSettingsApplyAck()
        end

        return shouldActivate

    end
end
