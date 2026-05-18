return function(tabCount)



    local resolvedTabCount = tonumber(tabCount) or 6



    local currentPageByTab = {}



    for index = 1, resolvedTabCount do



        currentPageByTab[index] = 1



    end



    return {



        rowsPerPage = 4,



        dropdownRowsPerPage = 5,



        currentTabIndex = 1,



        currentPageByTab = currentPageByTab,



        currentInputFieldKey = nil,



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



        noticeHistory = {},



        noticeLatestId = 0,



        noticeNextId = 1,



        noticeDismissedId = 0,



        noticeHistoryExpanded = false,



        noticeHistoryPageIndex = 1,



        versionManagerLaunchPending = false,



        versionManagerLaunchStartedAt = 0,



        versionManagerLaunchToken = '',



        tabCount = resolvedTabCount,



    }



end
