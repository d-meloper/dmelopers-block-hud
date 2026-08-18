return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local setVariable = app.setVariable
    local preferences = app.loadSharedLuaModule('HudMirrorPreferences.lua')

    local MAX_SECONDARY_MONITORS = preferences.MaxReplicas()
    local ALL_SELECTIONS_MASK = preferences.AllSelections()
    local POSITION_TARGET_IDS = preferences.PositionTargets()
    local SELECTIONS = {
        { bit = 1, key = 'Settings_HudMirror_Option_Hotbar', fallback = '핫바' },
        { bit = 2, key = 'Settings_HudMirror_Option_Health', fallback = '체력 바' },
        { bit = 4, key = 'Settings_HudMirror_Option_Armor', fallback = '방어구 바' },
        { bit = 8, key = 'Settings_HudMirror_Option_Food', fallback = '허기 바' },
        { bit = 16, key = 'Settings_HudMirror_Option_Air', fallback = '산소 바' },
        { bit = 32, key = 'Settings_HudMirror_Option_ExpBar', fallback = '경험치 바' },
        { bit = 64, key = 'Settings_HudMirror_Option_ExpLevel', fallback = '경험치 수치' },
        { bit = 128, key = 'Settings_HudMirror_Option_ClockText', fallback = '시계 텍스트' },
        { bit = 256, key = 'Settings_HudMirror_Option_ClockSprite', fallback = '시계 아이템' },
    }

    local function slotSuffix(slotIndex)
        return string.format('%02d', slotIndex)
    end

    local function slotVariable(slotIndex, suffix)
        return 'HudMirrorSlot' .. slotSuffix(slotIndex) .. suffix
    end

    local function slotFieldKey(slotIndex)
        return 'hudMirrorSlot' .. slotSuffix(slotIndex) .. 'Selection'
    end

    local function clampMask(raw)
        return preferences.NormalizeMask(raw)
    end

    local function hasBit(mask, bit)
        return preferences.HasBit(mask, bit)
    end

    local function preferenceSignature()
        local fragments = {
            'D=' .. methods.normalizeToggleValue(SKIN:GetVariable('AllowHudMirrorReplicaDrag', '0')),
            'S=' .. methods.normalizeToggleValue(SKIN:GetVariable('AllowHudMirrorReplicaSnapEdges', '0')),
        }
        for slotIndex = 1, MAX_SECONDARY_MONITORS do
            fragments[#fragments + 1] = table.concat({
                slotSuffix(slotIndex),
                trim(SKIN:GetVariable(slotVariable(slotIndex, 'Fingerprint'), '')),
                tostring(clampMask(SKIN:GetVariable(slotVariable(slotIndex, 'Selection'), '0'))),
            }, ':')
        end
        return table.concat(fragments, '|')
    end

    local function hudMirrorPath()
        return methods.settingsFilePath('HudMirror')
    end

    local function writePreference(variableName, value)
        local resolved = tostring(value or '')
        if trim(SKIN:GetVariable(variableName, '')) == trim(resolved) then
            return false
        end
        methods.writeIniVariable(hudMirrorPath(), variableName, resolved)
        SKIN:Bang('!SetVariableGroup', variableName, resolved, 'HudMirrorRuntime')
        state.hudMirrorPreferenceRefreshPending = true
        return true
    end

    local function clearSlot(slotIndex, options)
        options = options or {}
        local changed = false
        if options.preserveFingerprint ~= true then
            changed = writePreference(slotVariable(slotIndex, 'Fingerprint'), '') or changed
        end
        if options.preserveSelection ~= true then
            changed = writePreference(slotVariable(slotIndex, 'Selection'), '0') or changed
        end
        if options.preservePositions ~= true then
            for _, targetId in ipairs(POSITION_TARGET_IDS) do
                changed = writePreference(slotVariable(slotIndex, targetId .. 'Position'), '') or changed
            end
        end
        return changed
    end

    local function notifyController()
        methods.ensurePaths()
        local config = state.rootConfig .. '\\HUD\\Mirror\\Controller'
        SKIN:Bang('!CommandMeasure', 'MeasureHudMirrorController', 'RefreshPreferences()', config)
    end

    function methods.isHudMirrorPreferenceField(field)
        return field and field.settingsFile == 'HudMirror'
            and trim(field.variableName or '') ~= ''
    end

    function methods.markHudMirrorPreferencesChanged(field, resolved)
        if not methods.isHudMirrorPreferenceField(field) then
            return false
        end
        SKIN:Bang('!SetVariableGroup', field.variableName, tostring(resolved or ''), 'HudMirrorRuntime')
        state.hudMirrorPreferenceRefreshPending = true
        return true
    end

    function methods.flushHudMirrorPreferenceRefresh()
        if state.hudMirrorPreferenceRefreshPending ~= true then
            return false
        end
        state.hudMirrorPreferenceRefreshPending = false
        state.hudMirrorPreferenceSignature = preferenceSignature()
        notifyController()
        return true
    end

    function methods.hudMirrorSelectionMask(field)
        return clampMask(field and SKIN:GetVariable(field.variableName, '0') or '0')
    end

    function methods.hudMirrorSelectionDisplay(field)
        local mask = methods.hudMirrorSelectionMask(field)
        if mask == 0 then
            return methods.localize('Settings_HudMirror_SelectionDisabled', '사용 안 함')
        end
        if mask == ALL_SELECTIONS_MASK then
            return methods.localize('Settings_HudMirror_SelectionAll', '모두')
        end
        local count = 0
        for _, option in ipairs(SELECTIONS) do
            if hasBit(mask, option.bit) then
                count = count + 1
            end
        end
        return methods.localizeFormat('Settings_HudMirror_SelectionCount', { count }, tostring(count) .. '개 선택됨.')
    end

    function methods.hudMirrorDropdownOptions(field)
        local mask = methods.hudMirrorSelectionMask(field)
        local options = {
            {
                displayLabel = methods.localize('Settings_HudMirror_SelectionDisabled', '사용 안 함'),
                appliedValue = '0',
                hudMirrorBit = 0,
                selected = mask == 0,
            },
            {
                displayLabel = methods.localize('Settings_HudMirror_SelectionAll', '모두'),
                appliedValue = tostring(ALL_SELECTIONS_MASK),
                hudMirrorSelectAll = true,
                selected = mask == ALL_SELECTIONS_MASK,
            },
        }
        for _, item in ipairs(SELECTIONS) do
            options[#options + 1] = {
                displayLabel = methods.localize(item.key, item.fallback),
                appliedValue = tostring(item.bit),
                hudMirrorBit = item.bit,
                selected = hasBit(mask, item.bit),
            }
        end
        return options
    end

    function methods.SelectHudMirrorDropdownOption(field, option)
        if not field or field.dropdownId ~= 'hudMirrorSelection' or not option then
            return false
        end
        if methods.ValidateHudMirrorDropdownMonitor
            and not methods.ValidateHudMirrorDropdownMonitor(field, state.activeDropdownRowIndex) then
            return false
        end
        local currentMask = methods.hudMirrorSelectionMask(field)
        local bit = tonumber(option.hudMirrorBit) or 0
        local nextMask = 0
        if option.hudMirrorSelectAll == true then
            nextMask = ALL_SELECTIONS_MASK
        elseif bit > 0 then
            if hasBit(currentMask, bit) then
                nextMask = currentMask - bit
            else
                nextMask = currentMask + bit
            end
        end
        if nextMask == currentMask then
            return false
        end

        local beforeSnapshot = methods.captureSnapshot()
        methods.applyFieldValue(field, tostring(nextMask))
        methods.flushHudMirrorPreferenceRefresh()
        methods.pushHistory(field.historyLabel, beforeSnapshot)
        methods.renderActivePage()
        return true
    end

    local function currentSecondaryMonitors(snapshot)
        local monitors = {}
        for _, monitor in ipairs(snapshot and snapshot.monitors or {}) do
            if monitor.isPrimary ~= true and #monitors < MAX_SECONDARY_MONITORS then
                monitors[#monitors + 1] = monitor
            end
        end
        return monitors
    end

    local function bindMonitorSlots(monitors)
        local currentFingerprintSet = {}
        local slotFingerprint = {}
        local preferredSlotByFingerprint = {}
        local usedSlots = {}
        local bindings = {}
        local changed = false

        for _, monitor in ipairs(monitors) do
            currentFingerprintSet[monitor.fingerprint] = true
        end
        for slotIndex = 1, MAX_SECONDARY_MONITORS do
            slotFingerprint[slotIndex] = trim(SKIN:GetVariable(slotVariable(slotIndex, 'Fingerprint'), ''))
            if slotFingerprint[slotIndex] ~= '' and preferredSlotByFingerprint[slotFingerprint[slotIndex]] == nil then
                preferredSlotByFingerprint[slotFingerprint[slotIndex]] = slotIndex
            end
        end

        for ordinal, monitor in ipairs(monitors) do
            local chosenSlot = nil
            for slotIndex = 1, MAX_SECONDARY_MONITORS do
                if not usedSlots[slotIndex] and slotFingerprint[slotIndex] == monitor.fingerprint then
                    chosenSlot = slotIndex
                    break
                end
            end
            if not chosenSlot then
                for slotIndex = 1, MAX_SECONDARY_MONITORS do
                    if not usedSlots[slotIndex] and slotFingerprint[slotIndex] == '' then
                        chosenSlot = slotIndex
                        changed = clearSlot(slotIndex) or changed
                        break
                    end
                end
            end
            if not chosenSlot then
                for slotIndex = 1, MAX_SECONDARY_MONITORS do
                    if not usedSlots[slotIndex] and not currentFingerprintSet[slotFingerprint[slotIndex]] then
                        chosenSlot = slotIndex
                        changed = clearSlot(slotIndex) or changed
                        break
                    end
                end
            end
            if not chosenSlot then
                for slotIndex = 1, MAX_SECONDARY_MONITORS do
                    local fingerprint = slotFingerprint[slotIndex]
                    if not usedSlots[slotIndex] and fingerprint ~= ''
                        and preferredSlotByFingerprint[fingerprint] ~= slotIndex then
                        chosenSlot = slotIndex
                        changed = clearSlot(slotIndex) or changed
                        break
                    end
                end
            end
            if chosenSlot then
                usedSlots[chosenSlot] = true
                if slotFingerprint[chosenSlot] ~= monitor.fingerprint then
                    changed = writePreference(slotVariable(chosenSlot, 'Fingerprint'), monitor.fingerprint) or changed
                    slotFingerprint[chosenSlot] = monitor.fingerprint
                end
                bindings[#bindings + 1] = {
                    ordinal = ordinal,
                    slotIndex = chosenSlot,
                    monitor = monitor,
                }
            end
        end

        return bindings, changed
    end

    local function monitorPage(ordinal)
        if ordinal == 1 then
            return 1
        end
        return 2 + math.floor((ordinal - 2) / 4)
    end

    local function rebuildTabFields(bindings)
        local tab = nil
        for _, candidate in ipairs(schema.tabs or {}) do
            if candidate.id == 'hudMirror' then
                tab = candidate
                break
            end
        end
        if not tab then
            return
        end

        local fieldKeys = {
            'refreshHudMirrorMonitors',
            'hudMirrorReplicaDraggable',
            'hudMirrorReplicaSnapEdges',
        }
        if #bindings == 0 then
            fieldKeys[#fieldKeys + 1] = 'hudMirrorUnavailableStatus'
        else
            for _, binding in ipairs(bindings) do
                local fieldKey = slotFieldKey(binding.slotIndex)
                local field = schema.fields[fieldKey]
                field.pageId = monitorPage(binding.ordinal)
                field.label = methods.localizeFormat(
                    'Settings_Field_HudMirrorMonitor_Label',
                    { binding.ordinal },
                    '보조 모니터-' .. tostring(binding.ordinal) .. ' 복제'
                )
                field.hudMirrorMonitorOrdinal = binding.ordinal
                field.hudMirrorMonitorFingerprint = binding.monitor.fingerprint
                fieldKeys[#fieldKeys + 1] = fieldKey
            end
        end

        local lastPage = #bindings > 0 and monitorPage(#bindings) or 1
        local occupiedOnLastPage = #bindings > 1 and ((#bindings - 2) % 4) + 1 or 4
        local resetPage = lastPage
        if lastPage == 1 or occupiedOnLastPage >= 4 then
            resetPage = lastPage + 1
        end
        schema.fields.resetHudMirrorSettings.pageId = resetPage
        fieldKeys[#fieldKeys + 1] = 'resetHudMirrorSettings'
        tab.fields = fieldKeys
    end

    function methods.PrepareHudMirrorTab(options)
        options = options or {}
        local core = methods.responsiveLayoutCore()
        local snapshot = core.SnapshotMonitors(SKIN)
        local monitors = currentSecondaryMonitors(snapshot)
        local previousTopologySignature = state.hudMirrorTopologySignature
        local previousPreferenceSignature = state.hudMirrorPreferenceSignature
        local bindings, wrotePreferences = bindMonitorSlots(monitors)

        state.hudMirrorTopologySignature = snapshot.signature
        state.hudMirrorPreferenceSignature = preferenceSignature()
        state.hudMirrorMonitorBindings = bindings
        state.hudMirrorHasSecondaryMonitor = #bindings > 0
        rebuildTabFields(bindings)

        local topologyChanged = previousTopologySignature ~= nil
            and previousTopologySignature ~= state.hudMirrorTopologySignature
        local preferencesChanged = previousPreferenceSignature ~= nil
            and previousPreferenceSignature ~= state.hudMirrorPreferenceSignature
        if wrotePreferences or topologyChanged or preferencesChanged then
            state.hudMirrorPreferenceRefreshPending = true
            if options.deferRefresh ~= true then
                methods.flushHudMirrorPreferenceRefresh()
            end
        end
        return wrotePreferences or topologyChanged or preferencesChanged
    end

    function methods.ValidateHudMirrorDropdownMonitor(field, rowIndex)
        if not field or field.dropdownId ~= 'hudMirrorSelection' then
            return true
        end

        local fieldKey = trim(field.key or '')
        local expectedFingerprint = trim(field.hudMirrorMonitorFingerprint or '')
        local expectedSlot = tonumber(field.hudMirrorSlotIndex)
        local topologyChanged = methods.PrepareHudMirrorTab()
        local currentBinding = nil
        for _, binding in ipairs(state.hudMirrorMonitorBindings or {}) do
            if binding.slotIndex == expectedSlot
                and trim(binding.monitor and binding.monitor.fingerprint or '') == expectedFingerprint then
                currentBinding = binding
                break
            end
        end

        local expectedPage = currentBinding and monitorPage(currentBinding.ordinal) or nil
        local expectedRow = nil
        if currentBinding then
            expectedRow = currentBinding.ordinal == 1
                and 4
                or (((currentBinding.ordinal - 2) % 4) + 1)
        end
        local requestedRow = tonumber(rowIndex) or 0
        local stillVisible = currentBinding ~= nil
            and methods.activePageIndex() == expectedPage
            and requestedRow == expectedRow
            and fieldKey ~= ''

        if not stillVisible then
            methods.closeDropdownInternal()
        end
        if topologyChanged or not stillVisible then
            methods.renderActivePage()
        end
        return stillVisible
    end

    function methods.RefreshHudMirrorMonitors()
        methods.closeDropdownInternal()
        methods.PrepareHudMirrorTab()
        methods.renderActivePage()
        return true
    end

    function methods.configureHudMirrorStatusRow(rowIndex, field)
        local text = methods.localize(
            'Settings_HudMirror_Unavailable',
            field.displayFallback or '디스플레이 모드가 복제 이거나,\n연결된 다른 모니터를 감지하지 못했습니다.'
        )
        local contentX = methods.numericVariable('SettingsContentX', 0) or 0
        local contentW = methods.numericVariable('SettingsContentW', 0) or 0
        local contentPad = methods.numericVariable(
            'SlotSettingsRowText_ContentPad',
            methods.numericVariable('SettingsInnerPad', 10)
        ) or 10
        local contentTextW = math.max(0, contentW - (2 * contentPad))
        local contentCenterX = contentX + (contentW / 2)
        local rowY = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlY', 0) or 0
        local rowH = methods.numericVariable('SlotSettingsRow' .. rowIndex .. '_ControlH', 40) or 40
        setVariable('SettingsRow' .. rowIndex .. '_LabelText', '')
        setVariable('SettingsRow' .. rowIndex .. '_LabelW', '0')
        setVariable('SettingsRow' .. rowIndex .. '_FieldHidden', '0')
        setVariable('SettingsRow' .. rowIndex .. '_FieldBgHidden', '1')
        setVariable('SettingsRow' .. rowIndex .. '_Field_X', tostring(contentX))
        setVariable('SettingsRow' .. rowIndex .. '_Field_Y', tostring(rowY))
        setVariable('SettingsRow' .. rowIndex .. '_Field_W', tostring(contentW))
        setVariable('SettingsRow' .. rowIndex .. '_Field_H', tostring(rowH))
        setVariable('SettingsRow' .. rowIndex .. '_FieldContentX', tostring(contentCenterX))
        setVariable('SettingsRow' .. rowIndex .. '_FieldContentY', tostring(rowY))
        setVariable('SettingsRow' .. rowIndex .. '_FieldContentW', tostring(contentTextW))
        setVariable('SettingsRow' .. rowIndex .. '_FieldContentH', tostring(rowH))
        setVariable('SettingsRow' .. rowIndex .. '_FieldText', text)
        setVariable('SettingsRow' .. rowIndex .. '_FieldTextAlign', 'CenterCenter')
        setVariable('SettingsRow' .. rowIndex .. '_FieldCommand', '')
        setVariable('SettingsRow' .. rowIndex .. '_DropdownButtonHidden', '1')
        if app.renderHelpers and app.renderHelpers.applyTextFit then
            app.renderHelpers.applyTextFit(
                'MeterSettingsRow' .. tostring(rowIndex) .. 'FieldText',
                text,
                'SettingsUIFontSize',
                contentTextW,
                rowH,
                'wrap4'
            )
        end
    end

    function methods.ResetHudMirrorPreferences()
        local beforeSnapshot = methods.captureSnapshot()
        local changed = false
        changed = writePreference('AllowHudMirrorReplicaDrag', '0') or changed
        changed = writePreference('AllowHudMirrorReplicaSnapEdges', '0') or changed
        for slotIndex = 1, MAX_SECONDARY_MONITORS do
            changed = clearSlot(slotIndex) or changed
        end

        state.hudMirrorTopologySignature = nil
        state.hudMirrorPreferenceSignature = nil
        methods.PrepareHudMirrorTab()
        methods.flushHudMirrorPreferenceRefresh()

        local afterSnapshot = methods.captureSnapshot()
        if app.snapshotSignature(beforeSnapshot) ~= app.snapshotSignature(afterSnapshot) then
            methods.pushHistory('HUD mirror settings reset', beforeSnapshot, { afterSnapshot = afterSnapshot })
        end
        methods.renderActivePage()
        return changed
    end

    function methods.ResetHudMirrorPersistentMetadataForOverallReset()
        local changed = false
        for slotIndex = 1, MAX_SECONDARY_MONITORS do
            changed = clearSlot(slotIndex, { preserveSelection = true }) or changed
        end
        state.hudMirrorTopologySignature = nil
        state.hudMirrorPreferenceSignature = nil
        methods.PrepareHudMirrorTab({ deferRefresh = true })
        return changed
    end
end
