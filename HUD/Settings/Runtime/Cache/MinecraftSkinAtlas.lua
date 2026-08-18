return function(app)
    local state = app.state
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local logNotice = app.logNotice

    local function flag(value)
        local resolved = trim(value or ''):lower()
        return resolved == '1' or resolved == 'true'
    end

    local function luaString(value)
        return string.format('%q', tostring(value or ''))
    end

    local function modalConfigName()
        local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', ''))
        return rootConfig ~= '' and (rootConfig .. '\\Utilities\\Modal') or ''
    end

    function methods.minecraftSkinAtlasProgressDirectory()
        methods.ensurePaths()
        return (state.resourcesRoot or '') .. 'Customs\\Data'
    end

    function methods.nextMinecraftSkinAtlasRequestToken()
        state.minecraftSkinAtlasRequestCounter = (tonumber(state.minecraftSkinAtlasRequestCounter) or 0) + 1
        local timePart = tostring(os.time() or 0):gsub('[^0-9]', '')
        local clockPart = tostring(os.clock() or 0):gsub('[^0-9]', '')
        return 'SettingsAtlas-' .. timePart .. '-' .. clockPart .. '-' .. tostring(state.minecraftSkinAtlasRequestCounter)
    end

    function methods.minecraftSkinAtlasLoadingText(percent)
        local value = math.max(0, math.min(100, math.floor((tonumber(percent) or 0) / 5) * 5))
        local languageCode = methods.normalizeLanguageCode
            and methods.normalizeLanguageCode(SKIN:GetVariable('LanguageCode', 'en-US'), 'en-US')
            or trim(SKIN:GetVariable('LanguageCode', 'en-US'))
        local fallback = languageCode == 'ko-KR'
            and '커서 애니메이션을 위한 아틀라스 이미지를 생성하는 중입니다.. %1% 완료'
            or 'Generating the atlas image for cursor animation... %1% complete'
        return methods.localizeFormat(
            'Settings_Loading_MinecraftSkinAtlas',
            { tostring(value) },
            fallback
        )
    end

    function methods.persistMinecraftSkinAtlasState(path, verified, managed)
        local resolvedPath = verified == true and trim(path or '') or ''
        local verifiedLiteral = resolvedPath ~= '' and '1' or '0'
        local managedLiteral = managed == true and '1' or '0'
        methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinAtlasPath', resolvedPath)
        methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinAtlasPathVerified', verifiedLiteral)
        methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinAtlasManaged', managedLiteral)
        return {
            path = resolvedPath,
            verified = verifiedLiteral == '1',
            managed = managedLiteral == '1',
        }
    end

    function methods.prepareMinecraftSkinAtlasState(result)
        result = result or {}
        local ready = flag(result.atlasReady) and trim(result.atlasPath or '') ~= ''
        local required = flag(result.atlasRequired)
        local cacheKey = trim(result.cacheKey or '')
        if cacheKey == '' then
            local bodyFileName = trim(result.imagePath or ''):match('([^\\/]+)$') or ''
            cacheKey = bodyFileName:match('^MinecraftSkinBody_(.+)%.png$') or ''
        end
        local texturePath = trim(result.texturePath or '')
        local bodyPath = trim(result.imagePath or '')
        local model = methods.normalizeMinecraftSkinModelInput
            and methods.normalizeMinecraftSkinModelInput(result.model)
            or (trim(result.model):lower() == 'slim' and 'slim' or 'wide')
        local persisted = methods.persistMinecraftSkinAtlasState(result.atlasPath, ready, true)
        return {
            ready = persisted.verified,
            path = persisted.path,
            managed = true,
            required = required and not ready and texturePath ~= '' and cacheKey ~= '' and bodyPath ~= '',
            bodyOnly = not ready and texturePath == '' and bodyPath ~= '',
            cacheKey = cacheKey,
            texturePath = texturePath,
            bodyPath = bodyPath,
            model = model,
            username = trim(result.username or ''),
        }
    end

    function methods.beginMinecraftSkinAtlasStage(request)
        request = request or {}
        if trim(request.texturePath or '') == '' or trim(request.bodyPath or '') == '' or trim(request.cacheKey or '') == '' then
            return false
        end
        -- Stage one has already reached its RunCommand FinishAction. Release that
        -- completed helper owner before arming the next-tick atlas helper.
        if state.pendingLoadHelperRunning == true and methods.clearPendingLoadHelperState then
            methods.clearPendingLoadHelperState()
        end
        local token = methods.nextMinecraftSkinAtlasRequestToken()
        state.pendingMinecraftSkinAtlasRequest = {
            token = token,
            texturePath = trim(request.texturePath),
            bodyPath = trim(request.bodyPath),
            cacheKey = trim(request.cacheKey),
            model = request.model == 'slim' and 'slim' or 'wide',
            username = trim(request.username or ''),
        }
        state.pendingLoadKind = 'minecraftSkinAtlasRender'
        state.pendingLoadFieldKey = 'minecraftSkinUsername'
        state.pendingLoadRowIndex = 0
        state.pendingLoadDelayTicksRemaining = 1
        state.pendingLoadReopenDropdown = false
        state.pendingLoadSilent = false
        state.pendingLoadValue = nil
        state.pendingLoadBeforeSnapshot = nil
        state.pendingLoadHistoryLabel = nil
        setVariable('SettingsPendingLoadKind', 'minecraftSkinAtlasRender')
        setVariable('SettingsMinecraftSkinAtlasRequestToken', token)
        methods.setLoadingVisible(true, methods.minecraftSkinAtlasLoadingText(0))
        if methods.refreshLoadingVisuals then
            methods.refreshLoadingVisuals()
        end
        methods.SetUpdateJob('atlasProgress', true)
        methods.SetUpdateJob('deferredLoad', true)
        return true
    end

    function methods.minecraftSkinAtlasHelperArguments(request)
        return '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File '
            .. methods.escapeCommandArgument('.\\EnsureMinecraftSkinLookAtlas.ps1')
            .. ' -SourcePath ' .. methods.escapeCommandArgument(request.texturePath)
            .. ' -OutputDirectory ' .. methods.escapeCommandArgument(methods.playerSkinImageDirectoryPath())
            .. ' -CacheKey ' .. methods.escapeCommandArgument(request.cacheKey)
            .. ' -Model ' .. methods.escapeCommandArgument(request.model)
            .. ' -BodyPath ' .. methods.escapeCommandArgument(request.bodyPath)
            .. ' -RequestToken ' .. methods.escapeCommandArgument(request.token)
            .. ' -ProgressDirectory ' .. methods.escapeCommandArgument(methods.minecraftSkinAtlasProgressDirectory())
    end

    function methods.startMinecraftSkinAtlasHelper()
        local request = state.pendingMinecraftSkinAtlasRequest
        if type(request) ~= 'table' or trim(request.token or '') == '' then
            return false
        end
        state.minecraftSkinAtlasLastProgress = -1
        setVariable('SettingsMinecraftSkinAtlasRequestToken', request.token)
        SKIN:Bang('!EnableMeasure', 'MeasureSettingsMinecraftSkinAtlasProgress')
        SKIN:Bang('!EnableMeasure', 'MeasureSettingsMinecraftSkinAtlasProgressName')
        methods.SetUpdateJob('atlasProgress', true)
        return methods.startRunCommandHelper(
            'minecraftSkinAtlas',
            'MeasureSettingsMinecraftSkinAtlasRun',
            'SettingsMinecraftSkinAtlasHelperArgs',
            methods.minecraftSkinAtlasHelperArguments(request),
            { loadKind = 'minecraftSkinAtlasRender', timeoutSeconds = 55 }
        )
    end

    function methods.stopMinecraftSkinAtlasProgress()
        methods.SetUpdateJob('atlasProgress', false)
        SKIN:Bang('!DisableMeasure', 'MeasureSettingsMinecraftSkinAtlasProgressName')
        SKIN:Bang('!DisableMeasure', 'MeasureSettingsMinecraftSkinAtlasProgress')
        setVariable('SettingsMinecraftSkinAtlasRequestToken', '')
        state.minecraftSkinAtlasLastProgress = -1
    end

    function methods.CaptureMinecraftSkinAtlasProgress()
        local request = state.pendingMinecraftSkinAtlasRequest
        if type(request) ~= 'table' or state.pendingLoadHelperRunning ~= true
            or trim(state.pendingLoadHelperKind or '') ~= 'minecraftSkinAtlas' then
            return false
        end
        local measure = SKIN:GetMeasure('MeasureSettingsMinecraftSkinAtlasProgressName')
        local fileName = measure and trim(measure:GetStringValue() or '') or ''
        local token, rawPercent = fileName:match('^MinecraftSkinAtlasProgress_(.-)_(%d%d%d)%.progress$')
        if trim(token or '') ~= trim(request.token or '') then
            return false
        end
        local percent = tonumber(rawPercent)
        if not percent or percent < 0 or percent > 100 or percent % 5 ~= 0
            or percent <= (tonumber(state.minecraftSkinAtlasLastProgress) or -1) then
            return false
        end
        state.minecraftSkinAtlasLastProgress = percent
        methods.setLoadingVisible(true, methods.minecraftSkinAtlasLoadingText(percent))
        SKIN:Bang('!UpdateMeter', 'MeterSettingsLoadingCover')
        SKIN:Bang('!UpdateMeter', 'MeterSettingsLoadingLabel')
        SKIN:Bang('!Redraw')
        return true
    end

    function methods.PollMinecraftSkinAtlasProgress()
        local request = state.pendingMinecraftSkinAtlasRequest
        if type(request) ~= 'table' or state.pendingLoadHelperRunning ~= true
            or trim(state.pendingLoadHelperKind or '') ~= 'minecraftSkinAtlas' then
            return false
        end
        -- FileView publishes its child result asynchronously. The parent's
        -- FinishAction updates the child and calls Capture... after the scan.
        SKIN:Bang('!CommandMeasure', 'MeasureSettingsMinecraftSkinAtlasProgress', 'Update')
        SKIN:Bang('!UpdateMeasure', 'MeasureSettingsMinecraftSkinAtlasProgress')
        return true
    end

    function methods.applyMinecraftSkinAtlasHelperResult(values)
        values = values or {}
        local request = state.pendingMinecraftSkinAtlasRequest
        if type(request) ~= 'table' then
            return false
        end
        local expectedToken = trim(request.token or '')
        local actualToken = trim(values.DMEL_REQUEST_TOKEN or '')
        if expectedToken == '' or actualToken ~= expectedToken then
            logNotice('Ignored stale Minecraft skin atlas completion: expectedToken=' .. expectedToken .. ' actualToken=' .. actualToken)
            return false
        end
        methods.stopMinecraftSkinAtlasProgress()
        local status = trim(values.DMEL_STATUS or ''):upper()
        local atlasPath = trim(values.DMEL_ATLASPATH or '')
        if status == 'OK' and atlasPath ~= '' then
            methods.persistMinecraftSkinAtlasState(atlasPath, true, true)
            local targetSet = {}
            if methods.syncInventoryPlayerSkinLiveState then
                methods.syncInventoryPlayerSkinLiveState(request.username, request.bodyPath, targetSet, {
                    verified = true,
                    texturePath = request.texturePath,
                    model = request.model,
                    atlasPath = atlasPath,
                    atlasVerified = true,
                    atlasManaged = true,
                })
            end
            methods.refreshTargets(targetSet)
            if methods.markMinecraftSkinPlayerFolderSizeDirty then
                methods.markMinecraftSkinPlayerFolderSizeDirty()
            end
            state.pendingMinecraftSkinAtlasRequest = nil
            state.pendingMinecraftSkinAtlasRetry = nil
            return true
        end

        return methods.failMinecraftSkinAtlasRequest(trim(values.DMEL_MESSAGE or ''))
    end

    function methods.failMinecraftSkinAtlasRequest(message)
        local request = state.pendingMinecraftSkinAtlasRequest
        if type(request) ~= 'table' then
            return false
        end
        methods.stopMinecraftSkinAtlasProgress()
        methods.persistMinecraftSkinAtlasState('', false, true)
        state.pendingMinecraftSkinAtlasRetry = {
            texturePath = request.texturePath,
            bodyPath = request.bodyPath,
            cacheKey = request.cacheKey,
            model = request.model,
            username = request.username,
            message = trim(message or ''),
        }
        state.pendingMinecraftSkinAtlasRequest = nil
        methods.RequestMinecraftSkinAtlasFailureModal()
        return true
    end

    function methods.RequestMinecraftSkinAtlasFailureModal()
        if type(state.pendingMinecraftSkinAtlasRetry) ~= 'table' then
            return false
        end
        if trim(SKIN:GetVariable('BlockHudSettingsVisible', '0')) ~= '1' then
            return true
        end
        if methods.PreloadModalAlert then
            methods.PreloadModalAlert()
        end
        SKIN:Bang('!SetVariable', 'BlockHudSettingsMinecraftAtlasModalDeferredOpen', '0')
        SKIN:Bang('!UpdateMeasure', 'MeasureSettingsMinecraftAtlasModalDeferredOpen')
        SKIN:Bang('!SetVariable', 'BlockHudSettingsMinecraftAtlasModalDeferredOpen', '1')
        SKIN:Bang('!UpdateMeasure', 'MeasureSettingsMinecraftAtlasModalDeferredOpen')
        return true
    end

    function methods.OpenPendingMinecraftSkinAtlasFailureModal()
        local retry = state.pendingMinecraftSkinAtlasRetry
        local modalConfig = modalConfigName()
        if type(retry) ~= 'table' or modalConfig == '' then
            return false
        end
        local token = methods.nextMinecraftSkinAtlasRequestToken()
        retry.modalToken = token
        local command = 'OpenConfirmByKeys('
            .. luaString(SKIN:GetVariable('CURRENTCONFIG', '')) .. ','
            .. luaString(token) .. ','
            .. luaString('Modal_MinecraftSkinAtlasFailed_Title') .. ','
            .. luaString('Modal_MinecraftSkinAtlasFailed_Message') .. ','
            .. luaString('Common_Retry') .. ','
            .. luaString('Common_Close') .. ','
            .. luaString('MeasureSettingsCommit') .. ','
            .. luaString('RetryMinecraftSkinAtlas') .. ','
            .. luaString('CloseMinecraftSkinAtlasFailure') .. ')'
        SKIN:Bang('!CommandMeasure', 'MeasureModal', command, modalConfig)
        return true
    end

    function methods.RetryMinecraftSkinAtlas(token)
        local retry = state.pendingMinecraftSkinAtlasRetry
        if type(retry) ~= 'table' or trim(retry.modalToken or '') ~= trim(token or '') then
            return false
        end
        state.pendingMinecraftSkinAtlasRetry = nil
        retry.modalToken = nil
        return methods.beginMinecraftSkinAtlasStage(retry)
    end

    function methods.CloseMinecraftSkinAtlasFailure(token)
        local retry = state.pendingMinecraftSkinAtlasRetry
        if type(retry) ~= 'table' or trim(retry.modalToken or '') ~= trim(token or '') then
            return false
        end
        state.pendingMinecraftSkinAtlasRetry = nil
        methods.renderActivePage()
        return true
    end

    function methods.showMinecraftSkinBodyOnlyNotice()
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(
                'warn',
                'ModalAlert_MinecraftSkinBodyOnly',
                'A 64x64 skin image must be attached to generate the cursor animation atlas. The attached image is currently shown as a static image only.'
            )
        end
    end
end
