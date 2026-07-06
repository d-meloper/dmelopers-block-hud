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
    function methods.applyMinecraftSkinFetchResult(result)

        local canonicalField = methods.getField('minecraftSkinUsername')

        local status = result and result.status or ''

        local resolvedImagePath = trim(result and result.imagePath or '')
        local resolvedTexturePath = trim(result and result.texturePath or '')
        local resolvedModel = ''
        if result and result.model ~= nil then
            if methods.normalizeMinecraftSkinModelInput then
                resolvedModel = methods.normalizeMinecraftSkinModelInput(result.model)
            elseif string.lower(trim(result.model)) == 'slim' then
                resolvedModel = 'slim'
            else
                resolvedModel = 'wide'
            end
        end

        methods.appendMinecraftSkinDebugLog('applyMinecraftSkinFetchResult status=' .. tostring(status) .. ' username=' .. tostring(result and result.username or '') .. ' imagePath=' .. tostring(resolvedImagePath) .. ' texturePath=' .. tostring(resolvedTexturePath) .. ' model=' .. tostring(resolvedModel) .. ' message=' .. tostring(result and result.message or ''))

        if status == 'OK' and canonicalField then

            local targetSet = {}

            methods.applyFieldValue(canonicalField, result.username, { targetSet = targetSet })
            if resolvedModel ~= '' then
                local modelField = methods.getField('minecraftSkinModel')
                if modelField then
                    methods.applyFieldValue(modelField, resolvedModel, { targetSet = targetSet })
                else
                    methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinModel', resolvedModel)
                end
            end

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', resolvedImagePath)

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', '1')
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', resolvedTexturePath)

            if methods.syncInventoryPlayerSkinLiveState then

                methods.syncInventoryPlayerSkinLiveState(result.username, resolvedImagePath, targetSet, { verified = true })

            end

            methods.refreshTargets(targetSet)

            methods.rememberMinecraftSkinHistory(result.username)

            if state.pendingLoadBeforeSnapshot then

                methods.pushHistory(state.pendingLoadHistoryLabel or canonicalField.historyLabel, state.pendingLoadBeforeSnapshot, {

                    afterSnapshot = methods.captureSnapshot(),

                })

            end

        elseif status == 'RESET' and canonicalField then

            local targetSet = {}

            methods.applyFieldValue(canonicalField, '', { targetSet = targetSet })

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', '')

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', '0')
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', '')

            if methods.syncInventoryPlayerSkinLiveState then

                methods.syncInventoryPlayerSkinLiveState('', '', targetSet)

            end

            methods.refreshTargets(targetSet)

            if state.pendingLoadBeforeSnapshot then

                methods.pushHistory(state.pendingLoadHistoryLabel or canonicalField.historyLabel, state.pendingLoadBeforeSnapshot, {

                    afterSnapshot = methods.captureSnapshot(),

                })

            end

        else

            local errorMessage = result and result.message or ''
            local modalErrorMessage = errorMessage
            local modalSummaryKey = ''

            if errorMessage == '' then

                errorMessage = methods.localize('Settings_Notice_MinecraftFailed', 'The Minecraft skin could not be loaded. Check the log folder for details.')
                modalErrorMessage = methods.localize('ModalAlert_MinecraftFailed', 'The Minecraft skin could not be loaded. Check the username and try again.')
                modalSummaryKey = 'ModalAlert_MinecraftFailed'

            end

            methods.syncMinecraftSkinDraftFromCanonical()

            logNotice(methods.localizeFormat('Settings_Notice_MinecraftFetchFailed', { errorMessage }, errorMessage))
            if methods.ShowModalAlertByKeys then
                methods.ShowModalAlertByKeys(
                    'error',
                    modalSummaryKey,
                    modalErrorMessage
                )
            end

        end

    end

    function methods.applyMinecraftSkinFileAttachResult(result)
        result = result or {}
        local status = string.upper(trim(result.status or ''))
        local message = trim(result.message or '')
        local imagePath = trim(result.imagePath or '')
        local texturePath = trim(result.texturePath or '')
        local model = trim(result.model or '')
        local username = trim(result.username or '')
        local logPath = trim(result.logPath or '')

        methods.appendMinecraftSkinDebugLog('applyMinecraftSkinFileAttachResult status=' .. tostring(status) .. ' imagePath=' .. tostring(imagePath) .. ' texturePath=' .. tostring(texturePath) .. ' model=' .. tostring(model) .. ' message=' .. tostring(message) .. ' logPath=' .. tostring(logPath))

        if status == 'CANCEL' then
            logNotice('Minecraft skin file attachment canceled.')
            return
        end

        if status == 'OK' and imagePath ~= '' then
            if username == '' then
                username = 'A'
            end
            methods.applyMinecraftSkinFetchResult({
                status = 'OK',
                username = username,
                imagePath = imagePath,
                texturePath = texturePath,
                model = model,
                message = '',
            })
            if methods.syncMinecraftSkinDraft then
                methods.syncMinecraftSkinDraft('')
            end
            return
        end

        if message == '' then
            message = methods.localize('ModalAlert_MinecraftSkinFileInvalid', 'Attach a correct 64x64 PNG Minecraft skin texture.')
        end

        logNotice(methods.localizeFormat('Settings_Notice_MinecraftSkinFileFailed', { message }, message))
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_MinecraftSkinFileInvalid',
                message,
                logPath
            )
        end
    end

    function methods.restorePendingMinecraftSkinModelSelection()
        local snapshot = state.pendingLoadBeforeSnapshot
        if not snapshot then
            return
        end

        local previousModel = trim(snapshot.minecraftSkinModel or '')
        if previousModel == '' then
            return
        end

        local modelField = methods.getField('minecraftSkinModel')
        if not modelField then
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinModel', previousModel)
            return
        end

        methods.applyFieldValue(modelField, previousModel, { targetSet = {} })
    end

    function methods.applyMinecraftSkinTextureRenderResult(result)
        result = result or {}
        local status = string.upper(trim(result.status or ''))
        local message = trim(result.message or '')
        local imagePath = trim(result.imagePath or '')
        local texturePath = trim(result.texturePath or '')
        local model = trim(result.model or '')
        local username = trim(result.username or '')
        local logPath = trim(result.logPath or '')

        if username == '' then
            local canonicalField = methods.getField('minecraftSkinUsername')
            username = canonicalField and trim(methods.readFieldValue(canonicalField)) or ''
        end

        methods.appendMinecraftSkinDebugLog('applyMinecraftSkinTextureRenderResult status=' .. tostring(status) .. ' username=' .. tostring(username) .. ' imagePath=' .. tostring(imagePath) .. ' texturePath=' .. tostring(texturePath) .. ' model=' .. tostring(model) .. ' message=' .. tostring(message) .. ' logPath=' .. tostring(logPath))

        if status == 'OK' and imagePath ~= '' then
            methods.applyMinecraftSkinFetchResult({
                status = 'OK',
                username = username,
                imagePath = imagePath,
                texturePath = texturePath,
                model = model,
                message = '',
            })
            if methods.syncMinecraftSkinDraft then
                methods.syncMinecraftSkinDraft(username)
            end
            return
        end

        if message == '' then
            message = methods.localize('ModalAlert_MinecraftSkinFileInvalid', 'Attach a correct 64x64 PNG Minecraft skin texture.')
        end

        if methods.restorePendingMinecraftSkinModelSelection then
            methods.restorePendingMinecraftSkinModelSelection()
        end

        logNotice(methods.localizeFormat('Settings_Notice_MinecraftSkinFileFailed', { message }, message))
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'error',
                'ModalAlert_MinecraftSkinFileInvalid',
                message,
                logPath
            )
        end
    end
end
