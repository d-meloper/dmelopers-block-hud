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

    local function minecraftSkinPlayerFolderSizeViewIsVisible()
        local tab = methods.activeTab and methods.activeTab() or nil
        return tab ~= nil
            and trim(tab.id or '') == 'inventory'
            and methods.activePageIndex
            and methods.activePageIndex() == 2
    end

    local function minecraftSkinPlayerFolderSizeKoreanFallback(korean, global)
        local languageCode = methods.normalizeLanguageCode
            and methods.normalizeLanguageCode(SKIN:GetVariable('LanguageCode', 'en-US'), 'en-US')
            or trim(SKIN:GetVariable('LanguageCode', 'en-US'))
        return languageCode == 'ko-KR' and korean or global
    end

    function methods.minecraftSkinPlayerFolderSizeDisplayText()
        local bytes = math.max(0, tonumber(state.minecraftSkinPlayerFolderSizeBytes) or 0)
        local megabytes = string.format('%.1f', bytes / (1024 * 1024))
        return methods.localizeFormat(
            'Settings_Notice_MinecraftSkinPlayerFolderSize_Format',
            { megabytes },
            minecraftSkinPlayerFolderSizeKoreanFallback('차지한 용량: %1MB', 'Occupied space: %1MB')
        )
    end

    function methods.minecraftSkinPlayerFolderSizeTooltipText()
        return methods.localize(
            'Settings_Tooltip_MinecraftSkinPlayerFolderSize',
            minecraftSkinPlayerFolderSizeKoreanFallback(
                '스티브 스킨과 아틀라스 이미지 파일이 차지하는 총 용량입니다.\n윈도우 탐색기에서 사용하지 않는 파일을 직접 삭제해 용량을 확보할 수 있습니다.',
                'This is the total space used by Steve skin and atlas image files.\nYou can free up space by deleting unused files directly in File Explorer.'
            )
        )
    end

    function methods.requestMinecraftSkinPlayerFolderSize()
        if state.minecraftSkinPlayerFolderSizePending == true then
            return false
        end
        if not SKIN:GetMeasure('MeasureSettingsMinecraftSkinPlayerFolder')
            or not SKIN:GetMeasure('MeasureSettingsMinecraftSkinPlayerFolderSize') then
            return false
        end
        state.minecraftSkinPlayerFolderSizePending = true
        state.minecraftSkinPlayerFolderSizeNeedsRefresh = false
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsMinecraftSkinPlayerFolder', 'Update')
        SKIN:Bang('!UpdateMeasure', 'MeasureSettingsMinecraftSkinPlayerFolder')
        return true
    end

    function methods.markMinecraftSkinPlayerFolderSizeDirty()
        state.minecraftSkinPlayerFolderSizeNeedsRefresh = true
        if state.minecraftSkinPlayerFolderSizePending == true then
            state.minecraftSkinPlayerFolderSizeRescanRequested = true
            return false
        end
        if minecraftSkinPlayerFolderSizeViewIsVisible() then
            return methods.requestMinecraftSkinPlayerFolderSize()
        end
        return true
    end

    function methods.syncMinecraftSkinPlayerFolderSizeView()
        local visible = minecraftSkinPlayerFolderSizeViewIsVisible()
        if not visible then
            state.minecraftSkinPlayerFolderSizeViewActive = false
            return false
        end
        if state.minecraftSkinPlayerFolderSizeViewActive ~= true then
            state.minecraftSkinPlayerFolderSizeViewActive = true
            state.minecraftSkinPlayerFolderSizeNeedsRefresh = true
        end
        if state.minecraftSkinPlayerFolderSizeNeedsRefresh == true
            and state.minecraftSkinPlayerFolderSizePending ~= true then
            return methods.requestMinecraftSkinPlayerFolderSize()
        end
        return false
    end

    function methods.CaptureMinecraftSkinPlayerFolderSize()
        if state.minecraftSkinPlayerFolderSizePending ~= true then
            return false
        end
        local measure = SKIN:GetMeasure('MeasureSettingsMinecraftSkinPlayerFolderSize')
        local bytes = measure and tonumber(measure:GetValue()) or nil
        if bytes ~= nil then
            state.minecraftSkinPlayerFolderSizeBytes = math.max(0, math.floor(bytes + 0.5))
        end
        state.minecraftSkinPlayerFolderSizePending = false
        local rescanRequested = state.minecraftSkinPlayerFolderSizeRescanRequested == true
        state.minecraftSkinPlayerFolderSizeRescanRequested = false
        state.minecraftSkinPlayerFolderSizeNeedsRefresh = rescanRequested
        if minecraftSkinPlayerFolderSizeViewIsVisible() and methods.renderActivePage then
            methods.renderActivePage()
        end
        return bytes ~= nil
    end

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
        local atlasState = nil
        if status == 'OK' and methods.prepareMinecraftSkinAtlasState then
            atlasState = methods.prepareMinecraftSkinAtlasState({
                username = result and result.username or '',
                imagePath = resolvedImagePath,
                texturePath = resolvedTexturePath,
                model = resolvedModel,
                cacheKey = result and result.cacheKey or '',
                atlasPath = result and result.atlasPath or '',
                atlasReady = result and result.atlasReady or '',
                atlasRequired = result and result.atlasRequired or '',
            })
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

                methods.syncInventoryPlayerSkinLiveState(result.username, resolvedImagePath, targetSet, {
                    verified = true,
                    texturePath = resolvedTexturePath,
                    model = resolvedModel,
                    atlasPath = atlasState and atlasState.path or '',
                    atlasVerified = atlasState and atlasState.ready or false,
                    atlasManaged = atlasState ~= nil,
                })

            end

            methods.refreshTargets(targetSet)

            if methods.markMinecraftSkinPlayerFolderSizeDirty then
                methods.markMinecraftSkinPlayerFolderSizeDirty()
            end

            methods.rememberMinecraftSkinHistory(result.username)

            if state.pendingLoadBeforeSnapshot then

                methods.pushHistory(state.pendingLoadHistoryLabel or canonicalField.historyLabel, state.pendingLoadBeforeSnapshot, {

                    afterSnapshot = methods.captureSnapshot(),

                })

            end

            if atlasState and atlasState.required and methods.beginMinecraftSkinAtlasStage then
                return methods.beginMinecraftSkinAtlasStage(atlasState)
            end
            if atlasState and atlasState.bodyOnly and methods.showMinecraftSkinBodyOnlyNotice then
                methods.showMinecraftSkinBodyOnlyNotice()
            end
            return false

        elseif status == 'RESET' and canonicalField then

            local targetSet = {}

            methods.applyFieldValue(canonicalField, '', { targetSet = targetSet })

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', '')

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', '0')
            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', '')
            if methods.persistMinecraftSkinAtlasState then
                methods.persistMinecraftSkinAtlasState('', false, false)
            end

            if methods.syncInventoryPlayerSkinLiveState then

                methods.syncInventoryPlayerSkinLiveState('', '', targetSet, {
                    texturePath = '',
                    atlasPath = '',
                    atlasVerified = false,
                    atlasManaged = false,
                })

            end

            methods.refreshTargets(targetSet)

            if state.pendingLoadBeforeSnapshot then

                methods.pushHistory(state.pendingLoadHistoryLabel or canonicalField.historyLabel, state.pendingLoadBeforeSnapshot, {

                    afterSnapshot = methods.captureSnapshot(),

                })

            end

            return false

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

        return false

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
            return false
        end

        if status == 'OK' and imagePath ~= '' then
            if username == '' then
                username = 'A'
            end
            local atlasScheduled = methods.applyMinecraftSkinFetchResult({
                status = 'OK',
                username = username,
                imagePath = imagePath,
                texturePath = texturePath,
                model = model,
                cacheKey = result.cacheKey,
                atlasPath = result.atlasPath,
                atlasReady = result.atlasReady,
                atlasRequired = result.atlasRequired,
                message = '',
            })
            if methods.syncMinecraftSkinDraft then
                methods.syncMinecraftSkinDraft('')
            end
            return atlasScheduled == true
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
        return false
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
            local atlasScheduled = methods.applyMinecraftSkinFetchResult({
                status = 'OK',
                username = username,
                imagePath = imagePath,
                texturePath = texturePath,
                model = model,
                cacheKey = result.cacheKey,
                atlasPath = result.atlasPath,
                atlasReady = result.atlasReady,
                atlasRequired = result.atlasRequired,
                message = '',
            })
            if methods.syncMinecraftSkinDraft then
                methods.syncMinecraftSkinDraft(username)
            end
            return atlasScheduled == true
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
        return false
    end
end
