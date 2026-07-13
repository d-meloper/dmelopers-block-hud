return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local function visibleTabs()
        if methods.activeTabs then
            return methods.activeTabs()
        end
        return schema.tabs
    end

    local function visibleTabCount()
        return #visibleTabs()
    end

    local PENDING_ROUTE_MODE_VARIABLE = 'BlockHudSettingsPendingRouteMode'
    local PENDING_ROUTE_TAB_VARIABLE = 'BlockHudSettingsPendingRouteTab'
    local PENDING_ROUTE_PAGE_VARIABLE = 'BlockHudSettingsPendingRoutePage'

    function methods.writePendingSettingsRoute(mode, tabIdOrIndex, pageId)
        local resolvedMode = trim(mode)
        local resolvedTab = trim(tabIdOrIndex)
        local resolvedPage = trim(pageId)
        setVariable(PENDING_ROUTE_MODE_VARIABLE, resolvedMode)
        setVariable(PENDING_ROUTE_TAB_VARIABLE, resolvedTab)
        setVariable(PENDING_ROUTE_PAGE_VARIABLE, resolvedPage)
        methods.writeInternalStateVariable(PENDING_ROUTE_MODE_VARIABLE, resolvedMode)
        methods.writeInternalStateVariable(PENDING_ROUTE_TAB_VARIABLE, resolvedTab)
        methods.writeInternalStateVariable(PENDING_ROUTE_PAGE_VARIABLE, resolvedPage)
    end

    local function tabsForRouteMode(mode)
        local requested = trim(mode):lower()
        if requested == 'content' then
            return schema.contentTabs or {}, true, requested
        elseif requested == 'normal' then
            return schema.tabs or {}, false, requested
        end
        return nil, nil, requested
    end

    local function tabIndexInList(tabs, tabIdOrIndex)
        local requested = trim(tabIdOrIndex)
        if requested == '' then
            return nil
        end

        local targetIndex = tonumber(requested)
        if targetIndex ~= nil then
            targetIndex = math.floor(targetIndex)
        end

        if targetIndex == nil then
            for index, tab in ipairs(tabs or {}) do
                if trim(tab and tab.id or '') == requested then
                    targetIndex = index
                    break
                end
            end
        end

        if targetIndex == nil or targetIndex < 1 or targetIndex > #(tabs or {}) then
            return nil
        end

        return targetIndex
    end

    local function pageIndexForTab(tab, requestedPage)
        local pageCount = methods.getTabPageCount(tab)
        local targetPage = tonumber(trim(requestedPage))
        if targetPage ~= nil then
            targetPage = math.floor(targetPage)
        end
        if targetPage == nil then
            targetPage = 1
        end
        if targetPage < 1 then
            targetPage = 1
        elseif targetPage > pageCount then
            targetPage = pageCount
        end
        return targetPage
    end

    function methods.clearPendingSettingsRoute()
        local pendingMode = trim(SKIN:GetVariable(PENDING_ROUTE_MODE_VARIABLE, ''))
        local pendingTab = trim(SKIN:GetVariable(PENDING_ROUTE_TAB_VARIABLE, ''))
        local pendingPage = trim(SKIN:GetVariable(PENDING_ROUTE_PAGE_VARIABLE, ''))
        setVariable(PENDING_ROUTE_MODE_VARIABLE, '')
        setVariable(PENDING_ROUTE_TAB_VARIABLE, '')
        setVariable(PENDING_ROUTE_PAGE_VARIABLE, '')
        if pendingMode ~= '' or pendingTab ~= '' or pendingPage ~= '' then
            methods.writeInternalStateVariable(PENDING_ROUTE_MODE_VARIABLE, '')
            methods.writeInternalStateVariable(PENDING_ROUTE_TAB_VARIABLE, '')
            methods.writeInternalStateVariable(PENDING_ROUTE_PAGE_VARIABLE, '')
        end
    end

    function methods.applyContentModeState(enabled, options)
        local nextEnabled = enabled == true
        local currentCount = visibleTabCount()
        if state.contentMode == true then
            state.contentTabIndex = math.max(1, math.min(state.currentTabIndex, currentCount))
        else
            state.normalTabIndex = math.max(1, math.min(state.currentTabIndex, currentCount))
        end

        state.contentMode = nextEnabled
        local nextTabs = visibleTabs()
        local nextIndex = nextEnabled and state.contentTabIndex or state.normalTabIndex
        nextIndex = math.max(1, math.min(tonumber(nextIndex) or 1, #nextTabs))
        state.currentTabIndex = nextIndex
        state.currentPageByTab[methods.activePageKey()] = 1

        local literal = nextEnabled and '1' or '0'
        setVariable('SettingsContentMode', literal)
        if not options or options.persist ~= false then
            methods.writeIniVariable(methods.statePath(), 'SettingsContentMode', literal)
        end
    end

    function methods.ToggleContentMode()
        if methods.isLoadingVisible() then
            if methods.CancelPendingLoad() == false then
                return
            end
            methods.clearPendingRefreshState()
        end

        methods.clearPendingConfirmation()
        methods.closeDropdownInternal()
        methods.applyContentModeState(state.contentMode ~= true)
        methods.renderActivePage()
    end

    local function applySettingsRoute(mode, tabIdOrIndex, pageId, options)
        options = options or {}
        local tabs, contentEnabled, normalizedMode = tabsForRouteMode(mode)
        if tabs == nil then
            logNotice('Settings route ignored because mode is invalid: ' .. tostring(normalizedMode or ''))
            return false
        end

        local targetIndex = tabIndexInList(tabs, tabIdOrIndex)
        if targetIndex == nil then
            logNotice('Settings route ignored because tab is invalid: mode=' .. tostring(normalizedMode or '') .. ' tab=' .. tostring(tabIdOrIndex or ''))
            return false
        end

        local targetPage = pageIndexForTab(tabs[targetIndex], pageId)

        if options.prepare ~= false then
            if methods.isLoadingVisible() then
                if methods.CancelPendingLoad() == false then
                    return false
                end
                methods.clearPendingRefreshState()
            end

            methods.clearPendingConfirmation()
            methods.closeDropdownInternal()
        end

        methods.applyContentModeState(contentEnabled)

        state.currentTabIndex = targetIndex
        if state.contentMode == true then
            state.contentTabIndex = targetIndex
        else
            state.normalTabIndex = targetIndex
        end
        state.currentPageByTab[methods.activePageKey()] = targetPage

        return true
    end

    function methods.OpenSettingsRoute(mode, tabIdOrIndex, pageId)
        if not applySettingsRoute(mode, tabIdOrIndex, pageId) then
            return false
        end

        methods.clearPendingSettingsRoute()
        methods.ResumeSettingsResident()
        return true
    end

    function methods.consumePendingSettingsRoute()
        local pendingMode = trim(SKIN:GetVariable(PENDING_ROUTE_MODE_VARIABLE, ''))
        local pendingTab = trim(SKIN:GetVariable(PENDING_ROUTE_TAB_VARIABLE, ''))
        local pendingPage = trim(SKIN:GetVariable(PENDING_ROUTE_PAGE_VARIABLE, ''))
        if pendingMode == '' and pendingTab == '' and pendingPage == '' then
            return false
        end

        methods.clearPendingSettingsRoute()
        if pendingMode == '' or pendingTab == '' then
            logNotice('Settings pending route ignored because the route was incomplete.')
            return false
        end

        return applySettingsRoute(pendingMode, pendingTab, pendingPage, { prepare = false })
    end

    function methods.SelectTab(tabIdOrIndex)

        local requested = trim(tabIdOrIndex)

        if requested == '' then
            return false
        end

        local targetIndex = tonumber(requested)

        if targetIndex ~= nil then
            targetIndex = math.floor(targetIndex)
        end

        if targetIndex == nil then

            for index, tab in ipairs(visibleTabs()) do

                if trim(tab and tab.id or '') == requested then

                    targetIndex = index

                    break

                end

            end

        end

        if targetIndex == nil or targetIndex < 1 or targetIndex > visibleTabCount() then
            return false
        end

        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return false

            end

            methods.clearPendingRefreshState()

        end

        methods.clearPendingConfirmation()

        methods.closeDropdownInternal()

        state.currentTabIndex = targetIndex
        if state.contentMode == true then
            state.contentTabIndex = targetIndex
        else
            state.normalTabIndex = targetIndex
        end

        state.currentPageByTab[methods.activePageKey()] = 1

        methods.renderActivePage()

        return true

    end





    function methods.PrevTab()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        methods.closeDropdownInternal()







        state.currentTabIndex = state.currentTabIndex - 1







        if state.currentTabIndex < 1 then







            state.currentTabIndex = visibleTabCount()







        end







        state.currentPageByTab[methods.activePageKey()] = 1
        if state.contentMode == true then
            state.contentTabIndex = state.currentTabIndex
        else
            state.normalTabIndex = state.currentTabIndex
        end







        methods.renderActivePage()







    end







    function methods.NextTab()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        methods.closeDropdownInternal()







        state.currentTabIndex = state.currentTabIndex + 1







        if state.currentTabIndex > visibleTabCount() then







            state.currentTabIndex = 1







        end







        state.currentPageByTab[methods.activePageKey()] = 1
        if state.contentMode == true then
            state.contentTabIndex = state.currentTabIndex
        else
            state.normalTabIndex = state.currentTabIndex
        end







        methods.renderActivePage()







    end







    function methods.PrevPage()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        local pageCount = methods.getTabPageCount(methods.activeTab())







        if pageCount <= 1 then







            return







        end







        methods.closeDropdownInternal()







        local nextPage = methods.activePageIndex() - 1







        if nextPage < 1 then







            nextPage = pageCount







        end







        state.currentPageByTab[methods.activePageKey()] = nextPage







        methods.renderActivePage()







    end







    function methods.NextPage()







        if methods.isLoadingVisible() then

            if methods.CancelPendingLoad() == false then

                return

            end

            methods.clearPendingRefreshState()

        end







        methods.clearPendingConfirmation()










        local pageCount = methods.getTabPageCount(methods.activeTab())







        if pageCount <= 1 then







            return







        end







        methods.closeDropdownInternal()







        local nextPage = methods.activePageIndex() + 1







        if nextPage > pageCount then







            nextPage = 1







        end







        state.currentPageByTab[methods.activePageKey()] = nextPage







        methods.renderActivePage()







    end
end
