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
    function methods.handleOpenVersionManagerHelperResult(values, options)
        options = options or {}
        local allowFailureModal = options.allowFailureModal == true
        local resultScope = allowFailureModal and 'current request' or 'stale request'
        local status = string.upper(trim(values.DMEL_STATUS or ''))
        local logPath = trim(values.DMEL_LOGPATH or '')
        local message = trim(values.DMEL_MESSAGE or '')

        if status == 'OK' or status == 'CANCEL' then
            if allowFailureModal and methods.clearVersionManagerLaunchPending then
                methods.clearVersionManagerLaunchPending()
            end
            if not allowFailureModal then
                logNotice('Ignored stale Version manager completion: ' .. string.lower(status))
            end
            return
        end

        if status == 'WARN' then
            local details = {}
            if message ~= '' then
                details[#details + 1] = message
            end
            if logPath ~= '' then
                details[#details + 1] = 'log=' .. logPath
            end
            if #details == 0 then
                details[#details + 1] = 'Version manager launch confirmation timed out.'
            end
            logNotice('Version manager warning (' .. resultScope .. '): ' .. table.concat(details, ' | '))
            -- The launcher has started; keep the Settings watchdog pending so
            -- slower packaged installs can still report the eventual shown/error state.
            return
        end

        if allowFailureModal and methods.clearVersionManagerLaunchPending then
            methods.clearVersionManagerLaunchPending()
        end

        local details = {}
        if message ~= '' then
            details[#details + 1] = message
        end
        if logPath ~= '' then
            details[#details + 1] = 'log=' .. logPath
        end
        if #details == 0 then
            details[#details + 1] = 'Version manager failed.'
        end
        if status == '' then
            status = 'ERROR'
            details[#details + 1] = 'missing DMEL_STATUS output'
        end

        logNotice('Version manager ' .. string.lower(status) .. ' (' .. resultScope .. '): ' .. table.concat(details, ' | '))
        if allowFailureModal then
            showModalAlert(
                'error',
                'ModalAlert_VersionManagerFailed',
                'Skins could not be opened from Settings. Refresh the skin and try again.',
                logPath
            )
        end
    end

    function methods.handleOpenLogFolderHelperResult(values)
        local status = string.upper(trim(values.DMEL_STATUS or ''))
        local logPath = trim(values.DMEL_LOGPATH or '')
        local message = trim(values.DMEL_MESSAGE or '')

        if status == 'OK' then
            return
        end

        local details = {}

        if message ~= '' then
            details[#details + 1] = message
        end
        if logPath ~= '' then
            details[#details + 1] = 'log=' .. logPath
        end

        if status == '' then
            status = 'ERROR'
            details[#details + 1] = 'missing DMEL_STATUS output'
        end

        if #details == 0 then
            details[#details + 1] = 'Log folder open failed.'
        end

        logNotice('Log folder open ' .. string.lower(status) .. ': ' .. table.concat(details, ' | '))
    end

    function methods.finishPendingLoadCycle()

        local reopenFieldKey = state.pendingLoadFieldKey

        local reopenRowIndex = state.pendingLoadRowIndex

        local shouldReopenDropdown = state.pendingLoadReopenDropdown

        local wasSilent = state.pendingLoadSilent == true

        methods.clearPendingLoadState()

        if not wasSilent then
            methods.setLoadingVisible(false)
        end

        local reopenField = methods.getField(reopenFieldKey)

        if shouldReopenDropdown and reopenField and methods.hasDropdown(reopenField) and state.currentVisibleRows[reopenFieldKey] then

            state.activeDropdownFieldKey = reopenFieldKey

            state.activeDropdownRowIndex = state.currentVisibleRows[reopenFieldKey] or reopenRowIndex or 0

            state.activeDropdownPageIndex = methods.optionPageForValue(reopenField, methods.readFieldValue(reopenField))

        end

        methods.renderActivePage()

    end

    function methods.HandleHelperComplete(helperKind)
        if state.pendingLoadHelperRunning ~= true then
            if methods.handleIgnoredPendingLoadHelperCompletion(helperKind) then
                return
            end
            return
        end
        if trim(state.pendingLoadHelperKind or '') ~= trim(helperKind or '') then
            if methods.handleIgnoredPendingLoadHelperCompletion(helperKind) then
                return
            end
            return
        end
        local loadKind = state.pendingLoadKind
        local field = methods.getField(state.pendingLoadFieldKey)
        local output = methods.runCommandMeasureOutput(state.pendingLoadHelperMeasureName)
        local values = methods.parseCommandCaptureVariables(output)
        local shouldFinishLoadCycle = true
        if loadKind == 'startupAutoRunApply' or loadKind == 'startupAutoRunRecoveryProbe' then
            local startupResult = parseStartupAutoRunResult(output, methods.currentStartupAutoRunState())
            local expectedToken = trim(state.pendingStartupAutoRunRequestToken or '')
            if expectedToken ~= ''
                and startupResult.requestToken ~= ''
                and startupResult.requestToken ~= expectedToken then
                logNotice(
                    'Ignored stale startup auto-run helper completion: expectedToken='
                        .. expectedToken
                        .. ' actualToken='
                        .. startupResult.requestToken
                )
                return
            end
        end
        if loadKind == 'fontFamily' then
            methods.applyBundledFontFacesFromValues(field, values)
            if not state.bundledFontFaces or #state.bundledFontFaces == 0 then
                methods.setBundledFontFaces({})
                logNotice('Settings UI bundled font scan returned no resource fonts.')
            end
            methods.persistPersistentCache('fontFamily')
        elseif loadKind == 'driveTargets' then
            methods.applyInstalledDriveTargetsFromValues(field, values)
            if not state.installedDriveTargets or #state.installedDriveTargets == 0 then
                methods.setInstalledDriveTargetList(methods.defaultDriveTargets(field))
                logNotice('Settings UI drive load fallback applied.')
            end
            methods.persistPersistentCache('driveTargets')
        elseif loadKind == 'computerInfo' then
            local driveField = methods.getField('expSource') or methods.getField('healthSource')
            methods.applyComputerInfoCachesFromValues(driveField, values)
            if not state.bundledFontFaces or #state.bundledFontFaces == 0 then
                methods.setBundledFontFaces({})
                logNotice('Settings UI bundled font scan returned no resource fonts.')
            end
            if not state.installedDriveTargets or #state.installedDriveTargets == 0 then
                methods.setInstalledDriveTargetList(methods.defaultDriveTargets(driveField))
                logNotice('Settings UI drive load fallback applied.')
            end
            if state.pendingLoadFieldKey == 'refreshComputerInfo'
                and methods.ShowModalAlertByKeys
                and ((not state.bundledFontFaces or #state.bundledFontFaces == 0)
                    or (not state.installedDriveTargets or #state.installedDriveTargets == 0)) then
                methods.ShowModalAlertByKeys(
                    'warn',
                    'ModalAlert_ComputerInfoUnavailable',
                    'Some computer information could not be loaded, so default options are being shown.'
                )
            end
            methods.persistPersistentCache('computerInfo')
            if state.pendingLoadFieldKey == 'startupAutoRun' then
                methods.captureBaselineState()
            end
        elseif loadKind == 'startupAutoRunProbe' then
            methods.applyStartupAutoRunProbeOutput(output)
            methods.captureBaselineState()
        elseif loadKind == 'startupAutoRunApply' then
            local applyResult = methods.applyStartupAutoRunApplyOutput(output, field)
            if type(applyResult) == 'table' and applyResult.requiresProbe == true then
                shouldFinishLoadCycle = not methods.beginStartupAutoRunRecoveryProbe(
                    applyResult.result,
                    'incomplete-helper-result'
                )
            end
        elseif loadKind == 'startupAutoRunRecoveryProbe' then
            methods.applyStartupAutoRunRecoveryProbeOutput(output)
        elseif loadKind == 'minecraftSkinApply' then
            shouldFinishLoadCycle = not methods.applyMinecraftSkinFetchResult({
                status = trim(values.DMEL_STATUS or ''),
                username = trim(values.DMEL_USERNAME or ''),
                imagePath = trim(values.DMEL_IMAGEPATH or ''),
                texturePath = trim(values.DMEL_TEXTUREPATH or ''),
                model = trim(values.DMEL_MODEL or ''),
                cacheKey = trim(values.DMEL_CACHEKEY or ''),
                atlasPath = trim(values.DMEL_ATLASPATH or ''),
                atlasReady = trim(values.DMEL_ATLASREADY or ''),
                atlasRequired = trim(values.DMEL_ATLAS_REQUIRED or ''),
                message = trim(values.DMEL_MESSAGE or ''),
                logPath = trim(values.DMEL_LOGPATH or values.DMEL_DEBUGLOG or ''),
            })
        elseif loadKind == 'minecraftSkinFileAttach' then
            shouldFinishLoadCycle = not methods.applyMinecraftSkinFileAttachResult({
                status = trim(values.DMEL_STATUS or ''),
                username = trim(values.DMEL_USERNAME or ''),
                imagePath = trim(values.DMEL_IMAGEPATH or ''),
                texturePath = trim(values.DMEL_TEXTUREPATH or ''),
                model = trim(values.DMEL_MODEL or ''),
                cacheKey = trim(values.DMEL_CACHEKEY or ''),
                atlasPath = trim(values.DMEL_ATLASPATH or ''),
                atlasReady = trim(values.DMEL_ATLASREADY or ''),
                atlasRequired = trim(values.DMEL_ATLAS_REQUIRED or ''),
                message = trim(values.DMEL_MESSAGE or ''),
                logPath = trim(values.DMEL_LOGPATH or ''),
            })
        elseif loadKind == 'minecraftSkinModelRender' then
            shouldFinishLoadCycle = not methods.applyMinecraftSkinTextureRenderResult({
                status = trim(values.DMEL_STATUS or ''),
                username = trim(values.DMEL_USERNAME or state.pendingLoadUsername or ''),
                imagePath = trim(values.DMEL_IMAGEPATH or ''),
                texturePath = trim(values.DMEL_TEXTUREPATH or state.pendingLoadTexturePath or ''),
                model = trim(values.DMEL_MODEL or state.pendingLoadValue or ''),
                cacheKey = trim(values.DMEL_CACHEKEY or ''),
                atlasPath = trim(values.DMEL_ATLASPATH or ''),
                atlasReady = trim(values.DMEL_ATLASREADY or ''),
                atlasRequired = trim(values.DMEL_ATLAS_REQUIRED or ''),
                message = trim(values.DMEL_MESSAGE or ''),
                logPath = trim(values.DMEL_LOGPATH or values.DMEL_DEBUGLOG or ''),
            })
        elseif loadKind == 'minecraftSkinAtlasRender' then
            shouldFinishLoadCycle = methods.applyMinecraftSkinAtlasHelperResult(values) ~= false
        end
        if shouldFinishLoadCycle ~= false then
            methods.finishPendingLoadCycle()
        end
    end

    function methods.HandleDetachedHelperComplete(helperKind)
        local resolvedKind = trim(helperKind or '')
        state.detachedHelperMeasures = state.detachedHelperMeasures or {}
        state.detachedHelperTokens = state.detachedHelperTokens or {}
        local measureName = trim(state.detachedHelperMeasures[resolvedKind] or '')
        local launchToken = trim(state.detachedHelperTokens[resolvedKind] or '')
        if measureName == '' then
            if state.detachedHelperRunning ~= true then
                return
            end
            if trim(state.detachedHelperKind or '') ~= resolvedKind then
                return
            end
            measureName = trim(state.detachedHelperMeasureName or '')
            launchToken = trim(state.detachedHelperLaunchToken or '')
        end

        if measureName == '' then
            methods.clearDetachedHelperState(resolvedKind)
            return
        end

        local output = methods.runCommandMeasureOutput(measureName)
        local values = methods.parseCommandCaptureVariables(output)

        if resolvedKind == 'openLogFolder' then
            methods.handleOpenLogFolderHelperResult(values)
        elseif resolvedKind == 'openVersionManager' then
            local currentLaunchToken = trim(state.versionManagerLaunchToken or '')
            local allowFailureModal = state.versionManagerLaunchPending == true
                and launchToken ~= ''
                and currentLaunchToken ~= ''
                and launchToken == currentLaunchToken
            methods.handleOpenVersionManagerHelperResult(values, {
                allowFailureModal = allowFailureModal,
                launchToken = launchToken,
            })
        end

        methods.clearDetachedHelperState(resolvedKind)
    end
end
