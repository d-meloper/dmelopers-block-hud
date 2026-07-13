return function(tabCount, contentTabCount)



    local resolvedTabCount = tonumber(tabCount) or 7
    local resolvedContentTabCount = tonumber(contentTabCount) or 2
    local pageSlotCount = math.max(resolvedTabCount, resolvedContentTabCount)



    local currentPageByTab = {}



    for index = 1, pageSlotCount do



        currentPageByTab['normal:' .. tostring(index)] = 1
        currentPageByTab['content:' .. tostring(index)] = 1



    end



    return {



        rowsPerPage = 4,



        dropdownRowsPerPage = 5,



        currentTabIndex = 1,
        normalTabIndex = 1,
        contentTabIndex = 1,
        contentMode = false,



        currentPageByTab = currentPageByTab,



        currentInputFieldKey = nil,
        sharedInputActive = false,



        currentVisibleRows = {},



        currentFieldKeyByRow = {},



        currentRowActionByIndex = {},



        currentRowSecondaryActionByIndex = {},



        activeDropdownFieldKey = nil,



        activeDropdownRowIndex = 0,



        activeDropdownPageIndex = 1,



        currentDropdownOptionBySlot = {},



        pendingConfirmActionKey = nil,



        undoHistory = {},



        redoHistory = {},



        baselineSnapshot = nil,



        resourcesRoot = nil,



        settingsRoot = nil,



        rootConfig = nil,



        bundledFontFaceSet = nil,



        bundledFontFaces = nil,



        installedDriveTargets = nil,



        pendingLoadKind = nil,



        pendingLoadFieldKey = nil,



        pendingLoadRowIndex = 0,



        pendingLoadDelayTicksRemaining = 0,



        pendingLoadReopenDropdown = false,



        pendingLoadValue = nil,

        pendingLoadTexturePath = nil,

        pendingLoadUsername = nil,



        pendingLoadBeforeSnapshot = nil,



        pendingLoadHistoryLabel = nil,



        pendingLoadHelperRunning = false,



        pendingLoadHelperKind = nil,



        pendingLoadHelperMeasureName = nil,



        pendingLoadHelperLoadKind = nil,



        pendingLoadHelperStartedAt = 0,



        pendingLoadHelperDeadlineAt = 0,



        pendingLoadHelperTimeoutSeconds = 0,



        ignoredPendingLoadHelpers = {},


        pendingRefreshBatchIndex = 0,

        pendingRefreshBatches = {},


        pendingRefreshBatchTotal = 0,

        pendingRefreshOptions = nil,

        pendingRefreshDelayTicksRemaining = 0,

        pendingLanguageSwitchValue = nil,

        pendingLanguageSwitchBeforeSnapshot = nil,

        pendingLanguageSwitchSubmitActionFieldKey = nil,


        cacheFormatVersion = '2',



        versionManagerLaunchPending = false,



        versionManagerLaunchStartedAt = 0,



        versionManagerLaunchToken = '',



        tabCount = resolvedTabCount,
        contentTabCount = resolvedContentTabCount,



    }



end
