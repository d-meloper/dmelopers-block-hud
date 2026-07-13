return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    function methods.captureSnapshot()

        local snapshot = {}

        for _, fieldKey in ipairs(schema.trackedFieldKeys) do

            local field = methods.getField(fieldKey)

            snapshot[fieldKey] = methods.normalizeFieldValue(field, methods.readFieldValue(field), '')

        end

        local snapshotMinecraftSkinImagePath = SKIN:GetVariable('MinecraftSkinImagePath', '')
        local snapshotMinecraftSkinImagePathVerified = methods.isMinecraftSkinImagePathVerified(snapshotMinecraftSkinImagePath)
        snapshot.minecraftSkinImagePath = methods.resolveStoredMinecraftSkinImagePath(snapshot.minecraftSkinUsername, snapshotMinecraftSkinImagePath, { allowStoredWidePath = snapshotMinecraftSkinImagePathVerified })
        snapshot.minecraftSkinImagePathVerified = snapshot.minecraftSkinImagePath ~= '' and snapshotMinecraftSkinImagePathVerified and '1' or '0'
        snapshot.minecraftSkinTexturePath = methods.resolveStoredMinecraftSkinTexturePath(snapshot.minecraftSkinUsername, SKIN:GetVariable('MinecraftSkinTexturePath', ''), {

            allowStoredTexturePath = snapshotMinecraftSkinImagePathVerified,

        })

        return snapshot

    end



    function methods.toggleSemanticValue(field, storedValue)

        local storedEnabled = methods.normalizeToggleValue(storedValue) == '1'

        if field.invert then

            return not storedEnabled

        end

        return storedEnabled

    end



    function methods.nextStoredToggleValue(field)

        local nextSemantic = not methods.toggleSemanticValue(field, methods.readFieldValue(field))

        if field.invert then

            return nextSemantic and '0' or '1'

        end

        return nextSemantic and '1' or '0'

    end



    function methods.defaultSnapshotFallbackValue(fieldKey)

        local fallbackByFieldKey = {

            jukeboxDraggable = '1',

            jukeboxDragSnap = '0',

            hotbarDragSnap = '0',

            itemCountTextFontSize = '18',

            indicatorsDragSnap = '0',

            inventoryDragSnap = '0',

            inventoryRefreshPositionLock = '1',

            clockDragSnap = '0',

        }

        return fallbackByFieldKey[fieldKey]

    end

    function methods.defaultSnapshotRestoreValue(fieldKey, rawValue)

        local field = methods.getField(fieldKey)

        local resolved = methods.normalizeFieldValue(field, rawValue, rawValue)

        if field and field.valueType == 'bool' and field.defaultSnapshotInvert then

            return resolved == '1' and '0' or '1'

        end

        return resolved

    end


    function methods.loadDefaultSnapshot(fieldKeys)

        local snapshot = {}

        local missingKeys = {}

        local sentinel = '__SETTINGS_DEFAULT_MISSING__'

        for _, fieldKey in ipairs(fieldKeys or schema.trackedFieldKeys) do

            local variableName = 'SettingsDefault_' .. fieldKey

            local value = SKIN:GetVariable(variableName, sentinel)

            if value == sentinel then

                local fallback = methods.defaultSnapshotFallbackValue(fieldKey)

                if fallback ~= nil then

                    snapshot[fieldKey] = methods.defaultSnapshotRestoreValue(fieldKey, fallback)

                else

                    missingKeys[#missingKeys + 1] = fieldKey

                end
            else

                snapshot[fieldKey] = methods.defaultSnapshotRestoreValue(fieldKey, value or '')

            end

        end

        if #missingKeys > 0 then

            return nil, missingKeys

        end

        return snapshot, nil

    end



    function methods.resetFieldKeysForTab(tabId)

        local orderedFieldKeys = {}

        local included = {}

        for _, fieldKey in ipairs(schema.trackedFieldKeys) do

            local field = methods.getField(fieldKey)

            if field and field.tabId == tabId and field.controlType ~= 'action' then

                if not included[field.key] then

                    orderedFieldKeys[#orderedFieldKeys + 1] = field.key

                    included[field.key] = true

                end

                local pairedField = methods.pairedDiskTargetField(field)

                if pairedField and not included[pairedField.key] then

                    orderedFieldKeys[#orderedFieldKeys + 1] = pairedField.key

                    included[pairedField.key] = true

                end

            end

        end

        return orderedFieldKeys

    end



    function methods.copyLayoutTargetIds(targetIds)

        local copied = {}

        for _, id in ipairs(targetIds or {}) do

            copied[#copied + 1] = id

        end

        return copied

    end



    function methods.layoutTargetIdsForTab(tabId)

        local core = methods.responsiveLayoutCore()

        return methods.copyLayoutTargetIds(core.TargetIdsForTab(tabId) or {})

    end



    function methods.allLayoutTargetIds()

        local core = methods.responsiveLayoutCore()

        return methods.copyLayoutTargetIds(core.AllSkinIds() or {})

    end



    function methods.copyLayoutSnapshot(snapshot)

        local copied = {}

        for id, stateSnapshot in pairs(snapshot or {}) do

            copied[id] = shallowCopy(stateSnapshot)

        end

        return copied

    end



    function methods.captureLayoutSnapshot(targetIds)

        local core = methods.responsiveLayoutCore()

        local snapshot = {}

        for _, id in ipairs(targetIds or {}) do

            local stateSnapshot = core.GetState(SKIN, id)

            if stateSnapshot then

                snapshot[id] = shallowCopy(stateSnapshot)

            end

        end

        return snapshot

    end



    function methods.captureTabLayoutSnapshot(tabId)

        return methods.captureLayoutSnapshot(methods.layoutTargetIdsForTab(tabId))

    end



    function methods.captureAllLayoutSnapshot()

        return methods.captureLayoutSnapshot(methods.allLayoutTargetIds())

    end



    function methods.captureBaselineState()

        state.baselineSnapshot = methods.captureSnapshot()

        state.baselineLayoutTargetIds = methods.allLayoutTargetIds()

        state.baselineLayoutSnapshot = methods.captureLayoutSnapshot(state.baselineLayoutTargetIds)

    end



    function methods.layoutSnapshotSignature(snapshot)

        local fragments = {}

        for id, stateSnapshot in pairs(snapshot or {}) do

            local stateFragments = {}

            for key, value in pairs(stateSnapshot or {}) do

                stateFragments[#stateFragments + 1] = key .. '=' .. tostring(value)

            end

            table.sort(stateFragments)

            fragments[#fragments + 1] = id .. '{' .. table.concat(stateFragments, ',') .. '}'

        end

        table.sort(fragments)

        return table.concat(fragments, '|')

    end



    function methods.reflowLayoutTargetIds(targetIds, options)

        local core = methods.responsiveLayoutCore()

        local reflowIds = {}

        local applySettingsLayout = false

        local forceRefresh = options and options.forceRefresh == true

        for _, id in ipairs(targetIds or {}) do

            if id == 'Settings' then

                applySettingsLayout = true

            elseif forceRefresh or methods.isConfigTargetRefreshable(id) then

                reflowIds[#reflowIds + 1] = id

            else

                -- Persist state for inactive targets, but never refresh them from Settings-side reflow.

            end

        end

        if #reflowIds > 0 then

            core.ReflowTargets(SKIN, reflowIds, { forceRefresh = forceRefresh })

        end

        if applySettingsLayout then

            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')

        end

    end



    function methods.restoreLayoutSnapshot(snapshot, targetIds)

        local core = methods.responsiveLayoutCore()

        local ids = methods.copyLayoutTargetIds(targetIds)

        if #ids == 0 then

            for id, _ in pairs(snapshot or {}) do

                ids[#ids + 1] = id

            end

            table.sort(ids)

        end

        if #ids == 0 then

            return

        end

        for _, id in ipairs(ids) do

            local stateSnapshot = snapshot and snapshot[id]

            if stateSnapshot then

                core.WriteState(SKIN, id, stateSnapshot, true)

            end

        end

        methods.reflowLayoutTargetIds(ids)

    end



    function methods.restoreTabLayoutSnapshot(tabId, snapshot)

        methods.restoreLayoutSnapshot(snapshot, methods.layoutTargetIdsForTab(tabId))

    end



    function methods.windowOptionTargetIdsForField(field)
        local ids = {}
        for _, targetId in ipairs(field and field.windowOptionTargetIds or {}) do
            ids[#ids + 1] = targetId
        end
        return ids
    end
    function methods.windowOptionNameForField(field)
        if not field then
            return ''
        end
        return trim(field.windowOptionName or '')
    end
end
