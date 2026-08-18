return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local logNotice = app.logNotice
    local helperResult = app.helperResult
    local helpers = app.cacheHelpers or {}
    local normalizeStartupAutoRunOutput = helpers.normalizeStartupAutoRunOutput
    local parseStartupAutoRunResult = helpers.parseStartupAutoRunResult
    local defaultLoadingMessage = helpers.defaultLoadingMessage
    local showModalAlert = helpers.showModalAlert
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

            started = methods.startStartupAutoRunHelper(nil, 'all')

        elseif loadKind == 'startupAutoRunApply' then

            started = methods.startStartupAutoRunHelper(state.pendingLoadValue, state.pendingLoadStartupMethod)

        elseif loadKind == 'startupAutoRunRecoveryProbe' then

            started = methods.startStartupAutoRunHelper(nil, 'all')

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

        elseif loadKind == 'minecraftSkinAtlasRender' then

            started = methods.startMinecraftSkinAtlasHelper()

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
