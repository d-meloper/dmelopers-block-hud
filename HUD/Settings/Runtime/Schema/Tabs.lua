return {
tabs = {

        { id = 'general', name = '기본', fields = { 'muteSound', 'hideHintTooltip', 'itemCountTextFontSize', 'language', 'refreshComputerInfo', 'startupAutoRun', 'openLogFolder', 'resetAllSettings' } },

        { id = 'lowSpec', name = '저사양 모드', fields = { 'lowSpecFreezeInventoryPlayerAnimation', 'lowSpecDisableSlotHoverHighlight', 'lowSpecDisableHoverTextTooltip' } },

        { id = 'hotbar', name = '핫바', fields = { 'hotbarSlotSize', 'hotbarItemOffset', 'hotbarTextYOffset', 'hotbarTextFontSize', 'hotbarTextColor', 'hotbarEnabled', 'hotbarDraggable', 'hotbarDragSnap', 'resetHotbarSettings', 'resetHotbarSkinPositions' } },

        { id = 'indicators', name = '인디케이터', fields = { 'healthSource', 'armorSource', 'foodSource', 'airSource', 'expSource', 'expLevel', 'expLevelGap', 'indicatorBarScalePercent', 'indicatorsDraggable', 'indicatorsDragSnap', 'resetIndicatorsSettings', 'resetIndicatorsSkinPositions' } },

        { id = 'inventory', name = '인벤토리', fields = { 'inventoryItemSize', 'inventoryTooltipSize', 'inventoryBottomRow', 'minecraftSkinUsernameDraft', 'minecraftSkinModel', 'attachMinecraftSkinFile', 'hideSteve', 'hideUsageGuide', 'hideSkinFolderButton', 'hideEditButton', 'hideSettingsButton', 'inventoryEnabled', 'inventoryDraggable', 'inventoryDragSnap', 'inventoryRefreshPositionLock', 'resetInventorySettings', 'resetInventorySkinPositions' } },

        { id = 'clock', name = '시계', fields = { 'clockType', 'clockSpriteSize', 'clock24Hour', 'clockHideMeridiem', 'clockTimeSize', 'clockDateSize', 'clockTextColor', 'clockTextGap', 'clockEnabled', 'clockDraggable', 'clockDragSnap', 'resetClockSettings', 'resetClockSkinPositions' } },

        { id = 'ui', name = 'UI', fields = { 'baseFont', 'settingsTheme', 'resetAllSkinPositions' } },

    },
contentTabs = {
        { id = 'jukebox', name = 'Jukebox', labelVariable = 'Loc_Settings_Content_Jukebox', fields = { 'jukeboxEnabled', 'jukeboxHelp', 'jukeboxPlaybackSourceMode', 'jukebox2DMode', 'jukeboxDisableNoteAnimation', 'jukeboxDraggable', 'jukeboxDragSnap', 'resetJukeboxSettings', 'resetJukeboxSkinPositions' } },
        { id = 'herobrine', name = 'Herobrine', labelVariable = 'Loc_Settings_Content_Herobrine', fields = { 'herobrineEnabled', 'herobrineTotalAppearances', 'herobrineCaptures', 'herobrineVisibleSeconds', 'refreshHerobrineStats' } },
    },
}
