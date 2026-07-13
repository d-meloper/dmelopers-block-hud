return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local FULL_REFRESH_BATCHES = {







        { 'Hotbar' },







        { 'Inventory' },







        { 'InventoryBG', 'Clock' },







        { 'Editor' },







        { 'IndicatorHeart', 'IndicatorArmor', 'IndicatorFood', 'IndicatorAir', 'IndicatorExp' },







    }







    local function refreshTarget(targetName, forceRefresh)







        local target = schema.refreshTargetsByName[targetName]







        if not target or state.rootConfig == '' then







            return false







        end







        local configPath = state.rootConfig .. '\\' .. target.config

        if targetName == 'Settings' then
            local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
            local currentFile = trim(SKIN:GetVariable('CURRENTFILE', target.file or 'Settings.ini'))
            if currentConfig == '' then
                return false
            end
            SKIN:Bang('!Refresh', currentConfig, currentFile ~= '' and currentFile or (target.file or 'Settings.ini'))
            return true
        end







        local isActive = methods.isConfigTargetActive(targetName)
        local isRefreshable = isActive
        if not isRefreshable and methods.isConfigTargetRefreshable then
            isRefreshable = methods.isConfigTargetRefreshable(targetName)
        end







        if not isRefreshable and forceRefresh ~= true then







            return false







        end







        if isActive and targetName == 'Inventory' then







            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()', configPath)







        elseif isActive then







            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()', configPath)







        end







        SKIN:Bang('!Refresh', configPath, target.file)







        return true







    end







    local function refreshBatch(batch, options)







        for _, targetName in ipairs(batch or {}) do







            refreshTarget(targetName, options and options.forceRefresh == true)







        end







    end







    local function pendingRefreshTargetSet()

        local seen = {}

        local batches = state.pendingRefreshBatches or {}

        local startIndex = (tonumber(state.pendingRefreshBatchIndex) or 0) + 1

        for index = startIndex, #batches do

            for _, targetName in ipairs(batches[index] or {}) do

                seen[targetName] = true

            end

        end

        return seen

    end

    local function normalizePendingRefreshOptions(options)

        local resolved = options or {}

        return {

            includeSettings = resolved.includeSettings == true,

            loadingText = trim(resolved.loadingText or ''),
            delayTicks = math.max(0, tonumber(resolved.delayTicks) or 0),
            forceRefresh = resolved.forceRefresh == true,

        }

    end







    local function appendRefreshBatches(batches, options)



        options = options or {}



        if options.replace then



            methods.clearPendingRefreshState()



        end



        local pendingBatches = state.pendingRefreshBatches or {}

        local pendingOptions = normalizePendingRefreshOptions(options)

        local existingOptions = state.pendingRefreshOptions or {}

        if existingOptions.includeSettings == true then

            pendingOptions.includeSettings = true

        end

        if existingOptions.forceRefresh == true then

            pendingOptions.forceRefresh = true

        end

        if pendingOptions.loadingText == '' then

            pendingOptions.loadingText = trim(existingOptions.loadingText or '')

        end

        local seen = pendingRefreshTargetSet()



        local added = false



        for _, batch in ipairs(batches or {}) do



            local queuedBatch = {}



            for _, targetName in ipairs(batch or {}) do



                if schema.refreshTargetsByName[targetName] and not seen[targetName] then



                    queuedBatch[#queuedBatch + 1] = targetName



                    seen[targetName] = true



                end



            end



            if #queuedBatch > 0 then



                pendingBatches[#pendingBatches + 1] = queuedBatch



                added = true



            end



        end



        state.pendingRefreshBatches = pendingBatches



        state.pendingRefreshBatchTotal = #pendingBatches

        state.pendingRefreshDelayTicksRemaining = math.max(
            tonumber(state.pendingRefreshDelayTicksRemaining) or 0,
            pendingOptions.delayTicks or 0)

        if #pendingBatches > 0 and (pendingOptions.includeSettings or pendingOptions.loadingText ~= '') then

            state.pendingRefreshOptions = pendingOptions

        else

            state.pendingRefreshOptions = nil

        end

        setVariable('SettingsPendingRefreshBatchIndex', tostring(state.pendingRefreshBatchIndex or 0))



        setVariable('SettingsPendingRefreshBatchTotal', tostring(state.pendingRefreshBatchTotal or 0))



        if added then
            if pendingOptions.loadingText ~= '' then
                methods.setLoadingVisible(true, pendingOptions.loadingText)
            end
            if pendingOptions.includeSettings == true or pendingOptions.loadingText ~= '' then
                methods.renderActivePage()
            end

            methods.SetUpdateJob('deferredRefresh', true)



        end



        return added



    end







    function methods.QueueRefreshBatches(batches, options)



        return appendRefreshBatches(batches, options)



    end







    function methods.QueueRefreshTargets(targetSet, options)



        local batches = {}



        local included = {}



        for _, templateBatch in ipairs(FULL_REFRESH_BATCHES) do



            local batch = {}



            for _, targetName in ipairs(templateBatch or {}) do



                if targetSet and targetSet[targetName] then



                    batch[#batch + 1] = targetName



                    included[targetName] = true



                end



            end



            if #batch > 0 then



                batches[#batches + 1] = batch



            end



        end



        local extras = {}

        local includeSettingsRefresh = options.includeSettings == true and targetSet and targetSet.Settings == true



        for targetName, _ in pairs(targetSet or {}) do



            if targetName ~= 'Settings' and schema.refreshTargetsByName[targetName] and not included[targetName] then



                extras[#extras + 1] = targetName



            end



        end



        table.sort(extras)



        for _, targetName in ipairs(extras) do



            batches[#batches + 1] = { targetName }



        end




        if includeSettingsRefresh then
            batches[#batches + 1] = { 'Settings' }
        end
        local added = appendRefreshBatches(batches, options)
        return added



    end

    function methods.RefreshSkin()
        SKIN:Bang('!RefreshApp')
    end















    function methods.RunPendingRefresh()

        local pendingOptions = state.pendingRefreshOptions or {}

        local batches = state.pendingRefreshBatches or {}







        if (tonumber(state.pendingRefreshDelayTicksRemaining) or 0) > 0 then
            state.pendingRefreshDelayTicksRemaining = (tonumber(state.pendingRefreshDelayTicksRemaining) or 0) - 1
            return true
        end

        local nextIndex = (tonumber(state.pendingRefreshBatchIndex) or 0) + 1







        if nextIndex > #batches then







            methods.clearPendingRefreshState()

            if pendingOptions.loadingText ~= '' then

                methods.setLoadingVisible(false)

            end

            if pendingOptions.includeSettings == true or pendingOptions.loadingText ~= '' then

                methods.renderActivePage()

            end

            return false







        end







        state.pendingRefreshBatchIndex = nextIndex







        state.pendingRefreshBatchTotal = #batches







        setVariable('SettingsPendingRefreshBatchIndex', tostring(nextIndex))







        setVariable('SettingsPendingRefreshBatchTotal', tostring(#batches))







        refreshBatch(batches[nextIndex], pendingOptions)







        if nextIndex >= #batches then

            methods.clearPendingRefreshState()

            if pendingOptions.loadingText ~= '' then

                methods.setLoadingVisible(false)

            end

            if pendingOptions.includeSettings == true or pendingOptions.loadingText ~= '' then

                methods.renderActivePage()

            end

        end







        return true







    end







end
