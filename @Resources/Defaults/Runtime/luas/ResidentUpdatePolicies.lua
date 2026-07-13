return {
    Inventory = {
        group = 'ResidentUpdateInventory',
        oneShotMeasures = { 'MeasureInventoryEnableGuard', 'MeasurePlayerDefaultHidden', 'MeasurePlayerCustomHidden', 'MeasureEditorModeBadgeVisibility' },
        drivers = {
            runtime = { config = 'HUD/Inventory/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
            animation = { config = 'HUD/Inventory/AnimationDriver', file = 'AnimationDriver.ini', resume = false },
        },
    },
    Editor = {
        group = 'ResidentUpdateEditor',
        oneShotMeasures = { 'MeasureViewerPreviewBaseImageX', 'MeasureViewerPreviewBaseImageY', 'MeasureViewerPreviewBaseImageW', 'MeasureViewerPreviewBaseImageH' },
        drivers = {
            runtime = { config = 'HUD/Editor/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
        },
    },
    Settings = {
        group = 'ResidentUpdateSettings',
        oneShotMeasures = {  },
        drivers = {
            runtime = { config = 'HUD/Settings/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
        },
    },
    JukeboxDiscSlot = {
        group = 'ResidentUpdateJukeboxDiscSlot',
        oneShotMeasures = {  },
        drivers = {
            runtime = { config = 'ExtraContent/Jukebox/DiscSlot/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
        },
    },
    Jukebox = {
        group = 'ResidentUpdateJukebox',
        oneShotMeasures = {  },
        drivers = {
            runtime = { config = 'ExtraContent/Jukebox/RuntimeDriver', file = 'RuntimeDriver.ini', resume = false },
            animation = { config = 'ExtraContent/Jukebox/AnimationDriver', file = 'AnimationDriver.ini', resume = false },
        },
    },
}
