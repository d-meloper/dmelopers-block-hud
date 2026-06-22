return {
    Inventory = {
        group = 'ResidentUpdateInventory',
        oneShotMeasures = { 'MeasureInventoryEnableGuard', 'MeasurePlayerDefaultHidden', 'MeasurePlayerCustomHidden', 'MeasureEditorModeBadgeVisibility' },
        drivers = {
            runtime = { config = 'Inventory/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
            animation = { config = 'Inventory/AnimationDriver', file = 'AnimationDriver.ini', resume = false },
        },
    },
    InventoryBG = {
        group = 'ResidentUpdateInventoryBG',
        oneShotMeasures = { 'MeasureInventoryBGEnableGuard' },
        drivers = {
        },
    },
    Editor = {
        group = 'ResidentUpdateEditor',
        oneShotMeasures = { 'MeasureViewerPreviewBaseImageX', 'MeasureViewerPreviewBaseImageY', 'MeasureViewerPreviewBaseImageW', 'MeasureViewerPreviewBaseImageH' },
        drivers = {
            runtime = { config = 'Editor/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
        },
    },
    Settings = {
        group = 'ResidentUpdateSettings',
        oneShotMeasures = {  },
        drivers = {
            runtime = { config = 'Settings/RuntimeDriver', file = 'RuntimeDriver.ini', resume = true },
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
