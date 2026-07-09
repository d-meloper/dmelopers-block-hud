return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    function methods.liveWindowPositionForTargetId(targetId, fallbackRects)

        methods.ensurePaths()

        local target = schema.refreshTargetsByName[targetId]

        if not target or state.rootConfig == '' then

            return nil

        end

        local core = methods.responsiveLayoutCore()

        if core and core.LiveWindowPositionForId then

            return core.LiveWindowPositionForId(SKIN, targetId, fallbackRects)

        end

        local fallback = fallbackRects and fallbackRects[targetId]

        if fallback then

            return { x = fallback.x, y = fallback.y }

        end

        return nil

    end



    function methods.captureFixedPositionsForIds(ids)

        local core = methods.responsiveLayoutCore()

        local rects = core.ResolveRects(SKIN)

        local positionsById = {}

        for _, id in ipairs(ids or {}) do

            local position = methods.liveWindowPositionForTargetId(id, rects)

            if position then

                positionsById[id] = position

            end

        end

        core.CaptureFixedPositionsForIds(SKIN, ids, positionsById)

    end



    function methods.ResetTabPositionsToDefaults(tabId)

        local ids = methods.layoutTargetIdsForTab(tabId)

        if #ids == 0 then

            return false

        end

        local core = methods.responsiveLayoutCore()

        core.ResetStateIds(SKIN, ids)

        methods.reflowLayoutTargetIds(ids, { forceRefresh = true })

        return true

    end



    function methods.ResetAllSkinPositions()

        local ids = methods.allLayoutTargetIds()

        if #ids == 0 then

            return false

        end

        local core = methods.responsiveLayoutCore()

        core.ResetStateIds(SKIN, ids)

        methods.reflowLayoutTargetIds(ids, { forceRefresh = true })

        return true

    end



    function methods.ResetTabToDefaults(tabId, historyLabel, options)

        options = options or {}

        local fieldKeys = methods.resetFieldKeysForTab(tabId)

        local defaultSnapshot, missingKeys = methods.loadDefaultSnapshot(fieldKeys)

        if not defaultSnapshot then

            logNotice('Settings default snapshot is incomplete for tab reset: ' .. table.concat(missingKeys or {}, ', '))
            if methods.ShowModalAlertByKeys then
                methods.ShowModalAlertByKeys(
                    'error',
                    'ModalAlert_SettingsDefaultsUnavailable',
                    'Reset to defaults was canceled because the default data could not be read.'
                )
            end

            return false

        end

        local beforeSnapshot = methods.captureSnapshot()

        local targets = {}

        for _, fieldKey in ipairs(fieldKeys) do

            local field = methods.getField(fieldKey)

            local desired = defaultSnapshot[fieldKey]

            if field and field.controlType ~= 'action' and desired ~= nil then

                methods.applyFieldValue(field, desired, { targetSet = targets })

            end

        end

        local afterSnapshot = methods.captureSnapshot()

        local changed = app.snapshotSignature(beforeSnapshot) ~= app.snapshotSignature(afterSnapshot)

        if not changed then

            return false

        end

        methods.refreshTargets(targets)

        if not options.suppressHistory then

            methods.pushHistory(historyLabel, beforeSnapshot, { afterSnapshot = afterSnapshot })

        end

        return true

    end



    function methods.pushHistory(label, beforeSnapshot, options)

        options = options or {}

        local afterSnapshot = options.afterSnapshot or methods.captureSnapshot()

        local beforeLayout = options.beforeLayout

        local afterLayout = options.afterLayout

        local snapshotChanged = app.snapshotSignature(beforeSnapshot) ~= app.snapshotSignature(afterSnapshot)

        local layoutChanged = false

        if beforeLayout or afterLayout then

            layoutChanged = methods.layoutSnapshotSignature(beforeLayout) ~= methods.layoutSnapshotSignature(afterLayout)

        end

        if not snapshotChanged and not layoutChanged then

            return false

        end

        local entry = {

            label = label,

            before = shallowCopy(beforeSnapshot),

            after = shallowCopy(afterSnapshot),

        }

        if options.tabId then

            entry.tabId = options.tabId

        end

        if beforeLayout or afterLayout then

            entry.beforeLayout = methods.copyLayoutSnapshot(beforeLayout)

            entry.afterLayout = methods.copyLayoutSnapshot(afterLayout)

            entry.layoutTargetIds = methods.copyLayoutTargetIds(options.layoutTargetIds)

        end

        state.undoHistory[#state.undoHistory + 1] = entry

        state.redoHistory = {}

        return true

    end



    function methods.applyFieldValue(field, value, options)

        options = options or {}

        local currentValue = methods.readFieldValue(field)
        if field and field.key == 'language' then
            value = methods.normalizeLanguageCode(value, currentValue)
        end

        local previousResolved = methods.normalizeFieldValue(field, currentValue, currentValue)

        local resolved = methods.normalizeFieldValue(field, value, currentValue)

        if field and field.key == 'startupAutoRun' then

            resolved = methods.resolveStartupAutoRunState(resolved)

            methods.persistStartupAutoRunCache(resolved)

        end

        local selection = nil

        if methods.isIndicatorLikeField(field) then

            selection = options.selectionOption or methods.resolveIndicatorLikeInput(field, value)

            resolved = trim(selection.value or resolved)

        end

        if previousResolved == resolved then

            return false

        end

        if field.sessionOnly then

            methods.setFieldSessionValue(field, resolved)

        elseif field.settingsFile == 'State' then

            methods.writeIniVariable(methods.statePath(), field.variableName, resolved)

            if field.variableName == 'SettingsThemeMode' then

                methods.applyTheme(resolved)

            end

        else

            methods.writeIniVariable(methods.settingsFilePath(field.settingsFile), field.variableName, resolved)

        end

        if field.variableName == 'BaseFont' then
            setVariable('BaseFont', resolved)
            methods.syncModalBaseFont(resolved)
        end
        methods.syncSettingsTargetVariable(field, resolved)
        if field.key == 'minecraftSkinUsername' then

            local draftUsername = resolved

            if methods.isLocalAttachedMinecraftSkinUsername(resolved) then

                draftUsername = ''

            end

            methods.syncMinecraftSkinDraft(draftUsername)

        end

        if field.key == 'language' then
            methods.syncActiveLocalization(resolved)
        end

        methods.syncInventoryRefreshPositionLockState(field, resolved)

        if methods.syncWindowOptionToggleState(field, resolved) then
            return
        end

        if methods.syncInventoryTooltipSize(field, resolved) then

            return

        end

        if methods.syncInventoryItemSize(field, resolved) then

            return

        end

        if methods.syncInventorySupportToggle(field, resolved) then

            return

        end

        if methods.syncHerobrineLiveState(field, resolved) then

            return true

        end

        if methods.syncClockType(field, resolved) then

            return

        end

        if methods.syncClockSpriteSize(field, resolved) then

            return

        end

        if methods.syncClock24Hour(field, resolved) then

            return

        end

        if methods.syncClockHideMeridiem(field, resolved) then

            return

        end

        if methods.syncClockDateSize(field, resolved) then

            return

        end

        if methods.syncClockTextColor(field, resolved) then

            return

        end

        if methods.syncHotbarTextColor(field, resolved) then

            return

        end

        if options.suppressRefresh == true then
            if field.key == 'language' then
                methods.syncItemLabelsForLanguage(resolved, {
                    refreshAppOnComplete = options.refreshAppAfterItemLabels == true,
                })
            end
            return true
        end

        local targetSet = options.targetSet or {}

        methods.collectFieldTargets(targetSet, field)

        methods.syncHotbarInventoryEnabledLiveState(field, resolved)

        methods.syncInventoryBottomRowLiveState(field, resolved, targetSet)

        if selection and selection.diskTarget and field.pairedDiskTargetFieldKey then

            local targetField = methods.getField(field.pairedDiskTargetFieldKey)

            if targetField then

                methods.writeIniVariable(methods.settingsFilePath(targetField.settingsFile), targetField.variableName, trim(selection.diskTarget))

                methods.collectFieldTargets(targetSet, targetField)

            end

        end

        local shouldRefreshActivatedTarget = nil

        if methods.activationSemanticValue(field, previousResolved) ~= methods.activationSemanticValue(field, resolved) then

            shouldRefreshActivatedTarget = methods.syncFieldActivationState(field, resolved)

        end

        methods.syncClockActivationResync(field, shouldRefreshActivatedTarget)

        if shouldRefreshActivatedTarget == false then

            if not field.preserveRefreshTargetsOnDeactivate then

                for _, targetName in ipairs(field.refreshTargets or {}) do

                    targetSet[targetName] = nil

                end

            end

            for _, targetName in ipairs(field.activateTargets or {}) do

                targetSet[targetName] = nil

            end

            for _, targetName in ipairs(field.deactivateTargets or {}) do

                targetSet[targetName] = nil

            end

        end

        local refreshOptions = nil

        if field.key == 'language' then
            targetSet.Settings = true
            refreshOptions = {
                includeSettings = true,
                loadingText = methods.languageSwitchLoadingText(resolved),
                delayTicks = 0,
            }
        end

        if options.targetSet and refreshOptions then
            options.targetSet.__includeSettings = true
            options.targetSet.__loadingText = refreshOptions.loadingText
        end

        if field.key == 'language' and not options.targetSet then
            if methods.syncItemLabelsForLanguage(resolved, {
                targetSet = targetSet,
                refreshOptions = refreshOptions,
            }) then
                return true
            end
        end

        if not options.targetSet then

            methods.refreshTargets(targetSet, refreshOptions)

        end

    end



    function methods.restoreSnapshot(snapshot, options)
        options = options or {}
        local targets = {}
        local skipFieldKeySet = {}
        for _, fieldKey in ipairs(options.skipFieldKeys or {}) do
            skipFieldKeySet[fieldKey] = true
        end
        local fieldKeys = options.fieldKeys or schema.trackedFieldKeys
        local restoreMinecraftSkinState = false
        for _, fieldKey in ipairs(fieldKeys) do
            local field = methods.getField(fieldKey)
            local desired = snapshot[fieldKey]
            if fieldKey == 'minecraftSkinUsername' then
                restoreMinecraftSkinState = true
            end
            if not skipFieldKeySet[fieldKey] and field and field.controlType ~= 'action' and desired ~= nil then
                methods.applyFieldValue(field, desired, { targetSet = targets })
            end
        end
        if restoreMinecraftSkinState and not skipFieldKeySet.minecraftSkinUsername and snapshot.minecraftSkinUsername ~= nil then
            local restoredUsername = trim(snapshot.minecraftSkinUsername)
            local snapshotImagePathVerified = trim(snapshot.minecraftSkinImagePathVerified) == '1' or trim(snapshot.minecraftSkinImagePathVerified) == 'true'
            local restoredImagePath = methods.resolveStoredMinecraftSkinImagePath(restoredUsername, snapshot.minecraftSkinImagePath, { allowStoredWidePath = snapshotImagePathVerified })
            local restoredTexturePath = methods.resolveStoredMinecraftSkinTexturePath(restoredUsername, snapshot.minecraftSkinTexturePath, {
                allowStoredTexturePath = snapshotImagePathVerified,
            })
            local restoredImagePathVerified = restoredImagePath ~= '' and snapshotImagePathVerified
            local currentUsernameField = methods.getField('minecraftSkinUsername')
            local currentUsername = currentUsernameField and trim(methods.readFieldValue(currentUsernameField)) or ''
            local currentImagePath = trim(SKIN:GetVariable('MinecraftSkinImagePath', ''))
            local currentTexturePath = trim(SKIN:GetVariable('MinecraftSkinTexturePath', ''))
            local currentImagePathVerified = methods.isMinecraftSkinImagePathVerified(currentImagePath)
            local sameUsername = restoredUsername == currentUsername
            local sameImagePath = (restoredImagePath == '' and currentImagePath == '')
                or methods.sameNormalizedPath(currentImagePath, restoredImagePath)
            local sameTexturePath = (restoredTexturePath == '' and currentTexturePath == '')
                or methods.sameNormalizedPath(currentTexturePath, restoredTexturePath)
            if not (sameUsername and sameImagePath and sameTexturePath and currentImagePathVerified == restoredImagePathVerified) then
                methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', restoredImagePath)
                methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', restoredImagePathVerified and '1' or '0')
                methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', restoredTexturePath)
                if methods.syncInventoryPlayerSkinLiveState then
                    methods.syncInventoryPlayerSkinLiveState(restoredUsername, restoredImagePath, targets, { verified = restoredImagePathVerified })
                end
            end
        end
        methods.refreshTargets(targets)

        if not options.suppressRender then

            methods.renderActivePage()

        end

        return targets

    end
end
