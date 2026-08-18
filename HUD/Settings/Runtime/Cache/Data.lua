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
    function methods.defaultDriveTargets(field)

        local drives = {}

        local currentTarget = trim(methods.currentDiskTargetForField(field))

        if currentTarget ~= '' then

            drives[#drives + 1] = currentTarget

        end

        if #drives == 0 then

            local expTargetField = methods.getField('expDiskTarget')

            local expTarget = expTargetField and trim(methods.readFieldValue(expTargetField)) or ''

            if expTarget ~= '' then

                drives[#drives + 1] = expTarget

            end

        end

        if #drives == 0 then

            drives[#drives + 1] = 'C:'

        end

        return drives

    end

    function methods.loadInstalledDriveTargets(field)

        local hadDriveTargets = methods.cachedListHasEntries(state.installedDriveTargets)

        local values = methods.runComputerInfoHelper({ includeDrives = true, tag = 'drives' })

        local drives = methods.splitCachedList(values.DMEL_DRIVETARGETS or '')

        if #drives > 0 then

            methods.setInstalledDriveTargetList(drives)

            return state.installedDriveTargets or {}

        end

        if hadDriveTargets then

            return state.installedDriveTargets or {}

        end

        if methods.RestorePersistentCache('driveTargets') then

            return state.installedDriveTargets or {}

        end

        methods.setInstalledDriveTargetList(methods.defaultDriveTargets(field))

        return state.installedDriveTargets or {}

    end

    function methods.resourceFontsPath()

        methods.ensurePaths()

        return state.resourcesRoot .. 'Fonts'

    end

    function methods.loadBundledFontFaces(field)

        local hadBundledFonts = methods.cachedListHasEntries(state.bundledFontFaces)

        local values = methods.runComputerInfoHelper({ includeFonts = true, tag = 'fonts' })

        local fontFaces = methods.splitCachedList(values.DMEL_FONTFAMILIES or '')

        if #fontFaces > 0 then

            methods.setBundledFontFaces(fontFaces)

            return state.bundledFontFaceSet or {}

        end

        if hadBundledFonts then

            return state.bundledFontFaceSet or {}

        end

        if methods.RestorePersistentCache('fontFamily') then

            return state.bundledFontFaceSet or {}

        end

        methods.setBundledFontFaces({})

        return state.bundledFontFaceSet or {}

    end

    function methods.loadComputerInfoCaches(driveField)

        local values = methods.runComputerInfoHelper({

            includeFonts = true,

            includeDrives = true,

            includeStartupAutoRun = true,

            tag = 'computer_info',

        })

        local fontFaces = methods.splitCachedList(values.DMEL_FONTFAMILIES or '')

        if #fontFaces > 0 then

            methods.setBundledFontFaces(fontFaces)

        elseif not methods.cachedListHasEntries(state.bundledFontFaces) and not methods.RestorePersistentCache('fontFamily') then

            methods.setBundledFontFaces({})

        end

        local drives = methods.splitCachedList(values.DMEL_DRIVETARGETS or '')

        if #drives > 0 then

            methods.setInstalledDriveTargetList(drives)

        elseif not methods.cachedListHasEntries(state.installedDriveTargets) and not methods.RestorePersistentCache('driveTargets') then

            methods.setInstalledDriveTargetList(methods.defaultDriveTargets(driveField))

        end

        methods.applyComputerInfoStartupAutoRunLiteral(
            values.DMEL_STARTUPAUTORUN or '',
            values.DMEL_STARTUPFASTAUTORUN or '')

        return values

    end

    function methods.persistPersistentCache(kind)

        if kind == 'fontFamily' then

            methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)

            methods.writePersistentCacheVariable('SettingsPersistentCacheFontsLoaded', methods.cachedListHasEntries(state.bundledFontFaces) and '1' or '0')

            methods.writePersistentCacheVariable('SettingsPersistentCacheFontFamilies', methods.joinCachedList(state.bundledFontFaces or {}))

            return

        end

        if kind == 'driveTargets' then

            methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)

            methods.writePersistentCacheVariable('SettingsPersistentCacheDrivesLoaded', methods.cachedListHasEntries(state.installedDriveTargets) and '1' or '0')

            methods.writePersistentCacheVariable('SettingsPersistentCacheDriveTargets', methods.joinCachedList(state.installedDriveTargets or {}))

            return

        end

        if kind == 'computerInfo' then

            methods.persistPersistentCache('fontFamily')

            methods.persistPersistentCache('driveTargets')

        end

    end

    function methods.RestorePersistentCache(kind)

        local version = methods.readPersistentCacheVariable('SettingsPersistentCacheFormatVersion', '')

        if version ~= state.cacheFormatVersion then

            return false

        end

        if kind == 'fontFamily' then

            if methods.readPersistentCacheVariable('SettingsPersistentCacheFontsLoaded', '0') ~= '1' then

                return false

            end

            methods.setBundledFontFaces(methods.splitCachedList(methods.readPersistentCacheVariable('SettingsPersistentCacheFontFamilies', '')))

            return state.bundledFontFaces ~= nil and #state.bundledFontFaces > 0

        end

        if kind == 'driveTargets' then

            if methods.readPersistentCacheVariable('SettingsPersistentCacheDrivesLoaded', '0') ~= '1' then

                return false

            end

            methods.setInstalledDriveTargetList(methods.splitCachedList(methods.readPersistentCacheVariable('SettingsPersistentCacheDriveTargets', '')))

            return state.installedDriveTargets ~= nil and #state.installedDriveTargets > 0

        end

        if kind == 'computerInfo' then

            if not methods.RestorePersistentCache('fontFamily') then

                return false

            end

            if not methods.RestorePersistentCache('driveTargets') then

                return false

            end

            return methods.startupAutoRunCacheInitialized()

        end

        return false

    end

    function methods.ScheduleDropdownDataLoad(fieldKey, rowIndex, forcedKind, reopenAfterLoad, options)

        options = options or {}

        local field = methods.getField(fieldKey)

        if not field then

            return false

        end

        if state.pendingLoadSilent == true and state.pendingLoadHelperRunning == true then
            return false
        end

        if not forcedKind and not methods.hasDropdown(field) then

            return false

        end

        local kind = forcedKind or (field.dropdownId == 'fontFamily' and 'fontFamily' or 'driveTargets')

        methods.closeDropdownInternal()

        methods.clearPendingLoadState()

        state.pendingLoadKind = kind

        state.pendingLoadFieldKey = fieldKey

        state.pendingLoadRowIndex = tonumber(rowIndex) or 0

        state.pendingLoadDelayTicksRemaining = math.max(0, tonumber(options.delayTicks) or 1)

        state.pendingLoadReopenDropdown = reopenAfterLoad ~= false

        state.pendingLoadSilent = options.silent == true

        state.pendingLoadValue = options.pendingValue
        state.pendingLoadStartupMethod = options.startupMethod
        state.pendingStartupAutoRunRequestToken = trim(options.requestToken or '')
        state.pendingStartupAutoRunRecoveryAttempted = false
        state.pendingStartupAutoRunFailure = nil
        state.pendingLoadTexturePath = options.pendingTexturePath
        state.pendingLoadUsername = options.pendingUsername

        state.pendingLoadBeforeSnapshot = options.beforeSnapshot

        state.pendingLoadHistoryLabel = options.historyLabel

        setVariable('SettingsPendingLoadKind', kind)

        setVariable('SettingsPendingLoadFieldKey', fieldKey)

        setVariable('SettingsPendingLoadRowIndex', tostring(state.pendingLoadRowIndex))

        if state.pendingLoadSilent ~= true then
            methods.setLoadingVisible(true, options.loadingText)
            methods.renderActivePage()
        end

        methods.SetUpdateJob('deferredLoad', true)

        return true

    end

    function methods.ScheduleStartupAutoRunStateProbe(options)
        options = options or {}
        if trim(state.pendingLoadKind or '') ~= '' or state.pendingLoadHelperRunning == true then
            return false
        end
        return methods.ScheduleDropdownDataLoad('startupAutoRun', 0, 'startupAutoRunProbe', false, {
            delayTicks = options.delayTicks or 0,
            silent = true,
        })
    end

    function methods.CancelPendingLoad()

        if state.pendingLoadHelperRunning == true then
            local activeLoadKind = trim(state.pendingLoadHelperLoadKind or state.pendingLoadKind or '')
            methods.clearPendingLoadState({
                abandonActiveHelperReason = 'canceled',
                clearIgnoredHelper = false,
            })
        else
            methods.clearPendingLoadState()
        end

        methods.setLoadingVisible(false)

        methods.renderActivePage()

        return true

    end

    function methods.applyInstalledDriveTargetsFromValues(field, values)

        local hadDriveTargets = methods.cachedListHasEntries(state.installedDriveTargets)

        local drives = methods.splitCachedList(values.DMEL_DRIVETARGETS or '')

        if #drives > 0 then

            methods.setInstalledDriveTargetList(drives)

            return state.installedDriveTargets or {}

        end

        if hadDriveTargets then

            return state.installedDriveTargets or {}

        end

        if methods.RestorePersistentCache('driveTargets') then

            return state.installedDriveTargets or {}

        end

        methods.setInstalledDriveTargetList(methods.defaultDriveTargets(field))

        return state.installedDriveTargets or {}

    end

    function methods.applyBundledFontFacesFromValues(field, values)

        local hadBundledFonts = methods.cachedListHasEntries(state.bundledFontFaces)

        local fontFaces = methods.splitCachedList(values.DMEL_FONTFAMILIES or '')

        if #fontFaces > 0 then

            methods.setBundledFontFaces(fontFaces)

            return state.bundledFontFaceSet or {}

        end

        if hadBundledFonts then

            return state.bundledFontFaceSet or {}

        end

        if methods.RestorePersistentCache('fontFamily') then

            return state.bundledFontFaceSet or {}

        end

        methods.setBundledFontFaces({})

        return state.bundledFontFaceSet or {}

    end

    function methods.applyComputerInfoCachesFromValues(driveField, values)

        methods.applyBundledFontFacesFromValues(nil, values)

        methods.applyInstalledDriveTargetsFromValues(driveField, values)

        methods.applyComputerInfoStartupAutoRunLiteral(
            values.DMEL_STARTUPAUTORUN or '',
            values.DMEL_STARTUPFASTAUTORUN or '')

        return values

    end

    function methods.applyStartupAutoRunProbeOutput(output)
        local current = methods.currentStartupAutoRunState()
        local result = parseStartupAutoRunResult(output, current)
        if not result.hasLiteral or not result.hasFastLiteral then
            logNotice('Startup auto-run probe returned an incomplete state bundle.')
            return current
        end

        return methods.applyStartupAutoRunState(result.literal, result.fastLiteral) or current

    end

    local function showStartupAutoRunAlert(messageKey, fallback, severity)
        if methods.ShowModalAlertByKeys then
            methods.ShowModalAlertByKeys(severity or 'warn', messageKey, fallback)
        end
    end

    function methods.beginStartupAutoRunRecoveryProbe(failure, reason)
        if state.pendingStartupAutoRunRecoveryAttempted == true then
            return false
        end

        state.pendingStartupAutoRunRecoveryAttempted = true
        state.pendingStartupAutoRunFailure = {
            code = trim(type(failure) == 'table' and failure.code or ''),
            recovery = trim(type(failure) == 'table' and failure.recovery or ''),
            recoveryCode = trim(type(failure) == 'table' and failure.recoveryCode or ''),
            reason = trim(reason or ''),
            requestedMethod = trim(state.pendingLoadStartupMethod or ''),
            requestedValue = trim(state.pendingLoadValue or ''),
        }
        state.pendingLoadKind = 'startupAutoRunRecoveryProbe'
        state.pendingLoadValue = nil
        state.pendingLoadStartupMethod = 'all'
        state.pendingLoadDelayTicksRemaining = 1
        state.pendingStartupAutoRunRequestToken = methods.nextStartupAutoRunRequestToken()
        setVariable('SettingsPendingLoadKind', state.pendingLoadKind)
        methods.clearPendingLoadHelperState()
        methods.setLoadingVisible(
            true,
            methods.localize(
                'Settings_Loading_StartupVerify',
                'Checking the actual Windows startup state...\nPlease wait.'
            )
        )
        methods.SetUpdateJob('deferredLoad', true)
        methods.renderActivePage()
        return true
    end

    function methods.applyStartupAutoRunApplyOutput(output, field)
        local previous = methods.currentStartupAutoRunState()
        local result = parseStartupAutoRunResult(output, previous)
        local hasActualState = result.hasLiteral and result.hasFastLiteral
        local succeeded = result.status == 'OK' and hasActualState

        if not succeeded then
            logNotice(
                'Startup auto-run helper failed: status='
                    .. result.status
                    .. ' code='
                    .. result.code
                    .. ' hasLiteral='
                    .. tostring(hasActualState)
                    .. ' recovery='
                    .. tostring(result.recovery)
                    .. ' recoveryCode='
                    .. tostring(result.recoveryCode)
            )
        end

        if hasActualState then
            methods.applyStartupAutoRunState(result.literal, result.fastLiteral, { force = true })
        end

        if succeeded then
            return {
                result = result,
                hasActualState = true,
                requiresProbe = false,
            }
        end

        if not hasActualState then
            return {
                result = result,
                hasActualState = false,
                requiresProbe = true,
            }
        end

        if trim(state.pendingLoadStartupMethod or '') == 'task' and result.recovery == 'shortcut'
            and result.literal == '1' and result.fastLiteral == '0' then
            showStartupAutoRunAlert(
                'ModalAlert_StartupFastAutoRunRecovered',
                'Fast startup could not be enabled because Windows policy, security software, or Task Scheduler blocked the change. Standard startup will continue to be used.',
                'warn'
            )
        elseif trim(state.pendingLoadStartupMethod or '') == 'task'
            and (result.recovery == 'partial' or result.recovery == 'failed') then
            showStartupAutoRunAlert(
                'ModalAlert_StartupFastAutoRunPartial',
                'Fast startup could not be enabled and the Windows startup state was only partially recovered. Check Startup Apps and Task Scheduler before trying again.',
                'error'
            )
        else
            showStartupAutoRunAlert(
                'ModalAlert_StartupAutoRunFailed',
                'The startup-program setting result could not be confirmed. The setting may not have been applied.',
                'error'
            )
        end

        return {
            result = result,
            hasActualState = true,
            requiresProbe = false,
        }
    end

    function methods.applyStartupAutoRunRecoveryProbeOutput(output)
        local previous = methods.currentStartupAutoRunState()
        local result = parseStartupAutoRunResult(output, previous)
        local hasActualState = result.hasLiteral and result.hasFastLiteral
        local failure = type(state.pendingStartupAutoRunFailure) == 'table'
            and state.pendingStartupAutoRunFailure
            or {}
        local requestedMethod = trim(failure.requestedMethod or '')
        local requestedValue = trim(failure.requestedValue or '')
        local reachedRequestedState = false
        if hasActualState and result.hasShortcutLiteral then
            if requestedMethod == 'task' then
                reachedRequestedState = result.literal == '1'
                    and result.fastLiteral == '1'
                    and result.shortcutLiteral == '0'
            elseif requestedMethod == 'shortcut' then
                reachedRequestedState = result.literal == '1'
                    and result.fastLiteral == '0'
                    and result.shortcutLiteral == '1'
            elseif requestedMethod == 'all' and requestedValue == '0' then
                reachedRequestedState = result.literal == '0'
                    and result.fastLiteral == '0'
                    and result.shortcutLiteral == '0'
            end
        end

        if hasActualState then
            methods.applyStartupAutoRunState(result.literal, result.fastLiteral, { force = true })
        end

        logNotice(
            'Startup auto-run recovery probe completed: status='
                .. tostring(result.status)
                .. ' hasLiteral='
                .. tostring(hasActualState)
                .. ' originalCode='
                .. tostring(failure.code or '')
                .. ' reason='
                .. tostring(failure.reason or '')
        )

        if reachedRequestedState then
            return {
                result = result,
                hasActualState = true,
                reachedRequestedState = true,
            }
        elseif requestedMethod ~= 'task' then
            showStartupAutoRunAlert(
                'ModalAlert_StartupAutoRunFailed',
                'The startup-program setting result could not be confirmed. The setting may not have been applied.',
                'error'
            )
        elseif hasActualState
            and result.literal == '1'
            and result.fastLiteral == '0'
            and result.shortcutLiteral == '1' then
            showStartupAutoRunAlert(
                'ModalAlert_StartupFastAutoRunRecovered',
                'Fast startup could not be enabled because Windows policy, security software, or Task Scheduler blocked the change. Standard startup will continue to be used.',
                'warn'
            )
        elseif hasActualState then
            showStartupAutoRunAlert(
                'ModalAlert_StartupFastAutoRunPartial',
                'Fast startup could not be enabled and the Windows startup state was only partially recovered. Check Startup Apps and Task Scheduler before trying again.',
                'error'
            )
        else
            showStartupAutoRunAlert(
                'ModalAlert_StartupFastAutoRunUnconfirmed',
                'The actual Windows startup state could not be confirmed. No additional changes were attempted; check Startup Apps and Task Scheduler before trying again.',
                'error'
            )
        end

        return {
            result = result,
            hasActualState = hasActualState,
        }
    end
end
