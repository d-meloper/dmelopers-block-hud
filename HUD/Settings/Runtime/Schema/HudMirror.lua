local fields = {
    refreshHudMirrorMonitors = {
        key = 'refreshHudMirrorMonitors', tabId = 'hudMirror', pageId = 1,
        controlType = 'action', label = '모니터 새로고침', defaultActionText = '⟲',
        actionButtonWidthScale = 0.5,
        historyLabel = 'HUD mirror monitor refresh', refreshTargets = {},
    },
    hudMirrorReplicaDraggable = {
        key = 'hudMirrorReplicaDraggable', tabId = 'hudMirror', pageId = 1,
        controlType = 'toggle', label = '드래그 허용',
        settingsFile = 'HudMirror', variableName = 'AllowHudMirrorReplicaDrag', valueType = 'bool',
        defaultSnapshotValue = '0', historyLabel = 'HUD mirror replica drag change', refreshTargets = {},
        disabledWhenNoHudMirrorMonitor = true,
    },
    hudMirrorReplicaSnapEdges = {
        key = 'hudMirrorReplicaSnapEdges', tabId = 'hudMirror', pageId = 1,
        controlType = 'toggle', label = '드래그 위치 스냅',
        settingsFile = 'HudMirror', variableName = 'AllowHudMirrorReplicaSnapEdges', valueType = 'bool',
        defaultSnapshotValue = '0', historyLabel = 'HUD mirror replica snap change', refreshTargets = {},
        disabledWhenNoHudMirrorMonitor = true,
    },
    hudMirrorUnavailableStatus = {
        key = 'hudMirrorUnavailableStatus', tabId = 'hudMirror', pageId = 1,
        controlType = 'hudMirrorStatus', label = '',
        displayFallback = '디스플레이 모드가 복제 이거나,\n연결된 다른 모니터를 감지하지 못했습니다.',
    },
    resetHudMirrorSettings = {
        key = 'resetHudMirrorSettings', tabId = 'hudMirror', pageId = 9,
        controlType = 'action', label = '기본값으로 초기화', defaultActionText = '설정 초기화',
        historyLabel = 'HUD mirror settings reset', refreshTargets = {},
        requiresConfirmation = true, actionStyle = 'danger',
    },
}

local trackedFieldKeys = {
    'hudMirrorReplicaDraggable',
    'hudMirrorReplicaSnapEdges',
}

for slotIndex = 1, 31 do
    local suffix = string.format('%02d', slotIndex)
    local fieldKey = 'hudMirrorSlot' .. suffix .. 'Selection'
    fields[fieldKey] = {
        key = fieldKey,
        tabId = 'hudMirror',
        pageId = 1,
        controlType = 'multiDropdown',
        dropdownId = 'hudMirrorSelection',
        wideTextField = true,
        label = '',
        settingsFile = 'HudMirror',
        variableName = 'HudMirrorSlot' .. suffix .. 'Selection',
        valueType = 'integer',
        min = 0,
        max = 511,
        defaultSnapshotValue = '0',
        historyLabel = 'HUD mirror monitor selection change',
        refreshTargets = {},
        hudMirrorSlotIndex = slotIndex,
    }
    trackedFieldKeys[#trackedFieldKeys + 1] = fieldKey
end

return {
    fields = fields,
    trackedFieldKeys = trackedFieldKeys,
}
