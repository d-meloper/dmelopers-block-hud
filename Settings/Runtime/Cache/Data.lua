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

        methods.applyComputerInfoStartupAutoRunLiteral(values.DMEL_STARTUPAUTORUN or '')

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

            return

        end

        if not forcedKind and not methods.hasDropdown(field) then

            return

        end

        local kind = forcedKind or (field.dropdownId == 'fontFamily' and 'fontFamily' or 'driveTargets')

        methods.closeDropdownInternal()

        methods.clearPendingLoadState()

        state.pendingLoadKind = kind

        state.pendingLoadFieldKey = fieldKey

        state.pendingLoadRowIndex = tonumber(rowIndex) or 0

        state.pendingLoadDelayTicksRemaining = math.max(0, tonumber(options.delayTicks) or 1)

        state.pendingLoadReopenDropdown = reopenAfterLoad ~= false

        state.pendingLoadValue = options.pendingValue
        state.pendingLoadTexturePath = options.pendingTexturePath
        state.pendingLoadUsername = options.pendingUsername

        state.pendingLoadBeforeSnapshot = options.beforeSnapshot

        state.pendingLoadHistoryLabel = options.historyLabel

        setVariable('SettingsPendingLoadKind', kind)

        setVariable('SettingsPendingLoadFieldKey', fieldKey)

        setVariable('SettingsPendingLoadRowIndex', tostring(state.pendingLoadRowIndex))

        methods.setLoadingVisible(true, options.loadingText)

        methods.renderActivePage()

        methods.SetUpdateJob('deferredLoad', true)

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

        methods.applyComputerInfoStartupAutoRunLiteral(values.DMEL_STARTUPAUTORUN or '')

        return values

    end

    function methods.applyStartupAutoRunProbeOutput(output)

        local field = methods.getField('startupAutoRun')

        if not field then

            return '0'

        end

        local currentLiteral = methods.normalizeToggleValue(methods.readFieldValue(field))

        local result = parseStartupAutoRunResult(output, currentLiteral)
        local actualLiteral = methods.normalizeToggleValue(result.literal)

        methods.persistStartupAutoRunCache(actualLiteral)

        methods.setFieldSessionValue(field, actualLiteral)

        methods.persistStartupAutoRunSetting(actualLiteral, { currentLiteral = currentLiteral })

        return actualLiteral

    end

    function methods.applyStartupAutoRunApplyOutput(output, field)

        local previousLiteral = field and methods.readFieldValue(field) or '0'
        local result = parseStartupAutoRunResult(output, previousLiteral)
        local succeeded = result.status == 'OK' and result.hasLiteral
        local actualLiteral = methods.normalizeToggleValue(result.literal)

        if not succeeded then
            logNotice(
                'Startup auto-run helper failed: status='
                    .. result.status
                    .. ' code='
                    .. result.code
                    .. ' hasLiteral='
                    .. tostring(result.hasLiteral)
            )
            if methods.ShowModalAlertByKeys then
                methods.ShowModalAlertByKeys(
                    'error',
                    'ModalAlert_StartupAutoRunFailed',
                    'The startup-program setting result could not be confirmed. The setting may not have been applied.'
                )
            end
        end

        methods.persistStartupAutoRunCache(actualLiteral)

        if field then

            methods.setFieldSessionValue(field, actualLiteral)

        end

        methods.persistStartupAutoRunSetting(actualLiteral, { force = true, currentLiteral = previousLiteral })

        if succeeded and state.pendingLoadBeforeSnapshot and field then

            methods.pushHistory(state.pendingLoadHistoryLabel or field.historyLabel, state.pendingLoadBeforeSnapshot, {

                afterSnapshot = methods.captureSnapshot(),

            })

        end

        return actualLiteral

    end
end
